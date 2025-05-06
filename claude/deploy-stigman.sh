#!/bin/bash
set -e

# Create directories
mkdir -p ~/.config/containers/systemd
mkdir -p certs

# Generate self-signed certificates if not already present
if [ ! -f certs/server.crt ]; then
  echo "Generating self-signed certificates..."
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout certs/server.key -out certs/server.crt \
    -subj "/CN=localhost"
fi

# Copy quadlet files to systemd user directory
cp *.kube *.container *.volume ~/.config/containers/systemd/

# Reload systemd
systemctl --user daemon-reload

# Start the pod and containers
systemctl --user start stigman-pod.service
systemctl --user start stigman-mysql.service
systemctl --user start stigman-keycloak.service
systemctl --user start stigman-api.service
systemctl --user start stigman-nginx.service

# Enable auto-start
systemctl --user enable stigman-pod.service
systemctl --user enable stigman-mysql.service
systemctl --user enable stigman-keycloak.service
systemctl --user enable stigman-api.service
systemctl --user enable stigman-nginx.service

echo "STIG Manager has been deployed!"
echo "Access it at: https://$(hostname -f)/"
echo "Initial Keycloak admin credentials: admin:admin"
