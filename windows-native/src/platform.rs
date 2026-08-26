use std::{
    cell::{Cell, RefCell},
    fmt,
    marker::PhantomData,
    rc::Rc,
    sync::mpsc::Sender,
};

use windows::{
    Win32::{
        Foundation::{HINSTANCE, HWND, LPARAM, LRESULT, POINT, RECT, WPARAM},
        Graphics::Gdi::{
            EnumDisplayMonitors, GetMonitorInfoW, HMONITOR, MONITOR_DEFAULTTONEAREST,
            MONITOR_DEFAULTTOPRIMARY, MONITORINFO, MONITORINFOEXW, MonitorFromPoint,
            MonitorFromWindow, ScreenToClient, UpdateWindow,
        },
        System::LibraryLoader::GetModuleHandleW,
        UI::{
            HiDpi::{GetDpiForMonitor, GetDpiForWindow, MDT_EFFECTIVE_DPI},
            Input::KeyboardAndMouse::{HOT_KEY_MODIFIERS, RegisterHotKey, UnregisterHotKey},
            Shell::{
                NIF_ICON, NIF_MESSAGE, NIF_TIP, NIM_ADD, NIM_DELETE, NIM_SETVERSION,
                NOTIFYICONDATAW, Shell_NotifyIconW,
            },
            WindowsAndMessaging::{
                AppendMenuW, CREATESTRUCTW, CW_USEDEFAULT, CreatePopupMenu, CreateWindowExW,
                DefWindowProcW, DestroyMenu, DestroyWindow, DispatchMessageW, GWLP_USERDATA,
                GetClientRect, GetCursorPos, GetWindowLongPtrW, GetWindowRect, HICON, HTBOTTOM,
                HTBOTTOMLEFT, HTBOTTOMRIGHT, HTCAPTION, HTCLIENT, HTLEFT, HTRIGHT, HTTOP,
                HTTOPLEFT, HTTOPRIGHT, HWND_MESSAGE, HWND_NOTOPMOST, HWND_TOPMOST, IsWindowVisible,
                LoadIconW, MF_CHECKED, MF_SEPARATOR, MF_STRING, MSG, PM_REMOVE, PostMessageW,
                RegisterClassW, RegisterWindowMessageW, SW_HIDE, SW_SHOWNOACTIVATE,
                SWP_FRAMECHANGED, SWP_NOACTIVATE, SWP_NOMOVE, SWP_NOSIZE, SWP_NOZORDER,
                SetForegroundWindow, SetTimer, SetWindowLongPtrW, SetWindowPos, ShowWindow,
                TPM_BOTTOMALIGN, TPM_RIGHTBUTTON, TrackPopupMenu, TranslateMessage,
                WINDOW_EX_STYLE, WINDOW_LONG_PTR_INDEX, WM_APP, WM_CLOSE, WM_COMMAND,
                WM_CONTEXTMENU, WM_DPICHANGED, WM_EXITSIZEMOVE, WM_GETMINMAXINFO, WM_HOTKEY,
                WM_LBUTTONUP, WM_NCCALCSIZE, WM_NCCREATE, WM_NCDESTROY, WM_NCHITTEST, WM_NULL,
                WM_RBUTTONUP, WM_SIZE, WM_TIMER, WNDCLASSW, WS_EX_LAYERED, WS_EX_NOACTIVATE,
                WS_EX_TOOLWINDOW, WS_EX_TRANSPARENT, WS_OVERLAPPED, WS_POPUP, WS_THICKFRAME,
            },
        },
    },
    core::{Error as WindowsError, PCWSTR, w},
};

use crate::core::{HudMode, Placement};

const TRAY_ID: u32 = 1;
const HOTKEY_ID: i32 = 1;
const COMMAND_TOGGLE_VISIBILITY: u16 = 1001;
const COMMAND_TOGGLE_MODE: u16 = 1002;
const COMMAND_OPEN_SETTINGS: u16 = 1003;
const COMMAND_EXIT: u16 = 1004;
const TRAY_CALLBACK: u32 = WM_APP + 1;
const TRAY_NIN_KEYSELECT: u32 = 0x0401;
pub const FILE_CHANGE_MESSAGE: u32 = WM_APP + 2;
const FILE_CHANGE_TIMER: usize = 1;
const MIN_LOGICAL_WIDTH: f64 = 300.0;
const MIN_LOGICAL_HEIGHT: f64 = 280.0;

#[derive(Debug)]
pub struct PlatformError {
    pub operation: &'static str,
    pub code: Option<i32>,
    pub message: String,
}
impl fmt::Display for PlatformError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{}: {}", self.operation, self.message)
    }
}
impl std::error::Error for PlatformError {}
impl From<WindowsError> for PlatformError {
    fn from(error: WindowsError) -> Self {
        Self {
            operation: "Win32",
            code: Some(error.code().0),
            message: error.message().to_string(),
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum PlatformEvent {
    ToggleVisibility,
    ToggleMode,
    OpenSettings,
    Exit,
    Advance(String),
    GeometryChanged,
    Resized { width: i32, height: i32 },
    DpiChanged { dpi: u32 },
    TaskbarCreated,
    ShowTrayMenu,
    FilesChanged,
    Settings(SettingsChange),
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SettingsChange {
    ToggleVisibility,
    ToggleTopmost,
    ToggleMode,
    ScopeAll,
    ScopeToday,
    SetOpacity(u8),
    SetMaxItems(usize),
    SetHotkey { modifiers: u32, key: u32 },
    UseDefaultHotkey,
    ClearHotkey,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct HudStyle {
    pub ex_style: WINDOW_EX_STYLE,
}
impl HudStyle {
    pub fn for_mode(mode: HudMode) -> Self {
        let base = WS_EX_TOOLWINDOW | WS_EX_LAYERED;
        let ex_style = match mode {
            HudMode::Passthrough => base | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE,
            HudMode::Interactive => base,
        };
        Self { ex_style }
    }
}

#[derive(Clone, Debug)]
struct HitRegion {
    id: String,
    rect: RECT,
}

struct WindowState {
    mode: Cell<HudMode>,
    sender: Option<Sender<PlatformEvent>>,
    hit_regions: RefCell<Vec<HitRegion>>,
    taskbar_created: u32,
    _thread_affine: PhantomData<Rc<()>>,
}

fn loword(value: usize) -> u16 {
    (value & 0xffff) as u16
}
fn hiword(value: usize) -> u16 {
    ((value >> 16) & 0xffff) as u16
}
fn signed_low(value: isize) -> i32 {
    (value as i16) as i32
}
fn signed_high(value: isize) -> i32 {
    ((value >> 16) as i16) as i32
}

fn monitor_device_name(monitor: HMONITOR) -> Result<String, PlatformError> {
    let mut info = MONITORINFOEXW {
        monitorInfo: MONITORINFO {
            cbSize: std::mem::size_of::<MONITORINFOEXW>() as u32,
            ..Default::default()
        },
        ..Default::default()
    };
    // SAFETY: the monitor handle is supplied by the display enumeration APIs and info is initialized.
    unsafe {
        GetMonitorInfoW(monitor, (&mut info.monitorInfo as *mut MONITORINFO).cast())
            .ok()
            .map_err(PlatformError::from)?;
    }
    let length = info
        .szDevice
        .iter()
        .position(|value| *value == 0)
        .unwrap_or(info.szDevice.len());
    Ok(String::from_utf16_lossy(&info.szDevice[..length]))
}

struct MonitorSearch {
    wanted: String,
    found: Option<HMONITOR>,
}

unsafe extern "system" fn find_monitor_proc(
    monitor: HMONITOR,
    _dc: windows::Win32::Graphics::Gdi::HDC,
    _rect: *mut RECT,
    data: LPARAM,
) -> windows::core::BOOL {
    // SAFETY: EnumDisplayMonitors receives the pointer to this stack-owned search value.
    let search = unsafe { &mut *(data.0 as *mut MonitorSearch) };
    if let Ok(name) = monitor_device_name(monitor) {
        if name.eq_ignore_ascii_case(&search.wanted) {
            search.found = Some(monitor);
            return windows::core::BOOL(0);
        }
    }
    windows::core::BOOL(1)
}

fn find_monitor(device_name: &str) -> Option<HMONITOR> {
    if device_name.is_empty() {
        return None;
    }
    let mut search = MonitorSearch {
        wanted: device_name.to_owned(),
        found: None,
    };
    // SAFETY: the callback and search pointer remain valid for this synchronous enumeration.
    unsafe {
        let _ = EnumDisplayMonitors(
            None,
            None,
            Some(find_monitor_proc),
            LPARAM((&mut search as *mut MonitorSearch).cast::<()>() as isize),
        );
    }
    search.found
}

fn monitor_dpi(monitor: HMONITOR, fallback: u32) -> u32 {
    let mut dpi_x = 0;
    let mut dpi_y = 0;
    // SAFETY: monitor is a live display handle and the DPI outputs are valid pointers.
    if unsafe { GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &mut dpi_x, &mut dpi_y) }.is_ok() {
        dpi_x.max(96)
    } else {
        fallback.max(96)
    }
}

fn min_pixel_size(dpi: u32) -> (i32, i32) {
    let scale = dpi.max(96) as f64 / 96.0;
    (
        (MIN_LOGICAL_WIDTH * scale).round() as i32,
        (MIN_LOGICAL_HEIGHT * scale).round() as i32,
    )
}

fn placement_rect(placement: &Placement, info: &MONITORINFO, dpi: u32) -> RECT {
    let (min_width, min_height) = min_pixel_size(dpi);
    let scale = dpi.max(96) as f64 / 96.0;
    let work_width = (info.rcWork.right - info.rcWork.left).max(min_width);
    let work_height = (info.rcWork.bottom - info.rcWork.top).max(min_height);
    let width = (placement.logical_width * scale)
        .round()
        .clamp(min_width as f64, work_width as f64) as i32;
    let height = (placement.logical_height * scale)
        .round()
        .clamp(min_height as f64, work_height as f64) as i32;
    let x = info.rcWork.left + (placement.relative_x * scale).round() as i32;
    let y = info.rcWork.top + (placement.relative_y * scale).round() as i32;
    RECT {
        left: x,
        top: y,
        right: x.saturating_add(width),
        bottom: y.saturating_add(height),
    }
}

fn intersects(a: RECT, b: RECT) -> bool {
    a.left < b.right && a.right > b.left && a.top < b.bottom && a.bottom > b.top
}

fn clamp_to_work_area(mut rect: RECT, info: &MONITORINFO) -> RECT {
    let width = rect.right - rect.left;
    let height = rect.bottom - rect.top;
    rect.left = rect.left.clamp(info.rcWork.left, info.rcWork.right - width);
    rect.top = rect.top.clamp(info.rcWork.top, info.rcWork.bottom - height);
    rect.right = rect.left.saturating_add(width);
    rect.bottom = rect.top.saturating_add(height);
    rect
}

unsafe fn state_ptr(hwnd: HWND) -> Option<*mut WindowState> {
    let value = unsafe { GetWindowLongPtrW(hwnd, GWLP_USERDATA) };
    (value != 0).then_some(value as *mut WindowState)
}

fn send_event(state: &WindowState, event: PlatformEvent) {
    if let Some(sender) = &state.sender {
        let _ = sender.send(event);
    }
}

fn hit_test(state: &WindowState, hwnd: HWND, x: i32, y: i32) -> i32 {
    if state.mode.get() == HudMode::Passthrough {
        return windows::Win32::UI::WindowsAndMessaging::HTTRANSPARENT as i32;
    }
    let mut client = POINT { x, y };
    // SAFETY: client is a valid point and hwnd belongs to this UI thread.
    unsafe {
        let _ = ScreenToClient(hwnd, &mut client);
    }
    let mut bounds = RECT::default();
    // SAFETY: bounds is an out parameter for a live window.
    unsafe {
        let _ = GetClientRect(hwnd, &mut bounds);
    }
    let edge = 8;
    let left = client.x < bounds.left + edge;
    let right = client.x >= bounds.right - edge;
    let top = client.y < bounds.top + edge;
    let bottom = client.y >= bounds.bottom - edge;
    return match (left, right, top, bottom) {
        (true, false, true, false) => HTTOPLEFT as i32,
        (false, true, true, false) => HTTOPRIGHT as i32,
        (true, false, false, true) => HTBOTTOMLEFT as i32,
        (false, true, false, true) => HTBOTTOMRIGHT as i32,
        (true, false, false, false) => HTLEFT as i32,
        (false, true, false, false) => HTRIGHT as i32,
        (false, false, true, false) => HTTOP as i32,
        (false, false, false, true) => HTBOTTOM as i32,
        _ if state.hit_regions.borrow().iter().any(|region| {
            client.x >= region.rect.left
                && client.x < region.rect.right
                && client.y >= region.rect.top
                && client.y < region.rect.bottom
        }) =>
        {
            HTCLIENT as i32
        }
        _ => HTCAPTION as i32,
    };
}

unsafe extern "system" fn window_proc(
    hwnd: HWND,
    message: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    if message == WM_NCCREATE {
        // SAFETY: WM_NCCREATE supplies a valid CREATESTRUCTW for this window.
        let create = unsafe { &*(lparam.0 as *const CREATESTRUCTW) };
        // SAFETY: the value remains owned by the window until WM_NCDESTROY.
        unsafe {
            SetWindowLongPtrW(hwnd, GWLP_USERDATA, create.lpCreateParams as isize);
        }
        return LRESULT(1);
    }
    // SAFETY: user data is installed by WM_NCCREATE and is valid until WM_NCDESTROY.
    let state = unsafe { state_ptr(hwnd) }.map(|ptr| unsafe { &*ptr });
    if let Some(state) = state {
        if message == TRAY_CALLBACK {
            // NOTIFYICON_VERSION_4 packs the callback message in the low word;
            // the high word carries the icon identifier.
            match loword(lparam.0 as usize) as u32 {
                WM_LBUTTONUP => send_event(state, PlatformEvent::ToggleVisibility),
                WM_RBUTTONUP | WM_CONTEXTMENU => send_event(state, PlatformEvent::ShowTrayMenu),
                windows::Win32::UI::Shell::NIN_SELECT => {
                    send_event(state, PlatformEvent::ToggleVisibility)
                }
                TRAY_NIN_KEYSELECT => send_event(state, PlatformEvent::ShowTrayMenu),
                _ => {}
            }
            return LRESULT(0);
        }
        if message == WM_NCCALCSIZE {
            return LRESULT(0);
        }
        if message == FILE_CHANGE_MESSAGE {
            // SAFETY: the timer is owned by this message-only HWND and coalesces bursts of changes.
            unsafe {
                let _ = SetTimer(Some(hwnd), FILE_CHANGE_TIMER, 500, None);
            }
            return LRESULT(0);
        }
        if message == WM_TIMER && wparam.0 == FILE_CHANGE_TIMER {
            // SAFETY: only this HWND owns the debounce timer.
            unsafe {
                let _ = windows::Win32::UI::WindowsAndMessaging::KillTimer(
                    Some(hwnd),
                    FILE_CHANGE_TIMER,
                );
            }
            send_event(state, PlatformEvent::FilesChanged);
            return LRESULT(0);
        }
        if message == WM_NCHITTEST {
            return LRESULT(
                hit_test(state, hwnd, signed_low(lparam.0), signed_high(lparam.0)) as isize,
            );
        }
        if message == WM_CLOSE && state.taskbar_created != 0 && state.sender.is_some() {
            send_event(state, PlatformEvent::Exit);
            return LRESULT(0);
        }
        if message == WM_LBUTTONUP && state.mode.get() == HudMode::Interactive {
            let x = signed_low(lparam.0);
            let y = signed_high(lparam.0);
            if let Some(region) = state.hit_regions.borrow().iter().find(|region| {
                x >= region.rect.left
                    && x < region.rect.right
                    && y >= region.rect.top
                    && y < region.rect.bottom
            }) {
                send_event(state, PlatformEvent::Advance(region.id.clone()));
            }
            return LRESULT(0);
        }
        match message {
            WM_HOTKEY if wparam.0 as i32 == HOTKEY_ID => {
                send_event(state, PlatformEvent::ToggleMode)
            }
            WM_COMMAND => match loword(wparam.0) {
                COMMAND_TOGGLE_VISIBILITY => send_event(state, PlatformEvent::ToggleVisibility),
                COMMAND_TOGGLE_MODE => send_event(state, PlatformEvent::ToggleMode),
                COMMAND_OPEN_SETTINGS => send_event(state, PlatformEvent::OpenSettings),
                COMMAND_EXIT => send_event(state, PlatformEvent::Exit),
                _ => {}
            },
            WM_SIZE => send_event(
                state,
                PlatformEvent::Resized {
                    width: loword(lparam.0 as usize) as i32,
                    height: hiword(lparam.0 as usize) as i32,
                },
            ),
            WM_DPICHANGED => {
                let dpi = loword(wparam.0) as u32;
                send_event(state, PlatformEvent::DpiChanged { dpi });
                if lparam.0 != 0 {
                    // SAFETY: WM_DPICHANGED supplies a suggested RECT owned by the system for this callback.
                    let suggested = unsafe { &*(lparam.0 as *const RECT) };
                    // SAFETY: applying the system suggested rectangle preserves the new monitor scale.
                    unsafe {
                        let _ = SetWindowPos(
                            hwnd,
                            None,
                            suggested.left,
                            suggested.top,
                            suggested.right - suggested.left,
                            suggested.bottom - suggested.top,
                            SWP_NOACTIVATE | SWP_NOZORDER,
                        );
                    }
                }
            }
            WM_EXITSIZEMOVE => send_event(state, PlatformEvent::GeometryChanged),
            value if state.taskbar_created != 0 && value == state.taskbar_created => {
                send_event(state, PlatformEvent::TaskbarCreated)
            }
            WM_GETMINMAXINFO => {
                if lparam.0 != 0 {
                    // SAFETY: WM_GETMINMAXINFO supplies a MINMAXINFO pointer for this callback.
                    let info = unsafe {
                        &mut *(lparam.0 as *mut windows::Win32::UI::WindowsAndMessaging::MINMAXINFO)
                    };
                    let (min_width, min_height) =
                        min_pixel_size(unsafe { GetDpiForWindow(hwnd) }.max(96));
                    info.ptMinTrackSize.x = min_width;
                    info.ptMinTrackSize.y = min_height;
                    return LRESULT(0);
                }
            }
            _ => {}
        }
    }
    if message == WM_NCDESTROY {
        // SAFETY: clear the pointer; the owning Rust window struct reclaims the state.
        let value = unsafe { GetWindowLongPtrW(hwnd, GWLP_USERDATA) };
        unsafe {
            SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
        }
        let _ = value;
    }
    // SAFETY: forwarding unhandled messages to DefWindowProcW is required by Win32.
    unsafe { DefWindowProcW(hwnd, message, wparam, lparam) }
}

fn register_class(name: PCWSTR, instance: HINSTANCE) -> Result<(), PlatformError> {
    let class = WNDCLASSW {
        lpfnWndProc: Some(window_proc),
        hInstance: instance,
        lpszClassName: name,
        ..Default::default()
    };
    // SAFETY: class and static name remain valid for this synchronous registration.
    let atom = unsafe { RegisterClassW(&class) };
    if atom == 0 {
        let error = WindowsError::from_win32();
        if error.code().0 != 1410 {
            return Err(PlatformError::from(error));
        }
    }
    Ok(())
}

pub struct MessageWindow {
    hwnd: HWND,
    _state: Box<WindowState>,
    _thread_affine: PhantomData<Rc<()>>,
}
impl MessageWindow {
    pub fn new(sender: Sender<PlatformEvent>) -> Result<Self, PlatformError> {
        // SAFETY: querying the current module handle does not dereference caller memory.
        let instance = unsafe { GetModuleHandleW(None) }.map_err(PlatformError::from)?;
        let instance = HINSTANCE(instance.0);
        let class_name = w!("GhostPin.Native.Rust.Message");
        register_class(class_name, instance)?;
        let state = Box::new(WindowState {
            mode: Cell::new(HudMode::Interactive),
            sender: Some(sender),
            hit_regions: RefCell::new(Vec::new()),
            taskbar_created: 0,
            _thread_affine: PhantomData,
        });
        let state_ptr = (&*state as *const WindowState).cast_mut();
        // SAFETY: pointers refer to static strings or the uniquely owned WindowState.
        let result = unsafe {
            CreateWindowExW(
                WINDOW_EX_STYLE(0),
                class_name,
                w!(""),
                WS_OVERLAPPED,
                CW_USEDEFAULT,
                CW_USEDEFAULT,
                CW_USEDEFAULT,
                CW_USEDEFAULT,
                Some(HWND_MESSAGE),
                None,
                Some(instance),
                Some(state_ptr.cast()),
            )
        };
        match result {
            Ok(hwnd) => Ok(Self {
                hwnd,
                _state: state,
                _thread_affine: PhantomData,
            }),
            Err(error) => Err(PlatformError::from(error)),
        }
    }
    pub fn hwnd(&self) -> HWND {
        self.hwnd
    }
    pub fn notify_file_change(&self) -> Result<(), PlatformError> {
        // SAFETY: the HWND is a message-only window owned by this UI thread.
        unsafe {
            PostMessageW(Some(self.hwnd), FILE_CHANGE_MESSAGE, WPARAM(0), LPARAM(0))
                .map_err(PlatformError::from)
        }
    }
}
impl Drop for MessageWindow {
    fn drop(&mut self) {
        if !self.hwnd.0.is_null() {
            unsafe {
                let _ = DestroyWindow(self.hwnd);
            }
        }
    }
}

pub struct HudWindow {
    hwnd: HWND,
    _state: Box<WindowState>,
    instance: HINSTANCE,
    taskbar_created: u32,
    tray_icon: Option<HICON>,
    _thread_affine: PhantomData<Rc<()>>,
}
impl HudWindow {
    pub fn new(
        mode: HudMode,
        width: i32,
        height: i32,
        sender: Sender<PlatformEvent>,
    ) -> Result<Self, PlatformError> {
        // SAFETY: querying the current module handle does not dereference caller memory.
        let instance = unsafe { GetModuleHandleW(None) }.map_err(PlatformError::from)?;
        let instance = HINSTANCE(instance.0);
        let class_name = w!("GhostPin.Native.Rust.Hud");
        register_class(class_name, instance)?;
        let taskbar_created = unsafe { RegisterWindowMessageW(w!("TaskbarCreated")) };
        if taskbar_created == 0 {
            return Err(PlatformError {
                operation: "RegisterWindowMessageW",
                code: None,
                message: "TaskbarCreated registration failed".into(),
            });
        }
        let state = Box::new(WindowState {
            mode: Cell::new(mode),
            sender: Some(sender),
            hit_regions: RefCell::new(Vec::new()),
            taskbar_created,
            _thread_affine: PhantomData,
        });
        let state_ptr = (&*state as *const WindowState).cast_mut();
        // SAFETY: pointers refer to static strings or the uniquely owned WindowState.
        let result = unsafe {
            CreateWindowExW(
                HudStyle::for_mode(mode).ex_style,
                class_name,
                w!("GhostPin"),
                WS_POPUP | WS_THICKFRAME,
                CW_USEDEFAULT,
                CW_USEDEFAULT,
                width.max(min_pixel_size(96).0),
                height.max(min_pixel_size(96).1),
                None,
                None,
                Some(instance),
                Some(state_ptr.cast()),
            )
        };
        match result {
            Ok(hwnd) => Ok(Self {
                hwnd,
                _state: state,
                instance,
                taskbar_created,
                tray_icon: None,
                _thread_affine: PhantomData,
            }),
            Err(error) => Err(PlatformError::from(error)),
        }
    }
    pub fn hwnd(&self) -> HWND {
        self.hwnd
    }
    pub fn show(&self) {
        unsafe {
            let _ = ShowWindow(self.hwnd, SW_SHOWNOACTIVATE);
            let _ = UpdateWindow(self.hwnd);
        }
    }
    pub fn hide(&self) {
        unsafe {
            let _ = ShowWindow(self.hwnd, SW_HIDE);
        }
    }
    pub fn visible(&self) -> bool {
        unsafe { IsWindowVisible(self.hwnd).as_bool() }
    }
    pub fn mode(&self) -> HudMode {
        unsafe { state_ptr(self.hwnd) }
            .map(|ptr| unsafe { &*ptr })
            .map_or(HudMode::Passthrough, |state| state.mode.get())
    }
    pub fn set_mode(&self, mode: HudMode) -> Result<(), PlatformError> {
        self.apply_style(HudStyle::for_mode(mode))?;
        if let Some(state) = unsafe { state_ptr(self.hwnd) }.map(|ptr| unsafe { &*ptr }) {
            state.mode.set(mode);
        }
        Ok(())
    }
    pub fn set_hit_regions(&self, regions: Vec<(String, RECT)>) {
        if let Some(state) = unsafe { state_ptr(self.hwnd) }.map(|ptr| unsafe { &*ptr }) {
            *state.hit_regions.borrow_mut() = regions
                .into_iter()
                .map(|(id, rect)| HitRegion { id, rect })
                .collect();
        }
    }
    pub fn apply_style(&self, style: HudStyle) -> Result<(), PlatformError> {
        // SAFETY: this HWND belongs to the current UI thread and the index is valid for extended styles.
        let previous = unsafe {
            SetWindowLongPtrW(
                self.hwnd,
                WINDOW_LONG_PTR_INDEX(-20),
                style.ex_style.0 as isize,
            )
        };
        if previous == 0 {
            let error = WindowsError::from_win32();
            if error.code().0 != 0 {
                return Err(PlatformError::from(error));
            }
        }
        // SAFETY: force the non-client style to be recalculated without moving or activating the HUD.
        unsafe {
            let _ = SetWindowPos(
                self.hwnd,
                None,
                0,
                0,
                0,
                0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOZORDER | SWP_FRAMECHANGED,
            );
        }
        Ok(())
    }
    pub fn set_topmost(&self, topmost: bool) -> Result<(), PlatformError> {
        let owner = if topmost {
            HWND_TOPMOST
        } else {
            HWND_NOTOPMOST
        };
        unsafe {
            SetWindowPos(
                self.hwnd,
                Some(owner),
                0,
                0,
                0,
                0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE,
            )
            .map_err(PlatformError::from)
        }
    }
    pub fn set_pixel_rect(&self, rect: RECT) {
        unsafe {
            let _ = SetWindowPos(
                self.hwnd,
                None,
                rect.left,
                rect.top,
                rect.right - rect.left,
                rect.bottom - rect.top,
                SWP_NOACTIVATE | SWP_NOZORDER,
            );
        }
    }
    pub fn pixel_rect(&self) -> Result<RECT, PlatformError> {
        let mut rect = RECT::default();
        // SAFETY: rect is a valid out parameter for a live window.
        unsafe {
            GetWindowRect(self.hwnd, &mut rect).map_err(PlatformError::from)?;
        }
        Ok(rect)
    }
    pub fn dpi(&self) -> u32 {
        unsafe { GetDpiForWindow(self.hwnd) }.max(96)
    }
    pub fn capture_placement(&self) -> Result<Placement, PlatformError> {
        let rect = self.pixel_rect()?;
        let monitor = unsafe { MonitorFromWindow(self.hwnd, MONITOR_DEFAULTTONEAREST) };
        let mut info = MONITORINFO {
            cbSize: std::mem::size_of::<MONITORINFO>() as u32,
            ..Default::default()
        };
        // SAFETY: monitor is returned for this live window and info is initialized.
        unsafe {
            GetMonitorInfoW(monitor, &mut info)
                .ok()
                .map_err(PlatformError::from)?;
        }
        let dpi = self.dpi();
        Ok(Placement {
            monitor_id: monitor_device_name(monitor)?,
            relative_x: (rect.left - info.rcWork.left) as f64 / dpi as f64 * 96.0,
            relative_y: (rect.top - info.rcWork.top) as f64 / dpi as f64 * 96.0,
            logical_width: (rect.right - rect.left) as f64 / dpi as f64 * 96.0,
            logical_height: (rect.bottom - rect.top) as f64 / dpi as f64 * 96.0,
            dpi,
        })
    }
    pub fn restore_placement(&self, placement: &Placement) -> Result<(), PlatformError> {
        let monitor = find_monitor(&placement.monitor_id).unwrap_or_else(|| unsafe {
            MonitorFromPoint(POINT { x: 0, y: 0 }, MONITOR_DEFAULTTOPRIMARY)
        });
        let mut info = MONITORINFO {
            cbSize: std::mem::size_of::<MONITORINFO>() as u32,
            ..Default::default()
        };
        unsafe {
            GetMonitorInfoW(monitor, &mut info)
                .ok()
                .map_err(PlatformError::from)?;
        }
        let dpi = monitor_dpi(monitor, self.dpi());
        let mut rect = placement_rect(placement, &info, dpi);
        if !intersects(rect, info.rcWork) {
            let primary =
                unsafe { MonitorFromPoint(POINT { x: 0, y: 0 }, MONITOR_DEFAULTTOPRIMARY) };
            if primary != monitor {
                unsafe {
                    GetMonitorInfoW(primary, &mut info)
                        .ok()
                        .map_err(PlatformError::from)?;
                }
                rect = placement_rect(placement, &info, monitor_dpi(primary, dpi));
            }
        }
        rect = clamp_to_work_area(rect, &info);
        unsafe {
            SetWindowPos(
                self.hwnd,
                None,
                rect.left,
                rect.top,
                rect.right - rect.left,
                rect.bottom - rect.top,
                SWP_NOACTIVATE | SWP_NOZORDER,
            )
            .map_err(PlatformError::from)
        }
    }
    pub fn register_hotkey(&self, modifiers: u32, key: u32) -> Result<(), PlatformError> {
        unsafe {
            RegisterHotKey(
                Some(self.hwnd),
                HOTKEY_ID,
                HOT_KEY_MODIFIERS(modifiers | 0x4000),
                key,
            )
            .map_err(PlatformError::from)
        }
    }
    pub fn unregister_hotkey(&self) {
        unsafe {
            let _ = UnregisterHotKey(Some(self.hwnd), HOTKEY_ID);
        }
    }
    pub fn add_tray_icon(&mut self) -> Result<(), PlatformError> {
        let icon = self.tray_icon.or_else(|| unsafe {
            LoadIconW(Some(self.instance), PCWSTR(101usize as *const u16)).ok()
        });
        let Some(icon) = icon else {
            return Err(PlatformError {
                operation: "LoadIconW",
                code: None,
                message: "GhostPin.ico resource 101 is unavailable".into(),
            });
        };
        let mut data = NOTIFYICONDATAW {
            cbSize: std::mem::size_of::<NOTIFYICONDATAW>() as u32,
            hWnd: self.hwnd,
            uID: TRAY_ID,
            uFlags: NIF_MESSAGE | NIF_ICON | NIF_TIP,
            uCallbackMessage: TRAY_CALLBACK,
            hIcon: icon,
            ..Default::default()
        };
        let tip = "GhostPin"
            .encode_utf16()
            .chain(std::iter::once(0))
            .collect::<Vec<_>>();
        let limit = tip.len().min(data.szTip.len());
        data.szTip[..limit].copy_from_slice(&tip[..limit]);
        unsafe {
            Shell_NotifyIconW(NIM_ADD, &mut data)
                .ok()
                .map_err(PlatformError::from)?;
            data.Anonymous.uVersion = 4;
            Shell_NotifyIconW(NIM_SETVERSION, &mut data)
                .ok()
                .map_err(PlatformError::from)?;
        }
        self.tray_icon = Some(icon);
        Ok(())
    }
    pub fn remove_tray_icon(&mut self) {
        let mut data = NOTIFYICONDATAW {
            cbSize: std::mem::size_of::<NOTIFYICONDATAW>() as u32,
            hWnd: self.hwnd,
            uID: TRAY_ID,
            ..Default::default()
        };
        unsafe {
            let _ = Shell_NotifyIconW(NIM_DELETE, &mut data);
        }
        self.tray_icon = None;
    }
    pub fn show_tray_menu(&self) -> Result<(), PlatformError> {
        let menu = unsafe { CreatePopupMenu().map_err(PlatformError::from)? };
        let result = unsafe {
            (|| {
                AppendMenuW(
                    menu,
                    if self.visible() {
                        MF_STRING | MF_CHECKED
                    } else {
                        MF_STRING
                    },
                    COMMAND_TOGGLE_VISIBILITY as usize,
                    w!("显示/隐藏 HUD"),
                )
                .map_err(PlatformError::from)?;
                AppendMenuW(
                    menu,
                    if self.mode() == HudMode::Interactive {
                        MF_STRING | MF_CHECKED
                    } else {
                        MF_STRING
                    },
                    COMMAND_TOGGLE_MODE as usize,
                    w!("切换交互模式"),
                )
                .map_err(PlatformError::from)?;
                AppendMenuW(menu, MF_STRING, COMMAND_OPEN_SETTINGS as usize, w!("设置"))
                    .map_err(PlatformError::from)?;
                AppendMenuW(menu, MF_SEPARATOR, 0, PCWSTR::null()).map_err(PlatformError::from)?;
                AppendMenuW(menu, MF_STRING, COMMAND_EXIT as usize, w!("退出"))
                    .map_err(PlatformError::from)?;
                let mut point = POINT::default();
                GetCursorPos(&mut point).map_err(PlatformError::from)?;
                let _ = SetForegroundWindow(self.hwnd);
                TrackPopupMenu(
                    menu,
                    TPM_RIGHTBUTTON | TPM_BOTTOMALIGN,
                    point.x,
                    point.y,
                    Some(0),
                    self.hwnd,
                    None,
                )
                .ok()
                .map_err(PlatformError::from)?;
                let _ = PostMessageW(Some(self.hwnd), WM_NULL, WPARAM(0), LPARAM(0));
                Ok(())
            })()
        };
        unsafe {
            let _ = DestroyMenu(menu);
        }
        result
    }
    pub fn taskbar_message(&self) -> u32 {
        self.taskbar_created
    }
}
impl Drop for HudWindow {
    fn drop(&mut self) {
        self.remove_tray_icon();
        self.unregister_hotkey();
        if !self.hwnd.0.is_null() {
            unsafe {
                let _ = DestroyWindow(self.hwnd);
            }
        }
    }
}

pub fn pump_messages(dialog: Option<HWND>) -> bool {
    let mut message = MSG::default();
    let mut quit = false;
    while unsafe {
        windows::Win32::UI::WindowsAndMessaging::PeekMessageW(&mut message, None, 0, 0, PM_REMOVE)
    }
    .as_bool()
    {
        if let Some(dialog) = dialog {
            // SAFETY: the modeless settings window belongs to this UI thread.
            if unsafe {
                windows::Win32::UI::WindowsAndMessaging::IsDialogMessageW(dialog, &mut message)
            }
            .as_bool()
            {
                continue;
            }
        }
        if message.message == windows::Win32::UI::WindowsAndMessaging::WM_QUIT {
            quit = true;
            break;
        }
        unsafe {
            let _ = TranslateMessage(&message);
            let _ = DispatchMessageW(&message);
        }
    }
    quit
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn style_modes_have_expected_flags() {
        let passthrough = HudStyle::for_mode(HudMode::Passthrough).ex_style.0;
        let interactive = HudStyle::for_mode(HudMode::Interactive).ex_style.0;
        assert_ne!(passthrough & WS_EX_TRANSPARENT.0, 0);
        assert_eq!(interactive & WS_EX_TRANSPARENT.0, 0);
        assert_ne!(passthrough & WS_EX_NOACTIVATE.0, 0);
    }

    #[test]
    fn placement_minimum_scales_with_target_dpi() {
        let info = MONITORINFO {
            cbSize: std::mem::size_of::<MONITORINFO>() as u32,
            rcWork: RECT {
                left: 0,
                top: 0,
                right: 1920,
                bottom: 1080,
            },
            ..Default::default()
        };
        let rect = placement_rect(&Placement::default(), &info, 144);
        assert_eq!(rect.right - rect.left, 540);
        assert_eq!(rect.bottom - rect.top, 690);
        let minimum = placement_rect(
            &Placement {
                logical_width: 1.0,
                logical_height: 1.0,
                ..Placement::default()
            },
            &info,
            144,
        );
        assert_eq!(minimum.right - minimum.left, 450);
        assert_eq!(minimum.bottom - minimum.top, 420);
    }
}
