use std::fmt;

use windows::{
    Win32::{
        Foundation::{CloseHandle, ERROR_ALREADY_EXISTS, GetLastError, HANDLE},
        System::Threading::CreateMutexW,
    },
    core::w,
};

#[derive(Debug)]
pub enum LifecycleError {
    Windows(String),
    NativeAlreadyRunning,
}
impl fmt::Display for LifecycleError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Windows(message) => write!(formatter, "生命周期初始化失败: {message}"),
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
        Ok(Self { mutex })
    }
}
impl Drop for AppGuard {
    fn drop(&mut self) {
        unsafe {
            let _ = CloseHandle(self.mutex);
        }
    }
}
