output "argocd_namespace" {
  description = "Namespace do ArgoCD"
  value       = kubernetes_namespace.argocd.metadata[0].name
}

output "argocd_release_name" {
  description = "Nome do release do ArgoCD"
  value       = helm_release.argocd.name
}
