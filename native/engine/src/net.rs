//! Local network interface detection. Nothing here is hard-coded: the host
//! address is always derived from the interfaces that are currently up.

use serde::Serialize;
use std::net::Ipv4Addr;

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct InterfaceInfo {
    pub name: String,
    pub ip: String,
    /// `hotspot`, `wifi`, `ethernet`, `cellular`, `vpn` or `other`.
    pub kind: String,
    /// True when participants on the same LAN/hotspot can plausibly reach it.
    pub usable: bool,
    pub score: i32,
}

pub fn is_private_v4(ip: Ipv4Addr) -> bool {
    let o = ip.octets();
    o[0] == 10 || (o[0] == 172 && (16..=31).contains(&o[1])) || (o[0] == 192 && o[1] == 168)
}

fn classify(name: &str) -> &'static str {
    let n = name.to_ascii_lowercase();
    let starts = |p: &[&str]| p.iter().any(|x| n.starts_with(x));
    if starts(&["ap", "swlan", "softap", "bridge", "rndis", "wlan1", "wigig"]) {
        "hotspot"
    } else if starts(&["wlan", "wlp", "wifi", "en0", "wl"]) {
        "wifi"
    } else if starts(&["eth", "enp", "eno", "ens", "en"]) {
        "ethernet"
    } else if starts(&["rmnet", "pdp_ip", "ccmni", "wwan", "usb_rmnet", "v4-rmnet", "clat"]) {
        "cellular"
    } else if starts(&["tun", "tap", "utun", "ipsec", "ppp", "wg"]) {
        "vpn"
    } else {
        "other"
    }
}

/// Ranks a candidate IPv4 interface. Higher is better; <= 0 is unusable.
pub fn score(name: &str, ip: Ipv4Addr) -> (String, i32) {
    let kind = classify(name).to_string();
    if ip.is_loopback() || ip.is_unspecified() || ip.is_link_local() || !is_private_v4(ip) {
        return (kind, 0);
    }
    let s = match kind.as_str() {
        "hotspot" => 100,
        "wifi" => 80,
        "ethernet" => 60,
        "other" => 40,
        _ => 0, // cellular / vpn are not reachable by hotspot clients
    };
    (kind, s)
}

/// Lists IPv4 interfaces, best candidates first.
pub fn list_interfaces() -> Vec<InterfaceInfo> {
    let mut out: Vec<InterfaceInfo> = match if_addrs::get_if_addrs() {
        Ok(list) => list
            .into_iter()
            .filter_map(|iface| match iface.ip() {
                std::net::IpAddr::V4(v4) if !v4.is_loopback() => {
                    let (kind, score) = score(&iface.name, v4);
                    Some(InterfaceInfo { name: iface.name.clone(), ip: v4.to_string(), kind, usable: score > 0, score })
                }
                _ => None,
            })
            .collect(),
        Err(e) => {
            tracing::warn!("could not enumerate network interfaces: {e}");
            Vec::new()
        }
    };
    out.sort_by(|a, b| b.score.cmp(&a.score).then(a.name.cmp(&b.name)));
    out.dedup_by(|a, b| a.ip == b.ip);
    out
}

pub fn primary(list: &[InterfaceInfo]) -> Option<&InterfaceInfo> {
    list.iter().find(|i| i.usable)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ranks_hotspot_over_wifi_and_rejects_cellular() {
        let (k, s) = score("ap0", Ipv4Addr::new(192, 168, 7, 1));
        assert_eq!((k.as_str(), s), ("hotspot", 100));
        assert_eq!(score("wlan0", Ipv4Addr::new(10, 0, 0, 5)).1, 80);
        assert_eq!(score("bridge100", Ipv4Addr::new(172, 20, 10, 1)).1, 100);
        assert_eq!(score("rmnet_data0", Ipv4Addr::new(10, 1, 2, 3)).1, 0);
        assert_eq!(score("wlan0", Ipv4Addr::new(100, 64, 1, 1)).1, 0);
        assert_eq!(score("wlan0", Ipv4Addr::new(169, 254, 1, 1)).1, 0);
    }

    #[test]
    fn private_ranges() {
        assert!(is_private_v4(Ipv4Addr::new(172, 31, 0, 1)));
        assert!(!is_private_v4(Ipv4Addr::new(172, 32, 0, 1)));
        assert!(!is_private_v4(Ipv4Addr::new(8, 8, 8, 8)));
    }
}
