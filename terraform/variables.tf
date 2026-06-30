variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "instance_type" {
  description = "EC2 instance type; t4g.small (Graviton/ARM64) preferred for cost in ap-south-1"
  type        = string
  default     = "t4g.small"
}

variable "my_ip_cidr" {
  description = "Your public IPv6 address in CIDR notation (e.g. 2001:db8::1/128) — restricts SSH inbound"
  type        = string
}

variable "key_pair_name" {
  description = "Name of an existing EC2 key pair in ap-south-1 for SSH access (create manually before apply)"
  type        = string
  default     = "ap-south-1"
}
