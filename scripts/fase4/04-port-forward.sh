#!/bin/bash
set -euo pipefail
# ==============================================================================
# Abre o acesso local às interfaces de administração (não publicadas por Ingress):
#   Grafana     http://localhost:3000
#   Prometheus  http://localhost:9090
#   ArgoCD      http://localhost:8081
# Deixe este terminal aberto; Ctrl+C encerra os túneis.
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need kubectl

PIDS=()
cleanup() { for pid in "${PIDS[@]:-}"; do kill "$pid" 2>/dev/null || true; done; }
trap cleanup EXIT INT TERM

forward() { # namespace alvo portas
  kubectl -n "$1" port-forward "$2" "$3" >/dev/null 2>&1 &
  PIDS+=($!)
}

forward "$OBS_NS" svc/grafana 3000:80
forward "$OBS_NS" svc/prometheus-server 9090:80
forward argocd svc/argo-cd-argocd-server 8081:80

title "Túneis abertos (Ctrl+C para encerrar)"
echo "Grafana     http://localhost:3000   usuário: admin"
echo "            senha: $(kubectl -n "$OBS_NS" get secret grafana-admin -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d)"
echo "            dashboard: http://localhost:3000/d/togglemaster-overview"
echo "Prometheus  http://localhost:9090"
echo "ArgoCD      http://localhost:8081   usuário: admin"
echo "            senha: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)"
wait
