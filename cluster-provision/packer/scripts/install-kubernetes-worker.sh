#!/bin/bash
# Worker Node Installation Script
# Installs minimal components needed for Kubernetes worker nodes
set -euo pipefail

log() { echo "[$(date '+%H:%M:%S')] $*"; }
error() { log "ERROR: $*" >&2; exit 1; }

log "Starting Kubernetes worker installation..."

# === Debug Environment Variables ===
log "DEBUG: KUBERNETES_VERSION=${KUBERNETES_VERSION:-'NOT_SET'}"
log "DEBUG: CONTAINERD_VERSION=${CONTAINERD_VERSION:-'NOT_SET'}"

# === System Updates and Dependencies ===
log "Installing system dependencies..."
export DEBIAN_FRONTEND=noninteractive

apt-get install -y \
  apt-transport-https \
  ca-certificates \
  curl \
  gpg \
  lsb-release \
  gnupg \
  unzip \
  jq || error "Failed to install system dependencies"

# === Install AWS CLI ===
log "Installing AWS CLI..."
if ! command -v aws >/dev/null; then
  curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip -q awscliv2.zip
  ./aws/install --update >/dev/null 2>&1
  rm -rf awscliv2.zip aws/
fi

# === Configure System for Kubernetes ===
log "Configuring system for Kubernetes..."

# Disable swap
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Load kernel modules
cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Configure sysctl
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

# === Install containerd ===
log "Installing containerd..."
# Note: CONTAINERD_VERSION must be set by Packer template
if [ -z "${CONTAINERD_VERSION:-}" ]; then
    error "CONTAINERD_VERSION environment variable not set by Packer template"
fi
log "Using containerd version: $CONTAINERD_VERSION"
apt-get install -y containerd="$CONTAINERD_VERSION" || error "Failed to install containerd"

# Configure containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# Enable SystemdCgroup and set pause image
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sed -i 's|sandbox_image = "registry.k8s.io/pause:3.8"|sandbox_image = "registry.k8s.io/pause:3.10"|' /etc/containerd/config.toml

# Configure crictl
cat <<EOF > /etc/crictl.yaml
runtime-endpoint: unix:///var/run/containerd/containerd.sock
image-endpoint: unix:///var/run/containerd/containerd.sock
timeout: 10
debug: false
EOF

systemctl restart containerd
systemctl enable containerd

# === Install Kubernetes packages ===
log "Installing Kubernetes packages (worker components only)..."

# Add Kubernetes repository
KUBE_MINOR=$(echo $KUBERNETES_VERSION | cut -d. -f1-2)
KUBE_REPO="https://pkgs.k8s.io/core:/stable:/v${KUBE_MINOR}/deb/"

curl -fsSL https://pkgs.k8s.io/core:/stable:/v${KUBE_MINOR}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] $KUBE_REPO /" > /etc/apt/sources.list.d/kubernetes.list

apt-get update -qq

# Install specific versions (worker only needs kubelet and kubeadm for joining)
log "Installing kubelet and kubeadm (kubectl and etcdctl excluded for workers)..."
apt-get install -y \
  kubelet=${KUBERNETES_VERSION}-1.1 \
  kubeadm=${KUBERNETES_VERSION}-1.1

# Hold packages to prevent automatic updates
apt-mark hold kubelet kubeadm containerd

# === Configure services ===
log "Configuring services..."
systemctl enable kubelet

# Set permissions
# chmod 644 /etc/sysctl.d/k8s.conf
# chmod 644 /etc/modules-load.d/k8s.conf

log "Worker installation completed successfully!"
log "Installed versions:"
log "- containerd: $(containerd --version | awk '{print $3}')"
log "- kubelet: $(kubelet --version | awk '{print $2}')"
log "- kubeadm: $(kubeadm version -o short)"
log "Excluded packages (not installed on workers):"
log "- kubectl: not installed (control plane only)"
log "- etcdctl: not installed (control plane only)"
log "- helm: not installed (control plane only)"

log "Note: Final cleanup will be handled by Packer template"
exit 0
