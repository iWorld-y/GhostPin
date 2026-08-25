use std::{ffi::c_void, fmt, mem::size_of, ptr::null_mut};

use windows::Win32::{
    Foundation::{COLORREF, HWND, POINT, RECT, SIZE},
    Graphics::Gdi::{
        BI_RGB, BITMAPINFO, BITMAPINFOHEADER, CreateCompatibleDC, CreateDIBSection, DIB_RGB_COLORS,
        DT_LEFT, DT_NOPREFIX, DT_SINGLELINE, DT_VCENTER, DeleteDC, DeleteObject, DrawTextW, GetDC,
        HBITMAP, HDC, HGDIOBJ, ReleaseDC, SelectObject, SetBkMode, SetTextColor, TRANSPARENT,
    },
    UI::WindowsAndMessaging::{ULW_ALPHA, UpdateLayeredWindow},
};

use crate::core::{Priority, Projection};

#[derive(Debug)]
pub struct RenderError(pub String);
impl fmt::Display for RenderError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}
impl std::error::Error for RenderError {}

/// Owns a top-down 32-bit premultiplied DIB used as the layered-window source.
pub struct HudSurface {
    dc: HDC,
    bitmap: HBITMAP,
    previous: HGDIOBJ,
    bits: *mut c_void,
    width: i32,
    height: i32,
}

impl HudSurface {
    pub fn new(width: i32, height: i32) -> Result<Self, RenderError> {
        let width = width.max(1);
        let height = height.max(1);
        // SAFETY: a memory DC with a null source is valid and owned by this surface.
        let dc = unsafe { CreateCompatibleDC(None) };
        if dc.0.is_null() {
            return Err(RenderError("CreateCompatibleDC: returned null".into()));
        }
        let info = BITMAPINFO {
            bmiHeader: BITMAPINFOHEADER {
                biSize: size_of::<BITMAPINFOHEADER>() as u32,
                biWidth: width,
                biHeight: -height,
                biPlanes: 1,
                biBitCount: 32,
                biCompression: BI_RGB.0,
                ..Default::default()
            },
            ..Default::default()
        };
        let mut bits: *mut c_void = null_mut();
        // SAFETY: info is initialized, bits is an out pointer, and the returned bitmap is owned here.
        let bitmap = unsafe { CreateDIBSection(None, &info, DIB_RGB_COLORS, &mut bits, None, 0) }
            .map_err(|e| RenderError(format!("CreateDIBSection: {e}")))?;
        // SAFETY: the bitmap belongs to this DC for the lifetime of the surface.
        let previous = unsafe { SelectObject(dc, bitmap.into()) };
        if previous.0.is_null() {
            // SAFETY: both handles were created above and are not selected elsewhere.
            unsafe {
                let _ = DeleteObject(bitmap.into());
                let _ = DeleteDC(dc);
            }
            return Err(RenderError("SelectObject(DIB): returned null".into()));
        }
        Ok(Self {
            dc,
            bitmap,
            previous,
            bits,
            width,
            height,
        })
    }

    pub fn resize(&mut self, width: i32, height: i32) -> Result<(), RenderError> {
        if self.width == width && self.height == height {
            return Ok(());
        }
        let next = Self::new(width, height)?;
        std::mem::replace(self, next).dispose();
        Ok(())
    }

    pub fn draw(&mut self, projection: &Projection) {
        // SAFETY: bits points to width*height 32-bit pixels returned by CreateDIBSection.
        let pixels = unsafe {
            std::slice::from_raw_parts_mut(
                self.bits.cast::<u32>(),
                (self.width * self.height) as usize,
            )
        };
        pixels.fill(0x00000000);
        fill_rect(
            pixels,
            self.width,
            self.height,
            16,
            16,
            self.width - 16,
            self.height - 16,
            0xF5FFFFFF,
        );
        fill_rect(
            pixels,
            self.width,
            self.height,
            16,
            16,
            self.width - 16,
            68,
            0xFFEAF7EF,
        );
        draw_text(
            self.dc,
            "GhostPin",
            RECT {
                left: 30,
                top: 22,
                right: self.width - 30,
                bottom: 58,
            },
            0xFF1F6F45,
        );
        let mut y = 84;
        if projection.items.is_empty() {
            draw_text(
                self.dc,
                "暂无待办",
                RECT {
                    left: 30,
                    top: y,
                    right: self.width - 30,
                    bottom: y + 34,
                },
                0xFF667085,
            );
            return;
        }
        if !projection.doing.is_empty() {
            draw_text(
                self.dc,
                "Doing",
                RECT {
                    left: 30,
                    top: y,
                    right: self.width - 30,
                    bottom: y + 24,
                },
                0xFF1F6F45,
            );
            y += 28;
            for item in &projection.doing {
                y = draw_item(self.dc, y, &item.title, item.priority, self.width);
            }
        }
        if !projection.todo.is_empty() {
            draw_text(
                self.dc,
                "Todo",
                RECT {
                    left: 30,
                    top: y + 4,
                    right: self.width - 30,
                    bottom: y + 28,
                },
                0xFF667085,
            );
            y += 32;
            for item in &projection.todo {
                y = draw_item(self.dc, y, &item.title, item.priority, self.width);
            }
        }
    }

    pub fn present(&self, hwnd: HWND, x: i32, y: i32, opacity: u8) -> Result<(), RenderError> {
        // SAFETY: acquiring the desktop DC for the synchronous layered update.
        let screen = unsafe { GetDC(None) };
        if screen.0.is_null() {
            return Err(RenderError("GetDC: returned null".into()));
        }
        let destination = POINT { x, y };
        let size = SIZE {
            cx: self.width,
            cy: self.height,
        };
        let source = POINT { x: 0, y: 0 };
        let blend = windows::Win32::Graphics::Gdi::BLENDFUNCTION {
            BlendOp: 0,
            BlendFlags: 0,
            SourceConstantAlpha: opacity,
            AlphaFormat: 1,
        };
        // SAFETY: all handles and structures remain valid for the synchronous layered update.
        let result = unsafe {
            UpdateLayeredWindow(
                hwnd,
                Some(screen),
                Some(&destination),
                Some(&size),
                Some(self.dc),
                Some(&source),
                COLORREF(0),
                Some(&blend),
                ULW_ALPHA,
            )
        };
        // SAFETY: screen was acquired for the desktop window and is released exactly once.
        unsafe {
            let _ = ReleaseDC(None, screen);
        }
        result.map_err(|e| RenderError(format!("UpdateLayeredWindow: {e}")))
    }

    fn dispose(mut self) {
        // SAFETY: restore the previous selection before deleting the selected DIB/DC.
        unsafe {
            let _ = SelectObject(self.dc, self.previous);
            let _ = DeleteObject(self.bitmap.into());
            let _ = DeleteDC(self.dc);
        }
        self.bits = null_mut();
    }
}
impl Drop for HudSurface {
    fn drop(&mut self) {
        // SAFETY: restore the previous selection before deleting the selected DIB/DC.
        unsafe {
            let _ = SelectObject(self.dc, self.previous);
            let _ = DeleteObject(self.bitmap.into());
            let _ = DeleteDC(self.dc);
        }
    }
}

#[allow(clippy::too_many_arguments)]
fn fill_rect(
    pixels: &mut [u32],
    width: i32,
    height: i32,
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
    color: u32,
) {
    let left = left.clamp(0, width);
    let right = right.clamp(left, width);
    let top = top.clamp(0, height);
    let bottom = bottom.clamp(top, height);
    for row in top..bottom {
        pixels[(row * width + left) as usize..(row * width + right) as usize].fill(color);
    }
}

fn draw_item(dc: HDC, y: i32, title: &str, priority: Priority, width: i32) -> i32 {
    let color = match priority {
        Priority::High => 0xFFE0A100,
        Priority::Medium => 0xFF1F6F45,
        Priority::Low => 0xFF667085,
    };
    let title = title.chars().take(34).collect::<String>();
    let title = format!(
        "{} {}",
        match priority {
            Priority::High => "!",
            Priority::Medium => "·",
            Priority::Low => "–",
        },
        title
    );
    draw_text(
        dc,
        &title,
        RECT {
            left: 34,
            top: y,
            right: width - 30,
            bottom: y + 30,
        },
        color,
    );
    y + 36
}

fn draw_text(dc: HDC, text: &str, mut rect: RECT, color: u32) {
    let mut wide = text
        .encode_utf16()
        .chain(std::iter::once(0))
        .collect::<Vec<_>>();
    // SAFETY: wide is NUL terminated and alive for the synchronous DrawTextW call.
    unsafe {
        let _ = SetBkMode(dc, TRANSPARENT);
        let _ = SetTextColor(dc, COLORREF(color));
        let _ = DrawTextW(
            dc,
            &mut wide,
            &mut rect,
            DT_LEFT | DT_SINGLELINE | DT_VCENTER | DT_NOPREFIX,
        );
    }
}
