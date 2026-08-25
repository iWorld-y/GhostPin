#![windows_subsystem = "windows"]

use std::time::{Duration, Instant, SystemTime};

use ghostpin_native::{
    codec::RuntimeApartment,
    core::{ProjectionOptions, project},
    diagnostics::Diagnostics,
    platform::{HudWindow, MessageWindow},
    render::HudSurface,
    storage::{SettingsRepository, StoragePaths, TaskRepository},
    watcher::DirectoryWatcher,
};
use windows::Win32::System::Threading::Sleep;
use windows::Win32::UI::WindowsAndMessaging::{
    DispatchMessageW, MSG, PM_REMOVE, PeekMessageW, TranslateMessage,
};

fn run() -> Result<(), Box<dyn std::error::Error>> {
    let _apartment = RuntimeApartment::new()?;
    let paths = StoragePaths::native()?;
    let settings = SettingsRepository::new(paths.settings.clone()).load()?;
    let mut repository = TaskRepository::new(paths.todos.clone());
    let snapshot = repository.load()?.to_vec();
    let width = settings.placement.logical_width.round() as i32;
    let height = settings.placement.logical_height.round() as i32;
    let hud = HudWindow::new(settings.mode, width, height)?;
    let mut surface = HudSurface::new(width, height)?;
    let now = SystemTime::now();
    let projection = project(
        &snapshot,
        ProjectionOptions {
            scope: settings.scope,
            max_count: settings.max_items,
            now,
            today_start: now
                .checked_sub(Duration::from_secs(24 * 60 * 60))
                .unwrap_or(now),
        },
    );
    surface.draw(&projection);
    if settings.visible {
        surface.present(hud.hwnd(), 40, 40, (settings.opacity * 255.0).round() as u8)?;
        hud.show();
    } else {
        hud.hide();
    }
    let (_watcher, changes) = DirectoryWatcher::start(paths.root.clone())?;
    let _message_window = MessageWindow::new()?;
    let mut message = MSG::default();
    let mut pending_reload = None;
    loop {
        while unsafe { PeekMessageW(&mut message, None, 0, 0, PM_REMOVE) }.as_bool() {
            if message.message == windows::Win32::UI::WindowsAndMessaging::WM_QUIT {
                return Ok(());
            }
            // SAFETY: the message was initialized by PeekMessageW.
            unsafe {
                let _ = TranslateMessage(&message);
                let _ = DispatchMessageW(&message);
            }
        }
        if changes.try_recv().is_ok() {
            pending_reload = Some(Instant::now());
        }
        if pending_reload.is_some_and(|at| at.elapsed() >= Duration::from_millis(500)) {
            if repository.load().is_ok() {
                let now = SystemTime::now();
                let projection = project(
                    repository.snapshot(),
                    ProjectionOptions {
                        scope: settings.scope,
                        max_count: settings.max_items,
                        now,
                        today_start: now
                            .checked_sub(Duration::from_secs(24 * 60 * 60))
                            .unwrap_or(now),
                    },
                );
                surface.draw(&projection);
                let _ =
                    surface.present(hud.hwnd(), 40, 40, (settings.opacity * 255.0).round() as u8);
            }
            pending_reload = None;
        }
        // SAFETY: yielding the UI thread does not borrow any Rust state.
        unsafe {
            Sleep(50);
        }
    }
}

fn main() {
    if let Err(error) = run()
        && let Ok(diagnostics) = Diagnostics::native()
    {
        diagnostics.record("startup", &error.to_string());
        diagnostics.show_error("GhostPin Native", &error.to_string());
    }
}
