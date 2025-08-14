#!/bin/bash
# Wait for cloud-init to complete before proceeding with installation
# This ensures the system is fully initialized

set -euo pipefail

echo "Waiting for cloud-init to complete..."
cloud-init status --wait

echo "Cloud-init completed successfully"
echo "System is ready for Kubernetes installation"
