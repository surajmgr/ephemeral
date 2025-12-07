#!/bin/bash
set -e

# Install rclone
# Usage: ./install_rclone.sh

echo "Installing rclone..."
curl https://rclone.org/install.sh | bash

echo "Rclone installed successfully."
rclone --version
