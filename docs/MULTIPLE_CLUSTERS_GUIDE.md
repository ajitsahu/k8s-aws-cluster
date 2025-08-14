# Multiple Kubernetes Clusters Deployment Guide

This guide covers the precautions and configurations needed to deploy multiple Kubernetes clusters without conflicts.

## 🔧 Required Changes

### 1. **Terraform State Separation** (Critical)
Each cluster needs its own Terraform state to avoid conflicts:

**Option A: Different S3 state keys**
```hcl
# backend.tf for cluster-1
terraform {
  backend "s3" {
    bucket = "your-terraform-state-bucket"
    key    = "k8s-cluster-1/terraform.tfstate"  # Different key
    region = "ap-south-1"
    dynamodb_table = "terraform-state-lock"
  }
}

# backend.tf for cluster-2
terraform {
  backend "s3" {
    bucket = "your-terraform-state-bucket"
    key    = "k8s-cluster-2/terraform.tfstate"  # Different key
    region = "ap-south-1"
    dynamodb_table = "terraform-state-lock"
  }
}
```

**Option B: Terraform workspaces**
```bash
terraform workspace new cluster-1
terraform workspace new cluster-2
terraform workspace select cluster-1
```

### 2. **Network Isolation**
Ensure VPC CIDR blocks don't overlap:

```hcl
# terraform.tfvars for cluster-1
vpc_cidr = "10.0.0.0/16"
public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.20.0/24"]

# terraform.tfvars for cluster-2
vpc_cidr = "10.1.0.0/16"  # Different CIDR range
public_subnet_cidrs = ["10.1.1.0/24", "10.1.2.0/24"]
private_subnet_cidrs = ["10.1.10.0/24", "10.1.20.0/24"]
```

### 3. **Resource Naming**
Beyond `cluster_name`, ensure unique names for:

```hcl
# terraform.tfvars
cluster_name = "prod-cluster"           # Unique cluster name
vpc_name = "prod-vpc"                   # Unique VPC name
# Any other resource prefixes should be unique
```

### 4. **Load Balancer and DNS**
If using custom domain names or load balancers, ensure they don't conflict:

```hcl
# Different load balancer names and DNS entries
nlb_name = "prod-k8s-nlb"  # vs "staging-k8s-nlb"
```

## 📁 Recommended Directory Structure

```
k8s-clusters/
├── cluster-prod/
│   ├── backend.tf          # Different state key
│   ├── terraform.tfvars    # Prod-specific values
│   └── [other tf files]
├── cluster-staging/
│   ├── backend.tf          # Different state key
│   ├── terraform.tfvars    # Staging-specific values
│   └── [other tf files]
└── modules/                # Shared modules
    ├── iam/
    ├── vpc/
    └── [other modules]
```

## 🔒 Security Considerations

### 1. **IAM Resources**
If your modules create IAM roles with fixed names, make them unique:

```hcl
# In your IAM module
resource "aws_iam_role" "control_plane_role" {
  name = "${var.cluster_name}-control-plane-role"  # Uses cluster_name prefix
}
```

### 2. **Parameter Store**
Ensure SSM parameters use unique paths:

```hcl
resource "aws_ssm_parameter" "cluster_ca" {
  name  = "/${var.cluster_name}/cluster-ca"  # Unique path per cluster
  type  = "SecureString"
  value = base64encode(var.cluster_ca)
}
```

## 🚀 Deployment Workflow

```bash
# For each cluster
mkdir cluster-prod cluster-staging

# Copy base configuration
cp -r cluster-provision/* cluster-prod/
cp -r cluster-provision/* cluster-staging/

# Update backend.tf in each directory
# Update terraform.tfvars in each directory

# Deploy each cluster separately
cd cluster-prod
terraform init
terraform apply

cd ../cluster-staging
terraform init
terraform apply
```

## ⚠️ Common Pitfalls to Avoid

1. **Same state file** - Will cause resource conflicts
2. **Overlapping CIDR blocks** - Network routing issues
3. **Hardcoded resource names** - Resource name conflicts
4. **Same SSH key pair** - Security risk if compromised
5. **Same security group rules** - May reference wrong resources

## 🔍 Verification Commands

After deployment, verify isolation:

```bash
# Check different VPCs
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=prod-vpc"
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=staging-vpc"

# Check different clusters
kubectl config get-contexts
kubectl config use-context prod-cluster
kubectl get nodes

kubectl config use-context staging-cluster
kubectl get nodes
```

## 📋 Checklist for Multiple Clusters

Before deploying a new cluster, ensure:

- [ ] Unique Terraform state key or workspace
- [ ] Non-overlapping VPC CIDR blocks
- [ ] Unique cluster_name in terraform.tfvars
- [ ] Unique resource naming prefixes
- [ ] Separate kubeconfig contexts
- [ ] Different SSH key pairs (recommended)
- [ ] Unique SSM parameter paths
- [ ] Unique IAM role names
- [ ] Different load balancer names
- [ ] Separate directory structure

## 🔄 Managing Multiple Clusters

### Kubeconfig Management
```bash
# Merge multiple kubeconfigs
export KUBECONFIG=~/.kube/config-prod:~/.kube/config-staging
kubectl config view --merge --flatten > ~/.kube/config

# Switch between clusters
kubectl config use-context prod-cluster
kubectl config use-context staging-cluster
```

### Terraform State Management
```bash
# List all workspaces
terraform workspace list

# Switch between workspaces
terraform workspace select prod-cluster
terraform workspace select staging-cluster

# Show current workspace
terraform workspace show
```

## 🎯 Best Practices

1. **Environment Separation**: Use different AWS accounts for prod/staging if possible
2. **Naming Convention**: Establish consistent naming patterns (e.g., `{env}-{purpose}-{resource}`)
3. **Resource Tagging**: Tag all resources with environment and cluster information
4. **State Management**: Use remote state with proper locking
5. **Access Control**: Implement proper IAM policies for each environment
6. **Monitoring**: Set up separate monitoring and logging for each cluster
7. **Backup Strategy**: Implement cluster-specific backup and disaster recovery plans

The key is treating each cluster as a completely separate infrastructure deployment with its own state management and resource naming conventions.
