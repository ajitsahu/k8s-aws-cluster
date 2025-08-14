# This data source will be populated once the first control plane node creates the certificates
# Using try() to handle cases where parameters don't exist yet during initial deployment
data "aws_ssm_parameter" "ca_cert" {
  count = var.control_count > 0 ? 1 : 0
  name = "/k8s/${var.cluster_name}/ca-cert"
  depends_on = [module.control, null_resource.wait_for_control_init]
}

data "aws_ssm_parameter" "client_cert" {
  count = var.control_count > 0 ? 1 : 0
  name = "/k8s/${var.cluster_name}/client-cert"
  depends_on = [module.control, null_resource.wait_for_control_init]
}

data "aws_ssm_parameter" "client_key" {
  count = var.control_count > 0 ? 1 : 0
  name = "/k8s/${var.cluster_name}/client-key"
  depends_on = [module.control, null_resource.wait_for_control_init]
}

# Generate kubeconfig content as a local value for reuse
locals {
  kubeconfig_content = var.control_count > 0 && length(data.aws_ssm_parameter.ca_cert) > 0 ? (
    <<-EOF
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: ${data.aws_ssm_parameter.ca_cert[0].value}
    server: https://${module.nlb.lb_dns_name}:${var.api_server_port}
  name: ${var.cluster_name}
contexts:
- context:
    cluster: ${var.cluster_name}
    user: admin
  name: admin@${var.cluster_name}
current-context: admin@${var.cluster_name}
kind: Config
users:
- name: admin
  user:
    client-certificate-data: ${data.aws_ssm_parameter.client_cert[0].value}
    client-key-data: ${data.aws_ssm_parameter.client_key[0].value}
EOF
  ) : null
}

# Save kubeconfig to local file
resource "local_file" "kubeconfig" {
  count    = local.kubeconfig_content != null ? 1 : 0
  filename = "${path.module}/kubeconfig"
  content  = local.kubeconfig_content
  
  depends_on = [
    data.aws_ssm_parameter.ca_cert,
    data.aws_ssm_parameter.client_cert,
    data.aws_ssm_parameter.client_key
  ]
}

output "kubeconfig" {
  value = local.kubeconfig_content != null ? local.kubeconfig_content : "Kubeconfig will be available after control plane initialization completes. Please wait 2-3 minutes after deployment."
  sensitive = true
}

output "kubeconfig_file" {
  value = local.kubeconfig_content != null ? "${path.module}/kubeconfig" : "Kubeconfig file will be created after control plane initialization completes."
  description = "Path to the generated kubeconfig file"
  sensitive = true
}



output "worker_instance_ids" {
  description = "List of worker instance IDs"
  value = module.workers.instance_ids
}



output "api_server_lb_dns" {
  description = "DNS name of the internet-facing NLB for external access"
  value = module.nlb.lb_dns_name
}

output "internal_api_server_lb_dns" {
  description = "DNS name of the internal NLB for worker-to-control-plane communication"
  value = module.internal_nlb.lb_dns_name
}