"""ToggleMaster - automação de Self-Healing (Fase 4).

Recebe o webhook do Grafana Alerting e, quando o alerta autorizado dispara,
reinicia o deployment afetado (equivalente a `kubectl rollout restart`),
acompanhando o rollout até as novas réplicas ficarem disponíveis.

Salvaguardas:
  - autenticidade: assinatura HMAC-SHA256 do Grafana + validade do horário;
  - escopo restrito: só uma regra de alerta e um deployment são aceitos;
  - idempotência: eventos resolvidos e ocorrências já tratadas são ignorados;
  - intervalo mínimo (cooldown) entre duas intervenções;
  - privilégio mínimo: a ServiceAccount só pode ler/atualizar o deployment alvo.
"""
import hashlib
import hmac
import logging
import os
import threading
import time
from datetime import datetime, timezone

import requests
from flask import Flask, jsonify, request

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s self-healing %(message)s")
log = logging.getLogger("self-healing")
logging.getLogger("werkzeug").setLevel(logging.WARNING)  # sem log de acesso do servidor HTTP

# --- Configuração ---
HMAC_SECRET = os.getenv("HMAC_SECRET", "")
SIGNATURE_HEADER = os.getenv("SIGNATURE_HEADER", "X-Grafana-Alerting-Signature")
TIMESTAMP_HEADER = os.getenv("TIMESTAMP_HEADER", "X-Grafana-Alerting-Signature-Timestamp")
MAX_TIMESTAMP_SKEW_SECONDS = int(os.getenv("MAX_TIMESTAMP_SKEW_SECONDS", "300"))

ALLOWED_ALERT_NAME = os.getenv("ALLOWED_ALERT_NAME", "EvaluationServiceHighErrorRate")
TARGET_NAMESPACE = os.getenv("TARGET_NAMESPACE", "togglemaster")
TARGET_DEPLOYMENT = os.getenv("TARGET_DEPLOYMENT", "evaluation-service")

COOLDOWN_SECONDS = int(os.getenv("COOLDOWN_SECONDS", "300"))
ROLLOUT_TIMEOUT_SECONDS = int(os.getenv("ROLLOUT_TIMEOUT_SECONDS", "240"))
DRY_RUN = os.getenv("DRY_RUN", "false").lower() == "true"

K8S_API = os.getenv("K8S_API", "https://kubernetes.default.svc")
SA_DIR = os.getenv("SA_DIR", "/var/run/secrets/kubernetes.io/serviceaccount")

app = Flask(__name__)

# Estado em memória (o serviço roda com uma única réplica)
_lock = threading.Lock()
_state = {"last_action_at": 0.0, "handled": set()}


# --- Verificação da assinatura do Grafana ---

def expected_signature(secret, timestamp, body):
    """HMAC-SHA256 em hexadecimal de "<timestamp>:<corpo>" (formato usado pelo Grafana)."""
    mac = hmac.new(secret.encode(), digestmod=hashlib.sha256)
    if timestamp:
        mac.update(timestamp.encode())
        mac.update(b":")
    mac.update(body)
    return mac.hexdigest()


def verify_request(headers, body, now=None):
    """Valida a assinatura HMAC e o horário do evento. Retorna (ok, motivo)."""
    if not HMAC_SECRET:
        return False, "HMAC_SECRET não configurado"
    signature = headers.get(SIGNATURE_HEADER, "")
    timestamp = headers.get(TIMESTAMP_HEADER, "")
    if not signature or not timestamp:
        return False, "assinatura ou horário ausentes"
    try:
        sent_at = int(timestamp)
    except ValueError:
        return False, "horário inválido"
    now = time.time() if now is None else now
    if abs(now - sent_at) > MAX_TIMESTAMP_SKEW_SECONDS:
        return False, "evento fora da janela de tempo aceita"
    if not hmac.compare_digest(signature, expected_signature(HMAC_SECRET, timestamp, body)):
        return False, "assinatura inválida"
    return True, "ok"


# --- API do Kubernetes (ServiceAccount do próprio pod) ---

def _k8s_session():
    with open(os.path.join(SA_DIR, "token"), encoding="utf-8") as handle:
        token = handle.read().strip()
    session = requests.Session()
    session.headers["Authorization"] = f"Bearer {token}"
    session.verify = os.path.join(SA_DIR, "ca.crt")
    return session


def _deployment_url():
    return f"{K8S_API}/apis/apps/v1/namespaces/{TARGET_NAMESPACE}/deployments/{TARGET_DEPLOYMENT}"


def restart_deployment(reason):
    """Altera uma anotação do modelo dos pods, o que inicia a substituição gradual das réplicas."""
    patch = {"spec": {"template": {"metadata": {"annotations": {
        "kubectl.kubernetes.io/restartedAt": datetime.now(timezone.utc).isoformat(),
        "togglemaster.io/self-healing-reason": reason,
    }}}}}
    response = _k8s_session().patch(
        _deployment_url(), json=patch, timeout=10,
        headers={"Content-Type": "application/strategic-merge-patch+json"},
    )
    response.raise_for_status()


def rollout_finished(deployment):
    """True quando todas as réplicas já são do novo modelo e estão disponíveis."""
    spec, status = deployment.get("spec", {}), deployment.get("status", {})
    desired = spec.get("replicas", 1)
    return (
        status.get("observedGeneration", 0) >= deployment.get("metadata", {}).get("generation", 0)
        and status.get("updatedReplicas", 0) == desired
        and status.get("replicas", 0) == desired
        and status.get("availableReplicas", 0) == desired
    )


def watch_rollout():
    """Acompanha o rollout e registra o resultado da ação corretiva."""
    started = time.time()
    target = f"{TARGET_NAMESPACE}/{TARGET_DEPLOYMENT}"
    while time.time() - started < ROLLOUT_TIMEOUT_SECONDS:
        time.sleep(5)
        try:
            response = _k8s_session().get(_deployment_url(), timeout=10)
            response.raise_for_status()
            deployment = response.json()
        except requests.RequestException as exc:
            log.warning("falha ao consultar o rollout de %s: %s", target, exc)
            continue
        status = deployment.get("status", {})
        log.info("rollout em andamento deployment=%s atualizadas=%s disponiveis=%s desejadas=%s",
                 target, status.get("updatedReplicas", 0), status.get("availableReplicas", 0),
                 deployment.get("spec", {}).get("replicas", 1))
        if rollout_finished(deployment):
            log.info("ACAO CORRETIVA CONCLUIDA deployment=%s duracao=%.0fs replicas_disponiveis=%s",
                     target, time.time() - started, status.get("availableReplicas", 0))
            return True
    log.error("ACAO CORRETIVA NAO CONFIRMADA deployment=%s: rollout não concluiu em %ss",
              target, ROLLOUT_TIMEOUT_SECONDS)
    return False


# --- Decisão ---

def decide(payload, now=None):
    """Decide o que fazer com a notificação. Retorna (acao, motivo, chave_da_ocorrencia)."""
    now = time.time() if now is None else now
    firing = [
        alert for alert in payload.get("alerts", [])
        if alert.get("status") == "firing" and alert.get("labels", {}).get("alertname") == ALLOWED_ALERT_NAME
    ]
    if not firing:
        return "ignored", "nenhum alerta autorizado em estado firing", None

    # uma ocorrência = o mesmo alerta (fingerprint) desde o mesmo início
    key = "|".join(sorted(f"{a.get('fingerprint', '')}@{a.get('startsAt', '')}" for a in firing))
    with _lock:
        if key in _state["handled"]:
            return "ignored", "ocorrência já tratada", key
        remaining = COOLDOWN_SECONDS - (now - _state["last_action_at"])
        if remaining > 0:
            return "ignored", f"intervalo mínimo entre intervenções ({remaining:.0f}s restantes)", key
        _state["handled"].add(key)
        _state["last_action_at"] = now
    return "restart", "alerta autorizado em estado firing", key


# --- Endpoints ---

@app.route("/health")
def health():
    return jsonify({"status": "ok"})


@app.route("/webhook/grafana", methods=["POST"])
def grafana_webhook():
    body = request.get_data()
    ok, reason = verify_request(request.headers, body)
    if not ok:
        log.warning("webhook REJEITADO: %s (origem=%s)", reason, request.remote_addr)
        return jsonify({"error": "requisição não autorizada", "reason": reason}), 401

    payload = request.get_json(silent=True) or {}
    alertnames = sorted({a.get("labels", {}).get("alertname", "?") for a in payload.get("alerts", [])})
    log.info("webhook recebido: assinatura HMAC válida status=%s alertas=%s", payload.get("status"), alertnames)

    action, reason, key = decide(payload)
    target = f"{TARGET_NAMESPACE}/{TARGET_DEPLOYMENT}"
    if action != "restart":
        log.info("nenhuma ação executada: %s", reason)
        return jsonify({"action": "ignored", "reason": reason}), 200

    if DRY_RUN:
        log.info("DRY_RUN: reinício de %s NÃO executado", target)
        return jsonify({"action": "dry_run", "deployment": target}), 200

    try:
        restart_deployment(f"alerta {ALLOWED_ALERT_NAME}")
    except (requests.RequestException, OSError) as exc:
        with _lock:  # libera nova tentativa na próxima notificação
            _state["handled"].discard(key)
            _state["last_action_at"] = 0.0
        log.error("FALHA ao reiniciar %s: %s", target, exc)
        return jsonify({"error": "falha ao acionar o Kubernetes"}), 502

    log.info("ACAO CORRETIVA INICIADA: rollout restart de deployment=%s motivo=%s", target, ALLOWED_ALERT_NAME)
    threading.Thread(target=watch_rollout, daemon=True).start()
    return jsonify({"action": "rollout_restart", "deployment": target}), 202


if __name__ == "__main__":
    if not HMAC_SECRET:
        log.critical("HMAC_SECRET deve ser definido")
        raise SystemExit(1)
    log.info("Self-Healing iniciado: alerta=%s alvo=%s/%s cooldown=%ss dry_run=%s",
             ALLOWED_ALERT_NAME, TARGET_NAMESPACE, TARGET_DEPLOYMENT, COOLDOWN_SECONDS, DRY_RUN)
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")), debug=False)  # nosec B104
