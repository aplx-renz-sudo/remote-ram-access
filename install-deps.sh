#!/bin/bash
# Install dependencies for Remote RAM Access

echo "Installing dependencies..."

if command -v apt &> /dev/null; then
    # Debian/Ubuntu
    sudo apt update
    sudo apt install -y build-essential pkg-config libssl-dev netcat-openbsd net-tools
    echo "✓ Dependencies installed (Debian/Ubuntu)"
elif command -v yum &> /dev/null; then
    # RHEL/CentOS/Fedora
    sudo yum groupinstall -y "Development Tools"
    sudo yum install -y pkg-config openssl-devel nmap-ncat net-tools
    echo "✓ Dependencies installed (RHEL/CentOS/Fedora)"
elif command -v pacman &> /dev/null; then
    # Arch
    sudo pacman -S base-devel openssl net-tools nmap
    echo "✓ Dependencies installed (Arch Linux)"
else
    echo "⚠️  Unsupported package manager. Please install manually:"
    echo "    - build-essential"
    echo "    - pkg-config"
    echo "    - openssl-dev"
    echo "    - netcat"
    echo "    - net-tools"
fi
