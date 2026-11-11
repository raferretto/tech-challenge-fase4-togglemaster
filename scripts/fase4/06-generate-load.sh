#!/bin/bash
set -euo pipefail
# ==============================================================================
# Gera tráfego contínuo no evaluation-service através do Ingress (ELB), o que
# distribui as requisições entre todos os pods.
# Uso: ./scripts/fase4/06-generate-load.sh [requisicoes_por_segundo] [duracao_em_segundos]
#      padrão: 5 req/s por 900 s (15 min). Ctrl+C encerra.
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need kubectl curl

RPS="${1:-5}"
DURATION="${2:-900}"
FLAG="${FLAG_NAME:-checkout_v2}"

HOST="${EVAL_BASE_URL:-}"
if [ -z "$HOST" ]; then
  ELB="$(ingress_host)"
  [ -n "$ELB" ] || fail "endereço do Ingress não encontrado. Informe EVAL_BASE_URL=http://host/eval"
  HOST="http://${ELB}/eval"
fi

title "Carga: ${RPS} req/s por ${DURATION}s em ${HOST}/evaluate"
INTERVAL="$(python3 -c "print(1/${RPS})" 2>/dev/null || echo 0.2)"
END=$(( $(date +%s) + DURATION ))
declare -A COUNT=()
LAST=$(date +%s)
i=0
while [ "$(date +%s)" -lt "$END" ]; do
  i=$((i + 1))
  code="$(curl -s -o /dev/null -m 5 -w '%{http_code}' "${HOST}/evaluate?user_id=user-$((i % 500))&flag_name=${FLAG}" || echo 000)"
  COUNT[$code]=$(( ${COUNT[$code]:-0} + 1 ))
  now=$(date +%s)
  if [ $((now - LAST)) -ge 10 ]; then
    summary=""
    for c in $(echo "${!COUNT[@]}" | tr ' ' '\n' | sort); do summary+=" HTTP ${c}: ${COUNT[$c]} |"; done
    echo "$(date +%H:%M:%S) últimos 10s ->${summary}"
    COUNT=()
    LAST=$now
  fi
  sleep "$INTERVAL"
done
info "carga encerrada."
