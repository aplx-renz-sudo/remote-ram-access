#!/bin/bash
# Installation script for Remote RAM Access System
# Installs systemd service and auto-detection daemon

set -e

echo "🚀 Remote RAM Access System - Installation"
echo "="*50

if [ "$EUID" -ne 0 ]; then 
    echo "⚠️  This script requires sudo for system installation"
    echo "   Run: sudo ./install.sh"
    exit 1
fi

echo "📦 Building server and client..."
cd "$(dirname "$0")"

# Build server
echo "   Building server..."
cd server && cargo build --release 2>/dev/null
SERVER_BIN="$(pwd)/target/release/ram-server"
echo "   ✓ Server built"

# Build client
cd ../client && cargo build --release 2>/dev/null
CLIENT_BIN="$(pwd)/target/release/ram-client"
echo "   ✓ Client built"

cd ..

# Create installation directory
echo "📁 Creating installation directory..."
INSTALL_DIR="/opt/remote-ram-access"
sudo mkdir -p "$INSTALL_DIR"
sudo cp "$SERVER_BIN" "$INSTALL_DIR/ram-server"
sudo cp "$CLIENT_BIN" "$INSTALL_DIR/ram-client"
echo "   ✓ Installed to $INSTALL_DIR"

# Create systemd service for server
echo "🔧 Setting up systemd services..."
echo "   Creating server service..."
sudo tee /etc/systemd/system/remote-ram-server.service > /dev/null << 'EOF'
[Unit]
Description=Remote RAM Access Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/opt/remote-ram-access/ram-server --port 5555 --pool-size 2048
Restart=on-failure
RestartSec=10s
KillMode=process
KillSignal=SIGTERM

[Install]
WantedBy=multi-user.target
EOF

echo "   Creating client auto-detect service..."
sudo tee /etc/systemd/system/remote-ram-client.service > /dev/null << 'EOF'
[Unit]
Description=Remote RAM Access Client (Auto-detect)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/opt/remote-ram-access/ram-client-daemon
Restart=on-failure
RestartSec=10s
KillMode=process
KillSignal=SIGTERM

[Install]
WantedBy=multi-user.target
EOF

# Install udev rules for device detection
echo "   Creating udev rules for device detection..."
sudo tee /etc/udev/rules.d/99-remote-ram.rules > /dev/null << 'EOF'
# Detect USB device connections
SUBSYSTEM=="usb", ATTR{idVendor}=="*", ACTION=="add", RUN+="/opt/remote-ram-access/detect-device.sh add %s"
SUBSYSTEM=="usb", ATTR{idVendor}=="*", ACTION=="remove", RUN+="/opt/remote-ram-access/detect-device.sh remove %s"

# Detect Ethernet device connections
SUBSYSTEM=="net", ACTION=="add", RUN+="/opt/remote-ram-access/detect-device.sh add network %s"
SUBSYSTEM=="net", ACTION=="remove", RUN+="/opt/remote-ram-access/detect-device.sh remove network %s"
EOF

# Create device detection script
echo "   Creating device detection daemon..."
sudo tee /opt/remote-ram-access/detect-device.sh > /dev/null << 'EOF'
#!/bin/bash
# Auto-detect connected devices and start client

ACTION=$1
DEVICE_TYPE=$2
DEVICE=$3

LOG_FILE="/var/log/remote-ram-access.log"

log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

if [ "$ACTION" = "add" ]; then
    log_message "Device detected: $DEVICE_TYPE - $DEVICE"
    
    # Wait for device to be ready
    sleep 2
    
    # Try to detect IP and connect
    if [ "$DEVICE_TYPE" = "usb" ]; then
        # USB device - try localhost first
        DEVICE_IP="127.0.0.1"
    else
        # Network device - scan for server
        DEVICE_IP=$(arp-scan -l 2>/dev/null | grep -i "remote-ram" | awk '{print $1}' | head -1)
        if [ -z "$DEVICE_IP" ]; then
            # Try common gateway
            DEVICE_IP="192.168.1.1"
        fi
    fi
    
    log_message "Attempting connection to $DEVICE_IP:5555"
    
    # Start client in background
    nohup /opt/remote-ram-access/ram-client --server "$DEVICE_IP:5555" >> "$LOG_FILE" 2>&1 &
    log_message "Client started (PID: $!)"
    
elif [ "$ACTION" = "remove" ]; then
    log_message "Device disconnected: $DEVICE_TYPE - $DEVICE"
    
    # Kill any connected clients
    killall -q ram-client 2>/dev/null || true
    log_message "Client disconnected"
fi
EOF

sudo chmod +x /opt/remote-ram-access/detect-device.sh

# Create client daemon wrapper
echo "   Creating client daemon wrapper..."
sudo tee /opt/remote-ram-access/ram-client-daemon > /dev/null << 'EOF'
#!/bin/bash
# Client daemon - monitors for device connections and auto-starts

LOG_FILE="/var/log/remote-ram-access.log"

log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log_message "=== Remote RAM Client Daemon Started ==="

# Function to try connecting to a server
try_connect() {
    local ip=$1
    local port=${2:-5555}
    
    if nc -z -w 1 "$ip" "$port" 2>/dev/null; then
        log_message "Found server at $ip:$port - connecting..."
        /opt/remote-ram-access/ram-client --server "$ip:$port" >> "$LOG_FILE" 2>&1
        return 0
    fi
    return 1
}

# Monitor for device connections
while true; do
    # Check for USB devices
    if lsusb | grep -q .; then
        # Try localhost first (direct USB connection)
        if try_connect 127.0.0.1 5555; then
            log_message "Connected via USB"
            sleep 30
            continue
        fi
    fi
    
    # Check for network devices
    if ip link show | grep -q "state UP"; then
        # Get gateway IP and try connecting
        GATEWAY=$(ip route | grep default | awk '{print $3}' | head -1)
        
        if [ -n "$GATEWAY" ]; then
            # Try gateway
            if try_connect "$GATEWAY" 5555; then
                log_message "Connected via network (gateway: $GATEWAY)"
                sleep 30
                continue
            fi
            
            # Try common local IPs (192.168.1.x, 10.0.0.x)
            for i in {1..10}; do
                IP="192.168.1.$i"
                if try_connect "$IP" 5555; then
                    log_message "Connected via network ($IP)"
                    sleep 30
                    continue 2
                fi
            done
        fi
    fi
    
    # Wait before retrying
    sleep 5
done
EOF

sudo chmod +x /opt/remote-ram-access/ram-client-daemon

# Reload udev rules
echo "   Reloading udev rules..."
sudo udevadm control --reload-rules
sudo udevadm trigger

# Enable and start services
echo "🚀 Enabling services..."
sudo systemctl daemon-reload
sudo systemctl enable remote-ram-server.service
sudo systemctl enable remote-ram-client.service
sudo systemctl start remote-ram-server.service
sudo systemctl start remote-ram-client.service

echo "   ✓ Server service enabled and started"
echo "   ✓ Client service enabled and started"

# Create log rotation config
echo "📝 Setting up log rotation..."
sudo tee /etc/logrotate.d/remote-ram-access > /dev/null << 'EOF'
/var/log/remote-ram-access.log {
    daily
    rotate 7
    compress
    delaycompress
    notifempty
    create 0640 root root
}
EOF

echo ""
echo "✅ Installation Complete!"
echo "="*50
echo ""
echo "📋 What's installed:"
echo "   • Binary location: /opt/remote-ram-access/"
echo "   • Server service: remote-ram-server.service"
echo "   • Client daemon: remote-ram-client.service"
echo "   • Device detection: udev rules + daemon"
echo "   • Logs: /var/log/remote-ram-access.log"
echo ""
echo "🔧 Service Management:"
echo "   Start server:    sudo systemctl start remote-ram-server"
echo "   Stop server:     sudo systemctl stop remote-ram-server"
echo "   Start client:    sudo systemctl start remote-ram-client"
echo "   Stop client:     sudo systemctl stop remote-ram-client"
echo "   View status:     sudo systemctl status remote-ram-*"
echo "   View logs:       sudo journalctl -u remote-ram-server -f"
echo "                    sudo journalctl -u remote-ram-client -f"
echo ""
echo "🎯 Auto-detection:"
echo "   • When a USB device is connected, client auto-starts"
echo "   • When a network device is detected, client auto-connects"
echo "   • All without any manual intervention required!"
echo ""
echo "✨ Your system now has extended RAM available!"
echo ""
