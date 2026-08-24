#pragma once

#include <filesystem>

namespace ghostpin::storage {

struct StoragePaths {
    std::filesystem::path root_directory;
    std::filesystem::path todos_file;
    std::filesystem::path native_settings_file;
};

StoragePaths fromRootDirectory(const std::filesystem::path& root_directory);
StoragePaths resolveLocalAppData();
void ensureDirectory(const StoragePaths& paths);

} // namespace ghostpin::storage
