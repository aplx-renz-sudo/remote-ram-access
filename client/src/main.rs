use std::io::{Read, Write};
use std::net::TcpStream;
use std::time::Duration;
use tracing::info;

struct RemoteRAMClient {
    stream: TcpStream,
    server_addr: String,
}

impl RemoteRAMClient {
    fn connect(server_addr: &str) -> Result<Self, Box<dyn std::error::Error>> {
        let stream = TcpStream::connect(server_addr)?;
        stream.set_read_timeout(Some(Duration::from_secs(10)))?;
        stream.set_write_timeout(Some(Duration::from_secs(10)))?;
        
        info!("Connected to RAM server at {}", server_addr);
        Ok(RemoteRAMClient {
            stream,
            server_addr: server_addr.to_string(),
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
            info!("Allocated pool: {}", pool_id);
            Ok(pool_id)
        } else {
            Err(response.to_string().into())
        }
    }

    fn write_data(&mut self, pool_id: &str, offset: usize, data: &[u8]) -> Result<(), Box<dyn std::error::Error>> {
        let data_str = String::from_utf8_lossy(data);
        let command = format!("WRITE {} {} {}\n", pool_id, offset, data_str);
        self.stream.write_all(command.as_bytes())?;

        let mut buffer = [0u8; 256];
        let n = self.stream.read(&mut buffer)?;
        let response = String::from_utf8_lossy(&buffer[..n]);

        if response.starts_with("OK") {
            info!("Wrote {} bytes to pool {} at offset {}", data.len(), pool_id, offset);
            Ok(())
        } else {
            Err(response.to_string().into())
        }
    }

    fn read_data(&mut self, pool_id: &str, offset: usize, size: usize) -> Result<Vec<u8>, Box<dyn std::error::Error>> {
        let command = format!("READ {} {} {}\n", pool_id, offset, size);
        self.stream.write_all(command.as_bytes())?;

        let mut buffer = vec![0u8; size + 1024];
        let n = self.stream.read(&mut buffer)?;
        let response = String::from_utf8_lossy(&buffer[..n]);

        if response.starts_with("OK") {
            let data = response.trim().strip_prefix("OK ").unwrap_or("").as_bytes().to_vec();
            info!("Read {} bytes from pool {} at offset {}", size, pool_id, offset);
            Ok(data)
        } else {
            Err(response.to_string().into())
        }
    }

    fn list_pools(&mut self) -> Result<Vec<String>, Box<dyn std::error::Error>> {
        self.stream.write_all(b"LIST\n")?;

        let mut buffer = [0u8; 4096];
        let n = self.stream.read(&mut buffer)?;
        let response = String::from_utf8_lossy(&buffer[..n]);

        if response.starts_with("OK") {
            let pools_str = response.trim().strip_prefix("OK ").unwrap_or("");
            let pools = pools_str
                .trim_matches(|c| c == '[' || c == ']')
                .split(", ")
                .map(|s| s.to_string())
                .collect();
            Ok(pools)
        } else {
            Err(response.to_string().into())
        }
    }

    fn get_pool_info(&mut self, pool_id: &str) -> Result<String, Box<dyn std::error::Error>> {
        let command = format!("INFO {}\n", pool_id);
        self.stream.write_all(command.as_bytes())?;

        let mut buffer = [0u8; 1024];
        let n = self.stream.read(&mut buffer)?;
        let response = String::from_utf8_lossy(&buffer[..n]);

        if response.starts_with("OK") {
            let info = response.trim().strip_prefix("OK ").unwrap_or("").to_string();
            Ok(info)
        } else {
            Err(response.to_string().into())
        }
    }

    fn delete_pool(&mut self, pool_id: &str) -> Result<(), Box<dyn std::error::Error>> {
        let command = format!("DELETE {}\n", pool_id);
        self.stream.write_all(command.as_bytes())?;

        let mut buffer = [0u8; 256];
        let n = self.stream.read(&mut buffer)?;
        let response = String::from_utf8_lossy(&buffer[..n]);

        if response.starts_with("OK") {
            info!("Deleted pool {}", pool_id);
            Ok(())
        } else {
            Err(response.to_string().into())
        }
    }

    fn ping(&mut self) -> Result<bool, Box<dyn std::error::Error>> {
        self.stream.write_all(b"PING\n")?;

        let mut buffer = [0u8; 256];
        let n = self.stream.read(&mut buffer)?;
        let response = String::from_utf8_lossy(&buffer[..n]);

        Ok(response.trim() == "PONG")
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

    let mut client = RemoteRAMClient::connect(server_addr)?;

    // Ping server
    if client.ping()? {
        println!("✓ Connected to remote RAM server");
    }

    // Example: Allocate a 256MB pool
    let pool_id = client.allocate_pool("data_processing", 256)?;
    println!("✓ Allocated pool: {}", pool_id);

    // Write data to remote memory
    let test_data = b"Hello from local device! This is data stored in remote RAM.";
    client.write_data(&pool_id, 0, test_data)?;
    println!("✓ Wrote test data to remote pool");

    // Read data back
    let read_data = client.read_data(&pool_id, 0, test_data.len())?;
    println!("✓ Read data from remote pool: {}", String::from_utf8_lossy(&read_data));

    // Get pool information
    if let Ok(info) = client.get_pool_info(&pool_id) {
        println!("✓ Pool info: {}", info);
    }

    // List all pools
    let pools = client.list_pools()?;
    println!("✓ Active pools: {:?}", pools);

    // Write larger data
    let large_data = vec![0xABu8; 10 * 1024 * 1024]; // 10MB
    client.write_data(&pool_id, 0, &large_data)?;
    println!("✓ Wrote 10MB of data to remote pool");

    // Cleanup
    client.delete_pool(&pool_id)?;
    println!("✓ Deleted pool");

    Ok(())
}
