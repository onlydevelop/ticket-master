output "instance_ipv6_address" {
  description = "Public IPv6 address of the k3s node — use this in the API Gateway HTTP_PROXY integration"
  value       = aws_instance.k8s.ipv6_addresses[0]
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.k8s.id
}
