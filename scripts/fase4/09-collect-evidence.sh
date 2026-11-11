#!/bin/bash
set -euo pipefail
# ==============================================================================
# Salva em evidencias/<data-hora>/ as saídas de texto úteis para o relatório:
# estado do cluster, Applications do ArgoCD, pods, log do Self-Healing e a
# configuração dos pipelines do OpenTelemetry Collector.
# (Os prints de tela do Grafana, New Relic, PagerDuty e Slack são manuais.)
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need kubectl

DIR="$PROJECT_ROOT/evidencias/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$DIR"
run() { local file="$1"; shift; { echo "\$ $*"; "$@" 2>&1 || true; } > "$DIR/$file"; echo "  $file"; }

title "Coletando evidências em $DIR"
run 01-nodes.txt                kubectl get nodes -o wide
run 02-argocd-applications.txt  kubectl -n argocd get applications.argoproj.io
run 03-pods-observability.txt   kubectl -n "$OBS_NS" get pods -o wide
run 04-pods-togglemaster.txt    kubectl -n "$APP_NS" get pods -o wide
run 05-hpa-keda.txt             kubectl -n "$APP_NS" get hpa,scaledobject
run 06-otel-gateway-config.txt  kubectl -n "$OBS_NS" get configmap otel-collector-gateway-config -o jsonpath='{.data.config\.yaml}'
run 07-otel-gateway-logs.txt    kubectl -n "$OBS_NS" logs deployment/otel-collector-gateway --tail=80
run 08-self-healing-logs.txt    kubectl -n "$OBS_NS" logs deployment/self-healing --tail=200
run 09-evaluation-rollout.txt   kubectl -n "$APP_NS" rollout history deployment/evaluation-service
run 10-evaluation-describe.txt  kubectl -n "$APP_NS" describe deployment evaluation-service
run 11-events-togglemaster.txt  kubectl -n "$APP_NS" get events --sort-by=.lastTimestamp
info "pronto."
