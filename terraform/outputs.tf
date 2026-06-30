output "instance_public_ip" {
  description = "Public IPv4 address of the k3s node"
  value       = aws_instance.k8s.public_ip
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.k8s.id
}

output "dns_name" {
  description = "Public DNS name for the k3s node"
  value       = aws_route53_record.ticket_master.name
}
