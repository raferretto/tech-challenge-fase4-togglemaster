# Passo a passo — criação do ambiente da Fase 4

Do zero até o experimento de Self-Healing. Os comandos são executados na raiz do
repositório, em um terminal Linux/WSL (o mesmo usado na Fase 3). Se os scripts perderem a
permissão de execução ao extrair o projeto: `chmod +x scripts/*.sh scripts/fase4/*.sh`.

**Tempo total:** cerca de 1h30 (30 min de espera do Terraform, 15 min dos pipelines).
**Custo:** o ambiente ligado custa aproximadamente US$ 0,45 a 0,50 por hora (estimativa
com preços sob demanda de us-east-1: EKS, 3 nós t3.medium, 2 NAT Gateways, 3 RDS,
ElastiCache e 2 load balancers). **Destrua tudo ao terminar (passo 11).**

---

## 1. Pré-requisitos

### Ferramentas

| Ferramenta | Para quê |
|---|---|
| AWS CLI v2, Terraform >= 1.5, kubectl, git | já usados na Fase 3 |
| python3, curl, openssl | usados pelos scripts da Fase 4 |

### Contas e chaves (anote os três valores)

| Serviço | O que criar | Valor que você vai precisar |
|---|---|---|
| **New Relic** (conta gratuita) | — | **Chave de ingestão**: *API Keys* → chave do tipo `INGEST - LICENSE`. Contas na região da UE usam o endpoint `https://otlp.eu01.nr-data.net`. |
| **PagerDuty** (conta gratuita) | Um *Service* (ex.: `ToggleMaster`) com a integração **Events API V2** | **Integration Key** (32 caracteres) |
| **Slack** | Um canal (ex.: `#togglemaster-alertas`) e um app com **Incoming Webhooks** ativado para esse canal | **Webhook URL** (`https://hooks.slack.com/services/...`) |

---

## 2. Criar o repositório no GitHub

1. Crie um repositório **público** vazio (ex.: `tech-challenge-fase4-togglemaster`). O ArgoCD
   lê os manifestos direto do GitHub, por isso precisa ser público.
2. Em **Settings → Secrets and variables → Actions**, cadastre as credenciais da AWS usadas
   pelos pipelines:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `AWS_SESSION_TOKEN` (obrigatório no AWS Academy; em conta pessoal pode ficar vazio)
3. Em **Settings → Actions → General → Workflow permissions**, marque **Read and write
   permissions** (o pipeline grava a tag da imagem no repositório).
4. Inicialize o repositório local, **sem fazer push ainda**:

```bash
git init -b main
git remote add origin https://github.com/<usuario>/<repositorio>.git
```

> No AWS Academy as credenciais expiram a cada sessão do laboratório. Ao reabrir o lab,
> atualize os três secrets do GitHub e o `aws configure` local.

---

## 3. Provisionar a infraestrutura (Terraform)

```bash
# 3.1 Bucket S3 do estado remoto (interativo; atualiza terraform/backend.tf)
./scripts/setup-remote-backend.sh

# 3.2 Parâmetros
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
#   - AWS Academy:   use_aws_academy = true
#   - Conta pessoal: use_aws_academy = false
#   - mantenha node_instance_types = ["t3.medium"] e desired_nodes = 3

# 3.3 Criação (cerca de 20 a 30 minutos)
cd terraform
terraform init
terraform apply
cd ..
```

O Terraform cria a rede, o cluster EKS, os três bancos RDS, o Redis, a fila SQS, a tabela
DynamoDB, os **seis** repositórios ECR (cinco microsserviços + `self-healing`) e instala o
ArgoCD, o Ingress NGINX e o metrics-server.

> **Por que t3.medium?** Em t3.small o EKS permite só 11 pods por nó. A stack de
> observabilidade acrescenta cerca de 9 pods; com 3 nós t3.medium (17 pods cada) há folga.

---

## 4. Apontar o GitOps para a sua conta e publicar o código

```bash
# 4.1 URL do seu repositório nas Applications do ArgoCD
./scripts/fase4/00-set-repo-url.sh https://github.com/<usuario>/<repositorio>

# 4.2 Endpoints criados pelo Terraform (RDS, Redis, SQS) e registro ECR da sua conta
./scripts/fase4/01-sync-gitops-config.sh

# 4.3 Primeiro push: dispara os 6 pipelines de CI/CD
git add .
git commit -m "feat: fase 4 - observabilidade, APM e self-healing"
git push -u origin main
```

Acompanhe em **Actions**. Cada pipeline executa testes, linter, SCA/SAST, build e scan da
imagem, envia a imagem ao ECR e grava a nova tag no manifesto GitOps (commit `[skip ci]`).
Espere os seis ficarem verdes (cerca de 10 a 15 minutos) e atualize a cópia local:

```bash
git pull --rebase origin main
```

---

## 5. Preparar o cluster

```bash
# 5.1 kubectl + KEDA + Applications do ArgoCD (microsserviços e observabilidade)
./scripts/fase4/03-bootstrap-cluster.sh

# 5.2 Segredos da observabilidade (pergunta as três chaves do passo 1)
./scripts/fase4/02-create-observability-secrets.sh
```

O segundo script cria três Secrets no namespace `observability` — eles **não** ficam no Git:

| Secret | Conteúdo |
|---|---|
| `newrelic-otlp` | chave de ingestão e endpoint OTLP do New Relic |
| `grafana-alerting-secrets` | Integration Key do PagerDuty, webhook do Slack e segredo HMAC do Self-Healing |
| `grafana-admin` | usuário e senha do Grafana (a senha é exibida ao final) |

> Enquanto os Secrets não existem, o Grafana, o gateway do Collector e o Self-Healing ficam
> em `CreateContainerConfigError`. É esperado: eles sobem sozinhos depois do passo 5.2.

---

## 6. Conferir se está tudo no ar

```bash
kubectl -n argocd get applications          # 12 Applications: Synced / Healthy
kubectl -n observability get pods           # Prometheus, kube-state-metrics, Loki, Grafana,
                                            # otel-collector-gateway, otel-collector-agent (1 por nó), self-healing
kubectl -n togglemaster get pods            # 5 microsserviços (evaluation com 2 réplicas)
```

Abra as interfaces (deixe o terminal aberto):

```bash
./scripts/fase4/04-port-forward.sh
```

| Interface | Endereço |
|---|---|
| Grafana | http://localhost:3000 — dashboard em http://localhost:3000/d/togglemaster-overview |
| Prometheus | http://localhost:9090 |
| ArgoCD | http://localhost:8081 |

---

## 7. Dados de demonstração e tráfego

```bash
# cria a flag "checkout_v2" e a regra de 50%, e faz três avaliações de teste
./scripts/fase4/05-seed-demo-data.sh

# em outro terminal: tráfego contínuo pelo Ingress (5 req/s por 15 min)
./scripts/fase4/06-generate-load.sh
```

Com o tráfego rodando, confira:

- **Grafana → dashboard**: painéis de requisições, latência, cache, fila SQS e logs com dados.
- **Grafana → Explore → Loki**: `{service_name="evaluation-service"}` (cada linha traz `trace_id`).
- **New Relic → APM & Services**: os cinco serviços; em **Service map**, as dependências;
  em **Distributed tracing**, um trace `GET /evaluate` com os spans de flag, targeting, auth,
  Redis e SQS/analytics. Os dados levam de 1 a 2 minutos para aparecer.

---

## 8. Experimento de falha e Self-Healing

Deixe o tráfego rodando há pelo menos 5 minutos e abra três terminais:

```bash
# Terminal A — pods do evaluation-service
kubectl -n togglemaster get pods -l app=evaluation-service -w

# Terminal B — log da automação
kubectl -n observability logs -f deployment/self-healing

# Terminal C — injeta a falha em todos os pods do evaluation-service
./scripts/fase4/07-inject-failure.sh
```

Linha do tempo esperada (aproximada):

| Momento | O que acontece | Onde ver |
|---|---|---|
| 0 min | `/evaluate` passa a responder 503; `/health` continua 200 | terminal da carga, dashboard |
| ~1 min | a taxa de erros dos últimos 5 min passa de 20%: alerta em **Pending** | Grafana → Alerting |
| ~3 a 4 min | alerta em **Firing**; incidente aberto; mensagem no canal | Grafana, PagerDuty, Slack |
| logo em seguida | webhook assinado chega ao Self-Healing, que reinicia o deployment | Terminal B |
| +30 a 60 s | pods antigos terminam, pods novos ficam `Running` | Terminal A |
| em seguida | respostas voltam a 200 | terminal da carga, dashboard |
| ~5 min depois | alerta volta a **Normal**; incidente resolvido; mensagem `[RESOLVED]` | Grafana, PagerDuty, Slack |

Se precisar remover a falha manualmente: `./scripts/fase4/08-clear-failure.sh`.

> O Self-Healing respeita um intervalo mínimo de 5 minutos entre duas intervenções. Para
> repetir o experimento, espere esse tempo (ou reinicie o pod: `kubectl -n observability
> rollout restart deployment/self-healing`).

---

## 9. Evidências para o relatório

```bash
./scripts/fase4/09-collect-evidence.sh      # salva saídas de texto em evidencias/<data-hora>/
```

Prints de tela a capturar durante os passos 6 a 8 (numeração do relatório):

| Figura | Print |
|---|---|
| 2 e 3 | Applications no ArgoCD; `kubectl -n observability get pods` |
| 4 | **Dashboard do Grafana** (obrigatório) |
| 5 | Consulta de logs no Loki (Explore) |
| 6 | Pipelines do OTel Collector (`gitops/observability/otel-collector/20-gateway-config.yaml`) |
| 7 e 8 | Service map e **trace distribuído** no New Relic (obrigatório) |
| 9 | Regra de alerta no Grafana |
| 10 | Injeção da falha e respostas 503 |
| 11 e 12 | Alerta em Firing; incidente no PagerDuty |
| 13 | **Notificação no Slack** (obrigatório) |
| 14 | **Log do Self-Healing** (obrigatório) |
| 15 e 16 | Pods substituídos; respostas 200 e alerta resolvido |

---

## 10. Roteiro do vídeo

Veja [demonstracao.md](demonstracao.md).

---

## 11. Destruir o ambiente

```bash
./scripts/teardown-aws.sh
```

Remove load balancers, imagens do ECR e toda a infraestrutura (`terraform destroy`).

---

## Problemas comuns

| Sintoma | Causa provável | Como resolver |
|---|---|---|
| Pods em `Pending` com `Too many pods` | nós pequenos demais | `node_instance_types = ["t3.medium"]`, `desired_nodes = 3` e `terraform apply` |
| `ImagePullBackOff` nos microsserviços ou no self-healing | pipelines ainda não publicaram as imagens, ou o registro ECR nos manifestos é de outra conta | veja a aba Actions; rode `01-sync-gitops-config.sh` e faça push |
| `CreateContainerConfigError` no namespace `observability` | Secrets ainda não criados | `02-create-observability-secrets.sh` |
| Grafana em `CrashLoopBackOff` | alguma chave do Secret `grafana-alerting-secrets` vazia (o provisionamento dos pontos de contato falha) | rode de novo o `02-create-observability-secrets.sh` informando os três valores |
| `/evaluate` responde 502 | flag/regra não criadas ou chave interna diferente entre os serviços | `05-seed-demo-data.sh`; confira se `01-sync-gitops-config.sh` foi executado e publicado |
| Nenhum dado no New Relic | chave de ingestão ou região erradas | `kubectl -n observability logs deployment/otel-collector-gateway` (erros 401/403); refaça o passo 5.2 |
| Painéis de aplicação vazios | sem tráfego | `06-generate-load.sh` |
| Alerta não dispara | menos de 20 requisições em 5 min, ou falha injetada em poucos pods | mantenha a carga; injete com `07-inject-failure.sh all` |
| Self-Healing responde `401` | segredo HMAC diferente entre Grafana e Self-Healing | os dois leem o mesmo Secret; rode o passo 5.2 de novo (ele reinicia ambos) |
| Pipelines falham no passo de AWS | credenciais do GitHub expiradas (AWS Academy) | atualize os secrets e reexecute o workflow |
