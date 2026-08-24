#include "storage_paths.hpp"

#include <chrono>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <utility>

namespace {

bool expect(bool condition, const char* message, int& checks) {
    ++checks;
    if (!condition) std::cerr << "FAIL " << message << "\n";
    return condition;
}

template <typename Function>
bool expectInvalid(Function&& function, const char* message, int& checks) {
    ++checks;
    try {
        function();
    } catch (const std::invalid_argument&) {
        return true;
    } catch (const std::exception& error) {
        std::cerr << "FAIL " << message << " raised wrong exception: " << error.what() << "\n";
        return false;
    }
    std::cerr << "FAIL " << message << " was accepted\n";
    return false;
}

template <typename Function>
bool expectFilesystemError(Function&& function, const char* message, int& checks) {
    ++checks;
    try {
        function();
    } catch (const std::filesystem::filesystem_error&) {
        return true;
    } catch (const std::exception& error) {
        std::cerr << "FAIL " << message << " raised wrong exception: " << error.what() << "\n";
        return false;
    }
    std::cerr << "FAIL " << message << " was accepted\n";
    return false;
}

struct TemporaryDirectory final {
    explicit TemporaryDirectory(std::filesystem::path value) : path(std::move(value)) {}
    ~TemporaryDirectory() {
        std::error_code error;
        std::filesystem::remove_all(path, error);
    }

    TemporaryDirectory(const TemporaryDirectory&) = delete;
    TemporaryDirectory& operator=(const TemporaryDirectory&) = delete;

    std::filesystem::path path;
};

} // namespace

int main() {
    int checks = 0;
    try {
        const auto token = std::chrono::steady_clock::now().time_since_epoch().count();
        const auto temporary_parent = std::filesystem::temp_directory_path() /
            ("GhostPin.Native.StoragePathsChecks-" + std::to_string(token));
        TemporaryDirectory temporary(temporary_parent);
        const auto input_root = temporary_parent / L"nested" / L".." / L"GhostPin";
        const auto paths = ghostpin::storage::fromRootDirectory(input_root);
        const auto expected_root = std::filesystem::absolute(input_root).lexically_normal();
        if (!expect(paths.root_directory.is_absolute(), "storage root is absolute", checks)) return 1;
        if (!expect(paths.root_directory == expected_root &&
            paths.root_directory == paths.root_directory.lexically_normal(),
            "storage root is normalized", checks)) return 1;
        if (!expect(paths.todos_file == expected_root / L"todos.json",
            "todos path uses canonical filename", checks)) return 1;
        if (!expect(paths.native_settings_file == expected_root / L"native-settings.json" &&
            paths.native_settings_file.filename() == std::filesystem::path(L"native-settings.json"),
            "native settings uses prototype-specific filename", checks)) return 1;
        if (!expect(paths.native_settings_file != expected_root / L"settings.json",
            "native settings is isolated from WPF settings", checks)) return 1;
        if (!expect(paths.todos_file != paths.native_settings_file,
            "tasks and settings paths are distinct", checks)) return 1;

        const auto resolved = ghostpin::storage::resolveLocalAppData();
        if (!expect(resolved.root_directory.is_absolute() &&
            resolved.root_directory.filename() == std::filesystem::path(L"GhostPin"),
            "system LocalAppData resolves to absolute GhostPin root", checks)) return 1;
        if (!expect(resolved.todos_file.filename() == std::filesystem::path(L"todos.json") &&
            resolved.native_settings_file.filename() == std::filesystem::path(L"native-settings.json") &&
            resolved.native_settings_file != resolved.root_directory / L"settings.json",
            "system paths keep native settings isolated", checks)) return 1;

        ghostpin::storage::ensureDirectory(paths);
        if (!expect(std::filesystem::is_directory(paths.root_directory),
            "injected root directory is created", checks)) return 1;
        if (!expect(!std::filesystem::exists(paths.todos_file) &&
            !std::filesystem::exists(paths.native_settings_file) &&
            !std::filesystem::exists(expected_root / L"settings.json"),
            "path initialization does not create or touch data files", checks)) return 1;
        ghostpin::storage::ensureDirectory(paths);
        if (!expect(std::filesystem::is_directory(paths.root_directory),
            "directory initialization is idempotent", checks)) return 1;
        const auto blocker_path = temporary_parent / L"blocker-file";
        std::ofstream blocker(blocker_path, std::ios::binary);
        if (!blocker) throw std::runtime_error("failed to create temporary blocker file");
        blocker << "blocker";
        blocker.close();
        const auto blocker_paths = ghostpin::storage::fromRootDirectory(blocker_path);
        if (!expectFilesystemError(
            [&] { ghostpin::storage::ensureDirectory(blocker_paths); },
            "file blocker makes directory initialization diagnosable", checks)) return 1;
        if (!expectInvalid(
            [] { (void)ghostpin::storage::fromRootDirectory(std::filesystem::path{}); },
            "empty storage root is rejected", checks)) return 1;
        if (!expectInvalid(
            [] { (void)ghostpin::storage::fromRootDirectory(std::filesystem::path(L"   ")); },
            "whitespace storage root is rejected", checks)) return 1;
    } catch (const std::exception& error) {
        std::cerr << "FAIL unexpected storage path check exception: " << error.what() << "\n";
        return 1;
    }

    std::cout << "PASS GhostPin.Native.StoragePathsChecks (" << checks << " checks)\n";
    return 0;
}
