use std::fmt;

use windows::{
    Win32::{
        Foundation::{
            CloseHandle, ERROR_ALREADY_EXISTS, ERROR_NO_MORE_FILES, GetLastError, HANDLE,
        },
        System::{
            Diagnostics::ToolHelp::{
                CreateToolhelp32Snapshot, PROCESSENTRY32W, Process32FirstW, Process32NextW,
                TH32CS_SNAPPROCESS,
            },
            RemoteDesktop::ProcessIdToSessionId,
            Threading::{CreateMutexW, GetCurrentProcessId},
        },
    },
    core::w,
};

#[derive(Debug)]
pub enum LifecycleError {
    Windows(String),
    WpfAlreadyRunning,
    NativeAlreadyRunning,
}
impl fmt::Display for LifecycleError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Windows(message) => write!(formatter, "生命周期初始化失败: {message}"),
            Self::WpfAlreadyRunning => {
                formatter.write_str("检测到 WPF GhostPin 正在运行，请先退出 WPF 版本")
            }
            Self::NativeAlreadyRunning => formatter.write_str("GhostPin 原生版本已经在运行"),
        }
    }
}
impl std::error::Error for LifecycleError {}

pub struct AppGuard {
    mutex: HANDLE,
}
impl AppGuard {
    pub fn acquire() -> Result<Self, LifecycleError> {
        // SAFETY: the named mutex is a process lifetime synchronization primitive owned here.
        let mutex = unsafe { CreateMutexW(None, false, w!("Local\\GhostPin.Native.App")) }
            .map_err(|error| LifecycleError::Windows(error.message().to_string()))?;
        if unsafe { GetLastError() } == ERROR_ALREADY_EXISTS {
            unsafe {
                let _ = CloseHandle(mutex);
            }
            return Err(LifecycleError::NativeAlreadyRunning);
        }
        let guard = Self { mutex };
        if wpf_process_running()? {
            return Err(LifecycleError::WpfAlreadyRunning);
        }
        Ok(guard)
    }
}
impl Drop for AppGuard {
    fn drop(&mut self) {
        unsafe {
            let _ = CloseHandle(self.mutex);
        }
    }
}

fn wpf_process_running() -> Result<bool, LifecycleError> {
    // SAFETY: the snapshot is read-only and closed before returning.
    let snapshot = unsafe { CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0) }
        .map_err(|error| LifecycleError::Windows(error.message().to_string()))?;
    let mut entry = PROCESSENTRY32W {
        dwSize: std::mem::size_of::<PROCESSENTRY32W>() as u32,
        ..Default::default()
    };
    let mut found = false;
    let mut current_session = 0u32;
    if unsafe { ProcessIdToSessionId(GetCurrentProcessId(), &mut current_session) }.is_err() {
        unsafe {
            let _ = CloseHandle(snapshot);
        }
        return Err(LifecycleError::Windows("无法获取当前用户会话".into()));
    }
    match unsafe { Process32FirstW(snapshot, &mut entry) } {
        Ok(()) => loop {
            let length = entry
                .szExeFile
                .iter()
                .position(|value| *value == 0)
                .unwrap_or(entry.szExeFile.len());
            let name = String::from_utf16_lossy(&entry.szExeFile[..length]);
            let mut session = 0u32;
            let same_session = unsafe { ProcessIdToSessionId(entry.th32ProcessID, &mut session) }
                .is_ok()
                && session == current_session;
            if same_session && name.eq_ignore_ascii_case("GhostPin.Windows.App.exe") {
                found = true;
                break;
            }
            match unsafe { Process32NextW(snapshot, &mut entry) } {
                Ok(()) => {}
                Err(error) if error.code() == ERROR_NO_MORE_FILES.into() => break,
                Err(error) => {
                    unsafe {
                        let _ = CloseHandle(snapshot);
                    }
                    return Err(LifecycleError::Windows(format!(
                        "Process32NextW 失败: {error}"
                    )));
                }
            }
        },
        Err(error) if error.code() == ERROR_NO_MORE_FILES.into() => {}
        Err(error) => {
            unsafe {
                let _ = CloseHandle(snapshot);
            }
            return Err(LifecycleError::Windows(format!(
                "Process32FirstW 失败: {error}"
            )));
        }
    }
    unsafe {
        let _ = CloseHandle(snapshot);
    }
    Ok(found)
}
