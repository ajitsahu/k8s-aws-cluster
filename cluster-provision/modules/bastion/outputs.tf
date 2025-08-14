output "bastion_instance_id" {
  description = "ID of the bastion host instance"
  value       = aws_instance.bastion.id
}

output "bastion_public_ip" {
  description = "Public IP of the bastion host"
  value       = aws_instance.bastion.public_ip
}

output "bastion_private_ip" {
  description = "Private IP of the bastion host"
  value       = aws_instance.bastion.private_ip
}

output "bastion_eip" {
  description = "Elastic IP of the bastion host (if enabled)"
  value       = var.enable_eip ? aws_eip.bastion[0].public_ip : null
}

output "bastion_security_group_id" {
  description = "Security group ID of the bastion host"
  value       = aws_security_group.bastion.id
}

output "ssh_command" {
  description = "SSH command to connect to bastion host"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${var.enable_eip ? aws_eip.bastion[0].public_ip : aws_instance.bastion.public_ip}"
}
