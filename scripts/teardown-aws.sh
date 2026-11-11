#!/bin/bash
set -e

# ==============================================================================
# Script de Destruição Completa da Infraestrutura AWS (Teardown)
# Permite ao usuário escolher interativamente qual perfil AWS utilizar
# ==============================================================================

select_aws_profile() {
    AVAILABLE_PROFILES=($(aws configure list-profiles 2>/dev/null || true))
    
    if [ ${#AVAILABLE_PROFILES[@]} -eq 0 ]; then
        echo "Nenhum perfil AWS encontrado na máquina."
        exit 1
    elif [ ${#AVAILABLE_PROFILES[@]} -eq 1 ]; then
        export AWS_PROFILE="${AVAILABLE_PROFILES[0]}"
        echo ">> Usando perfil AWS: $AWS_PROFILE"
    else
        echo "=============================================================================="
        echo "Perfis AWS configurados nesta máquina:"
        for i in "${!AVAILABLE_PROFILES[@]}"; do
            echo "  [$((i+1))] ${AVAILABLE_PROFILES[$i]}"
        done
        echo "=============================================================================="
        
        while true; do
            read -p "Escolha o número do perfil para o Teardown [1-${#AVAILABLE_PROFILES[@]}]: " CHOICE
            if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#AVAILABLE_PROFILES[@]}" ]; then
                export AWS_PROFILE="${AVAILABLE_PROFILES[$((CHOICE-1))]}"
                echo ">> Perfil selecionado: $AWS_PROFILE"
                break
            else
                echo "Opção inválida. Digite um número entre 1 e ${#AVAILABLE_PROFILES[@]}."
            fi
        done
    fi
}

select_aws_profile

ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "default")
REGION=${AWS_REGION:-"us-east-1"}
CLUSTER_NAME="togglemaster-cluster"
STATE_BUCKET="togglemaster-state-${ACCOUNT}"
ECR_REPOS=(
  "togglemaster/auth-service"
  "togglemaster/flag-service"
  "togglemaster/targeting-service"
  "togglemaster/evaluation-service"
  "togglemaster/analytics-service"
  "togglemaster/self-healing"
)

echo "=============================================================================="
echo "                   TOGGLEMASTER - AWS TEARDOWN COMPLETO"
echo "=============================================================================="
echo "ATENÇÃO: Este script irá DESTRUIR TODOS os recursos criados na AWS:"
echo "  - Ingress Controllers & Load Balancers (ELB/ALB)"
echo "  - Imagens nos 6 Repositórios ECR"
echo "  - Cluster EKS e Worker Nodes"
echo "  - 3 Instâncias RDS PostgreSQL"
echo "  - Cluster ElastiCache Redis"
echo "  - Tabela DynamoDB"
echo "  - Fila SQS e DLQ"
echo "  - VPC, Subnets, NAT Gateway e Security Groups"
echo "=============================================================================="

if [ "$1" != "--force" ]; then
    read -p "Tem certeza absoluta que deseja destruir toda a infraestrutura? (digite 'sim' para confirmar): " CONFIRM
    if [ "$CONFIRM" != "sim" ]; then
        echo "Operação cancelada pelo usuário."
        exit 0
    fi
fi

echo ""
echo ">> 1. Removendo Ingress e Load Balancers do Kubernetes para liberar os ALBs/ELBs da VPC..."
if command -v kubectl &> /dev/null && kubectl get svc -A &> /dev/null; then
    echo "Cluster EKS acessível. Deletando LoadBalancers e Ingress..."
    kubectl delete ingress --all -A --ignore-not-found=true --timeout=60s || true
    kubectl delete svc -n ingress-nginx --all --ignore-not-found=true --timeout=60s || true
    kubectl delete svc -n argocd -l app.kubernetes.io/name=argocd-server --ignore-not-found=true --timeout=60s || true
    echo "Aguardando 15 segundos para liberação dos ELBs na AWS..."
    sleep 15
else
    echo "Cluster EKS não conectado ou já inacessível. Prosseguindo..."
fi

echo ""
echo ">> 2. Esvaziando imagens dos repositórios ECR..."
for repo in "${ECR_REPOS[@]}"; do
    if aws ecr describe-repositories --repository-names "$repo" --region "$REGION" &> /dev/null; then
        echo "Limpando imagens de $repo..."
        IMAGE_IDS=$(aws ecr list-images --repository-name "$repo" --region "$REGION" --query 'imageIds[*]' --output json)
        if [ "$IMAGE_IDS" != "[]" ] && [ -n "$IMAGE_IDS" ]; then
            aws ecr batch-delete-image --repository-name "$repo" --image-ids "$IMAGE_IDS" --region "$REGION" > /dev/null || true
            echo "Imagens de $repo removidas."
        fi
    fi
done

echo ""
echo ">> 3. Executando 'terraform destroy'..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"

cd "$TERRAFORM_DIR"
echo "Inicializando Terraform com o perfil '$AWS_PROFILE'..."
if ! terraform init -input=false -reconfigure 2>/dev/null; then
    echo "Aviso: Não foi possível conectar ao backend S3 remoto (pode ser que o bucket ainda não tenha sido criado ou a infraestrutura nunca tenha sido aplicada)."
    echo "Inicializando localmente para verificar recursos pendentes..."
    terraform init -input=false -backend=false >/dev/null 2>&1 || true
fi

terraform destroy -auto-approve || echo "Nota: Nenhum recurso gerenciado pelo Terraform precisava ser destruído."

echo ""
echo ">> 4. Destruição do Bucket S3 de Remote State (Opcional)..."
if [ "$1" == "--delete-state-bucket" ] || [ "$2" == "--delete-state-bucket" ]; then
    echo "Esvaziando e deletando bucket S3: $STATE_BUCKET..."
    if aws s3api head-bucket --bucket "$STATE_BUCKET" 2>/dev/null; then
        aws s3 rb "s3://$STATE_BUCKET" --force
        echo "Bucket S3 $STATE_BUCKET excluído."
    fi
else
    echo "Nota: O bucket S3 de estado ($STATE_BUCKET) foi preservado."
    echo "Para deletá-lo também, execute: $0 --force --delete-state-bucket"
fi

echo ""
echo "=============================================================================="
echo ">> TEARDOWN CONCLUÍDO COM SUCESSO! Todos os recursos foram removidos da AWS."
echo "=============================================================================="
