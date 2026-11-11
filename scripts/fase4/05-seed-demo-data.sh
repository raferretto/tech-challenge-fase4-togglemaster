#!/bin/bash
set -euo pipefail
# ==============================================================================
# Cria os dados de demonstração: a flag "checkout_v2" (habilitada) e a regra de
# segmentação de 50%. Em seguida faz uma avaliação de teste.
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need kubectl curl

FLAG="${FLAG_NAME:-checkout_v2}"
KEY="$(service_api_key)"
[ -n "$KEY" ] || fail "não foi possível ler a chave interna (secret auth-service-secret)."

PIDS=()
cleanup() { for pid in "${PIDS[@]:-}"; do kill "$pid" 2>/dev/null || true; done; }
trap cleanup EXIT
kubectl -n "$APP_NS" port-forward svc/flag-service 18002:8002 >/dev/null 2>&1 & PIDS+=($!)
kubectl -n "$APP_NS" port-forward svc/targeting-service 18003:8003 >/dev/null 2>&1 & PIDS+=($!)
kubectl -n "$APP_NS" port-forward svc/evaluation-service 18004:8004 >/dev/null 2>&1 & PIDS+=($!)
sleep 4

title "Criando a flag '${FLAG}'"
curl -s -X POST http://localhost:18002/flags -H "Authorization: Bearer ${KEY}" -H "Content-Type: application/json" \
  -d "{\"name\":\"${FLAG}\",\"description\":\"Novo checkout (demonstração Fase 4)\",\"is_enabled\":true}"; echo

title "Criando a regra de segmentação (50% dos usuários)"
curl -s -X POST http://localhost:18003/rules -H "Authorization: Bearer ${KEY}" -H "Content-Type: application/json" \
  -d "{\"flag_name\":\"${FLAG}\",\"is_enabled\":true,\"rules\":{\"type\":\"PERCENTAGE\",\"value\":50}}"; echo

title "Avaliação de teste"
for user in user-1 user-2 user-3; do
  curl -s "http://localhost:18004/evaluate?user_id=${user}&flag_name=${FLAG}"; echo
done
echo
info "(respostas 409 nos dois primeiros passos significam que os dados já existiam)"
