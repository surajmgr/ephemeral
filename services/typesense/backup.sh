#!/bin/bash
set -e

# Load utils
source /app/scripts/utils.sh

# Configuration
TYPESENSE_HOST=${TYPESENSE_HOST:-"http://localhost:8108"}
TYPESENSE_API_KEY=${TYPESENSE_API_KEY}
SNAPSHOT_DIR=${SNAPSHOT_DIR:-"/tmp/typesense-snapshots"}
CLOUD_DEST=${CLOUD_DEST} # e.g., remote:backup/typesense

check_env_var "TYPESENSE_API_KEY"
check_env_var "CLOUD_DEST"

TIMESTAMP=$(date +%Y%m%d%H%M%S)
LOCAL_SNAPSHOT_PATH="$SNAPSHOT_DIR/$TIMESTAMP"
ARCHIVE_NAME="snapshot_$TIMESTAMP.tar.gz"
LATEST_ARCHIVE_NAME="latest.tar.gz"

log_info "Starting Typesense backup..."

# Ensure snapshot directory exists and is empty
mkdir -p "$SNAPSHOT_DIR"
rm -rf "${SNAPSHOT_DIR:?}"/*

# 1. Trigger Snapshot via API
log_info "Triggering snapshot via API..."
HTTP_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  "${TYPESENSE_HOST}/operations/snapshot?snapshot_path=${LOCAL_SNAPSHOT_PATH}" \
  -H "X-TYPESENSE-API-KEY: ${TYPESENSE_API_KEY}")

if [ "$HTTP_RESPONSE" != "200" ]; then
    log_error "Snapshot failed. HTTP Status: $HTTP_RESPONSE"
    exit 1
fi
log_success "Snapshot created at $LOCAL_SNAPSHOT_PATH"

# 2. Compress Snapshot
log_info "Compressing snapshot..."
cd "$SNAPSHOT_DIR"
tar -czf "$ARCHIVE_NAME" "$TIMESTAMP"
log_success "Compressed to $ARCHIVE_NAME"

# 3. Upload to Cloud
log_info "Uploading to cloud ($CLOUD_DEST)..."
# Use --retries and --transfers for better reliability
if ! rclone copy "$ARCHIVE_NAME" "$CLOUD_DEST" --retries 5 --transfers 4; then
    log_error "Failed to upload snapshot to cloud."
    exit 1
fi

# Copy as 'latest' for easy restore
cp "$ARCHIVE_NAME" "$LATEST_ARCHIVE_NAME"
if ! rclone copy "$LATEST_ARCHIVE_NAME" "$CLOUD_DEST" --retries 5; then
    log_warn "Failed to update 'latest.tar.gz' in cloud, but timestamped backup was uploaded."
fi

log_success "Backup uploaded successfully."

# 4. Retention Policy (Keep last 5)
RETENTION_COUNT=${BACKUP_RETENTION_COUNT:-5}
log_info "Applying retention policy (Keep last $RETENTION_COUNT)..."

# List files, filter for snapshot_*.tar.gz, sort by time (oldest first), head to find ones to delete
# rclone lsl produces: size date time path
# We only want to manage files in the specific CLOUD_DEST
FILES_TO_DELETE=$(rclone lsf "$CLOUD_DEST" --files-only --include "snapshot_*.tar.gz" | sort | head -n -"$RETENTION_COUNT")

if [ -n "$FILES_TO_DELETE" ]; then
    log_info "Deleting old snapshots..."
    for file in $FILES_TO_DELETE; do
        log_info "Deleting $file..."
        rclone deletefile "$CLOUD_DEST/$file" || log_warn "Failed to delete $file"
    done
else
    log_info "No old snapshots to purge."
fi

# 5. Cleanup
cleanup_temp "$SNAPSHOT_DIR"
