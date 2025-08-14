resource "aws_security_group" "control" {
  name        = "${var.cluster_name}-control-sg"
  description = "Security group for control plane nodes"
  vpc_id      = var.vpc_id

  # API Server (external access) - Keep this for external kubectl access
  ingress {
    from_port   = var.api_server_port
    to_port     = var.api_server_port
    protocol    = "tcp"
    cidr_blocks = var.api_server_cidr_blocks
  }

  # SSH - Keep this for external SSH access
  ingress {
    from_port   = var.ssh_port
    to_port     = var.ssh_port
    protocol    = "tcp"
    cidr_blocks = var.ssh_cidr_blocks
  }

  # All traffic within VPC (for simplified debugging)
  # This covers all internal communication including etcd
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-control-sg"
    Type = "control-plane"
  })
}

resource "aws_security_group" "worker" {
  name        = "${var.cluster_name}-worker-sg"
  description = "Security group for worker nodes"
  vpc_id      = var.vpc_id

  # SSH - Keep this for external SSH access
  ingress {
    from_port   = var.ssh_port
    to_port     = var.ssh_port
    protocol    = "tcp"
    cidr_blocks = var.ssh_cidr_blocks
  }

  # NodePort Services - Keep this for external service access
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = var.nodeport_cidr_blocks
  }

  # All traffic within VPC (for simplified debugging)
  # This covers all internal communication including pod networking
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-worker-sg"
    Type = "worker"
  })
}

# NLB Security Group (AWS NLB now supports security groups as of 2023+)
resource "aws_security_group" "nlb" {
  name        = "${var.cluster_name}-nlb-sg"
  description = "Security group for Network Load Balancer"
  vpc_id      = var.vpc_id

  # Allow API server traffic from VPC (internal access)
  ingress {
    from_port   = var.api_server_port
    to_port     = var.api_server_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow external API access (if needed for internet-facing NLB)
  ingress {
    from_port   = var.api_server_port
    to_port     = var.api_server_port
    protocol    = "tcp"
    cidr_blocks = var.api_server_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-nlb-sg"
    Type = "load-balancer"
  })
}

# Outputs
output "control_sg_id" {
  description = "ID of the control plane security group"
  value       = aws_security_group.control.id
}

output "worker_sg_id" {
  description = "ID of the worker security group"
  value       = aws_security_group.worker.id
}

output "control_sg_arn" {
  description = "ARN of the control plane security group"
  value       = aws_security_group.control.arn
}

output "worker_sg_arn" {
  description = "ARN of the worker security group"
  value       = aws_security_group.worker.arn
}

output "nlb_sg_id" {
  description = "ID of the NLB security group"
  value       = aws_security_group.nlb.id
}

output "nlb_sg_arn" {
  description = "ARN of the NLB security group"
  value       = aws_security_group.nlb.arn
}

# Internal NLB Security Group (for worker-to-control-plane communication)
resource "aws_security_group" "internal_nlb" {
  name        = "${var.cluster_name}-internal-nlb-sg"
  description = "Security group for internal NLB (worker-to-control-plane communication)"
  vpc_id      = var.vpc_id

  # API Server access from entire VPC (for flexibility)
  ingress {
    from_port   = var.api_server_port
    to_port     = var.api_server_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "API server access from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-internal-nlb-sg"
    Type = "internal-nlb"
  })
}

# Security group rules for internal NLB (using separate resources)
resource "aws_security_group_rule" "internal_nlb_from_control" {
  type                     = "ingress"
  from_port                = var.api_server_port
  to_port                  = var.api_server_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.control.id
  security_group_id        = aws_security_group.internal_nlb.id
  description              = "API server access from control plane nodes"
}

resource "aws_security_group_rule" "internal_nlb_from_worker" {
  type                     = "ingress"
  from_port                = var.api_server_port
  to_port                  = var.api_server_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.worker.id
  security_group_id        = aws_security_group.internal_nlb.id
  description              = "API server access from worker nodes"
}

output "internal_nlb_sg_id" {
  description = "ID of the internal NLB security group"
  value       = aws_security_group.internal_nlb.id
}

output "internal_nlb_sg_arn" {
  description = "ARN of the internal NLB security group"
  value       = aws_security_group.internal_nlb.arn
}

# Add cross-SG rules after both security groups are created
# Allow all traffic from worker nodes to control nodes
resource "aws_security_group_rule" "worker_to_control" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.worker.id
  security_group_id        = aws_security_group.control.id
  description              = "Allow all traffic from worker nodes"
}

# Allow all traffic from control nodes to worker nodes
resource "aws_security_group_rule" "control_to_worker" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.control.id
  security_group_id        = aws_security_group.worker.id
  description              = "Allow all traffic from control nodes"
}