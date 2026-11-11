output "cluster_id" {
  description = "ID do Cluster EKS"
  value       = aws_eks_cluster.main.id
}

output "cluster_name" {
  description = "Nome do Cluster EKS"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "Endpoint do Kubernetes API Server"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Dados da autoridade certificadora do Cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "oidc_provider_arn" {
  description = "ARN do OpenID Connect Provider para IRSA"
  value       = aws_iam_openid_connect_provider.oidc.arn
}

output "oidc_issuer" {
  description = "Issuer URL do OIDC"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "node_group_arn" {
  description = "ARN do Managed Node Group"
  value       = aws_eks_node_group.main.arn
}
