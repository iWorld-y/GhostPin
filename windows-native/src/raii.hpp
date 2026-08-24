#pragma once

#include <windows.h>
#include <objbase.h>

#include <optional>
#include <system_error>
#include <string>
#include <utility>

namespace ghostpin::platform {

class unique_handle final {
public:
    unique_handle() noexcept = default;
    explicit unique_handle(HANDLE value) noexcept : value_(value) {}
    unique_handle(const unique_handle&) = delete;
    unique_handle& operator=(const unique_handle&) = delete;
    unique_handle(unique_handle&& other) noexcept : value_(std::exchange(other.value_, nullptr)) {}
    unique_handle& operator=(unique_handle&& other) noexcept {
        if (this != &other) {
            reset(std::exchange(other.value_, nullptr));
        }
        return *this;
    }
    ~unique_handle() { reset(); }

    HANDLE get() const noexcept { return value_; }
    explicit operator bool() const noexcept {
        return value_ != nullptr && value_ != INVALID_HANDLE_VALUE;
    }
    HANDLE release() noexcept { return std::exchange(value_, nullptr); }
    void reset(HANDLE value = nullptr) noexcept {
        if (value_ != nullptr && value_ != INVALID_HANDLE_VALUE && value_ != value) {
            CloseHandle(value_);
        }
        value_ = value;
    }

private:
    HANDLE value_{nullptr};
};

using unique_file = unique_handle;
using unique_thread = unique_handle;

class unique_window final {
public:
    unique_window() noexcept = default;
    explicit unique_window(HWND value) noexcept : value_(value) {}
    unique_window(const unique_window&) = delete;
    unique_window& operator=(const unique_window&) = delete;
    unique_window(unique_window&& other) noexcept
        : value_(std::exchange(other.value_, nullptr)) {}
    unique_window& operator=(unique_window&& other) noexcept {
        if (this != &other) {
            reset(std::exchange(other.value_, nullptr));
        }
        return *this;
    }
    ~unique_window() { reset(); }

    HWND get() const noexcept { return value_; }
    explicit operator bool() const noexcept { return value_ != nullptr; }
    void reset(HWND value = nullptr) noexcept {
        if (value_ != nullptr && value_ != value) {
            DestroyWindow(value_);
        }
        value_ = value;
    }

private:
    HWND value_{nullptr};
};

class registered_window_class final {
public:
    registered_window_class(HINSTANCE instance, const WNDCLASSEXW& specification)
        : instance_(instance), name_(specification.lpszClassName != nullptr
            ? specification.lpszClassName : L"") {
        WNDCLASSEXW copy = specification;
        copy.cbSize = sizeof(WNDCLASSEXW);
        copy.hInstance = instance_;
        copy.lpszClassName = name_.c_str();
        atom_ = RegisterClassExW(&copy);
        if (atom_ == 0) {
            throw std::system_error(
                static_cast<int>(GetLastError()), std::system_category(), "RegisterClassExW");
        }
    }
    registered_window_class(const registered_window_class&) = delete;
    registered_window_class& operator=(const registered_window_class&) = delete;
    ~registered_window_class() {
        if (atom_ != 0) {
            UnregisterClassW(name_.c_str(), instance_);
        }
    }

    ATOM atom() const noexcept { return atom_; }
    const wchar_t* name() const noexcept { return name_.c_str(); }

private:
    HINSTANCE instance_{nullptr};
    std::wstring name_;
    ATOM atom_{0};
};

class unique_gdi_object final {
public:
    unique_gdi_object() noexcept = default;
    explicit unique_gdi_object(HGDIOBJ value) noexcept : value_(value) {}
    unique_gdi_object(const unique_gdi_object&) = delete;
    unique_gdi_object& operator=(const unique_gdi_object&) = delete;
    unique_gdi_object(unique_gdi_object&& other) noexcept
        : value_(std::exchange(other.value_, nullptr)) {}
    unique_gdi_object& operator=(unique_gdi_object&& other) noexcept {
        if (this != &other) {
            reset(std::exchange(other.value_, nullptr));
        }
        return *this;
    }
    ~unique_gdi_object() { reset(); }

    HGDIOBJ get() const noexcept { return value_; }
    void reset(HGDIOBJ value = nullptr) noexcept {
        if (value_ != nullptr && value_ != value) {
            DeleteObject(value_);
        }
        value_ = value;
    }

private:
    HGDIOBJ value_{nullptr};
};

class unique_icon final {
public:
    unique_icon() noexcept = default;
    explicit unique_icon(HICON value) noexcept : value_(value) {}
    unique_icon(const unique_icon&) = delete;
    unique_icon& operator=(const unique_icon&) = delete;
    unique_icon(unique_icon&& other) noexcept : value_(std::exchange(other.value_, nullptr)) {}
    unique_icon& operator=(unique_icon&& other) noexcept {
        if (this != &other) {
            reset(std::exchange(other.value_, nullptr));
        }
        return *this;
    }
    ~unique_icon() { reset(); }

    HICON get() const noexcept { return value_; }
    void reset(HICON value = nullptr) noexcept {
        if (value_ != nullptr && value_ != value) {
            DestroyIcon(value_);
        }
        value_ = value;
    }

private:
    HICON value_{nullptr};
};

class unique_menu final {
public:
    unique_menu() noexcept = default;
    explicit unique_menu(HMENU value) noexcept : value_(value) {}
    unique_menu(const unique_menu&) = delete;
    unique_menu& operator=(const unique_menu&) = delete;
    unique_menu(unique_menu&& other) noexcept : value_(std::exchange(other.value_, nullptr)) {}
    unique_menu& operator=(unique_menu&& other) noexcept {
        if (this != &other) {
            reset(std::exchange(other.value_, nullptr));
        }
        return *this;
    }
    ~unique_menu() { reset(); }

    HMENU get() const noexcept { return value_; }
    void reset(HMENU value = nullptr) noexcept {
        if (value_ != nullptr && value_ != value) {
            DestroyMenu(value_);
        }
        value_ = value;
    }

private:
    HMENU value_{nullptr};
};

class unique_hotkey final {
public:
    unique_hotkey() noexcept = default;
    unique_hotkey(const unique_hotkey&) = delete;
    unique_hotkey& operator=(const unique_hotkey&) = delete;
    unique_hotkey(unique_hotkey&& other) noexcept
        : window_(std::exchange(other.window_, nullptr)),
          id_(std::exchange(other.id_, 0)),
          registered_(std::exchange(other.registered_, false)) {}
    unique_hotkey& operator=(unique_hotkey&& other) noexcept {
        if (this != &other) {
            reset();
            window_ = std::exchange(other.window_, nullptr);
            id_ = std::exchange(other.id_, 0);
            registered_ = std::exchange(other.registered_, false);
        }
        return *this;
    }
    ~unique_hotkey() { reset(); }

    static std::optional<unique_hotkey> try_register(
        HWND window, int id, UINT modifiers, UINT virtual_key) noexcept {
        if (!RegisterHotKey(window, id, modifiers, virtual_key)) {
            return std::nullopt;
        }
        return unique_hotkey(window, id);
    }

    bool registered() const noexcept { return registered_; }
    void reset() noexcept {
        if (registered_) {
            UnregisterHotKey(window_, id_);
            registered_ = false;
        }
        window_ = nullptr;
        id_ = 0;
    }

private:
    unique_hotkey(HWND window, int id) noexcept
        : window_(window), id_(id), registered_(true) {}

    HWND window_{nullptr};
    int id_{0};
    bool registered_{false};
};

class com_apartment final {
public:
    explicit com_apartment(DWORD model = COINIT_APARTMENTTHREADED) {
        result_ = CoInitializeEx(nullptr, model);
        if (FAILED(result_)) {
            throw std::system_error(
                static_cast<int>(result_), std::system_category(), "CoInitializeEx");
        }
        initialized_ = result_ == S_OK || result_ == S_FALSE;
    }
    com_apartment(const com_apartment&) = delete;
    com_apartment& operator=(const com_apartment&) = delete;
    ~com_apartment() {
        if (initialized_) {
            CoUninitialize();
        }
    }

private:
    HRESULT result_{E_FAIL};
    bool initialized_{false};
};

} // namespace ghostpin::platform
