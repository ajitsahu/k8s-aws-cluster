provider "aws" {
  region = var.region
}

# Control Plane AMI built with Packer (includes kubectl, etcdctl, helm)
data "aws_ami" "kubernetes_control" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["kubernetes-control-${var.kubernetes_version}-*"]
  }

  filter {
    name   = "tag:Type"
    values = ["control-plane"]
  }

  filter {
    name   = "tag:KubernetesVersion"
    values = [var.kubernetes_version]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Worker AMI built with Packer (minimal runtime components only)
data "aws_ami" "kubernetes_worker" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["kubernetes-worker-${var.kubernetes_version}-*"]
  }

  filter {
    name   = "tag:Type"
    values = ["worker"]
  }

  filter {
    name   = "tag:KubernetesVersion"
    values = [var.kubernetes_version]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Ubuntu AMI for bastion host (general purpose)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-*/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Fallback to Ubuntu base AMI if custom AMI not found
data "aws_ami" "ubuntu_fallback" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-*/ubuntu-noble-24.04-amd64-server-*"]
  }
}

data "aws_vpc" "default" {
  default = true
}