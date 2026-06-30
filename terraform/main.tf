terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.6"
}

provider "aws" {
  region = var.region
}

# ── VPC ──────────────────────────────────────────────────────────────────────
# AWS requires an IPv4 CIDR on every VPC even though we won't route IPv4 publicly.
# assign_generated_ipv6_cidr_block requests an Amazon-provided /56 IPv6 block
# from which we'll carve out a /64 subnet below.
resource "aws_vpc" "main" {
  cidr_block                       = "10.0.0.0/16"
  assign_generated_ipv6_cidr_block = true

  tags = { Name = "k8s-dev-vpc" }
}

# ── Subnet ────────────────────────────────────────────────────────────────────
# A single /64 IPv6 subnet (cidrsubnet with 8 new bits from the /56 gives /64).
# ipv6_native = true makes this a true IPv6-only subnet — no IPv4 addressing.
# No public IPv4 is assigned on launch because there is no NAT Gateway and
# we have no use for public IPv4 in this setup.
resource "aws_subnet" "ipv6" {
  vpc_id                          = aws_vpc.main.id
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, 0)
  ipv6_native                     = true
  assign_ipv6_address_on_creation = true
  map_public_ip_on_launch         = false
  availability_zone               = "${var.region}a"

  tags = { Name = "k8s-dev-subnet-ipv6" }
}

# ── Internet Gateway ──────────────────────────────────────────────────────────
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "k8s-dev-igw" }
}

# ── Route Table ───────────────────────────────────────────────────────────────
# Only an IPv6 default route is needed. There is no NAT Gateway and no public
# IPv4, so an IPv4 default route would have nowhere to point.
resource "aws_route_table" "ipv6" {
  vpc_id = aws_vpc.main.id

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.main.id
  }

  tags = { Name = "k8s-dev-rt" }
}

resource "aws_route_table_association" "ipv6" {
  subnet_id      = aws_subnet.ipv6.id
  route_table_id = aws_route_table.ipv6.id
}

# ── Security Group ────────────────────────────────────────────────────────────
resource "aws_security_group" "k8s" {
  name        = "k8s-dev-sg"
  description = "SSH from my IPv6, HTTP/HTTPS from anywhere, all IPv6 egress"
  vpc_id      = aws_vpc.main.id

  # SSH locked to your IP — var.my_ip_cidr should be your /128 public IPv6
  ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    ipv6_cidr_blocks = [var.my_ip_cidr]
  }

  ingress {
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    ipv6_cidr_blocks = ["::/0"]
  }

  # Allow all IPv6 outbound — required for k3s install, image pulls, etc.
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = { Name = "k8s-dev-sg" }
}

# ── AMI ───────────────────────────────────────────────────────────────────────
# Ubuntu 24.04 LTS ARM64 for the t4g.small (Graviton2) instance type.
# Canonical's AWS account: 099720109477.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── EC2 Instance ──────────────────────────────────────────────────────────────
resource "aws_instance" "k8s" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.ipv6.id
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.k8s.id]

  # Request one IPv6 address from the subnet; no public IPv4 assigned
  ipv6_address_count          = 1
  associate_public_ip_address = false

  user_data                   = file("${path.module}/userdata.sh")
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = { Name = "k8s-dev-node" }
}
