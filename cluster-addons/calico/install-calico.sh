#!/bin/bash

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# Calico version to install/upgrade to
CALICO_VERSION="v3.30.0"

# Function to display usage information
usage() {
  echo -e "${YELLOW}Usage: $0 [OPTIONS]${NC}"
  echo -e "  --version VERSION  Specify Calico version to install/upgrade (default: ${CALICO_VERSION})"
  echo -e "  --pod-cidr CIDR    Manually specify pod CIDR (default: auto-detected from terraform.tfvars)"
  echo -e "  --help             Display this help message"
  exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --version)
      CALICO_VERSION="$2"
      shift 2
      ;;
    --pod-cidr)
      POD_CIDR="$2"
      shift 2
      ;;
    --help)
      usage
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      usage
      ;;
  esac
done

# Get pod CIDR from tfvars if not specified
if [ -z "$POD_CIDR" ]; then
  if [ -f "../../cluster-provision/terraform.tfvars" ]; then
    POD_CIDR=$(grep 'pod_cidr' ../../cluster-provision/terraform.tfvars | awk -F '=' '{print $2}' | awk -F '#' '{print $1}' | tr -d ' "')
  else
    # Try to get from Kubernetes node spec as fallback
    POD_CIDR=$(kubectl describe cm kubeadm-config -n kube-system | grep podSubnet | awk '{print$2}')
  fi

  # Validate pod CIDR
  if [ -z "$POD_CIDR" ]; then
    echo -e "${RED}Error: Could not determine pod CIDR automatically.${NC}"
    echo -e "${YELLOW}Please specify manually with --pod-cidr flag.${NC}"
    exit 1
  fi
fi

echo -e "${GREEN}Installing/upgrading Calico CNI ${CALICO_VERSION} for cluster with pod CIDR: ${POD_CIDR}${NC}"

# Validate required tools
command -v helm >/dev/null 2>&1 || { echo -e "${RED}Error: Helm is required but not installed. Aborting.${NC}"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}Error: kubectl is required but not installed. Aborting.${NC}"; exit 1; }

# Check if kubectl can connect to the cluster
kubectl get nodes &>/dev/null || { echo -e "${RED}Error: kubectl cannot connect to the cluster. Check your kubeconfig.${NC}"; exit 1; }

# Add Calico Helm repo
echo -e "${GREEN}Adding/updating Calico Helm repository...${NC}"
helm repo add projectcalico https://docs.tigera.io/calico/charts || true
helm repo update

# Check if Calico is already installed
CALICO_INSTALLED=false
if kubectl get ns tigera-operator &>/dev/null; then
  if helm -n tigera-operator list | grep -q calico; then
    CALICO_INSTALLED=true
    CURRENT_VERSION=$(helm -n tigera-operator list -o json | jq -r '.[] | select(.name=="calico") | .app_version')
    echo -e "${YELLOW}Calico ${CURRENT_VERSION} is already installed. Upgrading to ${CALICO_VERSION}...${NC}"
  else
    echo -e "${YELLOW}Namespace tigera-operator exists but Calico helm release not found.${NC}"
  fi
else
  echo -e "${GREEN}Creating tigera-operator namespace...${NC}"
  kubectl create ns tigera-operator
fi

# Install or upgrade Calico
echo -e "${GREEN}Installing/upgrading Calico ${CALICO_VERSION}...${NC}"
helm upgrade --install calico projectcalico/tigera-operator \
  --namespace tigera-operator \
  --version $CALICO_VERSION \
  --set installation.cni.type=Calico \
  --set installation.calicoNetwork.ipPools[0].cidr=$POD_CIDR \
  -f ./values.yaml

INSTALL_STATUS=$?
if [ $INSTALL_STATUS -ne 0 ]; then
  echo -e "${RED}Error: Calico installation/upgrade failed.${NC}"
  exit 1
fi

# Wait for calico pods
echo -e "${GREEN}Waiting for Calico pods to become ready...${NC}"

# Wait for calico-system namespace to be created
for i in {1..30}; do
  if kubectl get ns calico-system &>/dev/null; then
    break
  fi
  echo -n "."
  sleep 2
done

# Wait for pods to be ready
if kubectl get ns calico-system &>/dev/null; then
  echo -e "${GREEN}Waiting for Calico pods to be ready (this may take a few minutes)...${NC}"
  
  # More robust approach - wait for specific deployments instead of all pods
  # This avoids issues with pods being terminated or recreated during installation
  for i in {1..30}; do
    READY_COUNT=$(kubectl get deployments -n calico-system -o json | jq '.items | map(select(.status.readyReplicas == .status.replicas and .status.replicas > 0)) | length')
    TOTAL_COUNT=$(kubectl get deployments -n calico-system -o json | jq '.items | length')
    
    if [ "$READY_COUNT" = "$TOTAL_COUNT" ] && [ "$TOTAL_COUNT" -gt 0 ]; then
      echo -e "${GREEN}All Calico deployments are ready!${NC}"
      break
    fi
    
    echo -n "."
    sleep 10
  done
  
  # Show current status
  echo -e "\n${GREEN}Current Calico pod status:${NC}"
  kubectl get pods -n calico-system
  
  # Check if any pods are in a bad state
  FAILED_PODS=$(kubectl get pods -n calico-system --field-selector=status.phase!=Running,status.phase!=Succeeded -o name)
  if [ -n "$FAILED_PODS" ]; then
    echo -e "${YELLOW}Warning: Some Calico pods are not running. Check their logs for details.${NC}"
  fi
else
  echo -e "${RED}Error: calico-system namespace was not created after 60 seconds.${NC}"
  echo -e "${YELLOW}Check the operator logs with:${NC}"
  echo -e "  kubectl logs -n tigera-operator -l k8s-app=tigera-operator"
  exit 1
fi

# Verify installation
if $CALICO_INSTALLED; then
  echo -e "${GREEN} Calico CNI successfully upgraded to ${CALICO_VERSION}.${NC}"
else
  echo -e "${GREEN} Calico CNI ${CALICO_VERSION} installation complete.${NC}"
fi

# calicoctl installation has been moved to manual process
# See README.md for calicoctl installation instructions

# Show status
echo -e "\n${GREEN}Calico Operator Pods:${NC}"
kubectl get pods -n tigera-operator

echo -e "\n${GREEN}Calico System Pods:${NC}"
kubectl get pods -n calico-system

echo -e "\nTo verify network policies are working, run the network policy test:"
echo -e "  kubectl apply -f https://docs.tigera.io/calico/latest/network-policy/get-started/kubernetes-policy/demo.yaml"
