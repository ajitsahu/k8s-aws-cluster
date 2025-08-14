# Calico CNI Installation

Installs Calico CNI for pod networking and network policies on your Kubernetes cluster.

## 📋 Prerequisites

- Running Kubernetes cluster
- `kubectl` and `helm` installed
- Control plane node access

## 🚀 Quick Start

### 1. Install Calico
*Installs Calico CNI with automatic pod CIDR detection from terraform.tfvars.*

```bash
# Basic installation (auto-detects settings)
./install-calico.sh

# Specify version and pod CIDR manually
./install-calico.sh --version v3.31.0 --pod-cidr 192.168.0.0/16
```

### 2. Verify Installation
*Confirms all Calico pods are running and ready.*

```bash
# Check Calico operator status
kubectl get tigerastatus

# Check Calico pods
kubectl get pods -n calico-system

# Verify nodes are ready
kubectl get nodes
```

## 🛠️ calicoctl (Optional)
*Command-line tool for advanced Calico management and troubleshooting. Been already installed in control nodes*

### Common Commands
```bash
# Node status
calicoctl node status

# IP pools
calicoctl get ippools

# Network policies
calicoctl get networkpolicies --all-namespaces
   ```

## Upgrading Calico

### Automatic Upgrade

To upgrade Calico to a new version, you have two options:

#### Option 1: Use command-line arguments (recommended)

Simply run the script with the desired version:

```bash
./install-calico.sh --version v3.31.0
```

#### Option 2: Edit the script

1. Edit the `install-calico.sh` script and update the `CALICO_VERSION` variable:
   ```bash
   # Change this line
   CALICO_VERSION="v3.30.0"
   # To the desired version, e.g.
   CALICO_VERSION="v3.31.0"
   ```

2. Run the installation script:
   ```bash
   ./install-calico.sh
   ```

Both methods use `helm upgrade --install` which will perform an upgrade if Calico is already installed.


Always check the [official Calico documentation](https://docs.tigera.io/calico/latest/getting-started/kubernetes/) for the most up-to-date compatibility information.

## Additional Resources

- [Calico Official Documentation](https://docs.tigera.io/calico/latest/)
- [Calico GitHub Repository](https://github.com/projectcalico/calico)
- [Calico Helm Chart Documentation](https://docs.tigera.io/calico/latest/reference/installation/helm)