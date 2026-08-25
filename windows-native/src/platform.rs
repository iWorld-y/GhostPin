use std::{cell::Cell, fmt, marker::PhantomData, rc::Rc};

use windows::{
    Win32::{
        Foundation::{HINSTANCE, HWND, LPARAM, LRESULT, WPARAM},
        System::LibraryLoader::GetModuleHandleW,
        UI::WindowsAndMessaging::{
            CREATESTRUCTW, CW_USEDEFAULT, CreateWindowExW, DefWindowProcW, DestroyWindow,
            GWLP_USERDATA, GetWindowLongPtrW, HWND_MESSAGE, RegisterClassW, SetWindowLongPtrW,
            WINDOW_EX_STYLE, WINDOW_LONG_PTR_INDEX, WM_NCCREATE, WM_NCDESTROY, WNDCLASSW,
            WS_EX_LAYERED, WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW, WS_EX_TRANSPARENT, WS_OVERLAPPED,
        },
    },
    core::{Error as WindowsError, w},
};

use crate::core::HudMode;

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

struct WindowState {
    mode: Cell<HudMode>,
    _thread_affine: PhantomData<Rc<()>>,
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
        // SAFETY: the value is an owned WindowState pointer until WM_NCDESTROY.
        unsafe {
            SetWindowLongPtrW(hwnd, GWLP_USERDATA, create.lpCreateParams as isize);
        }
        return LRESULT(1);
    }
    if message == WM_NCDESTROY {
        // SAFETY: only the creating UI thread accesses this window user data.
        let state = unsafe { GetWindowLongPtrW(hwnd, GWLP_USERDATA) };
        // SAFETY: clear the pointer before reclaiming its unique allocation.
        unsafe {
            SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
        }
        if state != 0 {
            // SAFETY: WM_NCDESTROY is the final callback and owns this pointer.
            unsafe {
                drop(Box::from_raw(state as *mut WindowState));
            }
        }
    }
    if message == windows::Win32::UI::WindowsAndMessaging::WM_NCHITTEST {
        // SAFETY: the user data was installed during WM_NCCREATE and remains valid until WM_NCDESTROY.
        let state = unsafe { GetWindowLongPtrW(hwnd, GWLP_USERDATA) };
        if state != 0 {
            // SAFETY: only the creating UI thread dispatches this window procedure.
            let mode = unsafe { &*(state as *const WindowState) }.mode.get();
            if mode == HudMode::Passthrough {
                return LRESULT(windows::Win32::UI::WindowsAndMessaging::HTTRANSPARENT as isize);
            }
            return LRESULT(windows::Win32::UI::WindowsAndMessaging::HTCAPTION as isize);
        }
    }
    // SAFETY: forwarding unhandled messages to the system window procedure is required by Win32.
    unsafe { DefWindowProcW(hwnd, message, wparam, lparam) }
}

pub struct MessageWindow {
    hwnd: HWND,
    _thread_affine: PhantomData<Rc<()>>,
}
impl MessageWindow {
    pub fn new() -> Result<Self, PlatformError> {
        // SAFETY: querying the current module handle does not dereference caller memory.
        let instance = unsafe { GetModuleHandleW(None) }.map_err(PlatformError::from)?;
        let class_name = w!("GhostPin.Native.Rust.Message");
        let class = WNDCLASSW {
            lpfnWndProc: Some(window_proc),
            hInstance: HINSTANCE(instance.0),
            lpszClassName: class_name,
            ..Default::default()
        };
        // SAFETY: the class structure and static name remain valid for the call.
        let atom = unsafe { RegisterClassW(&class) };
        if atom == 0 {
            let error = WindowsError::from_win32();
            if error.code().0 != 1410 {
                return Err(PlatformError::from(error));
            }
        }
        let state = Box::into_raw(Box::new(WindowState {
            mode: Cell::new(HudMode::Interactive),
            _thread_affine: PhantomData,
        }));
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
                Some(instance.into()),
                Some(state.cast()),
            )
        };
        match result {
            Ok(hwnd) => Ok(Self {
                hwnd,
                _thread_affine: PhantomData,
            }),
            Err(error) => {
                // SAFETY: creation failed, so ownership of state remains here.
                unsafe {
                    drop(Box::from_raw(state));
                }
                Err(PlatformError::from(error))
            }
        }
    }
    pub fn hwnd(&self) -> HWND {
        self.hwnd
    }
    pub fn apply_style(&self, style: HudStyle) -> Result<(), PlatformError> {
        let value = style.ex_style.0 as isize;
        // SAFETY: this HWND is owned by the creating UI thread and the index is valid for extended styles.
        let previous = unsafe { SetWindowLongPtrW(self.hwnd, WINDOW_LONG_PTR_INDEX(-20), value) };
        if previous == 0 {
            let error = WindowsError::from_win32();
            if error.code().0 != 0 {
                return Err(PlatformError::from(error));
            }
        }
        // SAFETY: readback uses the same valid window and style index.
        let actual = unsafe { GetWindowLongPtrW(self.hwnd, WINDOW_LONG_PTR_INDEX(-20)) } as u32;
        if actual != style.ex_style.0 {
            return Err(PlatformError {
                operation: "SetWindowLongPtrW",
                code: None,
                message: "window style readback mismatch".into(),
            });
        }
        Ok(())
    }
}
impl Drop for MessageWindow {
    fn drop(&mut self) {
        if !self.hwnd.0.is_null() {
            // SAFETY: HWND destruction is confined to its creating UI thread.
            unsafe {
                let _ = DestroyWindow(self.hwnd);
            }
        }
    }
}

/// Owns the visible layered HUD window and keeps its mode state thread-affine.
pub struct HudWindow {
    hwnd: HWND,
    _thread_affine: PhantomData<Rc<()>>,
}
impl HudWindow {
    pub fn new(mode: HudMode, width: i32, height: i32) -> Result<Self, PlatformError> {
        // SAFETY: querying the current module handle does not dereference caller memory.
        let instance = unsafe { GetModuleHandleW(None) }.map_err(PlatformError::from)?;
        let class_name = w!("GhostPin.Native.Rust.Hud");
        let class = WNDCLASSW {
            lpfnWndProc: Some(window_proc),
            hInstance: HINSTANCE(instance.0),
            lpszClassName: class_name,
            ..Default::default()
        };
        // SAFETY: the class structure and static name remain valid for the call.
        let atom = unsafe { RegisterClassW(&class) };
        if atom == 0 {
            let error = WindowsError::from_win32();
            if error.code().0 != 1410 {
                return Err(PlatformError::from(error));
            }
        }
        let state = Box::into_raw(Box::new(WindowState {
            mode: Cell::new(mode),
            _thread_affine: PhantomData,
        }));
        // SAFETY: pointers refer to static strings or the uniquely owned WindowState.
        let result = unsafe {
            CreateWindowExW(
                HudStyle::for_mode(mode).ex_style,
                class_name,
                w!("GhostPin"),
                windows::Win32::UI::WindowsAndMessaging::WS_POPUP,
                CW_USEDEFAULT,
                CW_USEDEFAULT,
                width,
                height,
                None,
                None,
                Some(instance.into()),
                Some(state.cast()),
            )
        };
        match result {
            Ok(hwnd) => Ok(Self {
                hwnd,
                _thread_affine: PhantomData,
            }),
            Err(error) => {
                // SAFETY: creation failed, so ownership of state remains here.
                unsafe {
                    drop(Box::from_raw(state));
                }
                Err(PlatformError::from(error))
            }
        }
    }
    pub fn hwnd(&self) -> HWND {
        self.hwnd
    }
    pub fn show(&self) {
        // SAFETY: this HWND belongs to the current UI thread; SW_SHOWNOACTIVATE preserves focus.
        unsafe {
            let _ = windows::Win32::UI::WindowsAndMessaging::ShowWindow(
                self.hwnd,
                windows::Win32::UI::WindowsAndMessaging::SW_SHOWNOACTIVATE,
            );
        }
    }
    pub fn hide(&self) {
        // SAFETY: this HWND belongs to the current UI thread.
        unsafe {
            let _ = windows::Win32::UI::WindowsAndMessaging::ShowWindow(
                self.hwnd,
                windows::Win32::UI::WindowsAndMessaging::SW_HIDE,
            );
        }
    }
    pub fn set_mode(&self, mode: HudMode) -> Result<(), PlatformError> {
        self.apply_style(HudStyle::for_mode(mode))?;
        // SAFETY: the pointer is the unique WindowState installed by WM_NCCREATE.
        let state = unsafe { GetWindowLongPtrW(self.hwnd, GWLP_USERDATA) };
        if state != 0 {
            // SAFETY: only the creating UI thread accesses the state.
            unsafe {
                (&*(state as *const WindowState)).mode.set(mode);
            }
        }
        Ok(())
    }
    pub fn apply_style(&self, style: HudStyle) -> Result<(), PlatformError> {
        let value = style.ex_style.0 as isize;
        // SAFETY: this HWND is owned by the creating UI thread and the index is valid for extended styles.
        let previous = unsafe { SetWindowLongPtrW(self.hwnd, WINDOW_LONG_PTR_INDEX(-20), value) };
        if previous == 0 {
            let error = WindowsError::from_win32();
            if error.code().0 != 0 {
                return Err(PlatformError::from(error));
            }
        }
        // SAFETY: readback uses the same valid window and style index.
        let actual = unsafe { GetWindowLongPtrW(self.hwnd, WINDOW_LONG_PTR_INDEX(-20)) } as u32;
        if actual != style.ex_style.0 {
            return Err(PlatformError {
                operation: "SetWindowLongPtrW",
                code: None,
                message: "window style readback mismatch".into(),
            });
        }
        Ok(())
    }
}
impl Drop for HudWindow {
    fn drop(&mut self) {
        if !self.hwnd.0.is_null() {
            // SAFETY: HWND destruction is confined to its creating UI thread.
            unsafe {
                let _ = DestroyWindow(self.hwnd);
            }
        }
    }
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
}
