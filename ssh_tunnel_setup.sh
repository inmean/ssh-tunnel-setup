#!/bin/bash
# SSH Tunnel Setup Script for OpenClaw Gateway
# This script sets up a persistent SSH reverse tunnel for OpenClaw gateway communication with nodes on Linux using systemd.

set -e

# Exit codes
EXIT_SUCCESS=0
EXIT_GENERAL_ERROR=1
EXIT_PORT_IN_USE=2
EXIT_SSH_FAILURE=3
EXIT_SYSTEMD_FAILURE=4

# Function to print error message and exit
error_exit() {
    echo "Error: $1" >&2
    exit "$2"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if port is in use
port_in_use() {
    ss -tuln | grep ":$1 " >/dev/null 2>&1
}

# Parse command-line arguments
REMOVE_MODE=false
if [[ "$1" == "--remove" ]]; then
    REMOVE_MODE=true
fi

# Check prerequisites
if ! command_exists ssh; then
    error_exit "OpenSSH client (ssh) is not installed. Please install it before running this script." "$EXIT_GENERAL_ERROR"
fi

if ! command_exists ssh-copy-id; then
    error_exit "ssh-copy-id is not installed. Please install openssh-client before running this script." "$EXIT_GENERAL_ERROR"
fi

if ! command_exists systemctl; then
    error_exit "systemd is not available. This script requires systemd to manage services." "$EXIT_SYSTEMD_FAILURE"
fi

if ! command_exists ss; then
    error_exit "ss command (from iproute2) is not available. Please install iproute2 before running this script." "$EXIT_GENERAL_ERROR"
fi

# Interactive configuration
echo "=== SSH Tunnel Setup for OpenClaw Gateway ==="
echo

# Detect existing ssh-tunnel-*.service services
echo "Checking for existing SSH tunnel services..."
EXISTING_SERVICES=$(systemctl list-units --type=service --state=active --no-legend --no-pager 2>/dev/null | grep "ssh-tunnel-" || true)
if [ -n "$EXISTING_SERVICES" ]; then
    echo "The following SSH tunnel services are currently running:"
    echo "$EXISTING_SERVICES"
    echo
else
    echo "No active SSH tunnel services found."
    echo
fi

if [ "$REMOVE_MODE" = false ]; then
    # Setup mode
    read -p "Enter remote host or IP: " REMOTE_HOST
    if [ -z "$REMOTE_HOST" ]; then
        error_exit "Remote host is required." "$EXIT_GENERAL_ERROR"
    fi

    read -p "Enter remote SSH port [22]: " REMOTE_PORT
    REMOTE_PORT=${REMOTE_PORT:-22}

    read -p "Enter remote SSH username: " REMOTE_USER
    if [ -z "$REMOTE_USER" ]; then
        error_exit "Remote username is required." "$EXIT_GENERAL_ERROR"
    fi

    read -p "Enter remote gateway port [18789]: " GATEWAY_PORT
    GATEWAY_PORT=${GATEWAY_PORT:-18789}

    read -p "Enter local SSH key path [~/.ssh/id_rsa]: " KEY_PATH
    KEY_PATH=${KEY_PATH:-~/.ssh/id_rsa}
    KEY_PATH=$(eval echo "$KEY_PATH")  # Expand ~

    # Check if port is already in use
    if port_in_use "$GATEWAY_PORT"; then
        error_exit "Port $GATEWAY_PORT is already in use. Please choose a different port or stop the existing service." "$EXIT_PORT_IN_USE"
    fi

    # Check if key exists, generate if not
    if [ ! -f "$KEY_PATH" ]; then
        echo "Generating SSH key pair at $KEY_PATH..."
        ssh-keygen -t rsa -b 4096 -f "$KEY_PATH" -N "" || error_exit "Failed to generate SSH key." "$EXIT_SSH_FAILURE"
    fi

    # Set permissions
    chmod 600 "$KEY_PATH" || error_exit "Failed to set permissions on private key." "$EXIT_GENERAL_ERROR"

    # Copy public key to remote server
    echo "Copying public key to $REMOTE_USER@$REMOTE_HOST:$REMOTE_PORT..."
    ssh-copy-id -i "${KEY_PATH}.pub" -p "$REMOTE_PORT" "$REMOTE_USER@$REMOTE_HOST" -o StrictHostKeyChecking=accept-new || error_exit "Failed to copy public key to remote server. Check password authentication." "$EXIT_SSH_FAILURE"

    # Create systemd service
    SERVICE_NAME="ssh-tunnel-$GATEWAY_PORT.service"
    SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"

    echo "Creating systemd service $SERVICE_NAME..."
    cat <<EOF | sudo tee "$SERVICE_FILE" >/dev/null
[Unit]
Description=SSH Reverse Tunnel to $REMOTE_HOST:$GATEWAY_PORT (OpenClaw Gateway)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$(whoami)
ExecStart=/usr/bin/ssh -i $KEY_PATH \
  -p $REMOTE_PORT \
  -o StrictHostKeyChecking=accept-new \
  -o ServerAliveInterval=60 \
  -o ServerAliveCountMax=3 \
  -o ExitOnForwardFailure=yes \
  -N \
  -R 127.0.0.1:$GATEWAY_PORT:127.0.0.1:$GATEWAY_PORT \
  $REMOTE_USER@$REMOTE_HOST
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Enable and start service
    sudo systemctl daemon-reload || error_exit "Failed to reload systemd daemon." "$EXIT_SYSTEMD_FAILURE"
    sudo systemctl enable "$SERVICE_NAME" || error_exit "Failed to enable service." "$EXIT_SYSTEMD_FAILURE"
    sudo systemctl start "$SERVICE_NAME" || error_exit "Failed to start service." "$EXIT_SYSTEMD_FAILURE"

    # Verify service
    echo "Checking service status..."
    sudo systemctl status "$SERVICE_NAME" --no-pager

    echo
    echo "=== Setup Complete ==="
    echo "Tunnel is active: 127.0.0.1:$GATEWAY_PORT -> $REMOTE_HOST:$GATEWAY_PORT"
    echo "Test with: nc -zv 127.0.0.1 $GATEWAY_PORT"
    echo "For OpenClaw gateway communication, configure your node to connect to 127.0.0.1:$GATEWAY_PORT"

else
    # Remove mode
    read -p "Enter remote gateway port to remove [18789]: " GATEWAY_PORT
    GATEWAY_PORT=${GATEWAY_PORT:-18789}

    SERVICE_NAME="ssh-tunnel-$GATEWAY_PORT.service"
    SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"

    if [ ! -f "$SERVICE_FILE" ]; then
        echo "Service $SERVICE_NAME not found. Nothing to remove."
        exit $EXIT_SUCCESS
    fi

    echo "Stopping service $SERVICE_NAME..."
    sudo systemctl stop "$SERVICE_NAME" || error_exit "Failed to stop service." "$EXIT_SYSTEMD_FAILURE"

    echo "Disabling service $SERVICE_NAME..."
    sudo systemctl disable "$SERVICE_NAME" || error_exit "Failed to disable service." "$EXIT_SYSTEMD_FAILURE"

    echo "Removing service file..."
    sudo rm "$SERVICE_FILE" || error_exit "Failed to remove service file." "$EXIT_GENERAL_ERROR"

    sudo systemctl daemon-reload || error_exit "Failed to reload systemd daemon." "$EXIT_SYSTEMD_FAILURE"

    echo
    echo "=== Removal Complete ==="
    echo "Service $SERVICE_NAME has been removed."
fi
