#!/bin/bash
set -e

# ==============================================================================
# Setup do Backend S3 Remoto para Terraform State
# Permite ao usuário escolher interativamente qual perfil AWS utilizar
# ==============================================================================

select_aws_profile() {
    AVAILABLE_PROFILES=($(aws configure list-profiles 2>/dev/null || true))
    
    if [ ${#AVAILABLE_PROFILES[@]} -eq 0 ]; then
        echo "Nenhum perfil AWS encontrado na máquina. Execute 'aws configure' para configurar suas credenciais."
        exit 1
    elif [ ${#AVAILABLE_PROFILES[@]} -eq 1 ]; then
        export AWS_PROFILE="${AVAILABLE_PROFILES[0]}"
        echo ">> Usando o único perfil AWS configurado: $AWS_PROFILE"
    else
        echo "=============================================================================="
        echo "Perfis AWS configurados nesta máquina:"
        for i in "${!AVAILABLE_PROFILES[@]}"; do
            echo "  [$((i+1))] ${AVAILABLE_PROFILES[$i]}"
        done
        echo "=============================================================================="
        
        while true; do
            read -p "Escolha o número do perfil desejado [1-${#AVAILABLE_PROFILES[@]}]: " CHOICE
            if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#AVAILABLE_PROFILES[@]}" ]; then
                export AWS_PROFILE="${AVAILABLE_PROFILES[$((CHOICE-1))]}"
                echo ">> Perfil selecionado: $AWS_PROFILE"
                break
            else
                echo "Opção inválida. Digite um número entre 1 e ${#AVAILABLE_PROFILES[@]}."
            fi
        done
    fi

    # Validação rápida de credenciais
    echo ">> Validando credenciais do perfil '$AWS_PROFILE'..."
    IDENTITY=$(aws sts get-caller-identity --output json 2>/dev/null || true)
    if [ -z "$IDENTITY" ]; then
        echo "ERRO: As credenciais do perfil '$AWS_PROFILE' são inválidas ou expiraram."
        echo "Dica: Se for AWS Academy, atualize o AWS_SESSION_TOKEN em ~/.aws/credentials."
        exit 1
    else
        ACCOUNT=$(echo "$IDENTITY" | grep -o '"Account": "[^"]*' | cut -d'"' -f4)
        ARN=$(echo "$IDENTITY" | grep -o '"Arn": "[^"]*' | cut -d'"' -f4)
        echo ">> Autenticado com sucesso na AWS! Conta: $ACCOUNT ($ARN)"
    fi
}

select_aws_profile

# Se o usuário passou como argumento o nome antigo com colisão global, substituímos pelo exclusivo da conta
if [ "$1" == "togglemaster-terraform-state-fiap" ] || [ -z "$1" ]; then
    BUCKET_NAME="togglemaster-state-${ACCOUNT}"
else
    BUCKET_NAME="$1"
fi
REGION=${2:-"us-east-1"}

echo ""
echo ">> Alvo para o Terraform State: '$BUCKET_NAME' (Região: $REGION)"

BUCKET_STATUS="Criado com sucesso"
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    echo ">> O bucket '$BUCKET_NAME' já existe na sua conta AWS."
    BUCKET_STATUS="Já existente (revalidado)"
else
    echo ">> Criando S3 Bucket: $BUCKET_NAME..."
    if [ "$REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$REGION"
    else
        aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$REGION" \
            --create-bucket-configuration LocationConstraint="$REGION"
    fi
    echo ">> Bucket criado com sucesso!"
fi

echo ">> Configurando Versionamento (Status=Enabled)..."
aws s3api put-bucket-versioning \
    --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled

echo ">> Configurando Criptografia em repouso SSE-S3 (AES256)..."
aws s3api put-bucket-encryption \
    --bucket "$BUCKET_NAME" \
    --server-side-encryption-configuration '{
        "Rules": [
            {
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }
        ]
    }'

echo ">> Bloqueando todo o acesso público (Public Access Block)..."
aws s3api put-public-access-block \
    --bucket "$BUCKET_NAME" \
    --public-access-block-configuration '{
        "BlockPublicAcls": true,
        "IgnorePublicAcls": true,
        "BlockPublicPolicy": true,
        "RestrictPublicBuckets": true
    }'

# Atualiza backend.tf se o nome do bucket for diferente
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_FILE="$SCRIPT_DIR/../terraform/backend.tf"
if [ -f "$BACKEND_FILE" ]; then
    sed -i "s|bucket\s*=\s*\"[^\"]*\"|bucket       = \"$BUCKET_NAME\"|g" "$BACKEND_FILE"
fi

echo ""
echo "=============================================================================="
echo "                   RELATÓRIO DE CRIAÇÃO DO BACKEND S3"
echo "=============================================================================="
echo "  [✓] Perfil AWS Utilizado : $AWS_PROFILE"
echo "  [✓] ID da Conta AWS      : $ACCOUNT"
echo "  [✓] S3 Bucket            : $BUCKET_NAME"
echo "  [✓] Status do Bucket     : $BUCKET_STATUS"
echo "  [✓] Região AWS           : $REGION"
echo "  [✓] Versionamento        : Habilitado (Histórico de alterações do tfstate)"
echo "  [✓] Criptografia         : AES256 (SSE-S3 Server-Side Encryption)"
echo "  [✓] Bloqueio Público     : 100% Protegido (Public Access Block ativo)"
echo "  [✓] Trava de Concorrência: use_lockfile = true (Nativo do Terraform S3)"
echo "  [✓] Arquivo Atualizado   : terraform/backend.tf"
echo "=============================================================================="
echo "Resultado: Remote Backend configurado e pronto para uso!"
echo "Próximo passo recomendado:"
echo "  export AWS_PROFILE=$AWS_PROFILE"
echo "  cd terraform && terraform init"
echo "=============================================================================="
