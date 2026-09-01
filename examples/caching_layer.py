#!/usr/bin/env python3
"""
Example: Using remote device RAM as a distributed cache layer.
This demonstrates how to use connected device memory for caching frequently accessed data.
"""

import socket
import time
import json
from typing import Optional, Dict, Any

class RemoteRAMCache:
    def __init__(self, server_addr: str, port: int = 5555):
        self.server_addr = server_addr
        self.port = port
        self.socket = None
        self.pool_id = None
        self.connect()
    
    def connect(self):
        """Connect to remote RAM server"""
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.socket.connect((self.server_addr, self.port))
        print(f"✓ Connected to remote RAM server at {self.server_addr}:{self.port}")
    
    def send_command(self, command: str) -> str:
        """Send command to server and receive response"""
        self.socket.send(command.encode() + b'\n')
        response = self.socket.recv(8192).decode().strip()
        return response
    
    def allocate_cache(self, size_mb: int = 256) -> str:
        """Allocate a cache pool"""
        response = self.send_command(f"ALLOCATE cache_pool {size_mb}")
        if response.startswith("OK"):
            self.pool_id = response.split()[1]
            print(f"✓ Cache pool allocated: {self.pool_id} ({size_mb}MB)")
            return self.pool_id
        else:
            raise Exception(f"Failed to allocate cache: {response}")
    
    def cache_data(self, key: str, value: Any, offset: int = 0) -> bool:
        """Cache data in remote RAM"""
        if not self.pool_id:
            raise Exception("Cache pool not allocated")
        
        data = json.dumps({"key": key, "value": value, "timestamp": time.time()})
        response = self.send_command(f"WRITE {self.pool_id} {offset} {data}")
        
        if response.startswith("OK"):
            print(f"✓ Cached '{key}' at offset {offset}")
            return True
        else:
            print(f"✗ Failed to cache: {response}")
            return False
    
    def retrieve_cached(self, offset: int, size: int = 1024) -> Optional[Dict]:
        """Retrieve cached data from remote RAM"""
        if not self.pool_id:
            raise Exception("Cache pool not allocated")
        
        response = self.send_command(f"READ {self.pool_id} {offset} {size}")
        
        if response.startswith("OK"):
            data_str = response[3:]  # Remove "OK "
            try:
                return json.loads(data_str)
            except:
                return {"raw_data": data_str}
        else:
            return None
    
    def get_cache_stats(self) -> str:
        """Get cache statistics"""
        if not self.pool_id:
            return "No cache pool allocated"
        
        response = self.send_command(f"INFO {self.pool_id}")
        return response.replace("OK ", "")
    
    def cleanup(self):
        """Clean up cache pool"""
        if self.pool_id:
            response = self.send_command(f"DELETE {self.pool_id}")
            if response.startswith("OK"):
                print(f"✓ Cache pool deleted")
                self.pool_id = None
        self.socket.close()


def main():
    print("=== Remote RAM Caching Layer Example ===")
    print()
    
    # Initialize cache
    cache = RemoteRAMCache("127.0.0.1", 5555)
    cache.allocate_cache(256)
    
    print("\n1. Caching sample data...")
    # Cache some example data
    user_data = {
        "id": 12345,
        "name": "Alice Johnson",
        "email": "alice@example.com",
        "preferences": {"theme": "dark", "language": "en"}
    }
    cache.cache_data("user:12345", user_data, 0)
    
    sensor_data = [
        {"sensor_id": "temp_01", "value": 22.5, "unit": "C"},
        {"sensor_id": "humidity_01", "value": 45.3, "unit": "%"},
        {"sensor_id": "pressure_01", "value": 1013.25, "unit": "hPa"}
    ]
    cache.cache_data("sensors:building_a", sensor_data, 512)
    
    print("\n2. Retrieving cached data...")
    retrieved = cache.retrieve_cached(0, 512)
    print(f"   Retrieved: {retrieved}")
    
    print("\n3. Cache statistics:")
    stats = cache.get_cache_stats()
    print(f"   {stats}")
    
    print("\n4. Simulating cache hits and misses...")
    start = time.time()
    for i in range(10):
        # Simulate accessing cached data
        _ = cache.retrieve_cached(0, 256)
    elapsed = time.time() - start
    print(f"   ✓ 10 cache hits in {elapsed*1000:.2f}ms ({elapsed*100:.2f}ms per hit)")
    
    print("\n5. Cleanup...")
    cache.cleanup()
    
    print("\n=== Example Complete ===")


if __name__ == "__main__":
    main()
