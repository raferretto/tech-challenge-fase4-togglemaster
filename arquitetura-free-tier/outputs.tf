# Outputs Consolidados para uso na Aplicação, CI/CD e GitOps

output "vpc_id" {
  description = "ID da VPC"
  value       = module.networking.vpc_id
}

output "free_tier_ec2_public_ip" {
  description = "IP Público da Instância EC2 Free Tier (quando enable_free_tier = true)"
  value       = try(module.compute[0].public_ip, null)
}

output "eks_cluster_name" {
  description = "Nome do Cluster EKS"
  value       = try(module.eks[0].cluster_name, null)
}

output "eks_cluster_endpoint" {
  description = "Endpoint da API do EKS"
  value       = try(module.eks[0].cluster_endpoint, null)
}

output "ecr_repository_urls" {
  description = "URLs dos repositórios ECR para build/push"
  value       = module.ecr.repository_urls
}

output "sqs_queue_url" {
  description = "URL da fila SQS de eventos"
  value       = module.messaging.queue_url
}

output "sqs_queue_arn" {
  description = "ARN da fila SQS"
  value       = module.messaging.queue_arn
}

output "rds_primary_endpoint" {
  description = "Endpoint do banco RDS PostgreSQL primário"
  value       = module.databases.rds_auth_endpoint
}

output "rds_flag_endpoint" {
  description = "Endpoint do banco RDS Flag (ou compartilhado em Free Tier)"
  value       = module.databases.rds_flag_endpoint
}

output "rds_targeting_endpoint" {
  description = "Endpoint do banco RDS Targeting (ou compartilhado em Free Tier)"
  value       = module.databases.rds_targeting_endpoint
}

output "redis_endpoint" {
  description = "Endpoint do cluster ElastiCache Redis (ou local na EC2 em Free Tier)"
  value       = module.databases.redis_endpoint
}

output "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB"
  value       = module.databases.dynamodb_table_name
}

output "configure_kubectl_command" {
  description = "Comando para conectar o kubectl local ao cluster EKS"
  value       = try("aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks[0].cluster_name}", null)
}
