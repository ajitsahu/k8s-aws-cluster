#!/bin/bash
# cleanup-secrets.sh
# Run after all control plane nodes have joined
# FIXED: Only clean up truly temporary secrets, keep join parameters for future scaling

CLUSTER_NAME="$1"

# Ensure cluster name is provided
if [ -z "$CLUSTER_NAME" ]; then
  echo "Error: Cluster name not provided as argument"
  echo "Usage: $0 <cluster-name>"
  exit 1
fi

echo "[$(date)] Cleaning up temporary SSM secrets for cluster: $CLUSTER_NAME"

# Only delete cert-key (used for control plane joining, not needed after initial setup)
aws ssm delete-parameter --name "/k8s/$CLUSTER_NAME/cert-key" || true

# KEEP these parameters for future worker scaling:
# - /k8s/$CLUSTER_NAME/join-token (needed for worker nodes)
# - /k8s/$CLUSTER_NAME/cacert-hash (needed for worker nodes)  
# - /k8s/$CLUSTER_NAME/control-plane-endpoint (needed for worker nodes)
# - /k8s/$CLUSTER_NAME/token-created (needed for token refresh logic)

# Keep ca-cert, client-cert, and client-key for kubeconfig generation
# These are needed for ongoing cluster access

echo "[$(date)] Temporary SSM secrets cleaned up (kept join parameters for future scaling)"
