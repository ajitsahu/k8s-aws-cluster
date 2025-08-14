resource "aws_instance" "control" {
  count                     = var.control_count
  instance_type             = var.instance_type
  ami                       = var.ami
  key_name                  = var.ssh_key_name
  subnet_id                 = element(var.subnet_ids, count.index % length(var.subnet_ids))
  vpc_security_group_ids    = var.security_group_ids
  iam_instance_profile      = var.iam_role_name
  associate_public_ip_address = false  # Private subnet - no public IP
  source_dest_check         = false  # Disable source/destination check for Kubernetes networking
  user_data_base64          = local.init_scripts[count.index]
  
  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
    tags        = merge(var.tags, { Name = "${var.cluster_name}-control-${count.index + 1}" })
  }
  
  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-control-${count.index}"
      Role = "control-plane"
    }
  )
}

locals {
  # Create separate scripts for first vs additional control nodes
  init_scripts = {
    for i in range(var.control_count) : i => base64encode(templatefile(
      i == 0 ? "${var.scripts_path}/init-control.sh" : "${var.scripts_path}/join-control.sh", {
      CLUSTER_NAME           = var.cluster_name
      POD_CIDR              = var.pod_cidr
      SERVICE_CIDR          = var.service_cidr
      EXTERNAL_NLB_DNS_NAME = var.nlb_dns_name
      INTERNAL_NLB_DNS_NAME = var.internal_nlb_dns_name
      KUBERNETES_VERSION    = var.kubernetes_version
      AWS_REGION            = var.region
      NODE_INDEX            = i
    }))
  }
}

# DISABLED: Complex SSM parameter refresh logic causing deployment failures
# This resource was causing shell syntax errors and SSM command failures
# The init-control-optimized.sh script handles token refresh internally
/*
# Ensure join parameters are available for additional control nodes
resource "null_resource" "ensure_join_parameters" {
  count = var.control_count > 1 ? 1 : 0
  
  depends_on = [
    aws_instance.control,
    null_resource.wait_for_control_init
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo " SSM parameter refresh disabled - handled by init scripts"
      echo " Relying on init-control-optimized.sh for token management"
    EOT
  }
}
*/

# Outputs
output "instance_ids" {
  description = "List of control plane instance IDs"
  value       = aws_instance.control[*].id
}

output "instance_private_ips" {
  description = "List of control plane instance private IP addresses"
  value       = aws_instance.control[*].private_ip
}

output "health_check_complete" {
  description = "Indicates that all control plane nodes have completed their health checks"
  value       = null_resource.control_plane_health_check[*].id
  depends_on  = [null_resource.control_plane_health_check]
}
