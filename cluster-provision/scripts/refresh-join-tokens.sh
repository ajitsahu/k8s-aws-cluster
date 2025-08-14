#!/bin/bash
# refresh-join-tokens.sh
# Script to refresh kubeadm join tokens when they expire
# Should be run on the control plane node

set -euo pipefail

CLUSTER_NAME="${1:-}"
AWS_REGION="${2:-ap-south-1}"

if [ -z "$CLUSTER_NAME" ]; then
    echo "Usage: $0 <cluster-name> [aws-region]"
    exit 1
fi

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "Refreshing join tokens for cluster: $CLUSTER_NAME"

# Check if we're on a control plane node
if ! command -v kubeadm >/dev/null 2>&1; then
    log "ERROR: kubeadm not found. This script must run on a control plane node."
    exit 1
fi

# Check if kubernetes is running
if ! kubectl get nodes >/dev/null 2>&1; then
    log "ERROR: Cannot connect to Kubernetes API. Ensure this is a control plane node."
    exit 1
fi

# Generate new join token (72 hour TTL)
log "Generating new join token..."
NEW_JOIN_TOKEN=$(kubeadm token create --ttl 72h0m0s)

# Get CA cert hash
CACERT_HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')

# Get internal NLB endpoint from existing SSM parameter
INTERNAL_NLB_DNS_NAME=$(aws ssm get-parameter --region "$AWS_REGION" --name "/k8s/$CLUSTER_NAME/control-plane-endpoint" --with-decryption --query 'Parameter.Value' --output text 2>/dev/null || echo "")

if [ -z "$INTERNAL_NLB_DNS_NAME" ]; then
    log "ERROR: Could not retrieve control plane endpoint from SSM"
    exit 1
fi

# Update SSM parameters
log "Updating SSM parameters..."
aws ssm put-parameter --region "$AWS_REGION" --name "/k8s/$CLUSTER_NAME/join-token" --value "$NEW_JOIN_TOKEN" --type "SecureString" --overwrite
aws ssm put-parameter --region "$AWS_REGION" --name "/k8s/$CLUSTER_NAME/cacert-hash" --value "sha256:$CACERT_HASH" --type "SecureString" --overwrite
aws ssm put-parameter --region "$AWS_REGION" --name "/k8s/$CLUSTER_NAME/control-plane-endpoint" --value "$INTERNAL_NLB_DNS_NAME" --type "SecureString" --overwrite
aws ssm put-parameter --region "$AWS_REGION" --name "/k8s/$CLUSTER_NAME/token-created" --value "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --type "String" --overwrite

log "Join tokens refreshed successfully!"
log "New token ID: $(echo $NEW_JOIN_TOKEN | cut -d. -f1)"
log "Token valid for: 72 hours"
log "CA hash: sha256:$CACERT_HASH"
log "Endpoint: $INTERNAL_NLB_DNS_NAME"
