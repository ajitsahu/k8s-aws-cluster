# Health check resource that waits for control plane to be fully ready
resource "null_resource" "control_plane_health_check" {
  count = var.control_count

  depends_on = [aws_instance.control]

  provisioner "local-exec" {
    command = <<-EOT
      echo "[$(date)] Waiting for control plane node ${count.index} to be ready..."
      
      # Get instance ID for this control node
      INSTANCE_ID="${aws_instance.control[count.index].id}"
      
      # Wait for instance to be running and status checks to pass
      echo "[$(date)] Waiting for instance $INSTANCE_ID to pass status checks..."
      aws ec2 wait instance-status-ok --instance-ids $INSTANCE_ID --region ${var.region}
      
      # Wait for SSM parameters to be created by the first control node
      if [ ${count.index} -eq 0 ]; then
        echo "[$(date)] Waiting for first control node to create SSM parameters..."
        for i in {1..60}; do  # Wait up to 30 minutes
          echo "[$(date)] Checking attempt $i/60..."
          
          # Check if all required SSM parameters are available with valid content
          if aws ssm get-parameter --region ${var.region} --name "/k8s/${var.cluster_name}/join-token" --query 'Parameter.Value' --output text >/dev/null 2>&1 && \
             aws ssm get-parameter --region ${var.region} --name "/k8s/${var.cluster_name}/cacert-hash" --query 'Parameter.Value' --output text >/dev/null 2>&1 && \
             aws ssm get-parameter --region ${var.region} --name "/k8s/${var.cluster_name}/control-plane-endpoint" --query 'Parameter.Value' --output text >/dev/null 2>&1 && \
             [ "$(aws ssm get-parameter --region ${var.region} --name "/k8s/${var.cluster_name}/ca-cert" --query 'Parameter.Value' --output text 2>/dev/null | wc -c)" -gt 100 ] && \
             [ "$(aws ssm get-parameter --region ${var.region} --name "/k8s/${var.cluster_name}/client-cert" --query 'Parameter.Value' --output text 2>/dev/null | wc -c)" -gt 100 ] && \
             [ "$(aws ssm get-parameter --region ${var.region} --name "/k8s/${var.cluster_name}/client-key" --query 'Parameter.Value' --output text 2>/dev/null | wc -c)" -gt 100 ]; then
            echo "[$(date)] ✅ Control plane node ${count.index} is ready! All SSM parameters are available."
            break
          fi
          
          if [ $i -eq 60 ]; then
            echo "[$(date)] ❌ Control plane node ${count.index} initialization timed out after 30 minutes"
            exit 1
          fi
          
          echo "[$(date)] Control plane node ${count.index} not ready yet, waiting 30 seconds..."
          sleep 30
        done
      else
        # For additional control nodes, just wait for them to join
        echo "[$(date)] Waiting for additional control node ${count.index} to join..."
        sleep 60  # Give it time to join
      fi
      
      echo "[$(date)] ✅ Control plane node ${count.index} health check completed"
    EOT
  }

  # Trigger recreation if control plane configuration changes
  triggers = {
    instance_id = aws_instance.control[count.index].id
    cluster_name = var.cluster_name
    kubernetes_version = var.kubernetes_version
  }
}
