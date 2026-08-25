#![allow(clippy::undocumented_unsafe_blocks)]
#![allow(clippy::chunks_exact_to_as_chunks)]
#![allow(clippy::collapsible_if)]

use std::{
    fmt,
    path::PathBuf,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
        mpsc::{self, Receiver, Sender},
    },
    thread::{self, JoinHandle},
};

use windows::{
    Win32::{
        Foundation::{CloseHandle, ERROR_IO_PENDING, WAIT_OBJECT_0, WAIT_TIMEOUT},
        Storage::FileSystem::{
            CreateFileW, FILE_ACTION_ADDED, FILE_ACTION_MODIFIED, FILE_ACTION_REMOVED,
            FILE_ACTION_RENAMED_NEW_NAME, FILE_ACTION_RENAMED_OLD_NAME, FILE_FLAG_BACKUP_SEMANTICS,
            FILE_FLAG_OVERLAPPED, FILE_LIST_DIRECTORY, FILE_NOTIFY_CHANGE_FILE_NAME,
            FILE_NOTIFY_CHANGE_LAST_WRITE, FILE_NOTIFY_CHANGE_SIZE, FILE_SHARE_DELETE,
            FILE_SHARE_READ, FILE_SHARE_WRITE, OPEN_EXISTING, ReadDirectoryChangesW,
        },
        System::{
            IO::{CancelIoEx, GetOverlappedResult, OVERLAPPED},
            Threading::{CreateEventW, INFINITE, WaitForSingleObject},
        },
    },
    core::{Error as WindowsError, HSTRING},
};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ChangeKind {
    Added,
    Modified,
    Removed,
    Renamed,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct FileChange {
    pub kind: ChangeKind,
    pub name: String,
}

pub fn parse_notifications(buffer: &[u8], bytes: usize) -> Result<Vec<FileChange>, String> {
    let mut offset = 0usize;
    let mut changes = Vec::new();
    while offset < bytes {
        if bytes - offset < 12 {
            return Err("FILE_NOTIFY_INFORMATION header is truncated".into());
        }
        let next = u32::from_le_bytes(buffer[offset..offset + 4].try_into().unwrap()) as usize;
        let action = u32::from_le_bytes(buffer[offset + 4..offset + 8].try_into().unwrap());
        let name_bytes =
            u32::from_le_bytes(buffer[offset + 8..offset + 12].try_into().unwrap()) as usize;
        let name_start = offset + 12;
        let name_end = name_start
            .checked_add(name_bytes)
            .ok_or("FILE_NOTIFY_INFORMATION name overflow")?;
        if name_end > bytes || !name_bytes.is_multiple_of(2) {
            return Err("FILE_NOTIFY_INFORMATION name is out of bounds".into());
        }
        let name = String::from_utf16(
            &buffer[name_start..name_end]
                .chunks_exact(2)
                .map(|value| u16::from_le_bytes([value[0], value[1]]))
                .collect::<Vec<_>>(),
        )
        .map_err(|_| "FILE_NOTIFY_INFORMATION name is not UTF-16")?;
        let kind = match action {
            value if value == FILE_ACTION_ADDED.0 => ChangeKind::Added,
            value if value == FILE_ACTION_MODIFIED.0 => ChangeKind::Modified,
            value if value == FILE_ACTION_REMOVED.0 => ChangeKind::Removed,
            value
                if value == FILE_ACTION_RENAMED_NEW_NAME.0
                    || value == FILE_ACTION_RENAMED_OLD_NAME.0 =>
            {
                ChangeKind::Renamed
            }
            _ => return Err("unknown FILE_NOTIFY_INFORMATION action".into()),
        };
        changes.push(FileChange { kind, name });
        if next == 0 {
            break;
        }
        if next < 12 || offset + next > bytes {
            return Err("FILE_NOTIFY_INFORMATION next offset is out of bounds".into());
        }
        offset += next;
    }
    Ok(changes)
}

#[derive(Debug)]
pub struct WatcherError(pub String);
impl fmt::Display for WatcherError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.0)
    }
}
impl std::error::Error for WatcherError {}
impl From<WindowsError> for WatcherError {
    fn from(error: WindowsError) -> Self {
        Self(error.message().to_string())
    }
}

pub struct DirectoryWatcher {
    stop: Arc<AtomicBool>,
    join: Option<JoinHandle<()>>,
}
impl DirectoryWatcher {
    pub fn start(path: PathBuf) -> Result<(Self, Receiver<Vec<FileChange>>), WatcherError> {
        let (sender, receiver) = mpsc::channel();
        let stop = Arc::new(AtomicBool::new(false));
        let worker_stop = Arc::clone(&stop);
        let join = thread::Builder::new()
            .name("ghostpin-storage-watcher".into())
            .spawn(move || worker(path, worker_stop, sender))
            .map_err(|error| WatcherError(error.to_string()))?;
        Ok((
            Self {
                stop,
                join: Some(join),
            },
            receiver,
        ))
    }
    pub fn stop(&mut self) {
        self.stop.store(true, Ordering::Release);
        if let Some(join) = self.join.take() {
            let _ = join.join();
        }
    }
}
impl Drop for DirectoryWatcher {
    fn drop(&mut self) {
        self.stop();
    }
}

fn worker(path: PathBuf, stop: Arc<AtomicBool>, sender: Sender<Vec<FileChange>>) {
    let path = HSTRING::from(path.to_string_lossy().as_ref());
    let handle = unsafe {
        CreateFileW(
            &path,
            FILE_LIST_DIRECTORY.0,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
            None,
            OPEN_EXISTING,
            FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED,
            None,
        )
    };
    let Ok(handle) = handle else {
        return;
    };
    let event = unsafe { CreateEventW(None, true, false, None) };
    let Ok(event) = event else {
        unsafe {
            let _ = CloseHandle(handle);
        }
        return;
    };
    let mut buffer = vec![0u8; 16 * 1024];
    let mut overlapped = Box::new(OVERLAPPED {
        hEvent: event,
        ..Default::default()
    });
    loop {
        if stop.load(Ordering::Acquire) {
            break;
        }
        unsafe {
            let _ = windows::Win32::System::Threading::ResetEvent(event);
        }
        let result = unsafe {
            ReadDirectoryChangesW(
                handle,
                buffer.as_mut_ptr().cast(),
                buffer.len() as u32,
                false,
                FILE_NOTIFY_CHANGE_FILE_NAME
                    | FILE_NOTIFY_CHANGE_LAST_WRITE
                    | FILE_NOTIFY_CHANGE_SIZE,
                None,
                Some(&mut *overlapped),
                None,
            )
        };
        if let Err(error) = result {
            if error.code() != ERROR_IO_PENDING.into() {
                break;
            }
        }
        loop {
            let wait = unsafe { WaitForSingleObject(event, 100) };
            if wait == WAIT_OBJECT_0 {
                break;
            }
            if wait != WAIT_TIMEOUT && stop.load(Ordering::Acquire) {
                break;
            }
            if stop.load(Ordering::Acquire) {
                unsafe {
                    let _ = CancelIoEx(handle, Some(&*overlapped));
                }
                unsafe {
                    let _ = WaitForSingleObject(event, INFINITE);
                }
                break;
            }
        }
        if stop.load(Ordering::Acquire) {
            break;
        }
        let mut bytes = 0u32;
        if unsafe { GetOverlappedResult(handle, &*overlapped, &mut bytes, false) }.is_ok()
            && bytes > 0
        {
            if let Ok(changes) = parse_notifications(&buffer, bytes as usize) {
                let _ = sender.send(changes);
            }
        }
    }
    unsafe {
        let _ = CancelIoEx(handle, Some(&*overlapped));
        let _ = CloseHandle(event);
        let _ = CloseHandle(handle);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_truncated_notifications() {
        assert!(parse_notifications(&[0; 8], 8).is_err());
    }
}
