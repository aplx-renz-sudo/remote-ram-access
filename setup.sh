#!/bin/bash
# Setup script - automatic installation wrapper

echo "🚀 Remote RAM Access System - Quick Setup"
echo "========================================="
echo ""

# Check if running on Linux
if [[ ! "$OSTYPE" == "linux-gnu"* ]]; then
    echo "❌ This system only supports Linux"
    exit 1
fi

# Check for Rust
if ! command -v cargo &> /dev/null; then
    echo "📦 Installing Rust (required for compilation)..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source $HOME/.cargo/env
    echo "   ✓ Rust installed"
else
    echo "✓ Rust already installed"
fi

# Check for required tools
echo ""
echo "🔍 Checking required tools..."

if ! command -v systemctl &> /dev/null; then
    echo "❌ systemd is required but not found"
    exit 1
fi
echo "   ✓ systemd found"

if ! command -v udevadm &> /dev/null; then
    echo "❌ udev is required but not found"
    exit 1
fi
echo "   ✓ udev found"

if ! command -v nc &> /dev/null; then
    echo "⚠️  netcat not found, installing..."
    if command -v apt &> /dev/null; then
        sudo apt update && sudo apt install -y netcat-openbsd
    elif command -v yum &> /dev/null; then
        sudo yum install -y nmap-ncat
    fi
fi
echo "   ✓ netcat available"

echo ""
echo "📥 Proceeding to full installation..."
echo ""

# Run actual installer
cd "$(dirname "$0")"
sudo ./install.sh
