#!/bin/bash
# Validate Custom Kubernetes AMIs (Control Plane and Worker)
set -euo pipefail

log() { echo "[$(date '+%H:%M:%S')] $*"; }
error() { log "ERROR: $*" >&2; exit 1; }

# Check if required tools are installed
command -v aws >/dev/null || error "AWS CLI not installed"
command -v jq >/dev/null || error "jq not installed"

# Get variables
CLUSTER_NAME="${1:-your-cluster-name}"
KUBERNETES_VERSION="${2:-1.32.4}"
REGION="${3:-ap-south-1}"
AMI_TYPE="${4:-both}"  # control, worker, or both

log "Validating Kubernetes AMIs for cluster: $CLUSTER_NAME"
log "Kubernetes version: $KUBERNETES_VERSION"
log "Region: $REGION"
log "AMI type: $AMI_TYPE"

validate_ami() {
    local ami_name_pattern="$1"
    local type_display="$2"
    local tag_type="$3"
    
    log ""
    log "🔍 Searching for $type_display AMI..."
    
    # Find the most recent AMI for this type
    local ami_id
    ami_id=$(aws ec2 describe-images \
      --region "$REGION" \
      --owners self \
      --filters \
        "Name=name,Values=kubernetes-${ami_name_pattern}-${KUBERNETES_VERSION}-*" \
        "Name=tag:Type,Values=${tag_type}" \
        "Name=state,Values=available" \
      --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
      --output text)

    if [ "$ami_id" = "None" ] || [ -z "$ami_id" ]; then
        log "❌ No $type_display AMI found. Please build AMI first using:"
        log "   packer build -var-file=variables.pkrvars.hcl kubernetes-${ami_name_pattern}.pkr.hcl"
        return 1
    fi

    log "✅ Found $type_display AMI: $ami_id"
    
    # Get AMI details
    local ami_info
    ami_info=$(aws ec2 describe-images \
      --region "$REGION" \
      --image-ids "$ami_id" \
      --output json)

    # Extract details
    local ami_name creation_date k8s_version_tag containerd_version_tag
    ami_name=$(echo "$ami_info" | jq -r '.Images[0].Name')
    creation_date=$(echo "$ami_info" | jq -r '.Images[0].CreationDate')
    k8s_version_tag=$(echo "$ami_info" | jq -r '.Images[0].Tags[] | select(.Key=="KubernetesVersion") | .Value')
    containerd_version_tag=$(echo "$ami_info" | jq -r '.Images[0].Tags[] | select(.Key=="ContainerdVersion") | .Value')

    log "📋 $type_display AMI Details:"
    log "  AMI ID: $ami_id"
    log "  Name: $ami_name"
    log "  Created: $creation_date"
    log "  Kubernetes Version: $k8s_version_tag"
    log "  Containerd Version: $containerd_version_tag"

    # Validate version match
    if [ "$k8s_version_tag" != "$KUBERNETES_VERSION" ]; then
        log "⚠️  WARNING: AMI Kubernetes version ($k8s_version_tag) doesn't match requested version ($KUBERNETES_VERSION)"
        log "   Consider rebuilding AMI with correct version"
    fi

    # Check AMI age
    validate_ami_age "$creation_date" "$type_display"
    
    # Generate Terraform data source
    generate_terraform_data_source "$tag_type" "$ami_id"
    
    return 0
}

validate_ami_age() {
    local creation_date="$1"
    local type_display="$2"
    
    # Check if AMI is recent (less than 30 days old)
    local creation_timestamp=""
    
    # Cross-platform date parsing (works on both Linux and macOS)
    if date -d "$creation_date" +%s >/dev/null 2>&1; then
        # Linux date command
        creation_timestamp=$(date -d "$creation_date" +%s)
    elif date -j -f "%Y-%m-%dT%H:%M:%S.%fZ" "$creation_date" +%s >/dev/null 2>&1; then
        # macOS date command
        creation_timestamp=$(date -j -f "%Y-%m-%dT%H:%M:%S.%fZ" "$creation_date" +%s)
    else
        # Fallback: skip age check
        log "⚠️  Cannot parse creation date format for $type_display AMI, skipping age check"
    fi

    if [ -n "$creation_timestamp" ]; then
        local current_timestamp age_days
        current_timestamp=$(date +%s)
        age_days=$(( (current_timestamp - creation_timestamp) / 86400 ))
        
        if [ $age_days -gt 30 ]; then
            log "⚠️  WARNING: $type_display AMI is $age_days days old. Consider rebuilding for latest security patches"
        else
            log "✅ $type_display AMI age: $age_days days (recent)"
        fi
    fi
}

generate_terraform_data_source() {
    local ami_type="$1"
    local ami_id="$2"
    
    log ""
    log "📄 Terraform data source for $ami_type AMI:"
    cat <<EOF
data "aws_ami" "kubernetes_${ami_type}" {
  most_recent = true
  owners      = ["self"]
  
  filter {
    name   = "tag:Type"
    values = ["${ami_type}"]
  }
  
  filter {
    name   = "tag:KubernetesVersion"
    values = ["${KUBERNETES_VERSION}"]
  }
  
  filter {
    name   = "state"
    values = ["available"]
  }
}
EOF
}

# Main validation logic
VALIDATION_SUCCESS=true

case "$AMI_TYPE" in
    "control"|"control-plane")
        validate_ami "control" "Control Plane" "control-plane" || VALIDATION_SUCCESS=false
        ;;
    "worker")
        validate_ami "worker" "Worker" "worker" || VALIDATION_SUCCESS=false
        ;;
    "both"|*)
        log "🚀 Validating both AMI types..."
        validate_ami "control" "Control Plane" "control-plane" || VALIDATION_SUCCESS=false
        validate_ami "worker" "Worker" "worker" || VALIDATION_SUCCESS=false
        ;;
esac

log ""
if [ "$VALIDATION_SUCCESS" = true ]; then
    log "🎉 All AMI validations completed successfully!"
    log "✅ AMIs are ready to use with Terraform deployment"
    
    if [ "$AMI_TYPE" = "both" ] || [ "$AMI_TYPE" = "*" ]; then
        log ""
        log "💡 Usage in Terraform:"
        log "   Control plane nodes: data.aws_ami.kubernetes_control-plane"
        log "   Worker nodes: data.aws_ami.kubernetes_worker"
    fi
else
    log "❌ AMI validation failed!"
    log "Please build the missing AMIs using:"
    log "  packer build -var-file=variables.pkrvars.hcl kubernetes-control.pkr.hcl"
    log "  packer build -var-file=variables.pkrvars.hcl kubernetes-worker.pkr.hcl"
    exit 1
fi
