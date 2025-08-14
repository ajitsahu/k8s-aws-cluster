#!/bin/bash
# Minimal Worker Node Join Script for Custom AMI
# This script only handles cluster-specific joining
set -euo pipefail

log() { echo "[$(date '+%H:%M:%S')] $*"; }
error() { log "ERROR: $*" >&2; exit 1; }

log "Starting worker node join process..."

# Set variables from template
CLUSTER_NAME="${CLUSTER_NAME}"
AWS_REGION="${AWS_REGION}"
INTERNAL_NLB_DNS_NAME="${INTERNAL_NLB_DNS_NAME}"

# === Node Identity ===
log "Node identity managed by AMI-level cleanup - no verification needed"

# === Wait for Valid Join Parameters ===
wait_for_join_parameters() {
    log "Waiting for valid cluster join parameters..."
    
    for i in {1..60}; do
        # Check if all required parameters exist
        if aws ssm get-parameter --region "$AWS_REGION" --name "/k8s/$CLUSTER_NAME/join-token" --with-decryption >/dev/null 2>&1 && \
           aws ssm get-parameter --region "$AWS_REGION" --name "/k8s/$CLUSTER_NAME/token-created" >/dev/null 2>&1; then
            
            # Get token creation time
            TOKEN_CREATED=$(aws ssm get-parameter --region "$AWS_REGION" --name "/k8s/$CLUSTER_NAME/token-created" --query 'Parameter.Value' --output text)
            TOKEN_AGE_MINUTES=$(( ($(date +%s) - $(date -d "$TOKEN_CREATED" +%s)) / 60 ))
            
            # Accept tokens that are valid for kubeadm join (kubeadm tokens are valid for 24 hours by default)
            if [ $TOKEN_AGE_MINUTES -le 1440 ]; then  # ≤24 hours (kubeadm default TTL)
                if [ $TOKEN_AGE_MINUTES -le 10 ]; then
                    log "Fresh join parameters available (token age: $TOKEN_AGE_MINUTES minutes)"
                else
                    log "Valid join parameters available (token age: $(($TOKEN_AGE_MINUTES / 60)) hours)"
                fi
                return 0
            else
                log "Join token expired (token age: $(($TOKEN_AGE_MINUTES / 60)) hours), waiting for refresh..."
            fi
        fi
        
        [ $i -eq 60 ] && error "Timeout waiting for valid join parameters"
        log "Waiting for valid join parameters... ($i/60)"
        sleep 10
    done
}

# === Trigger Token Refresh for Long-term Scaling ===
trigger_token_refresh_if_needed() {
    TOKEN_CREATED=$(aws ssm get-parameter --region "$AWS_REGION" --name "/k8s/$CLUSTER_NAME/token-created" --query 'Parameter.Value' --output text 2>/dev/null || echo "")
    
    if [ -n "$TOKEN_CREATED" ]; then
        TOKEN_AGE_HOURS=$(( ($(date +%s) - $(date -d "$TOKEN_CREATED" +%s)) / 3600 ))
        
        # Trigger refresh for expired tokens (>24 hours)
        if [ $TOKEN_AGE_HOURS -gt 24 ]; then
            log "Triggering token refresh for expired token (token age: $TOKEN_AGE_HOURS hours)..."
            
            FIRST_CONTROL_INSTANCE=$(aws ec2 describe-instances \
                --region "$AWS_REGION" \
                --filters "Name=tag:Name,Values=${CLUSTER_NAME}-control-0" "Name=instance-state-name,Values=running" \
                --query 'Reservations[0].Instances[0].InstanceId' --output text)
            
            if [ "$FIRST_CONTROL_INSTANCE" != "None" ] && [ -n "$FIRST_CONTROL_INSTANCE" ]; then
                aws ssm send-command \
                    --region "$AWS_REGION" \
                    --instance-ids "$FIRST_CONTROL_INSTANCE" \
                    --document-name "AWS-RunShellScript" \
                    --parameters 'commands=[
                        "NEW_JOIN_TOKEN=$(kubeadm token create --ttl 72h0m0s)",
                        "aws ssm put-parameter --region '$AWS_REGION' --name \"/k8s/'$CLUSTER_NAME'/join-token\" --value \"$NEW_JOIN_TOKEN\" --type \"SecureString\" --overwrite",
                        "aws ssm put-parameter --region '$AWS_REGION' --name \"/k8s/'$CLUSTER_NAME'/token-created\" --value \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\" --type \"String\" --overwrite"
                    ]' --output text >/dev/null 2>&1
                
                log "Token refresh triggered, waiting 30 seconds..."
                sleep 30
            fi
        fi
    fi
}

# Execute token management logic
trigger_token_refresh_if_needed
wait_for_join_parameters

# === Retrieve Join Parameters ===
log "Retrieving join parameters from SSM..."
JOIN_TOKEN=$(aws ssm get-parameter --region "$AWS_REGION" --name "/k8s/$CLUSTER_NAME/join-token" --with-decryption --query 'Parameter.Value' --output text)
CACERT_HASH=$(aws ssm get-parameter --region "$AWS_REGION" --name "/k8s/$CLUSTER_NAME/cacert-hash" --with-decryption --query 'Parameter.Value' --output text)
ENDPOINT=$(aws ssm get-parameter --region "$AWS_REGION" --name "/k8s/$CLUSTER_NAME/control-plane-endpoint" --with-decryption --query 'Parameter.Value' --output text)

# Validate parameters
[ -z "$JOIN_TOKEN" ] && error "Join token is empty"
[ -z "$CACERT_HASH" ] && error "CA cert hash is empty" 
[ -z "$ENDPOINT" ] && error "Control plane endpoint is empty"

# Debug logging for troubleshooting
log "Using token ID: $(echo $JOIN_TOKEN | cut -d. -f1) | Endpoint: $ENDPOINT"

log "Using endpoint: $ENDPOINT"

# Wait for API server to be healthy
log "Checking API server health..."
for i in {1..30}; do
    if curl -k -s "https://$ENDPOINT:6443/healthz" | grep -q "ok"; then
        log "API server is healthy"
        break
    fi
    [ $i -eq 30 ] && error "API server health check failed"
    log "Waiting for API server to be healthy... ($i/30)"
    sleep 10
done

# Create JoinConfiguration for production-grade kubelet.conf generation
log "Creating JoinConfiguration for proper cluster discovery..."
cat > /tmp/kubeadm-join-config.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1beta4
kind: JoinConfiguration
discovery:
  bootstrapToken:
    apiServerEndpoint: "$ENDPOINT:6443"
    token: "$JOIN_TOKEN"
    caCertHashes:
    - "$CACERT_HASH"
nodeRegistration:
  name: "$(hostname -s)"
  criSocket: "unix:///var/run/containerd/containerd.sock"
EOF

# Join the cluster using configuration file (production approach)
log "Joining worker node to cluster using JoinConfiguration..."
kubeadm join --config /tmp/kubeadm-join-config.yaml --v=5 || error "kubeadm join failed"

# Update kubelet.conf to use internal NLB for HA (server endpoint only)
log "Updating kubelet.conf to use internal NLB for HA..."
if [ -f /etc/kubernetes/kubelet.conf ]; then
    # Only update server endpoint to use internal NLB (cluster naming is already correct from JoinConfiguration)
    sudo sed -i "s|server: https://.*:6443|server: https://$ENDPOINT:6443|g" /etc/kubernetes/kubelet.conf
    log "Updated kubelet.conf to use internal NLB: $ENDPOINT"
    
    # Restart kubelet to pick up the new configuration
    sudo systemctl restart kubelet
    sleep 5
else
    log "WARNING: /etc/kubernetes/kubelet.conf not found"
fi

# Clean up temporary configuration file
rm -f /tmp/kubeadm-join-config.yaml

# Verify kubelet is running
log "Verifying kubelet status..."
sleep 10
if systemctl is-active --quiet kubelet; then
    log "Kubelet is running successfully with HA configuration"
    
    # Verify the kubelet.conf is using the correct endpoint
    KUBELET_SERVER=$(sudo grep "server:" /etc/kubernetes/kubelet.conf | awk '{print $2}' || echo "unknown")
    log "Kubelet server endpoint: $KUBELET_SERVER"
else
    error "Kubelet is not running. Check with: systemctl status kubelet -l"
fi

log "Worker node joined cluster successfully with HA configuration"
