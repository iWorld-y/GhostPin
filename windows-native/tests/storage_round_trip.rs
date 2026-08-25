use std::{fs, time::SystemTime};

use ghostpin_native::{
    codec::RuntimeApartment,
    core::{Priority, Status, Todo},
    storage::{StoragePaths, TaskRepository},
};

fn todo() -> Todo {
    Todo {
        id: "123e4567-e89b-12d3-a456-426614174000".into(),
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

#[test]
fn repository_round_trip_is_atomic() {
    let _apartment = RuntimeApartment::new().expect("WinRT apartment");
    let root = std::env::temp_dir().join(format!("ghostpin-storage-{}", std::process::id()));
    let _ = fs::remove_dir_all(&root);
    let paths = StoragePaths::under(root.clone()).expect("paths");
    let mut repository = TaskRepository::new(paths.todos.clone());
    repository.replace(&[todo()]).expect("write");
    let mut reloaded = TaskRepository::new(paths.todos);
    assert_eq!(reloaded.load().expect("load").len(), 1);
    let _ = fs::remove_dir_all(root);
}
