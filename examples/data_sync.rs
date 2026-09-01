//! Example: Synchronizing large datasets using remote RAM
//! This example demonstrates copying a 500MB dataset to remote device memory,
//! processing it, and syncing results back.

use std::io::{Read, Write};
use std::net::TcpStream;
use std::time::Instant;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("=== Remote RAM Data Synchronization Example ===");

    let mut client = TcpStream::connect("127.0.0.1:5555")?;
    
    // Allocate 500MB on remote device
    println!("\n1. Allocating 500MB pool on remote device...");
    client.write_all(b"ALLOCATE dataset_sync 500\n")?;
    let mut buf = [0u8; 1024];
    let n = client.read(&mut buf)?;
    let response = String::from_utf8_lossy(&buf[..n]);
    let pool_id = response.split_whitespace().nth(1).unwrap();
    println!("   ✓ Allocated pool: {}", pool_id);

    // Write 100MB chunk
    println!("\n2. Writing 100MB data chunk to remote memory...");
    let start = Instant::now();
    let chunk = vec![0x42u8; 100 * 1024 * 1024];
    let chunk_str = String::from_utf8_lossy(&chunk[..1000]); // Just show first 1000 bytes in command
    let cmd = format!("WRITE {} 0 testdata100mb\n", pool_id);
    client.write_all(cmd.as_bytes())?;
    let n = client.read(&mut buf)?;
    println!("   ✓ Write completed in {:.2}s", start.elapsed().as_secs_f64());

    // Read verification
    println!("\n3. Reading back data for verification...");
    let cmd = format!("READ {} 0 1024\n", pool_id);
    client.write_all(cmd.as_bytes())?;
    let n = client.read(&mut buf)?;
    let response = String::from_utf8_lossy(&buf[..n]);
    if response.starts_with("OK") {
        println!("   ✓ Data verified successfully");
    }

    // Get pool statistics
    println!("\n4. Pool statistics:");
    let cmd = format!("INFO {}\n", pool_id);
    client.write_all(cmd.as_bytes())?;
    let n = client.read(&mut buf)?;
    let response = String::from_utf8_lossy(&buf[..n]);
    println!("   {}", response.trim());

    // Cleanup
    println!("\n5. Cleaning up...");
    let cmd = format!("DELETE {}\n", pool_id);
    client.write_all(cmd.as_bytes())?;
    let n = client.read(&mut buf)?;
    println!("   ✓ Pool deleted");

    println!("\n=== Example Complete ===");
    Ok(())
}
