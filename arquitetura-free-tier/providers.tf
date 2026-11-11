terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "ToggleMaster"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Course      = "FIAP-PosTech-Fase3"
    }
  }
}

data "aws_eks_cluster_auth" "cluster" {
  count = var.enable_free_tier ? 0 : 1
  name  = try(module.eks[0].cluster_name, "")
}

provider "kubernetes" {
  host                   = try(module.eks[0].cluster_endpoint, "https://localhost")
  cluster_ca_certificate = try(base64decode(module.eks[0].cluster_certificate_authority_data), "")
  token                  = try(data.aws_eks_cluster_auth.cluster[0].token, "")
}

provider "helm" {
  kubernetes {
    host                   = try(module.eks[0].cluster_endpoint, "https://localhost")
    cluster_ca_certificate = try(base64decode(module.eks[0].cluster_certificate_authority_data), "")
    token                  = try(data.aws_eks_cluster_auth.cluster[0].token, "")
  }
}
