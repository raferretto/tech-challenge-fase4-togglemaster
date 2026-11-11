variable "cluster_name" {
  type        = string
  description = "Nome do projeto/cluster"
  default     = "togglemaster"
}

variable "subnet_id" {
  type        = string
  description = "Subnet pública onde a instância EC2 Free Tier será executada"
}

variable "security_group_id" {
  type        = string
  description = "Security Group ID para a instância EC2"
}

variable "instance_type" {
  type        = string
  description = "Tipo de instância EC2 (padrão Free Tier: t3.micro ou t2.micro)"
  default     = "t3.micro"
}

variable "tags" {
  type        = map(string)
  description = "Tags padronizadas"
  default     = {}
}
