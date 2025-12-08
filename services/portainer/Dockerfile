FROM portainer/portainer-ce:alpine

# Install dependencies for scripts
RUN apk update && apk add --no-cache curl tar jq bash unzip ca-certificates fuse

# Install rclone
COPY scripts/install_rclone.sh /tmp/install_rclone.sh
RUN chmod +x /tmp/install_rclone.sh && /tmp/install_rclone.sh && rm /tmp/install_rclone.sh

# Setup directories
WORKDIR /app

# Copy scripts
COPY scripts/utils.sh /app/scripts/utils.sh
COPY services/portainer/backup.sh /app/services/portainer/backup.sh
COPY services/portainer/restore.sh /app/services/portainer/restore.sh
COPY services/portainer/entrypoint.sh /app/services/portainer/entrypoint.sh

# Permissions
RUN chmod +x /app/services/portainer/*.sh /app/scripts/*.sh

# Portainer data dir is /data
RUN mkdir -p /data
RUN mkdir -p /tmp/portainer-snapshots

# Set Entrypoint
ENTRYPOINT ["/app/services/portainer/entrypoint.sh"]
