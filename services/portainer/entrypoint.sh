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

# 1. Restore Data
/app/services/portainer/restore.sh

# 2. Start Portainer in background
log_info "Starting Portainer..."
# Portainer on Alpine is located at /portainer
# We pass arguments if any. Standard portainer args can be appended.
/portainer --data /data --bind :9443 --bind :8000 --host unix:///var/run/docker.sock &
PORTAINER_PID=$!

log_success "Portainer started with PID $PORTAINER_PID"

# 3. Start Backup Loop
(
    log_info "Starting backup loop (Interval: ${BACKUP_INTERVAL}s)..."
    while kill -0 $PORTAINER_PID > /dev/null 2>&1; do
        sleep "$BACKUP_INTERVAL"
        log_info "Scheduled backup triggered."
        if ! /app/services/portainer/backup.sh; then
            log_error "Backup failed. Retrying next cycle."
        else
            log_success "Scheduled backup completed."
        fi
    done
) &

# 4. Wait for Portainer to exit
wait $PORTAINER_PID
EXIT_CODE=$?
log_info "Portainer exited with code $EXIT_CODE"
exit $EXIT_CODE
