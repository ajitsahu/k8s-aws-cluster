#!/bin/bash
# Terraform Backend Cleanup Script
# Deletes S3 bucket and DynamoDB table for Terraform state management

set -euo pipefail

# Default values (can be overridden)
BUCKET_NAME="${1:-your-terraform-state-bucket}"
REGION="${2:-ap-south-1}"
DYNAMODB_TABLE="${3:-terraform-state-lock}"

log() { echo "[$(date '+%H:%M:%S')] $*"; }
error() { log "ERROR: $*" >&2; exit 1; }
warn() { log "WARNING: $*" >&2; }

log "⚠️  DANGER: This will delete Terraform backend resources!"
log "Bucket: $BUCKET_NAME"
log "Region: $REGION"
log "DynamoDB Table: $DYNAMODB_TABLE"
log ""

# Confirmation prompt
read -p "Are you sure you want to delete these resources? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    log "Operation cancelled."
    exit 0
fi

# Verify AWS CLI is configured
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    error "AWS CLI not configured. Run 'aws configure' first."
fi

# Check if bucket exists
if ! aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    warn "S3 bucket $BUCKET_NAME does not exist or is not accessible"
else
    # Delete all objects from the S3 bucket (including versions)
    log "Deleting all objects from S3 bucket..."
    aws s3api delete-objects \
        --bucket "$BUCKET_NAME" \
        --delete "$(aws s3api list-object-versions \
            --bucket "$BUCKET_NAME" \
            --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
            --output json)" 2>/dev/null || warn "No objects to delete"

    # Delete all delete markers (if any)
    log "Deleting all delete markers..."
    aws s3api delete-objects \
        --bucket "$BUCKET_NAME" \
        --delete "$(aws s3api list-object-versions \
            --bucket "$BUCKET_NAME" \
            --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
            --output json)" 2>/dev/null || warn "No delete markers to remove"

    # Delete the S3 bucket
    log "Deleting S3 bucket..."
    aws s3api delete-bucket \
        --bucket "$BUCKET_NAME" \
        --region "$REGION" || warn "Failed to delete S3 bucket"
fi

# Check if DynamoDB table exists
if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$REGION" >/dev/null 2>&1; then
    # Delete the DynamoDB table
    log "Deleting DynamoDB table..."
    aws dynamodb delete-table \
        --table-name "$DYNAMODB_TABLE" \
        --region "$REGION" || warn "Failed to delete DynamoDB table"
    
    log "Waiting for DynamoDB table deletion..."
    aws dynamodb wait table-not-exists --table-name "$DYNAMODB_TABLE" --region "$REGION" 2>/dev/null || true
else
    warn "DynamoDB table $DYNAMODB_TABLE does not exist"
fi

log "✅ Terraform backend cleanup complete!"
