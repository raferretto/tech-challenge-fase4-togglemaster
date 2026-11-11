#!/bin/bash
set -euo pipefail
# ==============================================================================
# FALHA CONTROLADA (experimento de Self-Healing)
# Cria o arquivo /tmp/togglemaster-force-503 nos pods do evaluation-service.
# Enquanto ele existir, /evaluate responde HTTP 503 e /health continua 200:
# a "falha silenciosa" que o Kubernetes não percebe.
# Uso: ./scripts/fase4/07-inject-failure.sh [all|one]   (padrão: all)
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need kubectl

MODE="${1:-all}"
mapfile -t PODS < <(kubectl -n "$APP_NS" get pods -l app=evaluation-service \
  --field-selector=status.phase=Running -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
[ "${#PODS[@]}" -gt 0 ] || fail "nenhum pod do evaluation-service em execução."
[ "$MODE" = "one" ] && PODS=("${PODS[0]}")

title "Injetando a falha em ${#PODS[@]} pod(s) - $(date '+%d/%m/%Y %H:%M:%S')"
for pod in "${PODS[@]}"; do
  kubectl -n "$APP_NS" exec "$pod" -- touch /tmp/togglemaster-force-503
  echo "  falha ativa em: $pod"
done

echo
echo "Pods ANTES do Self-Healing (anote os nomes para comparar depois):"
kubectl -n "$APP_NS" get pods -l app=evaluation-service -o wide
cat <<MSG

O que acompanhar agora (com a carga do 06-generate-load.sh rodando):
  1. Grafana > Alerting: a regra EvaluationServiceHighErrorRate passa a Pending e, após 2 min, a Firing
  2. PagerDuty: incidente aberto | Slack: notificação no canal
  3. Self-Healing:   kubectl -n ${OBS_NS} logs -f deployment/self-healing
  4. Pods novos:     kubectl -n ${APP_NS} get pods -l app=evaluation-service -w
MSG
