# Guia de GitOps & ArgoCD - ToggleMaster Fase 3

Este documento descreve o fluxo de **Entrega Contínua (CD)** baseado no padrão **GitOps** com **ArgoCD**, eliminando o uso de `kubectl apply` manual diretamente de computadores locais.

---

## 1. Princípios do GitOps Adotados

1. **Repositório Git como Fonte Única da Verdade**: Todo o estado desejado do cluster Kubernetes está versionado em código sob o diretório `gitops/`.
2. **Atualização Automatizada de Imagens**: O pipeline de CI do GitHub Actions não faz deploy direto no cluster. Em vez disso, ele atualiza a tag da imagem no arquivo `deployment.yaml` e comita a mudança de volta no repositório.
3. **Sincronização Contínua e Self-Healing**: O agente do ArgoCD monitora o repositório Git e aplica imediatamente qualquer divergência no cluster EKS. Caso alguém altere algo manualmente com `kubectl`, o ArgoCD detecta a deriva (*drift*) e restaura o estado para o que está no Git.

---

## 2. Estrutura do Diretório GitOps

```text
gitops/
├── argocd-apps/
│   └── root-application.yaml   # Manifestos das Applications do ArgoCD (App of Apps)
└── apps/
    ├── base/                   # Recursos compartilhados do cluster
    │   ├── namespace.yaml      # Namespace 'togglemaster'
    │   ├── configmap.yaml      # Variáveis de ambiente e URLs de serviços
    │   ├── secrets.yaml        # Credenciais e conexões seguras
    │   ├── ingress.yaml        # Roteamento NGINX Ingress para os 5 serviços
    │   ├── hpa.yaml            # Horizontal Pod Autoscalers
    │   └── keda.yaml           # KEDA ScaledObject para fila SQS
    ├── auth-service/
    │   ├── deployment.yaml     # Declaração do Deployment com tag da imagem ECR
    │   └── service.yaml        # Service ClusterIP (porta 8001)
    ├── flag-service/
    │   ├── deployment.yaml     # Porta 8002
    │   └── service.yaml
    ├── targeting-service/
    │   ├── deployment.yaml     # Porta 8003
    │   └── service.yaml
    ├── evaluation-service/
    │   ├── deployment.yaml     # Porta 8004
    │   └── service.yaml
    └── analytics-service/
        ├── deployment.yaml     # Porta 8005
        └── service.yaml
```

---

## 3. Fluxo de Atualização Automática (CI -> GitOps)

No final de cada pipeline de CI no GitHub Actions:
1. O Job `4. Docker Build, Scan & Push` gera a imagem no ECR:
   `889629667863.dkr.ecr.us-east-1.amazonaws.com/togglemaster/<service>:v1.0.0-<short_sha>`
2. O Job `5. GitOps Auto-Update` executa:
   ```bash
   sed -i "s|image: .*togglemaster/<service>:.*|image: ${NEW_IMAGE}|g" gitops/apps/<service>/deployment.yaml
   git commit -m "chore(gitops): update <service> image to v1.0.0-<short_sha> [skip ci]"
   git push origin main
   ```
3. O commit com a nova tag é adicionado ao repositório Git.

---

## 4. ArgoCD: Instalação e Sincronização

### 4.1 Instalação Automatizada via Terraform
O módulo `terraform/modules/argocd` instala o chart oficial do ArgoCD através do provider Helm do Terraform:
- **Namespace**: `argocd`
- **Service Type**: `LoadBalancer` (permitindo acesso externo à UI)

### 4.2 Obter a Senha de Acesso Inicial do ArgoCD
No terminal conectado ao cluster EKS:
```bash
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d
echo ""
```
- **Usuário**: `admin`
- **Senha**: (hash decodificado acima)

### 4.3 Aplicar as Aplicações no ArgoCD
Para registrar os 5 microsserviços no ArgoCD:
```bash
kubectl apply -f gitops/argocd-apps/root-application.yaml
```

### 4.4 Demonstração no Vídeo
1. Mostre a UI do ArgoCD com os 5 microsserviços exibidos como nós verdes (`Synced` e `Healthy`).
2. Mostre que, assim que o pipeline do GitHub Actions realiza o commit com a nova tag da imagem, o ArgoCD detecta a mudança e atualiza o pod correspondente no EKS via rolling update sem downtime.
