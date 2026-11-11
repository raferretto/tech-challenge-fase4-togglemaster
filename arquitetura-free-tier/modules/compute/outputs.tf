output "instance_id" {
  description = "ID da instância EC2 Free Tier"
  value       = aws_instance.server.id
}

output "public_ip" {
  description = "IP Público da instância EC2 Free Tier"
  value       = aws_instance.server.public_ip
}

output "public_dns" {
  description = "DNS Público da instância EC2 Free Tier"
  value       = aws_instance.server.public_dns
}
