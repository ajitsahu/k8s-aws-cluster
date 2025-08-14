#!/bin/bash
# Standalone etcd Cluster Synchronization Script
# Run this after cluster creation to ensure all control nodes have consistent etcd configuration
set -euo pipefail

log() { echo "[$(date '+%H:%M:%S')] $*"; }
error() { log "ERROR: $*" >&2; exit 1; }

# Check if running on a control plane node
if ! kubectl get nodes $(hostname) -o jsonpath='{.metadata.labels}' | grep -q 'node-role.kubernetes.io/control-plane'; then
    error "This script must be run from a control plane node"
fi

log "Starting etcd cluster synchronization..."

# Get current etcd cluster members using local etcdctl
log "Discovering etcd cluster members..."
ETCD_MEMBERS=$(sudo ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    member list --write-out=simple 2>/dev/null | awk -F', ' '{print $3"="$4}' | tr '\n' ',' | sed 's/,$//' || echo "")

if [ -z "$ETCD_MEMBERS" ]; then
    error "Could not retrieve etcd cluster members"
fi

log "Current etcd members: $ETCD_MEMBERS"

# Get all control plane nodes
CONTROL_NODES=$(kubectl get nodes -l node-role.kubernetes.io/control-plane --no-headers -o custom-columns=NAME:.metadata.name | sort)
NODE_COUNT=$(echo "$CONTROL_NODES" | wc -l)

log "Found $NODE_COUNT control plane nodes: $(echo $CONTROL_NODES | tr '\n' ' ')"

# Check current etcd configurations (using pod spec inspection)
log "Checking current etcd configurations..."
for node in $CONTROL_NODES; do
    # Get the current --initial-cluster value from the pod spec
    CURRENT_CLUSTER=$(kubectl get pod -n kube-system etcd-$node -o jsonpath='{.spec.containers[0].command}' | tr ' ' '\n' | grep '^--initial-cluster=' | sed 's/--initial-cluster=//' || echo "UNKNOWN")
    log "Node $node current config: $CURRENT_CLUSTER"
done

# Update etcd manifest on ALL control nodes
log "Updating etcd manifests on all control nodes..."
UPDATED_COUNT=0
FAILED_COUNT=0

# Process current node only
CURRENT_NODE=$(hostname)
log "Processing current node: $CURRENT_NODE"

if echo "$CONTROL_NODES" | grep -q "$CURRENT_NODE"; then
    # Local node - update directly
    log "  → Updating local node $CURRENT_NODE..."
    
    # Backup current manifest
    BACKUP_FILE="/etc/kubernetes/manifests/etcd.yaml.backup-$(date +%Y%m%d-%H%M%S)"
    cp /etc/kubernetes/manifests/etcd.yaml "$BACKUP_FILE"
    log "    Created backup: $BACKUP_FILE"
    
    # Update initial-cluster with all members (using awk to avoid sed regex issues)
    awk -v new_cluster="$ETCD_MEMBERS" '
        /--initial-cluster=/ { 
            gsub(/--initial-cluster=[^[:space:]]*/, "--initial-cluster=" new_cluster)
        }
        { print }
    ' /etc/kubernetes/manifests/etcd.yaml > /tmp/etcd.yaml.tmp && mv /tmp/etcd.yaml.tmp /etc/kubernetes/manifests/etcd.yaml
    
    # Set appropriate cluster state
    if echo "$CURRENT_NODE" | grep -q '\-0$'; then
        # Bootstrap node - keep state=new
        sed -i 's/--initial-cluster-state=existing/--initial-cluster-state=new/' /etc/kubernetes/manifests/etcd.yaml
        log "    Updated bootstrap node $CURRENT_NODE"
    else
        # Joined node - ensure state=existing
        if ! grep -q 'initial-cluster-state=existing' /etc/kubernetes/manifests/etcd.yaml; then
            sed -i '/--initial-cluster=/a\    - --initial-cluster-state=existing' /etc/kubernetes/manifests/etcd.yaml
        fi
        log "    Updated joined node $CURRENT_NODE"
    fi
    
    # Show differences between original and updated manifest
    log "    Changes made to etcd manifest:"
    diff -U0 "$BACKUP_FILE" /etc/kubernetes/manifests/etcd.yaml || true
    
    log "  ✅ Updated local node $CURRENT_NODE"
    ((UPDATED_COUNT++))
else
    error "Current node $CURRENT_NODE is not in the control plane node list"
fi

# Show status of other nodes (informational only)
log "Status of other control nodes (informational):"
for node in $CONTROL_NODES; do
    if [ "$node" != "$CURRENT_NODE" ]; then
        log "  ⚠️  Node $node: Run this script on that node to update"
        ((FAILED_COUNT++))
    fi
done

# Wait for etcd pods to restart and stabilize
log "Waiting for etcd pods to restart and stabilize..."
sleep 30

# Verify etcd cluster health
log "Verifying etcd cluster health..."
for i in {1..10}; do
    if kubectl exec -n kube-system etcd-$(hostname) -- etcdctl \
        --endpoints=https://127.0.0.1:2379 \
        --cacert=/etc/kubernetes/pki/etcd/ca.crt \
        --cert=/etc/kubernetes/pki/etcd/server.crt \
        --key=/etc/kubernetes/pki/etcd/server.key \
        endpoint health >/dev/null 2>&1; then
        log "✅ etcd cluster is healthy"
        break
    fi
    log "Waiting for etcd cluster to stabilize... ($i/10)"
    sleep 10
done

# Final verification - check all nodes have consistent config
log "Final verification of etcd configurations..."
ALL_CONSISTENT=true
for node in $CONTROL_NODES; do
    FINAL_CLUSTER=$(kubectl exec -n kube-system etcd-$node -- grep -E "^\s*-\s*--initial-cluster=" /etc/kubernetes/manifests/etcd.yaml | sed 's/.*--initial-cluster=//' || echo "FAILED")
    if [ "$FINAL_CLUSTER" = "$ETCD_MEMBERS" ]; then
        log "✅ Node $node: Consistent configuration"
    else
        log "❌ Node $node: Inconsistent configuration"
        log "   Expected: $ETCD_MEMBERS"
        log "   Actual:   $FINAL_CLUSTER"
        ALL_CONSISTENT=false
    fi
done

# Summary
log "=== etcd Cluster Synchronization Summary ==="
log "Total nodes processed: $NODE_COUNT"
log "Successfully updated: $UPDATED_COUNT"
log "Failed updates: $FAILED_COUNT"

if [ "$ALL_CONSISTENT" = true ]; then
    log "🎉 SUCCESS: All control nodes now have consistent etcd cluster configuration"
    log "Current cluster members: $ETCD_MEMBERS"
else
    log "⚠️  WARNING: Some nodes still have inconsistent configurations"
    log "Manual intervention may be required"
    exit 1
fi

log "etcd cluster synchronization completed successfully"
