#!/usr/bin/env bash
# Remote RAM Access - Installer wrapper
# This creates the 'install' and 'uninstall' commands

echo "📦 Installing commands to /usr/local/bin/"
echo ""

# Create install command
sudo tee /usr/local/bin/install > /dev/null << 'INSTALL_CMD'
#!/bin/bash
# This script is auto-generated - do not edit
echo "📦 Fetching installer..."
curl -fsSL https://raw.githubusercontent.com/aplx-renz-sudo/remote-ram-access/main/install | sudo bash
INSTALL_CMD

# Create uninstall command
sudo tee /usr/local/bin/uninstall > /dev/null << 'UNINSTALL_CMD'
#!/bin/bash
# This script is auto-generated - do not edit
echo "🗑️  Removing Remote RAM Access..."

if [ "$EUID" -ne 0 ]; then
    sudo $0
    exit $?
fi

sudo systemctl stop remote-ram-server.service 2>/dev/null || true
sudo systemctl stop remote-ram-client.service 2>/dev/null || true
sleep 1

sudo systemctl disable remote-ram-server.service 2>/dev/null || true
sudo systemctl disable remote-ram-client.service 2>/dev/null || true

sudo rm -f /etc/systemd/system/remote-ram-server.service
sudo rm -f /etc/systemd/system/remote-ram-client.service
sudo rm -rf /opt/remote-ram-access

sudo systemctl daemon-reload

echo "✅ Uninstalled!"
echo ""
UNINSTALL_CMD

# Make executable
sudo chmod +x /usr/local/bin/install
sudo chmod +x /usr/local/bin/uninstall

echo "✓ Commands registered:"
echo ""
echo "  Install:   sudo install"
echo "  Uninstall: sudo uninstall"
echo ""
