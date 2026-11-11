variable "cluster_name" {
  type        = string
  description = "Nome do cluster EKS para tagueamento correto das subnets"
  default     = "togglemaster-cluster"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block da VPC"
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  type        = list(string)
  description = "Zonas de disponibilidade para alocação de subnets"
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs para subnets públicas"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs para subnets privadas do EKS"
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "database_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs para subnets de banco de dados (RDS e Redis)"
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}

variable "enable_nat_gateway" {
  type        = bool
  description = "Habilitar NAT Gateway (quando false, economiza custos mantendo modo Free Tier)"
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Tags padronizadas para os recursos"
  default     = {}
}
