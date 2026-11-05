use rand::rngs::OsRng;
use rand::{Rng, RngCore};
use sha2::{Digest, Sha256};
use std::time::{SystemTime, UNIX_EPOCH};

pub fn now_ms() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as i64).unwrap_or(0)
}

/// Cryptographically secure random hex token (`bytes` bytes of entropy).
pub fn random_token(bytes: usize) -> String {
    let mut buf = vec![0u8; bytes];
    OsRng.fill_bytes(&mut buf);
    hex::encode(buf)
}

/// Opaque internal identifier (128 bits, hex).
pub fn new_id() -> String {
    random_token(16)
}

/// Numeric PIN of `len` digits (4..=6) from the OS CSPRNG.
pub fn random_pin(len: usize) -> String {
    let len = len.clamp(4, 6);
    (0..len).map(|_| char::from(b'0' + OsRng.gen_range(0..10u8))).collect()
}

pub fn sha256_hex(data: &[u8]) -> String {
    hex::encode(Sha256::digest(data))
}

pub fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    a.iter().zip(b).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}

pub fn is_sha256_hex(s: &str) -> bool {
    s.len() == 64 && s.bytes().all(|b| b.is_ascii_hexdigit())
}

/// Turns an untrusted client filename into a safe display name.
/// The result is never used as a filesystem path; it is only shown to users
/// and used inside `Content-Disposition` / ZIP entry names.
pub fn sanitize_filename(name: &str) -> String {
    let base = name.rsplit(['/', '\\']).next().unwrap_or("");
    let cleaned: String = base
        .chars()
        .filter(|c| !c.is_control())
        .map(|c| if matches!(c, '<' | '>' | ':' | '"' | '|' | '?' | '*') { '_' } else { c })
        .collect();
    let trimmed = cleaned.trim().trim_start_matches('.').trim_end_matches(['.', ' ']).to_string();
    let mut out = String::new();
    for c in trimmed.chars() {
        if out.len() + c.len_utf8() > 150 {
            break;
        }
        out.push(c);
    }
    if out.is_empty() {
        "file".to_string()
    } else {
        out
    }
}

pub fn extension_of(name: &str) -> Option<String> {
    let (stem, ext) = name.rsplit_once('.')?;
    if stem.is_empty() || ext.is_empty() || ext.len() > 8 {
        return None;
    }
    Some(ext.to_ascii_lowercase())
}

/// Validates and normalises a display name (session or participant).
pub fn clean_display_name(name: &str, max_chars: usize) -> Option<String> {
    let n: String = name.chars().filter(|c| !c.is_control()).collect();
    let n = n.split_whitespace().collect::<Vec<_>>().join(" ");
    if n.is_empty() || n.chars().count() > max_chars {
        return None;
    }
    Some(n)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sanitizes_paths_and_reserved_chars() {
        assert_eq!(sanitize_filename("../../etc/passwd"), "passwd");
        assert_eq!(sanitize_filename("C:\\Users\\x\\IMG 1.JPG"), "IMG 1.JPG");
        assert_eq!(sanitize_filename("a<b>c?.jpg"), "a_b_c_.jpg");
        assert_eq!(sanitize_filename("..."), "file");
        assert_eq!(sanitize_filename(".hidden.jpg"), "hidden.jpg");
        assert_eq!(sanitize_filename("x\u{0}y.png"), "xy.png");
    }

    #[test]
    fn pin_and_tokens() {
        let p = random_pin(6);
        assert_eq!(p.len(), 6);
        assert!(p.chars().all(|c| c.is_ascii_digit()));
        assert_eq!(random_pin(2).len(), 4);
        assert_eq!(random_token(32).len(), 64);
        assert_ne!(random_token(32), random_token(32));
    }

    #[test]
    fn extensions() {
        assert_eq!(extension_of("IMG.JPG").as_deref(), Some("jpg"));
        assert_eq!(extension_of("noext"), None);
        assert_eq!(extension_of(".jpg"), None);
    }

    #[test]
    fn display_names() {
        assert_eq!(clean_display_name("  Riya   K ", 40).as_deref(), Some("Riya K"));
        assert_eq!(clean_display_name("   ", 40), None);
        assert_eq!(clean_display_name(&"x".repeat(41), 40), None);
    }
}
