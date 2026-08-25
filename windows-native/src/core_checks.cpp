#include "core.hpp"

#include <chrono>
#include <cmath>
#include <iomanip>
#include <initializer_list>
#include <iostream>
#include <limits>
#include <optional>
#include <sstream>
#include <string>
#include <string_view>
#include <vector>

using namespace ghostpin::core;

namespace {

bool expect(bool condition, const char* message, int& checks) {
    ++checks;
    if (!condition) {
        std::cerr << "FAIL " << message << "\n";
        return false;
    }
    return true;
}

TimePoint testTime(
    int year_value,
    unsigned month_value,
    unsigned day_value,
    int hour,
    int minute,
    int second) {
    using namespace std::chrono;
    const auto value = sys_days{year{year_value} / month{month_value} / day{day_value}} +
        hours{hour} + minutes{minute} +
        seconds{second};
    return TimePoint{duration_cast<TimePoint::duration>(value.time_since_epoch())};
}

std::string formatTestTime(TimePoint value) {
    using namespace std::chrono;
    const auto whole_seconds = floor<seconds>(value);
    const auto day = floor<days>(whole_seconds);
    const year_month_day date{day};
    const auto time = whole_seconds - day;
    const auto hour = duration_cast<hours>(time).count();
    const auto minute = duration_cast<minutes>(time - hours{hour}).count();
    const auto second = duration_cast<seconds>(
        time - hours{hour} - minutes{minute}).count();
    std::ostringstream stream;
    stream << static_cast<int>(date.year()) << '-'
        << std::setfill('0') << std::setw(2) << static_cast<unsigned>(date.month()) << '-'
        << std::setfill('0') << std::setw(2) << static_cast<unsigned>(date.day()) << 'T'
        << std::setfill('0') << std::setw(2) << hour << ':'
        << std::setfill('0') << std::setw(2) << minute << ':'
        << std::setfill('0') << std::setw(2) << second << 'Z';
    return stream.str();
}

Todo makeTodo(
    std::string id,
    Status status,
    Priority priority,
    TimePoint created,
    std::optional<TimePoint> due = std::nullopt) {
    Todo item;
    item.id = std::move(id);
    item.title = item.id;
    item.status = status;
    item.priority = priority;
    item.created_at = created;
    item.due_at = due;
    return item;
}

bool expectIds(
    const std::vector<Todo>& items,
    std::initializer_list<std::string_view> expected,
    const char* message,
    int& checks) {
    ++checks;
    if (items.size() != expected.size()) {
        std::cerr << "FAIL " << message << " (count)\n";
        return false;
    }
    std::size_t index = 0;
    for (const auto id : expected) {
        if (items[index++].id != id) {
            std::cerr << "FAIL " << message << " (order)\n";
            return false;
        }
    }
    return true;
}

bool sameTodo(const Todo& left, const Todo& right) {
    return left.id == right.id && left.title == right.title &&
        left.created_at == right.created_at && left.status == right.status &&
        left.completed_at == right.completed_at && left.reminder_at == right.reminder_at &&
        left.reminder_sent_at == right.reminder_sent_at && left.priority == right.priority &&
        left.due_at == right.due_at && left.description == right.description;
}

bool sameTodos(const std::vector<Todo>& left, const std::vector<Todo>& right) {
    if (left.size() != right.size()) return false;
    for (std::size_t index = 0; index < left.size(); ++index) {
        if (!sameTodo(left[index], right[index])) return false;
    }
    return true;
}

} // namespace

int main() {
    int checks = 0;
    const auto now = testTime(2026, 8, 21, 8, 0, 0);
    const auto today_start = testTime(2026, 8, 21, 0, 0, 0);

    if (!expect(formatTestTime(now) == "2026-08-21T08:00:00Z",
        "chrono test time formatting", checks)) return 1;

    const std::vector<Todo> source{
        makeTodo("todo-low", Status::Todo, Priority::Low, testTime(2026, 8, 21, 6, 0, 0)),
        makeTodo("doing-high", Status::Doing, Priority::High, testTime(2026, 8, 21, 5, 0, 0)),
        makeTodo("doing-overdue", Status::Doing, Priority::Medium,
            testTime(2026, 8, 20, 5, 0, 0), testTime(2026, 8, 21, 7, 0, 0)),
        makeTodo("todo-high", Status::Todo, Priority::High, testTime(2026, 8, 21, 7, 0, 0),
            testTime(2026, 8, 21, 9, 0, 0)),
        makeTodo("old", Status::Todo, Priority::High, testTime(2026, 8, 20, 7, 0, 0)),
        makeTodo("done", Status::Done, Priority::High, testTime(2026, 8, 21, 7, 0, 0))
    };

    ProjectionOptions all_options;
    all_options.scope = HudScope::All;
    all_options.max_count = 4;
    all_options.now = now;
    all_options.today_start = today_start;
    const auto all = project(source, all_options);
    if (!expect(all.items.size() == 4, "all projection max count", checks)) return 1;
    if (!expect(all.items[0].id == "doing-high" &&
        all.items[1].id == "doing-overdue", "doing ordering", checks)) return 1;
    if (!expect(all.doing.size() == 2 && all.todo.size() == 2,
        "projection sections", checks)) return 1;

    all_options.scope = HudScope::Today;
    all_options.max_count = 20;
    const auto today = project(source, all_options);
    if (!expect(today.items.size() == 3, "today scope excludes old and done", checks)) return 1;
    all_options.max_count = 0;
    if (!expect(project(source, all_options).items.empty(), "zero max count is empty", checks)) return 1;

    const auto golden_now = testTime(2026, 8, 21, 8, 0, 0);
    const std::vector<Todo> golden_source{
        makeTodo("doing-high-future", Status::Doing, Priority::High,
            testTime(2026, 8, 21, 7, 0, 0), testTime(2026, 8, 21, 10, 0, 0)),
        makeTodo("doing-medium-future", Status::Doing, Priority::Medium,
            testTime(2026, 8, 21, 7, 30, 0), testTime(2026, 8, 21, 9, 0, 0)),
        makeTodo("doing-low-overdue", Status::Doing, Priority::Low,
            testTime(2026, 8, 20, 7, 0, 0), testTime(2026, 8, 21, 7, 0, 0)),
        makeTodo("todo-high-equal", Status::Todo, Priority::High,
            testTime(2026, 8, 21, 7, 0, 0), golden_now),
        makeTodo("todo-medium-earlier", Status::Todo, Priority::Medium,
            testTime(2026, 8, 21, 6, 0, 0), testTime(2026, 8, 21, 8, 30, 0)),
        makeTodo("todo-medium-later", Status::Todo, Priority::Medium,
            testTime(2026, 8, 21, 7, 0, 0), testTime(2026, 8, 21, 9, 0, 0)),
        makeTodo("todo-low-old", Status::Todo, Priority::Low,
            testTime(2026, 8, 21, 5, 0, 0), testTime(2026, 8, 21, 11, 0, 0)),
        makeTodo("todo-low-new", Status::Todo, Priority::Low,
            testTime(2026, 8, 21, 7, 30, 0), testTime(2026, 8, 21, 11, 0, 0)),
        makeTodo("todo-low-no-due", Status::Todo, Priority::Low,
            testTime(2026, 8, 21, 7, 15, 0)),
        makeTodo("todo-high-overdue", Status::Todo, Priority::High,
            testTime(2026, 8, 21, 7, 45, 0), testTime(2026, 8, 21, 7, 0, 0)),
        makeTodo("done-hidden", Status::Done, Priority::High,
            testTime(2026, 8, 21, 7, 50, 0))
    };
    ProjectionOptions golden_options;
    golden_options.scope = HudScope::All;
    golden_options.max_count = 20;
    golden_options.now = golden_now;
    golden_options.today_start = testTime(2026, 8, 21, 0, 0, 0);
    const auto golden = project(golden_source, golden_options);
    if (!expectIds(golden.items, {
        "doing-high-future", "doing-medium-future", "doing-low-overdue",
        "todo-high-equal", "todo-medium-earlier", "todo-medium-later",
        "todo-low-new", "todo-low-old", "todo-low-no-due", "todo-high-overdue"
    }, "projection golden ordering", checks)) return 1;
    if (!expect(golden.doing.size() == 3 && golden.todo.size() == 7,
        "projection sections exclude done after ordering", checks)) return 1;
    if (!expect(!isOverdue(golden_source[3], golden_now),
        "due equal to now is not overdue", checks)) return 1;

    golden_options.max_count = 4;
    const auto truncated = project(golden_source, golden_options);
    if (!expectIds(truncated.items, {
        "doing-high-future", "doing-medium-future", "doing-low-overdue", "todo-high-equal"
    }, "global max truncates after ordering", checks)) return 1;
    if (!expect(truncated.doing.size() == 3 && truncated.todo.size() == 1,
        "global max retains cross-section counts", checks)) return 1;
    golden_options.max_count = 3;
    const auto doing_only = project(golden_source, golden_options);
    if (!expect(doing_only.doing.size() == 3 && doing_only.todo.empty(),
        "global max can produce doing-only projection", checks)) return 1;
    golden_options.max_count = 0;
    if (!expect(project(golden_source, golden_options).items.empty(),
        "zero max produces empty projection", checks)) return 1;
    golden_options.max_count = -3;
    if (!expect(project(golden_source, golden_options).items.empty(),
        "negative max produces empty projection", checks)) return 1;
    if (!expect(project({}, golden_options).items.empty(),
        "empty source produces empty projection", checks)) return 1;

    const std::vector<Todo> today_source{
        makeTodo("before-today", Status::Todo, Priority::High,
            testTime(2026, 8, 20, 23, 59, 59)),
        makeTodo("today-doing", Status::Doing, Priority::Medium,
            testTime(2026, 8, 21, 0, 0, 0)),
        makeTodo("future-created", Status::Todo, Priority::Low,
            testTime(2026, 8, 21, 9, 0, 0)),
        makeTodo("today-done", Status::Done, Priority::High,
            testTime(2026, 8, 21, 1, 0, 0))
    };
    ProjectionOptions today_options;
    today_options.scope = HudScope::Today;
    today_options.max_count = 20;
    today_options.now = golden_now;
    today_options.today_start = testTime(2026, 8, 21, 0, 0, 0);
    const auto today_boundary = project(today_source, today_options);
    if (!expectIds(today_boundary.items, {"today-doing", "future-created"},
        "today scope uses injected lower bound", checks)) return 1;
    if (!expect(today_boundary.doing.size() == 1 && today_boundary.todo.size() == 1,
        "today scope preserves future created item and hides done", checks)) return 1;

    std::int64_t collection_clock = 1000;
    AdvanceService collection_advance([&] { return collection_clock; });
    const auto todo_completed_at = testTime(2026, 8, 21, 8, 1, 0);
    const auto doing_completed_at = testTime(2026, 8, 21, 8, 2, 0);
    std::vector<Todo> collection{
        makeTodo("collection-todo", Status::Todo, Priority::Medium, now),
        makeTodo("collection-doing", Status::Todo, Priority::High, now),
        makeTodo("collection-done", Status::Done, Priority::High, now),
        makeTodo("collection-invalid", static_cast<Status>(99), Priority::Low, now)
    };
    int write_attempts = 0;
    const auto dispatch = [&](std::string_view id, TimePoint completed_at) {
        const auto result = collection_advance.advanceById(collection, id, completed_at);
        if (result.has_value()) ++write_attempts;
        return result;
    };
    const auto todo_result = dispatch("collection-todo", todo_completed_at);
    if (!expect(todo_result.has_value() && todo_result->index == 0 &&
        todo_result->status == Status::Doing && collection[0].status == Status::Doing &&
        !collection[0].completed_at.has_value() && write_attempts == 1,
        "collection advance returns updated Todo index and clears completedAt", checks)) return 1;
    const auto after_todo = collection;
    if (!expect(!dispatch("collection-todo", doing_completed_at).has_value() &&
        write_attempts == 1 && sameTodos(collection, after_todo),
        "immediate repeated collection advance has no write intent", checks)) return 1;
    collection_clock = 1499;
    const auto before_499 = collection;
    if (!expect(!dispatch("collection-todo", doing_completed_at).has_value() &&
        write_attempts == 1 && sameTodos(collection, before_499),
        "499ms collection cooldown rejects without mutation", checks)) return 1;
    collection_clock = 1500;
    const auto done_result = dispatch("collection-todo", doing_completed_at);
    if (!expect(done_result.has_value() && done_result->index == 0 &&
        done_result->status == Status::Done && collection[0].status == Status::Done &&
        collection[0].completed_at == std::optional<TimePoint>{doing_completed_at} &&
        write_attempts == 2,
        "500ms collection cooldown allows Done with exact completion time", checks)) return 1;

    const auto before_other = collection;
    const auto other_result = dispatch("collection-doing", todo_completed_at);
    if (!expect(other_result.has_value() && other_result->index == 1 &&
        other_result->status == Status::Doing && !collection[1].completed_at.has_value() &&
        write_attempts == 3,
        "different UUID is not blocked by another task cooldown", checks)) return 1;
    if (!expect(before_other[1].status == Status::Todo && collection[1].status == Status::Doing,
        "different UUID updates only its matched item", checks)) return 1;
    const auto before_other_repeat = collection;
    if (!expect(!dispatch("collection-doing", doing_completed_at).has_value() &&
        write_attempts == 3 && sameTodos(collection, before_other_repeat),
        "repeated second UUID advance has no write intent", checks)) return 1;
    collection_advance.rollback("collection-doing");
    const auto rollback_result = dispatch("collection-doing", doing_completed_at);
    if (!expect(rollback_result.has_value() && rollback_result->index == 1 &&
        rollback_result->status == Status::Done && write_attempts == 4,
        "rollback clears UUID cooldown", checks)) return 1;

    const auto before_missing = collection;
    if (!expect(!dispatch("missing-uuid", doing_completed_at).has_value() &&
        write_attempts == 4 && sameTodos(collection, before_missing),
        "missing UUID has no write intent or mutation", checks)) return 1;
    const auto before_done = collection;
    if (!expect(!dispatch("collection-done", doing_completed_at).has_value() &&
        write_attempts == 4 && sameTodos(collection, before_done),
        "Done task has no write intent or mutation", checks)) return 1;
    const auto before_invalid = collection;
    if (!expect(!dispatch("collection-invalid", doing_completed_at).has_value() &&
        write_attempts == 4 && sameTodos(collection, before_invalid),
        "invalid status has no write intent or mutation", checks)) return 1;
    collection[3].status = Status::Todo;
    const auto invalid_followup = dispatch("collection-invalid", doing_completed_at);
    if (!expect(invalid_followup.has_value() && invalid_followup->index == 3 &&
        invalid_followup->status == Status::Doing && write_attempts == 5,
        "invalid status does not create a cooldown", checks)) return 1;
    if (!expect(collection.size() == 4, "collection advance preserves collection size", checks)) return 1;

    std::int64_t monotonic = 1000;
    AdvanceService advance([&] { return monotonic; });
    auto advancing = makeTodo("advance", Status::Todo, Priority::Medium,
        testTime(2026, 8, 21, 7, 0, 0));
    if (!expect(advance.advance(advancing, now), "Todo advances to Doing", checks)) return 1;
    if (!expect(advancing.status == Status::Doing && !advancing.completed_at.has_value(),
        "Doing clears completedAt", checks)) return 1;
    if (!expect(!advance.advance(advancing, now), "500ms cooldown rejects duplicate", checks)) return 1;
    monotonic += 500;
    if (!expect(advance.advance(advancing, now), "Doing advances after cooldown", checks)) return 1;
    if (!expect(advancing.status == Status::Done && advancing.completed_at.has_value(),
        "Done records completedAt", checks)) return 1;
    if (!expect(!advance.advance(advancing, now), "Done cannot advance", checks)) return 1;

    HudSettings settings;
    settings.opacity = std::numeric_limits<double>::quiet_NaN();
    settings.max_items = -4;
    settings.hotkey_enabled = true;
    settings.hotkey_modifiers = 0;
    settings.hotkey_key = 'A';
    settings.placement.logical_width = 20;
    settings.placement.logical_height = 5000;
    settings.placement.dpi = 1;
    settings = normalize(settings);
    if (!expect(settings.opacity == 1.0 && settings.max_items == 8,
        "settings scalar normalization", checks)) return 1;
    if (!expect(!settings.hotkey_enabled && settings.placement.logical_width == 360 &&
        settings.placement.logical_height == 460 && settings.placement.dpi == 96 &&
        settings.hotkey_modifiers == 0 && settings.hotkey_key == 0,
        "settings invalid values fallback", checks)) return 1;
    HudSettings scalar_boundaries;
    scalar_boundaries.opacity = 0.5;
    scalar_boundaries.max_items = 1;
    if (!expect(normalize(scalar_boundaries).opacity == 0.5 &&
        normalize(scalar_boundaries).max_items == 1,
        "settings lower scalar boundaries are preserved", checks)) return 1;
    scalar_boundaries.opacity = 1.0;
    scalar_boundaries.max_items = 20;
    if (!expect(normalize(scalar_boundaries).opacity == 1.0 &&
        normalize(scalar_boundaries).max_items == 20,
        "settings upper scalar boundaries are preserved", checks)) return 1;
    scalar_boundaries.opacity = 0.499;
    scalar_boundaries.max_items = 21;
    if (!expect(normalize(scalar_boundaries).opacity == 1.0 &&
        normalize(scalar_boundaries).max_items == 8,
        "settings out of range scalars fall back independently", checks)) return 1;
    scalar_boundaries.opacity = std::numeric_limits<double>::infinity();
    scalar_boundaries.max_items = std::numeric_limits<int>::min();
    if (!expect(normalize(scalar_boundaries).opacity == 1.0 &&
        normalize(scalar_boundaries).max_items == 8,
        "settings non-finite and extreme scalars fall back", checks)) return 1;
    HudSettings default_settings;
    if (!expect(default_settings.mode == HudMode::Passthrough,
        "HUD defaults to passthrough mode", checks)) return 1;
    default_settings.mode = HudMode::Interactive;
    if (!expect(normalize(default_settings).mode == HudMode::Interactive,
        "HUD interactive mode is preserved", checks)) return 1;
    HudSettings invalid_enum_settings;
    invalid_enum_settings.mode = static_cast<HudMode>(99);
    invalid_enum_settings.scope = static_cast<HudScope>(99);
    const auto normalized_enum_settings = normalize(invalid_enum_settings);
    if (!expect(normalized_enum_settings.mode == HudMode::Passthrough &&
        normalized_enum_settings.scope == HudScope::All,
        "invalid settings enums fall back to defaults", checks)) return 1;
    if (!expect(kHotkeyAlt == 0x0001u && kHotkeyControl == 0x0002u &&
        kHotkeyShift == 0x0004u && kHotkeyWin == 0x0008u &&
        kHotkeyNoRepeat == 0x4000u,
        "Win32 hotkey modifier constants", checks)) return 1;
    if (!expect(validHotkey(kHotkeyControl | kHotkeyNoRepeat, 'G') &&
        validHotkey(kHotkeyControl, 1) && validHotkey(kHotkeyControl, 0xFF) &&
        !validHotkey(kHotkeyControl, 0) && validHotkey(0, 0x70) &&
        !validHotkey(0, 'G') &&
        !validHotkey(kHotkeyControl, 0x10) && !validHotkey(kHotkeyControl, 0x11) &&
        !validHotkey(kHotkeyControl, 0x12) && !validHotkey(kHotkeyControl, 0x5B) &&
        !validHotkey(kHotkeyControl, 0x5C) && !validHotkey(kHotkeyControl, 0xA0) &&
        !validHotkey(kHotkeyControl, 0xA1) && !validHotkey(kHotkeyControl, 0xA2) &&
        !validHotkey(kHotkeyControl, 0xA3) && !validHotkey(kHotkeyControl, 0xA4) &&
        !validHotkey(kHotkeyControl, 0xA5) &&
        !validHotkey(0x8000u, 'G'),
        "hotkey candidate rules", checks)) return 1;
    const auto normalized_hotkey = normalizeHotkey(
        kHotkeyControl | kHotkeyNoRepeat | 0x8000u, 'G');
    if (!expect(normalized_hotkey.has_value() &&
        normalized_hotkey->modifiers == kHotkeyControl && normalized_hotkey->key == 'G',
        "hotkey normalization strips registration-only and unknown bits", checks)) return 1;
    const auto normalized_function = normalizeHotkey(kHotkeyNoRepeat, 0x77);
    if (!expect(normalized_function.has_value() && normalized_function->modifiers == 0 &&
        normalized_function->key == 0x77,
        "function hotkey stores no NoRepeat candidate bit", checks)) return 1;
    if (!expect(!normalizeHotkey(kHotkeyNoRepeat, 'G').has_value(),
        "NoRepeat alone does not qualify an ordinary key", checks)) return 1;
    HudSettings stored_hotkey;
    stored_hotkey.hotkey_enabled = true;
    stored_hotkey.hotkey_modifiers = kHotkeyAlt | kHotkeyNoRepeat | 0x8000u;
    stored_hotkey.hotkey_key = 'G';
    stored_hotkey = normalize(stored_hotkey);
    if (!expect(stored_hotkey.hotkey_enabled && stored_hotkey.hotkey_modifiers == kHotkeyAlt &&
        stored_hotkey.hotkey_key == 'G',
        "settings persist only normalized hotkey candidate", checks)) return 1;

    Placement boundary;
    boundary.relative_x = -24;
    boundary.relative_y = -12;
    boundary.logical_width = 300;
    boundary.logical_height = 280;
    boundary.dpi = 48;
    const auto normalized_boundary = normalize(boundary);
    if (!expect(normalized_boundary.relative_x == -24 && normalized_boundary.relative_y == -12 &&
        normalized_boundary.logical_width == 300 && normalized_boundary.logical_height == 280 &&
        normalized_boundary.dpi == 48,
        "valid placement boundaries and negative coordinates preserved", checks)) return 1;
    Placement upper_boundary;
    upper_boundary.logical_width = 1920;
    upper_boundary.logical_height = 1600;
    upper_boundary.dpi = 768;
    const auto normalized_upper = normalize(upper_boundary);
    if (!expect(normalized_upper.logical_width == 1920 && normalized_upper.logical_height == 1600 &&
        normalized_upper.dpi == 768,
        "valid upper placement boundaries are preserved", checks)) return 1;
    Placement non_finite;
    non_finite.relative_x = std::numeric_limits<double>::infinity();
    non_finite.relative_y = -std::numeric_limits<double>::infinity();
    non_finite.logical_width = std::numeric_limits<double>::quiet_NaN();
    non_finite.logical_height = std::numeric_limits<double>::infinity();
    non_finite.dpi = 769;
    const auto normalized_non_finite = normalize(non_finite);
    if (!expect(normalized_non_finite.relative_x == 0 && normalized_non_finite.relative_y == 0 &&
        normalized_non_finite.logical_width == 360 && normalized_non_finite.logical_height == 460 &&
        normalized_non_finite.dpi == 96,
        "non-finite placement fields fallback independently", checks)) return 1;

    const std::vector<MonitorWorkArea> monitors{
        MonitorWorkArea{"primary", 0, 0, 1920, 1080, 96, true},
        MonitorWorkArea{"secondary", -1280, 0, 0, 1024, 144, false}
    };
    const auto empty_monitor_rect = restorePlacement(Placement{}, {}, "primary");
    if (!expect(empty_monitor_rect.left == 0 && empty_monitor_rect.top == 0 &&
        empty_monitor_rect.right == 300 && empty_monitor_rect.bottom == 280,
        "empty monitor list uses macOS fallback rectangle", checks)) return 1;
    Placement secondary;
    secondary.monitor_id = "secondary";
    secondary.relative_x = 100;
    secondary.relative_y = 50;
    secondary.logical_width = 360;
    secondary.logical_height = 460;
    secondary.dpi = 96;
    const auto secondary_rect = restorePlacement(secondary, monitors, "primary");
    if (!expect(secondary_rect.left == -1130 && secondary_rect.top == 75 &&
        secondary_rect.right - secondary_rect.left == 540,
        "DPI placement conversion with negative coordinates", checks)) return 1;
    secondary.dpi = 144;
    const auto same_dpi_saved = restorePlacement(secondary, monitors, "primary");
    if (!expect(same_dpi_saved.left == -1130 && same_dpi_saved.right - same_dpi_saved.left == 540,
        "saved DPI does not change target physical conversion", checks)) return 1;
    secondary.monitor_id = "SeCoNdArY";
    const auto case_insensitive_monitor = restorePlacement(secondary, monitors, "primary");
    if (!expect(case_insensitive_monitor.left == -1130 && case_insensitive_monitor.top == 75 &&
        case_insensitive_monitor.right - case_insensitive_monitor.left == 540,
        "monitor IDs match case-insensitively", checks)) return 1;
    Placement primary_100;
    primary_100.monitor_id = "PRIMARY";
    primary_100.relative_x = 10;
    primary_100.relative_y = 20;
    primary_100.logical_width = 360;
    primary_100.logical_height = 460;
    const auto primary_rect = restorePlacement(primary_100, monitors, "primary");
    if (!expect(primary_rect.left == 10 && primary_rect.top == 20 &&
        primary_rect.right - primary_rect.left == 360 &&
        primary_rect.bottom - primary_rect.top == 460,
        "100 percent target DPI uses logical dimensions", checks)) return 1;
    const std::vector<MonitorWorkArea> high_dpi_monitors{
        MonitorWorkArea{"ultra", 1920, 0, 5760, 2160, 192, false}
    };
    Placement high_dpi;
    high_dpi.monitor_id = "ULTRA";
    high_dpi.relative_x = 10;
    high_dpi.relative_y = 20;
    high_dpi.logical_width = 360;
    high_dpi.logical_height = 460;
    const auto high_dpi_rect = restorePlacement(high_dpi, high_dpi_monitors, "ultra");
    if (!expect(high_dpi_rect.left == 1940 && high_dpi_rect.top == 40 &&
        high_dpi_rect.right - high_dpi_rect.left == 720 &&
        high_dpi_rect.bottom - high_dpi_rect.top == 920,
        "200 percent target DPI scales logical placement", checks)) return 1;
    const std::vector<MonitorWorkArea> tiny_monitors{
        MonitorWorkArea{"tiny", 0, 0, 200, 250, 192, true}
    };
    Placement tiny;
    tiny.monitor_id = "TINY";
    tiny.relative_x = -1000;
    tiny.relative_y = -1000;
    tiny.logical_width = 300;
    tiny.logical_height = 280;
    const auto tiny_rect = restorePlacement(tiny, tiny_monitors, "tiny");
    if (!expect(tiny_rect.left == 0 && tiny_rect.top == 0 &&
        tiny_rect.right - tiny_rect.left == 200 && tiny_rect.bottom - tiny_rect.top == 250,
        "minimum placement size is limited by small work area", checks)) return 1;
    Placement huge_positive;
    huge_positive.monitor_id = "primary";
    huge_positive.relative_x = std::numeric_limits<double>::max();
    huge_positive.relative_y = std::numeric_limits<double>::max();
    const auto huge_positive_rect = restorePlacement(huge_positive, monitors, "primary");
    if (!expect(huge_positive_rect.left == 1560 && huge_positive_rect.top == 620 &&
        huge_positive_rect.right == 1920 && huge_positive_rect.bottom == 1080,
        "huge positive coordinates clamp to work area edge", checks)) return 1;
    Placement huge_negative = huge_positive;
    huge_negative.relative_x = -std::numeric_limits<double>::max();
    huge_negative.relative_y = -std::numeric_limits<double>::max();
    const auto huge_negative_rect = restorePlacement(huge_negative, monitors, "primary");
    if (!expect(huge_negative_rect.left == 0 && huge_negative_rect.top == 0 &&
        huge_negative_rect.right == 360 && huge_negative_rect.bottom == 460,
        "huge negative coordinates clamp to work area origin", checks)) return 1;
    const std::vector<MonitorWorkArea> extreme_dpi_monitors{
        MonitorWorkArea{"extreme", 0, 0, 1920, 1080,
            std::numeric_limits<std::uint32_t>::max(), true}
    };
    Placement extreme_dpi;
    extreme_dpi.monitor_id = "extreme";
    extreme_dpi.relative_x = std::numeric_limits<double>::max();
    extreme_dpi.relative_y = std::numeric_limits<double>::max();
    const auto extreme_dpi_rect = restorePlacement(extreme_dpi, extreme_dpi_monitors, "extreme");
    if (!expect(extreme_dpi_rect.left == 0 && extreme_dpi_rect.top == 0 &&
        extreme_dpi_rect.right == 1920 && extreme_dpi_rect.bottom == 1080,
        "extreme target DPI clamps scaled size without overflow", checks)) return 1;

    Placement missing;
    missing.monitor_id = "disconnected";
    missing.relative_x = -5000;
    missing.relative_y = -5000;
    missing.logical_width = 4000;
    missing.logical_height = 4000;
    const auto recovered = restorePlacement(missing, monitors, "primary");
    if (!expect(recovered.left >= 0 && recovered.top >= 0 &&
        recovered.right <= 1920 && recovered.bottom <= 1080,
        "missing monitor recovers inside primary work area", checks)) return 1;
    const auto recovered_case_insensitive = restorePlacement(missing, monitors, "PRIMARY");
    if (!expect(recovered_case_insensitive.left >= 0 && recovered_case_insensitive.top >= 0 &&
        recovered_case_insensitive.right <= 1920 && recovered_case_insensitive.bottom <= 1080,
        "primary monitor fallback matches ID case-insensitively", checks)) return 1;

    const auto saved = savePlacement(secondary_rect, monitors[1]);
    if (!expect(saved.monitor_id == "secondary" && saved.dpi == 144 &&
        saved.logical_width > 300 && saved.logical_height > 300,
        "placement save preserves monitor and logical size", checks)) return 1;
    if (!expect(nativePrototypeVersion() == 2, "core version", checks)) return 1;

    std::cout << "PASS GhostPin.Native.CoreChecks (" << checks << " checks)\n";
    return 0;
}
