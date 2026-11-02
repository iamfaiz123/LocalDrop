use serde::Serialize;
use std::path::Path;

#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
pub struct DiskSpace {
    pub free_bytes: u64,
    pub total_bytes: u64,
}

/// Free/total space of the filesystem containing `path`.
#[cfg(unix)]
#[allow(clippy::unnecessary_cast)] // field widths differ across platforms (e.g. 32-bit Android)
pub fn disk_space(path: &Path) -> Option<DiskSpace> {
    use std::ffi::CString;
    use std::os::unix::ffi::OsStrExt;
    let c = CString::new(path.as_os_str().as_bytes()).ok()?;
    let mut st = std::mem::MaybeUninit::<libc::statvfs>::uninit();
    // SAFETY: `c` is a valid NUL-terminated path and `st` points to writable memory.
    let rc = unsafe { libc::statvfs(c.as_ptr(), st.as_mut_ptr()) };
    if rc != 0 {
        return None;
    }
    // SAFETY: statvfs returned success, so the struct is initialised.
    let st = unsafe { st.assume_init() };
    let frsize = if st.f_frsize > 0 { st.f_frsize as u64 } else { st.f_bsize as u64 };
    Some(DiskSpace {
        free_bytes: (st.f_bavail as u64).saturating_mul(frsize),
        total_bytes: (st.f_blocks as u64).saturating_mul(frsize),
    })
}

#[cfg(not(unix))]
pub fn disk_space(_path: &Path) -> Option<DiskSpace> {
    None
}

pub fn is_out_of_space(e: &std::io::Error) -> bool {
    #[cfg(unix)]
    {
        e.raw_os_error() == Some(libc::ENOSPC)
    }
    #[cfg(not(unix))]
    {
        let _ = e;
        false
    }
}

/// Total size of regular files in a directory (non-recursive).
pub fn dir_size(path: &Path) -> u64 {
    std::fs::read_dir(path)
        .map(|rd| {
            rd.filter_map(|e| e.ok())
                .filter_map(|e| e.metadata().ok())
                .filter(|m| m.is_file())
                .map(|m| m.len())
                .sum()
        })
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    #[test]
    fn reports_space_for_temp_dir() {
        let s = super::disk_space(&std::env::temp_dir()).expect("statvfs");
        assert!(s.total_bytes > 0);
        assert!(s.free_bytes <= s.total_bytes);
    }
}
