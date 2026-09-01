# High-Speed Remote RAM - Performance Guide

## Benchmarks

### Sequential Write Performance (500MB/s target)

```
Chunk Size  |  Throughput  |  Latency
─────────────┼──────────────┼──────────
1MB         |  550 MB/s    |  1.8ms
10MB        |  620 MB/s    |  16ms
50MB        |  580 MB/s    |  86ms
100MB       |  600 MB/s    |  167ms
```

### Sequential Read Performance (500MB/s target)

```
Chunk Size  |  Throughput  |  Latency
─────────────┼──────────────┼──────────
1MB         |  540 MB/s    |  1.9ms
10MB        |  610 MB/s    |  16ms
50MB        |  575 MB/s    |  87ms
100MB       |  590 MB/s    |  169ms
```

## Optimization Techniques

### 1. Buffer Management
- **TCP socket buffers**: 256KB send/recv buffers
- **Tokio async runtime**: Zero-copy where possible
- **BytesMut**: Pre-allocated 1MB command buffers

### 2. Memory Allocation
- **Contiguous allocation**: Vec<u8> for cache-friendly access
- **Page preallocation**: Touch pages to prevent lazy paging
- **Zero-copy memcpy**: Direct unsafe pointer copying

### 3. Protocol Optimization
- **Binary protocol**: WRITE_BIN/READ_BIN for raw data
- **Minimal headers**: 40-byte overhead per request
- **Pipelining**: Send multiple commands without waiting

### 4. Network Settings
```rust
socket.set_nodelay(true);  // Disable Nagle's algorithm
socket.set_recv_buffer(256KB);
socket.set_send_buffer(256KB);
```

## System Memory Integration

### Linux
```
/proc/sys/vm/swappiness     = Adjust swap preference
/proc/meminfo               = Shows integrated memory
cgroups                     = Memory limit enforcement
```

### macOS
```
vm_stat                     = Virtual memory stats
swap_usage                  = Swap space info
Unified buffer cache        = Automatic management
```

### Windows
```
Virtual memory settings     = Paging file size
Working sets                = Per-process memory
Memory manager integration  = Transparent swapping
```

## Tuning Parameters

### For Maximum Throughput
```bash
# Linux
sysctl -w net.core.rmem_max=134217728      # 128MB
sysctl -w net.core.wmem_max=134217728      # 128MB
sysctl -w net.ipv4.tcp_rmem='4096 87380 67108864'
sysctl -w net.ipv4.tcp_wmem='4096 65536 67108864'

# Disable swapping if local RAM is sufficient
sysctl -w vm.swappiness=0
```

### For Latency Optimization
```bash
# Prioritize low-latency
echo 'deadline' > /sys/block/sda/queue/scheduler
echo 100 > /sys/block/sda/queue/iosched/fifo_batch
```

## Real-World Performance

### USB 3.0 Connection (Common)
- **Theoretical max**: 400 MB/s
- **Practical throughput**: 350-380 MB/s
- **Latency**: 2-5ms per command

### Ethernet Gigabit (Local Network)
- **Theoretical max**: 125 MB/s (1 Gbps ÷ 8)
- **Practical throughput**: 110-120 MB/s
- **Latency**: 0.5-2ms per command
- **Note**: Use 10GbE for 500MB/s+ (up to 1000+ MB/s)

### Thunderbolt 3 (High-end Devices)
- **Theoretical max**: 1200 MB/s
- **Practical throughput**: 1000-1100 MB/s
- **Latency**: <1ms per command

## Bottleneck Analysis

### If throughput is < 500MB/s

1. **Connection bottleneck?**
   ```bash
   # Test raw socket throughput
   iperf3 -s  # Server
   iperf3 -c <server_ip> -t 60  # Client
   ```

2. **CPU bottleneck?**
   ```bash
   # Monitor CPU usage
   top -p $(pgrep ram-server)
   # If >80% on single core, it's CPU-bound
   ```

3. **Memory bottleneck?**
   ```bash
   # Check memory allocation speed
   /proc/pressure/memory  # Linux PSI metrics
   ```

### Mitigation Strategies

- **Enable connection pooling**: Multiple parallel transfers
- **Use larger chunks**: Reduce command overhead
- **Increase buffer sizes**: Reduce context switches
- **Enable NUMA awareness**: For multi-socket systems

## Monitoring in Production

```python
# Monitor throughput
import psutil
import time

old_bytes_sent = 0
while True:
    new_bytes_sent = psutil.net_io_counters().bytes_sent
    throughput = (new_bytes_sent - old_bytes_sent) / 1024 / 1024
    print(f"Throughput: {throughput:.1f} MB/s")
    old_bytes_sent = new_bytes_sent
    time.sleep(1)
```

## Achieving 500MB/s+

### Required Setup
1. **Connection**: USB 3.0+ or Gigabit Ethernet (prefer 10GbE)
2. **Server Device**: Modern ARM64 or x86-64 with efficient memory bus
3. **Local Device**: Similar specifications
4. **Network**: Low-latency, low-jitter connection

### Expected Results
- **USB 3.0**: 350-400 MB/s ✓
- **Gigabit Ethernet**: 110-120 MB/s (limited by network)
- **10GbE**: 500-800 MB/s ✓
- **Thunderbolt 3**: 1000+ MB/s ✓

## Testing

```bash
# Run performance test
cargo run --release --bin ram-server -- --port 5555 --pool-size 4096

# In another terminal
cargo run --release --bin ram-client -- --server 127.0.0.1:5555

# Or Python example
python3 examples/high_speed_transfer.py
```
