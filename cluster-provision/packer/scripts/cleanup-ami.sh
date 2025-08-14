#!/bin/bash
# Final cleanup and preparation for AMI creation
# This removes temporary files, logs, and history to create a clean AMI

set -euo pipefail

echo "Performing final cleanup for AMI preparation..."

# Clean package cache
echo "Cleaning package cache..."
apt-get autoremove -y
apt-get autoclean

# Remove temporary files
echo "Removing temporary files..."
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/*
rm -rf /var/tmp/*

# Clear logs
echo "Clearing system logs..."
truncate -s 0 /var/log/*log 2>/dev/null || true

# Clear bash history
echo "Clearing bash history..."
history -c 2>/dev/null || true
cat /dev/null > ~/.bash_history 2>/dev/null || true

# Clear cloud-init logs and cache (optional)
echo "Clearing cloud-init cache..."
rm -rf /var/lib/cloud/instances/* 2>/dev/null || true
rm -rf /var/log/cloud-init* 2>/dev/null || true

# Reset machine ID to ensure unique IDs on new instances
echo "Resetting machine ID..."
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id

# Remove hardware UUID (will be regenerated on new instances)
echo "Removing hardware UUID..."
rm -f /sys/class/dmi/id/product_uuid 2>/dev/null || true

# Reset SSH host keys (they will be regenerated on first boot)
echo "Removing SSH host keys..."
rm -f /etc/ssh/ssh_host_*

# Clear systemd machine ID journal
echo "Clearing systemd journal..."
rm -rf /var/log/journal/*

echo "AMI preparation completed - image is ready for creation"
