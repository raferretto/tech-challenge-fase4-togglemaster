output "rds_auth_endpoint" {
  description = "Endpoint do RDS Auth Service"
  value       = aws_db_instance.auth.endpoint
}

output "rds_auth_address" {
  description = "Host do RDS Auth Service"
  value       = aws_db_instance.auth.address
}

output "rds_flag_endpoint" {
  description = "Endpoint do RDS Flag Service"
  value       = aws_db_instance.flag.endpoint
}

output "rds_flag_address" {
  description = "Host do RDS Flag Service"
  value       = aws_db_instance.flag.address
}

output "rds_targeting_endpoint" {
  description = "Endpoint do RDS Targeting Service"
  value       = aws_db_instance.targeting.endpoint
}

output "rds_targeting_address" {
  description = "Host do RDS Targeting Service"
  value       = aws_db_instance.targeting.address
}

output "redis_endpoint" {
  description = "Endpoint primario do ElastiCache Redis"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "redis_port" {
  description = "Porta do ElastiCache Redis"
  value       = aws_elasticache_cluster.redis.port
}

output "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB"
  value       = aws_dynamodb_table.analytics.name
}

output "dynamodb_table_arn" {
  description = "ARN da tabela DynamoDB"
  value       = aws_dynamodb_table.analytics.arn
}
