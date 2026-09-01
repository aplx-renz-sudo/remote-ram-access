# Quick Start Guide - Auto-Detection Installation

## Installation (One Command)

```bash
cd remote-ram-access
chmod +x setup.sh
sudo ./setup.sh
```

That's it! The system will:
- Build the server and client
- Install systemd services
- Setup device auto-detection
- Enable automatic startup
- Configure logging

## What Happens Automatically

### When you plug in a device via USB/Ethernet:

1. **Device is detected** → udev rule triggers
2. **Daemon starts** → Attempts connection to remote device
3. **Connection established** → RAM automatically registered with OS
4. **Your apps get extra RAM** → Transparent to applications

### When you unplug the device:

1. **Device removal detected** → udev rule triggers
2. **Client disconnects** → Cleanup happens automatically
3. **No issues or errors** → System operates normally

## Service Management

### Check status
```bash
sudo systemctl status remote-ram-server
sudo systemctl status remote-ram-client
```

### View real-time logs
```bash
sudo journalctl -u remote-ram-server -f
sudo journalctl -u remote-ram-client -f
sudo tail -f /var/log/remote-ram-access.log
```

### Manual control
```bash
# Start/stop services
sudo systemctl start remote-ram-server
sudo systemctl stop remote-ram-server

# Restart services
sudo systemctl restart remote-ram-server
sudo systemctl restart remote-ram-client

# Disable auto-start (keep installed)
sudo systemctl disable remote-ram-server
sudo systemctl disable remote-ram-client

# Enable auto-start again
sudo systemctl enable remote-ram-server
sudo systemctl enable remote-ram-client
```

## Uninstall

```bash
cd remote-ram-access
chmod +x uninstall.sh
sudo ./uninstall.sh
```

This removes:
- All binaries and files
- Systemd services
- Udev rules
- Log files and configuration
- Completely clean uninstall

## Troubleshooting

### Service won't start
```bash
# Check what's wrong
sudo journalctl -u remote-ram-server -n 50

# Try manual start for debugging
sudo /opt/remote-ram-access/ram-server --port 5555 --pool-size 2048
```

### Device not auto-detected
```bash
# Check udev rules
sudo cat /etc/udev/rules.d/99-remote-ram.rules

# Reload udev
sudo udevadm control --reload-rules
sudo udevadm trigger

# Monitor udev events
sudo udevadm monitor
```

### Check all logs
```bash
# System logs
sudo journalctl -u remote-ram-server -u remote-ram-client -n 100

# Application log
sudo tail -100 /var/log/remote-ram-access.log

# Kernel logs
sudo dmesg | tail -20
```

## How It Works Behind the Scenes

### System Services
- **remote-ram-server.service** - Runs on remote device, manages RAM pools
- **remote-ram-client.service** - Runs on local device, auto-detects and connects

### Device Detection
- **udev rules** - Automatically trigger on USB/Ethernet device connection
- **Device daemon** - Continuously monitors for new connections
- **Auto-connect** - Intelligently tries to find and connect to servers

### Safety Features
- **Systemd restarts on failure** - Service automatically restarts if it crashes
- **Logging** - All activity logged to /var/log/remote-ram-access.log
- **Log rotation** - Old logs automatically cleaned up (7 day retention)
- **Graceful cleanup** - Properly closes connections on device removal

## Performance

Once running, you should see:
- **500MB/s+ throughput** via USB 3.0/3.1
- **800MB/s+ throughput** via 10GbE
- **<2ms latency** for local connections

Check performance:
```bash
# Monitor network activity
iftop -i eth0

# Check memory allocation
free -h
cat /proc/meminfo
```

## Examples

### Scenario 1: Laptop with limited RAM
```
1. Install Remote RAM on your laptop (client)
2. Install on Raspberry Pi (server) with extra RAM
3. Connect via USB 3.0
4. Plug in Pi → Automatic connection
5. Your laptop now has extra usable RAM
6. Run heavy applications normally
7. Unplug Pi → Everything cleans up automatically
```

### Scenario 2: Server with multiple clients
```
1. Install on main server (client) - has 8GB local RAM
2. Install on 3 connected Jetson Nanos (servers) - 4GB each
3. Connect via Ethernet
4. Each Jetson auto-detected and auto-connected
5. Main server now sees 20GB total RAM available
6. Load balances automatically across all devices
```

## Questions?

Check:
- README.md - Full documentation
- PERFORMANCE.md - Performance tuning guide
- examples/ - Code examples
- GitHub Issues - Common problems
