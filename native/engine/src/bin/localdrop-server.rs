//! Command-line host: runs a LocalDrop session from a laptop/desktop, and
//! is used for development and end-to-end testing of the engine.
//!
//! ```text
//! localdrop-server --name "Trip" --host "Aarav" [--port 8080] [--data ./data]
//!                  [--approval] [--resume <session-id>] [--list]
//! ```

use localdrop_engine::{engine, EngineConfig};
use std::path::PathBuf;

fn main() {
    let _ = tracing_subscriber::fmt()
        .with_env_filter(std::env::var("RUST_LOG").unwrap_or_else(|_| "localdrop_engine=info".into()))
        .try_init();
    let mut cfg = EngineConfig { data_dir: PathBuf::from("./localdrop-data"), ..Default::default() };
    let mut list = false;
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        let mut val = || args.next().unwrap_or_else(|| usage(&format!("{a} needs a value")));
        match a.as_str() {
            "--name" => cfg.session_name = val(),
            "--host" => cfg.host_name = val(),
            "--port" => cfg.port = val().parse().unwrap_or_else(|_| usage("invalid port")),
            "--data" => cfg.data_dir = PathBuf::from(val()),
            "--bind" => cfg.bind_address = Some(val()),
            "--pin-length" => cfg.pin_length = val().parse().unwrap_or_else(|_| usage("invalid pin length")),
            "--chunk-mib" => cfg.chunk_size = val().parse::<u64>().unwrap_or_else(|_| usage("invalid chunk size")) * 1024 * 1024,
            "--max-uploads" => cfg.max_concurrent_uploads = val().parse().unwrap_or_else(|_| usage("invalid number")),
            "--approval" => cfg.require_approval = true,
            "--resume" => cfg.resume_session_id = Some(val()),
            "--list" => list = true,
            "-h" | "--help" => usage(""),
            other => usage(&format!("unknown argument {other}")),
        }
    }
    if list {
        for s in engine::list_sessions(&cfg.data_dir) {
            println!(
                "{}  {:<30} photos={} videos={} bytes={} {}",
                s.id,
                s.name,
                s.photos,
                s.videos,
                s.bytes,
                if s.ended_at.is_some() { "(ended)" } else { "" }
            );
        }
        return;
    }
    let rt = tokio::runtime::Runtime::new().expect("runtime");
    rt.block_on(async move {
        let running = match engine::start(cfg).await {
            Ok(r) => r,
            Err(e) => {
                eprintln!("error: {e}");
                std::process::exit(1);
            }
        };
        let i = &running.info;
        println!("LocalDrop session \"{}\" (host: {})", i.session_name, i.host_name);
        println!("  Session id : {}", i.session_id);
        println!("  PIN        : {}", i.pin);
        if i.urls.is_empty() {
            println!("  WARNING: no Wi-Fi/hotspot interface found. Connect to a network; the address will appear here.");
        }
        for u in &i.urls {
            println!("  Open       : {u}");
        }
        if let Some(j) = &i.join_url {
            println!("  Join link  : {j}");
        }
        println!("  Data       : {}", i.session_dir.display());
        println!("Press Ctrl+C to stop (the session can be resumed with --resume {}).", i.session_id);
        let state = running.state.clone();
        tokio::select! {
            _ = tokio::signal::ctrl_c() => {}
            _ = state.shutdown.cancelled() => println!("Session ended by host."),
        }
        running.stop().await;
    });
}

fn usage(msg: &str) -> ! {
    if !msg.is_empty() {
        eprintln!("error: {msg}\n");
    }
    eprintln!(
        "usage: localdrop-server [--name NAME] [--host NAME] [--port PORT] [--data DIR] [--bind ADDR]\n\
         \x20                       [--pin-length 4-6] [--chunk-mib N] [--max-uploads N] [--approval]\n\
         \x20                       [--resume SESSION_ID] [--list]"
    );
    std::process::exit(if msg.is_empty() { 0 } else { 2 });
}
