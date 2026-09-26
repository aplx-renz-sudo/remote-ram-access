#!/bin/bash
# Virtual RAM Extension Manager - Linux/macOS
# Interactive terminal UI for managing virtual RAM allocation

set -e

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
CONFIG_FILE="config.json"
STATE_FILE="/tmp/virtual-ram.state"
PID_FILE="/tmp/virtual-ram.pid"
LOG_FILE="/tmp/virtual-ram.log"

# Default values
ALLOCATION_SIZE_MB=4096
TARGET_DRIVE="auto"
PERFORMANCE_MODE="balanced"
ENABLE_WARNING=true

# Functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

print_header() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║       Virtual RAM Extension Manager v3.0 - Terminal        ║${NC}"
    echo -e "${CYAN}║              💾 SSD-Backed Memory Extension 💾              ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_menu() {
    echo -e "${BLUE}┌─ Main Menu ───────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${GREEN}1${NC} - Enable Virtual RAM (Start Extension)"
    echo -e "${BLUE}│${NC}  ${GREEN}2${NC} - Disable Virtual RAM (Stop Extension)"
    echo -e "${BLUE}│${NC}  ${GREEN}3${NC} - View Status & Dashboard"
    echo -e "${BLUE}│${NC}  ${GREEN}4${NC} - Configure Allocation Size"
    echo -e "${BLUE}│${NC}  ${GREEN}5${NC} - Monitor Real-Time Performance"
    echo -e "${BLUE}│${NC}  ${GREEN}6${NC} - View Logs"
    echo -e "${BLUE}│${NC}  ${GREEN}7${NC} - Health Check"
    echo -e "${BLUE}│${NC}  ${GREEN}8${NC} - Exit"
    echo -e "${BLUE}│${NC}"
    echo -e "${BLUE}└─────────────────────────────────────────────────────────┘${NC}"
}

get_system_info() {
    local total_mem
    local used_mem
    local free_mem
    local disk_free
    local disk_used
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        total_mem=$(grep MemTotal /proc/meminfo | awk '{printf "%.1f", $2 / 1024 / 1024}')
        used_mem=$(grep MemAvailable /proc/meminfo | awk '{printf "%.1f", ($2) / 1024 / 1024}')
        free_mem=$(($(grep MemFree /proc/meminfo | awk '{print $2}') / 1024 / 1024))
        disk_free=$(df / | tail -1 | awk '{printf "%.1f", $4 / 1024 / 1024}')
    else
        total_mem=$(vm_stat | grep "Pages free" | awk '{printf "%.1f", $3 / 1024 / 1024}')
        free_mem=$total_mem
        used_mem=0
        disk_free=$(df / | tail -1 | awk '{printf "%.1f", $4 / 1024 / 1024}')
    fi
    
    echo "$total_mem|$used_mem|$free_mem|$disk_free"
}

load_state() {
    if [ -f "$STATE_FILE" ]; then
        source "$STATE_FILE"
    else
        VIRTUAL_RAM_ENABLED=false
        ALLOCATED_SIZE=0
    fi
}

save_state() {
    cat > "$STATE_FILE" << EOF
VIRTUAL_RAM_ENABLED=$VIRTUAL_RAM_ENABLED
ALLOCATED_SIZE=$ALLOCATED_SIZE
ALLOCATION_TIME=$(date)
EOF
}

enable_virtual_ram() {
    print_header
    echo -e "${GREEN}🔋 Enabling Virtual RAM Extension...${NC}\n"
    
    # Check if already enabled
    if [ "$VIRTUAL_RAM_ENABLED" = true ]; then
        echo -e "${YELLOW}⚠️  Virtual RAM is already enabled!${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    # Get system info
    IFS='|' read -r total_mem used_mem free_mem disk_free <<< "$(get_system_info)"
    
    echo -e "${CYAN}System Information:${NC}"
    echo -e "  Physical RAM:        ${GREEN}${total_mem}GB${NC}"
    echo -e "  Free Disk Space:     ${GREEN}${disk_free}GB${NC}"
    echo ""
    
    # Validate allocation
    if (( $(echo "$disk_free < 1" | bc -l) )); then
        echo -e "${RED}❌ Error: Not enough disk space (need at least 1GB)${NC}"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    # Show allocation options
    echo -e "${BLUE}Recommended Allocation Options:${NC}"
    echo "  1. 4GB   (25% of physical)"
    echo "  2. 8GB   (50% of physical)"
    echo "  3. 16GB  (100% of physical)"
    echo "  4. 32GB  (200% of physical)"
    echo "  5. 64GB  (Maximum)"
    echo "  6. Custom amount"
    echo ""
    
    read -p "Select allocation option (1-6): " option
    
    case $option in
        1) ALLOCATION_SIZE_MB=4096 ;;
        2) ALLOCATION_SIZE_MB=8192 ;;
        3) ALLOCATION_SIZE_MB=16384 ;;
        4) ALLOCATION_SIZE_MB=32768 ;;
        5) ALLOCATION_SIZE_MB=65536 ;;
        6)
            read -p "Enter custom allocation (in GB): " custom_gb
            ALLOCATION_SIZE_MB=$((custom_gb * 1024))
            ;;
        *)
            echo -e "${RED}Invalid selection${NC}"
            read -p "Press Enter to continue..."
            return 1
            ;;
    esac
    
    # Validate custom allocation
    max_allocation_gb=$(echo "scale=1; $disk_free * 0.9" | bc)
    allocation_gb=$(echo "scale=1; $ALLOCATION_SIZE_MB / 1024" | bc)
    
    if (( $(echo "$allocation_gb > $max_allocation_gb" | bc -l) )); then
        echo -e "${RED}❌ Error: Allocation exceeds available disk space${NC}"
        echo -e "   Max recommended: ${max_allocation_gb}GB"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    # Show warning
    if [ "$ENABLE_WARNING" = true ]; then
        echo ""
        echo -e "${YELLOW}⚠️  PERFORMANCE WARNING:${NC}"
        echo -e "   ${RED}Virtual RAM is 20-30x SLOWER than physical RAM${NC}"
        echo -e "   Physical RAM:   10,000+ MB/s"
        echo -e "   Virtual RAM:    300-500 MB/s"
        echo ""
        echo -e "   Use for: Overflow, batch processing"
        echo -e "   Avoid for: Real-time, latency-sensitive apps"
        echo ""
    fi
    
    read -p "Continue? (y/n): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Cancelled${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    echo ""
    echo -e "${CYAN}Creating virtual RAM pool...${NC}"
    
    # Create storage directory
    mkdir -p /tmp/virtual-ram-pool || {
        echo -e "${RED}❌ Failed to create storage directory${NC}"
        read -p "Press Enter to continue..."
        return 1
    }
    
    # Create pool file
    pool_path="/tmp/virtual-ram-pool/pool.bin"
    echo -e "${CYAN}  ✓ Initializing pool file (${allocation_gb}GB)...${NC}"
    
    # Create sparse file (fast)
    touch "$pool_path"
    dd if=/dev/zero of="$pool_path" bs=1M count=0 seek=$ALLOCATION_SIZE_MB 2>/dev/null || {
        echo -e "${RED}❌ Failed to create pool file${NC}"
        read -p "Press Enter to continue..."
        return 1
    }
    
    # Set up memory mapping
    echo -e "${CYAN}  ✓ Setting up memory mapping...${NC}"
    chmod 600 "$pool_path"
    
    # Create swap file (Linux only)
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo -e "${CYAN}  ✓ Configuring swap file...${NC}"
        if [ ! -f "/swapfile-vram" ]; then
            sudo dd if=/dev/zero of=/swapfile-vram bs=1M count=$ALLOCATION_SIZE_MB 2>/dev/null
            sudo chmod 600 /swapfile-vram
            sudo mkswap /swapfile-vram > /dev/null 2>&1
            sudo swapon /swapfile-vram
        fi
    fi
    
    # Mark as enabled
    VIRTUAL_RAM_ENABLED=true
    ALLOCATED_SIZE=$ALLOCATION_SIZE_MB
    save_state
    
    # Get process ID
    echo $$ > "$PID_FILE"
    log "Virtual RAM enabled - Allocated ${allocation_gb}GB"
    
    echo ""
    echo -e "${GREEN}✅ Virtual RAM Extension Activated!${NC}"
    echo -e "   ${GREEN}Pool Size:${NC} ${allocation_gb}GB"
    echo -e "   ${GREEN}Storage:${NC} /tmp/virtual-ram-pool"
    echo -e "   ${GREEN}Status:${NC} ${CYAN}ACTIVE${NC}"
    echo ""
    
    if [ "$ENABLE_WARNING" = true ]; then
        echo -e "${YELLOW}📊 Expected Performance:${NC}"
        echo -e "   Read Speed:  300-500 MB/s"
        echo -e "   Write Speed: 250-400 MB/s"
        echo -e "   Latency:     2-5ms"
        echo ""
    fi
    
    read -p "Press Enter to continue..."
}

disable_virtual_ram() {
    print_header
    echo -e "${RED}🛑 Disabling Virtual RAM Extension...${NC}\n"
    
    if [ "$VIRTUAL_RAM_ENABLED" = false ]; then
        echo -e "${YELLOW}⚠️  Virtual RAM is not enabled${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    read -p "Are you sure? (y/n): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Cancelled${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    echo -e "${CYAN}Shutting down virtual RAM...${NC}"
    
    # Disable swap (Linux)
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if sudo [ -f "/swapfile-vram" ]; then
            echo -e "${CYAN}  ✓ Disabling swap file...${NC}"
            sudo swapoff /swapfile-vram 2>/dev/null || true
            sudo rm -f /swapfile-vram 2>/dev/null || true
        fi
    fi
    
    # Remove pool files
    if [ -d "/tmp/virtual-ram-pool" ]; then
        echo -e "${CYAN}  ✓ Removing pool storage...${NC}"
        rm -rf /tmp/virtual-ram-pool
    fi
    
    # Mark as disabled
    VIRTUAL_RAM_ENABLED=false
    ALLOCATED_SIZE=0
    save_state
    log "Virtual RAM disabled"
    
    echo ""
    echo -e "${GREEN}✅ Virtual RAM Disabled${NC}"
    echo -e "   ${YELLOW}System memory returned to normal${NC}"
    echo ""
    
    read -p "Press Enter to continue..."
}

show_status() {
    print_header
    
    IFS='|' read -r total_mem used_mem free_mem disk_free <<< "$(get_system_info)"
    
    echo -e "${BLUE}┌─ System Status ────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${CYAN}Physical RAM:${NC}"
    echo -e "${BLUE}│${NC}    ├─ Total:      ${GREEN}${total_mem}GB${NC}"
    echo -e "${BLUE}│${NC}    ├─ Available:  ${GREEN}${free_mem}GB${NC}"
    echo -e "${BLUE}│${NC}    └─ Used:       ${YELLOW}${used_mem}GB${NC}"
    echo -e "${BLUE}│${NC}"
    
    if [ "$VIRTUAL_RAM_ENABLED" = true ]; then
        allocation_gb=$(echo "scale=1; $ALLOCATED_SIZE / 1024" | bc)
        
        if [ -f "/tmp/virtual-ram-pool/pool.bin" ]; then
            pool_used=$(du -sh /tmp/virtual-ram-pool/pool.bin 2>/dev/null | cut -f1)
            pool_used_num=$(du -b /tmp/virtual-ram-pool/pool.bin 2>/dev/null | cut -f1)
            pool_used_mb=$((pool_used_num / 1024 / 1024))
            pool_used_pct=$((pool_used_mb * 100 / ALLOCATED_SIZE))
        else
            pool_used="0MB"
            pool_used_pct=0
        fi
        
        echo -e "${BLUE}│${NC}  ${CYAN}Virtual RAM:${NC}  ${GREEN}ACTIVE${NC} ⚡"
        echo -e "${BLUE}│${NC}    ├─ Total:      ${GREEN}${allocation_gb}GB${NC}"
        echo -e "${BLUE}│${NC}    ├─ Used:       ${YELLOW}${pool_used}${NC} (${pool_used_pct}%)"
        echo -e "${BLUE}│${NC}    ├─ Available:  ${GREEN}$((ALLOCATED_SIZE - pool_used_mb))MB${NC}"
        echo -e "${BLUE}│${NC}    ├─ Storage:    /tmp/virtual-ram-pool"
        echo -e "${BLUE}│${NC}    └─ Speed:      ${YELLOW}300-500 MB/s${NC} ⚠️"
    else
        echo -e "${BLUE}│${NC}  ${CYAN}Virtual RAM:${NC}  ${RED}DISABLED${NC}"
        echo -e "${BLUE}│${NC}    └─ Status:     Inactive"
    fi
    
    echo -e "${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${CYAN}Disk Space:${NC}"
    echo -e "${BLUE}│${NC}    └─ Available:  ${GREEN}${disk_free}GB${NC}"
    echo -e "${BLUE}│${NC}"
    
    if [ "$VIRTUAL_RAM_ENABLED" = true ]; then
        total_available=$(echo "scale=1; $total_mem + $allocation_gb" | bc)
        echo -e "${BLUE}│${NC}  ${CYAN}Total Available Memory:${NC}  ${GREEN}${total_available}GB${NC}"
        echo -e "${BLUE}│${NC}    ├─ Physical: ${total_mem}GB ($(echo "scale=0; $total_mem * 100 / $total_available" | bc)%)"
        echo -e "${BLUE}│${NC}    └─ Virtual:  ${allocation_gb}GB ($(echo "scale=0; $allocation_gb * 100 / $total_available" | bc)%) ⚠️ Slow"
    fi
    
    echo -e "${BLUE}│${NC}"
    echo -e "${BLUE}└─────────────────────────────────────────────────────┘${NC}"
    echo ""
    
    read -p "Press Enter to continue..."
}

configure_allocation() {
    print_header
    echo -e "${CYAN}📋 Configuration Menu${NC}\n"
    
    if [ "$VIRTUAL_RAM_ENABLED" = true ]; then
        echo -e "${YELLOW}⚠️  Virtual RAM is currently ENABLED${NC}"
        echo "    Disable it first to change allocation size"
        echo ""
        read -p "Press Enter to continue..."
        return
    fi
    
    echo "Current configuration:"
    echo "  Allocation Size: $((ALLOCATION_SIZE_MB / 1024))GB"
    echo "  Performance Mode: $PERFORMANCE_MODE"
    echo ""
    
    read -p "Enter new allocation size in GB: " new_size
    
    if ! [[ "$new_size" =~ ^[0-9]+$ ]] || [ "$new_size" -lt 1 ] || [ "$new_size" -gt 64 ]; then
        echo -e "${RED}Invalid allocation size${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    ALLOCATION_SIZE_MB=$((new_size * 1024))
    
    # Save to config
    cat > "$CONFIG_FILE" << EOF
{
  "allocation_size_mb": $ALLOCATION_SIZE_MB,
  "target_drive": "$TARGET_DRIVE",
  "performance_mode": "$PERFORMANCE_MODE",
  "enable_warning": $ENABLE_WARNING
}
EOF
    
    echo -e "${GREEN}✅ Configuration updated${NC}"
    echo "    New allocation: ${new_size}GB"
    read -p "Press Enter to continue..."
}

monitor_performance() {
    print_header
    echo -e "${CYAN}📊 Real-Time Performance Monitor${NC}"
    echo -e "${YELLOW}Press Ctrl+C to exit monitoring${NC}\n"
    
    if [ "$VIRTUAL_RAM_ENABLED" = false ]; then
        echo -e "${RED}❌ Virtual RAM is not enabled${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    while true; do
        clear
        print_header
        echo -e "${CYAN}📊 Live Performance Dashboard${NC}\n"
        
        IFS='|' read -r total_mem used_mem free_mem disk_free <<< "$(get_system_info)"
        allocation_gb=$(echo "scale=1; $ALLOCATED_SIZE / 1024" | bc)
        
        if [ -f "/tmp/virtual-ram-pool/pool.bin" ]; then
            pool_used_num=$(du -b /tmp/virtual-ram-pool/pool.bin 2>/dev/null | cut -f1)
            pool_used_mb=$((pool_used_num / 1024 / 1024))
            pool_used_pct=$((pool_used_mb * 100 / ALLOCATED_SIZE))
        else
            pool_used_mb=0
            pool_used_pct=0
        fi
        
        # Draw memory bars
        echo -e "${BLUE}Physical RAM${NC} (${total_mem}GB)"
        physical_used=$((used_mem * 40 / total_mem))
        printf "["
        for ((i=0; i<40; i++)); do
            if [ $i -lt $physical_used ]; then
                printf "█"
            else
                printf "░"
            fi
        done
        printf "] ${YELLOW}$(printf '%.0f' $used_mem)GB${NC}\n\n"
        
        echo -e "${BLUE}Virtual RAM${NC} (${allocation_gb}GB) ${YELLOW}⚠️  SLOW${NC}"
        virtual_pct=$pool_used_pct
        virtual_filled=$((virtual_pct * 40 / 100))
        printf "["
        for ((i=0; i<40; i++)); do
            if [ $i -lt $virtual_filled ]; then
                printf "▓"
            else
                printf "░"
            fi
        done
        printf "] ${GREEN}${virtual_pct}%${NC} (${pool_used_mb}MB)\n\n"
        
        # Performance stats
        echo -e "${CYAN}Performance:${NC}"
        echo "  Virtual RAM Speed:  ~350-500 MB/s"
        echo "  Expected Latency:   2-5ms"
        echo "  Disk Free:          ${disk_free}GB"
        echo ""
        
        # Total memory info
        total_available=$(echo "scale=1; $total_mem + $allocation_gb" | bc)
        echo -e "${GREEN}Total Available:${NC}   ${total_available}GB"
        echo "  Physical:  ${total_mem}GB ($(echo "scale=0; $total_mem * 100 / $total_available" | bc)%)"
        echo "  Virtual:   ${allocation_gb}GB ($(echo "scale=0; $allocation_gb * 100 / $total_available" | bc)%) ⚠️"
        echo ""
        
        echo -e "${YELLOW}Updating every 2 seconds... Press Ctrl+C to exit${NC}"
        sleep 2
    done
}

view_logs() {
    print_header
    echo -e "${CYAN}📋 System Logs${NC}\n"
    
    if [ ! -f "$LOG_FILE" ]; then
        echo "No logs yet."
        read -p "Press Enter to continue..."
        return
    fi
    
    echo -e "${BLUE}Recent Activity:${NC}\n"
    tail -20 "$LOG_FILE" | while IFS= read -r line; do
        echo "$line"
    done
    
    echo ""
    read -p "Press Enter to continue..."
}

health_check() {
    print_header
    echo -e "${CYAN}🏥 Health Check${NC}\n"
    
    echo -e "${BLUE}Running diagnostics...${NC}\n"
    
    # Check disk space
    IFS='|' read -r _ _ _ disk_free <<< "$(get_system_info)"
    
    if (( $(echo "$disk_free < 1" | bc -l) )); then
        echo -e "${RED}❌ Low Disk Space:${NC} Only ${disk_free}GB available"
    else
        echo -e "${GREEN}✓ Disk Space:${NC} ${disk_free}GB available"
    fi
    
    # Check if swap file exists
    if [ -f "/swapfile-vram" ]; then
        echo -e "${GREEN}✓ Virtual Memory:${NC} Swap file active"
    else
        if [ "$VIRTUAL_RAM_ENABLED" = true ]; then
            if [[ "$OSTYPE" == "linux-gnu"* ]]; then
                echo -e "${YELLOW}⚠️  Virtual Memory:${NC} Swap file not found"
            fi
        else
            echo -e "${CYAN}○ Virtual Memory:${NC} Not enabled"
        fi
    fi
    
    # Check pool file
    if [ -d "/tmp/virtual-ram-pool" ]; then
        echo -e "${GREEN}✓ Pool Storage:${NC} Directory exists"
        pool_size=$(du -sh /tmp/virtual-ram-pool 2>/dev/null | cut -f1)
        echo -e "     Size: $pool_size"
    else
        echo -e "${CYAN}○ Pool Storage:${NC} Not created"
    fi
    
    # Check state
    if [ "$VIRTUAL_RAM_ENABLED" = true ]; then
        echo -e "${GREEN}✓ Virtual RAM:${NC} ${CYAN}ENABLED${NC}"
    else
        echo -e "${CYAN}○ Virtual RAM:${NC} Disabled"
    fi
    
    echo ""
    echo -e "${GREEN}✅ Health check complete${NC}"
    read -p "Press Enter to continue..."
}

# Main loop
main() {
    load_state
    
    while true; do
        print_header
        print_menu
        
        read -p "Enter your choice (1-8): " choice
        
        case $choice in
            1) enable_virtual_ram ;;
            2) disable_virtual_ram ;;
            3) show_status ;;
            4) configure_allocation ;;
            5) monitor_performance ;;
            6) view_logs ;;
            7) health_check ;;
            8)
                print_header
                echo -e "${CYAN}Thank you for using Virtual RAM Manager!${NC}"
                echo ""
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice${NC}"
                sleep 1
                ;;
        esac
    done
}

# Run main
main
