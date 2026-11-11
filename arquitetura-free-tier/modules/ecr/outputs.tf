output "repository_urls" {
  description = "URLs dos repositorios ECR criados"
  value       = { for k, v in aws_ecr_repository.repos : k => v.repository_url }
}

output "repository_arns" {
  description = "ARNs dos repositorios ECR criados"
  value       = { for k, v in aws_ecr_repository.repos : k => v.arn }
}
