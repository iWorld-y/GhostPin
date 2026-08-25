use std::{
    fs::{self, OpenOptions},
    io::Write,
    path::PathBuf,
    time::{SystemTime, UNIX_EPOCH},
};

use windows::{
    Win32::System::Diagnostics::Debug::OutputDebugStringW,
    Win32::UI::WindowsAndMessaging::{MB_ICONERROR, MB_OK, MESSAGEBOX_STYLE, MessageBoxW},
    core::HSTRING,
};

use crate::{
    platform::PlatformError,
    storage::{StorageError, StoragePaths},
};

#[derive(Debug)]
pub struct Diagnostics {
    path: PathBuf,
    max_bytes: u64,
}
impl Diagnostics {
    pub fn native() -> Result<Self, StorageError> {
        let paths = StoragePaths::native()?;
        Ok(Self {
            path: paths.root.join("native.log"),
            max_bytes: 512 * 1024,
        })
    }
    pub fn under(path: PathBuf) -> Self {
        Self {
            path,
            max_bytes: 512 * 1024,
        }
    }
    pub fn record(&self, operation: &str, message: &str) {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_or(0, |value| value.as_secs());
        let line = format!("{stamp} [{operation}] {message}\r\n");
        if let Ok(mut file) = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&self.path)
        {
            let _ = file.write_all(line.as_bytes());
            let _ = file.sync_all();
        }
        if let Ok(metadata) = fs::metadata(&self.path)
            && metadata.len() > self.max_bytes
        {
            let _ = fs::write(&self.path, line.as_bytes());
        }
        let debug = HSTRING::from(line.as_str());
        // SAFETY: the HSTRING remains alive for the synchronous debug call.
        unsafe {
            OutputDebugStringW(&debug);
        }
    }
    pub fn record_platform(&self, error: &PlatformError) {
        self.record(error.operation, &error.to_string());
    }
    pub fn record_storage(&self, error: &StorageError) {
        self.record(error.operation, &error.to_string());
    }
    pub fn show_error(&self, title: &str, message: &str) {
        let title = HSTRING::from(title);
        let message = HSTRING::from(message); // SAFETY: both HSTRING values remain alive for the synchronous message box call.
        unsafe {
            let _ = MessageBoxW(
                None,
                &message,
                &title,
                MESSAGEBOX_STYLE(MB_OK.0 | MB_ICONERROR.0),
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn diagnostics_writes_a_local_log() {
        let path =
            std::env::temp_dir().join(format!("ghostpin-diagnostics-{}.log", std::process::id()));
        let _ = fs::remove_file(&path);
        let diagnostics = Diagnostics::under(path.clone());
        diagnostics.record("test", "diagnostic");
        assert!(
            fs::read_to_string(&path)
                .expect("log")
                .contains("diagnostic")
        );
        let _ = fs::remove_file(path);
    }
}
