use std::{cell::Cell, process::ExitCode, time::SystemTime};

use ghostpin_native::core::{
    AdvanceService, HotkeyCandidate, HudScope, Priority, ProjectionOptions, Status, Todo,
    normalize_hotkey, project, valid_hotkey,
};

fn item(id: &str, status: Status, priority: Priority) -> Todo {
    Todo {
        id: id.into(),
        title: id.into(),
        created_at: SystemTime::UNIX_EPOCH,
        status,
        completed_at: None,
        reminder_at: None,
        reminder_sent_at: None,
        priority,
        due_at: None,
        description: None,
    }
}

fn check_projection() -> bool {
    let source = vec![
        item("todo", Status::Todo, Priority::High),
        item("done", Status::Done, Priority::High),
        item("doing", Status::Doing, Priority::Low),
    ];
    let result = project(
        &source,
        ProjectionOptions {
            scope: HudScope::All,
            max_count: 8,
            now: SystemTime::now(),
            today_start: SystemTime::UNIX_EPOCH,
        },
    );
    result
        .items
        .iter()
        .map(|item| item.id.as_str())
        .collect::<Vec<_>>()
        == ["doing", "todo"]
}

fn check_advance_cooldown() -> bool {
    let now = Cell::new(0u64);
    let mut service = AdvanceService::new(|| now.get());
    let mut todo = item("advance", Status::Todo, Priority::Medium);
    service.advance(&mut todo, SystemTime::UNIX_EPOCH)
        && !service.advance(&mut todo, SystemTime::UNIX_EPOCH)
        && {
            now.set(500);
            service.advance(&mut todo, SystemTime::UNIX_EPOCH)
        }
        && todo.status == Status::Done
        && todo.completed_at.is_some()
}

fn check_hotkey_normalization() -> bool {
    let candidate = normalize_hotkey(0x0002, 0x47);
    candidate
        == Some(HotkeyCandidate {
            modifiers: 0x0002,
            key: 0x47,
        })
        && valid_hotkey(0, 0x70)
        && !valid_hotkey(0, 0x47)
}

fn main() -> ExitCode {
    let checks = [
        ("projection", check_projection()),
        ("advance-cooldown", check_advance_cooldown()),
        ("hotkey-normalization", check_hotkey_normalization()),
    ];
    let failures = checks.iter().filter(|(_, passed)| !passed).count();
    for (name, passed) in checks {
        println!("{} {name}", if passed { "PASS" } else { "FAIL" });
    }
    if failures == 0 {
        println!("PASS ghostpin-native-core-checks ({} checks)", checks.len());
        ExitCode::SUCCESS
    } else {
        eprintln!("FAIL ghostpin-native-core-checks ({failures} failed)");
        ExitCode::FAILURE
    }
}
