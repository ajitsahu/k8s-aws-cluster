#!/bin/bash
# Terraform Backend Setup Script
# Creates S3 bucket and DynamoDB table for Terraform state management

set -euo pipefail

# Default values (can be overridden)
BUCKET_NAME="${1:-your-terraform-state-bucket}"
REGION="${2:-ap-south-1}"
DYNAMODB_TABLE="${3:-terraform-state-lock}"

log() { echo "[$(date '+%H:%M:%S')] $*"; }
error() { log "ERROR: $*" >&2; exit 1; }

log "Setting up Terraform backend..."
log "Bucket: $BUCKET_NAME"
log "Region: $REGION"
log "DynamoDB Table: $DYNAMODB_TABLE"

# Verify AWS CLI is configured
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    error "AWS CLI not configured. Run 'aws configure' first."
fi

# Create S3 bucket for Terraform state
log "Creating S3 bucket..."
if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket \
        --bucket "$BUCKET_NAME" \
        --region "$REGION" || error "Failed to create S3 bucket"
else
    aws s3api create-bucket \
        --bucket "$BUCKET_NAME" \
        --region "$REGION" \
        --create-bucket-configuration LocationConstraint="$REGION" || error "Failed to create S3 bucket"
fi

# Enable versioning on the bucket
log "Enabling S3 bucket versioning..."
aws s3api put-bucket-versioning \
    --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled || error "Failed to enable versioning"

# Enable encryption on the bucket
log "Enabling S3 bucket encryption..."
aws s3api put-bucket-encryption \
    --bucket "$BUCKET_NAME" \
    --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}' || error "Failed to enable encryption"

# Create DynamoDB table for state locking
log "Creating DynamoDB table for state locking..."
aws dynamodb create-table \
    --table-name "$DYNAMODB_TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION" || error "Failed to create DynamoDB table"

# Wait for table to be active
log "Waiting for DynamoDB table to be active..."
aws dynamodb wait table-exists --table-name "$DYNAMODB_TABLE" --region "$REGION"

log "✅ Terraform backend setup complete!"
log ""
log "Next steps:"
log "1. Update backend.tf with these values:"
log "   bucket         = \"$BUCKET_NAME\""
log "   region         = \"$REGION\""
log "   dynamodb_table = \"$DYNAMODB_TABLE\""
log ""
log "2. Run: terraform init"
