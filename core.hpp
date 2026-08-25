#pragma once

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace ghostpin::core {

using TimePoint = std::chrono::system_clock::time_point;

enum class Status {
    Todo,
    Doing,
    Done,
};

enum class Priority {
    High,
    Medium,
    Low,
};

enum class HudScope {
    All,
    Today,
};

enum class HudMode {
    Passthrough,
    Interactive,
};

struct Todo {
    std::string id;
    std::string title;
    TimePoint created_at{};
    Status status{Status::Todo};
    std::optional<TimePoint> completed_at;
    std::optional<TimePoint> reminder_at;
    std::optional<TimePoint> reminder_sent_at;
    Priority priority{Priority::Medium};
    std::optional<TimePoint> due_at;
    std::optional<std::string> description;
};

bool isCompleted(const Todo& item) noexcept;
bool isOverdue(const Todo& item, TimePoint now) noexcept;

struct ProjectionOptions {
    HudScope scope{HudScope::All};
    int max_count{8};
    TimePoint now{};
    TimePoint today_start{};
};

struct Projection {
    std::vector<Todo> items;
    std::vector<Todo> doing;
    std::vector<Todo> todo;
};

Projection project(const std::vector<Todo>& source, const ProjectionOptions& options);

struct AdvanceResult {
    std::size_t index{0};
    Status status{Status::Todo};
};

class AdvanceService final {
public:
    using MonotonicClock = std::function<std::int64_t()>;

    explicit AdvanceService(MonotonicClock clock = {});
    bool advance(Todo& item, TimePoint completed_at);
    std::optional<AdvanceResult> advanceById(
        std::vector<Todo>& items,
        std::string_view id,
        TimePoint completed_at);
    bool isCoolingDown(std::string_view id) const;
    void rollback(std::string_view id);

private:
    MonotonicClock clock_;
    std::vector<std::pair<std::string, std::int64_t>> last_successful_;
};

std::optional<Status> nextStatus(Status status) noexcept;

struct Placement {
    std::string monitor_id;
    double relative_x{0};
    double relative_y{0};
    double logical_width{360};
    double logical_height{460};
    std::uint32_t dpi{96};
};

struct HudSettings {
    bool visible{true};
    bool launch_at_login{false};
    HudMode mode{HudMode::Passthrough};
    bool topmost{true};
    double opacity{1.0};
    HudScope scope{HudScope::All};
    int max_items{8};
    bool hotkey_enabled{false};
    std::uint32_t hotkey_modifiers{0};
    std::uint32_t hotkey_key{0};
    Placement placement{};
};

struct HotkeyCandidate {
    std::uint32_t modifiers{0};
    std::uint32_t key{0};
};

HudSettings normalize(HudSettings settings);
Placement normalize(Placement placement);
std::optional<HotkeyCandidate> normalizeHotkey(
    std::uint32_t modifiers,
    std::uint32_t key) noexcept;
bool validHotkey(std::uint32_t modifiers, std::uint32_t key) noexcept;

struct MonitorWorkArea {
    std::string id;
    int left{0};
    int top{0};
    int right{0};
    int bottom{0};
    std::uint32_t dpi{96};
    bool primary{false};
};

struct PixelRect {
    int left{0};
    int top{0};
    int right{0};
    int bottom{0};
};

PixelRect restorePlacement(
    const Placement& placement,
    const std::vector<MonitorWorkArea>& monitors,
    std::string_view primary_monitor_id);

Placement savePlacement(const PixelRect& rect, const MonitorWorkArea& monitor);

constexpr std::uint32_t kHotkeyAlt = 0x0001u;
constexpr std::uint32_t kHotkeyControl = 0x0002u;
constexpr std::uint32_t kHotkeyShift = 0x0004u;
constexpr std::uint32_t kHotkeyWin = 0x0008u;
constexpr std::uint32_t kHotkeyNoRepeat = 0x4000u;

constexpr std::uint32_t nativePrototypeVersion() noexcept {
    return 2;
}

} // namespace ghostpin::core
