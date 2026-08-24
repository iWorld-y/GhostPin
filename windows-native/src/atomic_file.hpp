#pragma once

#include <filesystem>
#include <stdexcept>
#include <string>
#include <string_view>

namespace ghostpin::storage {

class AtomicWriteError final : public std::runtime_error {
public:
    AtomicWriteError(
        std::string message,
        std::filesystem::path target_path,
        std::filesystem::path temporary_path,
        unsigned long win32_error);

    const std::filesystem::path& targetPath() const noexcept;
    const std::filesystem::path& temporaryPath() const noexcept;
    unsigned long win32Error() const noexcept;

private:
    std::filesystem::path target_path_;
    std::filesystem::path temporary_path_;
    unsigned long win32_error_;
};

void writeAtomically(
    const std::filesystem::path& target_path,
    std::string_view utf8_content);

} // namespace ghostpin::storage
