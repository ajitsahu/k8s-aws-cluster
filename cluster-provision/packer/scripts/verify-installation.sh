#!/bin/bash
# Verify that all Kubernetes components are properly installed and enabled
# This performs final validation before AMI creation for both control plane and worker nodes

set -euo pipefail

echo "Performing final installation verification..."

# Detect node type based on available tools
if command -v kubectl >/dev/null 2>&1; then
    NODE_TYPE="control-plane"
    echo "Detected: Control Plane AMI build"
else
    NODE_TYPE="worker"
    echo "Detected: Worker AMI build"
fi

# Check systemd services are enabled
echo "Checking systemd services..."
systemctl is-enabled containerd || { echo "ERROR: containerd not enabled"; exit 1; }
systemctl is-enabled kubelet || { echo "ERROR: kubelet not enabled"; exit 1; }

# Check core Kubernetes binaries (required for both node types)
echo "Checking core Kubernetes binaries..."
command -v kubeadm >/dev/null || { echo "ERROR: kubeadm not found"; exit 1; }
command -v kubelet >/dev/null || { echo "ERROR: kubelet not found"; exit 1; }

# Check common tools (required for both node types)
echo "Checking common tools..."
command -v aws >/dev/null || { echo "ERROR: aws CLI not found"; exit 1; }
command -v containerd >/dev/null || { echo "ERROR: containerd not found"; exit 1; }

# Node-specific verification
if [ "$NODE_TYPE" = "control-plane" ]; then
    echo "Checking control plane specific tools..."
    
    # Control plane must have kubectl
    command -v kubectl >/dev/null || { echo "ERROR: kubectl not found on control plane"; exit 1; }
    
    # Control plane must have etcdctl
    command -v etcdctl >/dev/null || { echo "ERROR: etcdctl not found on control plane"; exit 1; }
    
    # Control plane must have helm
    command -v helm >/dev/null || { echo "ERROR: helm not found on control plane"; exit 1; }
    
    echo "✅ Control plane tools verified: kubectl, etcdctl, helm"
    
elif [ "$NODE_TYPE" = "worker" ]; then
    echo "Checking worker node configuration..."
    
    # Worker nodes should NOT have kubectl
    if command -v kubectl >/dev/null 2>&1; then
        echo "WARNING: kubectl found on worker node (should be excluded)"
    else
        echo "✅ kubectl correctly excluded from worker node"
    fi
    
    # Worker nodes should NOT have etcdctl
    if command -v etcdctl >/dev/null 2>&1; then
        echo "WARNING: etcdctl found on worker node (should be excluded)"
    else
        echo "✅ etcdctl correctly excluded from worker node"
    fi
    
    # Worker nodes should NOT have helm
    if command -v helm >/dev/null 2>&1; then
        echo "WARNING: helm found on worker node (should be excluded)"
    else
        echo "✅ helm correctly excluded from worker node"
    fi
fi

# Check container runtime configuration
echo "Checking container runtime configuration..."
if [ -f "/etc/containerd/config.toml" ]; then
    echo "✅ containerd configuration found"
    
    # Check SystemdCgroup setting
    if grep -q "SystemdCgroup = true" /etc/containerd/config.toml; then
        echo "✅ SystemdCgroup enabled in containerd"
    else
        echo "WARNING: SystemdCgroup not enabled in containerd"
    fi
    
    # Check pause image
    if grep -q "pause:3.10" /etc/containerd/config.toml; then
        echo "✅ Pause image 3.10 configured"
    else
        echo "WARNING: Pause image 3.10 not configured"
    fi
else
    echo "ERROR: containerd configuration not found"
    exit 1
fi

# Check crictl configuration
if [ -f "/etc/crictl.yaml" ]; then
    echo "✅ crictl configuration found"
else
    echo "WARNING: crictl configuration not found"
fi

# Check kernel modules and sysctl
echo "Checking Kubernetes system configuration..."
if [ -f "/etc/modules-load.d/k8s.conf" ]; then
    echo "✅ Kubernetes kernel modules configuration found"
else
    echo "ERROR: Kubernetes kernel modules configuration not found"
    exit 1
fi

if [ -f "/etc/sysctl.d/k8s.conf" ]; then
    echo "✅ Kubernetes sysctl configuration found"
else
    echo "ERROR: Kubernetes sysctl configuration not found"
    exit 1
fi

echo ""
echo "🎯 Final verification completed successfully!"
echo "Node Type: $NODE_TYPE"
echo "All required components are present and properly configured"
