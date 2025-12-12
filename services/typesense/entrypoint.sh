#!/bin/bash
set -e

# --- Generate rclone config dynamically ---
mkdir -p /root/.config/rclone

cat > /root/.config/rclone/rclone.conf <<EOF
[remote]
type = ${RCLONE_CONFIG_REMOTE_TYPE:-pcloud}
token = {"access_token":"${RCLONE_CONFIG_REMOTE_TOKEN}","token_type":"bearer","expiry":"0001-01-01T00:00:00Z"}
EOF

echo "[INFO] rclone config generated successfully"

# --- Source utils ---
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

# 3. Start Dashboard
log_info "Starting Typesense Dashboard on port 8109..."
cd /app/dashboard
serve -s . -l 8109 &
DASHBOARD_PID=$!
log_success "Dashboard started with PID $DASHBOARD_PID"

# 4. Start Backup Loop
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

# 5. Wait for any process to exit
wait -n
EXIT_CODE=$?
log_info "A process exited with code $EXIT_CODE"
exit $EXIT_CODE
