#!/bin/bash
# First Control Node Initialization Script
set -euo pipefail

log() { echo "[$(date '+%H:%M:%S')] $*"; }
error() { log "ERROR: $*" >&2; exit 1; }

log "Initializing FIRST control plane node..."

# Set variables from template
CLUSTER_NAME="${CLUSTER_NAME}"
POD_CIDR="${POD_CIDR}"
SERVICE_CIDR="${SERVICE_CIDR}"
EXTERNAL_NLB_DNS_NAME="${EXTERNAL_NLB_DNS_NAME}"
INTERNAL_NLB_DNS_NAME="${INTERNAL_NLB_DNS_NAME}"
KUBERNETES_VERSION="${KUBERNETES_VERSION}"
AWS_REGION="${AWS_REGION}"

# === Pre-flight checks ===
log "Running pre-flight checks..."
if ! systemctl is-active --quiet containerd; then
  error "containerd is not running"
fi
log "containerd is running"

if ! curl -s --connect-timeout 10 -m 15 https://registry.k8s.io > /dev/null; then
  log "Warning: Cannot reach registry.k8s.io"
else
  log "Container registry connectivity OK"
fi

# === Node Identity ===
log "Node identity managed by AMI-level cleanup"

# Initialize first control plane node
log "Initializing first control plane node..."

INIT_ENDPOINT="$(hostname -i):6443"
log "Local IP endpoint: $INIT_ENDPOINT"
log "External NLB DNS: ${EXTERNAL_NLB_DNS_NAME}"
log "Internal NLB DNS: ${INTERNAL_NLB_DNS_NAME}"

# Create kubeadm configuration
log "Creating kubeadm configuration..."
cat > /tmp/kubeadm-config.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
clusterName: "$CLUSTER_NAME"
kubernetesVersion: v$KUBERNETES_VERSION
controlPlaneEndpoint: "$INIT_ENDPOINT"
networking:
  podSubnet: "$POD_CIDR"
  serviceSubnet: "$SERVICE_CIDR"
apiServer:
  certSANs:
  - "${EXTERNAL_NLB_DNS_NAME}"
  - "${INTERNAL_NLB_DNS_NAME}"
  - "localhost"
  - "127.0.0.1"
  - "kubernetes"
  - "kubernetes.default"
  - "kubernetes.default.svc"
  - "kubernetes.default.svc.cluster.local"
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: "$(hostname -i)"
  bindPort: 6443
nodeRegistration:
  name: "$(hostname -s)"
  criSocket: "unix:///var/run/containerd/containerd.sock"
EOF

log "kubeadm configuration created"

# Run kubeadm init
log "Running kubeadm init..."
kubeadm init --config /tmp/kubeadm-config.yaml --v=5 || error "kubeadm init failed"

# Store cluster join information
log "Creating fresh bootstrap token..."
JOIN_TOKEN=$(kubeadm token create --ttl 24h)
if [ -z "$JOIN_TOKEN" ]; then
    error "Failed to create bootstrap token"
fi
log "Created join token: $${JOIN_TOKEN:0:6}..."

CERT_KEY=$(kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -1)
CACERT_HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')

# Validate AWS CLI
log "Validating AWS CLI configuration..."
if ! aws sts get-caller-identity --region "$AWS_REGION" >/dev/null 2>&1; then
    error "AWS CLI not configured properly"
fi
log "✓ AWS CLI configured"

# Test SSM access
if ! aws ssm describe-parameters --region "$AWS_REGION" --max-items 1 >/dev/null 2>&1; then
    error "No SSM access - check IAM permissions"
fi
log "✓ SSM access confirmed"

# Store in SSM Parameter Store
log "Storing join parameters in SSM..."
aws ssm put-parameter --region "$AWS_REGION" --name "/k8s/$CLUSTER_NAME/join-token" --value "$JOIN_TOKEN" --type "SecureString" --overwrite || error "Failed to store join-token"
log "✓ Stored join-token"

aws ssm put-parameter --region "$AWS_REGION" --name "/k8s/$CLUSTER_NAME/cert-key" --value "$CERT_KEY" --type "SecureString" --overwrite || error "Failed to store cert-key"
log "✓ Stored cert-key"

aws ssm put-parameter --region "$AWS_REGION" --name "/k8s/$CLUSTER_NAME/cacert-hash" --value "sha256:$CACERT_HASH" --type "SecureString" --overwrite || error "Failed to store cacert-hash"
log "✓ Stored cacert-hash"

aws ssm put-parameter --region "$AWS_REGION" --name "/k8s/$CLUSTER_NAME/control-plane-endpoint" --value "$INTERNAL_NLB_DNS_NAME" --type "SecureString" --overwrite || error "Failed to store control-plane-endpoint"
log "✓ Stored control-plane-endpoint"

aws ssm put-parameter --region "$AWS_REGION" --name "/k8s/$CLUSTER_NAME/token-created" --value "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --type "String" --overwrite || error "Failed to store token-created"
log "✓ Stored token-created timestamp"

# Store certificates for kubeconfig
CA_CERT=$(base64 -w 0 /etc/kubernetes/pki/ca.crt)
CLIENT_CERT=$(base64 -w 0 /etc/kubernetes/pki/apiserver-kubelet-client.crt)
CLIENT_KEY=$(base64 -w 0 /etc/kubernetes/pki/apiserver-kubelet-client.key)

aws ssm put-parameter --region "$AWS_REGION" --name "/k8s/$CLUSTER_NAME/ca-cert" --value "$CA_CERT" --type "String" --overwrite
aws ssm put-parameter --region "$AWS_REGION" --name "/k8s/$CLUSTER_NAME/client-cert" --value "$CLIENT_CERT" --type "String" --overwrite
aws ssm put-parameter --region "$AWS_REGION" --name "/k8s/$CLUSTER_NAME/client-key" --value "$CLIENT_KEY" --type "String" --overwrite

log "First control plane node initialized successfully"

# === Common Configuration ===
USER_HOME="/home/ubuntu"

log "Setting up kubeconfig for $(basename $${USER_HOME})"
mkdir -p "$${USER_HOME}/.kube"
cp /etc/kubernetes/admin.conf "$${USER_HOME}/.kube/config"
chown -R $(stat -c "%u:%g" "$${USER_HOME}") "$${USER_HOME}/.kube" || true

# Setup kubectl for root
mkdir -p /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config

# Create completion marker
aws ssm put-parameter --region "$AWS_REGION" --name "/k8s/$CLUSTER_NAME/control-ready-0" --value "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --type "String" --overwrite

log "First control plane node is fully ready"
