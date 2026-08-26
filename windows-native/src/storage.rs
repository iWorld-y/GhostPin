use std::{
    fmt, fs, io,
    path::{Path, PathBuf},
};

use windows::{
    Win32::{
        Storage::FileSystem::{MOVEFILE_REPLACE_EXISTING, MOVEFILE_WRITE_THROUGH, MoveFileExW},
        System::Com::CoTaskMemFree,
        UI::Shell::{FOLDERID_LocalAppData, KNOWN_FOLDER_FLAG, SHGetKnownFolderPath},
    },
    core::HSTRING,
};

use crate::{
    codec::{self, CodecError, RuntimeApartment},
    core::{HudSettings, Todo},
};

/// Determines whether a debounced file reload should trigger a redraw.
///
/// A successful write performed by this process produces a directory change
/// notification as well. When the reloaded snapshot is identical, that event
/// can be consumed without drawing a duplicate frame; external changes must
/// always be rendered.
pub fn should_redraw_after_reload<T: PartialEq>(
    previous: &[T],
    current: &[T],
    own_write_pending: bool,
) -> bool {
    !own_write_pending && current != previous
}

#[derive(Debug)]
pub struct StorageError {
    pub operation: &'static str,
    pub path: PathBuf,
    pub message: String,
}
impl fmt::Display for StorageError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            formatter,
            "{} {}: {}",
            self.operation,
            self.path.display(),
            self.message
        )
    }
}
impl std::error::Error for StorageError {}
impl StorageError {
    fn io(operation: &'static str, path: &Path, error: impl fmt::Display) -> Self {
        Self {
            operation,
            path: path.to_path_buf(),
            message: error.to_string(),
        }
    }
}
impl From<CodecError> for StorageError {
    fn from(error: CodecError) -> Self {
        Self {
            operation: "JSON",
            path: PathBuf::new(),
            message: error.to_string(),
        }
    }
}

pub fn local_app_data_dir() -> Result<PathBuf, StorageError> {
    // SAFETY: the API writes and returns an allocated path owned by this call.
    let raw = unsafe { SHGetKnownFolderPath(&FOLDERID_LocalAppData, KNOWN_FOLDER_FLAG(0), None) }
        .map_err(|error| {
        StorageError::io("SHGetKnownFolderPath", Path::new("%LOCALAPPDATA%"), error)
    })?;
    // SAFETY: `raw` is a valid null-terminated PWSTR returned by the known-folder API.
    let path = unsafe { raw.to_string() }.map_err(|error| {
        StorageError::io("SHGetKnownFolderPath", Path::new("%LOCALAPPDATA%"), error)
    })?;
    // SAFETY: the known-folder API allocates this buffer with the COM task allocator.
    unsafe {
        CoTaskMemFree(Some(raw.0 as _));
    }
    Ok(PathBuf::from(path))
}

#[derive(Clone, Debug)]
pub struct StoragePaths {
    pub root: PathBuf,
    pub todos: PathBuf,
    pub settings: PathBuf,
}
impl StoragePaths {
    pub fn native() -> Result<Self, StorageError> {
        Self::under(local_app_data_dir()?)
    }
    pub fn under(root: PathBuf) -> Result<Self, StorageError> {
        let root = root.join("GhostPin");
        fs::create_dir_all(&root)
            .map_err(|error| StorageError::io("create directory", &root, error))?;
        Ok(Self {
            todos: root.join("todos.json"),
            settings: root.join("native-settings.json"),
            root,
        })
    }
}

fn read_utf8(path: &Path) -> Result<String, StorageError> {
    fs::read_to_string(path).map_err(|error| StorageError::io("read", path, error))
}
fn atomic_write(path: &Path, contents: &str) -> Result<(), StorageError> {
    let temp = path.with_extension(format!("tmp.{}", std::process::id()));
    let result = (|| {
        let mut file = fs::File::create(&temp)
            .map_err(|error| StorageError::io("create temporary", &temp, error))?;
        io::Write::write_all(&mut file, contents.as_bytes())
            .map_err(|error| StorageError::io("write temporary", &temp, error))?;
        file.sync_all()
            .map_err(|error| StorageError::io("flush temporary", &temp, error))?;
        let source = HSTRING::from(temp.to_string_lossy().as_ref());
        let target = HSTRING::from(path.to_string_lossy().as_ref()); // SAFETY: both paths are valid UTF-16 strings and the flags request an atomic replacement.
        unsafe {
            MoveFileExW(
                &source,
                &target,
                MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH,
            )
        }
        .map_err(|error| StorageError::io("replace", path, error))
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temp);
    }
    result
}

#[derive(Debug)]
pub struct TaskRepository {
    path: PathBuf,
    snapshot: Vec<Todo>,
}
impl TaskRepository {
    pub fn new(path: PathBuf) -> Self {
        Self {
            path,
            snapshot: Vec::new(),
        }
    }
    pub fn path(&self) -> &Path {
        &self.path
    }
    pub fn snapshot(&self) -> &[Todo] {
        &self.snapshot
    }
    fn load_existing(&mut self) -> Result<&[Todo], StorageError> {
        let text = read_utf8(&self.path)?;
        let parsed = codec::decode_todos(&text).map_err(StorageError::from)?;
        self.snapshot = parsed;
        Ok(&self.snapshot)
    }
    pub fn load(&mut self) -> Result<&[Todo], StorageError> {
        if !self.path.exists() {
            return Ok(&self.snapshot);
        }
        self.load_existing()
    }
    /// Reloads the file for a mutating operation and rejects a missing file.
    ///
    /// A normal watcher refresh may keep the last valid snapshot when the
    /// file is temporarily absent. A user-triggered state transition must not
    /// use that snapshot to recreate a file that another process deleted.
    pub fn load_for_update(&mut self) -> Result<&[Todo], StorageError> {
        self.load_existing()
    }
    pub fn replace(&mut self, items: &[Todo]) -> Result<(), StorageError> {
        let text = codec::encode_todos(items).map_err(StorageError::from)?;
        atomic_write(&self.path, &text)?;
        self.snapshot = items.to_vec();
        Ok(())
    }
}

#[derive(Debug)]
pub struct SettingsRepository {
    path: PathBuf,
}
impl SettingsRepository {
    pub fn new(path: PathBuf) -> Self {
        Self { path }
    }
    pub fn load(&self) -> Result<HudSettings, StorageError> {
        if !self.path.exists() {
            return Ok(HudSettings::default());
        }
        let _apartment = RuntimeApartment::new().map_err(StorageError::from)?;
        let text = read_utf8(&self.path)?;
        codec::decode_settings(&text).map_err(StorageError::from)
    }
    pub fn save(&self, settings: &HudSettings) -> Result<(), StorageError> {
        let _apartment = RuntimeApartment::new().map_err(StorageError::from)?;
        let text = codec::encode_settings(settings).map_err(StorageError::from)?;
        atomic_write(&self.path, &text)
    }
}
