use dashmap::DashMap;
use std::sync::Arc;
use tokio::net::TcpListener;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tracing::{info, error, warn};
use sha2::{Sha256, Digest};
use std::collections::HashMap;

#[derive(Debug, Clone)]
struct MemoryPool {
    id: String,
    buffer: Arc<Vec<u8>>,
    max_size: usize,
    current_size: usize,
    created_at: i64,
    access_token: String,
}

struct RAMServer {
    pools: Arc<DashMap<String, MemoryPool>>,
    max_pool_size: usize,
    auth_tokens: Arc<DashMap<String, bool>>,
}

impl RAMServer {
    fn new(max_pool_size: usize) -> Self {
        RAMServer {
            pools: Arc::new(DashMap::new()),
            max_pool_size,
            auth_tokens: Arc::new(DashMap::new()),
        }
    }

    async fn allocate_pool(&self, name: &str, size: usize) -> Result<String, String> {
        if size > self.max_pool_size {
            return Err(format!("Pool size {} exceeds maximum {}", size, self.max_pool_size));
        }

        let pool_id = format!("pool_{}", uuid::Uuid::new_v4());
        let token = generate_token();
        
        let pool = MemoryPool {
            id: pool_id.clone(),
            buffer: Arc::new(vec![0u8; size]),
            max_size: size,
            current_size: 0,
            created_at: chrono::Local::now().timestamp(),
            access_token: token,
        };

        self.pools.insert(pool_id.clone(), pool);
        info!("Allocated pool {} with {} bytes", name, size);
        Ok(pool_id)
    }

    async fn write_to_pool(&self, pool_id: &str, offset: usize, data: &[u8]) -> Result<(), String> {
        if let Some(mut pool) = self.pools.get_mut(pool_id) {
            if offset + data.len() > pool.max_size {
                return Err("Write exceeds pool size".to_string());
            }
            
            unsafe {
                let ptr = pool.buffer.as_ptr() as *mut u8;
                std::ptr::copy_nonoverlapping(data.as_ptr(), ptr.add(offset), data.len());
            }
            
            pool.current_size = std::cmp::max(pool.current_size, offset + data.len());
            info!("Wrote {} bytes to pool {} at offset {}", data.len(), pool_id, offset);
            Ok(())
        } else {
            Err("Pool not found".to_string())
        }
    }

    async fn read_from_pool(&self, pool_id: &str, offset: usize, size: usize) -> Result<Vec<u8>, String> {
        if let Some(pool) = self.pools.get(pool_id) {
            if offset + size > pool.max_size {
                return Err("Read exceeds pool size".to_string());
            }
            
            let data = pool.buffer[offset..offset + size].to_vec();
            info!("Read {} bytes from pool {} at offset {}", size, pool_id, offset);
            Ok(data)
        } else {
            Err("Pool not found".to_string())
        }
    }

    async fn list_pools(&self) -> Vec<String> {
        self.pools.iter().map(|ref_multi| ref_multi.key().clone()).collect()
    }

    async fn get_pool_info(&self, pool_id: &str) -> Result<String, String> {
        if let Some(pool) = self.pools.get(pool_id) {
            let info = format!(
                "Pool: {}, Size: {}/{} bytes, Created: {}",
                pool.id, pool.current_size, pool.max_size, pool.created_at
            );
            Ok(info)
        } else {
            Err("Pool not found".to_string())
        }
    }

    async fn deallocate_pool(&self, pool_id: &str) -> Result<(), String> {
        self.pools.remove(pool_id)
            .ok_or_else(|| "Pool not found".to_string())?;
        info!("Deallocated pool {}", pool_id);
        Ok(())
    }
}

fn generate_token() -> String {
    let random_bytes: Vec<u8> = (0..32).map(|_| rand::random::<u8>()).collect();
    format!("{:x}", Sha256::digest(&random_bytes))
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt::init();

    let args: Vec<String> = std::env::args().collect();
    let port = if args.len() > 2 && args[1] == "--port" {
        args[2].parse::<u16>().unwrap_or(5555)
    } else {
        5555
    };

    let pool_size_mb = if args.len() > 4 && args[3] == "--pool-size" {
        args[4].parse::<usize>().unwrap_or(512) * 1024 * 1024
    } else {
        512 * 1024 * 1024
    };

    let listener = TcpListener::bind(format!("0.0.0.0:{}", port)).await?;
    let server = Arc::new(RAMServer::new(pool_size_mb));

    info!("Remote RAM Server listening on port {}", port);
    info!("Maximum pool size: {} MB", pool_size_mb / 1024 / 1024);

    loop {
        let (socket, addr) = listener.accept().await?;
        let server = server.clone();

        tokio::spawn(async move {
            if let Err(e) = handle_client(socket, server).await {
                error!("Client error: {}", e);
            }
        });
    }
}

async fn handle_client(
    mut socket: tokio::net::TcpStream,
    server: Arc<RAMServer>,
) -> Result<(), Box<dyn std::error::Error>> {
    let mut buffer = [0u8; 4096];

    loop {
        let n = socket.read(&mut buffer).await?;
        if n == 0 {
            return Ok(());
        }

        let command = String::from_utf8_lossy(&buffer[..n]);
        let parts: Vec<&str> = command.trim().split_whitespace().collect();

        let response = match parts.get(0).map(|s| *s) {
            Some("ALLOCATE") => {
                if parts.len() < 3 {
                    "ERROR: ALLOCATE <name> <size_mb>".to_string()
                } else {
                    let size_mb = parts[2].parse::<usize>().unwrap_or(0);
                    match server.allocate_pool(parts[1], size_mb * 1024 * 1024).await {
                        Ok(pool_id) => format!("OK {}", pool_id),
                        Err(e) => format!("ERROR: {}", e),
                    }
                }
            }
            Some("WRITE") => {
                if parts.len() < 4 {
                    "ERROR: WRITE <pool_id> <offset> <data>".to_string()
                } else {
                    let pool_id = parts[1];
                    let offset = parts[2].parse::<usize>().unwrap_or(0);
                    let data = parts[3..].join(" ").into_bytes();
                    match server.write_to_pool(pool_id, offset, &data).await {
                        Ok(_) => "OK".to_string(),
                        Err(e) => format!("ERROR: {}", e),
                    }
                }
            }
            Some("READ") => {
                if parts.len() < 4 {
                    "ERROR: READ <pool_id> <offset> <size>".to_string()
                } else {
                    let pool_id = parts[1];
                    let offset = parts[2].parse::<usize>().unwrap_or(0);
                    let size = parts[3].parse::<usize>().unwrap_or(0);
                    match server.read_from_pool(pool_id, offset, size).await {
                        Ok(data) => format!("OK {}", String::from_utf8_lossy(&data)),
                        Err(e) => format!("ERROR: {}", e),
                    }
                }
            }
            Some("LIST") => {
                let pools = server.list_pools().await;
                format!("OK [{}]", pools.join(", "))
            }
            Some("INFO") => {
                if parts.len() < 2 {
                    "ERROR: INFO <pool_id>".to_string()
                } else {
                    match server.get_pool_info(parts[1]).await {
                        Ok(info) => format!("OK {}", info),
                        Err(e) => format!("ERROR: {}", e),
                    }
                }
            }
            Some("DELETE") => {
                if parts.len() < 2 {
                    "ERROR: DELETE <pool_id>".to_string()
                } else {
                    match server.deallocate_pool(parts[1]).await {
                        Ok(_) => "OK".to_string(),
                        Err(e) => format!("ERROR: {}", e),
                    }
                }
            }
            Some("PING") => "PONG".to_string(),
            _ => "ERROR: Unknown command".to_string(),
        };

        socket.write_all(response.as_bytes()).await?;
        socket.write_all(b"\n").await?;
    }
}

mod chrono {
    pub struct Local;
    impl Local {
        pub fn now() -> DateTime {
            DateTime {
                timestamp: std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap()
                    .as_secs() as i64,
            }
        }
    }

    pub struct DateTime {
        pub timestamp: i64,
    }

    impl DateTime {
        pub fn timestamp(&self) -> i64 {
            self.timestamp
        }
    }
}

mod uuid {
    pub struct Uuid;
    impl Uuid {
        pub fn new_v4() -> String {
            format!("{:x}{:x}{:x}{:x}", rand::random::<u32>(), rand::random::<u32>(), rand::random::<u32>(), rand::random::<u32>())
        }
    }
}
