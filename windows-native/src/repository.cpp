#include "repository.hpp"

#include <algorithm>
#include <fstream>
#include <iterator>
#include <stdexcept>
#include <system_error>
#include <utility>

namespace ghostpin::storage {
namespace {

std::filesystem::path normalizeFilePath(std::filesystem::path path) {
    if (path.empty()) {
        throw std::invalid_argument("todo repository path must not be empty");
    }
    return std::filesystem::absolute(std::move(path)).lexically_normal();
}

std::string readUtf8(const std::filesystem::path& path) {
    std::ifstream stream(path, std::ios::binary);
    if (!stream) {
        throw std::runtime_error("unable to open todo file for reading");
    }
    const std::istreambuf_iterator<char> begin(stream);
    const std::istreambuf_iterator<char> end;
    std::string content(begin, end);
    if (stream.bad()) {
        throw std::runtime_error("unable to read todo file");
    }
    return content;
}

void sortByCreatedAt(std::vector<core::Todo>& items) {
    std::stable_sort(items.begin(), items.end(), [](const auto& left, const auto& right) {
        return left.created_at > right.created_at;
    });
}

} // namespace

TodoRepository::TodoRepository(
    std::filesystem::path file_path,
    AtomicWriter writer,
    MonotonicClock clock)
    : file_path_(normalizeFilePath(std::move(file_path))),
      writer_(writer ? std::move(writer) : writeAtomically),
      advance_(std::move(clock)) {
    std::promise<void> ready;
    auto initialized = ready.get_future();
    worker_ = std::thread(
        [this, ready = std::move(ready)]() mutable { workerMain(std::move(ready)); });
    try {
        initialized.get();
    } catch (...) {
        stopWorker();
        throw;
    }
}

TodoRepository::~TodoRepository() {
    stopWorker();
}

bool TodoRepository::load() {
    return submit([this] { return reloadUnderLock(); });
}

std::optional<core::Todo> TodoRepository::advanceById(
    std::string_view id,
    core::TimePoint completed_at) {
    return submit([this, id = std::string(id), completed_at] {
        return advanceByIdUnderLock(id, completed_at);
    });
}

const std::filesystem::path& TodoRepository::filePath() const noexcept {
    return file_path_;
}

std::vector<core::Todo> TodoRepository::snapshot() const {
    return submit([self = const_cast<TodoRepository*>(this)] { return self->snapshot_; });
}

std::optional<RepositoryDiagnostic> TodoRepository::lastError() const {
    return submit([self = const_cast<TodoRepository*>(this)] { return self->last_error_; });
}

bool TodoRepository::isCoolingDown(std::string_view id) const {
    return submit([self = const_cast<TodoRepository*>(this), id = std::string(id)] {
        return self->advance_.isCoolingDown(id);
    });
}

void TodoRepository::workerMain(std::promise<void> ready) {
    bool signaled = false;
    try {
        worker_id_ = std::this_thread::get_id();
        codec::RuntimeApartment apartment;
        ready.set_value();
        signaled = true;

        for (;;) {
            std::function<void()> job;
            {
                std::unique_lock lock(queue_mutex_);
                queue_condition_.wait(lock, [this] {
                    return stopping_ || !jobs_.empty();
                });
                if (stopping_ && jobs_.empty()) return;
                job = std::move(jobs_.front());
                jobs_.pop_front();
            }
            job();
        }
    } catch (...) {
        if (!signaled) {
            try {
                ready.set_exception(std::current_exception());
            } catch (const std::future_error&) {
            }
        }
        {
            std::lock_guard lock(queue_mutex_);
            stopping_ = true;
        }
        queue_condition_.notify_all();
    }
}

void TodoRepository::stopWorker() noexcept {
    {
        std::lock_guard lock(queue_mutex_);
        stopping_ = true;
    }
    queue_condition_.notify_all();
    if (worker_.joinable()) worker_.join();
}

bool TodoRepository::reloadUnderLock() {
    std::error_code exists_error;
    const bool exists = std::filesystem::exists(file_path_, exists_error);
    if (exists_error) {
        const std::system_error error(exists_error, "checking todo file");
        recordError(error);
        if (!has_loaded_) {
            snapshot_.clear();
            has_loaded_ = true;
        }
        return false;
    }
    if (!exists) {
        if (has_loaded_) {
            const std::runtime_error error("todo file is missing; retaining last valid snapshot");
            recordError(error);
            return false;
        }
        clearError();
        publish({});
        has_loaded_ = true;
        return true;
    }

    try {
        auto items = codec::decodeTodos(readUtf8(file_path_));
        sortByCreatedAt(items);
        clearError();
        publish(std::move(items));
        has_loaded_ = true;
        return true;
    } catch (const std::exception& error) {
        recordError(error);
        if (!has_loaded_) {
            snapshot_.clear();
            has_loaded_ = true;
        }
        return false;
    } catch (...) {
        const std::runtime_error error("unknown todo file reload failure");
        recordError(error);
        if (!has_loaded_) {
            snapshot_.clear();
            has_loaded_ = true;
        }
        return false;
    }
}

std::optional<core::Todo> TodoRepository::advanceByIdUnderLock(
    std::string_view id,
    core::TimePoint completed_at) {
    if (!reloadUnderLock()) return std::nullopt;

    auto next_snapshot = snapshot_;
    const auto result = advance_.advanceById(next_snapshot, id, completed_at);
    if (!result.has_value()) return std::nullopt;

    try {
        const auto encoded = codec::encodeTodos(next_snapshot);
        writer_(file_path_, encoded);
    } catch (const std::exception& error) {
        advance_.rollback(id);
        recordError(error);
        throw;
    } catch (...) {
        advance_.rollback(id);
        throw;
    }

    clearError();
    publish(std::move(next_snapshot));
    return snapshot_[result->index];
}

void TodoRepository::publish(std::vector<core::Todo> items) {
    snapshot_ = std::move(items);
}

void TodoRepository::recordError(const std::exception& error) {
    const auto* atomic_error = dynamic_cast<const AtomicWriteError*>(&error);
    const auto* system_error = dynamic_cast<const std::system_error*>(&error);
    std::optional<unsigned long> win32_error;
    if (atomic_error != nullptr) {
        win32_error = atomic_error->win32Error();
    } else if (system_error != nullptr && system_error->code().value() > 0) {
        win32_error = static_cast<unsigned long>(system_error->code().value());
    }
    last_error_ = RepositoryDiagnostic{
        error.what(),
        win32_error
    };
}

void TodoRepository::clearError() noexcept {
    last_error_.reset();
}

} // namespace ghostpin::storage
