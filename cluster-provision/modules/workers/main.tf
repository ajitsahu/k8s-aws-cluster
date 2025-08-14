resource "aws_instance" "worker" {
  count                     = var.desired_size
  instance_type             = var.instance_type
  ami                       = var.ami
  key_name                  = var.ssh_key_name
  subnet_id                 = var.subnet_ids[count.index % length(var.subnet_ids)]
  vpc_security_group_ids    = var.security_group_ids
  iam_instance_profile      = var.iam_role_name
  associate_public_ip_address = false  # Private subnet - no public IP
  source_dest_check         = false  # Disable source/destination check for Kubernetes networking

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  user_data_base64 = base64encode(<<-EOF
#!/bin/bash
# Execute main worker join script (node identity managed by AMI cleanup)
${templatefile("${var.scripts_path}/join-worker.sh", {
  CLUSTER_NAME           = var.cluster_name
  AWS_REGION            = var.region
  INTERNAL_NLB_DNS_NAME = var.internal_nlb_dns_name
})}
EOF
  )

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-worker-${count.index}"
      Type = "worker"
      Role = "worker"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Launch template removed - using direct EC2 instances for predictable naming

# Outputs
output "instance_ids" {
  description = "List of worker instance IDs"
  value       = aws_instance.worker[*].id
}

output "instance_private_ips" {
  description = "List of worker instance private IP addresses"
  value       = aws_instance.worker[*].private_ip
}
