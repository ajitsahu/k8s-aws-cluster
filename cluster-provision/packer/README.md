# Kubernetes AMI Builder

Build specialized AMIs for control plane and worker nodes with pre-installed Kubernetes components.

## 🚀 **Quick Start**

1. **Configure variables**:
   ```bash
   # Edit variables.pkrvars.hcl to match your terraform.tfvars
   # These values should match ../terraform.tfvars for consistency
   kubernetes_version = "1.32.4"  # Must match terraform.tfvars
   cluster_name = "your-cluster-name"   # Must match terraform.tfvars
   region = "ap-south-1"          # Must match terraform.tfvars
   ```
   
   ⚠️ **Important**: Keep these values synchronized with `../terraform.tfvars`

2. **Build AMIs**:
   ```bash
   cd packer/
   
   # Build control plane AMI (includes kubectl, etcdctl, helm)
   packer build -var-file=variables.pkrvars.hcl kubernetes-control.pkr.hcl
   
   # Build worker AMI (minimal - kubelet + kubeadm only)
   packer build -var-file=variables.pkrvars.hcl kubernetes-worker.pkr.hcl
   
   # Or build both sequentially
   ./build-ami.sh  # if updated to build both
   ```

3. **Validate AMIs** (optional):
   ```bash
   ./validate-ami.sh your-cluster-name 1.32.4 ap-south-1
   ```

4. **Deploy cluster** (uses latest AMIs automatically):
   **[See deployment README for detailed instructions](../README.md)**

## 📋 **Requirements**

- AWS credentials configured
- Packer installed (`brew install packer`)
- EC2/AMI/EBS permissions

## 🎯 **AMI Types**

### **Control Plane AMI** (`kubernetes-control.pkr.hcl`)
- **Includes:** kubelet, kubeadm, kubectl, etcdctl, helm, AWS CLI
- **Purpose:** Control plane nodes with full cluster management capabilities
- **Size:** ~2GB (includes all management tools)

### **Worker AMI** (`kubernetes-worker.pkr.hcl`)
- **Includes:** kubelet, kubeadm, AWS CLI
- **Excludes:** kubectl, etcdctl, helm (security/optimization)
- **Purpose:** Worker nodes with minimal runtime components
- **Size:** ~1.5GB (optimized for workers)

## 🚨 **Troubleshooting**

### **Build Failures**:
1. Check AWS credentials and permissions
2. Verify region and VPC settings
3. Review Packer logs for specific errors
4. Ensure base Ubuntu AMI is available

### **Terraform Integration**:
1. Verify AMI exists in correct region
2. Check AMI tags match Terraform filters
3. Ensure AMI is in "available" state

### **Instance Boot Issues**:
1. Check user data script syntax
2. Verify SSM parameters exist
3. Review EC2 instance logs via AWS Console