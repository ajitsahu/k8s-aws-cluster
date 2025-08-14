#!/bin/bash
# verify-control-plane.sh - Check if control plane is properly initialized

CLUSTER_NAME="$1"
REGION="${2:-ap-south-1}"  # Default to ap-south-1 if not provided

if [ -z "$CLUSTER_NAME" ]; then
  echo "Error: Cluster name not provided as argument"
  echo "Usage: $0 <cluster-name> [region]"
  exit 1
fi

echo "[$(date)] Verifying control plane initialization for cluster: $CLUSTER_NAME"

# Check if required SSM parameters exist
echo "Checking SSM parameters..."

REQUIRED_PARAMS=(
  "/k8s/$CLUSTER_NAME/ca-cert"
  "/k8s/$CLUSTER_NAME/client-cert"
  "/k8s/$CLUSTER_NAME/client-key"
  "/k8s/$CLUSTER_NAME/join-token"
  "/k8s/$CLUSTER_NAME/cert-key"
  "/k8s/$CLUSTER_NAME/cacert-hash"
  "/k8s/$CLUSTER_NAME/control-plane-endpoint"
)

MISSING_PARAMS=()

for param in "${REQUIRED_PARAMS[@]}"; do
  if aws ssm get-parameter --region "$REGION" --name "$param" --query "Parameter.Name" --output text >/dev/null 2>&1; then
    echo "✅ Found: $param"
  else
    echo "❌ Missing: $param"
    MISSING_PARAMS+=("$param")
  fi
done

if [ ${#MISSING_PARAMS[@]} -eq 0 ]; then
  echo "✅ All required SSM parameters found!"
  echo "Control plane appears to be properly initialized."
  exit 0
else
  echo "❌ Missing ${#MISSING_PARAMS[@]} required SSM parameters:"
  for param in "${MISSING_PARAMS[@]}"; do
    echo "  - $param"
  done
  echo ""
  echo "This indicates the control plane initialization (init-control.sh) failed."
  echo "Check the control plane instance logs for errors."
  exit 1
fi
