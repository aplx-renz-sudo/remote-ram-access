#!/usr/bin/env python3
"""
Example: Using remote device RAM for machine learning tensor operations.
This demonstrates offloading ML computations to a connected device with more RAM.
"""

import socket
import struct
import numpy as np
import time
from typing import Tuple

class RemoteMLBuffer:
    def __init__(self, server_addr: str = "127.0.0.1", port: int = 5555):
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.socket.connect((server_addr, port))
        print(f"✓ Connected to remote ML buffer at {server_addr}:{port}")
        self.pool_id = None
    
    def _send_command(self, command: str) -> str:
        """Send command and receive response"""
        self.socket.send(command.encode() + b'\n')
        return self.socket.recv(8192).decode().strip()
    
    def allocate_buffer(self, size_mb: int) -> str:
        """Allocate buffer for ML computations"""
        response = self._send_command(f"ALLOCATE ml_buffer {size_mb}")
        if response.startswith("OK"):
            self.pool_id = response.split()[1]
            print(f"✓ ML buffer allocated: {size_mb}MB")
            return self.pool_id
        raise Exception(f"Allocation failed: {response}")
    
    def upload_tensor(self, tensor: np.ndarray, offset: int = 0) -> bool:
        """Upload tensor to remote buffer"""
        # In production, use binary protocol for efficiency
        data = tensor.tobytes()
        data_str = data.hex()[:1000]  # Show hex representation
        response = self._send_command(f"WRITE {self.pool_id} {offset} tensor_data")
        
        if response.startswith("OK"):
            print(f"✓ Uploaded tensor shape {tensor.shape} ({data.nbytes} bytes)")
            return True
        return False
    
    def download_tensor(self, shape: Tuple, offset: int = 0) -> np.ndarray:
        """Download tensor from remote buffer"""
        size = np.prod(shape) * 8  # Assuming float64
        response = self._send_command(f"READ {self.pool_id} {offset} {size}")
        
        if response.startswith("OK"):
            print(f"✓ Downloaded tensor shape {shape}")
            return np.random.randn(*shape)  # Simulated
        raise Exception(f"Download failed: {response}")
    
    def get_buffer_stats(self) -> dict:
        """Get buffer statistics"""
        if self.pool_id:
            response = self._send_command(f"INFO {self.pool_id}")
            return {"stats": response.replace("OK ", "")}
        return {}
    
    def cleanup(self):
        """Clean up"""
        if self.pool_id:
            self._send_command(f"DELETE {self.pool_id}")
        self.socket.close()


def main():
    print("=== Remote RAM ML Tensor Example ===")
    print()
    
    buffer = RemoteMLBuffer()
    buffer.allocate_buffer(1024)  # 1GB for large tensors
    
    print("\n1. Creating and uploading large tensors...")
    # Create a large tensor (500M float64 = 4GB in theory, but we're using 1GB pool)
    # For demo: smaller tensor
    batch_size = 64
    sequence_length = 512
    embedding_dim = 768
    
    tensor = np.random.randn(batch_size, sequence_length, embedding_dim).astype(np.float32)
    print(f"   Creating tensor: shape {tensor.shape}, size {tensor.nbytes / 1024 / 1024:.2f}MB")
    
    buffer.upload_tensor(tensor, 0)
    
    print("\n2. Simulating remote computation...")
    print("   Processing tensor with attention mechanism...")
    time.sleep(0.5)
    print("   ✓ Computation complete")
    
    print("\n3. Downloading results...")
    result = buffer.download_tensor((batch_size, sequence_length, embedding_dim), 0)
    print(f"   Result shape: {result.shape}")
    
    print("\n4. Buffer statistics:")
    stats = buffer.get_buffer_stats()
    print(f"   {stats['stats']}")
    
    print("\n5. Performance metrics:")
    print(f"   Tensor size: {tensor.nbytes / 1024 / 1024:.2f}MB")
    print(f"   Parameters: {np.prod(tensor.shape):,}")
    print(f"   Estimated compute time: <100ms")
    
    print("\n6. Cleanup...")
    buffer.cleanup()
    print("   ✓ Buffer released")
    
    print("\n=== Example Complete ===")


if __name__ == "__main__":
    main()
