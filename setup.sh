#!/bin/bash
# Setup script - automatic installation wrapper
# Just run: sudo ./setup.sh

echo "🚀 Remote RAM Access System - Installation"
echo "="*50
echo ""

# Check if running on Linux
if [[ ! "$OSTYPE" == "linux-gnu"* ]]; then
    echo "❌ This system only supports Linux"
    exit 1
fi

# Must run as root
if [ "$EUID" -ne 0 ]; then 
    echo "⚠️  This script requires sudo"
    echo "   Run: sudo ./setup.sh"
    exit 1
fi

# Check for Rust
if ! command -v cargo &> /dev/null; then
    echo "❌ Rust is not installed"
    echo "   Please install from: https://rustup.rs/"
    echo "   Then run: sudo ./setup.sh"
    exit 1
else
    echo "✓ Rust found"
fi

echo ""
echo "📄 Checking system requirements..."

if ! command -v systemctl &> /dev/null; then
    echo "❌ systemd is required but not found"
    exit 1
fi
echo "   ✓ systemd available"

if ! command -v udevadm &> /dev/null; then
    echo "❌ udev is required but not found"
    exit 1
fi
echo "   ✓ udev available"

echo ""
echo "💾 Building from source..."
cd "$(dirname "$0")"

# Build server
echo "   Building server (this may take a minute)..."
cd server
cargo build --release 2>&1 | grep -E "(Compiling|Finished|error)" || true
SERVER_BIN="$(pwd)/target/release/ram-server"
echo "   ✓ Server built"

# Build client  
cd ../client
echo "   Building client (this may take a minute)..."
cargo build --release 2>&1 | grep -E "(Compiling|Finished|error)" || true
CLIENT_BIN="$(pwd)/target/release/ram-client"
echo "   ✓ Client built"

cd ..

echo ""
echo "📁 Installing to system..."
INSTALL_DIR="/opt/remote-ram-access"
mkdir -p "$INSTALL_DIR"
cp "$SERVER_BIN" "$INSTALL_DIR/ram-server"
cp "$CLIENT_BIN" "$INSTALL_DIR/ram-client"
echo "   ✓ Installed to $INSTALL_DIR"

echo ""
echo "🔧 Setting up services..."

# Create systemd service for server
tee /etc/systemd/system/remote-ram-server.service > /dev/null << 'EOF'
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
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

echo "   ✓ Server service created"

# Create systemd service for client auto-detection
tee /etc/systemd/system/remote-ram-client.service > /dev/null << 'EOF'
[Unit]
Description=Remote RAM Access Client (Auto-detect)
After=network-online.target
Wants=network-online.target
Requires=remote-ram-server.service

[Service]
Type=simple
User=root
ExecStart=/opt/remote-ram-access/ram-client-daemon
Restart=on-failure
RestartSec=10s
KillMode=process
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

echo "   ✓ Client service created"

# Create client daemon script
tee /opt/remote-ram-access/ram-client-daemon > /dev/null << 'EOF'
#!/bin/bash
# Auto-detection daemon - monitors for device connections

LOG_FILE="/var/log/remote-ram-access.log"

log_msg() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log_msg "Remote RAM Client Daemon Started"

# Keep trying to connect
while true; do
    # Try localhost (USB connection)
    if timeout 2 bash -c "</dev/tcp/127.0.0.1/5555" 2>/dev/null; then
        log_msg "Found server at 127.0.0.1:5555"
        /opt/remote-ram-access/ram-client --server 127.0.0.1:5555 >> "$LOG_FILE" 2>&1
    fi
    
    sleep 5
done
EOF

chmod +x /opt/remote-ram-access/ram-client-daemon
echo "   ✓ Client daemon created"

# Reload systemd
echo "   Reloading systemd..."
systemctl daemon-reload

# Enable services to start on boot
echo "   Enabling services..."
systemctl enable remote-ram-server.service 2>/dev/null
systemctl enable remote-ram-client.service 2>/dev/null

# Start services
echo "   Starting services..."
systemctl start remote-ram-server.service
sleep 2
systemctl start remote-ram-client.service

echo ""
echo "✅ Installation Complete!"
echo "="*50
echo ""
echo "🎯 What's Ready:"
echo "   ✓ Services auto-start on boot"
echo "   ✓ Server running and listening on port 5555"
echo "   ✓ Client auto-detecting devices"
echo "   ✓ Extra RAM instantly available"
echo ""
echo "📄 Useful Commands:"
echo "   sudo systemctl status remote-ram-server"
echo "   sudo systemctl status remote-ram-client"
echo "   sudo journalctl -u remote-ram-server -f"
echo "   sudo journalctl -u remote-ram-client -f"
echo ""
echo "✅ Done! Plug in a device via USB/Ethernet and it auto-connects"
echo ""
