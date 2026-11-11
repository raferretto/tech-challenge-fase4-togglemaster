#!/bin/bash

# ==============================================================================
# Script de Demonstração de DevSecOps (Para gravação do vídeo do Tech Challenge)
# Permite simular a falha do pipeline no passo de segurança e depois corrigir!
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ACTION=${1:-"help"}
TARGET_FILE="$PROJECT_ROOT/services/flag-service/requirements.txt"
VULN_DEP="django==2.0" # Dependência antiga com múltiplas CVEs CRÍTICAS conhecidas (CVE-2019-19844, CVE-2020-7471)

case "$ACTION" in
    fail)
        echo ">> Injetando dependência vulnerável ($VULN_DEP) em $TARGET_FILE..."
        cp "$TARGET_FILE" "${TARGET_FILE}.bak"
        echo "$VULN_DEP" >> "$TARGET_FILE"
        echo "Alteração feita com sucesso!"
        echo "Agora faça o commit e push para a main/PR para ver o Trivy/GitHub Actions FALHAR no passo SCA:"
        echo "  git commit -am 'test: inject vulnerable dependency for devsecops demo' && git push"
        ;;
    fix)
        echo ">> Restaurando arquivo seguro..."
        if [ -f "${TARGET_FILE}.bak" ]; then
            mv "${TARGET_FILE}.bak" "$TARGET_FILE"
        else
            sed -i "/django==2.0/d" "$TARGET_FILE"
        fi
        echo "Dependência vulnerável removida!"
        echo "Agora faça o commit e push para ver o pipeline PASSAR com sucesso:"
        echo "  git commit -am 'fix: remove vulnerable dependency' && git push"
        ;;
    *)
        echo "Uso:"
        echo "  $0 fail  -> Injeta dependência vulnerável para demonstrar falha no DevSecOps"
        echo "  $0 fix   -> Remove a dependência vulnerável para demonstrar pipeline passando"
        ;;
esac
