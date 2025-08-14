variable "control_count" {
  description = "Number of control plane nodes"
  type        = number
}

variable "instance_type" {
  description = "EC2 instance type for control plane nodes"
  type        = string
}

variable "ami" {
  description = "AMI ID for control plane nodes"
  type        = string
}

variable "ssh_key_name" {
  description = "SSH key name for control plane nodes"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for control plane nodes"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs for control plane nodes"
  type        = list(string)
}

variable "iam_role_name" {
  description = "IAM role name for control plane nodes"
  type        = string
}

variable "cluster_name" {
  description = "Kubernetes cluster name"
  type        = string
}

variable "pod_cidr" {
  description = "Pod network CIDR"
  type        = string
}

variable "service_cidr" {
  description = "Service CIDR"
  type        = string
}

variable "nlb_dns_name" {
  description = "DNS name of the internet-facing load balancer for API server"
  type        = string
}

variable "internal_nlb_dns_name" {
  description = "DNS name of the internal load balancer for worker-to-control-plane communication"
  type        = string
}

variable "scripts_path" {
  description = "Path to scripts directory"
  type        = string
}



variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 50
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}

variable "kubernetes_version" {
  description = "Kubernetes version to install"
  type        = string
  default     = "1.28.0"
}

variable "containerd_version" {
  description = "Containerd version to install"
  type        = string
  default     = "1.7.27-0ubuntu1~24.04.1"
}

variable "region" {
  description = "AWS region for resources"
  type        = string
}
