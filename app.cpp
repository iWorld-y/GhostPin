#include "app.hpp"

#include "core.hpp"
#include "raii.hpp"
#include "repository.hpp"
#include "storage_paths.hpp"

#include <d2d1.h>
#include <dwrite.h>
#include <windowsx.h>
#include <wrl/client.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <memory>
#include <stdexcept>
#include <string>
#include <string_view>
#include <system_error>
#include <iterator>
#include <vector>

#pragma comment(lib, "d2d1.lib")
#pragma comment(lib, "dwrite.lib")
#pragma comment(lib, "user32.lib")

using Microsoft::WRL::ComPtr;

namespace ghostpin::app {
namespace {

constexpr wchar_t kHudWindowClass[] = L"GhostPin.Native.Hud";
constexpr UINT_PTR kReloadTimer = 1;
constexpr int kToggleHotkey = 1;
constexpr UINT kToggleModifiers = MOD_CONTROL | MOD_ALT | MOD_NOREPEAT;
constexpr UINT kToggleVirtualKey = 'G';
constexpr int kDefaultWidth = 360;
constexpr int kDefaultHeight = 460;
constexpr int kMinimumWidth = 300;
constexpr int kMinimumHeight = 280;
constexpr float kDpi = 96.0f;

std::wstring utf8ToWide(std::string_view value) {
    if (value.empty()) return {};
    const int length = MultiByteToWideChar(
        CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), nullptr, 0);
    if (length <= 0) throw std::system_error(
        static_cast<int>(GetLastError()), std::system_category(), "MultiByteToWideChar");
    std::wstring result(static_cast<std::size_t>(length), L'\0');
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
        static_cast<int>(value.size()), result.data(), length) != length) {
        throw std::system_error(
            static_cast<int>(GetLastError()), std::system_category(), "MultiByteToWideChar");
    }
    return result;
}

std::wstring priorityText(core::Priority priority) {
    switch (priority) {
    case core::Priority::High: return L"高";
    case core::Priority::Medium: return L"中";
    case core::Priority::Low: return L"低";
    }
    return {};
}

std::wstring formatDueAt(const std::optional<core::TimePoint>& due_at) {
    if (!due_at.has_value()) return {};
    const auto time = std::chrono::system_clock::to_time_t(due_at.value());
    tm local_time{};
    if (localtime_s(&local_time, &time) != 0) return {};
    wchar_t buffer[64]{};
    if (wcsftime(buffer, std::size(buffer), L"%m-%d %H:%M", &local_time) == 0) return {};
    return buffer;
}

class HudSurface final {
public:
    HudSurface() {
        const HRESULT result = D2D1CreateFactory(
            D2D1_FACTORY_TYPE_SINGLE_THREADED, IID_PPV_ARGS(&factory_));
        if (FAILED(result)) throw std::system_error(
            static_cast<int>(result), std::system_category(), "D2D1CreateFactory");
        const HRESULT write_result = DWriteCreateFactory(
            DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory), &write_factory_);
        if (FAILED(write_result)) throw std::system_error(
            static_cast<int>(write_result), std::system_category(), "DWriteCreateFactory");
        createTextFormats();
    }

    ~HudSurface() {
        releaseSurface();
    }

    void resize(int width, int height) {
        width_ = std::max(width, kMinimumWidth);
        height_ = std::max(height, kMinimumHeight);
        target_.Reset();
        releaseSurface();

        HDC screen = GetDC(nullptr);
        if (screen == nullptr) throw std::system_error(
            static_cast<int>(GetLastError()), std::system_category(), "GetDC");
        HDC dc = CreateCompatibleDC(screen);
        ReleaseDC(nullptr, screen);
        if (dc == nullptr) throw std::system_error(
            static_cast<int>(GetLastError()), std::system_category(), "CreateCompatibleDC");
        memory_dc_.reset(dc);

        BITMAPINFO info{};
        info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        info.bmiHeader.biWidth = width_;
        info.bmiHeader.biHeight = -height_;
        info.bmiHeader.biPlanes = 1;
        info.bmiHeader.biBitCount = 32;
        info.bmiHeader.biCompression = BI_RGB;
        void* pixels = nullptr;
        HBITMAP bitmap = CreateDIBSection(memory_dc_.get(), &info, DIB_RGB_COLORS, &pixels, nullptr, 0);
        if (bitmap == nullptr || pixels == nullptr) throw std::system_error(
            static_cast<int>(GetLastError()), std::system_category(), "CreateDIBSection");
        bitmap_.reset(bitmap);
        SelectObject(memory_dc_.get(), bitmap_.get());

        const auto properties = D2D1::RenderTargetProperties(
            D2D1_RENDER_TARGET_TYPE_DEFAULT,
            D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED),
            kDpi, kDpi);
        const HRESULT result = factory_->CreateDCRenderTarget(
            &properties, &target_);
        if (FAILED(result)) throw std::system_error(
            static_cast<int>(result), std::system_category(), "CreateDCRenderTarget");
        const RECT bounds{0, 0, width_, height_};
        const HRESULT bind_result = target_->BindDC(memory_dc_.get(), &bounds);
        if (FAILED(bind_result)) throw std::system_error(
            static_cast<int>(bind_result), std::system_category(), "ID2D1DCRenderTarget::BindDC");
    }

    void draw(const std::vector<core::Todo>& items, core::HudMode mode, double opacity) {
        if (!target_) resize(kDefaultWidth, kDefaultHeight);
        target_->BeginDraw();
        target_->Clear(D2D1::ColorF(0, 0.0f));

        ComPtr<ID2D1SolidColorBrush> border;
        ComPtr<ID2D1SolidColorBrush> panel;
        ComPtr<ID2D1SolidColorBrush> card;
        ComPtr<ID2D1SolidColorBrush> text;
        ComPtr<ID2D1SolidColorBrush> secondary;
        ComPtr<ID2D1SolidColorBrush> accent;
        const auto mode_color = mode == core::HudMode::Interactive
            ? D2D1::ColorF(0.90f, 0.64f, 0.16f, 0.92f)
            : D2D1::ColorF(0.56f, 0.73f, 0.47f, 0.92f);
        target_->CreateSolidColorBrush(D2D1::ColorF(1.0f, 1.0f, 1.0f, 0.94f), &panel);
        target_->CreateSolidColorBrush(D2D1::ColorF(1.0f, 1.0f, 1.0f, 0.72f), &card);
        target_->CreateSolidColorBrush(D2D1::ColorF(0.13f, 0.14f, 0.12f, 1.0f), &text);
        target_->CreateSolidColorBrush(D2D1::ColorF(0.42f, 0.45f, 0.41f, 1.0f), &secondary);
        target_->CreateSolidColorBrush(mode_color, &accent);
        target_->CreateSolidColorBrush(D2D1::ColorF(0.72f, 0.84f, 0.65f, 0.88f), &border);

        const auto panel_rect = D2D1::RectF(8.0f, 8.0f,
            static_cast<float>(width_ - 8), static_cast<float>(height_ - 8));
        target_->FillRoundedRectangle(
            D2D1::RoundedRect(panel_rect, 26.0f, 26.0f), panel.Get());
        target_->DrawRoundedRectangle(
            D2D1::RoundedRect(panel_rect, 26.0f, 26.0f), border.Get(), 1.0f);

        drawText(L"GhostPin", D2D1::RectF(28, 24, width_ - 80.0f, 48), title_format_.Get(), text.Get());
        const std::wstring count = std::to_wstring(items.size()) + L" 个未完成";
        drawText(count, D2D1::RectF(28, 48, width_ - 28.0f, 70), secondary_format_.Get(), secondary.Get());
        drawText(mode == core::HudMode::Interactive ? L"交互模式" : L"穿透模式",
            D2D1::RectF(28, height_ - 34.0f, width_ - 28.0f, height_ - 16.0f),
            secondary_format_.Get(), secondary.Get());

        target_->PushAxisAlignedClip(
            D2D1::RectF(20.0f, 78.0f, width_ - 20.0f, height_ - 44.0f),
            D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
        float top = 82.0f;
        bool has_doing = false;
        for (const auto& item : items) {
            if (item.status == core::Status::Doing) {
                has_doing = true;
                break;
            }
        }
        if (has_doing) {
            drawText(L"DOING", D2D1::RectF(28, top, width_ - 28.0f, top + 20),
                section_format_.Get(), accent.Get());
            top += 24.0f;
        }
        for (const auto& item : items) {
            if (item.status == core::Status::Doing) {
                top = drawCard(item, top, card.Get(), border.Get(), text.Get(), secondary.Get(), accent.Get());
            }
        }
        bool has_todo = false;
        for (const auto& item : items) {
            if (item.status == core::Status::Todo) {
                has_todo = true;
                break;
            }
        }
        if (has_todo) {
            drawText(L"TODO", D2D1::RectF(28, top, width_ - 28.0f, top + 20),
                section_format_.Get(), secondary.Get());
            top += 24.0f;
            for (const auto& item : items) {
                if (item.status == core::Status::Todo) {
                    top = drawCard(item, top, card.Get(), border.Get(), text.Get(), secondary.Get(), accent.Get());
                }
            }
        }
        if (items.empty()) {
            drawText(L"✓", D2D1::RectF(28, height_ / 2.0f - 32, width_ - 28.0f, height_ / 2.0f + 8),
                empty_mark_format_.Get(), secondary.Get());
            drawText(L"没有未完成待办", D2D1::RectF(28, height_ / 2.0f + 8, width_ - 28.0f, height_ / 2.0f + 34),
                empty_format_.Get(), secondary.Get());
        }
        target_->PopAxisAlignedClip();
        const HRESULT result = target_->EndDraw();
        if (FAILED(result) && result != D2DERR_RECREATE_TARGET) {
            throw std::system_error(static_cast<int>(result), std::system_category(), "ID2D1RenderTarget::EndDraw");
        }
        opacity_ = std::clamp(opacity, 0.5, 1.0);
    }

    HDC dc() const noexcept { return memory_dc_.get(); }
    SIZE size() const noexcept { return SIZE{width_, height_}; }
    BYTE opacity() const noexcept { return static_cast<BYTE>(std::lround(opacity_ * 255.0)); }

private:
    void releaseSurface() noexcept {
        if (memory_dc_) {
            SelectObject(memory_dc_.get(), GetStockObject(DEFAULT_BITMAP));
        }
        bitmap_.reset();
        memory_dc_.reset();
    }

    void createTextFormats() {
        const auto create = [&](ComPtr<IDWriteTextFormat>& format, float size, DWRITE_FONT_WEIGHT weight) {
            const HRESULT result = write_factory_->CreateTextFormat(
                L"Segoe UI", nullptr, weight, DWRITE_FONT_STYLE_NORMAL,
                DWRITE_FONT_STRETCH_NORMAL, size, L"zh-CN", &format);
            if (FAILED(result)) throw std::system_error(
                static_cast<int>(result), std::system_category(), "IDWriteFactory::CreateTextFormat");
            format->SetWordWrapping(DWRITE_WORD_WRAPPING_WRAP);
        };
        create(title_format_, 16.0f, DWRITE_FONT_WEIGHT_SEMI_BOLD);
        create(section_format_, 11.0f, DWRITE_FONT_WEIGHT_SEMI_BOLD);
        create(body_format_, 14.0f, DWRITE_FONT_WEIGHT_SEMI_BOLD);
        create(secondary_format_, 11.0f, DWRITE_FONT_WEIGHT_NORMAL);
        create(empty_format_, 13.0f, DWRITE_FONT_WEIGHT_NORMAL);
        create(empty_mark_format_, 28.0f, DWRITE_FONT_WEIGHT_NORMAL);
    }

    void drawText(const std::wstring& value, const D2D1_RECT_F& rect,
        IDWriteTextFormat* format, ID2D1Brush* brush) {
        target_->DrawTextW(value.c_str(), static_cast<UINT32>(value.size()), format, &rect, brush);
    }

    float drawCard(const core::Todo& item, float top, ID2D1Brush* card,
        ID2D1Brush* border, ID2D1Brush* text, ID2D1Brush* secondary, ID2D1Brush* accent) {
        const float bottom = top + 72.0f;
        const auto rect = D2D1::RoundedRect(D2D1::RectF(24, top, width_ - 24.0f, bottom), 16.0f, 16.0f);
        target_->FillRoundedRectangle(rect, card);
        target_->DrawRoundedRectangle(rect, border, 1.0f);
        const auto circle = D2D1::Ellipse(D2D1::Point2F(48, top + 36), 14, 14);
        target_->DrawEllipse(circle, accent, 1.0f);
        drawText(utf8ToWide(item.title), D2D1::RectF(70, top + 12, width_ - 38.0f, top + 34),
            body_format_.Get(), text);
        std::wstring detail = priorityText(item.priority);
        const auto due = formatDueAt(item.due_at);
        if (!due.empty()) detail += L"  ·  " + due;
        drawText(detail, D2D1::RectF(70, top + 40, width_ - 38.0f, top + 62),
            secondary_format_.Get(), secondary);
        return bottom + 8.0f;
    }

    ComPtr<ID2D1Factory> factory_;
    ComPtr<IDWriteFactory> write_factory_;
    ComPtr<ID2D1DCRenderTarget> target_;
    ComPtr<IDWriteTextFormat> title_format_;
    ComPtr<IDWriteTextFormat> section_format_;
    ComPtr<IDWriteTextFormat> body_format_;
    ComPtr<IDWriteTextFormat> secondary_format_;
    ComPtr<IDWriteTextFormat> empty_format_;
    ComPtr<IDWriteTextFormat> empty_mark_format_;
    platform::unique_device_context memory_dc_;
    platform::unique_gdi_object bitmap_;
    int width_{0};
    int height_{0};
    double opacity_{1.0};
};

class NativeHud final {
public:
    NativeHud(HINSTANCE instance, storage::TodoRepository& repository)
        : instance_(instance), repository_(repository) {
        const int width = kDefaultWidth;
        const int height = kDefaultHeight;
        const int left = (GetSystemMetrics(SM_CXSCREEN) - width) / 2;
        const int top = (GetSystemMetrics(SM_CYSCREEN) - height) / 2;
        hwnd_ = CreateWindowExW(
            WS_EX_TOOLWINDOW | WS_EX_LAYERED | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT,
            kHudWindowClass, L"GhostPin", WS_POPUP,
            left, top, width, height, nullptr, nullptr, instance_, this);
        if (hwnd_ == nullptr) throw std::system_error(
            static_cast<int>(GetLastError()), std::system_category(), "CreateWindowExW");
        surface_.resize(width, height);
        if (!RegisterHotKey(hwnd_, kToggleHotkey, kToggleModifiers, kToggleVirtualKey)) {
            hotkey_registered_ = false;
        } else {
            hotkey_registered_ = true;
        }
        repository_.load();
        render();
        SetTimer(hwnd_, kReloadTimer, 500, nullptr);
        SetWindowPos(hwnd_, HWND_TOPMOST, left, top, width, height,
            SWP_NOACTIVATE | SWP_SHOWWINDOW);
    }

    ~NativeHud() {
        if (hwnd_ != nullptr) {
            KillTimer(hwnd_, kReloadTimer);
            if (hotkey_registered_) UnregisterHotKey(hwnd_, kToggleHotkey);
            DestroyWindow(hwnd_);
            hwnd_ = nullptr;
        }
    }

    HWND hwnd() const noexcept { return hwnd_; }

    static LRESULT CALLBACK windowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
        auto* self = reinterpret_cast<NativeHud*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
        if (message == WM_NCCREATE) {
            const auto* create = reinterpret_cast<const CREATESTRUCTW*>(lparam);
            self = static_cast<NativeHud*>(create->lpCreateParams);
            SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        }
        return self == nullptr ? DefWindowProcW(hwnd, message, wparam, lparam)
            : self->handleMessage(hwnd, message, wparam, lparam);
    }

private:
    LRESULT handleMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
        switch (message) {
        case WM_TIMER:
            if (wparam == kReloadTimer) {
                repository_.load();
                render();
            }
            return 0;
        case WM_SIZE:
            if (hwnd_ != nullptr && LOWORD(lparam) > 0 && HIWORD(lparam) > 0) {
                surface_.resize(LOWORD(lparam), HIWORD(lparam));
                render();
            }
            return 0;
        case WM_HOTKEY:
            if (wparam == kToggleHotkey) toggleMode();
            return 0;
        case WM_NCHITTEST:
            if (!interactive_) return HTTRANSPARENT;
            return hitTest(hwnd, lparam);
        case WM_LBUTTONUP:
            if (interactive_) {
                const POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
                const auto found = std::find_if(buttons_.begin(), buttons_.end(),
                    [&](const auto& button) { return PtInRect(&button.bounds, point) != FALSE; });
                if (found != buttons_.end()) {
                    repository_.advanceById(found->id, std::chrono::system_clock::now());
                    render();
                }
            }
            return 0;
        case WM_ERASEBKGND:
            return 1;
        case WM_DESTROY:
            PostQuitMessage(0);
            return 0;
        default:
            return DefWindowProcW(hwnd, message, wparam, lparam);
        }
    }

    LRESULT hitTest(HWND hwnd, LPARAM lparam) const {
        POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        ScreenToClient(hwnd, &point);
        const auto button = std::find_if(buttons_.begin(), buttons_.end(),
            [&](const auto& item) { return PtInRect(&item.bounds, point) != FALSE; });
        if (button != buttons_.end()) return HTCLIENT;
        RECT client{};
        GetClientRect(hwnd, &client);
        constexpr LONG edge = 8;
        const bool left = point.x < client.left + edge;
        const bool right = point.x >= client.right - edge;
        const bool top = point.y < client.top + edge;
        const bool bottom = point.y >= client.bottom - edge;
        if (top && left) return HTTOPLEFT;
        if (top && right) return HTTOPRIGHT;
        if (bottom && left) return HTBOTTOMLEFT;
        if (bottom && right) return HTBOTTOMRIGHT;
        if (top) return HTTOP;
        if (bottom) return HTBOTTOM;
        if (left) return HTLEFT;
        if (right) return HTRIGHT;
        return HTCAPTION;
    }

    void toggleMode() {
        interactive_ = !interactive_;
        LONG_PTR style = GetWindowLongPtrW(hwnd_, GWL_EXSTYLE);
        if (interactive_) {
            style &= ~(WS_EX_TRANSPARENT | WS_EX_NOACTIVATE);
        } else {
            style |= WS_EX_TRANSPARENT | WS_EX_NOACTIVATE;
        }
        SetWindowLongPtrW(hwnd_, GWL_EXSTYLE, style);
        SetWindowPos(hwnd_, HWND_TOPMOST, 0, 0, 0, 0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_FRAMECHANGED |
            (interactive_ ? 0 : SWP_NOACTIVATE));
        if (interactive_) {
            SetForegroundWindow(hwnd_);
            SetFocus(hwnd_);
        } else {
            SetWindowPos(hwnd_, HWND_TOPMOST, 0, 0, 0, 0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        }
        render();
    }

    void render() {
        const auto now = std::chrono::system_clock::now();
        core::ProjectionOptions options;
        options.scope = core::HudScope::All;
        options.max_count = 8;
        options.now = now;
        options.today_start = now - std::chrono::hours(24);
        const auto projection = core::project(repository_.snapshot(), options);
        buttons_.clear();
        float button_top = 82.0f;
        const bool has_doing = std::any_of(projection.items.begin(), projection.items.end(),
            [](const auto& item) { return item.status == core::Status::Doing; });
        const bool has_todo = std::any_of(projection.items.begin(), projection.items.end(),
            [](const auto& item) { return item.status == core::Status::Todo; });
        if (has_doing) button_top += 24.0f;
        for (const auto& item : projection.items) {
            if (item.status == core::Status::Doing) {
                buttons_.push_back(ButtonRegion{
                    item.id,
                    RECT{34, static_cast<LONG>(button_top + 22), 62,
                        static_cast<LONG>(button_top + 50)}});
                button_top += 80.0f;
            }
        }
        if (has_todo) button_top += 24.0f;
        for (const auto& item : projection.items) {
            if (item.status == core::Status::Todo) {
                buttons_.push_back(ButtonRegion{
                    item.id,
                    RECT{34, static_cast<LONG>(button_top + 22), 62,
                        static_cast<LONG>(button_top + 50)}});
                button_top += 80.0f;
            }
        }
        surface_.draw(projection.items, interactive_
            ? core::HudMode::Interactive : core::HudMode::Passthrough, 1.0);
        POINT position{};
        RECT window_rect{};
        GetWindowRect(hwnd_, &window_rect);
        position.x = window_rect.left;
        position.y = window_rect.top;
        SIZE size = surface_.size();
        BLENDFUNCTION blend{AC_SRC_OVER, 0, surface_.opacity(), AC_SRC_ALPHA};
        POINT source{0, 0};
        if (!UpdateLayeredWindow(hwnd_, nullptr, &position, &size, surface_.dc(),
            &source, 0, &blend, ULW_ALPHA)) {
            throw std::system_error(static_cast<int>(GetLastError()),
                std::system_category(), "UpdateLayeredWindow");
        }
    }

    HINSTANCE instance_{nullptr};
    storage::TodoRepository& repository_;
    HWND hwnd_{nullptr};
    bool interactive_{false};
    bool hotkey_registered_{false};
    struct ButtonRegion {
        std::string id;
        RECT bounds{};
    };
    std::vector<ButtonRegion> buttons_;
    HudSurface surface_;
};

} // namespace

int Controller::run(HINSTANCE instance, int) const {
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    const auto paths = storage::resolveLocalAppData();
    storage::ensureDirectory(paths);
    storage::TodoRepository repository(paths.todos_file);

    WNDCLASSEXW specification{};
    specification.cbSize = sizeof(WNDCLASSEXW);
    specification.style = CS_HREDRAW | CS_VREDRAW;
    specification.lpfnWndProc = &NativeHud::windowProc;
    specification.hInstance = instance;
    specification.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    specification.hIcon = LoadIconW(instance, MAKEINTRESOURCEW(101));
    specification.hIconSm = specification.hIcon;
    specification.lpszClassName = kHudWindowClass;
    platform::registered_window_class window_class(instance, specification);

    NativeHud hud(instance, repository);
    MSG message{};
    while (GetMessageW(&message, nullptr, 0, 0) > 0) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
    return static_cast<int>(message.wParam);
}

} // namespace ghostpin::app
