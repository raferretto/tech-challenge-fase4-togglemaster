# ==============================================================================
# PROJETO TOGGLEMASTER - FASE 4 TECH CHALLENGE (FIAP)
# Módulos: Networking, EKS, Databases, Messaging, ECR, ArgoCD
# ==============================================================================

locals {
  common_tags = {
    Project     = "ToggleMaster"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Course      = "FIAP-PosTech-Fase4"
  }
}

# 1. Networking (VPC, Subnets Públicas/Privadas/DB, IGW, NAT GW, SGs)
module "networking" {
  source       = "./modules/networking"
  cluster_name = var.cluster_name
  vpc_cidr     = var.vpc_cidr
  tags         = local.common_tags
}

# 2. Repositórios ECR: 5 microsserviços + automação de Self-Healing (Fase 4)
module "ecr" {
  source = "./modules/ecr"
  tags   = local.common_tags
}

# 3. Mensageria SQS (ToggleMasterEvents e DLQ)
module "messaging" {
  source     = "./modules/messaging"
  queue_name = "ToggleMasterEvents"
  tags       = local.common_tags
}

# 4. Bancos de Dados (3 RDS Postgres, ElastiCache Redis, DynamoDB)
module "databases" {
  source                     = "./modules/databases"
  database_subnet_ids        = module.networking.database_subnet_ids
  database_security_group_id = module.networking.database_security_group_id
  db_password                = var.db_password
  tags                       = local.common_tags
}

# 5. Cluster Kubernetes EKS & Managed Node Groups
module "eks" {
  source                    = "./modules/eks"
  cluster_name              = var.cluster_name
  vpc_id                    = module.networking.vpc_id
  public_subnet_ids         = module.networking.public_subnet_ids
  private_subnet_ids        = module.networking.private_subnet_ids
  cluster_security_group_id = module.networking.cluster_security_group_id
  use_aws_academy           = var.use_aws_academy
  node_instance_types       = var.node_instance_types
  desired_nodes             = var.desired_nodes
  tags                      = local.common_tags
}

# 6. ArgoCD & Complementos via Helm
module "argocd" {
  count  = var.install_argocd ? 1 : 0
  source = "./modules/argocd"

  depends_on = [module.eks]
}
