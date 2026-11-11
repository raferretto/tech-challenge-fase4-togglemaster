# Outputs Consolidados para uso na Aplicação, CI/CD e GitOps

output "vpc_id" {
  description = "ID da VPC"
  value       = module.networking.vpc_id
}

output "eks_cluster_name" {
  description = "Nome do Cluster EKS"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Endpoint da API do EKS"
  value       = module.eks.cluster_endpoint
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

output "rds_auth_endpoint" {
  description = "Endpoint do banco RDS Auth"
  value       = module.databases.rds_auth_endpoint
}

output "rds_flag_endpoint" {
  description = "Endpoint do banco RDS Flag"
  value       = module.databases.rds_flag_endpoint
}

output "rds_targeting_endpoint" {
  description = "Endpoint do banco RDS Targeting"
  value       = module.databases.rds_targeting_endpoint
}

output "redis_endpoint" {
  description = "Endpoint do cluster ElastiCache Redis"
  value       = module.databases.redis_endpoint
}

output "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB"
  value       = module.databases.dynamodb_table_name
}

output "configure_kubectl_command" {
  description = "Comando para conectar o kubectl local ao cluster EKS"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
