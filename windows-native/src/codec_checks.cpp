#include "codec.hpp"

#include <algorithm>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <initializer_list>
#include <iostream>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

using namespace ghostpin::core;

namespace {

constexpr std::string_view kUuid = "00000000-0000-0000-0000-000000000001";

bool expect(bool condition, const char* message, int& checks) {
    ++checks;
    if (!condition) std::cerr << "FAIL " << message << "\n";
    return condition;
}

std::string readFixture(const std::filesystem::path& fixture_directory, const char* name) {
    const auto path = fixture_directory / name;
    std::ifstream stream(path, std::ios::binary);
    if (!stream) throw std::runtime_error("fixture cannot be opened: " + path.string());
    std::ostringstream contents;
    contents << stream.rdbuf();
    return contents.str();
}

std::string singleJson(
    std::string_view id,
    std::string_view title_json,
    std::string_view created_at,
    std::string_view tail = {}) {
    std::string value = "[{\"id\":\"";
    value += id;
    value += "\",\"title\":";
    value += title_json;
    value += ",\"createdAt\":\"";
    value += created_at;
    value += '"';
    value += tail;
    value += "}]";
    return value;
}

template <typename Function>
bool expectInvalid(Function&& function, const char* message, int& checks) {
    ++checks;
    try {
        function();
    } catch (const std::invalid_argument&) {
        return true;
    } catch (const std::out_of_range&) {
        return true;
    } catch (const std::exception& error) {
        std::cerr << "FAIL " << message << " raised wrong exception: " << error.what() << "\n";
        return false;
    }
    std::cerr << "FAIL " << message << " was accepted\n";
    return false;
}

bool sameTodo(const Todo& left, const Todo& right) {
    return left.id == right.id && left.title == right.title &&
        left.created_at == right.created_at && left.status == right.status &&
        left.completed_at == right.completed_at && left.reminder_at == right.reminder_at &&
        left.reminder_sent_at == right.reminder_sent_at && left.priority == right.priority &&
        left.due_at == right.due_at && left.description == right.description;
}

bool contains(std::string_view value, std::string_view part) {
    return value.find(part) != std::string_view::npos;
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
        hours{hour} + minutes{minute} + seconds{second};
    return TimePoint{duration_cast<TimePoint::duration>(value.time_since_epoch())};
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

} // namespace

int main(int argc, char** argv) {
    if (argc < 1) return 1;
    int checks = 0;
    try {
        ghostpin::codec::RuntimeApartment apartment;
        const auto executable = std::filesystem::absolute(argv[0]);
        const auto fixture_directory = argc > 1
            ? std::filesystem::path(argv[1])
            : executable.parent_path() / "tests";

        const auto cross = ghostpin::codec::decodeTodos(
            readFixture(fixture_directory, "tasks-cross-language.json"));
        if (!expect(cross.size() == 2, "cross-language fixture count", checks)) return 1;
        if (!expect(cross[0].id == kUuid && cross[0].title == "处理高优先级任务" &&
            cross[0].status == Status::Doing && cross[0].priority == Priority::High &&
            !cross[0].completed_at.has_value() && !cross[0].reminder_at.has_value() &&
            cross[0].description.has_value(),
            "cross-language UTF-8 and lowercase fields", checks)) return 1;
        if (!expect(cross[1].status == Status::Todo && cross[1].priority == Priority::Low &&
            cross[1].due_at.has_value(), "cross-language nullable and due fields", checks)) return 1;

        const auto cross_encoded = ghostpin::codec::encodeTodos(cross);
        const auto cross_roundtrip = ghostpin::codec::decodeTodos(cross_encoded);
        if (!expect(cross_roundtrip.size() == cross.size() &&
            sameTodo(cross_roundtrip[0], cross[0]) && sameTodo(cross_roundtrip[1], cross[1]),
            "cross-language encode/decode roundtrip", checks)) return 1;
        if (!expect(contains(cross_encoded, "2026-08-19T01:00:00Z") &&
            contains(cross_encoded, "2026-08-19T10:00:00Z") &&
            !contains(cross_encoded, "futureField") && !contains(cross_encoded, "isCompleted"),
            "offset UTC seconds and computed/unknown fields", checks)) return 1;

        const auto legacy = ghostpin::codec::decodeTodos(
            readFixture(fixture_directory, "tasks-legacy-missing-status.json"));
        if (!expect(legacy.size() == 2 && legacy[0].status == Status::Todo &&
            legacy[0].priority == Priority::Medium && legacy[1].status == Status::Done &&
            legacy[1].priority == Priority::High && legacy[1].completed_at.has_value(),
            "legacy missing status mapping and medium default", checks)) return 1;

        std::vector<Todo> fixture_source = cross;
        fixture_source.push_back(legacy[1]);
        ProjectionOptions fixture_options;
        fixture_options.scope = HudScope::All;
        fixture_options.max_count = 8;
        fixture_options.now = testTime(2026, 8, 19, 4, 0, 0);
        fixture_options.today_start = testTime(2026, 8, 18, 16, 0, 0);
        const auto fixture_all = project(fixture_source, fixture_options);
        if (!expectIds(fixture_all.items, {cross[0].id, cross[1].id},
            "cross-language fixture All projection ordering", checks)) return 1;
        if (!expect(fixture_all.doing.size() == 1 && fixture_all.todo.size() == 1 &&
            fixture_all.items.front().status == Status::Doing &&
            isOverdue(fixture_all.items.back(), fixture_options.now) &&
            fixture_all.items.back().status == Status::Todo,
            "cross-language fixture Doing first and overdue Todo last", checks)) return 1;
        fixture_options.scope = HudScope::Today;
        const auto fixture_today = project(fixture_source, fixture_options);
        if (!expectIds(fixture_today.items, {cross[0].id},
            "cross-language fixture Today projection", checks)) return 1;
        if (!expect(std::none_of(fixture_all.items.begin(), fixture_all.items.end(),
            [&](const Todo& item) { return item.id == legacy[1].id; }),
            "cross-language fixture hides Done", checks)) return 1;

        const auto missing_nullable = ghostpin::codec::decodeTodos(singleJson(
            kUuid, "\"nullable\"", "2026-08-19T09:00:00Z"))[0];
        if (!expect(!missing_nullable.completed_at.has_value() &&
            !missing_nullable.reminder_at.has_value() &&
            !missing_nullable.reminder_sent_at.has_value() && !missing_nullable.due_at.has_value() &&
            !missing_nullable.description.has_value(),
            "missing nullable fields", checks)) return 1;
        const auto null_nullable = ghostpin::codec::decodeTodos(singleJson(
            kUuid, "\"nullable\"", "2026-08-19T09:00:00Z",
            ",\"completedAt\":null,\"reminderAt\":null,\"reminderSentAt\":null,\"dueAt\":null,\"description\":null,\"priority\":null,\"status\":null"))[0];
        if (!expect(!null_nullable.completed_at.has_value() &&
            !null_nullable.reminder_at.has_value() && !null_nullable.reminder_sent_at.has_value() &&
            !null_nullable.due_at.has_value() && !null_nullable.description.has_value() &&
            null_nullable.status == Status::Todo && null_nullable.priority == Priority::Medium,
            "null nullable fields and enum defaults", checks)) return 1;
        const auto status_null_done = ghostpin::codec::decodeTodos(singleJson(
            kUuid, "\"legacy done\"", "2026-08-19T09:00:00Z",
            ",\"completedAt\":\"2026-08-19T10:00:00Z\",\"status\":null,\"priority\":null"))[0];
        if (!expect(status_null_done.status == Status::Done &&
            status_null_done.priority == Priority::Medium,
            "null status maps completedAt to done", checks)) return 1;

        const auto valid_nullable = ghostpin::codec::decodeTodos(singleJson(
            kUuid, "\"valid\"", "2026-08-19T09:00:00+08:00",
            ",\"completedAt\":\"2026-08-19T10:00:00+08:00\",\"reminderAt\":\"2026-08-19T11:00:00+08:00\",\"reminderSentAt\":\"2026-08-19T12:00:00+08:00\",\"dueAt\":\"2026-08-19T13:00:00+08:00\",\"description\":\"说明\""))[0];
        if (!expect(valid_nullable.completed_at.has_value() && valid_nullable.reminder_at.has_value() &&
            valid_nullable.reminder_sent_at.has_value() && valid_nullable.due_at.has_value() &&
            valid_nullable.description == std::optional<std::string>{"说明"},
            "valid nullable fields", checks)) return 1;
        const auto nullable_encoded = ghostpin::codec::encodeTodos({missing_nullable});
        if (!expect(contains(nullable_encoded, "\"completedAt\":null") &&
            contains(nullable_encoded, "\"reminderAt\":null") &&
            contains(nullable_encoded, "\"reminderSentAt\":null") &&
            contains(nullable_encoded, "\"dueAt\":null") &&
            contains(nullable_encoded, "\"description\":null"),
            "encode writes all nullable fields as null", checks)) return 1;

        const auto plus08 = ghostpin::codec::encodeTodos(ghostpin::codec::decodeTodos(singleJson(
            kUuid, "\"offset\"", "2026-08-19T09:00:00+08:00")));
        const auto minus05 = ghostpin::codec::encodeTodos(ghostpin::codec::decodeTodos(singleJson(
            kUuid, "\"offset\"", "2026-08-19T09:00:00-05:00")));
        const auto plus09 = ghostpin::codec::encodeTodos(ghostpin::codec::decodeTodos(singleJson(
            kUuid, "\"offset\"", "2026-08-19T09:00:00+09:00")));
        const auto plus14 = ghostpin::codec::encodeTodos(ghostpin::codec::decodeTodos(singleJson(
            kUuid, "\"offset\"", "2026-08-19T09:00:00+14:00")));
        const auto millis = ghostpin::codec::encodeTodos(ghostpin::codec::decodeTodos(singleJson(
            kUuid, "\"offset\"", "2026-08-19T09:00:00.987+08:00")));
        if (!expect(contains(plus08, "2026-08-19T01:00:00Z") &&
            contains(minus05, "2026-08-19T14:00:00Z") &&
            contains(plus09, "2026-08-19T00:00:00Z") &&
            contains(plus14, "2026-08-18T19:00:00Z") &&
            contains(millis, "2026-08-19T01:00:00Z"),
            "fixed offset UTC and millisecond truncation", checks)) return 1;
        const auto year_one = ghostpin::codec::encodeTodos(ghostpin::codec::decodeTodos(singleJson(
            kUuid, "\"year one\"", "0001-01-01T00:00:00Z")));
        const auto year_max = ghostpin::codec::encodeTodos(ghostpin::codec::decodeTodos(singleJson(
            kUuid, "\"year max\"", "9999-12-31T23:59:59Z")));
        const auto negative_epoch = ghostpin::codec::encodeTodos(ghostpin::codec::decodeTodos(singleJson(
            kUuid, "\"negative epoch\"", "1969-12-31T23:59:59.987Z")));
        if (!expect(contains(year_one, "0001-01-01T00:00:00Z") &&
            contains(year_max, "9999-12-31T23:59:59Z") &&
            contains(negative_epoch, "1969-12-31T23:59:59Z"),
            "four-digit boundary years and negative epoch floor", checks)) return 1;

        const auto escaped = ghostpin::codec::decodeTodos(singleJson(
            kUuid, R"JSON("中文 \"引号\" \\ 路径\n下一行")JSON",
            "2026-08-19T09:00:00Z",
            ",\"description\":\"转义 \\\"内容\\\"\""))[0];
        const auto escaped_roundtrip = ghostpin::codec::decodeTodos(
            ghostpin::codec::encodeTodos({escaped}))[0];
        if (!expect(escaped_roundtrip.title == escaped.title &&
            escaped_roundtrip.description == escaped.description,
            "Unicode and escaped strings", checks)) return 1;

        const auto uppercase = ghostpin::codec::decodeTodos(singleJson(
            "00000000-0000-0000-0000-00000000000A", "\"uuid\"", "2026-08-19T09:00:00Z"))[0];
        if (!expect(uppercase.id == "00000000-0000-0000-0000-00000000000a" &&
            contains(ghostpin::codec::encodeTodos({uppercase}),
                "00000000-0000-0000-0000-00000000000a"),
            "UUID validation and lowercase normalization", checks)) return 1;

        const auto nested_unknown = ghostpin::codec::decodeTodos(singleJson(
            kUuid, "\"unknown\"", "2026-08-19T09:00:00Z",
            ",\"unknown\":{\"nested\":{\"values\":[1,true]}}"));
        if (!expect(nested_unknown.size() == 1, "unknown nested field ignored", checks)) return 1;
        if (!expect(ghostpin::codec::decodeTodos("[]").empty(), "empty array", checks)) return 1;

        const std::vector<std::string> invalid_json{
            "{}",
            "[1]",
            "[",
            singleJson("bad", "\"title\"", "2026-08-19T09:00:00Z"),
            singleJson(kUuid, "\"title\"", "2026-02-30T09:00:00Z"),
            singleJson(kUuid, "\"title\"", "2026-08-19T09:00:00+14:01"),
            singleJson(kUuid, "\"title\"", "2026-08-19T09:00:00+15:00"),
            singleJson(kUuid, "\"title\"", "2026-08-19T09:00:00Z", ",\"status\":\"blocked\""),
            singleJson(kUuid, "\"title\"", "2026-08-19T09:00:00Z", ",\"priority\":\"urgent\""),
            singleJson(kUuid, "\"title\"", "2026-08-19T09:00:00Z", ",\"status\":3"),
            singleJson(kUuid, "\"title\"", "2026-08-19T09:00:00Z", ",\"priority\":{}"),
            singleJson(kUuid, "\"title\"", "2026-08-19T09:00:00Z", ",\"reminderAt\":3"),
            singleJson(kUuid, "\"title\"", "2026-08-19T09:00:00Z", ",\"reminderSentAt\":3"),
            singleJson(kUuid, "\"title\"", "2026-08-19T09:00:00Z", ",\"dueAt\":3"),
            "[{\"id\":\"" + std::string(kUuid) + "\",\"title\":\"x\",\"createdAt\":3}]",
            "[{\"title\":\"missing id\",\"createdAt\":\"2026-08-19T09:00:00Z\"}]",
            "[{\"id\":3,\"title\":\"wrong id\",\"createdAt\":\"2026-08-19T09:00:00Z\"}]",
            "[{\"id\":\"" + std::string(kUuid) + "\",\"createdAt\":\"2026-08-19T09:00:00Z\"}]",
            "[{\"id\":\"" + std::string(kUuid) + "\",\"title\":3,\"createdAt\":\"2026-08-19T09:00:00Z\"}]",
            "[{\"id\":\"" + std::string(kUuid) + "\",\"title\":\"x\"}]",
            singleJson(kUuid, "\"title\"", "2026-08-19T09:00:00Z", ",\"completedAt\":3"),
            singleJson(kUuid, "\"title\"", "2026-08-19T09:00:00Z", ",\"description\":false")
        };
        for (const auto& invalid : invalid_json) {
            if (!expectInvalid([&] { (void)ghostpin::codec::decodeTodos(invalid); },
                "invalid JSON contract", checks)) return 1;
        }
        std::string invalid_utf8 = "[{\"id\":\"";
        invalid_utf8 += kUuid;
        invalid_utf8 += "\",\"title\":\"";
        invalid_utf8.push_back(static_cast<char>(0xFF));
        invalid_utf8 += "\",\"createdAt\":\"2026-08-19T09:00:00Z\"}]";
        if (!expectInvalid([&] { (void)ghostpin::codec::decodeTodos(invalid_utf8); },
            "invalid UTF-8", checks)) return 1;

        Todo invalid = cross[0];
        invalid.id = "bad";
        if (!expectInvalid([&] { (void)ghostpin::codec::encodeTodos({invalid}); },
            "encode invalid UUID", checks)) return 1;
        invalid = cross[0];
        invalid.status = static_cast<Status>(99);
        if (!expectInvalid([&] { (void)ghostpin::codec::encodeTodos({invalid}); },
            "encode invalid status", checks)) return 1;
        invalid = cross[0];
        invalid.priority = static_cast<Priority>(99);
        if (!expectInvalid([&] { (void)ghostpin::codec::encodeTodos({invalid}); },
            "encode invalid priority", checks)) return 1;
        invalid = cross[0];
        invalid.created_at = TimePoint::max();
        if (!expectInvalid([&] { (void)ghostpin::codec::encodeTodos({invalid}); },
            "encode out-of-range date", checks)) return 1;
        if (!expect(ghostpin::codec::encodeTodos({}).find("[]") != std::string::npos,
            "encode empty array", checks)) return 1;

        HudSettings settings;
        settings.visible = false;
        settings.launch_at_login = true;
        settings.mode = HudMode::Interactive;
        settings.topmost = false;
        settings.opacity = 0.75;
        settings.scope = HudScope::Today;
        settings.max_items = 12;
        settings.hotkey_enabled = true;
        settings.hotkey_modifiers = 0x0002;
        settings.hotkey_key = 'G';
        settings.placement.monitor_id = "DISPLAY2";
        settings.placement.relative_x = -120;
        settings.placement.relative_y = 24;
        const auto settings_json = ghostpin::codec::encodeSettings(settings);
        const auto settings_roundtrip = ghostpin::codec::decodeSettings(settings_json);
        if (!expect(!settings_roundtrip.visible && settings_roundtrip.launch_at_login &&
            settings_roundtrip.mode == HudMode::Interactive && !settings_roundtrip.topmost &&
            settings_roundtrip.opacity == 0.75 && settings_roundtrip.scope == HudScope::Today &&
            settings_roundtrip.max_items == 12 && settings_roundtrip.hotkey_enabled &&
            settings_roundtrip.hotkey_modifiers == 0x0002 && settings_roundtrip.hotkey_key == 'G' &&
            settings_roundtrip.placement.monitor_id == "DISPLAY2" &&
            settings_roundtrip.placement.relative_x == -120,
            "settings JSON roundtrip and normalization", checks)) return 1;
        const auto settings_partial = ghostpin::codec::decodeSettings(
            R"JSON({"opacity":"bad","maxItems":99,"unknown":true})JSON");
        if (!expect(settings_partial.opacity == 1.0 && settings_partial.max_items == 8,
            "settings invalid fields and unknown fields fallback", checks)) return 1;
        if (!expectInvalid([&] { (void)ghostpin::codec::decodeSettings("["); },
            "invalid settings JSON", checks)) return 1;
    } catch (const std::exception& error) {
        std::cerr << "FAIL unexpected codec check exception: " << error.what() << "\n";
        return 1;
    }

    std::cout << "PASS GhostPin.Native.JsonChecks (" << checks << " checks)\n";
    return 0;
}
