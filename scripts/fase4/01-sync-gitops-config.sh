#!/bin/bash
set -euo pipefail
# ==============================================================================
# Sincroniza os manifestos GitOps com a infraestrutura criada pelo Terraform:
#   - gitops/apps/base/secrets.yaml  (endpoints RDS/Redis, URL da fila SQS)
#   - gitops/apps/base/keda.yaml     (URL da fila SQS)
#   - gitops/apps/base/configmap.yaml (região)
#   - imagens dos deployments (conta/região do ECR)
#
# Executar DEPOIS do `terraform apply` e ANTES do push para o GitHub.
# Variáveis opcionais: DB_PASSWORD (senha dos bancos; padrão: a do terraform.tfvars)
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need aws terraform python3

cd "$PROJECT_ROOT"
title "Lendo os outputs do Terraform"
TF_OUT="$(terraform -chdir=terraform output -json)"
[ "$TF_OUT" != "{}" ] || fail "o Terraform não retornou outputs. Rode 'terraform apply' antes."

ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
if [ -z "${DB_PASSWORD:-}" ] && [ -f terraform/terraform.tfvars ]; then
  DB_PASSWORD="$(sed -n 's/^db_password[[:space:]]*=[[:space:]]*"\(.*\)"/\1/p' terraform/terraform.tfvars | head -1)"
fi
DB_PASSWORD="${DB_PASSWORD:-ToggleMaster123}"

export TF_OUT ACCOUNT REGION DB_PASSWORD
python3 - <<'PY'
import json, os, re, glob

out = {k: v["value"] for k, v in json.loads(os.environ["TF_OUT"]).items()}
account, region, password = os.environ["ACCOUNT"], os.environ["REGION"], os.environ["DB_PASSWORD"]

secrets_path = "gitops/apps/base/secrets.yaml"
current = open(secrets_path, encoding="utf-8").read()

def current_value(key, default):
    m = re.search(r'%s: "([^"]+)"' % key, current)
    return m.group(1) if m else default

# Uma única chave interna para toda a plataforma: o auth-service a cadastra na
# inicialização e o evaluation-service a utiliza para chamar flag e targeting.
api_key = current_value("SERVICE_API_KEY", "tm_key_super_secret_internal_token")
master_key = current_value("MASTER_KEY", "admin-master-key-togglemaster")
queue_url = out["sqs_queue_url"]
table = out.get("dynamodb_table_name", "ToggleMasterAnalytics")

def db(endpoint, name, extra=""):
    return f"postgres://postgres:{password}@{endpoint}/{name}{extra}"

secrets = f'''apiVersion: v1
kind: Secret
metadata:
  name: auth-service-secret
  namespace: togglemaster
type: Opaque
stringData:
  DATABASE_URL: "{db(out["rds_auth_endpoint"], "authdb", "?sslmode=require")}"
  MASTER_KEY: "{master_key}"
  SERVICE_API_KEY: "{api_key}"
---
apiVersion: v1
kind: Secret
metadata:
  name: flag-service-secret
  namespace: togglemaster
type: Opaque
stringData:
  DATABASE_URL: "{db(out["rds_flag_endpoint"], "flagdb").replace("postgres://", "postgresql://")}"
  SERVICE_API_KEY: "{api_key}"
---
apiVersion: v1
kind: Secret
metadata:
  name: targeting-service-secret
  namespace: togglemaster
type: Opaque
stringData:
  DATABASE_URL: "{db(out["rds_targeting_endpoint"], "targetingdb").replace("postgres://", "postgresql://")}"
  SERVICE_API_KEY: "{api_key}"
---
apiVersion: v1
kind: Secret
metadata:
  name: evaluation-service-secret
  namespace: togglemaster
type: Opaque
stringData:
  REDIS_URL: "redis://{out["redis_endpoint"]}:6379"
  SERVICE_API_KEY: "{api_key}"
  SQS_QUEUE_URL: "{queue_url}"
---
apiVersion: v1
kind: Secret
metadata:
  name: analytics-service-secret
  namespace: togglemaster
type: Opaque
stringData:
  SQS_QUEUE_URL: "{queue_url}"
  DYNAMODB_TABLE: "{table}"
'''
open(secrets_path, "w", encoding="utf-8").write(secrets)
print(f"  [ok] {secrets_path}")

# KEDA: fila monitorada
p = "gitops/apps/base/keda.yaml"
s = open(p, encoding="utf-8").read()
s = re.sub(r"queueURL: .*", f"queueURL: {queue_url}", s)
s = re.sub(r'awsRegion: ".*"', f'awsRegion: "{region}"', s)
open(p, "w", encoding="utf-8").write(s)
print(f"  [ok] {p}")

# ConfigMap: região
p = "gitops/apps/base/configmap.yaml"
s = open(p, encoding="utf-8").read()
s = re.sub(r'AWS_REGION: ".*"', f'AWS_REGION: "{region}"', s)
open(p, "w", encoding="utf-8").write(s)
print(f"  [ok] {p}")

# Imagens: registro ECR desta conta. Se a conta mudou, as tags antigas não existem
# no novo ECR: volta para :latest (o pipeline de CI grava a tag definitiva depois).
registry = f"{account}.dkr.ecr.{region}.amazonaws.com"
files = sorted(glob.glob("gitops/apps/*/deployment.yaml")) + ["gitops/observability/self-healing/deployment.yaml"]
for p in files:
    s = open(p, encoding="utf-8").read()
    m = re.search(r"image: (\d+\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com)/(togglemaster/[a-z-]+):(\S+)", s)
    if not m:
        continue
    if m.group(1) != registry:
        s = s.replace(m.group(0), f"image: {registry}/{m.group(2)}:latest")
        open(p, "w", encoding="utf-8").write(s)
        print(f"  [ok] {p} -> {registry}/{m.group(2)}:latest")
    else:
        print(f"  [--] {p} (registro já correto, tag mantida: {m.group(3)})")
PY

title "Manifestos GitOps sincronizados com a conta ${ACCOUNT} (${REGION})"
cat <<MSG
Revise e publique as alterações:

  git add gitops/
  git commit -m "chore(gitops): sincroniza manifestos com a infraestrutura da Fase 4"
  git push origin main
MSG
