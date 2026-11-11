output "vpc_id" {
  description = "ID da VPC criada"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs das subnets publicas"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas do EKS"
  value       = aws_subnet.private[*].id
}

output "database_subnet_ids" {
  description = "IDs das subnets isoladas de banco de dados"
  value       = aws_subnet.database[*].id
}

output "cluster_security_group_id" {
  description = "ID do Security Group do Cluster EKS"
  value       = aws_security_group.eks_cluster.id
}

output "database_security_group_id" {
  description = "ID do Security Group dos Bancos de Dados"
  value       = aws_security_group.database.id
}
