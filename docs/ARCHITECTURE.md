### 🏗️ Infrastructure Components
• **VPC with Public/Private Subnets**: Single AZ deployment (ap-south-1a) for cost optimization
• **High Availability Control Plane**: 3 control nodes for HA etcd cluster
• **Worker Nodes**: Scalable worker node deployment
• **Dual Load Balancers**: External NLB for kubectl access, Internal NLB for worker-to-control communication
• **Bastion Host**: Secure SSH gateway for private node access
• **Security Groups**: Comprehensive network security rules

### 🔧 Automation & Tooling
• **Terraform Modules**: Modular infrastructure as code
• **Packer AMI Building**: Pre-built AMIs with Kubernetes components
• **Shell Scripts**: Cluster initialization, node joining, etcd synchronization
• **Calico CNI**: Pod networking and network policies

### 🛡️ Security & Management
• **IAM Roles**: Separate roles for control and worker nodes
• **Systems Manager**: Parameter store for cluster secrets
• **Terraform State Management**: S3 backend with DynamoDB locking
• **Network Segmentation**: Private subnets for Kubernetes nodes

### 📊 Key Features
• **Production Ready**: HA control plane, security best practices
• **Cost Optimized**: Single AZ deployment, appropriate instance types
• **Automated**: Complete infrastructure provisioning and cluster setup
• **Extensible**: Modular design for easy customization
• **Secure**: Bastion host access, security groups, IAM roles

## Architecture Highlights

The generated diagram shows:
1. External access through Internet Gateway and External NLB
2. Secure SSH access via Bastion host
3. High-availability control plane with 3 nodes and etcd cluster
4. Dual load balancer setup for external and internal communication
5. Comprehensive AWS service integration (IAM, SSM, S3, DynamoDB)
6. Packer-built AMIs for consistent node deployment
7. Calico CNI for pod networking