use std::{
    ffi::c_void,
    fmt,
    marker::PhantomData,
    mem::size_of,
    ptr::null_mut,
    rc::Rc,
    time::{SystemTime, UNIX_EPOCH},
};

use windows::{
    Win32::{
        Foundation::{COLORREF, D2DERR_RECREATE_TARGET, HWND, POINT, RECT, SIZE},
        Graphics::Imaging::{
            CLSID_WICImagingFactory, GUID_WICPixelFormat32bppPBGRA, IWICImagingFactory,
            IWICPalette, WICBitmapDitherTypeNone, WICBitmapPaletteTypeCustom,
            WICDecodeMetadataCacheOnLoad,
        },
        Graphics::{
            Direct2D::{
                Common::{
                    D2D_RECT_F, D2D1_ALPHA_MODE_PREMULTIPLIED, D2D1_COLOR_F, D2D1_PIXEL_FORMAT,
                },
                D2D1_ANTIALIAS_MODE_PER_PRIMITIVE, D2D1_BITMAP_INTERPOLATION_MODE_LINEAR,
                D2D1_ELLIPSE, D2D1_FACTORY_TYPE_SINGLE_THREADED, D2D1_FEATURE_LEVEL_DEFAULT,
                D2D1_RENDER_TARGET_PROPERTIES, D2D1_RENDER_TARGET_TYPE_DEFAULT,
                D2D1_RENDER_TARGET_USAGE_NONE, D2D1CreateFactory, ID2D1Bitmap, ID2D1Brush,
                ID2D1DCRenderTarget, ID2D1Factory,
            },
            DirectWrite::{
                DWRITE_FACTORY_TYPE_SHARED, DWRITE_FONT_STRETCH_NORMAL, DWRITE_FONT_STYLE_NORMAL,
                DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_WEIGHT_SEMI_BOLD,
                DWRITE_MEASURING_MODE_NATURAL, DWRITE_WORD_WRAPPING_NO_WRAP, DWriteCreateFactory,
                IDWriteFactory, IDWriteTextFormat,
            },
            Dxgi::Common::DXGI_FORMAT_B8G8R8A8_UNORM,
            Gdi::{
                BI_RGB, BITMAPINFO, BITMAPINFOHEADER, CreateCompatibleDC, CreateDIBSection,
                DIB_RGB_COLORS, DeleteDC, DeleteObject, GetDC, HBITMAP, HDC, HGDIOBJ, ReleaseDC,
                SelectObject,
            },
        },
        System::Com::{CLSCTX_INPROC_SERVER, CoCreateInstance, IStream},
        UI::WindowsAndMessaging::{ULW_ALPHA, UpdateLayeredWindow},
    },
    core::{Interface, w},
};

use crate::core::{Priority, Projection, is_overdue};

#[derive(Debug)]
pub struct RenderError(pub String);
impl fmt::Display for RenderError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}
impl std::error::Error for RenderError {}

fn color(red: f32, green: f32, blue: f32, alpha: f32) -> D2D1_COLOR_F {
    D2D1_COLOR_F {
        r: red,
        g: green,
        b: blue,
        a: alpha,
    }
}

/// Owns a premultiplied DIB and the Direct2D/DirectWrite resources that draw into it.
pub struct HudSurface {
    dc: HDC,
    bitmap: HBITMAP,
    previous: HGDIOBJ,
    width: i32,
    height: i32,
    factory: ID2D1Factory,
    target: ID2D1DCRenderTarget,
    brand_bitmap: Option<ID2D1Bitmap>,
    title_format: IDWriteTextFormat,
    section_format: IDWriteTextFormat,
    body_format: IDWriteTextFormat,
    secondary_format: IDWriteTextFormat,
    empty_format: IDWriteTextFormat,
    _thread_affine: PhantomData<Rc<()>>,
}

impl HudSurface {
    pub fn new(width: i32, height: i32) -> Result<Self, RenderError> {
        // SAFETY: Direct2D and DirectWrite factories are created once on the UI thread.
        let factory =
            unsafe { D2D1CreateFactory::<ID2D1Factory>(D2D1_FACTORY_TYPE_SINGLE_THREADED, None) }
                .map_err(|e| RenderError(format!("D2D1CreateFactory: {e}")))?;
        // SAFETY: the shared DirectWrite factory is process-safe and owned by this surface.
        let write_factory =
            unsafe { DWriteCreateFactory::<IDWriteFactory>(DWRITE_FACTORY_TYPE_SHARED) }
                .map_err(|e| RenderError(format!("DWriteCreateFactory: {e}")))?;
        let title_format = create_format(&write_factory, 16.0, DWRITE_FONT_WEIGHT_SEMI_BOLD)?;
        let section_format = create_format(&write_factory, 11.0, DWRITE_FONT_WEIGHT_SEMI_BOLD)?;
        let body_format = create_format(&write_factory, 14.0, DWRITE_FONT_WEIGHT_SEMI_BOLD)?;
        let secondary_format = create_format(&write_factory, 11.0, DWRITE_FONT_WEIGHT_NORMAL)?;
        let empty_format = create_format(&write_factory, 13.0, DWRITE_FONT_WEIGHT_NORMAL)?;
        // SAFETY: the factory and immutable property structure are valid for this call.
        let target = unsafe { factory.CreateDCRenderTarget(&render_target_properties()) }
            .map_err(|e| RenderError(format!("CreateDCRenderTarget: {e}")))?;
        let mut surface = Self {
            dc: HDC::default(),
            bitmap: HBITMAP::default(),
            previous: HGDIOBJ::default(),
            width: 1,
            height: 1,
            factory,
            target,
            brand_bitmap: None,
            title_format,
            section_format,
            body_format,
            secondary_format,
            empty_format,
            _thread_affine: PhantomData,
        };
        surface.resize(width, height)?;
        Ok(surface)
    }

    pub fn resize(&mut self, width: i32, height: i32) -> Result<(), RenderError> {
        let width = width.max(1);
        let height = height.max(1);
        if self.width == width && self.height == height && !self.dc.0.is_null() {
            return Ok(());
        }
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
        // SAFETY: info and bits are valid out parameters; the DIB is owned by the surface.
        let bitmap =
            match unsafe { CreateDIBSection(None, &info, DIB_RGB_COLORS, &mut bits, None, 0) } {
                Ok(bitmap) => bitmap,
                Err(error) => {
                    unsafe {
                        let _ = DeleteDC(dc);
                    }
                    return Err(RenderError(format!("CreateDIBSection: {error}")));
                }
            };
        // SAFETY: the bitmap is selected into this DC for its lifetime.
        let previous = unsafe { SelectObject(dc, bitmap.into()) };
        if previous.0.is_null() {
            unsafe {
                let _ = DeleteObject(bitmap.into());
                let _ = DeleteDC(dc);
            }
            return Err(RenderError("SelectObject(DIB): returned null".into()));
        }
        let properties = render_target_properties();
        // SAFETY: properties points to a live structure and the resulting target is owned here.
        let target = match unsafe { self.factory.CreateDCRenderTarget(&properties) } {
            Ok(target) => target,
            Err(error) => {
                // SAFETY: restore and release the GDI objects created above before returning.
                unsafe {
                    let _ = SelectObject(dc, previous);
                    let _ = DeleteObject(bitmap.into());
                    let _ = DeleteDC(dc);
                }
                return Err(RenderError(format!("CreateDCRenderTarget: {error}")));
            }
        };
        let bounds = RECT {
            left: 0,
            top: 0,
            right: width,
            bottom: height,
        };
        // SAFETY: dc and bounds remain valid for the synchronous BindDC call.
        if let Err(error) = unsafe { target.BindDC(dc, &bounds) } {
            // SAFETY: restore and release the GDI objects created above before returning.
            unsafe {
                let _ = SelectObject(dc, previous);
                let _ = DeleteObject(bitmap.into());
                let _ = DeleteDC(dc);
            }
            return Err(RenderError(format!("BindDC: {error}")));
        }
        let brand_bitmap = match create_brand_bitmap(&target) {
            Ok(bitmap) => bitmap,
            Err(error) => {
                // SAFETY: release the newly allocated GDI objects when WIC cannot decode the icon.
                unsafe {
                    let _ = SelectObject(dc, previous);
                    let _ = DeleteObject(bitmap.into());
                    let _ = DeleteDC(dc);
                }
                return Err(error);
            }
        };
        self.release_surface();
        self.dc = dc;
        self.bitmap = bitmap;
        self.previous = previous;
        self.width = width;
        self.height = height;
        self.target = target;
        self.brand_bitmap = Some(brand_bitmap);
        Ok(())
    }

    pub fn draw(&mut self, projection: &Projection) -> Result<(), RenderError> {
        self.draw_result(projection)
    }

    fn draw_result(&mut self, projection: &Projection) -> Result<(), RenderError> {
        self.draw_attempt(projection, true)
    }

    fn draw_attempt(
        &mut self,
        projection: &Projection,
        allow_recreate: bool,
    ) -> Result<(), RenderError> {
        let panel = self.brush(color(1.0, 1.0, 1.0, 0.94))?;
        let card = self.brush(color(1.0, 1.0, 1.0, 0.72))?;
        let border = self.brush(color(0.72, 0.84, 0.65, 0.88))?;
        let text = self.brush(color(0.13, 0.14, 0.12, 1.0))?;
        let secondary = self.brush(color(0.42, 0.45, 0.41, 1.0))?;
        let accent = self.brush(color(0.56, 0.73, 0.47, 0.92))?;
        // SAFETY: the target is bound to the surface DC and all brushes cover the draw call.
        unsafe {
            self.target.BeginDraw();
            self.target.Clear(Some(&color(0.0, 0.0, 0.0, 0.0)));
        }
        let panel_rect = rounded(
            8.0,
            8.0,
            (self.width - 8) as f32,
            (self.height - 8) as f32,
            26.0,
        );
        // SAFETY: all pointers reference immutable stack values and live COM brushes.
        unsafe {
            self.target.FillRoundedRectangle(&panel_rect, &panel);
            self.target
                .DrawRoundedRectangle(&panel_rect, &border, 1.0, None);
        }
        self.draw_text(
            "GhostPin",
            rect(28.0, 24.0, (self.width - 80) as f32, 48.0),
            &self.title_format,
            &text,
        );
        if let Some(bitmap) = &self.brand_bitmap {
            let icon_rect = rect(28.0, 22.0, 52.0, 46.0);
            // SAFETY: the decoded brand bitmap is owned by this render target.
            unsafe {
                let _ = self.target.DrawBitmap(
                    bitmap,
                    Some(&icon_rect),
                    1.0,
                    D2D1_BITMAP_INTERPOLATION_MODE_LINEAR,
                    None,
                );
            }
        }
        self.draw_text(
            &format!("{} 个未完成", projection.items.len()),
            rect(28.0, 48.0, (self.width - 28) as f32, 70.0),
            &self.secondary_format,
            &secondary,
        );
        let clip = D2D_RECT_F {
            left: 20.0,
            top: 78.0,
            right: (self.width - 20) as f32,
            bottom: (self.height - 20) as f32,
        };
        unsafe {
            let _ = self
                .target
                .PushAxisAlignedClip(&clip, D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
        }
        let mut top = 82.0;
        if projection.doing.is_empty() == false {
            self.draw_text(
                "DOING",
                rect(28.0, top, (self.width - 28) as f32, top + 20.0),
                &self.section_format,
                &accent,
            );
            top += 24.0;
        }
        for item in &projection.doing {
            top = self.draw_card(item, top, &card, &border, &text, &secondary, &accent);
        }
        if projection.todo.is_empty() == false {
            self.draw_text(
                "TODO",
                rect(28.0, top, (self.width - 28) as f32, top + 20.0),
                &self.section_format,
                &secondary,
            );
            top += 24.0;
        }
        for item in &projection.todo {
            top = self.draw_card(item, top, &card, &border, &text, &secondary, &accent);
        }
        if projection.items.is_empty() {
            self.draw_text(
                "✓",
                rect(
                    28.0,
                    self.height as f32 / 2.0 - 32.0,
                    (self.width - 28) as f32,
                    self.height as f32 / 2.0 + 8.0,
                ),
                &self.title_format,
                &secondary,
            );
            self.draw_text(
                "没有未完成待办",
                rect(
                    28.0,
                    self.height as f32 / 2.0 + 8.0,
                    (self.width - 28) as f32,
                    self.height as f32 / 2.0 + 34.0,
                ),
                &self.empty_format,
                &secondary,
            );
        }
        unsafe {
            self.target.PopAxisAlignedClip();
        }
        match unsafe { self.target.EndDraw(None, None) } {
            Ok(()) => Ok(()),
            Err(error) if error.code() == D2DERR_RECREATE_TARGET && allow_recreate => {
                let target = unsafe {
                    self.factory
                        .CreateDCRenderTarget(&D2D1_RENDER_TARGET_PROPERTIES {
                            r#type: D2D1_RENDER_TARGET_TYPE_DEFAULT,
                            pixelFormat: D2D1_PIXEL_FORMAT {
                                format: DXGI_FORMAT_B8G8R8A8_UNORM,
                                alphaMode: D2D1_ALPHA_MODE_PREMULTIPLIED,
                            },
                            dpiX: 96.0,
                            dpiY: 96.0,
                            usage: D2D1_RENDER_TARGET_USAGE_NONE,
                            minLevel: D2D1_FEATURE_LEVEL_DEFAULT,
                        })
                }
                .map_err(|e| RenderError(format!("recreate render target: {e}")))?;
                let bounds = RECT {
                    left: 0,
                    top: 0,
                    right: self.width,
                    bottom: self.height,
                };
                unsafe {
                    target
                        .BindDC(self.dc, &bounds)
                        .map_err(|e| RenderError(format!("rebind render target: {e}")))?;
                }
                let brand_bitmap = create_brand_bitmap(&target)?;
                self.target = target;
                self.brand_bitmap = Some(brand_bitmap);
                self.draw_attempt(projection, false)
            }
            Err(error) if error.code() == D2DERR_RECREATE_TARGET => Err(RenderError(
                "EndDraw: render target recreation did not recover".into(),
            )),
            Err(error) => Err(RenderError(format!("EndDraw: {error}"))),
        }
    }

    fn brush(&self, value: D2D1_COLOR_F) -> Result<ID2D1Brush, RenderError> {
        let brush = unsafe { self.target.CreateSolidColorBrush(&value, None) }
            .map_err(|e| RenderError(format!("CreateSolidColorBrush: {e}")))?;
        brush
            .cast()
            .map_err(|e| RenderError(format!("cast solid brush: {e}")))
    }
    fn draw_text(
        &self,
        value: &str,
        layout: D2D_RECT_F,
        format: &IDWriteTextFormat,
        brush: &ID2D1Brush,
    ) {
        let wide = value.encode_utf16().collect::<Vec<_>>();
        unsafe {
            self.target.DrawText(
                &wide,
                format,
                &layout,
                brush,
                windows::Win32::Graphics::Direct2D::D2D1_DRAW_TEXT_OPTIONS_NONE,
                DWRITE_MEASURING_MODE_NATURAL,
            );
        }
    }
    fn draw_card(
        &self,
        item: &crate::core::Todo,
        top: f32,
        card: &ID2D1Brush,
        border: &ID2D1Brush,
        text: &ID2D1Brush,
        secondary: &ID2D1Brush,
        accent: &ID2D1Brush,
    ) -> f32 {
        let bottom = top + 72.0;
        let panel = rounded(24.0, top, (self.width - 24) as f32, bottom, 16.0);
        unsafe {
            self.target.FillRoundedRectangle(&panel, card);
            self.target.DrawRoundedRectangle(&panel, border, 1.0, None);
            let button = D2D1_ELLIPSE {
                point: windows_numerics::Vector2 {
                    X: 46.0,
                    Y: top + 36.0,
                },
                radiusX: 16.0,
                radiusY: 16.0,
            };
            self.target.FillEllipse(&button, accent);
        }
        self.draw_text(
            &item.title.chars().take(40).collect::<String>(),
            rect(70.0, top + 12.0, (self.width - 38) as f32, top + 34.0),
            &self.body_format,
            text,
        );
        let mut detail = priority_text(item.priority).to_string();
        if let Some(due) = item.due_at {
            detail.push_str("  ·  ");
            detail.push_str(&format_due(due));
        }
        if let Some(description) = &item.description {
            detail.push_str("  ·  ");
            detail.push_str(&description.chars().take(18).collect::<String>());
        }
        self.draw_text(
            &detail,
            rect(70.0, top + 40.0, (self.width - 38) as f32, top + 62.0),
            &self.secondary_format,
            secondary,
        );
        bottom + 8.0
    }

    pub fn hit_regions(&self, projection: &Projection) -> Vec<(String, RECT)> {
        let mut regions = Vec::new();
        let mut top = 82;
        if !projection.doing.is_empty() {
            top += 24;
        }
        for item in &projection.doing {
            let bottom = top + 72;
            regions.push((
                item.id.clone(),
                RECT {
                    left: self.width - 72,
                    top,
                    right: self.width - 24,
                    bottom,
                },
            ));
            top = bottom + 8;
        }
        if !projection.todo.is_empty() {
            top += 24;
        }
        for item in &projection.todo {
            let bottom = top + 72;
            regions.push((
                item.id.clone(),
                RECT {
                    left: self.width - 72,
                    top,
                    right: self.width - 24,
                    bottom,
                },
            ));
            top = bottom + 8;
        }
        regions
    }

    pub fn present(&self, hwnd: HWND, x: i32, y: i32, opacity: u8) -> Result<(), RenderError> {
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
        unsafe {
            let _ = ReleaseDC(None, screen);
        }
        result.map_err(|e| RenderError(format!("UpdateLayeredWindow: {e}")))
    }

    fn release_surface(&mut self) {
        if !self.dc.0.is_null() {
            unsafe {
                let _ = SelectObject(self.dc, self.previous);
                let _ = DeleteObject(self.bitmap.into());
                let _ = DeleteDC(self.dc);
            }
            self.dc = HDC::default();
            self.bitmap = HBITMAP::default();
            self.previous = HGDIOBJ::default();
        }
    }
}
impl Drop for HudSurface {
    fn drop(&mut self) {
        self.release_surface();
    }
}

fn create_format(
    factory: &IDWriteFactory,
    size: f32,
    weight: windows::Win32::Graphics::DirectWrite::DWRITE_FONT_WEIGHT,
) -> Result<IDWriteTextFormat, RenderError> {
    unsafe {
        factory.CreateTextFormat(
            w!("Segoe UI"),
            None,
            weight,
            DWRITE_FONT_STYLE_NORMAL,
            DWRITE_FONT_STRETCH_NORMAL,
            size,
            w!("zh-CN"),
        )
    }
    .map_err(|e| RenderError(format!("CreateTextFormat: {e}")))
    .and_then(|format| {
        unsafe { format.SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP) }
            .map_err(|e| RenderError(format!("SetWordWrapping: {e}")))?;
        Ok(format)
    })
}

fn create_brand_bitmap(target: &ID2D1DCRenderTarget) -> Result<ID2D1Bitmap, RenderError> {
    let factory: IWICImagingFactory =
        unsafe { CoCreateInstance(&CLSID_WICImagingFactory, None, CLSCTX_INPROC_SERVER) }
            .map_err(|e| RenderError(format!("CoCreateInstance(WIC): {e}")))?;
    let stream = unsafe { factory.CreateStream() }
        .map_err(|e| RenderError(format!("WIC CreateStream: {e}")))?;
    // SAFETY: the icon bytes are compile-time embedded and remain valid for this call.
    unsafe {
        stream
            .InitializeFromMemory(include_bytes!("../resources/GhostPin.ico"))
            .map_err(|e| RenderError(format!("WIC InitializeFromMemory: {e}")))?;
    }
    let stream: IStream = stream
        .cast()
        .map_err(|e| RenderError(format!("WIC stream cast: {e}")))?;
    let decoder = unsafe {
        factory.CreateDecoderFromStream(&stream, std::ptr::null(), WICDecodeMetadataCacheOnLoad)
    }
    .map_err(|e| RenderError(format!("WIC CreateDecoderFromStream: {e}")))?;
    let frame =
        unsafe { decoder.GetFrame(0) }.map_err(|e| RenderError(format!("WIC GetFrame: {e}")))?;
    let converter = unsafe { factory.CreateFormatConverter() }
        .map_err(|e| RenderError(format!("WIC CreateFormatConverter: {e}")))?;
    unsafe {
        converter
            .Initialize(
                &frame,
                &GUID_WICPixelFormat32bppPBGRA,
                WICBitmapDitherTypeNone,
                None::<&IWICPalette>,
                0.0,
                WICBitmapPaletteTypeCustom,
            )
            .map_err(|e| RenderError(format!("WIC format conversion: {e}")))?;
        target
            .CreateBitmapFromWicBitmap(&converter, None)
            .map_err(|e| RenderError(format!("D2D CreateBitmapFromWicBitmap: {e}")))
    }
}
fn rect(left: f32, top: f32, right: f32, bottom: f32) -> D2D_RECT_F {
    D2D_RECT_F {
        left,
        top,
        right,
        bottom,
    }
}
fn render_target_properties() -> D2D1_RENDER_TARGET_PROPERTIES {
    D2D1_RENDER_TARGET_PROPERTIES {
        r#type: D2D1_RENDER_TARGET_TYPE_DEFAULT,
        pixelFormat: D2D1_PIXEL_FORMAT {
            format: DXGI_FORMAT_B8G8R8A8_UNORM,
            alphaMode: D2D1_ALPHA_MODE_PREMULTIPLIED,
        },
        dpiX: 96.0,
        dpiY: 96.0,
        usage: D2D1_RENDER_TARGET_USAGE_NONE,
        minLevel: D2D1_FEATURE_LEVEL_DEFAULT,
    }
}
fn rounded(
    left: f32,
    top: f32,
    right: f32,
    bottom: f32,
    radius: f32,
) -> windows::Win32::Graphics::Direct2D::D2D1_ROUNDED_RECT {
    windows::Win32::Graphics::Direct2D::D2D1_ROUNDED_RECT {
        rect: rect(left, top, right, bottom),
        radiusX: radius,
        radiusY: radius,
    }
}
fn priority_text(priority: Priority) -> &'static str {
    match priority {
        Priority::High => "高",
        Priority::Medium => "中",
        Priority::Low => "低",
    }
}
fn format_due(value: SystemTime) -> String {
    let Ok(duration) = value.duration_since(UNIX_EPOCH) else {
        return "已到期".into();
    };
    let days = duration.as_secs() / 86_400;
    let (year, month, day) = civil_from_days(days as i64);
    let prefix = if value < SystemTime::now() {
        "逾期"
    } else {
        "到期"
    };
    format!("{prefix} {year:04}-{month:02}-{day:02}")
}
fn civil_from_days(mut days: i64) -> (i32, u32, u32) {
    days += 719_468;
    let era = if days >= 0 { days } else { days - 146_096 } / 146_097;
    let day_of_era = (days - era * 146_097) as u32;
    let year_of_era =
        (day_of_era - day_of_era / 1_460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let mut year = year_of_era as i32 + era as i32 * 400;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let month_part = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * month_part + 2) / 5 + 1;
    let month = if month_part < 10 {
        month_part + 3
    } else {
        month_part - 9
    };
    year += (month <= 2) as i32;
    (year, month, day)
}

#[allow(dead_code)]
fn _overdue_label(item: &crate::core::Todo) -> &'static str {
    if is_overdue(item, SystemTime::now()) {
        "逾期"
    } else {
        ""
    }
}
