# Kubernetes Cluster Provisioning

Production-grade Kubernetes cluster provisioning on AWS with Terraform.

## 📋 Prerequisites

- **AWS Account** with appropriate permissions
- **AWS CLI** configured (`aws configure`)
- **SSH key pair** uploaded to AWS
- **Terraform 1.5+**
- **Specialized AMIs** built with Packer (control plane + worker)

## 🚀 Quick Start

### 1. Setup Terraform Backend (One-time)
*Creates S3 bucket and DynamoDB table for storing Terraform state securely.*

```bash
# Create S3 bucket and DynamoDB table for state management
./scripts/setup-backend.sh [bucket-name] [region] [dynamodb-table]

# Example:
./scripts/setup-backend.sh your-terraform-state-bucket ap-south-1 terraform-state-lock
```

### 2. Build AMIs (Required)
*Creates specialized AMIs with pre-installed Kubernetes components for faster node provisioning. Generated image will automatically be used by Terraform.*

```bash
# Build specialized AMIs for control plane and worker nodes
cd packer/
# See packer/README.md for detailed instructions
./build-ami.sh
cd ..
```

📖 **[See Packer README for detailed AMI build instructions](./packer/README.md)**

### 3. Configure Variables
*Customizes cluster settings like region, instance types, and network configuration.*

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values
```

### 4. Deploy Cluster
*Provisions AWS infrastructure and initializes the Kubernetes cluster with HA control plane.*

```bash
terraform init
terraform plan
terraform apply
```

### 5. Synchronize etcd (Post-deployment)
*Ensures consistent etcd cluster configuration across all control plane nodes.*

```bash
# SSH to each control node and run:
sudo /home/ubuntu/sync-etcd.sh
```

### 6. Install CNI (Required for Pod Networking)
*Installs Calico CNI to enable pod-to-pod communication and network policies.*

```bash
# Install Calico CNI for pod networking
cd ../cluster-addons/calico/
./install-calico.sh
cd ../../cluster-provision/
```

📖 **[See Calico README for detailed CNI installation instructions](../cluster-addons/calico/README.md)**

## 📋 Kubeconfig

```bash
terraform output -raw kubeconfig > ~/.kube/config
chmod 600 ~/.kube/config
```

## 🛠️ Utility Scripts

- **`setup-backend.sh`** - Create S3 bucket and DynamoDB table for Terraform state
- **`cleanup-backend.sh`** - Delete backend resources when no longer needed
- **`verify-control-plane.sh`** - Check control plane SSM parameters
- **`refresh-join-tokens.sh`** - Refresh expired join tokens
- **`sync-etcd.sh`** - Synchronize etcd cluster configuration (run on each control node)
