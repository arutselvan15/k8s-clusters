# Steps 1–6: through worker EC2. Checklist: STEPS.md

# Step 1 — who we are (no cost).
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# Step 2 — VPC: a private IP network in this AWS account/region.
resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}

# Step 3 — one public subnet + door to the internet.
# cidrsubnet(10.0.0.0/16, 8, 1) => 10.0.1.0/24 (256 addresses in the first AZ).
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.cluster_name}-public"
  }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }

  tags = {
    Name = "${var.cluster_name}-public"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Step 4 — security group: stateful firewall (default deny inbound).
# admin_cidr is who may SSH / kubectl from the internet (from the cluster YAML).
# self = true lets control-plane and worker talk on every port (kubelet, CNI, 6443).
resource "aws_security_group" "lab" {
  name        = "${var.cluster_name}-sg"
  description = "Lab: SSH, Kubernetes API, node-to-node"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "Kubernetes API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "Node to node (same security group)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "All outbound (package installs, image pulls)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-sg"
  }
}

# Step 5 — control-plane EC2 (cost starts). Until kubeadm, this is only Ubuntu.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "tls_private_key" "lab" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "lab" {
  key_name   = "${var.cluster_name}-ssh"
  public_key = tls_private_key.lab.public_key_openssh
}

resource "local_file" "ssh_private_key" {
  content         = tls_private_key.lab.private_key_openssh
  filename        = abspath(var.ssh_private_key_path)
  file_permission = "0600"
}

resource "aws_instance" "control_plane" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.node_instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.lab.id]
  key_name                    = aws_key_pair.lab.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
  }

  tags = {
    Name = "${var.cluster_name}-cp"
    Role = "control-plane"
  }
}

# Step 6 — worker EC2. Same image, size, subnet, SG, and SSH key as the control plane.
resource "aws_instance" "worker" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.node_instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.lab.id]
  key_name                    = aws_key_pair.lab.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
  }

  tags = {
    Name = "${var.cluster_name}-wk-1"
    Role = "worker"
  }
}

# Additional workers when worker_nodes > 1. First worker stays aws_instance.worker
# so existing Terraform state is not replaced.
resource "aws_instance" "extra_workers" {
  count = var.worker_nodes > 1 ? var.worker_nodes - 1 : 0

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.node_instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.lab.id]
  key_name                    = aws_key_pair.lab.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
  }

  tags = {
    Name = "${var.cluster_name}-wk-${count.index + 2}"
    Role = "worker"
  }
}
