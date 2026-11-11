variable "queue_name" {
  type        = string
  description = "Nome da fila principal SQS"
  default     = "ToggleMasterEvents"
}

variable "tags" {
  type        = map(string)
  description = "Tags padronizadas"
  default     = {}
}
