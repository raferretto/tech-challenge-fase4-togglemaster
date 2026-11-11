#!/bin/bash
set -e

# ==============================================================================
# Execução Local de Testes e Scans DevSecOps (WSL Ubuntu)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=================================================="
echo "1. Rodando Testes Unitários Go"
echo "=================================================="
cd "$PROJECT_ROOT/services/auth-service" && go test -v ./...
cd "$PROJECT_ROOT/services/evaluation-service" && go test -v ./...

echo "=================================================="
echo "2. Rodando Testes Unitários Python"
echo "=================================================="
cd "$PROJECT_ROOT"
python3 -m unittest discover -s services/flag-service -p 'test_*.py'
python3 -m unittest discover -s services/targeting-service -p 'test_*.py'
python3 -m unittest discover -s services/analytics-service -p 'test_*.py'
python3 -m unittest discover -s services/self-healing -p 'test_*.py'

echo "=================================================="
echo "3. Validando Terraform Syntax e Módulos"
echo "=================================================="
cd "$PROJECT_ROOT/terraform"
terraform fmt -check -recursive
terraform validate
cd "$PROJECT_ROOT"

echo "=================================================="
echo "Todos os testes e validações locais passaram!"
echo "=================================================="
