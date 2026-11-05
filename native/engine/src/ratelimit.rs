//! Request rate limiting and PIN brute-force protection.

use std::collections::{HashMap, VecDeque};
use std::net::IpAddr;
use std::sync::Mutex;
use std::time::{Duration, Instant};

/// Token bucket per client IP.
pub struct RateLimiter {
    capacity: f64,
    refill_per_sec: f64,
    buckets: Mutex<HashMap<IpAddr, (f64, Instant)>>,
}

impl RateLimiter {
    pub fn new(capacity: u32, refill_per_sec: u32) -> Self {
        Self { capacity: capacity as f64, refill_per_sec: refill_per_sec as f64, buckets: Mutex::new(HashMap::new()) }
    }

    /// Returns `Ok(())` when allowed, or `Err(seconds_to_wait)`.
    pub fn check(&self, ip: IpAddr) -> Result<(), u64> {
        let now = Instant::now();
        let mut map = self.buckets.lock().unwrap_or_else(|e| e.into_inner());
        if map.len() > 4096 {
            map.retain(|_, (_, t)| now.duration_since(*t) < Duration::from_secs(60));
        }
        let entry = map.entry(ip).or_insert((self.capacity, now));
        let elapsed = now.duration_since(entry.1).as_secs_f64();
        entry.0 = (entry.0 + elapsed * self.refill_per_sec).min(self.capacity);
        entry.1 = now;
        if entry.0 >= 1.0 {
            entry.0 -= 1.0;
            Ok(())
        } else {
            Err(((1.0 - entry.0) / self.refill_per_sec).ceil().max(1.0) as u64)
        }
    }
}

type FailureLog = HashMap<IpAddr, VecDeque<Instant>>;

/// Limits failed PIN attempts per IP and globally (protects 4-digit PINs
/// from distributed guessing on the LAN).
pub struct PinGuard {
    window: Duration,
    per_ip: usize,
    global: usize,
    state: Mutex<(FailureLog, VecDeque<Instant>)>,
}

impl PinGuard {
    pub fn new(window: Duration, per_ip: usize, global: usize) -> Self {
        Self { window, per_ip, global, state: Mutex::new((HashMap::new(), VecDeque::new())) }
    }

    fn prune(window: Duration, q: &mut VecDeque<Instant>, now: Instant) {
        while q.front().is_some_and(|t| now.duration_since(*t) > window) {
            q.pop_front();
        }
    }

    /// `Err(retry_after_secs)` when the caller must wait.
    pub fn check(&self, ip: IpAddr) -> Result<(), u64> {
        let now = Instant::now();
        let mut st = self.state.lock().unwrap_or_else(|e| e.into_inner());
        let (per_ip, global) = &mut *st;
        Self::prune(self.window, global, now);
        if global.len() >= self.global {
            return Err(self.wait(global, now));
        }
        if let Some(q) = per_ip.get_mut(&ip) {
            Self::prune(self.window, q, now);
            if q.len() >= self.per_ip {
                return Err(self.wait(q, now));
            }
        }
        Ok(())
    }

    fn wait(&self, q: &VecDeque<Instant>, now: Instant) -> u64 {
        q.front().map(|t| self.window.saturating_sub(now.duration_since(*t)).as_secs().max(1)).unwrap_or(1)
    }

    pub fn record_failure(&self, ip: IpAddr) {
        let now = Instant::now();
        let mut st = self.state.lock().unwrap_or_else(|e| e.into_inner());
        st.0.entry(ip).or_default().push_back(now);
        st.1.push_back(now);
    }

    pub fn record_success(&self, ip: IpAddr) {
        let mut st = self.state.lock().unwrap_or_else(|e| e.into_inner());
        st.0.remove(&ip);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::Ipv4Addr;

    #[test]
    fn bucket_exhausts() {
        let rl = RateLimiter::new(3, 1);
        let ip = IpAddr::V4(Ipv4Addr::new(10, 0, 0, 2));
        assert!(rl.check(ip).is_ok());
        assert!(rl.check(ip).is_ok());
        assert!(rl.check(ip).is_ok());
        assert!(rl.check(ip).is_err());
        assert!(rl.check(IpAddr::V4(Ipv4Addr::new(10, 0, 0, 3))).is_ok());
    }

    #[test]
    fn pin_guard_locks_out() {
        let g = PinGuard::new(Duration::from_secs(60), 2, 10);
        let ip = IpAddr::V4(Ipv4Addr::new(10, 0, 0, 2));
        assert!(g.check(ip).is_ok());
        g.record_failure(ip);
        g.record_failure(ip);
        assert!(g.check(ip).is_err());
        g.record_success(ip);
        assert!(g.check(ip).is_ok());
    }
}
