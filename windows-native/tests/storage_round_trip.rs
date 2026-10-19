use std::{
    fs,
    sync::mpsc::Receiver,
    time::{Duration, SystemTime},
};

use ghostpin_native::{
    codec::{self, RuntimeApartment},
    core::{AdvanceService, Priority, Status, TaskDocument, Todo},
    platform::{MessageWindow, PlatformEvent, pump_messages},
    storage::{StoragePaths, TaskRepository, should_redraw_after_reload},
    watcher::WatcherEvent,
};
use windows::{
    Win32::Storage::FileSystem::{MOVEFILE_REPLACE_EXISTING, MOVEFILE_WRITE_THROUGH, MoveFileExW},
    core::HSTRING,
};

fn todo() -> Todo {
    Todo {
        id: 10000,
        group: "默认".into(),
        title: "测试".into(),
        created_at: SystemTime::UNIX_EPOCH,
        status: Status::Todo,
        completed_at: None,
        reminder_at: None,
        reminder_sent_at: None,
        priority: Priority::Medium,
        due_at: None,
        description: None,
    }
}

fn document(items: &[Todo], next_id: u64) -> TaskDocument {
    TaskDocument {
        next_id,
        items: items.to_vec(),
        ..TaskDocument::default()
    }
}

fn write_tasks(path: &std::path::Path, items: &[Todo], next_id: u64) {
    fs::write(
        path,
        codec::encode_document(&document(items, next_id)).expect("encode"),
    )
    .expect("fixture write");
}

#[test]
fn stale_advance_preserves_external_group_tasks_and_counter() {
    let _apartment = RuntimeApartment::new().expect("WinRT apartment");
    let root = std::env::temp_dir().join(format!("ghostpin-stale-{}", std::process::id()));
    let paths = StoragePaths::under(root.clone()).expect("paths");
    let mut first = todo();
    write_tasks(&paths.todos, &[first.clone()], 10001);
    let mut stale = TaskRepository::new(paths.todos.clone());
    stale.load().expect("old snapshot");
    first.group = "外部新组".into();
    let mut second = todo();
    second.id = 10001;
    write_tasks(&paths.todos, &[first, second.clone()], 10005);
    assert!(
        stale
            .advance_status(10000, &mut AdvanceService::default(), SystemTime::now())
            .expect("advance")
    );
    assert_eq!(stale.document().next_id, 10005);
    assert_eq!(stale.snapshot()[0].group, "外部新组");
    assert_eq!(stale.snapshot()[0].status, Status::Doing);
    assert_eq!(stale.snapshot()[1], second);
    write_tasks(&paths.todos, &[second], 10005);
    let before = fs::read(&paths.todos).expect("read");
    assert!(
        stale
            .advance_status(10000, &mut AdvanceService::default(), SystemTime::now())
            .is_err()
    );
    assert_eq!(fs::read(&paths.todos).expect("read after"), before);
    let _ = fs::remove_dir_all(root);
}

#[test]
fn migration_backup_conflict_and_failed_commit_are_retryable() {
    let _apartment = RuntimeApartment::new().expect("WinRT apartment");
    let root = std::env::temp_dir().join(format!("ghostpin-migration-{}", std::process::id()));
    let paths = StoragePaths::under(root.clone()).expect("paths");
    let legacy = include_bytes!("fixtures/tasks-groups-legacy.json");
    let backup = paths.root.join("todos.v1.backup.json");
    fs::write(&paths.todos, legacy).expect("legacy");
    fs::write(&backup, b"conflict").expect("conflicting backup");
    let mut repository = TaskRepository::new(paths.todos.clone());
    assert!(repository.load().is_err());
    assert_eq!(fs::read(&paths.todos).expect("read"), legacy);
    assert_eq!(fs::read(&backup).expect("backup"), b"conflict");
    fs::remove_file(&backup).expect("remove conflict");
    let blocked = paths
        .todos
        .with_extension(format!("tmp.{}", std::process::id()));
    fs::create_dir(&blocked).expect("block temporary commit");
    assert!(repository.load().is_err());
    assert!(repository.snapshot().is_empty());
    assert_eq!(fs::read(&paths.todos).expect("read"), legacy);
    assert_eq!(fs::read(&backup).expect("backup"), legacy);
    fs::remove_dir(&blocked).expect("unblock");
    repository.load().expect("retry migration");
    assert_eq!(repository.document().next_id, 10003);
    let migrated = fs::read(&paths.todos).expect("migrated");
    repository.load().expect("repeat load");
    assert_eq!(fs::read(&paths.todos).expect("repeat"), migrated);
    let _ = fs::remove_dir_all(root);
}

fn wait_for_task_file_change(receiver: &Receiver<WatcherEvent>) {
    let deadline = std::time::Instant::now() + Duration::from_secs(5);
    while std::time::Instant::now() < deadline {
        let remaining = deadline.saturating_duration_since(std::time::Instant::now());
        match receiver.recv_timeout(remaining).expect("watcher event") {
            WatcherEvent::Changes(changes)
                if changes.iter().any(|change| change.name == "todos.json") =>
            {
                return;
            }
            WatcherEvent::Overflow => return,
            WatcherEvent::Changes(_) => {}
            WatcherEvent::Error(message) => panic!("watcher error: {message}"),
        }
    }
    panic!("timed out waiting for todos.json watcher event");
}

fn replace_file(source: &std::path::Path, target: &std::path::Path) {
    let source = HSTRING::from(source.to_string_lossy().as_ref());
    let target = HSTRING::from(target.to_string_lossy().as_ref());
    // SAFETY: both HSTRING values are valid null-terminated UTF-16 paths and
    // the flags request replacement with write-through semantics.
    unsafe {
        MoveFileExW(
            &source,
            &target,
            MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH,
        )
    }
    .expect("atomic replacement");
}

#[test]
fn repository_round_trip_is_atomic() {
    let _apartment = RuntimeApartment::new().expect("WinRT apartment");
    let root = std::env::temp_dir().join(format!("ghostpin-storage-{}", std::process::id()));
    let _ = fs::remove_dir_all(&root);
    let paths = StoragePaths::under(root.clone()).expect("paths");
    let mut repository = TaskRepository::new(paths.todos.clone());
    write_tasks(&paths.todos, &[todo()], 10001);
    let mut reloaded = TaskRepository::new(paths.todos);
    assert_eq!(reloaded.load().expect("load").len(), 1);
    fs::remove_file(reloaded.path()).expect("remove task file");
    assert_eq!(reloaded.load().expect("preserve snapshot").len(), 1);
    assert!(
        reloaded
            .advance_status(10000, &mut AdvanceService::default(), SystemTime::now())
            .is_err()
    );
    let _ = fs::remove_dir_all(root);
}

#[test]
fn watcher_refresh_preserves_snapshot_during_corruption_and_recovers() {
    let _apartment = RuntimeApartment::new().expect("WinRT apartment");
    let root = std::env::temp_dir().join(format!(
        "ghostpin-watcher-{}-{}",
        std::process::id(),
        SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .expect("clock")
            .as_nanos()
    ));
    let _ = fs::remove_dir_all(&root);
    let paths = StoragePaths::under(root.clone()).expect("paths");
    let first = todo();
    let mut repository = TaskRepository::new(paths.todos.clone());
    write_tasks(&paths.todos, std::slice::from_ref(&first), 10001);
    repository.load().expect("initial load");
    let (mut watcher, changes) =
        ghostpin_native::watcher::DirectoryWatcher::start(paths.root.clone()).expect("watcher");

    let mut second = first.clone();
    second.title = "外部替换".into();
    let replacement = paths.root.join("todos.external.tmp");
    fs::write(
        &replacement,
        codec::encode_document(&document(std::slice::from_ref(&second), 10001))
            .expect("encode replacement"),
    )
    .expect("write replacement");
    replace_file(&replacement, &paths.todos);
    wait_for_task_file_change(&changes);
    repository.load().expect("load replacement");
    assert_eq!(repository.snapshot(), &[second.clone()]);

    fs::write(&paths.todos, b"{ temporarily invalid").expect("write corruption");
    wait_for_task_file_change(&changes);
    assert!(repository.load().is_err());
    assert_eq!(repository.snapshot(), &[second.clone()]);

    let mut recovered = second;
    recovered.title = "恢复".into();
    fs::write(
        &paths.todos,
        codec::encode_document(&document(std::slice::from_ref(&recovered), 10001))
            .expect("encode recovery"),
    )
    .expect("write recovery");
    wait_for_task_file_change(&changes);
    repository.load().expect("load recovery");
    assert_eq!(repository.snapshot(), &[recovered]);
    watcher.stop();
    let _ = fs::remove_dir_all(root);
}

#[test]
fn own_write_reload_is_deduplicated_but_external_change_redraws() {
    let previous = vec![1, 2, 3];
    assert!(!should_redraw_after_reload(&previous, &previous, true));
    assert!(!should_redraw_after_reload(&previous, &previous, false));
    assert!(should_redraw_after_reload(&previous, &[1, 2, 4], false));
}

#[test]
fn message_window_coalesces_duplicate_file_notifications() {
    let (sender, receiver) = std::sync::mpsc::channel();
    let window = MessageWindow::new(sender).expect("message window");
    window.notify_file_change().expect("first notification");
    window.notify_file_change().expect("second notification");
    window.notify_file_change().expect("third notification");

    let deadline = std::time::Instant::now() + Duration::from_secs(2);
    let mut refreshes = 0;
    while std::time::Instant::now() < deadline {
        pump_messages(None);
        while let Ok(event) = receiver.try_recv() {
            if event == PlatformEvent::FilesChanged {
                refreshes += 1;
            }
        }
        if refreshes > 0 {
            break;
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    pump_messages(None);
    while let Ok(event) = receiver.try_recv() {
        if event == PlatformEvent::FilesChanged {
            refreshes += 1;
        }
    }
    assert_eq!(refreshes, 1);
}
