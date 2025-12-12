#!/bin/bash
set -e

# Load utils
source /app/scripts/utils.sh

# Configuration
DATA_DIR=${DATA_DIR:-"/data"}
CLOUD_DEST=${CLOUD_DEST}
LATEST_ARCHIVE_NAME="latest.tar.gz"
DOWNLOAD_DIR="/tmp/restore"

check_env_var "CLOUD_DEST"

log_info "Starting Typesense restore..."

# Check if cloud has backup
log_info "Checking for latest snapshot in $CLOUD_DEST..."
if ! rclone lsf "$CLOUD_DEST/$LATEST_ARCHIVE_NAME" > /dev/null 2>&1; then
    log_warn "No snapshot found at $CLOUD_DEST/$LATEST_ARCHIVE_NAME. Starting with empty data."
    exit 0
fi

# Prepare download directory
mkdir -p "$DOWNLOAD_DIR"

# Download snapshot
log_info "Downloading latest snapshot..."
rclone copy "$CLOUD_DEST/$LATEST_ARCHIVE_NAME" "$DOWNLOAD_DIR"

if [ ! -f "$DOWNLOAD_DIR/$LATEST_ARCHIVE_NAME" ]; then
    log_warn "Download failed or file missing. Starting with empty data."
    exit 0
fi

log_success "Downloaded snapshot."

# Extract
log_info "Extracting snapshot to $DATA_DIR..."
if [ -d "$DATA_DIR" ]; then
    log_warn "Cleaning existing data directory..."
    rm -rf "${DATA_DIR:?}"/*
fi
mkdir -p "$DATA_DIR"

tar -xzf "$DOWNLOAD_DIR/$LATEST_ARCHIVE_NAME" -C "$DOWNLOAD_DIR"

# Find only the timestamped restore directory (ignoring other dirs like tls/bin/etc)
EXTRACTED_DIR=$(find "$DOWNLOAD_DIR" -maxdepth 1 -mindepth 1 -type d -name '20*' | head -n 1)

if [ -n "$EXTRACTED_DIR" ]; then
   log_info "Moving data from $EXTRACTED_DIR to $DATA_DIR"
   mv "$EXTRACTED_DIR"/* "$DATA_DIR/"
   log_success "Restore complete."
else
   log_error "Failed to find extracted restore directory."
   exit 1
fi

# Cleanup
cleanup_temp "$DOWNLOAD_DIR"
