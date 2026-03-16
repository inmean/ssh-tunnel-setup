#!/bin/bash
# SSH Tunnel Setup Script for OpenClaw Gateway
# This script sets up a persistent SSH reverse tunnel for OpenClaw gateway communication with nodes on Linux using systemd.

set -e
# set -x    # Enable trace mode for debugging

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

# Function to run sudo commands with better error handling
run_sudo() {
    if ! sudo "$@" 2>/dev/null; then
        error_exit "Failed to run: sudo $*
This script requires sudo privileges. Please run the script with sudo or ensure your user has passwordless sudo access." "$EXIT_SYSTEMD_FAILURE"
    fi
}

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
    
    # Only prompt if not in remove mode
    if [ "$REMOVE_MODE" = false ]; then
        # Try to read from /dev/tty for interactive prompts (works with piped input)
        if [ -t 0 ] || [ -t 1 ]; then
            # Interactive terminal - ask user
            if read -p "Do you want to set up a new connection? [y/N]: " SETUP_RESPONSE < /dev/tty 2>/dev/null; then
                if [[ ! "$SETUP_RESPONSE" =~ ^[Yy]$ ]]; then
                    echo "Setup cancelled."
                    exit $EXIT_SUCCESS
                fi
                echo
            else
                # Couldn't read from tty, continue with warning
                echo "WARNING: Existing SSH tunnel services found."
                echo "Continuing with setup... (use --remove flag to remove existing services)"
                echo
            fi
        else
            # Non-interactive (piped) - print warning and continue
            echo "WARNING: Existing SSH tunnel services found."
            echo "Continuing with setup... (use --remove flag to remove existing services)"
            echo
        fi
    fi
else
    echo "No active SSH tunnel services found."
    echo
fi

if [ "$REMOVE_MODE" = false ]; then
    # Setup mode
    # Check if running interactively (using stdout as fallback when stdin is piped)
    if [ -t 0 ] || [ -t 1 ]; then
        # Interactive terminal - read from /dev/tty to work with piped input
        read -p "Enter remote host or IP: " REMOTE_HOST < /dev/tty
        read -p "Enter remote SSH port [22]: " REMOTE_PORT < /dev/tty
        REMOTE_PORT=${REMOTE_PORT:-22}
        read -p "Enter remote SSH username: " REMOTE_USER < /dev/tty
        read -p "Enter remote gateway port [18789]: " GATEWAY_PORT < /dev/tty
        GATEWAY_PORT=${GATEWAY_PORT:-18789}
        read -p "Enter local SSH key path [$HOME/.ssh/id_rsa]: " KEY_PATH < /dev/tty
    else
        # Non-interactive (piped input)
        echo "Running in non-interactive mode. Using defaults or arguments."
        # Read from stdin if available, otherwise use defaults
        read -r REMOTE_HOST || true
        read -r REMOTE_PORT || true
        read -r REMOTE_USER || true
        read -r GATEWAY_PORT || true
        read -r KEY_PATH || true
        
        # Apply defaults
        REMOTE_PORT=${REMOTE_PORT:-22}
        GATEWAY_PORT=${GATEWAY_PORT:-18789}
        KEY_PATH=${KEY_PATH:-$HOME/.ssh/id_rsa}
    fi

    # Validate inputs
    if [ -z "$REMOTE_HOST" ]; then
        error_exit "Remote host is required." "$EXIT_GENERAL_ERROR"
    fi
    if [ -z "$REMOTE_USER" ]; then
        error_exit "Remote username is required." "$EXIT_GENERAL_ERROR"
    fi
    if [ -z "$GATEWAY_PORT" ]; then
        error_exit "Gateway port is required." "$EXIT_GENERAL_ERROR"
    fi
    
    # Set default key path if empty and expand ~ to full home directory path
    if [ -z "$KEY_PATH" ]; then
        KEY_PATH="$HOME/.ssh/id_rsa"
    else
        KEY_PATH="${KEY_PATH/#\~/$HOME}"
    fi

    # Check if port is already in use
    if port_in_use "$GATEWAY_PORT"; then
        error_exit "Port $GATEWAY_PORT is already in use. Please choose a different port or stop the existing service." "$EXIT_PORT_IN_USE"
    fi

    # Check if key exists
    if [ ! -f "$KEY_PATH" ]; then
        GENERATE_KEY=false
        if [ -t 0 ] || [ -t 1 ]; then
            # Interactive terminal - read from /dev/tty
            if read -p "SSH key not found at $KEY_PATH. Generate new key? [y/N]: " GENERATE_RESPONSE < /dev/tty 2>/dev/null; then
                if [[ "$GENERATE_RESPONSE" =~ ^[Yy]$ ]]; then
                    GENERATE_KEY=true
                fi
            fi
        else
            # Non-interactive mode - ask via prompt but read from stdin
            echo "SSH key not found at $KEY_PATH. Generate new key? [y/N]: "
            read -r GENERATE_RESPONSE || true
            if [[ "$GENERATE_RESPONSE" =~ ^[Yy]$ ]]; then
                GENERATE_KEY=true
            fi
        fi
        
        if [ "$GENERATE_KEY" = true ]; then
            echo "Generating SSH key pair at $KEY_PATH..."
            ssh-keygen -t rsa -b 4096 -f "$KEY_PATH" -N "" || error_exit "Failed to generate SSH key." "$EXIT_SSH_FAILURE"
        else
            error_exit "SSH key not found at $KEY_PATH. Please provide an existing key or generate a new one." "$EXIT_GENERAL_ERROR"
        fi
    fi

    # Set permissions
    chmod 600 "$KEY_PATH" || error_exit "Failed to set permissions on private key." "$EXIT_GENERAL_ERROR"

    # Copy public key to remote server
    echo "Copying public key to $REMOTE_USER@$REMOTE_HOST:$REMOTE_PORT..."
    # Note: ssh-copy-id expects -o options before -p port
    CMD="ssh-copy-id -i \"${KEY_PATH}.pub\" -o StrictHostKeyChecking=accept-new -p \"$REMOTE_PORT\" \"$REMOTE_USER@$REMOTE_HOST\""
    echo "Running: $CMD"
    eval $CMD || error_exit "Failed to copy public key to remote server. Check password authentication." "$EXIT_SSH_FAILURE"
    
    # Note: Using local port forwarding (-L), not remote port forwarding (-R)
    # No GatewayPorts configuration needed on remote server

    # Create systemd service
    SERVICE_NAME="ssh-tunnel-$GATEWAY_PORT.service"
    SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"

    echo "Creating systemd service $SERVICE_NAME..."
    cat <<EOF | run_sudo tee "$SERVICE_FILE" >/dev/null
[Unit]
Description=SSH Local Tunnel to $REMOTE_HOST:$GATEWAY_PORT (OpenClaw Gateway)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$(whoami)
ExecStart=/usr/bin/ssh -i "$KEY_PATH" -p $REMOTE_PORT -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes -N -L 127.0.0.1:$GATEWAY_PORT:127.0.0.1:$GATEWAY_PORT $REMOTE_USER@$REMOTE_HOST
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Enable and start service
    run_sudo systemctl daemon-reload
    run_sudo systemctl enable "$SERVICE_NAME"
    run_sudo systemctl start "$SERVICE_NAME"

    # Verify service
    echo "Checking service status..."
    run_sudo systemctl status "$SERVICE_NAME" --no-pager

    echo
    echo "=== Setup Complete ==="
    echo "Tunnel is active: 127.0.0.1:$GATEWAY_PORT -> $REMOTE_HOST:$GATEWAY_PORT"
    echo "Test with: nc -zv 127.0.0.1 $GATEWAY_PORT"
    echo "For OpenClaw gateway communication, configure your node to connect to 127.0.0.1:$GATEWAY_PORT"

else
    # Remove mode
    if [ -t 0 ] || [ -t 1 ]; then
        read -p "Enter remote gateway port to remove [18789]: " GATEWAY_PORT < /dev/tty
    else
        read -r GATEWAY_PORT || true
        GATEWAY_PORT=${GATEWAY_PORT:-18789}
    fi

    SERVICE_NAME="ssh-tunnel-$GATEWAY_PORT.service"
    SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"

    if [ ! -f "$SERVICE_FILE" ]; then
        echo "Service $SERVICE_NAME not found. Nothing to remove."
        exit $EXIT_SUCCESS
    fi

    echo "Stopping service $SERVICE_NAME..."
    run_sudo systemctl stop "$SERVICE_NAME"

    echo "Disabling service $SERVICE_NAME..."
    run_sudo systemctl disable "$SERVICE_NAME"

    echo "Removing service file..."
    run_sudo rm "$SERVICE_FILE"

    run_sudo systemctl daemon-reload

    echo
    echo "=== Removal Complete ==="
    echo "Service $SERVICE_NAME has been removed."
fi
