output "rds_auth_endpoint" {
  description = "Endpoint do RDS Auth Service (ou banco primário Free Tier)"
  value       = aws_db_instance.auth.endpoint
}

output "rds_auth_address" {
  description = "Host do RDS Auth Service"
  value       = aws_db_instance.auth.address
}

output "rds_flag_endpoint" {
  description = "Endpoint do RDS Flag Service"
  value       = try(aws_db_instance.flag[0].endpoint, aws_db_instance.auth.endpoint)
}

output "rds_flag_address" {
  description = "Host do RDS Flag Service"
  value       = try(aws_db_instance.flag[0].address, aws_db_instance.auth.address)
}

output "rds_targeting_endpoint" {
  description = "Endpoint do RDS Targeting Service"
  value       = try(aws_db_instance.targeting[0].endpoint, aws_db_instance.auth.endpoint)
}

output "rds_targeting_address" {
  description = "Host do RDS Targeting Service"
  value       = try(aws_db_instance.targeting[0].address, aws_db_instance.auth.address)
}

output "redis_endpoint" {
  description = "Endpoint primario do ElastiCache Redis"
  value       = try(aws_elasticache_cluster.redis[0].cache_nodes[0].address, "localhost")
}

output "redis_port" {
  description = "Porta do ElastiCache Redis"
  value       = try(aws_elasticache_cluster.redis[0].port, 6379)
}

output "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB"
  value       = aws_dynamodb_table.analytics.name
}

output "dynamodb_table_arn" {
  description = "ARN da tabela DynamoDB"
  value       = aws_dynamodb_table.analytics.arn
}
