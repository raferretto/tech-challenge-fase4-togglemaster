variable "cluster_name" {
  type        = string
  description = "Nome do cluster EKS"
  default     = "togglemaster-cluster"
}

variable "cluster_version" {
  type        = string
  description = "Versao do Kubernetes no EKS"
  default     = "1.30"
}

variable "vpc_id" {
  type        = string
  description = "ID da VPC"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Subnets privadas para os Worker Nodes"
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Subnets publicas para o Control Plane do EKS"
}

variable "cluster_security_group_id" {
  type        = string
  description = "Security Group do Cluster EKS"
}

variable "use_aws_academy" {
  type        = bool
  description = "Se verdadeiro, utiliza a LabRole existente do AWS Academy em vez de criar novas Roles IAM"
  default     = false
}

variable "node_instance_types" {
  type        = list(string)
  description = "Tipos de instancias EC2 para o Node Group"
  default     = ["t3.small"]
}

variable "desired_nodes" {
  type        = number
  description = "Quantidade desejada de nos no Node Group"
  default     = 2
}

variable "min_nodes" {
  type        = number
  description = "Quantidade minima de nos"
  default     = 1
}

variable "max_nodes" {
  type        = number
  description = "Quantidade maxima de nos"
  default     = 3
}

variable "tags" {
  type        = map(string)
  description = "Tags padronizadas"
  default     = {}
}
