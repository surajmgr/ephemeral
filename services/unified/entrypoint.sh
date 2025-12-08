#!/bin/bash
set -e

# --- Helper Functions ---
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

# --- Configuration ---
RUN_SERVICES=${RUN_SERVICES:-"typesense,novu"}
IFS=',' read -ra SERVICES <<< "$RUN_SERVICES"

# Check if a service is enabled
is_enabled() {
    local service=$1
    for s in "${SERVICES[@]}"; do
        if [[ "$s" == "$service" ]]; then
            return 0
        fi
    done
    return 1
}

# --- 1. Rclone Setup (if needed for backups) ---
# Similar to typesense/entrypoint.sh
if [[ ! -z "$RCLONE_CONFIG_REMOTE_TOKEN" ]]; then
    mkdir -p /root/.config/rclone
    cat > /root/.config/rclone/rclone.conf <<EOF
[remote]
type = ${RCLONE_CONFIG_REMOTE_TYPE:-pcloud}
token = {"access_token":"${RCLONE_CONFIG_REMOTE_TOKEN}","token_type":"bearer","expiry":"0001-01-01T00:00:00Z"}
EOF
    log_info "Rclone config generated."
fi

# --- 2. Start Minio (if Novu is enabled) ---
# Novu needs S3. If we don't have external S3, we run Minio.
# We run Minio if 'novu' is running OR if 'minio' is explicitly requested.
if is_enabled "novu" || is_enabled "minio"; then
    log_info "Starting Minio..."
    mkdir -p /data/minio
    # Minio default ports: 9000 (API), 9001 (Console)
    # We might need to remap if they conflict.
    export MINIO_ROOT_USER=${MINIO_ROOT_USER:-minioadmin}
    export MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD:-minioadmin}
    minio server /data/minio --console-address ":9001" &
    MINIO_PID=$!
    log_info "Minio started (PID $MINIO_PID)"
fi

# --- 3. Start Typesense ---
if is_enabled "typesense"; then
    log_info "Starting Typesense..."
    mkdir -p /data/typesense
    # Default port 8108.
    /usr/local/bin/typesense-server --data-dir /data/typesense --api-key="${TYPESENSE_API_KEY}" --enable-cors &
    TYPESENSE_PID=$!
    log_info "Typesense started (PID $TYPESENSE_PID)"
fi

# --- 4. Start Novu ---
if is_enabled "novu"; then
    log_info "Starting Novu Services..."

    # Ensure required env vars
    if [[ -z "$JWT_SECRET" ]]; then
        log_error "JWT_SECRET is missing!"
        exit 1
    fi

    # Start API
    cd /app/novu-api
    # Note: Novu API typically runs on port 3000.
    # The command depends on how the image was built.
    # Usually: npm run start:prod or node dist/main.js
    # We will try 'node dist/apps/api/main.js' or look for package.json script.
    # To be safe, we'll try to find the main file or use npm start.
    # As a fallback, we assume standard NestJS build output.
    log_info "Starting Novu API..."
    # We set specific ports to avoid conflict if any
    PORT=3000 node dist/apps/api/main.js &
    NOVU_API_PID=$!
    
    # Start Worker
    log_info "Starting Novu Worker..."
    # Worker often uses the same codebase but different entry point?
    # Or 'node dist/apps/worker/main.js'
    node dist/apps/worker/main.js &
    NOVU_WORKER_PID=$!

    # Start Web (Frontend)
    log_info "Starting Novu Web..."
    cd /app/novu-web/public
    # Serve static files on port 4200 (default Novu web port)
    serve -s . -l 4200 &
    NOVU_WEB_PID=$!
    
    # Start WS (WebSocket)
    # Usually 'node dist/apps/ws/main.js'
    # Check if necessary.
    log_info "Starting Novu WS..."
    cd /app/novu-api # Back to api dir for backend code
    PORT=3002 node dist/apps/ws/main.js &
    NOVU_WS_PID=$!
fi

# --- Monitor Loops ---
# Wait for any process to exit
wait -n
  
# Exit with status of process that exited
exit $?
