# =============================================================================
# AWS INFRASTRUCTURE VARIABLES
# =============================================================================

# AWS Region and Availability Zones
variable "region" {
  description = "AWS region for deployment"
  type        = string
  default     = "ap-south-1"
}

variable "availability_zones" {
  description = "List of availability zones (single AZ for cost optimization)"
  type        = list(string)
  default     = ["ap-south-1a"]  # Single AZ deployment
}

# VPC and Network Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC (65,536 IP addresses)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  description = "Public subnet CIDR blocks (for bastion, NAT gateway, external NLB)"
  type        = list(string)
  default     = ["10.0.1.0/24"]  # 254 usable IPs
}

variable "private_subnets" {
  description = "Private subnet CIDR blocks (for Kubernetes nodes)"
  type        = list(string)
  default     = ["10.0.100.0/22"]  # 1,022 usable IPs (10.0.100.1 - 10.0.103.254)
}

# EC2 Instance Configuration
variable "ssh_key_name" {
  description = "AWS EC2 Key Pair name for SSH access"
  type        = string
  default     = "your-ssh-key"
}

variable "control_instance_type" {
  description = "EC2 instance type for Kubernetes control plane nodes"
  type        = string
  default     = "t3.medium"
}

variable "worker_instance_type" {
  description = "EC2 instance type for Kubernetes worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB for all instances"
  type        = number
  default     = 50
}

# Bastion Host Configuration
variable "bastion_instance_type" {
  description = "EC2 instance type for bastion host (SSH gateway)"
  type        = string
  default     = "t3.micro"
}

variable "bastion_root_volume_size" {
  description = "Root EBS volume size in GB for bastion host"
  type        = number
  default     = 20
}

variable "bastion_ssh_cidr_blocks" {
  description = "CIDR blocks allowed for SSH access to bastion host (restrict in production)"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # SECURITY: Change to your IP range
}

variable "bastion_enable_eip" {
  description = "Whether to assign an Elastic IP to bastion host"
  type        = bool
  default     = true
}

# Load Balancer Configuration
variable "api_load_balancer_scheme" {
  description = "Load balancer scheme for Kubernetes API server (internet-facing or internal)"
  type        = string
  default     = "internet-facing"
}

variable "api_server_port" {
  description = "Port for Kubernetes API server"
  type        = number
  default     = 6443
}

# Resource Tags
variable "tags" {
  description = "Common tags to apply to all AWS resources"
  type        = map(string)
  default = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Project     = "Kubernetes-Cluster"
  }
}

# =============================================================================
# KUBERNETES CLUSTER VARIABLES
# =============================================================================

# Cluster Configuration
variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
  default     = "your-cluster-name"
}

variable "control_count" {
  description = "Number of Kubernetes control plane nodes (HA requires 3+)"
  type        = number
  default     = 3
}

variable "worker_count" {
  description = "Number of Kubernetes worker nodes"
  type        = number
  default     = 3
}

# Kubernetes Network Configuration
variable "pod_cidr" {
  description = "CIDR block for Kubernetes pod network (must not overlap with VPC/Service CIDR)"
  type        = string
  default     = "192.168.0.0/16"  # 192.168.0.0 - 192.168.255.255
}

variable "service_cidr" {
  description = "CIDR block for Kubernetes services (must not overlap with VPC/Pod CIDR)"
  type        = string
  default     = "10.96.0.0/12"  # 10.96.0.0 - 10.111.255.255
}

# Kubernetes Versions
variable "kubernetes_version" {
  description = "Kubernetes version to install"
  type        = string
  default     = "1.32.4"
}

variable "containerd_version" {
  description = "Containerd container runtime version"
  type        = string
  default     = "1.7.27-0ubuntu1~24.04.1"
}

# Security and Access
variable "node_port_range" {
  description = "Port range for Kubernetes NodePort services"
  type        = string
  default     = "30000-32767"
}

variable "ssh_port" {
  description = "SSH port for instance access"
  type        = number
  default     = 22
}

variable "cleanup_wait_seconds" {
  description = "Number of seconds to wait before running cleanup script"
  type        = number
  default     = 60
}
