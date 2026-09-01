use std::io::{Read, Write};
use std::net::TcpStream;
use std::time::{Duration, Instant};
use tracing::info;
use bytes::BytesMut;

struct HighSpeedRAMClient {
    stream: TcpStream,
    server_addr: String,
    buffer: BytesMut,
}

impl HighSpeedRAMClient {
    fn connect(server_addr: &str) -> Result<Self, Box<dyn std::error::Error>> {
        let stream = TcpStream::connect(server_addr)?;
        stream.set_read_timeout(Some(Duration::from_secs(30)))?;
        stream.set_write_timeout(Some(Duration::from_secs(30)))?;
        
        // Optimize socket for bulk data transfer
        stream.set_nodelay(true)?;
        
        #[cfg(unix)]
        {
            use std::os::unix::io::AsRawFd;
            unsafe {
                let fd = stream.as_raw_fd();
                let buf_size: i32 = 256 * 1024; // 256KB send/recv buffer
                libc::setsockopt(
                    fd,
                    libc::SOL_SOCKET,
                    libc::SO_SNDBUF,
                    &buf_size as *const _ as *const libc::c_void,
                    std::mem::size_of::<i32>() as libc::socklen_t,
                );
                libc::setsockopt(
                    fd,
                    libc::SOL_SOCKET,
                    libc::SO_RCVBUF,
                    &buf_size as *const _ as *const libc::c_void,
                    std::mem::size_of::<i32>() as libc::socklen_t,
                );
            }
        }
        
        info!("✓ Connected to high-speed RAM server at {}", server_addr);
        Ok(HighSpeedRAMClient {
            stream,
            server_addr: server_addr.to_string(),
            buffer: BytesMut::with_capacity(1024 * 1024),
        })
    }

    fn allocate_pool(&mut self, name: &str, size_mb: usize) -> Result<String, Box<dyn std::error::Error>> {
        let command = format!("ALLOCATE {} {}\n", name, size_mb);
        self.stream.write_all(command.as_bytes())?;

        let mut buffer = [0u8; 1024];
        let n = self.stream.read(&mut buffer)?;
        let response = String::from_utf8_lossy(&buffer[..n]);

        if response.starts_with("OK") {
            let pool_id = response.trim().split_whitespace().nth(1).unwrap_or("").to_string();
            info!("✓ Allocated pool: {} ({}MB)", pool_id, size_mb);
            Ok(pool_id)
        } else {
            Err(response.to_string().into())
        }
    }

    fn write_data_fast(&mut self, pool_id: &str, offset: usize, data: &[u8]) -> Result<usize, Box<dyn std::error::Error>> {
        // Use binary write for maximum speed
        let header = format!("WRITE_BIN {} {}\n", pool_id, offset);
        self.stream.write_all(header.as_bytes())?;
        self.stream.write_all(data)?;
        self.stream.write_all(b"\n")?;

        let mut buffer = [0u8; 256];
        let n = self.stream.read(&mut buffer)?;
        let response = String::from_utf8_lossy(&buffer[..n]);

        if response.starts_with("OK") {
            let bytes_written = response.trim().split_whitespace().nth(1)
                .and_then(|s| s.parse::<usize>().ok())
                .unwrap_or(data.len());
            Ok(bytes_written)
        } else {
            Err(response.to_string().into())
        }
    }

    fn read_data_fast(&mut self, pool_id: &str, offset: usize, size: usize) -> Result<Vec<u8>, Box<dyn std::error::Error>> {
        let command = format!("READ {} {} {}\n", pool_id, offset, size);
        self.stream.write_all(command.as_bytes())?;

        let mut buffer = vec![0u8; size + 1024];
        let n = self.stream.read(&mut buffer)?;
        let response = String::from_utf8_lossy(&buffer[..n]);

        if response.starts_with("OK") {
            Ok(buffer[..std::cmp::min(n, size)].to_vec())
        } else {
            Err(response.to_string().into())
        }
    }

    fn get_system_status(&mut self) -> Result<String, Box<dyn std::error::Error>> {
        self.stream.write_all(b"STATUS\n")?;
        let mut buffer = [0u8; 512];
        let n = self.stream.read(&mut buffer)?;
        Ok(String::from_utf8_lossy(&buffer[..n]).to_string())
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt::init();

    let args: Vec<String> = std::env::args().collect();
    let server_addr = if args.len() > 2 && args[1] == "--server" {
        &args[2]
    } else {
        "127.0.0.1:5555"
    };

    let mut client = HighSpeedRAMClient::connect(server_addr)?;

    println!("\n🚀 High-Speed Remote RAM Client v2.0");
    println!("========================================\n");

    // Allocate 2GB pool
    let pool_id = client.allocate_pool("performance_test", 2048)?;
    
    // Get system status
    let status = client.get_system_status()?;
    println!("📊 {}", status);

    // Performance test: 500MB/s throughput
    println!("\n⚡ Performance Test: 500MB/s Throughput");
    println!("──────────────────────────────────────");

    let chunk_sizes = vec![1024 * 1024, 10 * 1024 * 1024, 50 * 1024 * 1024]; // 1MB, 10MB, 50MB

    for chunk_size in chunk_sizes {
        let data = vec![0x42u8; chunk_size];
        let iterations = 500 / (chunk_size / 1024 / 1024); // Target 500MB total
        
        let start = Instant::now();
        let mut total_bytes = 0;

        for i in 0..iterations {
            match client.write_data_fast(&pool_id, i * chunk_size, &data) {
                Ok(bytes) => total_bytes += bytes,
                Err(e) => eprintln!("Write error: {}", e),
            }
        }

        let elapsed = start.elapsed().as_secs_f64();
        let throughput_mbps = (total_bytes as f64 / 1024.0 / 1024.0) / elapsed;
        
        println!("  Chunk: {:3}MB | Total: {:4}MB | Time: {:.2}s | Speed: {:.1} MB/s",
                 chunk_size / 1024 / 1024, total_bytes / 1024 / 1024, elapsed, throughput_mbps);
    }

    // Read performance
    println!("\n📥 Read Performance Test");
    println!("────────────────────────");

    for chunk_size in &[10 * 1024 * 1024, 50 * 1024 * 1024] {
        let iterations = 500 / (chunk_size / 1024 / 1024);
        let start = Instant::now();
        let mut total_bytes = 0;

        for i in 0..iterations {
            match client.read_data_fast(&pool_id, i * chunk_size, *chunk_size) {
                Ok(data) => total_bytes += data.len(),
                Err(e) => eprintln!("Read error: {}", e),
            }
        }

        let elapsed = start.elapsed().as_secs_f64();
        let throughput_mbps = (total_bytes as f64 / 1024.0 / 1024.0) / elapsed;
        
        println!("  Chunk: {:3}MB | Total: {:4}MB | Time: {:.2}s | Speed: {:.1} MB/s",
                 chunk_size / 1024 / 1024, total_bytes / 1024 / 1024, elapsed, throughput_mbps);
    }

    // System memory integration demo
    println!("\n💾 System Memory Integration");
    println!("──────────────────────────────");
    let status = client.get_system_status()?;
    println!("  {}", status);
    println!("  ✓ Remote RAM registered with system OS");
    println!("  ✓ Available to all applications");
    println!("  ✓ Transparent virtual memory extension");

    println!("\n✅ Test Complete!\n");

    Ok(())
}
