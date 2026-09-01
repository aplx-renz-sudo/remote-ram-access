#!/bin/bash
# Uninstall script for Remote RAM Access System

set -e

echo "🗑️  Remote RAM Access System - Uninstallation"
echo "="*50

if [ "$EUID" -ne 0 ]; then 
    echo "⚠️  This script requires sudo"
    echo "   Run: sudo ./uninstall.sh"
    exit 1
fi

echo "Stopping services..."
sudo systemctl stop remote-ram-server.service 2>/dev/null || true
sudo systemctl stop remote-ram-client.service 2>/dev/null || true

echo "Disabling services..."
sudo systemctl disable remote-ram-server.service 2>/dev/null || true
sudo systemctl disable remote-ram-client.service 2>/dev/null || true

echo "Removing systemd services..."
sudo rm -f /etc/systemd/system/remote-ram-server.service
sudo rm -f /etc/systemd/system/remote-ram-client.service

echo "Removing udev rules..."
sudo rm -f /etc/udev/rules.d/99-remote-ram.rules

echo "Removing log rotation..."
sudo rm -f /etc/logrotate.d/remote-ram-access

echo "Removing installation directory..."
sudo rm -rf /opt/remote-ram-access

echo "Reloading systemd..."
sudo systemctl daemon-reload

echo "Reloading udev..."
sudo udevadm control --reload-rules

echo ""
echo "✅ Uninstallation complete!"
echo "   All services, files, and configurations removed."
echo ""
