#pragma once

#include "atomic_file.hpp"
#include "codec.hpp"
#include "core.hpp"

#include <filesystem>
#include <exception>
#include <condition_variable>
#include <deque>
#include <functional>
#include <future>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <thread>
#include <type_traits>
#include <utility>
#include <vector>

namespace ghostpin::storage {

struct RepositoryDiagnostic {
    std::string message;
    std::optional<unsigned long> win32_error;
};

class TodoRepository final {
public:
    using AtomicWriter = std::function<void(
        const std::filesystem::path&, std::string_view)>;
    using MonotonicClock = core::AdvanceService::MonotonicClock;

    explicit TodoRepository(
        std::filesystem::path file_path,
        AtomicWriter writer = {},
        MonotonicClock clock = {});

    TodoRepository(const TodoRepository&) = delete;
    TodoRepository& operator=(const TodoRepository&) = delete;
    ~TodoRepository();

    bool load();
    std::optional<core::Todo> advanceById(
        std::string_view id,
        core::TimePoint completed_at);

    const std::filesystem::path& filePath() const noexcept;
    std::vector<core::Todo> snapshot() const;
    std::optional<RepositoryDiagnostic> lastError() const;
    bool isCoolingDown(std::string_view id) const;

private:
    template <typename Function>
    auto submit(Function&& function) const -> std::invoke_result_t<Function>;
    void workerMain(std::promise<void> ready);
    void stopWorker() noexcept;
    bool reloadUnderLock();
    std::optional<core::Todo> advanceByIdUnderLock(
        std::string_view id,
        core::TimePoint completed_at);
    void publish(std::vector<core::Todo> items);
    void recordError(const std::exception& error);
    void clearError() noexcept;

    std::filesystem::path file_path_;
    AtomicWriter writer_;
    mutable std::mutex queue_mutex_;
    mutable std::condition_variable queue_condition_;
    mutable std::deque<std::function<void()>> jobs_;
    mutable bool stopping_{false};
    std::thread worker_;
    std::thread::id worker_id_;
    core::AdvanceService advance_;
    std::vector<core::Todo> snapshot_;
    std::optional<RepositoryDiagnostic> last_error_;
    bool has_loaded_{false};
};

template <typename Function>
auto TodoRepository::submit(Function&& function) const -> std::invoke_result_t<Function> {
    using Result = std::invoke_result_t<Function>;
    if (std::this_thread::get_id() == worker_id_) {
        throw std::logic_error("todo repository calls cannot re-enter its worker");
    }
    auto task = std::make_shared<std::packaged_task<Result()>>(
        std::forward<Function>(function));
    auto result = task->get_future();
    {
        std::lock_guard lock(queue_mutex_);
        if (stopping_) throw std::runtime_error("todo repository is stopped");
        jobs_.emplace_back([task] { (*task)(); });
    }
    queue_condition_.notify_one();
    return result.get();
}

} // namespace ghostpin::storage
