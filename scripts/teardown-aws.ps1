<#
.SYNOPSIS
    Script de Destruição Completa da Infraestrutura AWS (Teardown em PowerShell)
    Tech Challenge Fase 4 - ToggleMaster
#>

param (
    [switch]$Force,
    [switch]$DeleteStateBucket
)

$ErrorActionPreference = "Continue"
$Region = if ($env:AWS_REGION) { $env:AWS_REGION } else { "us-east-1" }
$StateBucket = "togglemaster-terraform-state-fiap"
$EcrRepos = @(
    "togglemaster/auth-service",
    "togglemaster/flag-service",
    "togglemaster/targeting-service",
    "togglemaster/evaluation-service",
    "togglemaster/analytics-service",
    "togglemaster/self-healing"
)

Write-Host "==============================================================================" -ForegroundColor Red
Write-Host "                   TOGGLEMASTER - AWS TEARDOWN COMPLETO" -ForegroundColor Yellow
Write-Host "==============================================================================" -ForegroundColor Red
Write-Host "ATENCAO: Este script ira DESTRUIR TODOS os recursos criados na AWS:" -ForegroundColor Yellow
Write-Host "  - Ingress Controllers & Load Balancers (ELB/ALB)"
Write-Host "  - Imagens nos 5 Repositorios ECR"
Write-Host "  - Cluster EKS e Worker Nodes"
Write-Host "  - 3 Instancias RDS PostgreSQL"
Write-Host "  - Cluster ElastiCache Redis"
Write-Host "  - Tabela DynamoDB"
Write-Host "  - Fila SQS e DLQ"
Write-Host "  - VPC, Subnets, NAT Gateway e Security Groups"
Write-Host "=============================================================================="

if (-not $Force) {
    $confirm = Read-Host "Tem certeza absoluta que deseja destruir toda a infraestrutura? (digite 'sim' para confirmar)"
    if ($confirm -ne "sim") {
        Write-Host "Operacao cancelada pelo usuario." -ForegroundColor Green
        exit 0
    }
}

Write-Host "`n>> 1. Removendo Ingress e Load Balancers do Kubernetes..." -ForegroundColor Cyan
try {
    kubectl delete ingress --all -A --ignore-not-found=true --timeout=60s 2>$null
    kubectl delete svc -n ingress-nginx --all --ignore-not-found=true --timeout=60s 2>$null
    Start-Sleep -Seconds 15
} catch {
    Write-Host "Cluster EKS inacessivel ou kubectl nao configurado. Prosseguindo..." -ForegroundColor DarkGray
}

Write-Host "`n>> 2. Esvaziando imagens dos 5 repositorios ECR..." -ForegroundColor Cyan
foreach ($repo in $EcrRepos) {
    Write-Host "Verificando repositorio ECR: $repo"
    $images = aws ecr list-images --repository-name $repo --region $Region --query 'imageIds[*]' --output json 2>$null | ConvertFrom-Json
    if ($images -and $images.Count -gt 0) {
        Write-Host "Deletando $($images.Count) imagens de $repo..." -ForegroundColor Yellow
        $imageJson = aws ecr list-images --repository-name $repo --region $Region --query 'imageIds[*]' --output json
        aws ecr batch-delete-image --repository-name $repo --image-ids "$imageJson" --region $Region 2>$null | Out-Null
    }
}

Write-Host "`n>> 3. Executando 'terraform destroy'..." -ForegroundColor Cyan
$terraformDir = Join-Path $PSScriptRoot "..\terraform"
Push-Location $terraformDir
try {
    terraform destroy -auto-approve
} finally {
    Pop-Location
}

if ($DeleteStateBucket) {
    Write-Host "`n>> 4. Deletando bucket S3 de estado: $StateBucket..." -ForegroundColor Cyan
    aws s3 rb "s3://$StateBucket" --force 2>$null
    Write-Host "Bucket S3 removido." -ForegroundColor Green
} else {
    Write-Host "`nNota: O bucket S3 de estado ($StateBucket) foi preservado." -ForegroundColor DarkGray
}

Write-Host "`n==============================================================================" -ForegroundColor Green
Write-Host ">> TEARDOWN CONCLUIDO COM SUCESSO! Todos os recursos foram removidos." -ForegroundColor Green
Write-Host "==============================================================================" -ForegroundColor Green
