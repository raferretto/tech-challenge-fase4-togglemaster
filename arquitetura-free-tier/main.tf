# ==============================================================================
# PROJETO TOGGLEMASTER - FASE 3 TECH CHALLENGE (FIAP)
# Módulos: Networking, EKS, Databases, Messaging, ECR, ArgoCD
# ==============================================================================

locals {
  common_tags = {
    Project     = "ToggleMaster"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Course      = "FIAP-PosTech-Fase3"
  }
}

# 1. Networking (VPC, Subnets Públicas/Privadas/DB, IGW, NAT GW opcional, SGs)
module "networking" {
  source             = "./modules/networking"
  cluster_name       = var.cluster_name
  vpc_cidr           = var.vpc_cidr
  enable_nat_gateway = !var.enable_free_tier
  tags               = local.common_tags
}

# 2. Computação EC2 Free Tier (1x t3.micro com 750h gratuitas mensais)
module "compute" {
  count             = var.enable_free_tier ? 1 : 0
  source            = "./modules/compute"
  cluster_name      = var.cluster_name
  subnet_id         = module.networking.public_subnet_ids[0]
  security_group_id = module.networking.ec2_security_group_id
  tags              = local.common_tags
}

# 3. Repositórios ECR para os 5 microsserviços
module "ecr" {
  source = "./modules/ecr"
  tags   = local.common_tags
}

# 4. Mensageria SQS (ToggleMasterEvents e DLQ)
module "messaging" {
  source     = "./modules/messaging"
  queue_name = "ToggleMasterEvents"
  tags       = local.common_tags
}

# 5. Bancos de Dados (1 RDS no modo Free Tier ou 3 RDS + Redis na arquitetura completa)
module "databases" {
  source                     = "./modules/databases"
  database_subnet_ids        = module.networking.database_subnet_ids
  database_security_group_id = module.networking.database_security_group_id
  db_password                = var.db_password
  enable_free_tier           = var.enable_free_tier
  tags                       = local.common_tags
}

# 6. Cluster Kubernetes EKS & Managed Node Groups (Ativado se enable_free_tier = false)
module "eks" {
  count                     = var.enable_free_tier ? 0 : 1
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

# 7. ArgoCD & Complementos via Helm (Ativado se enable_free_tier = false e install_argocd = true)
module "argocd" {
  count  = (!var.enable_free_tier && var.install_argocd) ? 1 : 0
  source = "./modules/argocd"

  depends_on = [module.eks]
}
