#!/bin/bash
# Bastion Host User Data Script
# Minimal setup for secure SSH gateway to private Kubernetes nodes

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# === Logging ===
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a /var/log/bastion-setup.log
}

log "🚀 Starting bastion host setup for cluster: ${CLUSTER_NAME}"

# === Update System ===
log "📦 Updating system packages..."
apt-get update -y
apt-get upgrade -y

# === Install Essential Tools ===
log "🔧 Installing essential tools..."
apt-get install -y \
  curl \
  wget \
  unzip \
  jq \
  htop \
  tree \
  vim \
  git \
  awscli

# === Configure SSH ===
log "🔑 Configuring SSH for security..."

# Harden SSH configuration
cat >> /etc/ssh/sshd_config <<EOF

# Bastion host SSH hardening
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries 3
MaxSessions 10
Protocol 2
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
EOF

# Restart SSH service
systemctl restart ssh

# === Install kubectl (for troubleshooting) ===
log "⚙️ Installing kubectl for cluster troubleshooting..."

# Add Kubernetes repository
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" > /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get install -y kubectl

# === Configure AWS CLI ===
log "☁️ Configuring AWS CLI..."
aws configure set region ${AWS_REGION}
aws configure set output json

# === Setup Monitoring ===
log "📊 Setting up basic monitoring..."

# Create a simple system status script
cat > /usr/local/bin/system-status <<'EOF'
#!/bin/bash
echo "=== Bastion Host System Status ==="
echo "Date: $(date)"
echo "Uptime: $(uptime)"
echo "Memory: $(free -h | grep Mem)"
echo "Disk: $(df -h / | tail -1)"
echo "Active SSH connections: $(who | wc -l)"
echo "=================================="
EOF

chmod +x /usr/local/bin/system-status

# Add to crontab for periodic logging
echo "*/15 * * * * /usr/local/bin/system-status >> /var/log/system-status.log" | crontab -

# === Security Hardening ===
log "🔒 Applying security hardening..."

# Disable unused services
systemctl disable snapd --now 2>/dev/null || true

# Configure automatic security updates
apt-get install -y unattended-upgrades
echo 'Unattended-Upgrade::Automatic-Reboot "false";' >> /etc/apt/apt.conf.d/50unattended-upgrades

# === Create Welcome Message ===
cat > /etc/motd <<EOF
╔══════════════════════════════════════════════════════════════╗
║                    🏰 BASTION HOST                           ║
║                                                              ║
║  Cluster: ${CLUSTER_NAME}                                    ║
║  Region:  ${AWS_REGION}                                      ║
║                                                              ║
║  🔑 SSH Gateway to Private Kubernetes Nodes                  ║
║  📊 System Status: /usr/local/bin/system-status              ║
║  📝 Setup Log: /var/log/bastion-setup.log                    ║
║                                                             ║
║  ⚠️  Security Notice:                                        ║
║  - This host provides SSH access to private K8s nodes       ║
║  - All activities are logged                                ║
║  - Use responsibly and follow security policies             ║
╚══════════════════════════════════════════════════════════════╝

EOF

# === Final Setup ===
log "🎯 Finalizing bastion host setup..."

# Create ubuntu user .ssh directory with proper permissions
mkdir -p /home/ubuntu/.ssh
chown ubuntu:ubuntu /home/ubuntu/.ssh
chmod 700 /home/ubuntu/.ssh

# Set proper permissions on log files
chmod 644 /var/log/bastion-setup.log
chown ubuntu:ubuntu /var/log/bastion-setup.log

log "✅ Bastion host setup completed successfully!"
log "🔑 Ready to provide secure SSH access to private Kubernetes nodes"

# Display system status
/usr/local/bin/system-status
