#!/bin/bash
set -e

# Load utils
source /app/scripts/utils.sh

# Configuration
SNAPSHOT_DIR=${SNAPSHOT_DIR:-"/tmp/portainer-snapshots"}
DATA_DIR=${DATA_DIR:-"/data"}
CLOUD_DEST=${CLOUD_DEST} # e.g., remote:backups/portainer

check_env_var "CLOUD_DEST"

TIMESTAMP=$(date +%Y%m%d%H%M%S)
ARCHIVE_NAME="snapshot_$TIMESTAMP.tar.gz"
LATEST_ARCHIVE_NAME="latest.tar.gz"

log_info "Starting Portainer backup..."

# Ensure snapshot directory exists and is empty
mkdir -p "$SNAPSHOT_DIR"
rm -rf "${SNAPSHOT_DIR:?}"/*

# 1. Compress Data Directory
# We compress the contents of /data
log_info "Compressing data directory..."
cd "$DATA_DIR"
# tar everything in . to the archive in snapshot dir
tar -czf "$SNAPSHOT_DIR/$ARCHIVE_NAME" .
log_success "Compressed to $SNAPSHOT_DIR/$ARCHIVE_NAME"

# 2. Upload to Cloud
cd "$SNAPSHOT_DIR"
log_info "Uploading to cloud ($CLOUD_DEST)..."
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

# 3. Retention Policy (Keep last 5)
RETENTION_COUNT=${BACKUP_RETENTION_COUNT:-5}
log_info "Applying retention policy (Keep last $RETENTION_COUNT)..."

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

# 4. Cleanup
cleanup_temp "$SNAPSHOT_DIR"
