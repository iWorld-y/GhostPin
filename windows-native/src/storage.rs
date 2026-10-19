use std::{
    fmt, fs, io,
    path::{Path, PathBuf},
    time::SystemTime,
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
    core::{AdvanceService, HudSettings, TaskDocument, Todo},
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
    document: TaskDocument,
}
impl TaskRepository {
    pub fn new(path: PathBuf) -> Self {
        Self {
            path,
            document: TaskDocument::default(),
        }
    }
    pub fn path(&self) -> &Path {
        &self.path
    }
    pub fn snapshot(&self) -> &[Todo] {
        &self.document.items
    }
    pub fn document(&self) -> &TaskDocument {
        &self.document
    }
    fn read_latest(&self) -> Result<(TaskDocument, Option<Vec<u8>>), StorageError> {
        let text = read_utf8(&self.path)?;
        let (document, legacy) = codec::decode_document(&text).map_err(StorageError::from)?;
        Ok((document, legacy.then(|| text.into_bytes())))
    }
    pub fn load(&mut self) -> Result<&[Todo], StorageError> {
        let _lock = lock_tasks(&self.path)?;
        if !self.path.exists() {
            return Ok(self.snapshot());
        }
        let (document, legacy) = self.read_latest()?;
        if let Some(data) = legacy {
            self.commit(&document, Some(&data))?;
        }
        self.document = document;
        Ok(self.snapshot())
    }
    /// 在固定文件锁内读取、推进和提交，过期快照不得写回。
    pub fn advance_status<F: Fn() -> u64>(
        &mut self,
        id: u64,
        service: &mut AdvanceService<F>,
        at: SystemTime,
    ) -> Result<bool, StorageError> {
        let _lock = lock_tasks(&self.path)?;
        let (mut document, legacy) = self.read_latest()?;
        if !document.items.iter().any(|item| item.id == id) {
            return Err(StorageError::io(
                "advance",
                &self.path,
                format!("未找到任务：{id}"),
            ));
        }
        if service.advance_by_id(&mut document.items, id, at).is_none() {
            return Ok(false);
        }
        if let Err(error) = self.commit(&document, legacy.as_deref()) {
            service.rollback(id);
            return Err(error);
        }
        self.document = document;
        Ok(true)
    }
    fn commit(&self, document: &TaskDocument, legacy: Option<&[u8]>) -> Result<(), StorageError> {
        let text = codec::encode_document(document).map_err(StorageError::from)?;
        if let Some(data) = legacy {
            preserve_backup(&self.path.with_file_name("todos.v1.backup.json"), data)?;
        }
        atomic_write(&self.path, &text)?;
        Ok(())
    }
}

fn lock_tasks(path: &Path) -> Result<fs::File, StorageError> {
    let lock = path.with_file_name(".todos.lock");
    let file = fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(&lock)
        .map_err(|error| StorageError::io("open lock", &lock, error))?;
    file.lock()
        .map_err(|error| StorageError::io("lock", &lock, error))?;
    // 文件句柄存活到事务结束；关闭时释放进程间排他锁。
    Ok(file)
}

fn preserve_backup(path: &Path, data: &[u8]) -> Result<(), StorageError> {
    match fs::File::create_new(path) {
        Ok(mut file) => {
            let result = io::Write::write_all(&mut file, data).and_then(|_| file.sync_all());
            if let Err(error) = result {
                drop(file);
                let _ = fs::remove_file(path);
                return Err(StorageError::io("backup", path, error));
            }
            Ok(())
        }
        Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {
            if fs::read(path).map_err(|error| StorageError::io("read backup", path, error))? == data
            {
                Ok(())
            } else {
                Err(StorageError::io("backup", path, "备份内容与旧数据不一致"))
            }
        }
        Err(error) => Err(StorageError::io("backup", path, error)),
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
