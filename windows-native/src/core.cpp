#include "core.hpp"

#include <algorithm>
#include <cmath>
#include <iterator>
#include <limits>

namespace ghostpin::core {
namespace {

std::int64_t monotonicMilliseconds() {
    static const auto origin = std::chrono::steady_clock::now();
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - origin).count();
}

int priorityRank(Priority priority) {
    switch (priority) {
    case Priority::High: return 3;
    case Priority::Medium: return 2;
    case Priority::Low: return 1;
    }
    return 0;
}

char foldAscii(char value) noexcept {
    return value >= 'A' && value <= 'Z'
        ? static_cast<char>(value - 'A' + 'a') : value;
}

bool equalsIgnoreCase(std::string_view left, std::string_view right) noexcept {
    if (left.size() != right.size()) return false;
    for (std::size_t index = 0; index < left.size(); ++index) {
        if (foldAscii(left[index]) != foldAscii(right[index])) return false;
    }
    return true;
}

bool inScope(const Todo& item, const ProjectionOptions& options) {
    return options.scope == HudScope::All || item.created_at >= options.today_start;
}

const MonitorWorkArea* selectMonitor(
    const Placement& placement,
    const std::vector<MonitorWorkArea>& monitors,
    std::string_view primary_monitor_id) {
    const auto saved = std::find_if(monitors.begin(), monitors.end(),
        [&](const MonitorWorkArea& monitor) {
            return equalsIgnoreCase(monitor.id, placement.monitor_id);
        });
    if (saved != monitors.end()) {
        return &*saved;
    }
    const auto primary = std::find_if(monitors.begin(), monitors.end(),
        [&](const MonitorWorkArea& monitor) {
            return equalsIgnoreCase(monitor.id, primary_monitor_id) || monitor.primary;
        });
    return primary == monitors.end() ? (monitors.empty() ? nullptr : &monitors.front()) : &*primary;
}

int roundToInt(double value) noexcept {
    const double minimum = static_cast<double>(std::numeric_limits<int>::min());
    const double maximum = static_cast<double>(std::numeric_limits<int>::max());
    if (!std::isfinite(value)) return value < 0 ? std::numeric_limits<int>::min() :
        std::numeric_limits<int>::max();
    if (value <= minimum) return std::numeric_limits<int>::min();
    if (value >= maximum) return std::numeric_limits<int>::max();
    return static_cast<int>(std::lround(value));
}

int saturatedAdd(int value, int offset) noexcept {
    const auto result = static_cast<std::int64_t>(value) + offset;
    if (result <= std::numeric_limits<int>::min()) return std::numeric_limits<int>::min();
    if (result >= std::numeric_limits<int>::max()) return std::numeric_limits<int>::max();
    return static_cast<int>(result);
}

} // namespace

bool isCompleted(const Todo& item) noexcept {
    return item.status == Status::Done;
}

bool isOverdue(const Todo& item, TimePoint now) noexcept {
    return item.due_at.has_value() && !isCompleted(item) && item.due_at.value() < now;
}

Projection project(const std::vector<Todo>& source, const ProjectionOptions& options) {
    std::vector<Todo> ordered;
    ordered.reserve(source.size());
    for (const auto& item : source) {
        if (!isCompleted(item) && inScope(item, options)) {
            ordered.push_back(item);
        }
    }

    std::stable_sort(ordered.begin(), ordered.end(), [&](const Todo& left, const Todo& right) {
        const int left_status = left.status == Status::Doing ? 0 : 1;
        const int right_status = right.status == Status::Doing ? 0 : 1;
        if (left_status != right_status) return left_status < right_status;
        const int left_overdue = isOverdue(left, options.now) ? 1 : 0;
        const int right_overdue = isOverdue(right, options.now) ? 1 : 0;
        if (left_overdue != right_overdue) return left_overdue < right_overdue;
        if (priorityRank(left.priority) != priorityRank(right.priority)) {
            return priorityRank(left.priority) > priorityRank(right.priority);
        }
        const auto left_due = left.due_at.value_or(TimePoint::max());
        const auto right_due = right.due_at.value_or(TimePoint::max());
        if (left_due != right_due) return left_due < right_due;
        return left.created_at > right.created_at;
    });

    const int count = std::max(options.max_count, 0);
    if (static_cast<int>(ordered.size()) > count) {
        ordered.resize(static_cast<std::size_t>(count));
    }

    Projection result;
    result.items = ordered;
    for (const auto& item : ordered) {
        if (item.status == Status::Doing) result.doing.push_back(item);
        if (item.status == Status::Todo) result.todo.push_back(item);
    }
    return result;
}

AdvanceService::AdvanceService(MonotonicClock clock)
    : clock_(clock ? std::move(clock) : monotonicMilliseconds) {
}

bool AdvanceService::advance(Todo& item, TimePoint completed_at) {
    const auto next = nextStatus(item.status);
    if (!next.has_value() || isCoolingDown(item.id)) return false;
    item.status = next.value();
    item.completed_at = next.value() == Status::Done
        ? std::optional<TimePoint>{completed_at} : std::nullopt;
    const auto now = clock_();
    const auto found = std::find_if(last_successful_.begin(), last_successful_.end(),
        [&](const auto& entry) { return entry.first == item.id; });
    if (found == last_successful_.end()) {
        last_successful_.emplace_back(item.id, now);
    } else {
        found->second = now;
    }
    return true;
}

std::optional<AdvanceResult> AdvanceService::advanceById(
    std::vector<Todo>& items,
    std::string_view id,
    TimePoint completed_at) {
    const auto found = std::find_if(items.begin(), items.end(),
        [&](const Todo& item) { return item.id == id; });
    if (found == items.end()) return std::nullopt;
    const auto index = static_cast<std::size_t>(std::distance(items.begin(), found));
    if (!advance(*found, completed_at)) return std::nullopt;
    return AdvanceResult{index, found->status};
}

bool AdvanceService::isCoolingDown(std::string_view id) const {
    const auto found = std::find_if(last_successful_.begin(), last_successful_.end(),
        [&](const auto& entry) { return entry.first == id; });
    return found != last_successful_.end() && clock_() - found->second < 500;
}

void AdvanceService::rollback(std::string_view id) {
    last_successful_.erase(std::remove_if(last_successful_.begin(), last_successful_.end(),
        [&](const auto& entry) { return entry.first == id; }), last_successful_.end());
}

std::optional<Status> nextStatus(Status status) noexcept {
    switch (status) {
    case Status::Todo: return Status::Doing;
    case Status::Doing: return Status::Done;
    case Status::Done: return std::nullopt;
    }
    return std::nullopt;
}

Placement normalize(Placement placement) {
    if (!std::isfinite(placement.relative_x)) placement.relative_x = 0;
    if (!std::isfinite(placement.relative_y)) placement.relative_y = 0;
    if (!std::isfinite(placement.logical_width) || placement.logical_width < 300.0 ||
        placement.logical_width > 1920.0) placement.logical_width = 360;
    if (!std::isfinite(placement.logical_height) || placement.logical_height < 280.0 ||
        placement.logical_height > 1600.0) placement.logical_height = 460;
    if (placement.dpi < 48 || placement.dpi > 768) placement.dpi = 96;
    return placement;
}

bool isModifierKey(std::uint32_t key) noexcept {
    return key == 0x10u || key == 0x11u || key == 0x12u ||
        key == 0x5Bu || key == 0x5Cu || (key >= 0xA0u && key <= 0xA5u);
}

std::optional<HotkeyCandidate> normalizeHotkey(
    std::uint32_t modifiers,
    std::uint32_t key) noexcept {
    constexpr std::uint32_t allowed = kHotkeyShift | kHotkeyControl |
        kHotkeyAlt | kHotkeyWin;
    modifiers &= allowed;
    if (isModifierKey(key)) return std::nullopt;
    const bool has_modifier = (modifiers & allowed) != 0;
    const bool function_key = key >= 0x70u && key <= 0x83u;
    const bool regular_key = key > 0 && key <= 0xFFu;
    if (!((has_modifier && regular_key) || (!has_modifier && function_key))) {
        return std::nullopt;
    }
    return HotkeyCandidate{modifiers, key};
}

bool validHotkey(std::uint32_t modifiers, std::uint32_t key) noexcept {
    return normalizeHotkey(modifiers, key).has_value();
}

HudSettings normalize(HudSettings settings) {
    if (settings.mode != HudMode::Passthrough && settings.mode != HudMode::Interactive) {
        settings.mode = HudMode::Passthrough;
    }
    if (settings.scope != HudScope::All && settings.scope != HudScope::Today) {
        settings.scope = HudScope::All;
    }
    if (!std::isfinite(settings.opacity) || settings.opacity < 0.5 || settings.opacity > 1.0) {
        settings.opacity = 1.0;
    }
    if (settings.max_items < 1 || settings.max_items > 20) settings.max_items = 8;
    settings.placement = normalize(settings.placement);
    const auto hotkey = normalizeHotkey(settings.hotkey_modifiers, settings.hotkey_key);
    if (hotkey.has_value()) {
        settings.hotkey_modifiers = hotkey->modifiers;
        settings.hotkey_key = hotkey->key;
    } else {
        settings.hotkey_enabled = false;
        settings.hotkey_modifiers = 0;
        settings.hotkey_key = 0;
    }
    return settings;
}

PixelRect restorePlacement(
    const Placement& raw_placement,
    const std::vector<MonitorWorkArea>& monitors,
    std::string_view primary_monitor_id) {
    const Placement placement = normalize(raw_placement);
    const MonitorWorkArea* monitor = selectMonitor(placement, monitors, primary_monitor_id);
    if (monitor == nullptr) return {0, 0, 300, 280};
    const double scale = static_cast<double>(std::max(monitor->dpi, 1u)) / 96.0;
    const double area_width = std::max(
        static_cast<double>(monitor->right) - monitor->left, 1.0);
    const double area_height = std::max(
        static_cast<double>(monitor->bottom) - monitor->top, 1.0);
    const double int_max = static_cast<double>(std::numeric_limits<int>::max());
    const double bounded_area_width = std::min(area_width, int_max);
    const double bounded_area_height = std::min(area_height, int_max);
    const double minimum_width = std::min(300.0 * scale, bounded_area_width);
    const double minimum_height = std::min(280.0 * scale, bounded_area_height);
    const int width = std::max(1, roundToInt(std::clamp(
        placement.logical_width * scale, minimum_width, bounded_area_width)));
    const int height = std::max(1, roundToInt(std::clamp(
        placement.logical_height * scale, minimum_height, bounded_area_height)));
    const double left_minimum = static_cast<double>(monitor->left);
    const double top_minimum = static_cast<double>(monitor->top);
    const double left_maximum = std::max(left_minimum,
        static_cast<double>(monitor->right) - width);
    const double top_maximum = std::max(top_minimum,
        static_cast<double>(monitor->bottom) - height);
    const double left_relative_maximum = (left_maximum - left_minimum) / scale;
    const double top_relative_maximum = (top_maximum - top_minimum) / scale;
    const double desired_left = left_minimum +
        std::clamp(placement.relative_x, 0.0, left_relative_maximum) * scale;
    const double desired_top = top_minimum +
        std::clamp(placement.relative_y, 0.0, top_relative_maximum) * scale;
    const int left = roundToInt(std::clamp(desired_left, left_minimum, left_maximum));
    const int top = roundToInt(std::clamp(desired_top, top_minimum, top_maximum));
    return {
        left,
        top,
        saturatedAdd(left, width),
        saturatedAdd(top, height)
    };
}

Placement savePlacement(const PixelRect& rect, const MonitorWorkArea& monitor) {
    const std::uint32_t dpi = monitor.dpi < 48 ? 96 : monitor.dpi;
    const double scale = 96.0 / static_cast<double>(dpi);
    Placement placement;
    placement.monitor_id = monitor.id;
    placement.relative_x = (rect.left - monitor.left) * scale;
    placement.relative_y = (rect.top - monitor.top) * scale;
    placement.logical_width = (rect.right - rect.left) * scale;
    placement.logical_height = (rect.bottom - rect.top) * scale;
    placement.dpi = dpi;
    return normalize(placement);
}

} // namespace ghostpin::core
