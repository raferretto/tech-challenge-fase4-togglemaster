#!/bin/bash
# Funções comuns dos scripts da Fase 4 (carregado com `source`).

FASE4_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$FASE4_DIR/../.." && pwd)"
export PROJECT_ROOT

REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-togglemaster-cluster}"
APP_NS="togglemaster"
OBS_NS="observability"

info()  { echo ">> $*"; }
warn()  { echo "!! $*" >&2; }
fail()  { echo "ERRO: $*" >&2; exit 1; }
title() { echo; echo "=============================================================================="; echo "$*"; echo "=============================================================================="; }

need() {
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || fail "comando '$cmd' não encontrado. Instale-o e tente novamente."
  done
}

# Chave interna usada pelo evaluation-service para chamar flag/targeting (validada no auth-service)
service_api_key() {
  kubectl -n "$APP_NS" get secret auth-service-secret -o jsonpath='{.data.SERVICE_API_KEY}' | base64 -d
}

# Endereço público do Ingress NGINX (ELB)
ingress_host() {
  kubectl -n ingress-nginx get svc ingress-nginx-controller \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null
}
