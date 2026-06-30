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
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "k8s-dev-vpc" }
}

# ── Subnet ────────────────────────────────────────────────────────────────────
# Public IPv4 subnet; instances get a public IP on launch so they can reach
# the internet (and be SSH'd into) without a NAT gateway.
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.region}a"

  tags = { Name = "k8s-dev-subnet-public" }
}

# ── Internet Gateway ──────────────────────────────────────────────────────────
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "k8s-dev-igw" }
}

# ── Route Table ───────────────────────────────────────────────────────────────
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "k8s-dev-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ── Security Group ────────────────────────────────────────────────────────────
resource "aws_security_group" "k8s" {
  name        = "k8s-dev-sg"
  description = "SSH from my IP, HTTP/HTTPS from anywhere, all egress"
  vpc_id      = aws_vpc.main.id

  # SSH locked to your IP — var.my_ip_cidr should be your /32 public IPv4
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # k8s API server — open to 0.0.0.0/0 because GitHub Actions runners use
  # dynamic IPs; restrict to your own IP for non-CI access if desired
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "k8s-dev-sg" }
}

# ── AMI ───────────────────────────────────────────────────────────────────────
# Ubuntu 24.04 LTS ARM64 for the t4g.small (Graviton2) instance type.
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
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  key_name                    = var.key_pair_name
  vpc_security_group_ids      = [aws_security_group.k8s.id]
  associate_public_ip_address = true

  user_data                   = file("${path.module}/userdata.sh")
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = { Name = "k8s-dev-node" }
}

# ── DNS ───────────────────────────────────────────────────────────────────────
data "aws_route53_zone" "onlydevelop" {
  name         = "onlydevelop.net"
  private_zone = false
}

# A record pointing ticket-master.onlydevelop.net → instance's public IPv4.
# Note: the public IP changes on stop/start; re-apply Terraform after each restart.
resource "aws_route53_record" "ticket_master" {
  zone_id = data.aws_route53_zone.onlydevelop.zone_id
  name    = "ticket-master.onlydevelop.net"
  type    = "A"
  ttl     = 300
  records = [aws_instance.k8s.public_ip]
}
