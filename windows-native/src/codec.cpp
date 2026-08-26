#include "codec.hpp"

#include <windows.h>
#include <roapi.h>
#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Data.Json.h>

#include <chrono>
#include <cmath>
#include <cstdint>
#include <limits>
#include <stdexcept>
#include <string>
#include <string_view>
#include <system_error>
#include <utility>

namespace ghostpin::codec {
namespace {

using winrt::Windows::Data::Json::JsonArray;
using winrt::Windows::Data::Json::JsonObject;
using winrt::Windows::Data::Json::JsonValue;
using winrt::Windows::Data::Json::JsonValueType;

int parseNumber(std::string_view value, std::size_t offset, std::size_t length) {
    if (offset + length > value.size()) {
        throw std::invalid_argument("ISO 8601 date is too short");
    }
    int result = 0;
    for (std::size_t index = offset; index < offset + length; ++index) {
        if (value[index] < '0' || value[index] > '9') {
            throw std::invalid_argument("ISO 8601 date contains a non-digit");
        }
        result = result * 10 + value[index] - '0';
    }
    return result;
}

bool isLeapYear(int year) noexcept {
    return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
}

unsigned daysInMonth(int year, unsigned month) noexcept {
    constexpr unsigned days[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    return month == 2 && isLeapYear(year) ? 29 : days[month - 1];
}

std::int64_t daysFromCivil(int year, unsigned month, unsigned day) noexcept {
    year -= month <= 2;
    const int era = (year >= 0 ? year : year - 399) / 400;
    const unsigned year_of_era = static_cast<unsigned>(year - era * 400);
    const unsigned day_of_year =
        (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1;
    const unsigned day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 +
        day_of_year;
    return static_cast<std::int64_t>(era) * 146097 + day_of_era - 719468;
}

void civilFromDays(std::int64_t days, int& year, unsigned& month, unsigned& day) noexcept {
    days += 719468;
    const std::int64_t era = (days >= 0 ? days : days - 146096) / 146097;
    const unsigned day_of_era = static_cast<unsigned>(days - era * 146097);
    const unsigned year_of_era = (day_of_era - day_of_era / 1460 + day_of_era / 36524 -
        day_of_era / 146096) / 365;
    year = static_cast<int>(year_of_era) + static_cast<int>(era) * 400;
    const unsigned day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 -
        year_of_era / 100);
    const unsigned month_part = (5 * day_of_year + 2) / 153;
    day = day_of_year - (153 * month_part + 2) / 5 + 1;
    month = month_part + (month_part < 10 ? 3 : -9);
    year += month <= 2;
}

std::wstring utf8ToWide(std::string_view value) {
    if (value.empty()) return {};
    if (value.size() > static_cast<std::size_t>(std::numeric_limits<int>::max())) {
        throw std::invalid_argument("UTF-8 value is too large");
    }
    const int source_length = static_cast<int>(value.size());
    const int length = MultiByteToWideChar(
        CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), source_length, nullptr, 0);
    if (length <= 0) throw std::invalid_argument("invalid UTF-8 value");
    std::wstring result(static_cast<std::size_t>(length), L'\0');
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), source_length,
        result.data(), length) != length) {
        throw std::invalid_argument("invalid UTF-8 value");
    }
    return result;
}

std::string wideToUtf8(const winrt::hstring& value) {
    if (value.empty()) return {};
    if (value.size() > static_cast<std::uint32_t>(std::numeric_limits<int>::max())) {
        throw std::invalid_argument("UTF-16 value is too large");
    }
    const int source_length = static_cast<int>(value.size());
    const int length = WideCharToMultiByte(
        CP_UTF8, WC_ERR_INVALID_CHARS, value.c_str(), source_length,
        nullptr, 0, nullptr, nullptr);
    if (length <= 0) throw std::invalid_argument("invalid UTF-16 value");
    std::string result(static_cast<std::size_t>(length), '\0');
    if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.c_str(), source_length,
        result.data(), length, nullptr, nullptr) != length) {
        throw std::invalid_argument("invalid UTF-16 value");
    }
    return result;
}

core::TimePoint parseIso8601(std::string_view value) {
    if (value.size() < 20 || value[4] != '-' || value[7] != '-' ||
        value[10] != 'T' || value[13] != ':' || value[16] != ':') {
        throw std::invalid_argument("invalid ISO 8601 date");
    }
    const int year = parseNumber(value, 0, 4);
    const unsigned month = static_cast<unsigned>(parseNumber(value, 5, 2));
    const unsigned day = static_cast<unsigned>(parseNumber(value, 8, 2));
    const int hour = parseNumber(value, 11, 2);
    const int minute = parseNumber(value, 14, 2);
    const int second = parseNumber(value, 17, 2);
    if (year < 1 || year > 9999 || month < 1 || month > 12 ||
        day < 1 || day > daysInMonth(year, month) || hour > 23 || minute > 59 ||
        second > 59) {
        throw std::invalid_argument("invalid ISO 8601 value");
    }

    std::size_t cursor = 19;
    int milliseconds = 0;
    if (cursor < value.size() && value[cursor] == '.') {
        ++cursor;
        const std::size_t begin = cursor;
        while (cursor < value.size() && value[cursor] >= '0' && value[cursor] <= '9') ++cursor;
        if (cursor == begin) throw std::invalid_argument("invalid ISO 8601 fraction");
        milliseconds = (value[begin] - '0') * 100;
        if (cursor - begin > 1) milliseconds += (value[begin + 1] - '0') * 10;
        if (cursor - begin > 2) milliseconds += value[begin + 2] - '0';
    }

    int offset_minutes = 0;
    if (cursor < value.size() && value[cursor] == 'Z') {
        ++cursor;
    } else if (cursor < value.size() && (value[cursor] == '+' || value[cursor] == '-')) {
        const int sign = value[cursor++] == '+' ? 1 : -1;
        const int offset_hours = parseNumber(value, cursor, 2);
        cursor += 2;
        if (cursor >= value.size() || value[cursor] != ':') {
            throw std::invalid_argument("invalid ISO 8601 offset");
        }
        ++cursor;
        const int offset_part = parseNumber(value, cursor, 2);
        cursor += 2;
        if (offset_hours > 14 || offset_part > 59 ||
            (offset_hours == 14 && offset_part != 0)) {
            throw std::invalid_argument("invalid ISO 8601 offset");
        }
        offset_minutes = sign * (offset_hours * 60 + offset_part);
    } else {
        throw std::invalid_argument("ISO 8601 date has no timezone");
    }
    if (cursor != value.size()) throw std::invalid_argument("invalid ISO 8601 suffix");

    const std::int64_t seconds = daysFromCivil(year, month, day) * 86400 +
        hour * 3600 + minute * 60 + second - offset_minutes * 60;
    const auto timestamp = std::chrono::seconds{seconds} + std::chrono::milliseconds{milliseconds};
    return core::TimePoint{
        std::chrono::duration_cast<core::TimePoint::duration>(timestamp)};
}

void appendTwoDigits(std::string& value, unsigned number) {
    value.push_back(static_cast<char>('0' + number / 10));
    value.push_back(static_cast<char>('0' + number % 10));
}

std::string formatIso8601(core::TimePoint value) {
    const auto duration = value.time_since_epoch();
    auto whole_seconds = std::chrono::duration_cast<std::chrono::seconds>(duration);
    if (duration < whole_seconds) --whole_seconds;
    const std::int64_t total_seconds = whole_seconds.count();
    std::int64_t days = total_seconds / 86400;
    std::int64_t day_seconds = total_seconds % 86400;
    if (day_seconds < 0) {
        --days;
        day_seconds += 86400;
    }
    const auto minimum_seconds = daysFromCivil(1, 1, 1) * 86400;
    const auto maximum_seconds = daysFromCivil(9999, 12, 31) * 86400 + 86399;
    if (total_seconds < minimum_seconds || total_seconds > maximum_seconds) {
        throw std::out_of_range("ISO 8601 year is outside 0001..9999");
    }
    int year = 0;
    unsigned month = 0;
    unsigned day = 0;
    civilFromDays(days, year, month, day);
    const unsigned hour = static_cast<unsigned>(day_seconds / 3600);
    day_seconds %= 3600;
    const unsigned minute = static_cast<unsigned>(day_seconds / 60);
    const unsigned second = static_cast<unsigned>(day_seconds % 60);
    std::string result = std::to_string(year);
    if (result.size() < 4) result.insert(0, 4 - result.size(), '0');
    result.push_back('-');
    appendTwoDigits(result, month);
    result.push_back('-');
    appendTwoDigits(result, day);
    result += 'T';
    appendTwoDigits(result, hour);
    result.push_back(':');
    appendTwoDigits(result, minute);
    result.push_back(':');
    appendTwoDigits(result, second);
    result.push_back('Z');
    return result;
}

std::string normalizeUuid(std::string_view value) {
    if (value.size() != 36) throw std::invalid_argument("invalid todo UUID");
    std::string normalized(value);
    for (std::size_t index = 0; index < value.size(); ++index) {
        if (index == 8 || index == 13 || index == 18 || index == 23) {
            if (value[index] != '-') throw std::invalid_argument("invalid todo UUID");
            continue;
        }
        const char character = value[index];
        const bool digit = character >= '0' && character <= '9';
        const bool lower = character >= 'a' && character <= 'f';
        const bool upper = character >= 'A' && character <= 'F';
        if (!digit && !lower && !upper) throw std::invalid_argument("invalid todo UUID");
        if (upper) normalized[index] = static_cast<char>(character - 'A' + 'a');
    }
    return normalized;
}

std::string requiredString(const JsonObject& object, const wchar_t* name) {
    if (!object.HasKey(name)) throw std::invalid_argument("required JSON field is missing");
    const auto value = object.Lookup(name);
    if (value.ValueType() != JsonValueType::String) {
        throw std::invalid_argument("JSON field is not a string");
    }
    return wideToUtf8(value.GetString());
}

std::optional<std::string> nullableString(const JsonObject& object, const wchar_t* name) {
    if (!object.HasKey(name)) return std::nullopt;
    const auto value = object.Lookup(name);
    if (value.ValueType() == JsonValueType::Null) return std::nullopt;
    if (value.ValueType() != JsonValueType::String) {
        throw std::invalid_argument("nullable JSON field is not a string");
    }
    return wideToUtf8(value.GetString());
}

core::Status parseStatus(std::string_view value) {
    if (value == "todo") return core::Status::Todo;
    if (value == "doing") return core::Status::Doing;
    if (value == "done") return core::Status::Done;
    throw std::invalid_argument("unknown todo status");
}

core::Priority parsePriority(std::string_view value) {
    if (value == "high") return core::Priority::High;
    if (value == "medium") return core::Priority::Medium;
    if (value == "low") return core::Priority::Low;
    throw std::invalid_argument("unknown todo priority");
}

} // namespace

RuntimeApartment::RuntimeApartment() {
    const HRESULT result = ::RoInitialize(RO_INIT_SINGLETHREADED);
    if (FAILED(result)) {
        if (result == RPC_E_CHANGED_MODE) {
            throw std::runtime_error("Windows Runtime apartment mode already conflicts");
        }
        throw std::system_error(static_cast<int>(result), std::system_category(),
            "Windows Runtime initialization failed");
    }
    initialized_ = true;
}

RuntimeApartment::~RuntimeApartment() noexcept {
    if (initialized_) ::RoUninitialize();
}

std::vector<core::Todo> decodeTodos(std::string_view utf8_json) {
    try {
        const auto array = JsonArray::Parse(winrt::hstring(utf8ToWide(utf8_json)));
        std::vector<core::Todo> result;
        result.reserve(array.Size());
        for (std::uint32_t index = 0; index < array.Size(); ++index) {
            const auto object = array.GetObjectAt(index);
            core::Todo item;
            item.id = normalizeUuid(requiredString(object, L"id"));
            item.title = requiredString(object, L"title");
            item.created_at = parseIso8601(requiredString(object, L"createdAt"));
            const auto completed = nullableString(object, L"completedAt");
            item.completed_at = completed.has_value()
                ? std::optional<core::TimePoint>{parseIso8601(completed.value())}
                : std::nullopt;
            const auto reminder = nullableString(object, L"reminderAt");
            item.reminder_at = reminder.has_value()
                ? std::optional<core::TimePoint>{parseIso8601(reminder.value())}
                : std::nullopt;
            const auto reminder_sent = nullableString(object, L"reminderSentAt");
            item.reminder_sent_at = reminder_sent.has_value()
                ? std::optional<core::TimePoint>{parseIso8601(reminder_sent.value())}
                : std::nullopt;
            const auto due = nullableString(object, L"dueAt");
            item.due_at = due.has_value()
                ? std::optional<core::TimePoint>{parseIso8601(due.value())}
                : std::nullopt;
            item.description = nullableString(object, L"description");

            item.status = item.completed_at.has_value() ? core::Status::Done : core::Status::Todo;
            if (object.HasKey(L"status")) {
                const auto value = object.Lookup(L"status");
                if (value.ValueType() != JsonValueType::Null) {
                    if (value.ValueType() != JsonValueType::String) {
                        throw std::invalid_argument("status JSON field is not a string");
                    }
                    item.status = parseStatus(wideToUtf8(value.GetString()));
                }
            }
            item.priority = core::Priority::Medium;
            if (object.HasKey(L"priority")) {
                const auto value = object.Lookup(L"priority");
                if (value.ValueType() != JsonValueType::Null) {
                    if (value.ValueType() != JsonValueType::String) {
                        throw std::invalid_argument("priority JSON field is not a string");
                    }
                    item.priority = parsePriority(wideToUtf8(value.GetString()));
                }
            }
            result.push_back(std::move(item));
        }
        return result;
    } catch (const winrt::hresult_error& error) {
        throw std::invalid_argument("Windows.Data.Json: " + wideToUtf8(error.message()));
    }
}

namespace {

const wchar_t* statusName(core::Status status) {
    switch (status) {
    case core::Status::Todo: return L"todo";
    case core::Status::Doing: return L"doing";
    case core::Status::Done: return L"done";
    }
    throw std::invalid_argument("invalid todo status");
}

const wchar_t* priorityName(core::Priority priority) {
    switch (priority) {
    case core::Priority::High: return L"high";
    case core::Priority::Medium: return L"medium";
    case core::Priority::Low: return L"low";
    }
    throw std::invalid_argument("invalid todo priority");
}

void insertString(JsonObject& object, const wchar_t* name, std::string_view value) {
    object.Insert(name, JsonValue::CreateStringValue(winrt::hstring(utf8ToWide(value))));
}

void insertDate(JsonObject& object, const wchar_t* name, core::TimePoint value) {
    insertString(object, name, formatIso8601(value));
}

void insertNullableDate(
    JsonObject& object,
    const wchar_t* name,
    const std::optional<core::TimePoint>& value) {
    if (value.has_value()) {
        insertDate(object, name, value.value());
    } else {
        object.Insert(name, JsonValue::CreateNullValue());
    }
}

std::string wideToUtf8String(const wchar_t* value) {
    return wideToUtf8(winrt::hstring(value));
}

} // namespace

std::string encodeTodos(const std::vector<core::Todo>& items) {
    try {
        JsonArray array;
        for (const auto& item : items) {
            const auto id = normalizeUuid(item.id);
            JsonObject object;
            insertString(object, L"id", id);
            insertString(object, L"title", item.title);
            insertDate(object, L"createdAt", item.created_at);
            insertString(object, L"status", wideToUtf8String(statusName(item.status)));
            insertNullableDate(object, L"completedAt", item.completed_at);
            insertNullableDate(object, L"reminderAt", item.reminder_at);
            insertNullableDate(object, L"reminderSentAt", item.reminder_sent_at);
            insertString(object, L"priority", wideToUtf8String(priorityName(item.priority)));
            insertNullableDate(object, L"dueAt", item.due_at);
            if (item.description.has_value()) {
                insertString(object, L"description", item.description.value());
            } else {
                object.Insert(L"description", JsonValue::CreateNullValue());
            }
            array.Append(object);
        }
        return wideToUtf8(array.Stringify());
    } catch (const winrt::hresult_error& error) {
        throw std::invalid_argument("Windows.Data.Json: " + wideToUtf8(error.message()));
    }
}

namespace {

core::HudMode parseHudMode(std::string_view value) {
    if (value == "passthrough") return core::HudMode::Passthrough;
    if (value == "interactive") return core::HudMode::Interactive;
    throw std::invalid_argument("unknown HUD mode");
}

core::HudScope parseHudScope(std::string_view value) {
    if (value == "all") return core::HudScope::All;
    if (value == "today") return core::HudScope::Today;
    throw std::invalid_argument("unknown HUD scope");
}

const wchar_t* hudModeName(core::HudMode mode) {
    switch (mode) {
    case core::HudMode::Passthrough: return L"passthrough";
    case core::HudMode::Interactive: return L"interactive";
    }
    throw std::invalid_argument("invalid HUD mode");
}

const wchar_t* hudScopeName(core::HudScope scope) {
    switch (scope) {
    case core::HudScope::All: return L"all";
    case core::HudScope::Today: return L"today";
    }
    throw std::invalid_argument("invalid HUD scope");
}

template <typename Function>
void readSetting(const JsonObject& object, const wchar_t* name, Function&& function) {
    if (!object.HasKey(name)) return;
    try {
        function(object.Lookup(name));
    } catch (const winrt::hresult_error&) {
        // Windows.Data.Json 类型不匹配同样只影响当前字段。
    } catch (const std::exception&) {
        // 单字段损坏回退到默认值；顶层 JSON 损坏仍由 Parse 抛出。
    }
}

void insertBool(JsonObject& object, const wchar_t* name, bool value) {
    object.Insert(name, JsonValue::CreateBooleanValue(value));
}

void insertNumber(JsonObject& object, const wchar_t* name, double value) {
    object.Insert(name, JsonValue::CreateNumberValue(value));
}

void insertUnsigned(JsonObject& object, const wchar_t* name, std::uint32_t value) {
    object.Insert(name, JsonValue::CreateNumberValue(static_cast<double>(value)));
}

} // namespace

core::HudSettings decodeSettings(std::string_view utf8_json) {
    try {
        const auto object = JsonObject::Parse(winrt::hstring(utf8ToWide(utf8_json)));
        core::HudSettings settings;
        readSetting(object, L"isVisible", [&](const auto& value) {
            if (value.ValueType() != JsonValueType::Boolean) throw std::invalid_argument("isVisible is not boolean");
            settings.visible = value.GetBoolean();
        });
        readSetting(object, L"launchAtLogin", [&](const auto& value) {
            if (value.ValueType() != JsonValueType::Boolean) throw std::invalid_argument("launchAtLogin is not boolean");
            settings.launch_at_login = value.GetBoolean();
        });
        readSetting(object, L"mode", [&](const auto& value) {
            if (value.ValueType() != JsonValueType::String) throw std::invalid_argument("mode is not string");
            settings.mode = parseHudMode(wideToUtf8(value.GetString()));
        });
        readSetting(object, L"opacity", [&](const auto& value) {
            if (value.ValueType() != JsonValueType::Number) throw std::invalid_argument("opacity is not number");
            settings.opacity = value.GetNumber();
        });
        readSetting(object, L"isTopmost", [&](const auto& value) {
            if (value.ValueType() != JsonValueType::Boolean) throw std::invalid_argument("isTopmost is not boolean");
            settings.topmost = value.GetBoolean();
        });
        readSetting(object, L"scope", [&](const auto& value) {
            if (value.ValueType() != JsonValueType::String) throw std::invalid_argument("scope is not string");
            settings.scope = parseHudScope(wideToUtf8(value.GetString()));
        });
        readSetting(object, L"maxItems", [&](const auto& value) {
            if (value.ValueType() != JsonValueType::Number) throw std::invalid_argument("maxItems is not number");
            settings.max_items = static_cast<int>(value.GetNumber());
        });
        readSetting(object, L"hudModeHotKeyEnabled", [&](const auto& value) {
            if (value.ValueType() != JsonValueType::Boolean) throw std::invalid_argument("hotkey enabled is not boolean");
            settings.hotkey_enabled = value.GetBoolean();
        });
        readSetting(object, L"hudModeHotKeyShortcut", [&](const auto& value) {
            if (value.ValueType() == JsonValueType::Null) {
                settings.hotkey_modifiers = 0;
                settings.hotkey_key = 0;
                return;
            }
            if (value.ValueType() != JsonValueType::Object) throw std::invalid_argument("hotkey shortcut is not object");
            const auto shortcut = value.GetObject();
            if (shortcut.HasKey(L"modifiers")) {
                const auto modifiers = shortcut.Lookup(L"modifiers");
                if (modifiers.ValueType() != JsonValueType::Number) throw std::invalid_argument("hotkey modifiers is not number");
                settings.hotkey_modifiers = static_cast<std::uint32_t>(modifiers.GetNumber());
            }
            if (shortcut.HasKey(L"key")) {
                const auto key = shortcut.Lookup(L"key");
                if (key.ValueType() != JsonValueType::Number) throw std::invalid_argument("hotkey key is not number");
                settings.hotkey_key = static_cast<std::uint32_t>(key.GetNumber());
            }
        });
        readSetting(object, L"placement", [&](const auto& value) {
            if (value.ValueType() != JsonValueType::Object) throw std::invalid_argument("placement is not object");
            const auto placement = value.GetObject();
            readSetting(placement, L"monitorId", [&](const auto& item) {
                if (item.ValueType() == JsonValueType::Null) {
                    settings.placement.monitor_id.clear();
                    return;
                }
                if (item.ValueType() != JsonValueType::String) throw std::invalid_argument("monitorId is not string");
                settings.placement.monitor_id = wideToUtf8(item.GetString());
            });
            readSetting(placement, L"relativeX", [&](const auto& item) {
                if (item.ValueType() != JsonValueType::Number) throw std::invalid_argument("relativeX is not number");
                settings.placement.relative_x = item.GetNumber();
            });
            readSetting(placement, L"relativeY", [&](const auto& item) {
                if (item.ValueType() != JsonValueType::Number) throw std::invalid_argument("relativeY is not number");
                settings.placement.relative_y = item.GetNumber();
            });
            readSetting(placement, L"logicalWidth", [&](const auto& item) {
                if (item.ValueType() != JsonValueType::Number) throw std::invalid_argument("logicalWidth is not number");
                settings.placement.logical_width = item.GetNumber();
            });
            readSetting(placement, L"logicalHeight", [&](const auto& item) {
                if (item.ValueType() != JsonValueType::Number) throw std::invalid_argument("logicalHeight is not number");
                settings.placement.logical_height = item.GetNumber();
            });
            readSetting(placement, L"dpi", [&](const auto& item) {
                if (item.ValueType() != JsonValueType::Number) throw std::invalid_argument("dpi is not number");
                settings.placement.dpi = static_cast<std::uint32_t>(item.GetNumber());
            });
        });
        return core::normalize(settings);
    } catch (const winrt::hresult_error& error) {
        throw std::invalid_argument("Windows.Data.Json: " + wideToUtf8(error.message()));
    }
}

std::string encodeSettings(const core::HudSettings& raw_settings) {
    try {
        const auto settings = core::normalize(raw_settings);
        JsonObject object;
        insertBool(object, L"isVisible", settings.visible);
        insertBool(object, L"launchAtLogin", settings.launch_at_login);
        insertString(object, L"mode", wideToUtf8String(hudModeName(settings.mode)));
        insertNumber(object, L"opacity", settings.opacity);
        insertBool(object, L"isTopmost", settings.topmost);
        insertString(object, L"scope", wideToUtf8String(hudScopeName(settings.scope)));
        object.Insert(L"maxItems", JsonValue::CreateNumberValue(settings.max_items));
        insertBool(object, L"hudModeHotKeyEnabled", settings.hotkey_enabled);
        if (settings.hotkey_enabled) {
            JsonObject shortcut;
            insertUnsigned(shortcut, L"modifiers", settings.hotkey_modifiers);
            insertUnsigned(shortcut, L"key", settings.hotkey_key);
            object.Insert(L"hudModeHotKeyShortcut", shortcut);
        } else {
            object.Insert(L"hudModeHotKeyShortcut", JsonValue::CreateNullValue());
        }
        JsonObject placement;
        insertString(placement, L"monitorId", settings.placement.monitor_id);
        insertNumber(placement, L"relativeX", settings.placement.relative_x);
        insertNumber(placement, L"relativeY", settings.placement.relative_y);
        insertNumber(placement, L"logicalWidth", settings.placement.logical_width);
        insertNumber(placement, L"logicalHeight", settings.placement.logical_height);
        insertUnsigned(placement, L"dpi", settings.placement.dpi);
        object.Insert(L"placement", placement);
        return wideToUtf8(object.Stringify());
    } catch (const winrt::hresult_error& error) {
        throw std::invalid_argument("Windows.Data.Json: " + wideToUtf8(error.message()));
    }
}

} // namespace ghostpin::codec
