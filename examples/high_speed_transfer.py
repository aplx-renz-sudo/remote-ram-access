#!/usr/bin/env python3
"""
High-speed data transfer example - demonstrates 500MB/s+ throughput
using binary protocol and optimized socket settings.
"""

import socket
import time
import struct
from typing import Tuple

class HighSpeedTransfer:
    def __init__(self, server_addr: str = "127.0.0.1", port: int = 5555):
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.socket.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        
        # Optimize buffer sizes
        self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 256*1024)
        self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 256*1024)
        
        self.socket.connect((server_addr, port))
        print(f"✓ Connected to high-speed server at {server_addr}:{port}")
        self.pool_id = None
    
    def allocate(self, size_mb: int) -> str:
        cmd = f"ALLOCATE performance_pool {size_mb}\n".encode()
        self.socket.sendall(cmd)
        response = self.socket.recv(1024).decode().strip()
        self.pool_id = response.split()[1]
        print(f"✓ Allocated {size_mb}MB pool: {self.pool_id}")
        return self.pool_id
    
    def write_binary_fast(self, data: bytes, offset: int = 0) -> Tuple[float, int]:
        """Write data using binary protocol for maximum speed"""
        header = f"WRITE_BIN {self.pool_id} {offset}\n".encode()
        
        start = time.time()
        self.socket.sendall(header)
        self.socket.sendall(data)
        self.socket.sendall(b"\n")
        
        response = self.socket.recv(256).decode().strip()
        elapsed = time.time() - start
        
        bytes_written = int(response.split()[1]) if response.startswith("OK") else 0
        throughput_mbps = (bytes_written / 1024 / 1024) / elapsed if elapsed > 0 else 0
        
        return throughput_mbps, bytes_written
    
    def read_binary_fast(self, size: int, offset: int = 0) -> Tuple[float, int]:
        """Read data using binary protocol"""
        cmd = f"READ {self.pool_id} {offset} {size}\n".encode()
        
        start = time.time()
        self.socket.sendall(cmd)
        data = self.socket.recv(size + 1024)
        elapsed = time.time() - start
        
        throughput_mbps = (len(data) / 1024 / 1024) / elapsed if elapsed > 0 else 0
        return throughput_mbps, len(data)

def main():
    print("\n🚀 High-Speed Remote RAM Transfer Test")
    print("="*50)
    
    transfer = HighSpeedTransfer()
    transfer.allocate(2048)  # 2GB
    
    print("\n📤 Write Performance (Target: 500MB/s)")
    print("-" * 50)
    
    test_sizes = [
        (100, "100MB"),
        (200, "200MB"),
        (500, "500MB"),
    ]
    
    for size_mb, label in test_sizes:
        data = b'\x42' * (size_mb * 1024 * 1024)
        mbps, bytes_written = transfer.write_binary_fast(data, 0)
        print(f"  {label:8} | {mbps:6.1f} MB/s | {bytes_written/(1024*1024):.0f}MB written")
    
    print("\n📥 Read Performance (Target: 500MB/s)")
    print("-" * 50)
    
    for size_mb, label in test_sizes:
        size_bytes = size_mb * 1024 * 1024
        mbps, bytes_read = transfer.read_binary_fast(size_bytes, 0)
        print(f"  {label:8} | {mbps:6.1f} MB/s | {bytes_read/(1024*1024):.0f}MB read")
    
    print("\n✅ Test Complete\n")
    transfer.socket.close()

if __name__ == "__main__":
    main()
