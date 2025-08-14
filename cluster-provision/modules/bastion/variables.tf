variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
}

variable "ami_id" {
  description = "AMI ID for bastion host"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where bastion host will be created"
  type        = string
}

variable "public_subnet_id" {
  description = "Public subnet ID for bastion host"
  type        = string
}

variable "key_name" {
  description = "EC2 Key Pair name for SSH access"
  type        = string
}

variable "instance_type" {
  description = "Instance type for bastion host"
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 20
}

variable "bastion_ssh_cidr_blocks" {
  description = "CIDR blocks allowed for SSH access to bastion host"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Restrict this in production
}

variable "enable_eip" {
  description = "Whether to assign an Elastic IP to bastion host"
  type        = bool
  default     = true
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
