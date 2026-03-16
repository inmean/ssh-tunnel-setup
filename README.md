# SSH Tunnel Setup for OpenClaw Gateway

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Automated SSH reverse tunnel setup for OpenClaw gateway communication with nodes on Linux using systemd.

## Table of Contents

- [Purpose](#purpose)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
  - [Setup Mode](#setup-mode)
  - [Remove Mode](#remove-mode)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)
- [License](#license)

## Purpose

This script helps users quickly set up a persistent SSH reverse tunnel for OpenClaw gateway communication with nodes on Linux. It automates the process of generating SSH keys, authorizing remote access, and creating a systemd service for the tunnel.

## Features

- **Single-file Bash script**: Easy to download and run.
- **Interactive prompts**: Guides users through configuration.
- **Systemd integration**: Creates a persistent service that starts on boot and restarts on failure.
- **OpenClaw focus**: Designed for OpenClaw gateway-to-node communication (SEO: OpenClaw SSH tunnel setup).
- **Uninstall option**: Cleanly removes the service when no longer needed.
- **Error handling**: Exits immediately on errors with specific exit codes.

## Requirements

- Linux distribution with systemd (e.g., Ubuntu, Debian, CentOS, Fedora, Arch).
- OpenSSH client (`ssh`, `ssh-copy-id`).
- `iproute2` (for `ss` command).
- Root/sudo access for systemd service creation.

## Installation

### One-line Install

**Direct execution (recommended for quick use):**

```bash
curl -fsSL https://raw.githubusercontent.com/inmean/ssh-tunnel-setup/main/ssh_tunnel_setup.sh | bash
```

**Download and execute (save script locally):**

```bash
curl -fsSL https://raw.githubusercontent.com/inmean/ssh-tunnel-setup/main/ssh_tunnel_setup.sh -o ssh_tunnel_setup.sh && chmod +x ssh_tunnel_setup.sh && ./ssh_tunnel_setup.sh
```

**Using wget:**

```bash
wget -q https://raw.githubusercontent.com/inmean/ssh-tunnel-setup/main/ssh_tunnel_setup.sh -O ssh_tunnel_setup.sh && chmod +x ssh_tunnel_setup.sh && ./ssh_tunnel_setup.sh
```

### Git Clone

Alternatively, clone the repository:

```bash
git clone git@github.com:inmean/ssh-tunnel-setup.git
cd ssh-tunnel-setup
chmod +x ssh_tunnel_setup.sh
```

## Usage

### Setup Mode

Run the script without arguments to set up a new tunnel:

```bash
./ssh_tunnel_setup.sh
```

The script will prompt for:
- Remote host or IP
- Remote SSH port (default: 22)
- Remote SSH username
- Remote gateway port (default: 18789)
- Local SSH key path (default: ~/.ssh/id_rsa)

### Remove Mode

Run the script with `--remove` to remove an existing tunnel:

```bash
./ssh_tunnel_setup.sh --remove
```

The script will prompt for the remote gateway port to remove.

## Examples

### Setup a tunnel for OpenClaw gateway

```bash
./ssh_tunnel_setup.sh
# Enter remote host: 192.168.85.27
# Enter remote SSH port: 22
# Enter remote SSH username: inmean
# Enter remote gateway port: 18789
# Enter local SSH key path: ~/.ssh/id_rsa
```

### Remove a tunnel

```bash
./ssh_tunnel_setup.sh --remove
# Enter remote gateway port to remove: 18789
```

## Troubleshooting

### Port already in use

Error: "Port 18789 is already in use"
- Solution: Choose a different port or stop the existing service using `sudo systemctl stop ssh-tunnel-18789.service`.

### SSH connection failed

Error: "Failed to copy public key to remote server"
- Solution: Ensure password authentication is enabled on the remote server for the initial key copy. After setup, you can disable password authentication if desired.

### Service fails to start

Check service logs:
```bash
sudo journalctl -u ssh-tunnel-18789.service
```

Common issues:
- Remote server does not allow remote port forwarding (check `GatewayPorts` in `/etc/ssh/sshd_config`).
- Firewall blocking the port.

### OpenClaw Gateway Communication

This tunnel is designed for OpenClaw gateway-to-node communication. After setup, configure your OpenClaw node to connect to `127.0.0.1:<gateway_port>`.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
