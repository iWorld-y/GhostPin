#![windows_subsystem = "windows"]

use std::{
    sync::mpsc,
    time::{Duration, SystemTime},
};

use ghostpin_native::{
    codec::RuntimeApartment,
    core::{
        AdvanceService, HOTKEY_ALT, HOTKEY_CONTROL, HudSettings, ProjectionOptions,
        normalize_settings, project,
    },
    diagnostics::Diagnostics,
    lifecycle::AppGuard,
    platform::{HudWindow, MessageWindow, PlatformEvent, SettingsChange, pump_messages},
    render::HudSurface,
    settings::SettingsWindow,
    storage::{SettingsRepository, StoragePaths, TaskRepository, should_redraw_after_reload},
    watcher::{DirectoryWatcher, WatcherEvent},
};
use windows::Win32::{
    Foundation::{FILETIME, SYSTEMTIME},
    System::{
        SystemInformation::GetLocalTime,
        Threading::Sleep,
        Time::{SystemTimeToFileTime, TzSpecificLocalTimeToSystemTime},
    },
};

fn today_start(now: SystemTime) -> SystemTime {
    // Convert the local calendar midnight to UTC before comparing stored UTC timestamps.
    let mut local: SYSTEMTIME = unsafe { GetLocalTime() };
    local.wHour = 0;
    local.wMinute = 0;
    local.wSecond = 0;
    local.wMilliseconds = 0;
    let mut utc = SYSTEMTIME::default();
    if unsafe { TzSpecificLocalTimeToSystemTime(None, &local, &mut utc) }.is_err() {
        return now
            .checked_sub(Duration::from_secs(24 * 60 * 60))
            .unwrap_or(now);
    }
    let mut file_time = FILETIME::default();
    if unsafe { SystemTimeToFileTime(&utc, &mut file_time) }.is_err() {
        return now
            .checked_sub(Duration::from_secs(24 * 60 * 60))
            .unwrap_or(now);
    }
    let ticks = (u64::from(file_time.dwHighDateTime) << 32) | u64::from(file_time.dwLowDateTime);
    let Some(seconds) = ticks
        .checked_div(10_000_000)
        .and_then(|value| value.checked_sub(11_644_473_600))
    else {
        return now;
    };
    std::time::UNIX_EPOCH + Duration::from_secs(seconds)
}

fn redraw(
    surface: &mut HudSurface,
    hud: &HudWindow,
    repository: &TaskRepository,
    settings: &HudSettings,
) -> Result<(), Box<dyn std::error::Error>> {
    let now = SystemTime::now();
    let projection = project(
        repository.snapshot(),
        ProjectionOptions {
            scope: settings.scope,
            max_count: settings.max_items,
            now,
            today_start: today_start(now),
        },
    );
    surface.draw(&projection)?;
    hud.set_hit_regions(surface.hit_regions(&projection));
    if settings.visible {
        let rect = hud.pixel_rect()?;
        surface.present(
            hud.hwnd(),
            rect.left,
            rect.top,
            (settings.opacity.clamp(0.5, 1.0) * 255.0).round() as u8,
        )?;
    }
    Ok(())
}

fn save_settings(repository: &SettingsRepository, settings: &HudSettings) -> bool {
    if let Err(error) = repository.save(settings) {
        eprintln!("settings save failed: {error}");
        if let Ok(diagnostics) = Diagnostics::native() {
            diagnostics.record_storage(&error);
        }
        false
    } else {
        true
    }
}

fn record_runtime_error(category: &str, error: &dyn std::fmt::Display) {
    let message = error.to_string();
    eprintln!("{category}: {message}");
    if let Ok(diagnostics) = Diagnostics::native() {
        diagnostics.record(category, &message);
    }
}

fn redraw_safe(
    surface: &mut HudSurface,
    hud: &HudWindow,
    repository: &TaskRepository,
    settings: &HudSettings,
) {
    if let Err(error) = redraw(surface, hud, repository, settings) {
        record_runtime_error("render", error.as_ref());
    }
}

#[derive(Clone, Copy)]
enum HotkeyApplyResult {
    Applied,
    RegistrationFailed,
    PersistenceFailed,
    RestoreFailed,
}

fn hotkey_result_message(result: HotkeyApplyResult) -> &'static str {
    match result {
        HotkeyApplyResult::Applied => "快捷键已启用",
        HotkeyApplyResult::RegistrationFailed => "快捷键冲突，原组合保持不变",
        HotkeyApplyResult::PersistenceFailed => "快捷键保存失败，原组合保持不变",
        HotkeyApplyResult::RestoreFailed => "快捷键回退失败，已禁用",
    }
}

fn apply_hotkey_candidate(
    hud: &HudWindow,
    settings: &mut HudSettings,
    repository: &SettingsRepository,
    modifiers: u32,
    key: u32,
) -> HotkeyApplyResult {
    let old_enabled = settings.hotkey_enabled;
    let old_modifiers = settings.hotkey_modifiers;
    let old_key = settings.hotkey_key;
    hud.unregister_hotkey();
    match hud.register_hotkey(modifiers, key) {
        Ok(()) => {
            settings.hotkey_enabled = true;
            settings.hotkey_modifiers = modifiers;
            settings.hotkey_key = key;
            if save_settings(repository, settings) {
                HotkeyApplyResult::Applied
            } else {
                hud.unregister_hotkey();
                settings.hotkey_enabled = old_enabled;
                settings.hotkey_modifiers = old_modifiers;
                settings.hotkey_key = old_key;
                if old_enabled && hud.register_hotkey(old_modifiers, old_key).is_err() {
                    settings.hotkey_enabled = false;
                    settings.hotkey_modifiers = 0;
                    settings.hotkey_key = 0;
                    let _ = save_settings(repository, settings);
                    HotkeyApplyResult::RestoreFailed
                } else {
                    HotkeyApplyResult::PersistenceFailed
                }
            }
        }
        Err(error) => {
            if old_enabled {
                if let Err(restore_error) = hud.register_hotkey(old_modifiers, old_key) {
                    settings.hotkey_enabled = false;
                    settings.hotkey_modifiers = 0;
                    settings.hotkey_key = 0;
                    let _ = save_settings(repository, settings);
                    if let Ok(diagnostics) = Diagnostics::native() {
                        diagnostics.record_platform(&restore_error);
                    }
                    return HotkeyApplyResult::RestoreFailed;
                }
            }
            if let Ok(diagnostics) = Diagnostics::native() {
                diagnostics.record_platform(&error);
            }
            HotkeyApplyResult::RegistrationFailed
        }
    }
}

fn run() -> Result<(), Box<dyn std::error::Error>> {
    let _apartment = RuntimeApartment::new()?;
    let _app_guard = AppGuard::acquire()?;
    let paths = StoragePaths::native()?;
    let settings_repository = SettingsRepository::new(paths.settings.clone());
    let mut settings = normalize_settings(settings_repository.load()?);
    let mut repository = TaskRepository::new(paths.todos.clone());
    repository.load()?;

    let (events_sender, events_receiver) = mpsc::channel::<PlatformEvent>();
    let settings_sender = events_sender.clone();
    let mut hud = HudWindow::new(
        settings.mode,
        settings.placement.logical_width.round() as i32,
        settings.placement.logical_height.round() as i32,
        events_sender,
    )?;
    let message_window = MessageWindow::new(settings_sender.clone())?;
    let mut settings_window: Option<SettingsWindow> = None;
    let _ = hud.restore_placement(&settings.placement);
    let initial_rect = hud.pixel_rect()?;
    let mut surface = HudSurface::new(
        (initial_rect.right - initial_rect.left).max(1),
        (initial_rect.bottom - initial_rect.top).max(1),
    )?;
    hud.set_topmost(settings.topmost)?;
    if settings.hotkey_enabled {
        if let Err(error) = hud.register_hotkey(settings.hotkey_modifiers, settings.hotkey_key) {
            eprintln!("hotkey registration failed: {error}");
            if let Ok(diagnostics) = Diagnostics::native() {
                diagnostics.record_platform(&error);
            }
            settings.hotkey_enabled = false;
            settings.hotkey_modifiers = 0;
            settings.hotkey_key = 0;
            let _ = save_settings(&settings_repository, &settings);
        }
    }
    hud.add_tray_icon()?;
    if settings.visible {
        hud.show();
    } else {
        hud.hide();
    }
    redraw(&mut surface, &hud, &repository, &settings)?;

    let (_watcher, changes) = DirectoryWatcher::start(paths.root.clone())?;
    let mut advance = AdvanceService::default();
    let mut running = true;
    let mut hotkey_status: Option<&'static str> = None;
    let mut own_write_snapshot = None;
    while running {
        if pump_messages(settings_window.as_ref().map(SettingsWindow::hwnd)) {
            break;
        }
        while let Ok(event) = events_receiver.try_recv() {
            match event {
                PlatformEvent::ToggleVisibility => {
                    settings.visible = !settings.visible;
                    if settings.visible {
                        hud.show();
                    } else {
                        hud.hide();
                    }
                    save_settings(&settings_repository, &settings);
                    if settings.visible {
                        redraw_safe(&mut surface, &hud, &repository, &settings);
                    }
                    if let Some(window) = settings_window.as_ref() {
                        window.sync(&settings);
                    }
                }
                PlatformEvent::ToggleMode => {
                    let mode = if settings.mode == ghostpin_native::core::HudMode::Passthrough {
                        ghostpin_native::core::HudMode::Interactive
                    } else {
                        ghostpin_native::core::HudMode::Passthrough
                    };
                    if let Err(error) = hud.set_mode(mode) {
                        record_runtime_error("platform", &error);
                    } else {
                        settings.mode = mode;
                        save_settings(&settings_repository, &settings);
                    }
                    if let Some(window) = settings_window.as_ref() {
                        window.sync(&settings);
                    }
                }
                PlatformEvent::Advance(id) if !id.is_empty() => {
                    match repository.load_for_update() {
                        Ok(_) => {
                            let mut items = repository.snapshot().to_vec();
                            if advance
                                .advance_by_id(&mut items, &id, SystemTime::now())
                                .is_some()
                            {
                                if let Err(error) = repository.replace(&items) {
                                    record_runtime_error("storage", &error);
                                } else {
                                    own_write_snapshot = Some(repository.snapshot().to_vec());
                                    redraw_safe(&mut surface, &hud, &repository, &settings);
                                }
                            }
                        }
                        Err(error) => record_runtime_error("storage", &error),
                    }
                }
                PlatformEvent::GeometryChanged => {
                    if let Ok(placement) = hud.capture_placement() {
                        settings.placement = normalize_settings(HudSettings {
                            placement,
                            ..settings.clone()
                        })
                        .placement;
                        save_settings(&settings_repository, &settings);
                    }
                }
                PlatformEvent::Resized { .. } => match hud.pixel_rect() {
                    Ok(rect) => {
                        let width = rect.right - rect.left;
                        let height = rect.bottom - rect.top;
                        if width <= 0 || height <= 0 {
                            continue;
                        }
                        if let Err(error) = surface.resize(width, height) {
                            record_runtime_error("render", &error);
                        } else {
                            redraw_safe(&mut surface, &hud, &repository, &settings);
                        }
                    }
                    Err(error) => {
                        record_runtime_error("platform", &error);
                    }
                },
                PlatformEvent::DpiChanged { .. } => {
                    if let Ok(placement) = hud.capture_placement() {
                        settings.placement = placement;
                        save_settings(&settings_repository, &settings);
                    }
                }
                PlatformEvent::TaskbarCreated => {
                    if let Err(error) = hud.add_tray_icon() {
                        if let Ok(diagnostics) = Diagnostics::native() {
                            diagnostics.record_platform(&error);
                        }
                    }
                }
                PlatformEvent::FilesChanged => {
                    let previous = repository.snapshot().to_vec();
                    match repository.load() {
                        Ok(_) => {
                            let own_write_pending = own_write_snapshot
                                .as_ref()
                                .is_some_and(|expected| expected == repository.snapshot());
                            if should_redraw_after_reload(
                                previous.as_slice(),
                                repository.snapshot(),
                                own_write_pending,
                            ) {
                                redraw_safe(&mut surface, &hud, &repository, &settings);
                            }
                            if !own_write_pending {
                                own_write_snapshot = None;
                            }
                        }
                        Err(error) => record_runtime_error("storage", &error),
                    }
                }
                PlatformEvent::ShowTrayMenu => {
                    if let Err(error) = hud.show_tray_menu() {
                        if let Ok(diagnostics) = Diagnostics::native() {
                            diagnostics.record("tray", &error.to_string());
                        }
                    }
                }
                PlatformEvent::OpenSettings => {
                    if settings_window.is_none() {
                        match SettingsWindow::new(settings_sender.clone(), &settings) {
                            Ok(window) => settings_window = Some(window),
                            Err(error) => record_runtime_error("settings", &error),
                        }
                    }
                    if let Some(window) = settings_window.as_ref() {
                        window.sync(&settings);
                        window.show();
                    }
                }
                PlatformEvent::Settings(change) => {
                    match change {
                        SettingsChange::ToggleVisibility => {
                            settings.visible = !settings.visible;
                            if settings.visible {
                                hud.show();
                            } else {
                                hud.hide();
                            }
                            save_settings(&settings_repository, &settings);
                            if settings.visible {
                                redraw_safe(&mut surface, &hud, &repository, &settings);
                            }
                        }
                        SettingsChange::ToggleTopmost => {
                            let topmost = !settings.topmost;
                            if let Err(error) = hud.set_topmost(topmost) {
                                record_runtime_error("platform", &error);
                            } else {
                                settings.topmost = topmost;
                                save_settings(&settings_repository, &settings);
                            }
                        }
                        SettingsChange::ToggleMode => {
                            let mode =
                                if settings.mode == ghostpin_native::core::HudMode::Passthrough {
                                    ghostpin_native::core::HudMode::Interactive
                                } else {
                                    ghostpin_native::core::HudMode::Passthrough
                                };
                            if let Err(error) = hud.set_mode(mode) {
                                record_runtime_error("platform", &error);
                            } else {
                                settings.mode = mode;
                                save_settings(&settings_repository, &settings);
                            }
                        }
                        SettingsChange::ScopeAll => {
                            settings.scope = ghostpin_native::core::HudScope::All;
                            save_settings(&settings_repository, &settings);
                            redraw_safe(&mut surface, &hud, &repository, &settings);
                        }
                        SettingsChange::ScopeToday => {
                            settings.scope = ghostpin_native::core::HudScope::Today;
                            save_settings(&settings_repository, &settings);
                            redraw_safe(&mut surface, &hud, &repository, &settings);
                        }
                        SettingsChange::SetOpacity(percent) => {
                            settings.opacity = f64::from(percent.clamp(50, 100)) / 100.0;
                            save_settings(&settings_repository, &settings);
                            redraw_safe(&mut surface, &hud, &repository, &settings);
                        }
                        SettingsChange::SetMaxItems(max_items) => {
                            settings.max_items = max_items.clamp(1, 20);
                            save_settings(&settings_repository, &settings);
                            redraw_safe(&mut surface, &hud, &repository, &settings);
                        }
                        SettingsChange::SetHotkey { modifiers, key } => {
                            hotkey_status = Some(hotkey_result_message(apply_hotkey_candidate(
                                &hud,
                                &mut settings,
                                &settings_repository,
                                modifiers,
                                key,
                            )));
                        }
                        SettingsChange::UseDefaultHotkey => {
                            hotkey_status = Some(hotkey_result_message(apply_hotkey_candidate(
                                &hud,
                                &mut settings,
                                &settings_repository,
                                HOTKEY_CONTROL | HOTKEY_ALT,
                                0x47,
                            )));
                        }
                        SettingsChange::ClearHotkey => {
                            let old_settings = settings.clone();
                            hud.unregister_hotkey();
                            settings.hotkey_enabled = false;
                            settings.hotkey_modifiers = 0;
                            settings.hotkey_key = 0;
                            if save_settings(&settings_repository, &settings) {
                                hotkey_status = Some("快捷键已清除");
                            } else {
                                settings = old_settings;
                                if settings.hotkey_enabled {
                                    if let Err(error) = hud.register_hotkey(
                                        settings.hotkey_modifiers,
                                        settings.hotkey_key,
                                    ) {
                                        record_runtime_error("platform", &error);
                                        settings.hotkey_enabled = false;
                                        settings.hotkey_modifiers = 0;
                                        settings.hotkey_key = 0;
                                        let _ = save_settings(&settings_repository, &settings);
                                        hotkey_status = Some(hotkey_result_message(
                                            HotkeyApplyResult::RestoreFailed,
                                        ));
                                    } else {
                                        hotkey_status = Some(hotkey_result_message(
                                            HotkeyApplyResult::PersistenceFailed,
                                        ));
                                    }
                                } else {
                                    hotkey_status = Some(hotkey_result_message(
                                        HotkeyApplyResult::PersistenceFailed,
                                    ));
                                }
                            }
                        }
                    }
                    if let Some(window) = settings_window.as_ref() {
                        window.sync(&settings);
                        if let Some(status) = hotkey_status.take() {
                            window.set_hotkey_status(status);
                        }
                    }
                }
                PlatformEvent::Exit => running = false,
                PlatformEvent::Advance(_) => {}
            }
        }
        while let Ok(event) = changes.try_recv() {
            match event {
                WatcherEvent::Changes(_) | WatcherEvent::Overflow => {
                    if let Err(error) = message_window.notify_file_change() {
                        record_runtime_error("platform", &error);
                    }
                }
                WatcherEvent::Error(message) => {
                    if let Ok(diagnostics) = Diagnostics::native() {
                        diagnostics.record("watcher", &message);
                    }
                }
            }
        }
        // SAFETY: yielding the UI thread does not borrow any Rust state.
        unsafe {
            Sleep(16);
        }
    }
    Ok(())
}

fn main() {
    if let Err(error) = run() {
        if let Ok(diagnostics) = Diagnostics::native() {
            diagnostics.record("startup", &error.to_string());
            diagnostics.show_error("GhostPin Native", &error.to_string());
        }
    }
}
