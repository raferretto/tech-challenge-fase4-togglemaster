#!/bin/bash
set -euo pipefail
# ==============================================================================
# Prepara o cluster depois do `terraform apply`:
#   1. configura o kubectl
#   2. instala o KEDA (autoscaling do analytics-service pela fila SQS)
#   3. registra as Applications do ArgoCD (microsserviços + observabilidade)
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need aws kubectl

KEDA_VERSION="${KEDA_VERSION:-2.14.0}"

title "1/3 Configurando o kubectl para o cluster ${CLUSTER_NAME}"
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"
kubectl get nodes

title "2/3 Instalando o KEDA ${KEDA_VERSION}"
kubectl apply --server-side --force-conflicts \
  -f "https://github.com/kedacore/keda/releases/download/v${KEDA_VERSION}/keda-${KEDA_VERSION}.yaml" | tail -5

title "3/3 Registrando as Applications no ArgoCD"
kubectl -n argocd rollout status deployment/argo-cd-argocd-server --timeout=180s || warn "o ArgoCD ainda não está pronto; seguindo."
kubectl apply -f "$PROJECT_ROOT/gitops/argocd-apps/root-application.yaml"
kubectl apply -f "$PROJECT_ROOT/gitops/argocd-apps/observability-applications.yaml"

title "Cluster preparado"
echo "Applications:"
kubectl -n argocd get applications.argoproj.io 2>/dev/null || true
echo
echo "Senha inicial do ArgoCD (usuário admin):"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d; echo
echo "URL do ArgoCD (LoadBalancer):"
kubectl -n argocd get svc argo-cd-argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null; echo
echo
info "Próximo passo: ./scripts/fase4/02-create-observability-secrets.sh"
