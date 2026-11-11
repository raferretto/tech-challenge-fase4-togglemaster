variable "argocd_version" {
  type        = string
  description = "Versao do chart Helm do ArgoCD"
  default     = "7.7.0"
}

variable "namespace" {
  type        = string
  description = "Namespace Kubernetes onde o ArgoCD sera instalado"
  default     = "argocd"
}

variable "enable_metrics_server" {
  type        = bool
  description = "Instalar o metrics-server para HPA"
  default     = true
}

variable "enable_ingress_nginx" {
  type        = bool
  description = "Instalar o Ingress Nginx Controller"
  default     = true
}
