variable "subnet_ids" {
  description = "List of subnet IDs for the load balancer"
  type        = list(string)
}

variable "target_group_port" {
  description = "Port for the target group"
  type        = number
  default     = 6443
}

variable "load_balancer_scheme" {
  description = "Load balancer scheme (internal or internet-facing)"
  type        = string
  default     = "internet-facing"
}

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the load balancer will be created"
  type        = string
}

variable "tags" {
  description = "A map of tags to assign to the resources"
  type        = map(string)
  default     = {}
}

variable "security_group_ids" {
  description = "List of security group IDs for the NLB (AWS NLB supports security groups as of 2023+)"
  type        = list(string)
  default     = []
}

variable "shared_target_group_arn" {
  description = "ARN of an existing target group to use instead of creating a new one (optional)"
  type        = string
  default     = null
}
