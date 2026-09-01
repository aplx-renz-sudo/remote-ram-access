#!/bin/bash
# Uninstall script - removes all traces

if [ "$EUID" -ne 0 ]; then 
    echo "⚠️  This script requires sudo"
    echo "   Run: sudo ./uninstall.sh"
    exit 1
fi

echo "🗑️  Uninstalling Remote RAM Access..."
echo ""

echo "Stopping services..."
systemctl stop remote-ram-server.service 2>/dev/null || true
systemctl stop remote-ram-client.service 2>/dev/null || true
sleep 2

echo "Disabling services..."
systemctl disable remote-ram-server.service 2>/dev/null || true
systemctl disable remote-ram-client.service 2>/dev/null || true

echo "Removing services..."
rm -f /etc/systemd/system/remote-ram-server.service
rm -f /etc/systemd/system/remote-ram-client.service

echo "Removing installation..."
rm -rf /opt/remote-ram-access

echo "Reloading systemd..."
systemctl daemon-reload

echo ""
echo "✅ Uninstallation complete!"
echo "   All services and files removed."
echo ""
