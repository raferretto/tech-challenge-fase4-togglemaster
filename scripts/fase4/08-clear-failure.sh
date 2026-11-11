#!/bin/bash
set -euo pipefail
# ==============================================================================
# Remove manualmente a falha controlada (plano B, caso não queira esperar o
# Self-Healing). Os pods novos criados pelo rollout já nascem sem o arquivo.
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need kubectl

for pod in $(kubectl -n "$APP_NS" get pods -l app=evaluation-service \
  --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}'); do
  kubectl -n "$APP_NS" exec "$pod" -- rm -f /tmp/togglemaster-force-503
  echo "  falha removida de: $pod"
done
