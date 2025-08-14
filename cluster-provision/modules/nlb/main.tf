resource "aws_lb" "api_server" {
  name               = "${var.cluster_name}-nlb"
  internal           = var.load_balancer_scheme == "internal" ? true : false
  load_balancer_type = "network"
  subnets            = var.subnet_ids
  security_groups    = var.security_group_ids  # AWS NLB now supports security groups (2023+)

  enable_deletion_protection = false
  enable_cross_zone_load_balancing = true

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-nlb"
  })
}

# Create target group only if not using a shared one
resource "aws_lb_target_group" "api_target" {
  count       = var.shared_target_group_arn == null ? 1 : 0
  name        = "${var.cluster_name}-api-tg"
  port        = var.target_group_port
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 6
    interval            = 30
    port                = var.target_group_port
    protocol            = "HTTPS"
    path                = "/healthz"
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-api-tg"
  })
}

# Use shared target group or the one we created
locals {
  target_group_arn = var.shared_target_group_arn != null ? var.shared_target_group_arn : aws_lb_target_group.api_target[0].arn
}

resource "aws_lb_listener" "api_listener" {
  load_balancer_arn = aws_lb.api_server.arn
  port              = var.target_group_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = local.target_group_arn
  }
}



# Outputs
output "lb_dns_name" {
  description = "DNS name of the Network Load Balancer"
  value       = aws_lb.api_server.dns_name
}

output "lb_arn" {
  description = "ARN of the Network Load Balancer"
  value       = aws_lb.api_server.arn
}

output "target_group_arn" {
  description = "ARN of the target group (shared or created)"
  value       = local.target_group_arn
}