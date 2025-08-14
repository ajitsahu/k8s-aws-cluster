#!/bin/bash
# Additional Control Node Join Script
set -euo pipefail

log() { echo "[$(date '+%H:%M:%S')] $*"; }
error() { log "ERROR: $*" >&2; exit 1; }

log "Joining additional control plane node..."

# Set variables from template
CLUSTER_NAME="${CLUSTER_NAME}"
INTERNAL_NLB_DNS_NAME="${INTERNAL_NLB_DNS_NAME}"
KUBERNETES_VERSION="${KUBERNETES_VERSION}"
AWS_REGION="${AWS_REGION}"
NODE_INDEX="${NODE_INDEX}"

# === Pre-flight checks ===
log "Running pre-flight checks..."
if ! systemctl is-active --quiet containerd; then
  error "containerd is not running"
fi
log "containerd is running"

# Wait for join parameters
for i in {1..30}; do
    if aws ssm get-parameter --region "$AWS_REGION" --name "/k8s/$CLUSTER_NAME/join-token" --with-decryption >/dev/null 2>&1; then
        break
    fi
    log "Waiting for join parameters... ($i/30)"
    sleep 10
done

# Check token validity
log "Checking token validity..."
TOKEN_CREATED=$(aws ssm get-parameter --region "$AWS_REGION" --name "/k8s/$CLUSTER_NAME/token-created" --query 'Parameter.Value' --output text 2>/dev/null || echo "")

if [ -n "$TOKEN_CREATED" ]; then
    TOKEN_AGE_HOURS=$(( ($(date +%s) - $(date -d "$TOKEN_CREATED" +%s)) / 3600 ))
    log "Current token age: $TOKEN_AGE_HOURS hours"
    
    # Refresh tokens if older than 20 hours
    if [ $TOKEN_AGE_HOURS -gt 20 ]; then
        log "Token is older than 20 hours, refreshing..."
        
        NEW_JOIN_TOKEN=$(kubeadm token create --ttl 72h0m0s)
        NEW_CERT_KEY=$(kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -1)
        
        aws ssm put-parameter --region "$AWS_REGION" --name "/k8s/$CLUSTER_NAME/join-token" --value "$NEW_JOIN_TOKEN" --type "SecureString" --overwrite
        aws ssm put-parameter --region "$AWS_REGION" --name "/k8s/$CLUSTER_NAME/cert-key" --value "$NEW_CERT_KEY" --type "SecureString" --overwrite
        aws ssm put-parameter --region "$AWS_REGION" --name "/k8s/$CLUSTER_NAME/token-created" --value "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --type "String" --overwrite
        
        log "Tokens refreshed successfully"
    fi
fi

# Get join parameters
JOIN_TOKEN=$(aws ssm get-parameter --region "$AWS_REGION" --name "/k8s/$CLUSTER_NAME/join-token" --with-decryption --query 'Parameter.Value' --output text)
CERT_KEY=$(aws ssm get-parameter --region "$AWS_REGION" --name "/k8s/$CLUSTER_NAME/cert-key" --with-decryption --query 'Parameter.Value' --output text)
CACERT_HASH=$(aws ssm get-parameter --region "$AWS_REGION" --name "/k8s/$CLUSTER_NAME/cacert-hash" --with-decryption --query 'Parameter.Value' --output text)

# Validate join parameters
if [ -z "$JOIN_TOKEN" ] || [ -z "$CERT_KEY" ] || [ -z "$CACERT_HASH" ]; then
    error "Missing required join parameters from SSM"
fi

# Join the control plane
log "Joining additional control plane node..."
kubeadm join "$INTERNAL_NLB_DNS_NAME:6443" \
    --token "$JOIN_TOKEN" \
    --discovery-token-ca-cert-hash "$CACERT_HASH" \
    --control-plane \
    --certificate-key "$CERT_KEY" \
    --v=5 || error "Failed to join control plane"

# Setup kubectl for root
mkdir -p /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config

log "Additional control plane node joined successfully"

# === Common Configuration ===
USER_HOME="/home/ubuntu"

log "Setting up kubeconfig for $(basename $${USER_HOME})"
mkdir -p "$${USER_HOME}/.kube"
cp /etc/kubernetes/admin.conf "$${USER_HOME}/.kube/config"
chown -R $(stat -c "%u:%g" "$${USER_HOME}") "$${USER_HOME}/.kube" || true

# === Update kubelet.conf for HA ===
# Update kubelet.conf to use localhost for self-access (HA best practice)
log "Updating kubelet.conf to use localhost for self-access..."

KUBELET_CONF="/etc/kubernetes/kubelet.conf"
BACKUP_CONF="/etc/kubernetes/kubelet.conf.backup"

if [ -f "$${KUBELET_CONF}" ]; then
  # Backup original
  cp "$${KUBELET_CONF}" "$${BACKUP_CONF}"

  # Use localhost as the API server endpoint
  sed -i -E 's|server: https://[^:]+:6443|server: https://127.0.0.1:6443|' "$${KUBELET_CONF}"

  # Restart kubelet to apply the change
  log "Restarting kubelet to apply updated configuration..."
  systemctl restart kubelet

  # Wait and verify kubelet status
  sleep 5
  if systemctl is-active --quiet kubelet; then
    log "Kubelet restarted successfully with localhost endpoint"
  else
    log "Kubelet restart failed. Check with: systemctl status kubelet -l"
  fi
else
  log "kubelet.conf not found at $${KUBELET_CONF}. Skipping update."
fi

# Create completion marker
aws ssm put-parameter --region "$AWS_REGION" --name "/k8s/$CLUSTER_NAME/control-ready-$NODE_INDEX" --value "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --type "String" --overwrite

# etcd cluster synchronization is handled by separate script (sync-etcd-cluster.sh)
# This prevents user_data changes from causing node reboots
log "etcd cluster synchronization deferred to post-deployment script"
log "Run 'sudo bash /path/to/sync-etcd-cluster.sh' after cluster creation to ensure consistency"

log "Control plane node $NODE_INDEX is fully ready"
