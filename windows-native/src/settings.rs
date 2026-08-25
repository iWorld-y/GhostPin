use std::{
    cell::{Cell, RefCell},
    marker::PhantomData,
    rc::Rc,
    sync::mpsc::Sender,
};

use windows::{
    Win32::{
        Foundation::{HINSTANCE, HWND, LPARAM, LRESULT, WPARAM},
        Graphics::Gdi::{COLOR_WINDOW, HBRUSH},
        System::LibraryLoader::GetModuleHandleW,
        UI::{
            Controls::{BST_CHECKED, BST_UNCHECKED},
            Input::KeyboardAndMouse::{
                GetKeyState, SetFocus, VK_CONTROL, VK_ESCAPE, VK_LWIN, VK_MENU, VK_RWIN, VK_SHIFT,
            },
            WindowsAndMessaging::{
                BS_AUTOCHECKBOX, BS_AUTORADIOBUTTON, BS_PUSHBUTTON, CREATESTRUCTW, CW_USEDEFAULT,
                CreateWindowExW, DefWindowProcW, DestroyWindow, GWLP_USERDATA, GetWindowLongPtrW,
                RegisterClassW, SW_HIDE, SW_SHOW, SendMessageW, SetForegroundWindow,
                SetWindowLongPtrW, SetWindowTextW, ShowWindow, WINDOW_STYLE, WM_CLOSE, WM_COMMAND,
                WM_CREATE, WM_KEYDOWN, WM_NCCREATE, WM_NCDESTROY, WM_SYSKEYDOWN, WNDCLASSW,
                WS_CAPTION, WS_CHILD, WS_CLIPCHILDREN, WS_EX_CLIENTEDGE, WS_EX_TOOLWINDOW,
                WS_GROUP, WS_OVERLAPPED, WS_SYSMENU, WS_TABSTOP, WS_VISIBLE,
            },
        },
    },
    core::{Error as WindowsError, w},
};

use crate::core::{HudSettings, normalize_hotkey};
use crate::platform::{PlatformEvent, SettingsChange};

const ID_TAB_HUD: u16 = 2100;
const ID_TAB_ADVANCED: u16 = 2101;
const ID_VISIBLE: u16 = 2110;
const ID_TOPMOST: u16 = 2111;
const ID_MODE: u16 = 2112;
const ID_SCOPE_ALL: u16 = 2113;
const ID_SCOPE_TODAY: u16 = 2114;
const ID_OPACITY_50: u16 = 2115;
const ID_OPACITY_75: u16 = 2116;
const ID_OPACITY_100: u16 = 2117;
const ID_MAX_4: u16 = 2118;
const ID_MAX_8: u16 = 2119;
const ID_MAX_12: u16 = 2120;
const ID_DEFAULT_HOTKEY: u16 = 2121;
const ID_CLEAR_HOTKEY: u16 = 2122;
const ID_RECORD_HOTKEY: u16 = 2123;

struct Controls {
    tab_hud: HWND,
    tab_advanced: HWND,
    visible: HWND,
    topmost: HWND,
    mode: HWND,
    scope_all: HWND,
    scope_today: HWND,
    opacity_50: HWND,
    opacity_75: HWND,
    opacity_100: HWND,
    max_4: HWND,
    max_8: HWND,
    max_12: HWND,
    default_hotkey: HWND,
    clear_hotkey: HWND,
    record_hotkey: HWND,
    hotkey_status: HWND,
    hud_page: Vec<HWND>,
    advanced_page: Vec<HWND>,
    advanced_active: Cell<bool>,
    recording: Cell<bool>,
}

struct SettingsState {
    sender: Sender<PlatformEvent>,
    controls: RefCell<Option<Controls>>,
    _thread_affine: PhantomData<Rc<()>>,
}

unsafe fn state_ptr(hwnd: HWND) -> Option<*mut SettingsState> {
    // SAFETY: the pointer is installed by WM_NCCREATE and remains owned by SettingsWindow.
    let value = unsafe { GetWindowLongPtrW(hwnd, GWLP_USERDATA) };
    (value != 0).then_some(value as *mut SettingsState)
}
fn loword(value: usize) -> u16 {
    (value & 0xffff) as u16
}
fn current_modifiers() -> u32 {
    let mut modifiers = 0;
    // SAFETY: GetKeyState reads the current thread input state and has no pointer arguments.
    unsafe {
        if GetKeyState(VK_MENU.0 as i32) < 0 {
            modifiers |= crate::core::HOTKEY_ALT;
        }
        if GetKeyState(VK_CONTROL.0 as i32) < 0 {
            modifiers |= crate::core::HOTKEY_CONTROL;
        }
        if GetKeyState(VK_SHIFT.0 as i32) < 0 {
            modifiers |= crate::core::HOTKEY_SHIFT;
        }
        if GetKeyState(VK_LWIN.0 as i32) < 0 || GetKeyState(VK_RWIN.0 as i32) < 0 {
            modifiers |= crate::core::HOTKEY_WIN;
        }
    }
    modifiers
}
fn set_text(hwnd: HWND, text: &str) {
    let wide = text
        .encode_utf16()
        .chain(std::iter::once(0))
        .collect::<Vec<_>>();
    // SAFETY: SetWindowTextW copies the temporary NUL-terminated string synchronously.
    unsafe {
        let _ = SetWindowTextW(hwnd, windows::core::PCWSTR(wide.as_ptr()));
    }
}
unsafe extern "system" fn settings_proc(
    hwnd: HWND,
    message: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    if message == WM_NCCREATE {
        // SAFETY: WM_NCCREATE supplies a valid CREATESTRUCTW for this window.
        let create = unsafe { &*(lparam.0 as *const CREATESTRUCTW) };
        // SAFETY: the pointer is a stable borrow into the owner Box until WM_NCDESTROY.
        unsafe {
            SetWindowLongPtrW(hwnd, GWLP_USERDATA, create.lpCreateParams as isize);
        }
        return LRESULT(1);
    }
    // SAFETY: the owner keeps SettingsState alive for the whole HWND lifetime.
    let state = unsafe { state_ptr(hwnd) }.map(|ptr| unsafe { &*ptr });
    if let Some(state) = state {
        match message {
            WM_CREATE => {
                return if create_controls(hwnd, state) {
                    LRESULT(0)
                } else {
                    LRESULT(-1)
                };
            }
            WM_COMMAND => {
                match loword(wparam.0) {
                    ID_TAB_HUD => {
                        if let Some(controls) = state.controls.borrow().as_ref() {
                            show_page(controls, false);
                        }
                    }
                    ID_TAB_ADVANCED => {
                        if let Some(controls) = state.controls.borrow().as_ref() {
                            show_page(controls, true);
                        }
                    }
                    ID_VISIBLE => send(
                        state,
                        PlatformEvent::Settings(SettingsChange::ToggleVisibility),
                    ),
                    ID_TOPMOST => send(
                        state,
                        PlatformEvent::Settings(SettingsChange::ToggleTopmost),
                    ),
                    ID_MODE => send(state, PlatformEvent::Settings(SettingsChange::ToggleMode)),
                    ID_SCOPE_ALL => send(state, PlatformEvent::Settings(SettingsChange::ScopeAll)),
                    ID_SCOPE_TODAY => {
                        send(state, PlatformEvent::Settings(SettingsChange::ScopeToday))
                    }
                    ID_OPACITY_50 => send(
                        state,
                        PlatformEvent::Settings(SettingsChange::SetOpacity(50)),
                    ),
                    ID_OPACITY_75 => send(
                        state,
                        PlatformEvent::Settings(SettingsChange::SetOpacity(75)),
                    ),
                    ID_OPACITY_100 => send(
                        state,
                        PlatformEvent::Settings(SettingsChange::SetOpacity(100)),
                    ),
                    ID_MAX_4 => send(
                        state,
                        PlatformEvent::Settings(SettingsChange::SetMaxItems(4)),
                    ),
                    ID_MAX_8 => send(
                        state,
                        PlatformEvent::Settings(SettingsChange::SetMaxItems(8)),
                    ),
                    ID_MAX_12 => send(
                        state,
                        PlatformEvent::Settings(SettingsChange::SetMaxItems(12)),
                    ),
                    ID_DEFAULT_HOTKEY => send(
                        state,
                        PlatformEvent::Settings(SettingsChange::UseDefaultHotkey),
                    ),
                    ID_RECORD_HOTKEY => {
                        if let Some(controls) = state.controls.borrow().as_ref() {
                            controls.recording.set(true);
                            set_text(controls.record_hotkey, "按下快捷键（Esc 取消）");
                            set_text(controls.hotkey_status, "录制中：普通键需包含修饰键");
                            // SAFETY: the settings window is the active owner of the recording UI.
                            unsafe {
                                let _ = SetFocus(Some(hwnd));
                            }
                        }
                    }
                    ID_CLEAR_HOTKEY => {
                        send(state, PlatformEvent::Settings(SettingsChange::ClearHotkey))
                    }
                    _ => {}
                }
                return LRESULT(0);
            }
            WM_KEYDOWN | WM_SYSKEYDOWN => {
                if let Some(controls) = state.controls.borrow().as_ref() {
                    if controls.recording.get() {
                        let key = wparam.0 as u32;
                        if key == VK_ESCAPE.0 as u32 {
                            controls.recording.set(false);
                            set_text(controls.record_hotkey, "录制快捷键");
                            set_text(controls.hotkey_status, "录制已取消");
                        } else {
                            let modifiers = current_modifiers();
                            if let Some(candidate) = normalize_hotkey(modifiers, key) {
                                controls.recording.set(false);
                                set_text(controls.record_hotkey, "录制快捷键");
                                send(
                                    state,
                                    PlatformEvent::Settings(SettingsChange::SetHotkey {
                                        modifiers: candidate.modifiers,
                                        key: candidate.key,
                                    }),
                                );
                            } else {
                                set_text(
                                    controls.hotkey_status,
                                    "无效组合：需要修饰键+普通键，或单独 F1-F20",
                                );
                            }
                        }
                        return LRESULT(0);
                    }
                }
            }
            WM_CLOSE => {
                // SAFETY: hiding preserves the single settings window instance.
                unsafe {
                    let _ = ShowWindow(hwnd, SW_HIDE);
                }
                return LRESULT(0);
            }
            _ => {}
        }
    }
    if message == WM_NCDESTROY {
        // SAFETY: clear the borrowed pointer; SettingsWindow owns and drops the Box later.
        unsafe {
            SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
        }
    }
    // SAFETY: unhandled settings messages are delegated to the system procedure.
    unsafe { DefWindowProcW(hwnd, message, wparam, lparam) }
}
fn send(state: &SettingsState, event: PlatformEvent) {
    let _ = state.sender.send(event);
}
fn control(
    parent: HWND,
    class: windows::core::PCWSTR,
    title: windows::core::PCWSTR,
    id: u16,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    button_style: u32,
) -> HWND {
    let style = WS_CHILD | WS_VISIBLE | WS_TABSTOP | WINDOW_STYLE(button_style);
    // SAFETY: all strings are static and the parent HWND is valid during WM_CREATE.
    unsafe {
        CreateWindowExW(
            WS_EX_CLIENTEDGE,
            class,
            title,
            style,
            x,
            y,
            width,
            height,
            Some(parent),
            Some(windows::Win32::UI::WindowsAndMessaging::HMENU(
                id as usize as _,
            )),
            None,
            None,
        )
        .unwrap_or_default()
    }
}

fn label(parent: HWND, title: windows::core::PCWSTR, x: i32, y: i32, width: i32) -> HWND {
    let style = WS_CHILD | WS_VISIBLE;
    // SAFETY: the static label and parent HWND remain valid for this synchronous creation.
    unsafe {
        CreateWindowExW(
            windows::Win32::UI::WindowsAndMessaging::WINDOW_EX_STYLE(0),
            w!("STATIC"),
            title,
            style,
            x,
            y,
            width,
            24,
            Some(parent),
            None,
            None,
            None,
        )
        .unwrap_or_default()
    }
}

fn create_controls(hwnd: HWND, state: &SettingsState) -> bool {
    let tab_hud = control(
        hwnd,
        w!("BUTTON"),
        w!("HUD"),
        ID_TAB_HUD,
        16,
        14,
        170,
        30,
        BS_PUSHBUTTON as u32,
    );
    let tab_advanced = control(
        hwnd,
        w!("BUTTON"),
        w!("高级"),
        ID_TAB_ADVANCED,
        194,
        14,
        170,
        30,
        BS_PUSHBUTTON as u32,
    );
    let mut hud_page = vec![label(hwnd, w!("HUD 外观与任务范围"), 24, 54, 340)];
    let visible = control(
        hwnd,
        w!("BUTTON"),
        w!("显示 HUD"),
        ID_VISIBLE,
        24,
        82,
        160,
        28,
        BS_AUTOCHECKBOX as u32,
    );
    let topmost = control(
        hwnd,
        w!("BUTTON"),
        w!("保持置顶"),
        ID_TOPMOST,
        200,
        82,
        160,
        28,
        BS_AUTOCHECKBOX as u32,
    );
    let mode = control(
        hwnd,
        w!("BUTTON"),
        w!("交互模式"),
        ID_MODE,
        24,
        118,
        160,
        28,
        BS_AUTOCHECKBOX as u32,
    );
    let scope_all = control(
        hwnd,
        w!("BUTTON"),
        w!("全部任务"),
        ID_SCOPE_ALL,
        200,
        118,
        160,
        28,
        BS_AUTORADIOBUTTON as u32 | WS_GROUP.0,
    );
    let scope_today = control(
        hwnd,
        w!("BUTTON"),
        w!("今天任务"),
        ID_SCOPE_TODAY,
        200,
        154,
        160,
        28,
        BS_AUTORADIOBUTTON as u32,
    );
    let opacity_label = label(hwnd, w!("透明度"), 24, 154, 160);
    let opacity_50 = control(
        hwnd,
        w!("BUTTON"),
        w!("50%"),
        ID_OPACITY_50,
        24,
        182,
        100,
        28,
        BS_AUTORADIOBUTTON as u32 | WS_GROUP.0,
    );
    let opacity_75 = control(
        hwnd,
        w!("BUTTON"),
        w!("75%"),
        ID_OPACITY_75,
        134,
        182,
        100,
        28,
        BS_AUTORADIOBUTTON as u32,
    );
    let opacity_100 = control(
        hwnd,
        w!("BUTTON"),
        w!("100%"),
        ID_OPACITY_100,
        244,
        182,
        100,
        28,
        BS_AUTORADIOBUTTON as u32,
    );
    let max_label = label(hwnd, w!("最多显示任务数"), 24, 218, 160);
    let max_4 = control(
        hwnd,
        w!("BUTTON"),
        w!("4"),
        ID_MAX_4,
        24,
        246,
        100,
        28,
        BS_AUTORADIOBUTTON as u32 | WS_GROUP.0,
    );
    let max_8 = control(
        hwnd,
        w!("BUTTON"),
        w!("8"),
        ID_MAX_8,
        134,
        246,
        100,
        28,
        BS_AUTORADIOBUTTON as u32,
    );
    let max_12 = control(
        hwnd,
        w!("BUTTON"),
        w!("12"),
        ID_MAX_12,
        244,
        246,
        100,
        28,
        BS_AUTORADIOBUTTON as u32,
    );
    hud_page.extend([
        visible,
        topmost,
        mode,
        scope_all,
        scope_today,
        opacity_label,
        opacity_50,
        opacity_75,
        opacity_100,
        max_label,
        max_4,
        max_8,
        max_12,
    ]);

    let mut advanced_page = vec![label(hwnd, w!("全局交互快捷键"), 24, 54, 340)];
    let default_hotkey = control(
        hwnd,
        w!("BUTTON"),
        w!("使用 Ctrl+Alt+G"),
        ID_DEFAULT_HOTKEY,
        24,
        92,
        160,
        28,
        BS_PUSHBUTTON as u32,
    );
    let clear_hotkey = control(
        hwnd,
        w!("BUTTON"),
        w!("清除快捷键"),
        ID_CLEAR_HOTKEY,
        200,
        92,
        160,
        28,
        BS_PUSHBUTTON as u32,
    );
    let record_hotkey = control(
        hwnd,
        w!("BUTTON"),
        w!("录制快捷键"),
        ID_RECORD_HOTKEY,
        24,
        128,
        160,
        28,
        BS_PUSHBUTTON as u32,
    );
    let hotkey_status = label(hwnd, w!("未启用快捷键"), 24, 166, 340);
    advanced_page.extend([default_hotkey, clear_hotkey, record_hotkey, hotkey_status]);
    let controls = Controls {
        tab_hud,
        tab_advanced,
        visible,
        topmost,
        mode,
        scope_all,
        scope_today,
        opacity_50,
        opacity_75,
        opacity_100,
        max_4,
        max_8,
        max_12,
        default_hotkey,
        clear_hotkey,
        record_hotkey,
        hotkey_status,
        hud_page,
        advanced_page,
        advanced_active: Cell::new(false),
        recording: Cell::new(false),
    };
    let valid = [
        controls.tab_hud,
        controls.tab_advanced,
        controls.visible,
        controls.topmost,
        controls.mode,
        controls.scope_all,
        controls.scope_today,
        controls.opacity_50,
        controls.opacity_75,
        controls.opacity_100,
        controls.max_4,
        controls.max_8,
        controls.max_12,
        controls.default_hotkey,
        controls.clear_hotkey,
        controls.record_hotkey,
        controls.hotkey_status,
    ]
    .into_iter()
    .all(|control| !control.0.is_null());
    if valid {
        show_page(&controls, false);
        *state.controls.borrow_mut() = Some(controls);
    }
    valid
}

fn show_page(controls: &Controls, advanced: bool) {
    controls.advanced_active.set(advanced);
    let hud_visibility = if advanced { SW_HIDE } else { SW_SHOW };
    let advanced_visibility = if advanced { SW_SHOW } else { SW_HIDE };
    for hwnd in &controls.hud_page {
        // SAFETY: these child HWNDs are owned by the settings window.
        unsafe {
            let _ = ShowWindow(*hwnd, hud_visibility);
        }
    }
    for hwnd in &controls.advanced_page {
        // SAFETY: these child HWNDs are owned by the settings window.
        unsafe {
            let _ = ShowWindow(*hwnd, advanced_visibility);
        }
    }
}

fn set_check(hwnd: HWND, checked: bool) {
    let state = if checked {
        BST_CHECKED.0
    } else {
        BST_UNCHECKED.0
    };
    // SAFETY: the control HWND belongs to this settings window and the message has no pointer payload.
    unsafe {
        let _ = SendMessageW(
            hwnd,
            windows::Win32::UI::WindowsAndMessaging::BM_SETCHECK,
            Some(WPARAM(state as usize)),
            None,
        );
    }
}

pub struct SettingsWindow {
    hwnd: HWND,
    _state: Box<SettingsState>,
    _thread_affine: PhantomData<Rc<()>>,
}
impl SettingsWindow {
    pub fn new(sender: Sender<PlatformEvent>, settings: &HudSettings) -> Result<Self, String> {
        // SAFETY: the module handle is queried for the current process only.
        let instance = unsafe { GetModuleHandleW(None) }.map_err(|e| e.message().to_string())?;
        let instance = HINSTANCE(instance.0);
        let class_name = w!("GhostPin.Native.Rust.Settings");
        let class = WNDCLASSW {
            lpfnWndProc: Some(settings_proc),
            hInstance: instance,
            lpszClassName: class_name,
            hbrBackground: HBRUSH((COLOR_WINDOW.0 + 1) as *mut std::ffi::c_void),
            ..Default::default()
        };
        // SAFETY: the class structure and static class name are valid for this call.
        let atom = unsafe { RegisterClassW(&class) };
        if atom == 0 {
            let error = WindowsError::from_win32();
            if error.code().0 != 1410 {
                return Err(error.message().to_string());
            }
        }
        let state = Box::new(SettingsState {
            sender,
            controls: RefCell::new(None),
            _thread_affine: PhantomData,
        });
        let state_ptr = (&*state as *const SettingsState).cast_mut();
        // SAFETY: state_ptr remains valid because the returned owner stores state.
        let hwnd = unsafe {
            CreateWindowExW(
                WS_EX_TOOLWINDOW,
                class_name,
                w!("GhostPin 设置"),
                WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_CLIPCHILDREN,
                CW_USEDEFAULT,
                CW_USEDEFAULT,
                420,
                320,
                None,
                None,
                Some(instance),
                Some(state_ptr.cast()),
            )
        }
        .map_err(|e| e.message().to_string())?;
        let window = Self {
            hwnd,
            _state: state,
            _thread_affine: PhantomData,
        };
        window.sync(settings);
        Ok(window)
    }
    pub fn hwnd(&self) -> HWND {
        self.hwnd
    }
    pub fn show(&self) {
        // SAFETY: settings HWND belongs to this UI thread.
        unsafe {
            let _ = ShowWindow(self.hwnd, SW_SHOW);
            let _ = SetForegroundWindow(self.hwnd);
        }
    }
    pub fn sync(&self, settings: &HudSettings) {
        // SAFETY: SettingsWindow is confined to the UI thread that owns this HWND.
        let Some(state) = (unsafe { state_ptr(self.hwnd) }).map(|ptr| unsafe { &*ptr }) else {
            return;
        };
        let controls_ref = state.controls.borrow();
        let Some(controls) = controls_ref.as_ref() else {
            return;
        };
        set_check(controls.visible, settings.visible);
        set_check(controls.topmost, settings.topmost);
        set_check(
            controls.mode,
            settings.mode == crate::core::HudMode::Interactive,
        );
        set_check(
            controls.scope_all,
            settings.scope == crate::core::HudScope::All,
        );
        set_check(
            controls.scope_today,
            settings.scope == crate::core::HudScope::Today,
        );
        set_check(
            controls.opacity_50,
            (settings.opacity - 0.5).abs() < f64::EPSILON,
        );
        set_check(
            controls.opacity_75,
            (settings.opacity - 0.75).abs() < f64::EPSILON,
        );
        set_check(controls.opacity_100, settings.opacity >= 0.999);
        set_check(controls.max_4, settings.max_items == 4);
        set_check(controls.max_8, settings.max_items == 8);
        set_check(controls.max_12, settings.max_items == 12);
        set_text(
            controls.hotkey_status,
            if settings.hotkey_enabled {
                "当前快捷键已启用（可重新录制）"
            } else {
                "未启用快捷键"
            },
        );
    }
}
impl SettingsWindow {
    pub fn set_hotkey_status(&self, status: &str) {
        // SAFETY: SettingsWindow is confined to the UI thread that owns this HWND.
        let Some(state) = (unsafe { state_ptr(self.hwnd) }).map(|ptr| unsafe { &*ptr }) else {
            return;
        };
        if let Some(controls) = state.controls.borrow().as_ref() {
            set_text(controls.hotkey_status, status);
        }
    }
}
impl Drop for SettingsWindow {
    fn drop(&mut self) {
        if !self.hwnd.0.is_null() {
            // SAFETY: window is owned by this UI thread.
            unsafe {
                let _ = DestroyWindow(self.hwnd);
            }
        }
    }
}
