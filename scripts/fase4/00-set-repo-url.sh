#!/bin/bash
set -euo pipefail
# ==============================================================================
# Aponta o GitOps (Applications do ArgoCD e links) para o SEU repositório GitHub.
# Uso: ./scripts/fase4/00-set-repo-url.sh https://github.com/<usuario>/<repositorio>
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

URL="${1:-}"
[ -n "$URL" ] || fail "informe a URL do repositório. Ex.: $0 https://github.com/usuario/tech-challenge-fase4-togglemaster"
URL="${URL%.git}"
URL="${URL%/}"
[[ "$URL" =~ ^https://github\.com/[^/]+/[^/]+$ ]] || fail "URL inválida: $URL (esperado https://github.com/<usuario>/<repositorio>)"

cd "$PROJECT_ROOT"
FILES=(
  gitops/argocd-apps/root-application.yaml
  gitops/argocd-apps/observability-applications.yaml
  gitops/observability/values/grafana-values.yaml
)
for f in "${FILES[@]}"; do
  # repoURL das Applications que apontam para o GitHub (os charts Helm não são alterados)
  # e links de documentação (runbook) nas anotações do alerta
  sed -i -E "s#(repoURL: )https://github\.com/[^[:space:]]+\.git#\1${URL}.git#g; \
             s#https://github\.com/[^/[:space:]]+/[^/[:space:]]+/blob/#${URL}/blob/#g" "$f"
done

title "Repositório GitOps configurado: ${URL}.git"
grep -n "repoURL: https://github.com" gitops/argocd-apps/*.yaml | sed 's/^/  /'
echo
info "Faça o commit dessas alterações junto com as do passo seguinte."
