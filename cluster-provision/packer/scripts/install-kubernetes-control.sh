#!/bin/bash
# Control Plane Node Installation Script
# Installs all components needed for Kubernetes control plane nodes
set -euo pipefail

log() { echo "[$(date '+%H:%M:%S')] $*"; }
error() { log "ERROR: $*" >&2; exit 1; }

log "Starting Kubernetes control plane installation..."

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
log "Installing Kubernetes packages..."

# Add Kubernetes repository
KUBE_MINOR=$(echo $KUBERNETES_VERSION | cut -d. -f1-2)
KUBE_REPO="https://pkgs.k8s.io/core:/stable:/v${KUBE_MINOR}/deb/"

curl -fsSL https://pkgs.k8s.io/core:/stable:/v${KUBE_MINOR}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] $KUBE_REPO /" > /etc/apt/sources.list.d/kubernetes.list

apt-get update -qq

# Install specific versions (control plane needs kubectl, kubelet, kubeadm)
apt-get install -y \
  kubelet=${KUBERNETES_VERSION}-1.1 \
  kubeadm=${KUBERNETES_VERSION}-1.1 \
  kubectl=${KUBERNETES_VERSION}-1.1

# Hold packages to prevent automatic updates
apt-mark hold kubelet kubeadm kubectl containerd

# === Install etcdctl (Dynamic Version Matching) ===
log "Installing etcdctl matching Kubernetes version..."

install_etcdctl() {
    # Get the etcd version that kubeadm will use for this Kubernetes version
    local etcd_version
    etcd_version=$(kubeadm config images list --kubernetes-version="v$KUBERNETES_VERSION" 2>/dev/null | grep etcd | sed 's/.*etcd://' | sed 's/-.*//')
    
    if [ -z "$etcd_version" ]; then
        log "WARNING: Could not determine etcd version from kubeadm, using fallback method..."
        # Fallback: Use version mapping for known Kubernetes versions
        case "$KUBERNETES_VERSION" in
            1.32.*) etcd_version="3.5.17" ;;
            1.31.*) etcd_version="3.5.15" ;;
            1.30.*) etcd_version="3.5.12" ;;
            1.29.*) etcd_version="3.5.10" ;;
            1.28.*) etcd_version="3.5.9" ;;
            *) 
                log "WARNING: Unknown Kubernetes version $KUBERNETES_VERSION, using latest etcd"
                etcd_version="3.5.17"
                ;;
        esac
    fi
    
    log "Installing etcdctl version: $etcd_version"
    
    # Detect architecture
    local arch
    arch=$(uname -m)
    case $arch in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l) arch="arm" ;;
        *) error "Unsupported architecture: $arch" ;;
    esac
    
    # Download etcdctl from GitHub releases
    local download_url="https://github.com/etcd-io/etcd/releases/download/v${etcd_version}/etcd-v${etcd_version}-linux-${arch}.tar.gz"
    log "Downloading etcdctl from: $download_url"
    
    # Download with retries
    local temp_dir="/tmp/etcd-install"
    mkdir -p "$temp_dir"
    cd "$temp_dir"
    
    for i in {1..3}; do
        if curl -L "$download_url" -o etcd.tar.gz; then
            break
        fi
        [ $i -eq 3 ] && error "Failed to download etcdctl after 3 attempts"
        log "Download attempt $i failed, retrying in 5 seconds..."
        sleep 5
    done
    
    # Extract and verify
    tar xzvf etcd.tar.gz --strip-components=1 --no-same-owner
    
    if [ ! -f "./etcdctl" ]; then error "etcdctl binary not found in downloaded archive"; fi
    
    # Install etcdctl
    cp "./etcdctl" /usr/local/bin/etcdctl
    chmod +x /usr/local/bin/etcdctl
    
    # Verify installation
    if ! /usr/local/bin/etcdctl version >/dev/null 2>&1; then
        error "etcdctl installation verification failed"
    fi
    
    local installed_version
    installed_version=$(/usr/local/bin/etcdctl version | head -1 | awk '{print $3}')
    log "✅ etcdctl installed successfully: $installed_version"
    
    # Cleanup
    cd /
    rm -rf "$temp_dir"
}

# Install etcdctl
install_etcdctl

# === Install Helm ===
log "Installing Helm for cluster management..."
if ! command -v helm >/dev/null; then
    # Add Helm repository
    curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | tee /usr/share/keyrings/helm.gpg > /dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | tee /etc/apt/sources.list.d/helm-stable-debian.list
    
    # Update package list and install Helm
    apt-get update -qq
    apt-get install -y helm || error "Failed to install Helm"
    
    log "✅ Helm installed via official repository"
else
    log "✅ Helm already installed"
fi

# === Configure services ===
log "Configuring services..."
systemctl enable kubelet

# Set permissions
# chmod 644 /etc/sysctl.d/k8s.conf
# chmod 644 /etc/modules-load.d/k8s.conf

log "Control plane installation completed successfully!"
log "Installed versions:"
log "- containerd: $(containerd --version | awk '{print $3}')"
log "- kubelet: $(kubelet --version | awk '{print $2}')"
log "- kubeadm: $(kubeadm version -o short)"
log "- kubectl: $(kubectl version --client -o yaml | grep gitVersion | awk '{print $2}')"
log "- etcdctl: $(etcdctl version --cluster=false 2>/dev/null | head -1 | awk '{print $3}' || echo 'not available')"
log "- helm: $(helm version --short 2>/dev/null || echo 'not available')"

log "Note: Final cleanup will be handled by Packer template"
exit 0
