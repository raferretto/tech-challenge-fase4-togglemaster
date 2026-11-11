# Arquitetura de Infraestrutura em Nuvem (AWS) - ToggleMaster Fase 3

Este documento detalha a arquitetura em nuvem provisionada de forma 100% automatizada e imutável através do **Terraform**, substituindo os procedimentos manuais da Fase 2 e atendendo aos requisitos do Tech Challenge da Fase 3 (FIAP Pós-Tech).

---

## 1. Diagrama de Arquitetura

```
+----------------------------------------------------------------------------------------------------+
| AWS Cloud (us-east-1) - VPC: 10.0.0.0/16                                                           |
|                                                                                                    |
|  [ Internet Gateway ] <---> [ Public Subnets: 10.0.1.0/24, 10.0.2.0/24 ]                           |
|                                     |                                                              |
|                                [ NAT Gateway ]                                                     |
|                                     |                                                              |
|  +----------------------------------v-----------------------------------------------------------+  |
|  | Private Subnets (EKS Managed Nodes): 10.0.10.0/24, 10.0.11.0/24                              |  |
|  |                                                                                              |  |
|  |   +---------------------------------------------------------------------------------------+  |  |
|  |   | Amazon EKS Cluster: togglemaster-cluster (Kubernetes v1.30)                           |  |  |
|  |   |                                                                                       |  |  |
|  |   |  - ArgoCD Controller (GitOps)                                                         |  |  |
|  |   |  - Ingress NGINX Controller                                                           |  |  |
|  |   |  - KEDA Operator & Metrics Server (Autoscaling)                                       |  |  |
|  |   |                                                                                       |  |  |
|  |   |  Pods dos 5 Microsserviços:                                                           |  |  |
|  |   |    [ auth-service ]       (Go)     : Porta 8001                                      |  |  |
|  |   |    [ flag-service ]       (Python) : Porta 8002                                      |  |  |
|  |   |    [ targeting-service ]  (Python) : Porta 8003                                      |  |  |
|  |   |    [ evaluation-service ] (Go)     : Porta 8004                                      |  |  |
|  |   |    [ analytics-service ]  (Python) : Porta 8005                                      |  |  |
|  |   +---------------------------------------------------------------------------------------+  |  |
|  +----------------------------------------------------------------------------------------------+  |
|                                     |                                                              |
|  +----------------------------------v-----------------------------------------------------------+  |
|  | Isolated Database Subnets: 10.0.20.0/24, 10.0.21.0/24                                        |  |
|  |                                                                                              |  |
|  |   [ RDS Auth ]          [ RDS Flag ]          [ RDS Targeting ]       [ ElastiCache Redis ]  |  |
|  |   (PostgreSQL 15)       (PostgreSQL 15)       (PostgreSQL 15)         (Cluster Redis 7)      |  |
|  |   Porta: 5432           Porta: 5432           Porta: 5432             Porta: 6379            |  |
|  +----------------------------------------------------------------------------------------------+  |
|                                                                                                    |
|  Managed AWS Services:                                                                             |
|    - Amazon DynamoDB: Tabela 'ToggleMasterAnalytics' (PAY_PER_REQUEST)                             |
|    - Amazon SQS: Fila 'ToggleMasterEvents' + 'ToggleMasterEvents-dlq'                              |
|    - Amazon ECR: 5 Repositórios privados com Image Scanning on Push                                |
|    - Amazon S3: Remote State Bucket com 'use_lockfile = true'                                      |
+----------------------------------------------------------------------------------------------------+
```

---

## 2. Componentes da Infraestrutura

### 2.1 Networking & Segurança de Rede (`modules/networking`)
- **VPC**: Rede virtual isolada com bloco CIDR `10.0.0.0/16`.
- **Subnets Públicas**: Distribuídas em duas zonas de disponibilidade (`us-east-1a`, `us-east-1b`), associadas a um **Internet Gateway (IGW)** para balanceadores de carga externos e NAT Gateway.
- **Subnets Privadas**: Subnets para execução segura dos nós de trabalho do EKS sem exposição pública direta.
- **NAT Gateway**: Fornece saída segura à internet para que os nós privados possam baixar imagens e pacotes externos sem receber conexões de entrada.
- **Subnets de Banco de Dados**: Subnets exclusivas para os bancos de dados relacionais e em memória, sem acesso à internet externa.
- **Security Groups**:
  - `togglemaster-cluster-sg`: Permite o tráfego seguro do Control Plane do EKS.
  - `togglemaster-database-sg`: Restringe as portas `5432` (PostgreSQL) e `6379` (Redis) apenas aos nós do EKS dentro da VPC.

### 2.2 Cluster Kubernetes EKS (`modules/eks`)
- **Control Plane EKS**: Alta disponibilidade gerenciada pela AWS.
- **Managed Node Group**: 2 instâncias `t3.small` com escalabilidade automática configurada entre 1 e 3 nós.
- **Suporte Híbrido IAM**:
  - **AWS Academy**: Usa `data.aws_iam_role.lab_role` (`LabRole`).
  - **Conta Pessoal**: Cria roles e policies específicas com privilégio mínimo (`AmazonEKSClusterPolicy`, `AmazonEKSWorkerNodePolicy`, etc.).
- **IRSA (IAM Roles for Service Accounts)**: OpenID Connect Provider configurado para associar permissões IAM granulares a pods específicos (SQS e DynamoDB).

### 2.3 Camada de Bancos de Dados & Persistência (`modules/databases`)
- **3 Instâncias RDS PostgreSQL (`db.t3.micro`)**:
  - `togglemaster-db-auth`: Armazenamento de chaves de API e hashes.
  - `togglemaster-db-flag`: CRUD de feature flags e metadados.
  - `togglemaster-db-targeting`: Regras avançadas de segmentação por percentual e atributos.
- **1 Cluster ElastiCache Redis (`cache.t4g.micro`)**:
  - `togglemaster-cache`: Armazenamento em cache de flags e regras para baixa latência nas consultas do `evaluation-service`.
- **1 Tabela DynamoDB (`ToggleMasterAnalytics`)**:
  - Modo `PAY_PER_REQUEST` com chave primária `event_id` para persistência dos eventos de analytics.

### 2.4 Mensageria Assíncrona (`modules/messaging`)
- **Amazon SQS (`ToggleMasterEvents`)**: Desacopla o processamento do motor de avaliação (`evaluation-service`) do consumidor (`analytics-service`).
- **Dead Letter Queue (`ToggleMasterEvents-dlq`)**: Retenção de 14 dias para mensagens não processadas após 5 tentativas de entrega.

### 2.5 Registro de Contêineres (`modules/ecr`)
- **5 Repositórios ECR Privados**:
  - `togglemaster/auth-service`
  - `togglemaster/flag-service`
  - `togglemaster/targeting-service`
  - `togglemaster/evaluation-service`
  - `togglemaster/analytics-service`
- **Segurança ECR**: `scan_on_push = true` ativado para detecção contínua de vulnerabilidades em imagens.
- **Lifecycle Policy**: Expurgo automático de imagens com mais de 30 dias para otimização de custos.

### 2.6 Gerenciamento de Estado Remoto do Terraform (`backend.tf`)
- **Bucket S3**: `togglemaster-terraform-state-fiap` com versionamento e criptografia AES-256 ativados.
- **Locking Nativo**: Uso do parâmetro `use_lockfile = true` do Terraform moderno, garantindo integridade sem conflitos de execução concorrente.
