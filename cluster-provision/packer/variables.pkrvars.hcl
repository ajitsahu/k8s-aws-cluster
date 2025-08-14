# Packer Variables for Kubernetes AMI Build
# Update these values to match your cluster configuration

# AWS Configuration
region = "ap-south-1"

# Kubernetes Configuration
kubernetes_version = "1.32.4"
containerd_version = "1.7.27-0ubuntu1~24.04.1"

# Cluster Configuration
cluster_name = "your-cluster-name"

# Build Configuration
instance_type = "t2.micro"
ssh_username  = "ubuntu"
