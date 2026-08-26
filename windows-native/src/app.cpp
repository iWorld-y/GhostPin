#include "app.hpp"

#include "core.hpp"
#include "codec.hpp"
#include "atomic_file.hpp"
#include "raii.hpp"
#include "repository.hpp"
#include "storage_paths.hpp"

#include <d2d1.h>
#include <dwrite.h>
#include <shellapi.h>
#include <shellscalingapi.h>
#include <commctrl.h>
#include <winreg.h>
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
#include <fstream>
#include <filesystem>
#include <vector>

#pragma comment(lib, "d2d1.lib")
#pragma comment(lib, "dwrite.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "shcore.lib")

using Microsoft::WRL::ComPtr;

namespace ghostpin::app {
namespace {

class SettingsWindow;

constexpr wchar_t kHudWindowClass[] = L"GhostPin.Native.Hud";
constexpr UINT_PTR kReloadTimer = 1;
constexpr int kToggleHotkey = 1;
constexpr UINT kTrayMessage = WM_APP + 1;
constexpr UINT kTrayToggleVisibility = 1001;
constexpr UINT kTrayToggleMode = 1002;
constexpr UINT kTraySettings = 1003;
constexpr UINT kTrayExit = 1004;
constexpr int kDefaultWidth = 360;
constexpr int kDefaultHeight = 460;
constexpr int kMinimumWidth = 300;
constexpr int kMinimumHeight = 280;
constexpr wchar_t kNativeMutexName[] = L"Local\\GhostPin.Native.App";

void requireHresult(HRESULT result, const char* operation) {
    if (FAILED(result)) {
        throw std::system_error(static_cast<int>(result), std::system_category(), operation);
    }
}

std::string readUtf8File(const std::filesystem::path& path) {
    std::ifstream stream(path, std::ios::binary);
    if (!stream) throw std::runtime_error("无法读取 GhostPin 设置文件");
    return {std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>()};
}

std::uint64_t todoFileStamp(const std::filesystem::path& path) noexcept {
    WIN32_FILE_ATTRIBUTE_DATA attributes{};
    if (!GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &attributes)) return 0;
    ULARGE_INTEGER value{};
    value.LowPart = attributes.ftLastWriteTime.dwLowDateTime;
    value.HighPart = attributes.ftLastWriteTime.dwHighDateTime;
    return value.QuadPart;
}

bool setLaunchAtLogin(HINSTANCE instance, bool enabled) {
    HKEY key = nullptr;
    const LONG opened = RegOpenKeyExW(HKEY_CURRENT_USER,
        L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0,
        KEY_SET_VALUE, &key);
    if (opened != ERROR_SUCCESS) return false;
    const auto close = [&] { RegCloseKey(key); };
    if (!enabled) {
        const LONG removed = RegDeleteValueW(key, L"GhostPin");
        close();
        return removed == ERROR_SUCCESS || removed == ERROR_FILE_NOT_FOUND;
    }
    wchar_t executable[MAX_PATH * 4]{};
    const DWORD length = GetModuleFileNameW(instance, executable,
        static_cast<DWORD>(std::size(executable)));
    if (length == 0 || length >= static_cast<DWORD>(std::size(executable))) {
        close();
        return false;
    }
    const std::wstring command = std::wstring(L"\"") + executable + L"\"";
    const DWORD bytes = static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t));
    const LONG written = RegSetValueExW(key, L"GhostPin", 0, REG_SZ,
        reinterpret_cast<const BYTE*>(command.c_str()), bytes);
    close();
    return written == ERROR_SUCCESS;
}

core::HudSettings loadSettings(const std::filesystem::path& path) {
    core::HudSettings defaults = core::normalize(core::HudSettings{});
    std::error_code error;
    if (!std::filesystem::exists(path, error)) {
        storage::writeAtomically(path, codec::encodeSettings(defaults));
        return defaults;
    }
    try {
        return codec::decodeSettings(readUtf8File(path));
    } catch (const std::exception& exception) {
        OutputDebugStringA((std::string("GhostPin: 设置文件无效，使用默认值: ") +
            exception.what() + "\n").c_str());
        return defaults;
    }
}

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

std::string wideToUtf8(std::wstring_view value) {
    if (value.empty()) return {};
    const int source_length = static_cast<int>(value.size());
    const int length = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
        value.data(), source_length, nullptr, 0, nullptr, nullptr);
    if (length <= 0) throw std::system_error(static_cast<int>(GetLastError()),
        std::system_category(), "WideCharToMultiByte");
    std::string result(static_cast<std::size_t>(length), '\0');
    if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(), source_length,
        result.data(), length, nullptr, nullptr) != length) {
        throw std::system_error(static_cast<int>(GetLastError()),
            std::system_category(), "WideCharToMultiByte");
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

core::TimePoint localDayStart(std::chrono::system_clock::time_point now) {
    const auto time = std::chrono::system_clock::to_time_t(now);
    tm local_time{};
    if (localtime_s(&local_time, &time) != 0) return core::TimePoint{now.time_since_epoch()};
    local_time.tm_hour = 0;
    local_time.tm_min = 0;
    local_time.tm_sec = 0;
    const auto midnight = std::mktime(&local_time);
    if (midnight == static_cast<std::time_t>(-1)) {
        return core::TimePoint{now.time_since_epoch()};
    }
    return core::TimePoint{
        std::chrono::duration_cast<core::TimePoint::duration>(
            std::chrono::system_clock::from_time_t(midnight).time_since_epoch())};
}

struct MonitorMatch {
    std::string wanted_id;
    RECT work{};
    HMONITOR monitor{nullptr};
    bool found{false};
};

BOOL CALLBACK findMonitorForPlacement(HMONITOR monitor, HDC, LPRECT, LPARAM data) {
    auto* match = reinterpret_cast<MonitorMatch*>(data);
    MONITORINFOEXW info{};
    info.cbSize = sizeof(info);
    if (!GetMonitorInfoW(monitor, reinterpret_cast<MONITORINFO*>(&info))) return TRUE;
    const bool primary = (info.dwFlags & MONITORINFOF_PRIMARY) != 0;
    const bool selected = match->wanted_id.empty()
        ? primary : wideToUtf8(info.szDevice) == match->wanted_id;
    if (selected) {
        match->work = info.rcWork;
        match->monitor = monitor;
        match->found = true;
        return FALSE;
    }
    return TRUE;
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

    void resize(int logical_width, int logical_height, UINT dpi = 96) {
        dpi_ = std::max(dpi, 96u);
        logical_width_ = std::max(logical_width, kMinimumWidth);
        logical_height_ = std::max(logical_height, kMinimumHeight);
        pixel_width_ = std::max(1, static_cast<int>(std::lround(
            logical_width_ * static_cast<double>(dpi_) / 96.0)));
        pixel_height_ = std::max(1, static_cast<int>(std::lround(
            logical_height_ * static_cast<double>(dpi_) / 96.0)));
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
        info.bmiHeader.biWidth = pixel_width_;
        info.bmiHeader.biHeight = -pixel_height_;
        info.bmiHeader.biPlanes = 1;
        info.bmiHeader.biBitCount = 32;
        info.bmiHeader.biCompression = BI_RGB;
        void* pixels = nullptr;
        HBITMAP bitmap = CreateDIBSection(memory_dc_.get(), &info, DIB_RGB_COLORS, &pixels, nullptr, 0);
        if (bitmap == nullptr || pixels == nullptr) throw std::system_error(
            static_cast<int>(GetLastError()), std::system_category(), "CreateDIBSection");
        bitmap_.reset(bitmap);
        const HGDIOBJ previous = SelectObject(memory_dc_.get(), bitmap_.get());
        if (previous == nullptr || previous == HGDI_ERROR) {
            bitmap_.reset();
            throw std::system_error(
                static_cast<int>(GetLastError()), std::system_category(), "SelectObject");
        }
        previous_bitmap_ = previous;

        const auto properties = D2D1::RenderTargetProperties(
            D2D1_RENDER_TARGET_TYPE_DEFAULT,
            D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED),
            static_cast<float>(dpi_), static_cast<float>(dpi_));
        const HRESULT result = factory_->CreateDCRenderTarget(&properties, &target_);
        requireHresult(result, "CreateDCRenderTarget");
        const RECT bounds{0, 0, pixel_width_, pixel_height_};
        const HRESULT bind_result = target_->BindDC(memory_dc_.get(), &bounds);
        requireHresult(bind_result, "ID2D1DCRenderTarget::BindDC");
    }

    bool draw(const std::vector<core::Todo>& items, core::HudMode mode, double opacity,
        int attempt = 0) {
        if (!target_) resize(logical_width_ > 0 ? logical_width_ : kDefaultWidth,
            logical_height_ > 0 ? logical_height_ : kDefaultHeight, dpi_);
        opacity_ = std::clamp(opacity, 0.5, 1.0);
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
        requireHresult(target_->CreateSolidColorBrush(
            D2D1::ColorF(1.0f, 1.0f, 1.0f, 0.94f), &panel), "CreateSolidColorBrush(panel)");
        requireHresult(target_->CreateSolidColorBrush(
            D2D1::ColorF(1.0f, 1.0f, 1.0f, 0.72f), &card), "CreateSolidColorBrush(card)");
        requireHresult(target_->CreateSolidColorBrush(
            D2D1::ColorF(0.13f, 0.14f, 0.12f, 1.0f), &text), "CreateSolidColorBrush(text)");
        requireHresult(target_->CreateSolidColorBrush(
            D2D1::ColorF(0.42f, 0.45f, 0.41f, 1.0f), &secondary), "CreateSolidColorBrush(secondary)");
        requireHresult(target_->CreateSolidColorBrush(
            mode_color, &accent), "CreateSolidColorBrush(accent)");
        requireHresult(target_->CreateSolidColorBrush(
            D2D1::ColorF(0.72f, 0.84f, 0.65f, 0.88f), &border), "CreateSolidColorBrush(border)");

        const auto panel_rect = D2D1::RectF(8.0f, 8.0f,
            static_cast<float>(logical_width_ - 8), static_cast<float>(logical_height_ - 8));
        target_->FillRoundedRectangle(
            D2D1::RoundedRect(panel_rect, 26.0f, 26.0f), panel.Get());
        target_->DrawRoundedRectangle(
            D2D1::RoundedRect(panel_rect, 26.0f, 26.0f), border.Get(), 1.0f);

        drawText(L"GhostPin", D2D1::RectF(28, 24, logical_width_ - 80.0f, 48), title_format_.Get(), text.Get());
        const std::wstring count = std::to_wstring(items.size()) + L" 个未完成";
        drawText(count, D2D1::RectF(28, 48, logical_width_ - 28.0f, 70), secondary_format_.Get(), secondary.Get());
        target_->PushAxisAlignedClip(
            D2D1::RectF(20.0f, 78.0f, logical_width_ - 20.0f, logical_height_ - 20.0f),
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
            drawText(L"DOING", D2D1::RectF(28, top, logical_width_ - 28.0f, top + 20),
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
            drawText(L"TODO", D2D1::RectF(28, top, logical_width_ - 28.0f, top + 20),
                section_format_.Get(), secondary.Get());
            top += 24.0f;
            for (const auto& item : items) {
                if (item.status == core::Status::Todo) {
                    top = drawCard(item, top, card.Get(), border.Get(), text.Get(), secondary.Get(), accent.Get());
                }
            }
        }
        if (items.empty()) {
            drawText(L"✓", D2D1::RectF(28, logical_height_ / 2.0f - 32, logical_width_ - 28.0f, logical_height_ / 2.0f + 8),
                empty_mark_format_.Get(), secondary.Get());
            drawText(L"没有未完成待办", D2D1::RectF(28, logical_height_ / 2.0f + 8, logical_width_ - 28.0f, logical_height_ / 2.0f + 34),
                empty_format_.Get(), secondary.Get());
        }
        target_->PopAxisAlignedClip();
        const HRESULT result = target_->EndDraw();
        if (result == D2DERR_RECREATE_TARGET) {
            target_.Reset();
            releaseSurface();
            if (attempt == 0) {
                resize(logical_width_, logical_height_, dpi_);
                return draw(items, mode, opacity_, 1);
            }
            return false;
        }
        requireHresult(result, "ID2D1RenderTarget::EndDraw");
        return true;
    }

    HDC dc() const noexcept { return memory_dc_.get(); }
    SIZE size() const noexcept { return SIZE{pixel_width_, pixel_height_}; }
    int logicalWidth() const noexcept { return logical_width_; }
    int logicalHeight() const noexcept { return logical_height_; }
    float scale() const noexcept { return static_cast<float>(dpi_) / 96.0f; }
    BYTE opacity() const noexcept { return static_cast<BYTE>(std::lround(opacity_ * 255.0)); }

private:
    void releaseSurface() noexcept {
        if (memory_dc_ && previous_bitmap_ != nullptr) {
            SelectObject(memory_dc_.get(), previous_bitmap_);
        }
        previous_bitmap_ = nullptr;
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
        const auto rect = D2D1::RoundedRect(D2D1::RectF(24, top, logical_width_ - 24.0f, bottom), 16.0f, 16.0f);
        target_->FillRoundedRectangle(rect, card);
        target_->DrawRoundedRectangle(rect, border, 1.0f);
        const auto circle = D2D1::Ellipse(D2D1::Point2F(48, top + 36), 14, 14);
        target_->DrawEllipse(circle, accent, 1.0f);
        drawText(utf8ToWide(item.title), D2D1::RectF(70, top + 12, logical_width_ - 38.0f, top + 34),
            body_format_.Get(), text);
        std::wstring detail = priorityText(item.priority);
        const auto due = formatDueAt(item.due_at);
        if (!due.empty()) detail += L"  ·  " + due;
        drawText(detail, D2D1::RectF(70, top + 40, logical_width_ - 38.0f, top + 62),
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
    HGDIOBJ previous_bitmap_{nullptr};
    int logical_width_{0};
    int logical_height_{0};
    int pixel_width_{0};
    int pixel_height_{0};
    UINT dpi_{96};
    double opacity_{1.0};
};

class NativeHud final {
public:
    NativeHud(HINSTANCE instance, storage::TodoRepository& repository, core::HudSettings settings)
        : instance_(instance), repository_(repository), settings_(std::move(settings)),
          settings_path_(repository.filePath().parent_path() / L"native-settings.json") {
        interactive_ = settings_.mode == core::HudMode::Interactive;
        const auto placement = core::normalize(settings_.placement);
        const int width = std::max(kMinimumWidth,
            static_cast<int>(std::lround(placement.logical_width)));
        const int height = std::max(kMinimumHeight,
            static_cast<int>(std::lround(placement.logical_height)));
        const HWND hwnd = CreateWindowExW(
            WS_EX_TOOLWINDOW | WS_EX_LAYERED | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT,
            kHudWindowClass, L"GhostPin", WS_POPUP | WS_THICKFRAME,
            0, 0, width, height, nullptr, nullptr, instance_, this);
        if (hwnd == nullptr) throw std::system_error(
            static_cast<int>(GetLastError()), std::system_category(), "CreateWindowExW");
        window_.reset(hwnd);
        try {
            if (interactive_) {
                LONG_PTR style = GetWindowLongPtrW(window_.get(), GWL_EXSTYLE);
                SetWindowLongPtrW(window_.get(), GWL_EXSTYLE,
                    style & ~(WS_EX_TRANSPARENT | WS_EX_NOACTIVATE));
            }
            const UINT dpi = GetDpiForWindow(window_.get());
            surface_.resize(width, height, dpi == 0 ? 96 : dpi);
            addTrayIcon();
            if (settings_.hotkey_enabled && !RegisterHotKey(window_.get(), kToggleHotkey,
                settings_.hotkey_modifiers | MOD_NOREPEAT, settings_.hotkey_key)) {
                OutputDebugStringW(L"GhostPin: Ctrl+Alt+G 注册失败，交互模式不可用。\n");
            } else if (settings_.hotkey_enabled) {
                hotkey_registered_ = true;
            }
            repository_.load();
            last_todo_stamp_ = todoFileStamp(repository_.filePath());
            todo_stamp_initialized_ = true;
            render();
            if (SetTimer(window_.get(), kReloadTimer, 500, nullptr) == 0) {
                throw std::system_error(static_cast<int>(GetLastError()),
                    std::system_category(), "SetTimer");
            }
            timer_set_ = true;
            const SIZE pixel_size = surface_.size();
            const POINT position = restorePosition(pixel_size);
            if (!SetWindowPos(window_.get(), settings_.topmost ? HWND_TOPMOST : HWND_NOTOPMOST,
                position.x, position.y, pixel_size.cx, pixel_size.cy,
                SWP_NOACTIVATE | (settings_.visible ? SWP_SHOWWINDOW : SWP_HIDEWINDOW))) {
                throw std::system_error(static_cast<int>(GetLastError()),
                    std::system_category(), "SetWindowPos");
            }
        } catch (...) {
            cleanup();
            throw;
        }
    }

    ~NativeHud() {
        cleanup();
    }

    HWND hwnd() const noexcept { return window_.get(); }

    static LRESULT CALLBACK windowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
        try {
            if (message == WM_NCCREATE) {
                const auto* create = reinterpret_cast<const CREATESTRUCTW*>(lparam);
                auto* self = static_cast<NativeHud*>(create->lpCreateParams);
                SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
                return TRUE;
            }
            auto* self = reinterpret_cast<NativeHud*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
            if (self == nullptr) return DefWindowProcW(hwnd, message, wparam, lparam);
            if (message == WM_NCDESTROY) {
                const LRESULT result = DefWindowProcW(hwnd, message, wparam, lparam);
                SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
                return result;
            }
            return self->handleMessage(hwnd, message, wparam, lparam);
        } catch (const std::exception& error) {
            OutputDebugStringA((std::string("GhostPin.Native: ") + error.what() + "\n").c_str());
            PostMessageW(hwnd, WM_CLOSE, 0, 0);
            return 0;
        } catch (...) {
            OutputDebugStringW(L"GhostPin.Native: 未知窗口异常。\n");
            PostMessageW(hwnd, WM_CLOSE, 0, 0);
            return 0;
        }
    }

private:
    LRESULT handleMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
        switch (message) {
        case WM_TIMER:
            if (wparam == kReloadTimer) {
                const auto stamp = todoFileStamp(repository_.filePath());
                if (needs_render_ || !todo_stamp_initialized_ || stamp != last_todo_stamp_) {
                    repository_.load();
                    last_todo_stamp_ = stamp;
                    todo_stamp_initialized_ = true;
                    render();
                }
            }
            return 0;
        case WM_SIZE:
            if (window_ && LOWORD(lparam) > 0 && HIWORD(lparam) > 0) {
                const UINT dpi = std::max(GetDpiForWindow(window_.get()), 96u);
                const int logical_width = std::max(kMinimumWidth, static_cast<int>(std::lround(
                    LOWORD(lparam) * 96.0 / dpi)));
                const int logical_height = std::max(kMinimumHeight, static_cast<int>(std::lround(
                    HIWORD(lparam) * 96.0 / dpi)));
                surface_.resize(logical_width, logical_height, dpi);
                settings_.placement.logical_width = logical_width;
                settings_.placement.logical_height = logical_height;
                render();
            }
            return 0;
        case WM_EXITSIZEMOVE:
            capturePlacement();
            return 0;
        case WM_NCCALCSIZE:
            return 0;
        case WM_GETMINMAXINFO: {
            auto* limits = reinterpret_cast<MINMAXINFO*>(lparam);
            if (limits != nullptr) {
                const UINT dpi = std::max(GetDpiForWindow(window_.get()), 96u);
                limits->ptMinTrackSize.x = static_cast<LONG>(std::lround(
                    kMinimumWidth * dpi / 96.0));
                limits->ptMinTrackSize.y = static_cast<LONG>(std::lround(
                    kMinimumHeight * dpi / 96.0));
            }
            return 0;
        }
        case WM_DPICHANGED: {
            const auto* suggested = reinterpret_cast<const RECT*>(lparam);
            if (suggested != nullptr && window_) {
                settings_.placement.dpi = HIWORD(wparam);
                if (!SetWindowPos(window_.get(), settings_.topmost ? HWND_TOPMOST : HWND_NOTOPMOST,
                    suggested->left, suggested->top,
                    suggested->right - suggested->left,
                    suggested->bottom - suggested->top,
                    SWP_NOACTIVATE | SWP_NOOWNERZORDER)) {
                    throw std::system_error(static_cast<int>(GetLastError()),
                        std::system_category(), "SetWindowPos(WM_DPICHANGED)");
                }
            }
            return 0;
        }
        case WM_HOTKEY:
            if (wparam == kToggleHotkey) toggleMode();
            return 0;
        case kTrayMessage:
            if (LOWORD(lparam) == WM_LBUTTONUP || LOWORD(lparam) == NIN_SELECT) {
                toggleVisibility();
            } else if (LOWORD(lparam) == WM_RBUTTONUP || LOWORD(lparam) == WM_CONTEXTMENU) {
                showTrayMenu();
            }
            return 0;
        case WM_COMMAND:
            switch (LOWORD(wparam)) {
            case kTrayToggleVisibility:
                toggleVisibility();
                return 0;
            case kTrayToggleMode:
                toggleMode();
                return 0;
            case kTraySettings:
                showSettings();
                return 0;
            case kTrayExit:
                DestroyWindow(window_.get());
                return 0;
            default:
                break;
            }
            return DefWindowProcW(hwnd, message, wparam, lparam);
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
                    last_todo_stamp_ = todoFileStamp(repository_.filePath());
                    render();
                }
            }
            return 0;
        case WM_ERASEBKGND:
            return 1;
        case WM_DESTROY:
            removeTrayIcon();
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
        const LONG edge = static_cast<LONG>(std::lround(8.0f * surface_.scale()));
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
        if (interactive_) previous_foreground_ = GetForegroundWindow();
        LONG_PTR style = GetWindowLongPtrW(window_.get(), GWL_EXSTYLE);
        if (interactive_) {
            style &= ~(WS_EX_TRANSPARENT | WS_EX_NOACTIVATE);
        } else {
            style |= WS_EX_TRANSPARENT | WS_EX_NOACTIVATE;
        }
        SetLastError(ERROR_SUCCESS);
        if (SetWindowLongPtrW(window_.get(), GWL_EXSTYLE, style) == 0 &&
            GetLastError() != ERROR_SUCCESS) {
            throw std::system_error(static_cast<int>(GetLastError()),
                std::system_category(), "SetWindowLongPtrW");
        }
        if (!SetWindowPos(window_.get(), settings_.topmost ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_FRAMECHANGED |
            (interactive_ ? 0 : SWP_NOACTIVATE))) {
            throw std::system_error(static_cast<int>(GetLastError()),
                std::system_category(), "SetWindowPos");
        }
        if (interactive_) {
            SetForegroundWindow(window_.get());
            SetFocus(window_.get());
        } else {
            SetFocus(nullptr);
            SetActiveWindow(nullptr);
            if (previous_foreground_ != nullptr && IsWindow(previous_foreground_)) {
                if (!SetForegroundWindow(previous_foreground_)) {
                    OutputDebugStringW(L"GhostPin: 无法恢复交互前的前台窗口。\n");
                }
            }
            previous_foreground_ = nullptr;
        }
        settings_.mode = interactive_ ? core::HudMode::Interactive : core::HudMode::Passthrough;
        persistSettings();
        render();
        updateTrayIcon();
    }

    void capturePlacement() {
        if (!window_) return;
        RECT window_rect{};
        if (!GetWindowRect(window_.get(), &window_rect)) return;
        const HMONITOR monitor = MonitorFromWindow(window_.get(), MONITOR_DEFAULTTONEAREST);
        MONITORINFOEXW info{};
        info.cbSize = sizeof(info);
        if (monitor == nullptr || !GetMonitorInfoW(monitor,
            reinterpret_cast<MONITORINFO*>(&info))) return;
        const UINT dpi = std::max(GetDpiForWindow(window_.get()), 96u);
        const double scale = static_cast<double>(dpi) / 96.0;
        settings_.placement.relative_x = (window_rect.left - info.rcWork.left) / scale;
        settings_.placement.relative_y = (window_rect.top - info.rcWork.top) / scale;
        settings_.placement.monitor_id = wideToUtf8(info.szDevice);
        settings_.placement.dpi = dpi;
        persistSettings();
    }

    POINT restorePosition(SIZE size) const {
        POINT position{
            (GetSystemMetrics(SM_CXSCREEN) - size.cx) / 2,
            (GetSystemMetrics(SM_CYSCREEN) - size.cy) / 2};
        const bool has_saved_position = !settings_.placement.monitor_id.empty() ||
            settings_.placement.relative_x != 0 || settings_.placement.relative_y != 0 ||
            settings_.placement.dpi != 96;
        if (!has_saved_position) return position;
        MonitorMatch match{settings_.placement.monitor_id};
        EnumDisplayMonitors(nullptr, nullptr, &findMonitorForPlacement,
            reinterpret_cast<LPARAM>(&match));
        if (!match.found) return position;
        UINT dpi_x = 96;
        UINT dpi_y = 96;
        if (match.monitor != nullptr && SUCCEEDED(GetDpiForMonitor(
            match.monitor, MDT_EFFECTIVE_DPI, &dpi_x, &dpi_y))) {
            // 使用目标显示器 DPI，而不是窗口尚未移动前所在显示器的 DPI。
        }
        const UINT dpi = std::max(dpi_x, 96u);
        const double scale = static_cast<double>(dpi) / 96.0;
        const int desired_left = match.work.left + static_cast<int>(std::lround(
            settings_.placement.relative_x * scale));
        const int desired_top = match.work.top + static_cast<int>(std::lround(
            settings_.placement.relative_y * scale));
        const int max_left = std::max(match.work.left, match.work.right - size.cx);
        const int max_top = std::max(match.work.top, match.work.bottom - size.cy);
        position.x = std::clamp(desired_left, static_cast<int>(match.work.left), max_left);
        position.y = std::clamp(desired_top, static_cast<int>(match.work.top), max_top);
        return position;
    }

    bool render() {
        const auto now = std::chrono::system_clock::now();
        core::ProjectionOptions options;
        options.scope = settings_.scope;
        options.max_count = settings_.max_items;
        options.now = now;
        options.today_start = localDayStart(now);
        const auto projection = core::project(repository_.snapshot(), options);
        std::vector<ButtonRegion> next_buttons;
        const float scale = surface_.scale();
        float button_top = 82.0f;
        const bool has_doing = std::any_of(projection.items.begin(), projection.items.end(),
            [](const auto& item) { return item.status == core::Status::Doing; });
        const bool has_todo = std::any_of(projection.items.begin(), projection.items.end(),
            [](const auto& item) { return item.status == core::Status::Todo; });
        if (has_doing) button_top += 24.0f;
        for (const auto& item : projection.items) {
            if (item.status == core::Status::Doing) {
                next_buttons.push_back(ButtonRegion{
                    item.id,
                    RECT{static_cast<LONG>(34 * scale), static_cast<LONG>((button_top + 22) * scale),
                        static_cast<LONG>(62 * scale), static_cast<LONG>((button_top + 50) * scale)}});
                button_top += 80.0f;
            }
        }
        if (has_todo) button_top += 24.0f;
        for (const auto& item : projection.items) {
            if (item.status == core::Status::Todo) {
                next_buttons.push_back(ButtonRegion{
                    item.id,
                    RECT{static_cast<LONG>(34 * scale), static_cast<LONG>((button_top + 22) * scale),
                        static_cast<LONG>(62 * scale), static_cast<LONG>((button_top + 50) * scale)}});
                button_top += 80.0f;
            }
        }
        if (!surface_.draw(projection.items, interactive_
            ? core::HudMode::Interactive : core::HudMode::Passthrough, settings_.opacity)) {
            buttons_.clear();
            needs_render_ = true;
            return false;
        }
        POINT position{};
        RECT window_rect{};
        GetWindowRect(window_.get(), &window_rect);
        position.x = window_rect.left;
        position.y = window_rect.top;
        SIZE size = surface_.size();
        BLENDFUNCTION blend{AC_SRC_OVER, 0, surface_.opacity(), AC_SRC_ALPHA};
        POINT source{0, 0};
        if (!UpdateLayeredWindow(window_.get(), nullptr, &position, &size, surface_.dc(),
            &source, 0, &blend, ULW_ALPHA)) {
            throw std::system_error(static_cast<int>(GetLastError()),
                std::system_category(), "UpdateLayeredWindow");
        }
        buttons_ = std::move(next_buttons);
        needs_render_ = false;
        return true;
    }

    HINSTANCE instance_{nullptr};
    storage::TodoRepository& repository_;
    core::HudSettings settings_;
    std::filesystem::path settings_path_;
    platform::unique_window window_;
    bool interactive_{false};
    bool hotkey_registered_{false};
    bool timer_set_{false};
    bool tray_added_{false};
    HWND settings_hwnd_{nullptr};
    std::uint64_t last_todo_stamp_{0};
    bool todo_stamp_initialized_{false};
    bool needs_render_{false};
    HWND previous_foreground_{nullptr};
    struct ButtonRegion {
        std::string id;
        RECT bounds{};
    };
    std::vector<ButtonRegion> buttons_;
    HudSurface surface_;

    void cleanup() noexcept {
        if (window_) {
            removeTrayIcon();
            if (settings_hwnd_ != nullptr && IsWindow(settings_hwnd_)) {
                DestroyWindow(settings_hwnd_);
                settings_hwnd_ = nullptr;
            }
            if (timer_set_) KillTimer(window_.get(), kReloadTimer);
            if (hotkey_registered_) UnregisterHotKey(window_.get(), kToggleHotkey);
            timer_set_ = false;
            hotkey_registered_ = false;
            window_.reset();
        }
    }

    void addTrayIcon() {
        NOTIFYICONDATAW data{};
        data.cbSize = sizeof(data);
        data.hWnd = window_.get();
        data.uID = 1;
        data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
        data.uCallbackMessage = kTrayMessage;
        data.hIcon = LoadIconW(instance_, MAKEINTRESOURCEW(101));
        wcscpy_s(data.szTip, L"GhostPin");
        if (!Shell_NotifyIconW(NIM_ADD, &data)) {
            OutputDebugStringW(L"GhostPin: 通知区域图标创建失败。\n");
            return;
        }
        tray_added_ = true;
        data.uVersion = NOTIFYICON_VERSION_4;
        Shell_NotifyIconW(NIM_SETVERSION, &data);
    }

    void removeTrayIcon() noexcept {
        if (!tray_added_ || !window_) return;
        NOTIFYICONDATAW data{};
        data.cbSize = sizeof(data);
        data.hWnd = window_.get();
        data.uID = 1;
        Shell_NotifyIconW(NIM_DELETE, &data);
        tray_added_ = false;
    }

    void persistSettings() {
        storage::writeAtomically(settings_path_, codec::encodeSettings(settings_));
    }

public:
    core::HudSettings settingsSnapshot() const { return settings_; }

    bool applySettings(core::HudSettings settings) {
        settings = core::normalize(std::move(settings));
        const core::HudSettings previous_settings = settings_;
        const bool old_hotkey = hotkey_registered_;
        if (old_hotkey) {
            UnregisterHotKey(window_.get(), kToggleHotkey);
            hotkey_registered_ = false;
        }
        if (settings.hotkey_enabled && !RegisterHotKey(window_.get(), kToggleHotkey,
            settings.hotkey_modifiers | MOD_NOREPEAT, settings.hotkey_key)) {
            restoreHotkey(previous_settings);
            return false;
        }
        const bool new_hotkey = settings.hotkey_enabled;
        if (!setLaunchAtLogin(instance_, settings.launch_at_login)) {
            OutputDebugStringW(L"GhostPin: 登录启动设置写入失败。\n");
            if (new_hotkey) UnregisterHotKey(window_.get(), kToggleHotkey);
            restoreHotkey(previous_settings);
            return false;
        }
        hotkey_registered_ = new_hotkey;
        settings_ = std::move(settings);
        interactive_ = settings_.mode == core::HudMode::Interactive;
        LONG_PTR style = GetWindowLongPtrW(window_.get(), GWL_EXSTYLE);
        if (interactive_) style &= ~(WS_EX_TRANSPARENT | WS_EX_NOACTIVATE);
        else style |= WS_EX_TRANSPARENT | WS_EX_NOACTIVATE;
        SetWindowLongPtrW(window_.get(), GWL_EXSTYLE, style);
        ShowWindow(window_.get(), settings_.visible ? SW_SHOWNOACTIVATE : SW_HIDE);
        SetWindowPos(window_.get(), settings_.topmost ? HWND_TOPMOST : HWND_NOTOPMOST,
            0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_FRAMECHANGED);
        persistSettings();
        render();
        updateTrayIcon();
        return true;
    }

    void restoreHotkey(const core::HudSettings& settings) noexcept {
        hotkey_registered_ = false;
        if (settings.hotkey_enabled) {
            hotkey_registered_ = RegisterHotKey(window_.get(), kToggleHotkey,
                settings.hotkey_modifiers | MOD_NOREPEAT, settings.hotkey_key) != FALSE;
        }
    }

    void settingsClosed(HWND hwnd) noexcept {
        if (settings_hwnd_ == hwnd) settings_hwnd_ = nullptr;
    }

    void showSettings();

private:
    void toggleVisibility() {
        settings_.visible = !settings_.visible;
        ShowWindow(window_.get(), settings_.visible ? SW_SHOWNOACTIVATE : SW_HIDE);
        persistSettings();
        updateTrayIcon();
    }

    void updateTrayIcon() {
        if (!tray_added_ || !window_) return;
        NOTIFYICONDATAW data{};
        data.cbSize = sizeof(data);
        data.hWnd = window_.get();
        data.uID = 1;
        data.uFlags = NIF_TIP;
        wcscpy_s(data.szTip, settings_.visible ? L"GhostPin（显示中）" : L"GhostPin（已隐藏）");
        Shell_NotifyIconW(NIM_MODIFY, &data);
    }

    void showTrayMenu() {
        HMENU raw_menu = CreatePopupMenu();
        if (raw_menu == nullptr) throw std::system_error(
            static_cast<int>(GetLastError()), std::system_category(), "CreatePopupMenu");
        platform::unique_menu menu(raw_menu);
        AppendMenuW(menu.get(), MF_STRING, kTrayToggleVisibility,
            settings_.visible ? L"隐藏 HUD" : L"显示 HUD");
        AppendMenuW(menu.get(), MF_STRING, kTrayToggleMode,
            interactive_ ? L"切换为穿透模式" : L"切换为交互模式");
        AppendMenuW(menu.get(), MF_SEPARATOR, 0, nullptr);
        AppendMenuW(menu.get(), MF_STRING, kTraySettings, L"设置…");
        AppendMenuW(menu.get(), MF_STRING, kTrayExit, L"退出");
        POINT point{};
        GetCursorPos(&point);
        SetForegroundWindow(window_.get());
        TrackPopupMenu(menu.get(), TPM_RIGHTBUTTON,
            point.x, point.y, 0, window_.get(), nullptr);
        PostMessageW(window_.get(), WM_NULL, 0, 0);
    }
};

constexpr wchar_t kSettingsWindowClass[] = L"GhostPin.Native.Settings";
constexpr int kSettingsVisible = 2101;
constexpr int kSettingsOpacity = 2102;
constexpr int kSettingsScope = 2104;
constexpr int kSettingsMaxItems = 2105;
constexpr int kSettingsTopmost = 2106;
constexpr int kSettingsLaunchAtLogin = 2107;
constexpr int kSettingsHotkeyEnabled = 2202;
constexpr int kSettingsHotkeyUseDefault = 2203;
constexpr int kSettingsHotkeyClear = 2204;
constexpr int kSettingsStatus = 2205;

class SettingsWindow final {
public:
    explicit SettingsWindow(NativeHud& owner) : owner_(owner) {}

    HWND create() {
        INITCOMMONCONTROLSEX controls{};
        controls.dwSize = sizeof(controls);
        controls.dwICC = ICC_TAB_CLASSES | ICC_BAR_CLASSES;
        InitCommonControlsEx(&controls);
        WNDCLASSEXW specification{};
        specification.cbSize = sizeof(specification);
        specification.lpfnWndProc = &SettingsWindow::windowProc;
        specification.hInstance = GetModuleHandleW(nullptr);
        specification.hCursor = LoadCursorW(nullptr, IDC_ARROW);
        specification.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
        specification.lpszClassName = kSettingsWindowClass;
        static ATOM atom = RegisterClassExW(&specification);
        if (atom == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
            throw std::system_error(static_cast<int>(GetLastError()),
                std::system_category(), "RegisterClassExW(settings)");
        }
        hwnd_ = CreateWindowExW(0, kSettingsWindowClass, L"GhostPin 设置",
            WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
            CW_USEDEFAULT, CW_USEDEFAULT, 520, 420, nullptr, nullptr,
            GetModuleHandleW(nullptr), this);
        if (hwnd_ == nullptr) throw std::system_error(static_cast<int>(GetLastError()),
            std::system_category(), "CreateWindowExW(settings)");
        refresh();
        ShowWindow(hwnd_, SW_SHOWNORMAL);
        SetForegroundWindow(hwnd_);
        return hwnd_;
    }

    void refresh() {
        if (hwnd_ == nullptr || tabs_ == nullptr) return;
        const auto settings = owner_.settingsSnapshot();
        CheckDlgButton(hwnd_, kSettingsVisible, settings.visible ? BST_CHECKED : BST_UNCHECKED);
        CheckDlgButton(hwnd_, kSettingsTopmost, settings.topmost ? BST_CHECKED : BST_UNCHECKED);
        CheckDlgButton(hwnd_, kSettingsLaunchAtLogin,
            settings.launch_at_login ? BST_CHECKED : BST_UNCHECKED);
        SendDlgItemMessageW(hwnd_, kSettingsOpacity, TBM_SETPOS, TRUE,
            static_cast<LPARAM>(std::lround(settings.opacity * 100.0)));
        SendDlgItemMessageW(hwnd_, kSettingsScope, CB_SETCURSEL,
            settings.scope == core::HudScope::Today ? 1 : 0, 0);
        wchar_t max_items[16]{};
        _itow_s(settings.max_items, max_items, 10);
        SetDlgItemTextW(hwnd_, kSettingsMaxItems, max_items);
        CheckDlgButton(hwnd_, kSettingsHotkeyEnabled,
            settings.hotkey_enabled ? BST_CHECKED : BST_UNCHECKED);
        hotkey_modifiers_ = settings.hotkey_modifiers;
        hotkey_key_ = settings.hotkey_key;
        if (!settings.hotkey_enabled) {
            hotkey_modifiers_ = MOD_CONTROL | MOD_ALT;
            hotkey_key_ = 'G';
        }
        SetDlgItemTextW(hwnd_, kSettingsStatus, settings.hotkey_enabled
            ? L"快捷键：已启用" : L"快捷键：未启用");
    }

private:
    static LRESULT CALLBACK windowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
        if (message == WM_NCCREATE) {
            const auto* create = reinterpret_cast<const CREATESTRUCTW*>(lparam);
            SetWindowLongPtrW(hwnd, GWLP_USERDATA,
                reinterpret_cast<LONG_PTR>(create->lpCreateParams));
            return TRUE;
        }
        auto* self = reinterpret_cast<SettingsWindow*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
        if (self == nullptr) return DefWindowProcW(hwnd, message, wparam, lparam);
        try {
            if (message == WM_NCDESTROY) {
                const LRESULT result = DefWindowProcW(hwnd, message, wparam, lparam);
                self->owner_.settingsClosed(hwnd);
                SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
                delete self;
                return result;
            }
            return self->handleMessage(hwnd, message, wparam, lparam);
        } catch (const std::exception& error) {
            OutputDebugStringA((std::string("GhostPin.Settings: ") + error.what() + "\n").c_str());
            return 0;
        }
    }

    LRESULT handleMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
        switch (message) {
        case WM_CREATE:
            // WM_CREATE 在 CreateWindowExW 返回前同步派发，先保存真实父窗口句柄，
            // 供 createControl 创建所有 Common Controls。
            hwnd_ = hwnd;
            createControls(hwnd);
            return 0;
        case WM_COMMAND:
            if (HIWORD(wparam) == BN_CLICKED ||
                (LOWORD(wparam) == kSettingsScope && HIWORD(wparam) == CBN_SELCHANGE) ||
                (LOWORD(wparam) == kSettingsMaxItems && HIWORD(wparam) == EN_KILLFOCUS)) {
                switch (LOWORD(wparam)) {
                case kSettingsHotkeyUseDefault:
                    hotkey_modifiers_ = MOD_CONTROL | MOD_ALT;
                    hotkey_key_ = 'G';
                    CheckDlgButton(hwnd, kSettingsHotkeyEnabled, BST_CHECKED);
                    break;
                case kSettingsHotkeyClear:
                    hotkey_modifiers_ = 0;
                    hotkey_key_ = 0;
                    CheckDlgButton(hwnd, kSettingsHotkeyEnabled, BST_UNCHECKED);
                    break;
                default:
                    break;
                }
                applyFromControls();
                return 0;
            }
            return 0;
        case WM_HSCROLL:
            if (reinterpret_cast<HWND>(lparam) == GetDlgItem(hwnd, kSettingsOpacity)) {
                applyFromControls();
            }
            return 0;
        case WM_NOTIFY: {
            const auto* header = reinterpret_cast<const NMHDR*>(lparam);
            if (header != nullptr && header->idFrom == 2001 && header->code == TCN_SELCHANGE) {
                switchPage(TabCtrl_GetCurSel(tabs_));
            }
            return 0;
        }
        case WM_CLOSE:
            ShowWindow(hwnd, SW_HIDE);
            return 0;
        default:
            return DefWindowProcW(hwnd, message, wparam, lparam);
        }
    }

    HWND createControl(DWORD style, const wchar_t* class_name, const wchar_t* title,
        int id, int x, int y, int width, int height, DWORD ex_style = 0) {
        HWND control = CreateWindowExW(ex_style, class_name, title,
            WS_CHILD | WS_VISIBLE | style, x, y, width, height, hwnd_,
            reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), GetModuleHandleW(nullptr), nullptr);
        if (control == nullptr) throw std::system_error(static_cast<int>(GetLastError()),
            std::system_category(), "CreateWindowExW(settings control)");
        SendMessageW(control, WM_SETFONT,
            reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)), TRUE);
        return control;
    }

    void createControls(HWND hwnd) {
        tabs_ = createControl(WS_TABSTOP, WC_TABCONTROLW, L"", 2001, 12, 12, 480, 330);
        TCITEMW hud_item{};
        hud_item.mask = TCIF_TEXT;
        hud_item.pszText = const_cast<wchar_t*>(L"HUD");
        TabCtrl_InsertItem(tabs_, 0, &hud_item);
        TCITEMW advanced_item{};
        advanced_item.mask = TCIF_TEXT;
        advanced_item.pszText = const_cast<wchar_t*>(L"高级");
        TabCtrl_InsertItem(tabs_, 1, &advanced_item);

        createControl(BS_AUTOCHECKBOX, L"BUTTON", L"显示 HUD", kSettingsVisible,
            32, 58, 180, 26);
        createControl(0, L"STATIC", L"透明度", 2103, 32, 94, 70, 22);
        HWND opacity = createControl(TBS_AUTOTICKS | TBS_HORZ, TRACKBAR_CLASSW, L"",
            kSettingsOpacity, 100, 90, 270, 32);
        SendMessageW(opacity, TBM_SETRANGE, TRUE, MAKELONG(50, 100));
        createControl(0, L"STATIC", L"范围", 2108, 32, 140, 70, 22);
        HWND scope = createControl(CBS_DROPDOWNLIST, WC_COMBOBOXW, L"", kSettingsScope,
            100, 136, 180, 120);
        SendMessageW(scope, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(L"全部任务"));
        SendMessageW(scope, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(L"今天"));
        createControl(ES_NUMBER | WS_BORDER, L"EDIT", L"", kSettingsMaxItems,
            100, 178, 80, 24);
        createControl(0, L"STATIC", L"最多显示条数", 2109, 32, 180, 68, 22);
        createControl(BS_AUTOCHECKBOX, L"BUTTON", L"窗口置顶", kSettingsTopmost,
            32, 222, 180, 26);
        createControl(BS_AUTOCHECKBOX, L"BUTTON", L"登录时启动", kSettingsLaunchAtLogin,
            32, 254, 180, 26);

        createControl(0, L"STATIC", L"快捷键只用于切换 HUD 的穿透 / 交互模式。", 2201,
            32, 62, 410, 24);
        createControl(BS_AUTOCHECKBOX, L"BUTTON", L"启用全局快捷键", kSettingsHotkeyEnabled,
            32, 100, 180, 26);
        createControl(BS_PUSHBUTTON, L"BUTTON", L"使用 Ctrl+Alt+G", kSettingsHotkeyUseDefault,
            32, 138, 180, 28);
        createControl(BS_PUSHBUTTON, L"BUTTON", L"清除快捷键", kSettingsHotkeyClear,
            224, 138, 140, 28);
        createControl(0, L"STATIC", L"", kSettingsStatus, 32, 184, 400, 26);
        hud_controls_ = {
            GetDlgItem(hwnd, kSettingsVisible), GetDlgItem(hwnd, 2103),
            GetDlgItem(hwnd, kSettingsOpacity), GetDlgItem(hwnd, 2108),
            GetDlgItem(hwnd, kSettingsScope), GetDlgItem(hwnd, kSettingsMaxItems),
            GetDlgItem(hwnd, 2109), GetDlgItem(hwnd, kSettingsTopmost),
            GetDlgItem(hwnd, kSettingsLaunchAtLogin)
        };
        advanced_controls_ = {
            GetDlgItem(hwnd, 2201), GetDlgItem(hwnd, kSettingsHotkeyEnabled),
            GetDlgItem(hwnd, kSettingsHotkeyUseDefault), GetDlgItem(hwnd, kSettingsHotkeyClear),
            GetDlgItem(hwnd, kSettingsStatus)
        };
        switchPage(0);
    }

    void switchPage(int page) {
        for (HWND control : hud_controls_) ShowWindow(control, page == 0 ? SW_SHOW : SW_HIDE);
        for (HWND control : advanced_controls_) ShowWindow(control, page == 1 ? SW_SHOW : SW_HIDE);
    }

    void applyFromControls() {
        auto settings = owner_.settingsSnapshot();
        settings.visible = IsDlgButtonChecked(hwnd_, kSettingsVisible) == BST_CHECKED;
        settings.topmost = IsDlgButtonChecked(hwnd_, kSettingsTopmost) == BST_CHECKED;
        settings.launch_at_login = IsDlgButtonChecked(hwnd_, kSettingsLaunchAtLogin) == BST_CHECKED;
        settings.opacity = SendDlgItemMessageW(hwnd_, kSettingsOpacity, TBM_GETPOS, 0, 0) / 100.0;
        settings.scope = SendDlgItemMessageW(hwnd_, kSettingsScope, CB_GETCURSEL, 0, 0) == 1
            ? core::HudScope::Today : core::HudScope::All;
        wchar_t max_items[16]{};
        GetDlgItemTextW(hwnd_, kSettingsMaxItems, max_items,
            static_cast<int>(std::size(max_items)));
        const int parsed = _wtoi(max_items);
        if (parsed > 0) settings.max_items = parsed;
        settings.hotkey_enabled = IsDlgButtonChecked(hwnd_, kSettingsHotkeyEnabled) == BST_CHECKED;
        settings.hotkey_modifiers = hotkey_modifiers_;
        settings.hotkey_key = hotkey_key_;
        if (!owner_.applySettings(settings)) {
            SetDlgItemTextW(hwnd_, kSettingsStatus, L"快捷键冲突，未保存本次修改");
        } else if (settings.hotkey_enabled) {
            SetDlgItemTextW(hwnd_, kSettingsStatus, L"快捷键：已启用");
        } else {
            SetDlgItemTextW(hwnd_, kSettingsStatus, L"快捷键：未启用");
        }
    }

    NativeHud& owner_;
    HWND hwnd_{nullptr};
    HWND tabs_{nullptr};
    std::vector<HWND> hud_controls_;
    std::vector<HWND> advanced_controls_;
    std::uint32_t hotkey_modifiers_{MOD_CONTROL | MOD_ALT};
    std::uint32_t hotkey_key_{'G'};
};

void NativeHud::showSettings() {
    if (settings_hwnd_ != nullptr && IsWindow(settings_hwnd_)) {
        ShowWindow(settings_hwnd_, SW_SHOWNORMAL);
        SetForegroundWindow(settings_hwnd_);
        return;
    }
    auto* window = new SettingsWindow(*this);
    try {
        settings_hwnd_ = window->create();
    } catch (...) {
        delete window;
        throw;
    }
}

} // namespace

int Controller::run(HINSTANCE instance, int) const {
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    SetLastError(ERROR_SUCCESS);
    platform::unique_handle instance_mutex(CreateMutexW(nullptr, TRUE, kNativeMutexName));
    if (!instance_mutex) return static_cast<int>(GetLastError());
    const DWORD mutex_error = GetLastError();
    if (mutex_error == ERROR_ALREADY_EXISTS) {
        MessageBoxW(nullptr, L"GhostPin 原生版本已经在运行。", L"GhostPin", MB_OK | MB_ICONINFORMATION);
        return 2;
    }
    const auto paths = storage::resolveLocalAppData();
    storage::ensureDirectory(paths);
    const auto settings = loadSettings(paths.native_settings_file);
    if (!setLaunchAtLogin(instance, settings.launch_at_login)) {
        OutputDebugStringW(L"GhostPin: 无法同步登录启动设置。\n");
    }
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

    NativeHud hud(instance, repository, settings);
    MSG message{};
    int result = 0;
    while ((result = GetMessageW(&message, nullptr, 0, 0)) > 0) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
    if (result == -1) {
        return static_cast<int>(GetLastError());
    }
    return static_cast<int>(message.wParam);
}

} // namespace ghostpin::app
