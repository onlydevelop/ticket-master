# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

This is a Terraform project (to be built) for provisioning a minimal, learning-focused IPv6-only EC2 Kubernetes dev environment on AWS (ap-south-1). The `prompt` file contains the full specification.

## Target File Structure

Flat root-level `.tf` files only — no modules, no subdirectories:

- `main.tf` — VPC, subnet, IGW, route table, security group, EC2 instance
- `variables.tf` — region, instance type, my_ip_cidr (IPv6 CIDR for SSH), key_pair_name
- `outputs.tf` — instance's public IPv6 address, instance ID

## Key Architecture Decisions (from spec)

- **IPv6-only public connectivity**: no public IPv4, no Elastic IP, no NAT Gateway — the EC2 instance is reached solely via its public IPv6 address
- **Dual-stack VPC**: AWS requires an IPv4 CIDR on the VPC even though IPv4 is unused publicly; one /64 IPv6 subnet carved from the VPC's /56 block
- **Single-node k3s**: installed via user data (`curl -sfL https://get.k3s.io | sh -`), not EKS; cluster/service CIDRs set to IPv6 ranges
- **NGINX ingress with `hostNetwork: true`**: binds directly to the node's public IPv6 address instead of provisioning a cloud load balancer
- **IMDSv2 with IPv6 metadata**: user data must use the `fd00:ec2::254` metadata endpoint
- **Instance type**: prefer `t4g.small` (Graviton/ARM) for cost in ap-south-1, fall back to `t3.small`; must be a Nitro-based type
- **AMI**: Ubuntu 24.04 LTS or Amazon Linux 2023 (whichever has simpler IPv6 metadata/userdata support)
- **Route table**: only a `::/0 → IGW` IPv6 default route; no IPv4 default route
- **IAM**: only if strictly required (e.g. SSM Session Manager for debugging without IPv4 SSH)
- **State**: local only — no S3/DynamoDB remote backend

## Terraform Commands

```bash
terraform init
terraform plan -var="my_ip_cidr=<your-ipv6>/128" -var="key_pair_name=<your-key>"
terraform apply -var="my_ip_cidr=<your-ipv6>/128" -var="key_pair_name=<your-key>"
terraform destroy
```

## Pre-apply Manual Steps

1. Create an EC2 key pair in ap-south-1 (or reference an existing one) — Terraform does not create it
2. Know your public IPv6 address for the `my_ip_cidr` variable (used to restrict SSH inbound)
3. Ensure AWS credentials are configured (`aws configure` or env vars)

## Inline Comments

The spec explicitly requests brief inline comments explaining each IPv6-specific choice (why no NAT, why no public IPv4, why route table has only an IPv6 default route) — this is a learning project, so comments explaining decisions are intentional and required.
