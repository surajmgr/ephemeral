#!/bin/bash
set -e

source /app/scripts/utils.sh

# Configuration
BACKUP_INTERVAL=${BACKUP_INTERVAL:-3600} # Default 1 hour
TYPESENSE_API_KEY=${TYPESENSE_API_KEY}

# 1. Restore Data
/app/services/typesense/restore.sh

# 2. Start Typesense in background
log_info "Starting Typesense..."
# Pass all arguments to the real typesense command
/opt/typesense-server --data-dir /data --api-key="${TYPESENSE_API_KEY}" --enable-cors &
TYPESENSE_PID=$!

log_success "Typesense started with PID $TYPESENSE_PID"

# 3. Start Backup Loop
(
    log_info "Starting backup loop (Interval: ${BACKUP_INTERVAL}s)..."
    while kill -0 $TYPESENSE_PID > /dev/null 2>&1; do
        sleep "$BACKUP_INTERVAL"
        log_info "Scheduled backup triggered."
        if ! /app/services/typesense/backup.sh; then
            log_error "Backup failed. Retrying next cycle."
        else
            log_success "Scheduled backup completed."
        fi
    done
) &

# 4. Wait for Typesense to exit
wait $TYPESENSE_PID
EXIT_CODE=$?
log_info "Typesense exited with code $EXIT_CODE"
exit $EXIT_CODE
