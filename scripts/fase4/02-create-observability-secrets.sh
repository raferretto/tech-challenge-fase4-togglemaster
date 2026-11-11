#!/bin/bash
set -euo pipefail
# ==============================================================================
# Cria no cluster os Secrets da stack de observabilidade (NÃO ficam no Git):
#   observability/newrelic-otlp             -> chave de ingestão do New Relic (traces)
#   observability/grafana-alerting-secrets  -> PagerDuty, Slack e segredo HMAC do Self-Healing
#   observability/grafana-admin             -> usuário e senha do Grafana
#
# Os valores podem vir de variáveis de ambiente ou são perguntados na hora:
#   NEW_RELIC_LICENSE_KEY      chave "INGEST - LICENSE" da conta New Relic
#   NEW_RELIC_OTLP_ENDPOINT    padrão https://otlp.nr-data.net (EUA); contas da UE: https://otlp.eu01.nr-data.net
#   PAGERDUTY_INTEGRATION_KEY  Integration Key (Events API v2) do serviço no PagerDuty
#   SLACK_WEBHOOK_URL          URL do Incoming Webhook do canal do Slack
#   GRAFANA_ADMIN_PASSWORD     opcional (gerada se não informada)
#   SELF_HEALING_HMAC_SECRET   opcional (gerado se não informado)
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need kubectl openssl

ask() { # ask VAR "pergunta"
  local var="$1" prompt="$2" value="${!1:-}"
  while [ -z "$value" ]; do
    read -r -s -p "$prompt: " value; echo
    [ -n "$value" ] || warn "valor obrigatório."
  done
  printf -v "$var" '%s' "$value"
}

title "Segredos da stack de observabilidade (namespace ${OBS_NS})"
ask NEW_RELIC_LICENSE_KEY     "Chave de ingestão do New Relic (INGEST - LICENSE)"
ask PAGERDUTY_INTEGRATION_KEY "Integration Key do PagerDuty (Events API v2)"
ask SLACK_WEBHOOK_URL         "URL do Incoming Webhook do Slack"

NEW_RELIC_OTLP_ENDPOINT="${NEW_RELIC_OTLP_ENDPOINT:-https://otlp.nr-data.net}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-$(openssl rand -base64 18 | tr -d '/+=')}"
SELF_HEALING_HMAC_SECRET="${SELF_HEALING_HMAC_SECRET:-$(openssl rand -hex 32)}"

[[ "$SLACK_WEBHOOK_URL" =~ ^https://hooks\.slack\.com/ ]] || warn "a URL do Slack não começa com https://hooks.slack.com/ - confira."
[ "${#PAGERDUTY_INTEGRATION_KEY}" -eq 32 ] || warn "a Integration Key do PagerDuty costuma ter 32 caracteres - confira."

kubectl get namespace "$OBS_NS" >/dev/null 2>&1 || kubectl create namespace "$OBS_NS"

apply_secret() { # nome chave=valor...
  local name="$1"; shift
  local args=()
  for kv in "$@"; do args+=(--from-literal="$kv"); done
  kubectl -n "$OBS_NS" create secret generic "$name" "${args[@]}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  info "secret ${OBS_NS}/${name} aplicado"
}

apply_secret newrelic-otlp \
  "NEW_RELIC_LICENSE_KEY=${NEW_RELIC_LICENSE_KEY}" \
  "NEW_RELIC_OTLP_ENDPOINT=${NEW_RELIC_OTLP_ENDPOINT}"

apply_secret grafana-alerting-secrets \
  "PAGERDUTY_INTEGRATION_KEY=${PAGERDUTY_INTEGRATION_KEY}" \
  "SLACK_WEBHOOK_URL=${SLACK_WEBHOOK_URL}" \
  "SELF_HEALING_HMAC_SECRET=${SELF_HEALING_HMAC_SECRET}"

apply_secret grafana-admin \
  "admin-user=admin" \
  "admin-password=${GRAFANA_ADMIN_PASSWORD}"

# Pods que leem esses segredos por variável de ambiente só os enxergam ao reiniciar
for target in deployment/grafana deployment/self-healing deployment/otel-collector-gateway; do
  if kubectl -n "$OBS_NS" get "$target" >/dev/null 2>&1; then
    kubectl -n "$OBS_NS" rollout restart "$target" >/dev/null && info "reiniciado ${target} para carregar os segredos"
  fi
done

title "Segredos criados"
echo "Grafana -> usuário: admin | senha: ${GRAFANA_ADMIN_PASSWORD}"
echo "(para recuperar depois: kubectl -n ${OBS_NS} get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d)"
