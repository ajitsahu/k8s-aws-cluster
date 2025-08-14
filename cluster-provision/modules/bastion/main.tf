# Bastion Host Module for Secure SSH Access to Private Kubernetes Nodes

# Security group for bastion host
resource "aws_security_group" "bastion" {
  name_prefix = "${var.cluster_name}-bastion-"
  vpc_id      = var.vpc_id
  description = "Security group for bastion host - SSH access only"

  # Allow SSH from specified CIDR blocks
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.bastion_ssh_cidr_blocks
  }

  # Allow all outbound traffic (for SSH to private instances)
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-bastion-sg"
    Type = "bastion"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Bastion host instance
resource "aws_instance" "bastion" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.bastion.id]
  subnet_id              = var.public_subnet_id
  
  # Enable detailed monitoring
  monitoring = true
  
  # Disable source/destination checks (not needed for bastion)
  source_dest_check = true

  # Root volume configuration
  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    delete_on_termination = true
    encrypted             = true

    tags = merge(var.tags, {
      Name = "${var.cluster_name}-bastion-root"
    })
  }

  # User data for bastion host setup
  user_data_base64 = base64encode(templatefile("${path.module}/user-data.sh", {
    CLUSTER_NAME = var.cluster_name
    AWS_REGION   = var.aws_region
  }))

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-bastion"
    Type = "bastion"
    Role = "ssh-gateway"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Elastic IP for bastion host (optional but recommended)
resource "aws_eip" "bastion" {
  count    = var.enable_eip ? 1 : 0
  instance = aws_instance.bastion.id
  domain   = "vpc"

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-bastion-eip"
  })

  depends_on = [aws_instance.bastion]
}
