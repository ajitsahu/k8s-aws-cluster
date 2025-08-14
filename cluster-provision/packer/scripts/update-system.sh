#!/bin/bash
# Update system packages before Kubernetes installation
# This ensures we have the latest security updates and package versions

set -euo pipefail

echo "Updating system packages..."
apt-get update -y -qq
apt-get upgrade -y -qq

echo "System packages updated successfully"
