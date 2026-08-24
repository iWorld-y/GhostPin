#include "storage_paths.hpp"

#include <windows.h>
#include <knownfolders.h>
#include <shlobj.h>

#include <cwctype>
#include <memory>
#include <stdexcept>
#include <system_error>

namespace ghostpin::storage {
namespace {

bool isWhitespaceOnly(const std::filesystem::path& value) {
    const auto text = value.wstring();
    if (text.empty()) return true;
    for (const auto character : text) {
        if (!std::iswspace(character)) return false;
    }
    return true;
}

struct CoTaskMemDeleter {
    void operator()(wchar_t* value) const noexcept {
        if (value != nullptr) ::CoTaskMemFree(value);
    }
};

} // namespace

StoragePaths fromRootDirectory(const std::filesystem::path& root_directory) {
    if (isWhitespaceOnly(root_directory)) {
        throw std::invalid_argument("GhostPin storage root must not be empty");
    }
    const auto normalized = std::filesystem::absolute(root_directory).lexically_normal();
    return StoragePaths{
        normalized,
        normalized / L"todos.json",
        normalized / L"native-settings.json"
    };
}

StoragePaths resolveLocalAppData() {
    PWSTR raw_path = nullptr;
    const HRESULT result = ::SHGetKnownFolderPath(
        FOLDERID_LocalAppData, KF_FLAG_DEFAULT, nullptr, &raw_path);
    if (FAILED(result)) {
        throw std::system_error(static_cast<int>(result), std::system_category(),
            "SHGetKnownFolderPath(FOLDERID_LocalAppData) failed");
    }
    std::unique_ptr<wchar_t, CoTaskMemDeleter> local_app_data(raw_path);
    if (!local_app_data) {
        throw std::runtime_error("SHGetKnownFolderPath returned an empty path");
    }
    return fromRootDirectory(std::filesystem::path(local_app_data.get()) / L"GhostPin");
}

void ensureDirectory(const StoragePaths& paths) {
    std::filesystem::create_directories(paths.root_directory);
    if (!std::filesystem::is_directory(paths.root_directory)) {
        throw std::filesystem::filesystem_error(
            "GhostPin storage root is not a directory",
            paths.root_directory,
            std::make_error_code(std::errc::not_a_directory));
    }
}

} // namespace ghostpin::storage
