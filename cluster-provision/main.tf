# main.tf

# DISABLED: Cleanup resource that was deleting join parameters during deployment
# This was causing control-1 and control-2 to fail joining the cluster
# TODO: Re-enable with proper logic after deployment is stable
/*
resource "null_resource" "cleanup_stale_ssm" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "🧹 Cleaning up potentially stale SSM parameters for fresh deployment..."
      aws ssm delete-parameter --name "/k8s/${var.cluster_name}/control-plane-endpoint" --region ${var.region} 2>/dev/null || echo "  control-plane-endpoint: not found (OK)"
      aws ssm delete-parameter --name "/k8s/${var.cluster_name}/join-token" --region ${var.region} 2>/dev/null || echo "  join-token: not found (OK)"
      aws ssm delete-parameter --name "/k8s/${var.cluster_name}/cert-key" --region ${var.region} 2>/dev/null || echo "  cert-key: not found (OK)"
      aws ssm delete-parameter --name "/k8s/${var.cluster_name}/cacert-hash" --region ${var.region} 2>/dev/null || echo "  cacert-hash: not found (OK)"
      aws ssm delete-parameter --name "/k8s/${var.cluster_name}/token-created" --region ${var.region} 2>/dev/null || echo "  token-created: not found (OK)"
      echo "✅ SSM parameter cleanup completed"
    EOT
  }
  
  # Run cleanup only on initial deployment (not for scaling)
  triggers = {
    cluster_name = var.cluster_name
    region       = var.region
    # Removed control_count to preserve SSM parameters during HA scaling
    # Removed control_instance_type to avoid cleanup during instance type changes
    # Only cleanup on cluster name/region changes (new deployments)
  }
}
*/

module "vpc" {
  source = "./modules/vpc"

  name            = "${var.cluster_name}-vpc"
  cidr            = var.vpc_cidr
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets
  azs             = var.availability_zones
}

module "security_groups" {
  source = "./modules/security-groups"

  vpc_id   = module.vpc.vpc_id
  vpc_cidr = module.vpc.vpc_cidr

  api_server_port = var.api_server_port
  ssh_port        = var.ssh_port
  node_port_range = var.node_port_range
  cluster_name    = var.cluster_name
  tags            = var.tags
  
  # Security CIDR restrictions - using same blocks as bastion host
  ssh_cidr_blocks        = var.bastion_ssh_cidr_blocks
  api_server_cidr_blocks = var.bastion_ssh_cidr_blocks
  nodeport_cidr_blocks   = var.bastion_ssh_cidr_blocks
}

module "iam" {
  source = "./modules/iam"

  cluster_name = var.cluster_name
  region       = var.region
  tags         = var.tags
}

# Bastion Host for secure SSH access to private nodes
module "bastion" {
  source = "./modules/bastion"

  cluster_name            = var.cluster_name
  ami_id                  = data.aws_ami.ubuntu.id
  vpc_id                  = module.vpc.vpc_id
  public_subnet_id        = module.vpc.public_subnets[0]  # First public subnet
  key_name                = var.ssh_key_name
  instance_type           = var.bastion_instance_type
  root_volume_size        = var.bastion_root_volume_size
  bastion_ssh_cidr_blocks = var.bastion_ssh_cidr_blocks
  enable_eip              = var.bastion_enable_eip
  aws_region              = var.region
  tags                    = var.tags
}

# Internet-facing NLB for external kubectl access
module "nlb" {
  source = "./modules/nlb"

  subnet_ids           = module.vpc.public_subnets
  vpc_id               = module.vpc.vpc_id
  target_group_port    = var.api_server_port
  load_balancer_scheme = "internet-facing"
  security_group_ids   = [module.security_groups.nlb_sg_id]
  cluster_name         = var.cluster_name
  # No shared_target_group_arn - let module create its own
  tags                 = var.tags
}

# Internal NLB for worker-to-control-plane communication
module "internal_nlb" {
  source = "./modules/nlb"

  subnet_ids           = module.vpc.public_subnets  # Same subnets as control nodes (single AZ)
  vpc_id               = module.vpc.vpc_id
  target_group_port    = var.api_server_port
  load_balancer_scheme = "internal"  # Internal load balancer
  security_group_ids   = [module.security_groups.internal_nlb_sg_id]  # Separate SG for internal NLB
  cluster_name         = "${var.cluster_name}-internal"
  # No shared_target_group_arn - let module create its own
  tags                 = var.tags
}

module "control" {
  source = "./modules/control"

  # Explicit dependency to ensure both NLBs are fully created before control plane init
  depends_on = [module.nlb, module.internal_nlb]

  control_count        = var.control_count
  instance_type        = var.control_instance_type
  ami                  = data.aws_ami.kubernetes_control.id
  ssh_key_name         = var.ssh_key_name
  subnet_ids           = module.vpc.private_subnets
  security_group_ids   = [module.security_groups.control_sg_id]
  iam_role_name        = module.iam.control_iam_role_name
  cluster_name         = var.cluster_name
  pod_cidr             = var.pod_cidr
  service_cidr         = var.service_cidr
  nlb_dns_name         = module.nlb.lb_dns_name
  internal_nlb_dns_name = module.internal_nlb.lb_dns_name
  scripts_path         = "${path.module}/scripts"
  root_volume_size     = var.root_volume_size
  kubernetes_version   = var.kubernetes_version
  containerd_version   = var.containerd_version
  region               = var.region
  tags                 = var.tags
}

# Attach control nodes to internet-facing NLB target group
resource "aws_lb_target_group_attachment" "control_external" {
  count            = var.control_count
  target_group_arn = module.nlb.target_group_arn
  port             = var.api_server_port
  target_id        = module.control.instance_ids[count.index]
  
  # Wait for control plane initialization to complete before attaching to NLB
  depends_on = [null_resource.wait_for_control_init]
  
  # Ensure proper lifecycle management
  lifecycle {
    create_before_destroy = false
  }
}

# Attach control nodes to internal NLB target group
resource "aws_lb_target_group_attachment" "control_internal" {
  count            = var.control_count
  target_group_arn = module.internal_nlb.target_group_arn
  port             = var.api_server_port
  target_id        = module.control.instance_ids[count.index]
  
  # Wait for control plane initialization to complete before attaching to NLB
  depends_on = [null_resource.wait_for_control_init]
  
  # Ensure proper lifecycle management
  lifecycle {
    create_before_destroy = false
  }
}

# Wait for control plane to be fully initialized - now handled by control module health check
# This resource is kept for backward compatibility but now just depends on control module health check
resource "null_resource" "wait_for_control_init" {
  depends_on = [module.control.health_check_complete]
  
  provisioner "local-exec" {
    command = "echo '[$(date)] Control plane initialization verified by module health check'"
  }
}

resource "null_resource" "cleanup_secrets" {
  depends_on = [
    module.control,
    module.workers  # Wait for ALL nodes to join before cleanup
  ]

  provisioner "local-exec" {
    command = "sleep ${var.cleanup_wait_seconds} && ${path.module}/scripts/cleanup-secrets.sh ${var.cluster_name}"
    working_dir = path.module
  }
}

module "workers" {
  source = "./modules/workers"
  
  # Workers must wait for control plane initialization to complete
  depends_on = [null_resource.wait_for_control_init]

  instance_type      = var.worker_instance_type
  ami                = data.aws_ami.kubernetes_worker.id
  ssh_key_name       = var.ssh_key_name
  subnet_ids         = module.vpc.private_subnets
  security_group_ids = [module.security_groups.worker_sg_id]
  iam_role_name      = module.iam.worker_iam_role_name
  desired_size       = var.worker_count
  cluster_name       = var.cluster_name
  root_volume_size   = var.root_volume_size
  kubernetes_version = var.kubernetes_version
  containerd_version = var.containerd_version
  region             = var.region
  tags               = var.tags
  scripts_path       = "${path.module}/scripts"
  nlb_dns_name       = module.nlb.lb_dns_name
  internal_nlb_dns_name = module.internal_nlb.lb_dns_name
}