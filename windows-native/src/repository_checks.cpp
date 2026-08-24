#include "repository.hpp"

#include <atomic>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

namespace {

bool expect(bool condition, const char* message, int& checks) {
    ++checks;
    if (!condition) std::cerr << "FAIL " << message << "\n";
    return condition;
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

ghostpin::core::Todo makeTodo(
    std::string id,
    std::string title,
    std::int64_t created_seconds,
    ghostpin::core::Status status = ghostpin::core::Status::Todo) {
    ghostpin::core::Todo item;
    item.id = std::move(id);
    item.title = std::move(title);
    item.created_at = ghostpin::core::TimePoint{std::chrono::seconds{created_seconds}};
    item.status = status;
    item.priority = ghostpin::core::Priority::Medium;
    return item;
}

std::string encode(const std::vector<ghostpin::core::Todo>& items) {
    ghostpin::codec::RuntimeApartment apartment;
    return ghostpin::codec::encodeTodos(items);
}

void writeText(const std::filesystem::path& path, std::string_view content) {
    std::ofstream stream(path, std::ios::binary | std::ios::trunc);
    if (!stream) throw std::runtime_error("failed to open test file");
    stream.write(content.data(), static_cast<std::streamsize>(content.size()));
    if (!stream) throw std::runtime_error("failed to write test file");
}

bool hasTemporaryFile(const std::filesystem::path& directory) {
    for (const auto& entry : std::filesystem::directory_iterator(directory)) {
        const auto name = entry.path().filename().string();
        if (name.size() >= 4 && name.ends_with(".tmp")) return true;
    }
    return false;
}

const ghostpin::core::Todo* findTodo(
    const std::vector<ghostpin::core::Todo>& items,
    std::string_view id) {
    for (const auto& item : items) {
        if (item.id == id) return &item;
    }
    return nullptr;
}

} // namespace

int main(int argc, char** argv) {
    int checks = 0;
    try {
        const auto token = std::chrono::steady_clock::now().time_since_epoch().count();
        const auto root = std::filesystem::temp_directory_path() /
            ("GhostPin.Native.RepositoryChecks-" + std::to_string(token));
        TemporaryDirectory temporary(root);
        std::filesystem::create_directories(root);

        const std::string first_id = "11111111-1111-4111-8111-111111111111";
        const std::string second_id = "22222222-2222-4222-8222-222222222222";
        const auto first = makeTodo(first_id, "first", 100);
        const auto second = makeTodo(second_id, "second", 200);
        const auto data_path = root / L"todos.json";

        ghostpin::storage::TodoRepository missing(root / L"missing" / L"todos.json");
        if (!expect(missing.load(), "missing file is a valid empty snapshot", checks)) return 1;
        if (!expect(missing.snapshot().empty() && !std::filesystem::exists(missing.filePath()),
            "missing load does not create a file", checks)) return 1;
        if (!expect(!missing.lastError().has_value(), "missing load clears diagnostics", checks)) return 1;

        ghostpin::storage::writeAtomically(data_path, encode({first, second}));
        if (!expect(!hasTemporaryFile(root), "successful atomic write cleans temporary file", checks)) return 1;

        const auto directory_target = root / L"directory-target";
        std::filesystem::create_directory(directory_target);
        bool atomic_error = false;
        try {
            ghostpin::storage::writeAtomically(directory_target, "cannot replace directory");
        } catch (const ghostpin::storage::AtomicWriteError& error) {
            atomic_error = error.win32Error() != 0 &&
                error.targetPath() == std::filesystem::absolute(directory_target).lexically_normal();
        }
        if (!expect(atomic_error && !hasTemporaryFile(root),
            "atomic replace failure reports Win32 code and cleans temporary file", checks)) return 1;

        ghostpin::storage::TodoRepository repository(data_path);
        if (!expect(repository.load(), "valid task file loads", checks)) return 1;
        if (!expect(repository.snapshot().size() == 2 &&
            repository.snapshot().front().id == second_id,
            "valid load preserves compatibility and createdAt order", checks)) return 1;
        const auto valid_snapshot = repository.snapshot();

        writeText(data_path, "[{\"id\":");
        const bool corrupt_loaded = repository.load();
        if (!expect(!corrupt_loaded, "corrupt task file is rejected", checks)) return 1;
        if (!expect(repository.snapshot().size() == valid_snapshot.size() &&
            repository.snapshot().front().id == valid_snapshot.front().id &&
            repository.lastError().has_value(),
            "corrupt load retains last valid snapshot with diagnostic", checks)) return 1;

        ghostpin::storage::writeAtomically(data_path, encode({first}));
        if (!expect(repository.load() && repository.snapshot().size() == 1,
            "valid replacement recovers the snapshot", checks)) return 1;
        if (!expect(!repository.lastError().has_value(), "recovery clears diagnostics", checks)) return 1;

        auto monotonic = std::int64_t{0};
        ghostpin::storage::TodoRepository competitive(
            data_path,
            {},
            [&] { return monotonic; });
        if (!expect(competitive.load(), "competitive repository loads baseline", checks)) return 1;
        std::atomic<bool> concurrent_ok{true};
        std::vector<std::thread> concurrent_readers;
        for (int index = 0; index < 4; ++index) {
            concurrent_readers.emplace_back([&] {
                for (int iteration = 0; iteration < 8; ++iteration) {
                    if (!competitive.load() || competitive.snapshot().size() != 1) {
                        concurrent_ok = false;
                        return;
                    }
                }
            });
        }
        for (auto& reader : concurrent_readers) reader.join();
        if (!expect(concurrent_ok.load(), "repository serializes cross-thread load and snapshot", checks)) return 1;
        auto externally_changed = makeTodo(first_id, "changed outside HUD", 100);
        externally_changed.description = std::string("external update");
        auto externally_added = makeTodo(second_id, "second external", 200);
        ghostpin::storage::writeAtomically(data_path, encode({externally_changed, externally_added}));
        const auto advanced = competitive.advanceById(
            first_id, ghostpin::core::TimePoint{std::chrono::seconds{300}});
        if (!expect(advanced.has_value() && advanced->status == ghostpin::core::Status::Doing,
            "advance succeeds after rereading external replacement", checks)) return 1;
        const auto competitive_snapshot = competitive.snapshot();
        const auto* changed = findTodo(competitive_snapshot, first_id);
        if (!expect(changed != nullptr && changed->title == "changed outside HUD" &&
            changed->description.has_value() && changed->status == ghostpin::core::Status::Doing,
            "advance applies to the latest UUID-matched fields", checks)) return 1;
        if (!expect(competitive.isCoolingDown(first_id), "successful advance starts cooldown", checks)) return 1;
        if (!expect(!competitive.advanceById(
            first_id, ghostpin::core::TimePoint{std::chrono::seconds{301}}).has_value(),
            "repeated advance inside cooldown is ignored", checks)) return 1;

        monotonic = 600;
        std::filesystem::remove(data_path);
        if (!expect(!competitive.advanceById(
            first_id, ghostpin::core::TimePoint{std::chrono::seconds{302}}).has_value(),
            "deleted UUID is not recreated", checks)) return 1;
        const auto retained_after_delete = competitive.snapshot();
        if (!expect(retained_after_delete.size() == 2 &&
            findTodo(retained_after_delete, first_id) != nullptr &&
            !std::filesystem::exists(data_path) && competitive.lastError().has_value(),
            "deleted source retains last valid snapshot without writing", checks)) return 1;

        ghostpin::storage::writeAtomically(data_path, encode({first}));
        bool fail_write = true;
        ghostpin::storage::TodoRepository rollback_repository(
            data_path,
            [&](const auto&, std::string_view content) {
                if (fail_write) throw std::runtime_error("injected atomic writer failure");
                ghostpin::storage::writeAtomically(data_path, content);
            },
            [&] { return monotonic; });
        if (!expect(rollback_repository.load(), "rollback repository loads source", checks)) return 1;
        bool threw = false;
        try {
            (void)rollback_repository.advanceById(
                first_id, ghostpin::core::TimePoint{std::chrono::seconds{400}});
        } catch (const std::runtime_error&) {
            threw = true;
        }
        if (!expect(threw, "atomic writer failure is surfaced", checks)) return 1;
        const auto rollback_snapshot = rollback_repository.snapshot();
        const auto* after_failure = findTodo(rollback_snapshot, first_id);
        if (!expect(after_failure != nullptr && after_failure->status == ghostpin::core::Status::Todo &&
            rollback_repository.lastError().has_value(),
            "write failure keeps snapshot and records diagnostic", checks)) return 1;
        fail_write = false;
        const auto retried = rollback_repository.advanceById(
            first_id, ghostpin::core::TimePoint{std::chrono::seconds{401}});
        if (!expect(retried.has_value() && retried->status == ghostpin::core::Status::Doing,
            "write failure rolls back cooldown for retry", checks)) return 1;
        if (!expect(!hasTemporaryFile(root), "failed and successful writes leave no temporary file", checks)) return 1;

        ghostpin::storage::TodoRepository* reentrant_repository = nullptr;
        bool reentry_rejected = false;
        ghostpin::storage::TodoRepository reentry_repository(
            data_path,
            [&](const auto& path, std::string_view content) {
                try {
                    (void)reentrant_repository->snapshot();
                } catch (const std::logic_error&) {
                    reentry_rejected = true;
                }
                ghostpin::storage::writeAtomically(path, content);
            },
            [&] { return monotonic + 600; });
        reentrant_repository = &reentry_repository;
        if (!expect(reentry_repository.load(), "reentry repository loads source", checks)) return 1;
        if (!expect(reentry_repository.advanceById(
            first_id, ghostpin::core::TimePoint{std::chrono::seconds{450}}).has_value() &&
            reentry_rejected,
            "worker reentry is rejected without deadlock", checks)) return 1;

        if (argc > 1) {
            const auto fixture = std::filesystem::path(argv[1]) / L"tasks-cross-language.json";
            const auto fixture_copy = root / L"fixture.json";
            std::filesystem::copy_file(fixture, fixture_copy);
            ghostpin::storage::TodoRepository fixture_repository(fixture_copy);
            if (!expect(fixture_repository.load() && !fixture_repository.snapshot().empty(),
                "cross-language fixture loads through repository", checks)) return 1;
            const auto fixture_id = fixture_repository.snapshot().front().id;
            const auto fixture_advanced = fixture_repository.advanceById(
                fixture_id, ghostpin::core::TimePoint{std::chrono::seconds{500}});
            if (!expect(fixture_advanced.has_value(),
                "fixture can be atomically written back after UUID advance", checks)) return 1;
            ghostpin::storage::TodoRepository fixture_reloaded(fixture_copy);
            const auto fixture_disk_snapshot = fixture_reloaded.load()
                ? fixture_reloaded.snapshot() : std::vector<ghostpin::core::Todo>{};
            const auto* fixture_disk_item = findTodo(fixture_disk_snapshot, fixture_id);
            if (!expect(fixture_disk_item != nullptr &&
                fixture_disk_item->status == fixture_advanced->status,
                "fixture writeback survives an independent disk reload", checks)) return 1;
            if (!expect(!hasTemporaryFile(root), "fixture writeback cleans temporary file", checks)) return 1;
        }
    } catch (const std::exception& error) {
        std::cerr << "FAIL unexpected repository check exception: " << error.what() << "\n";
        return 1;
    }

    std::cout << "PASS GhostPin.Native.RepositoryChecks (" << checks << " checks)\n";
    return 0;
}
