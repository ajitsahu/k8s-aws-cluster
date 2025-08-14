packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.8"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

# Variables
variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "kubernetes_version" {
  description = "Kubernetes version to install"
  type        = string
}

variable "containerd_version" {
  description = "Containerd version to install"
  type        = string
}

variable "cluster_name" {
  description = "Cluster name for tagging"
  type        = string
  default     = "k8s-cluster"
}

variable "instance_type" {
  description = "Instance type for building AMI"
  type        = string
  default     = "t3.medium"
}

variable "ssh_username" {
  description = "SSH username for the AMI"
  type        = string
  default     = "ubuntu"
}

# Data source for latest Ubuntu 24.04 LTS AMI
data "amazon-ami" "ubuntu" {
  filters = {
    name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["099720109477"] # Canonical
  region      = var.region
}

# Build configuration
source "amazon-ebs" "kubernetes_worker" {
  ami_name      = "kubernetes-worker-${var.kubernetes_version}-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  instance_type = var.instance_type
  region        = var.region
  
  source_ami    = data.amazon-ami.ubuntu.id
  ssh_username  = var.ssh_username
  
  # Storage configuration
  ebs_optimized = true
  
  launch_block_device_mappings {
    device_name = "/dev/sda1"
    volume_size = 20
    volume_type = "gp3"
    delete_on_termination = true
  }
  
  # Tags for the AMI
  tags = {
    Name                = "kubernetes-worker-${var.kubernetes_version}"
    Type                = "worker"
    KubernetesVersion   = var.kubernetes_version
    ContainerdVersion   = var.containerd_version
    BuildDate           = formatdate("YYYY-MM-DD", timestamp())
    Environment         = "production"
    ManagedBy           = "packer"
  }
  
  # Tags for the build instance
  run_tags = {
    Name = "packer-kubernetes-worker-builder"
    Type = "temporary"
  }
}

# Build steps
build {
  name = "kubernetes-worker"
  sources = ["source.amazon-ebs.kubernetes_worker"]
  
  # Wait for cloud-init to complete
  provisioner "shell" {
    script = "scripts/wait-cloud-init.sh"
    execute_command = "sudo -E bash '{{.Path}}'"
  }
  
  # Update system packages
  provisioner "shell" {
    script = "scripts/update-system.sh"
    execute_command = "sudo -E bash '{{.Path}}'"
  }

  # Copy install script
  provisioner "file" {
    source      = "scripts/install-kubernetes-worker.sh"
    destination = "/tmp/install-kubernetes-worker.sh"
  }
  
  # Install base Kubernetes components (worker only)
  provisioner "shell" {
    inline = [
      "export KUBERNETES_VERSION='${var.kubernetes_version}'",
      "export CONTAINERD_VERSION='${var.containerd_version}'",
      "sudo -E bash /tmp/install-kubernetes-worker.sh"
    ]
  }
  
  # Verify installation
  provisioner "shell" {
    script = "scripts/verify-installation.sh"
    execute_command = "sudo -E bash '{{.Path}}'"
  }
  
  # Final cleanup and preparation
  provisioner "shell" {
    script = "scripts/cleanup-ami.sh"
    execute_command = "sudo -E bash '{{.Path}}'"
  }
  
  # Final validation
  provisioner "shell" {
    inline = [
      "echo 'Validating worker AMI...'",
      "command -v kubeadm || exit 1",
      "command -v kubelet || exit 1", 
      "command -v containerd || exit 1",
      "command -v aws || exit 1",
      "! command -v kubectl && echo 'kubectl correctly excluded'",
      "! command -v etcdctl && echo 'etcdctl correctly excluded'",
      "echo 'Worker AMI validation passed'"
    ]
  }
  
  # Create manifest file
  post-processor "manifest" {
    output = "manifest-worker.json"
    strip_path = true
    custom_data = {
      kubernetes_version = var.kubernetes_version
      containerd_version = var.containerd_version
      build_time        = timestamp()
      base_ami_id       = data.amazon-ami.ubuntu.id
      ami_type          = "worker"
    }
  }
}
