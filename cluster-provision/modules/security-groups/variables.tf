variable "vpc_id" {}
variable "vpc_cidr" {
  description = "VPC CIDR block for internal access"
  type        = string
}
variable "api_server_port" { type = number }
variable "ssh_port" { type = number }
variable "node_port_range" { type = string }
variable "cluster_name" { type = string }
variable "ssh_cidr_blocks" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "api_server_cidr_blocks" {
  description = "CIDR blocks allowed for API server access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "nodeport_cidr_blocks" {
  description = "CIDR blocks allowed for NodePort service access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "tags" {
  description = "A map of tags to assign to the resources"
  type        = map(string)
  default     = {}
}