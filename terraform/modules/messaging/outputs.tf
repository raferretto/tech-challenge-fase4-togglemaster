output "queue_url" {
  description = "URL da fila SQS principal"
  value       = aws_sqs_queue.main.url
}

output "queue_arn" {
  description = "ARN da fila SQS principal"
  value       = aws_sqs_queue.main.arn
}

output "queue_name" {
  description = "Nome da fila SQS principal"
  value       = aws_sqs_queue.main.name
}

output "dlq_url" {
  description = "URL da fila de Dead Letter"
  value       = aws_sqs_queue.dlq.url
}

output "dlq_arn" {
  description = "ARN da fila de Dead Letter"
  value       = aws_sqs_queue.dlq.arn
}
