#include "raii.hpp"

#include <windows.h>

#include <iostream>

namespace {

LRESULT CALLBACK checkWindowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    return DefWindowProcW(window, message, wparam, lparam);
}

DWORD WINAPI checkThreadProc(LPVOID) {
    return 0;
}

bool expect(bool condition, const char* message, int& checks) {
    ++checks;
    if (!condition) {
        std::cerr << "FAIL " << message << "\n";
        return false;
    }
    return true;
}

bool closedHandle(HANDLE handle) {
    DWORD flags = 0;
    SetLastError(ERROR_SUCCESS);
    const BOOL valid = GetHandleInformation(handle, &flags);
    return valid == FALSE && GetLastError() == ERROR_INVALID_HANDLE;
}

} // namespace

int main() {
    int checks = 0;
    try {
        ghostpin::platform::com_apartment apartment;

        HANDLE closed_event = nullptr;
        {
            ghostpin::platform::unique_handle owner(
                CreateEventW(nullptr, TRUE, FALSE, nullptr));
            if (!expect(owner.get() != nullptr, "event handle created", checks)) return 1;
            closed_event = owner.get();
        }
        if (!expect(closedHandle(closed_event), "HANDLE destructor closes raw handle", checks)) return 1;

        HANDLE old_handle = nullptr;
        HANDLE moved_handle = nullptr;
        {
            ghostpin::platform::unique_handle owner(
                CreateEventW(nullptr, TRUE, FALSE, nullptr));
            ghostpin::platform::unique_handle replacement(
                CreateEventW(nullptr, TRUE, FALSE, nullptr));
            if (!expect(owner.get() != nullptr && replacement.get() != nullptr,
                "move handles created", checks)) return 1;
            old_handle = owner.get();
            moved_handle = replacement.get();
            owner = std::move(replacement);
            if (!expect(closedHandle(old_handle), "move assignment closes old HANDLE", checks)) return 1;
            DWORD flags = 0;
            if (!expect(GetHandleInformation(moved_handle, &flags) != FALSE,
                "move assignment preserves new HANDLE", checks)) return 1;
        }
        if (!expect(closedHandle(moved_handle), "moved HANDLE destructor closes new owner", checks)) return 1;

        HANDLE closed_file = nullptr;
        {
            ghostpin::platform::unique_file file(
                CreateFileW(L"NUL", GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING,
                    FILE_ATTRIBUTE_NORMAL, nullptr));
            if (!expect(file.get() != nullptr && file.get() != INVALID_HANDLE_VALUE,
                "file handle created", checks)) return 1;
            closed_file = file.get();
        }
        if (!expect(closedHandle(closed_file), "file alias destructor closes handle", checks)) return 1;

        HANDLE closed_thread = nullptr;
        {
            ghostpin::platform::unique_thread thread(CreateThread(
                nullptr, 0, checkThreadProc, nullptr, 0, nullptr));
            if (!expect(thread.get() != nullptr, "thread handle created", checks)) return 1;
            if (!expect(WaitForSingleObject(thread.get(), 1000) == WAIT_OBJECT_0,
                "thread completed", checks)) return 1;
            closed_thread = thread.get();
        }
        if (!expect(closedHandle(closed_thread), "thread alias destructor closes handle", checks)) return 1;

        HGDIOBJ closed_bitmap = nullptr;
        {
            ghostpin::platform::unique_gdi_object bitmap(
                CreateBitmap(1, 1, 1, 32, nullptr));
            if (!expect(bitmap.get() != nullptr, "bitmap created", checks)) return 1;
            closed_bitmap = bitmap.get();
        }
        BITMAP bitmap_info{};
        if (!expect(GetObjectW(closed_bitmap, sizeof(bitmap_info), &bitmap_info) == 0,
            "GDI destructor deletes object", checks)) return 1;

        HICON closed_icon = nullptr;
        {
            ghostpin::platform::unique_icon icon(
                CopyIcon(LoadIconW(nullptr, IDI_APPLICATION)));
            if (!expect(icon.get() != nullptr, "icon created", checks)) return 1;
            closed_icon = icon.get();
        }
        ICONINFO icon_info{};
        const BOOL icon_valid = GetIconInfo(closed_icon, &icon_info);
        if (icon_valid != FALSE) {
            if (icon_info.hbmMask != nullptr) DeleteObject(icon_info.hbmMask);
            if (icon_info.hbmColor != nullptr) DeleteObject(icon_info.hbmColor);
        }
        if (!expect(icon_valid == FALSE, "icon destructor destroys icon", checks)) return 1;

        HMENU closed_menu = nullptr;
        {
            ghostpin::platform::unique_menu menu(CreatePopupMenu());
            if (!expect(menu.get() != nullptr, "menu created", checks)) return 1;
            closed_menu = menu.get();
        }
        if (!expect(IsMenu(closed_menu) == FALSE, "menu destructor destroys menu", checks)) return 1;

        const HINSTANCE instance = GetModuleHandleW(nullptr);
        constexpr wchar_t class_name[] = L"GhostPin.Native.PlatformChecks";
        HWND closed_window = nullptr;
        {
            WNDCLASSEXW specification{};
            specification.cbSize = sizeof(specification);
            specification.lpfnWndProc = checkWindowProc;
            specification.hInstance = instance;
            specification.lpszClassName = class_name;
            ghostpin::platform::registered_window_class window_class(instance, specification);
            WNDCLASSEXW registered{};
            registered.cbSize = sizeof(registered);
            if (!expect(GetClassInfoExW(instance, class_name, &registered) != FALSE,
                "window class registered", checks)) return 1;
            {
                ghostpin::platform::unique_window window(CreateWindowExW(
                    0, window_class.name(), L"GhostPin Native Platform Check",
                    WS_OVERLAPPED, 0, 0, 1, 1, nullptr, nullptr, instance, nullptr));
                if (!expect(window.get() != nullptr && IsWindow(window.get()) != FALSE,
                    "window created", checks)) return 1;
                closed_window = window.get();
            }
            if (!expect(IsWindow(closed_window) == FALSE,
                "window destructor destroys HWND", checks)) return 1;
        }
        WNDCLASSEXW after_unregister{};
        after_unregister.cbSize = sizeof(after_unregister);
        if (!expect(GetClassInfoExW(instance, class_name, &after_unregister) == FALSE,
            "window class destructor unregisters class", checks)) return 1;

        constexpr UINT hotkey_modifiers = MOD_CONTROL | MOD_ALT | MOD_SHIFT | MOD_NOREPEAT;
        constexpr UINT hotkey_key = 'G';
        {
            const auto hotkey = ghostpin::platform::unique_hotkey::try_register(
                nullptr, 0x4A31, hotkey_modifiers, hotkey_key);
            if (!hotkey.has_value() || !hotkey->registered()) {
                if (GetLastError() == 1459) {
                    std::cout << "SKIP hotkey registration requires interactive window station\n";
                    return 77;
                }
                std::cerr << "FAIL hotkey registration RAII error=" << GetLastError() << "\n";
                return 1;
            }
        }
        const auto second_hotkey = ghostpin::platform::unique_hotkey::try_register(
            nullptr, 0x4A31, hotkey_modifiers, hotkey_key);
        if (!second_hotkey.has_value() || !second_hotkey->registered()) {
            if (GetLastError() == 1459) {
                std::cout << "SKIP hotkey registration requires interactive window station\n";
                return 77;
            }
            std::cerr << "FAIL hotkey RAII error=" << GetLastError() << "\n";
            return 1;
        }
        ++checks;

        std::cout << "PASS GhostPin.Native.PlatformChecks (" << checks
            << " destructor and registration checks)\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL platform exception: " << error.what() << '\n';
        return 1;
    }
}
