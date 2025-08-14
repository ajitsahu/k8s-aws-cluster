#!/bin/bash
# Build Kubernetes AMI using Packer
set -euo pipefail

log() { echo "[$(date '+%H:%M:%S')] $*"; }
error() { log "ERROR: $*" >&2; exit 1; }

# Check if packer is installed
if ! command -v packer >/dev/null 2>&1; then
    error "Packer is not installed. Please install Packer first."
fi

# Check if AWS credentials are configured
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    error "AWS credentials not configured. Please configure AWS CLI."
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log "Starting Kubernetes AMI build..."
log "Build directory: $SCRIPT_DIR"

# Validate Packer templates
log "Validating Packer templates..."
packer validate -var-file="variables.pkrvars.hcl" kubernetes-control.pkr.hcl || error "Control plane template validation failed"
packer validate -var-file="variables.pkrvars.hcl" kubernetes-worker.pkr.hcl || error "Worker template validation failed"

# Build Control Plane AMI
log "Building Kubernetes Control Plane AMI (this will take 10-15 minutes)..."
packer build -var-file="variables.pkrvars.hcl" kubernetes-control.pkr.hcl || error "Control plane AMI build failed"

# Build Worker AMI
log "Building Kubernetes Worker AMI (this will take 10-15 minutes)..."
packer build -var-file="variables.pkrvars.hcl" kubernetes-worker.pkr.hcl || error "Worker AMI build failed"

# Extract AMI ID from manifest
if [ -f "manifest.json" ]; then
    AMI_ID=$(jq -r '.builds[0].artifact_id' manifest.json | cut -d':' -f2)
    REGION=$(jq -r '.builds[0].custom_data.region // "ap-south-1"' manifest.json)
    K8S_VERSION=$(jq -r '.builds[0].custom_data.kubernetes_version' manifest.json)
    
    log "✅ AMI build completed successfully!"
    log "AMI ID: $AMI_ID"
    log "Region: $REGION"
    log "Kubernetes Version: $K8S_VERSION"
    log ""
    log "Next steps:"
    log "1. Update your terraform.tfvars with the new AMI ID"
    log "2. Run 'terraform plan' to see the changes"
    log "3. Run 'terraform apply' to deploy with the new AMI"
    log ""
    log "Terraform data sources are already configured in data.tf:"
    log "  - data.aws_ami.kubernetes_control (for control plane nodes)"
    log "  - data.aws_ami.kubernetes_worker (for worker nodes)"
else
    error "Manifest file not found. Build may have failed."
fi
