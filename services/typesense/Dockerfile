FROM typesense/typesense:29.0

# Install dependencies for scripts
USER root
RUN apt-get update && apt-get install -y curl tar jq bash unzip && \
    rm -rf /var/lib/apt/lists/*

# Install rclone
COPY scripts/install_rclone.sh /tmp/install_rclone.sh
RUN chmod +x /tmp/install_rclone.sh && /tmp/install_rclone.sh && rm /tmp/install_rclone.sh

# Setup directories
WORKDIR /app

# Copy scripts
COPY scripts/utils.sh /app/scripts/utils.sh
COPY services/typesense/backup.sh /app/services/typesense/backup.sh
COPY services/typesense/restore.sh /app/services/typesense/restore.sh
COPY services/typesense/entrypoint.sh /app/services/typesense/entrypoint.sh

# Permissions
RUN chmod +x /app/services/typesense/*.sh /app/scripts/*.sh

# Create data directory just in case
RUN mkdir -p /data

# Data dir for snapshot temp
RUN mkdir -p /tmp/typesense-snapshots

# Set Entrypoint
ENTRYPOINT ["/app/services/typesense/entrypoint.sh"]
