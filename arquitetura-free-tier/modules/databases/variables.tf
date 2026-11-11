variable "database_subnet_ids" {
  type        = list(string)
  description = "IDs das subnets isoladas para banco de dados"
}

variable "database_security_group_id" {
  type        = string
  description = "Security Group ID para RDS e Redis"
}

variable "db_username" {
  type        = string
  description = "Usuario administrador dos bancos PostgreSQL"
  default     = "postgres"
}

variable "db_password" {
  type        = string
  description = "Senha de acesso aos bancos PostgreSQL"
  sensitive   = true
  default     = "ToggleMaster123"
}

variable "enable_free_tier" {
  type        = bool
  description = "Quando true, provisiona apenas 1 instancia RDS e omite ElastiCache para garantir 100% elegibilidade ao Free Tier (custo zero)"
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Tags padronizadas"
  default     = {}
}
