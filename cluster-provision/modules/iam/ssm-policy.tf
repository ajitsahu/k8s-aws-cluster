# SSM Permissions for Control Plane Nodes
resource "aws_iam_role_policy" "control_ssm_policy" {
  name = "${var.cluster_name}-control-ssm-policy"
  role = aws_iam_role.control_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:GetParameter",
          "ssm:DeleteParameter"
        ]
        Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/k8s/${var.cluster_name}/*"
      },
      {
        Effect = "Allow",
        Action = "ssm:DescribeParameters",
        Resource = "*"
      }
    ]
  })
}

# Optional: Restrict SSM access by path
resource "aws_ssm_parameter" "cluster_region" {
  name  = "/k8s/${var.cluster_name}/region"
  type  = "String"
  value = var.region
  tags  = { Environment = "k8s" }
}

# SSM parameters are created by the control plane initialization script
# with the correct values when the cluster is ready. No placeholder parameters needed.

data "aws_caller_identity" "current" {}