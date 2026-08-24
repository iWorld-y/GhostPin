#include "atomic_file.hpp"

#include <windows.h>

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <filesystem>
#include <limits>
#include <stdexcept>
#include <string>
#include <system_error>
#include <utility>

namespace ghostpin::storage {
namespace {

class UniqueHandle final {
public:
    explicit UniqueHandle(HANDLE value = INVALID_HANDLE_VALUE) noexcept : value_(value) {}
    ~UniqueHandle() {
        if (value_ != INVALID_HANDLE_VALUE) ::CloseHandle(value_);
    }

    UniqueHandle(const UniqueHandle&) = delete;
    UniqueHandle& operator=(const UniqueHandle&) = delete;
    UniqueHandle(UniqueHandle&& other) noexcept : value_(other.value_) {
        other.value_ = INVALID_HANDLE_VALUE;
    }
    UniqueHandle& operator=(UniqueHandle&& other) noexcept {
        if (this == &other) return *this;
        if (value_ != INVALID_HANDLE_VALUE) ::CloseHandle(value_);
        value_ = other.value_;
        other.value_ = INVALID_HANDLE_VALUE;
        return *this;
    }

    bool valid() const noexcept { return value_ != INVALID_HANDLE_VALUE; }
    HANDLE get() const noexcept { return value_; }

    bool close() noexcept {
        if (!valid()) return true;
        const bool result = ::CloseHandle(value_) != FALSE;
        value_ = INVALID_HANDLE_VALUE;
        return result;
    }

private:
    HANDLE value_;
};

std::atomic<std::uint64_t> nextTemporaryId{0};

std::string errorMessage(const char* operation, unsigned long error) {
    return std::string(operation) + " failed (Win32 error " + std::to_string(error) + ")";
}

std::filesystem::path temporaryPath(
    const std::filesystem::path& directory,
    const std::filesystem::path& target,
    std::uint64_t sequence) {
    const auto process = static_cast<unsigned long>(::GetCurrentProcessId());
    const auto name = "." + target.filename().string() + "." +
        std::to_string(process) + "." + std::to_string(sequence) + ".tmp";
    return directory / std::filesystem::path(name);
}

} // namespace

AtomicWriteError::AtomicWriteError(
    std::string message,
    std::filesystem::path target_path,
    std::filesystem::path temporary_path,
    unsigned long win32_error)
    : std::runtime_error(std::move(message)),
      target_path_(std::move(target_path)),
      temporary_path_(std::move(temporary_path)),
      win32_error_(win32_error) {
}

const std::filesystem::path& AtomicWriteError::targetPath() const noexcept {
    return target_path_;
}

const std::filesystem::path& AtomicWriteError::temporaryPath() const noexcept {
    return temporary_path_;
}

unsigned long AtomicWriteError::win32Error() const noexcept {
    return win32_error_;
}

void writeAtomically(
    const std::filesystem::path& raw_target_path,
    std::string_view utf8_content) {
    if (raw_target_path.empty()) {
        throw std::invalid_argument("atomic write target must not be empty");
    }

    const auto target_path = std::filesystem::absolute(raw_target_path).lexically_normal();
    const auto directory = target_path.parent_path();
    if (directory.empty()) {
        throw std::invalid_argument("atomic write target must include a directory");
    }
    std::filesystem::create_directories(directory);

    std::filesystem::path temporary_path;
    UniqueHandle temporary_file;
    for (std::size_t attempt = 0; attempt < 128; ++attempt) {
        const auto sequence = nextTemporaryId.fetch_add(1, std::memory_order_relaxed);
        temporary_path = temporaryPath(directory, target_path, sequence);
        const HANDLE value = ::CreateFileW(
            temporary_path.c_str(),
            GENERIC_WRITE,
            0,
            nullptr,
            CREATE_NEW,
            FILE_ATTRIBUTE_TEMPORARY | FILE_FLAG_WRITE_THROUGH,
            nullptr);
        if (value != INVALID_HANDLE_VALUE) {
            temporary_file = UniqueHandle(value);
            break;
        }

        const auto error = ::GetLastError();
        if (error != ERROR_FILE_EXISTS && error != ERROR_ALREADY_EXISTS) {
            throw AtomicWriteError(
                errorMessage("CreateFileW", error), target_path, temporary_path, error);
        }
    }
    if (!temporary_file.valid()) {
        throw AtomicWriteError(
            errorMessage("CreateFileW exhausted unique temporary names", ERROR_FILE_EXISTS),
            target_path,
            temporary_path,
            ERROR_FILE_EXISTS);
    }

    const auto cleanup = [&]() -> unsigned long {
        unsigned long first_error = ERROR_SUCCESS;
        if (temporary_file.valid() && !temporary_file.close()) {
            first_error = ::GetLastError();
            if (first_error == ERROR_SUCCESS) first_error = ERROR_INVALID_HANDLE;
        }
        std::error_code error;
        std::filesystem::remove(temporary_path, error);
        if (error && first_error == ERROR_SUCCESS) first_error = ERROR_GEN_FAILURE;
        return first_error;
    };
    try {
        std::size_t offset = 0;
        while (offset < utf8_content.size()) {
            const auto remaining = utf8_content.size() - offset;
            const auto chunk = static_cast<DWORD>(std::min<std::size_t>(
                remaining, static_cast<std::size_t>(std::numeric_limits<DWORD>::max())));
            DWORD written = 0;
            if (!::WriteFile(
                temporary_file.get(), utf8_content.data() + offset, chunk, &written, nullptr)) {
                auto error = ::GetLastError();
                if (error == ERROR_SUCCESS) error = ERROR_WRITE_FAULT;
                throw AtomicWriteError(
                    errorMessage("WriteFile", error), target_path, temporary_path, error);
            }
            if (written == 0 || written > chunk) {
                throw AtomicWriteError(
                    errorMessage("WriteFile returned an invalid byte count", ERROR_WRITE_FAULT),
                    target_path,
                    temporary_path,
                    ERROR_WRITE_FAULT);
            }
            offset += written;
        }
        if (!::FlushFileBuffers(temporary_file.get())) {
            const auto error = ::GetLastError();
            throw AtomicWriteError(
                errorMessage("FlushFileBuffers", error), target_path, temporary_path, error);
        }
        if (!temporary_file.close()) {
            const auto error = ::GetLastError();
            throw AtomicWriteError(
                errorMessage("CloseHandle", error), target_path, temporary_path, error);
        }

        const DWORD target_attributes = ::GetFileAttributesW(target_path.c_str());
        const bool target_exists = target_attributes != INVALID_FILE_ATTRIBUTES;
        const auto target_error = target_exists ? ERROR_SUCCESS : ::GetLastError();
        if (!target_exists && target_error != ERROR_FILE_NOT_FOUND &&
            target_error != ERROR_PATH_NOT_FOUND) {
            throw AtomicWriteError(
                errorMessage("GetFileAttributesW", target_error),
                target_path,
                temporary_path,
                target_error);
        }

        bool replaced = false;
        unsigned long replace_error = ERROR_SUCCESS;
        if (target_exists && ::ReplaceFileW(
            target_path.c_str(), temporary_path.c_str(), nullptr,
            0, nullptr, nullptr)) {
            replaced = true;
        } else if (target_exists) {
            replace_error = ::GetLastError();
            if (replace_error != ERROR_FILE_NOT_FOUND &&
                replace_error != ERROR_PATH_NOT_FOUND) {
                throw AtomicWriteError(
                    errorMessage("ReplaceFileW", replace_error),
                    target_path,
                    temporary_path,
                    replace_error);
            }
        }

        if (!replaced) {
            if (!::MoveFileExW(
                temporary_path.c_str(), target_path.c_str(),
                MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
                const auto error = ::GetLastError();
                std::string message = errorMessage("MoveFileExW fallback", error);
                if (replace_error != ERROR_SUCCESS) {
                    message += "; ReplaceFileW failed (Win32 error " +
                        std::to_string(replace_error) + ")";
                }
                throw AtomicWriteError(
                    std::move(message),
                    target_path,
                    temporary_path,
                    error);
            }
        }
    } catch (const AtomicWriteError& error) {
        const auto cleanup_error = cleanup();
        if (cleanup_error != ERROR_SUCCESS) {
            throw AtomicWriteError(
                std::string(error.what()) + "; temporary cleanup failed (Win32 error " +
                    std::to_string(cleanup_error) + ")",
                target_path,
                temporary_path,
                error.win32Error());
        }
        throw;
    } catch (...) {
        cleanup();
        throw;
    }

    // ReplaceFileW/MoveFileExW 消费了同目录临时文件；成功提交后不再把清理误报为写失败。
}

} // namespace ghostpin::storage
