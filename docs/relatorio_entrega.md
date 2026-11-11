# Relatório de Entrega - Tech Challenge Fase 3

**Curso**: Pós-Tech FIAP - DevOps & Cloud Architecture  
**Fase 3**: Automação e Segurança na Nuvem (DevSecOps, IaC e GitOps)  
**Data de Entrega**: Setembro de 2026  

---

## 1. Identificação dos Participantes

- **Erisvam Herdley Da Silva Santos**
- **Felipe Sousa Da Silva**
- **Rafael Andrade Ferretto**

---

## 2. Links de Entrega

- **Repositório GitHub (Código, IaC e GitOps)**: [github.com/dasilva-dev/tech-challenge-fase3-togglemaster](https://github.com/dasilva-dev/tech-challenge-fase3-togglemaster)
- **Vídeo de Demonstração (YouTube / Google Drive)**: `https://youtu.be/[SEU_LINK_DO_VIDEO]`
- **Documentação de Arquitetura**: [docs/arquitetura.md](docs/arquitetura.md)
- **Documentação de DevSecOps**: [docs/devsecops.md](docs/devsecops.md)
- **Documentação de GitOps**: [docs/gitops.md](docs/gitops.md)

### Diagrama da Arquitetura e Pipeline DevSecOps
![Desenho da Arquitetura ToggleMaster](images/arquitetura_togglemaster.png)

---

## 3. Resumo dos Desafios Encontrados e Decisões Tomadas

### 3.1 Desafio 1: Modularização e Compatibilidade da Infraestrutura (AWS Academy vs Conta Pessoal)
- **Desafio**: O ambiente do AWS Academy possui restrições severas de permissões IAM (proibição de criação de novas roles/policies, exigindo o uso exclusivo da `LabRole`), enquanto contas pessoais demandam policies de privilégio mínimo para um portfólio profissional.
- **Decisão**: Implementamos um módulo Terraform altamente flexível com a variável condicional `use_aws_academy`. Quando ativada, a infraestrutura consome a `LabRole` existente via data source; quando desativada, cria roles IAM com privilégio mínimo (`AmazonEKSClusterPolicy`, `AmazonEKSWorkerNodePolicy`, etc.).

### 3.2 Desafio 2: Estado Remoto Imutável e Concorrência de Deploy
- **Desafio**: Evitar conflitos de estado do Terraform quando múltiplos desenvolvedores ou pipelines executam alterações concorrentes.
- **Decisão**: Configuramos o Remote Backend em um bucket S3 com versionamento e criptografia AES-256 ativados, associado ao parâmetro nativo `use_lockfile = true` do Terraform moderno, eliminando a necessidade de gerenciar uma tabela DynamoDB separada apenas para locking de estado.

### 3.3 Desafio 3: Implementação de DevSecOps com Regra Estrita de Bloqueio
- **Desafio**: Garantir que o pipeline não seja apenas um gerador de relatórios passivo, mas sim uma barreira ativa contra vulnerabilidades em produção ("Shift-Left Security").
- **Decisão**: Integramos o **Trivy** em modo `fs` (SCA) e **Gosec/Bandit** (SAST), configurando a flag de falha obrigatória (`exit-code 1` para severidade `CRITICAL`). Imagens vulneráveis são sumariamente barradas antes da etapa de build Docker e publicação no ECR.

### 3.4 Desafio 4: Adoção do Padrão GitOps (Eliminando Deploy Direto via CI)
- **Desafio**: Desacoplar o processo de build/teste do processo de aplicação no cluster Kubernetes, garantindo que o repositório Git permaneça como fonte única da verdade.
- **Decisão**: O pipeline de CI é responsável apenas por testar, escanear, gerar a imagem no ECR e atualizar a tag no manifesto `deployment.yaml` na pasta `gitops/`. A reconciliação no cluster EKS é delegada integralmente ao **ArgoCD**, que monitora as alterações e realiza o sync com capacidade de *self-healing*.

---

## 4. Estimativa Detalhada de Custos na AWS (AWS Pricing Calculator)

### 4.1 Ambiente Principal (100% AWS Free Tier - Custo Zero)

O ambiente principal foi desenhado para operar com **custo zero** em contas da AWS, aproveitando os benefícios do Free Tier:

| Serviço AWS | Configuração Free Tier | Custo Mensal Estimado (USD) |
| :--- | :--- | :--- |
| **Amazon EC2** | 1 instância `t3.micro` (750 horas/mês gratuitas) | **$0.00** (Free Tier) |
| **Amazon EBS Storage** | 20 GB gp3 (até 30 GB gratuitos no Free Tier) | **$0.00** (Free Tier) |
| **Amazon RDS (PostgreSQL)** | 1 instância `db.t3.micro` Single-AZ + 20 GB gp3 | **$0.00** (Free Tier - 750h) |
| **Cache Redis** | Executado localmente em contêiner na EC2 | **$0.00** |
| **Amazon VPC / Rede** | Subnets públicas com Internet Gateway (Sem NAT GW) | **$0.00** |
| **Amazon DynamoDB** | On-Demand (PAY_PER_REQUEST) - até 25 GB gratuitos | **$0.00** (Free Tier) |
| **Amazon SQS** | Fila padrão - até 1.000.000 requisições/mês | **$0.00** (Free Tier) |
| **Amazon ECR** | 5 repositórios - até 500 MB/mês | **$0.00** (Free Tier) |
| **Amazon S3 (State)** | Bucket remoto com versionamento (< 1 GB) | **$0.00** (Free Tier) |
| **Total Mensal (Ambiente Principal)** | **Modo Free Tier Ativo** | **$0.00 USD / mês** |

---

### 4.2 Arquitetura Completa Enterprise (Preservada em `arquitetura-completa/`)

Para fins de dimensionamento corporativo em larga escala, a arquitetura multi-recurso com EKS e bancos dedicados possui a seguinte estimativa:

| Serviço AWS | Configuração / Dimensionamento | Custo Mensal Estimado (USD) |
| :--- | :--- | :--- |
| **Amazon EKS (Control Plane)** | 1 Cluster gerenciado ($0.10/hora) | ~$73.00 |
| **Amazon EC2 (Worker Nodes)** | 2 instâncias `t3.small` (2 vCPU, 2 GiB RAM) | ~$29.80 |
| **EBS Storage (Worker Nodes)** | 40 GB gp3 (20 GB por nó) | ~$3.20 |
| **Amazon RDS (PostgreSQL)** | 3 instâncias `db.t3.micro` Single-AZ + 20 GB gp3 cada | ~$54.00 (~$18.00/cada) |
| **Amazon ElastiCache (Redis)** | 1 nó `cache.t4g.micro` (0.5 GiB RAM) | ~$11.68 |
| **Amazon VPC (NAT Gateway)** | 1 NAT Gateway (~$0.045/hora) + tráfego | ~$34.50 |
| **Amazon DynamoDB** | On-Demand (PAY_PER_REQUEST) | ~$0.00 (Free Tier) |
| **Amazon SQS** | Fila padrão | ~$0.00 (Free Tier) |
| **Amazon ECR** | 5 repositórios com lifecycle policy | ~$0.50 |
| **Amazon S3 (Terraform State)** | Bucket com versionamento | ~$0.05 |
| **Total Mensal Estimado** | **Arquitetura Multi-Recurso Completa** | **~$206.73 / mês** |

> 💡 **Nota de Otimização para Gravação e Demonstração**:  
> Caso a arquitetura completa seja ligada para testes ou gravação e destruída logo em seguida através dos scripts de teardown (`scripts/teardown-aws.sh`), o custo real por 4 horas de execução é de apenas **~$1.15 USD** (menos de R$ 7,00).
