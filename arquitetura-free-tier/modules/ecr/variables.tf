variable "repositories" {
  type        = list(string)
  description = "Lista de nomes de repositorios ECR a serem criados"
  default = [
    "togglemaster/auth-service",
    "togglemaster/flag-service",
    "togglemaster/targeting-service",
    "togglemaster/evaluation-service",
    "togglemaster/analytics-service"
  ]
}

variable "tags" {
  type        = map(string)
  description = "Tags padronizadas para os repositorios ECR"
  default     = {}
}
