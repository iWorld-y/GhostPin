use std::{
    fmt,
    marker::PhantomData,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use windows::{
    Data::Json::{IJsonValue, JsonArray, JsonObject, JsonValue, JsonValueType},
    Win32::System::WinRT::{RO_INIT_SINGLETHREADED, RoInitialize, RoUninitialize},
    core::{Error as WindowsError, HSTRING, Param},
};

use crate::core::{self, HudMode, HudScope, HudSettings, Priority, Status, Todo};

#[derive(Debug)]
pub enum CodecError {
    Invalid(String),
    Windows(String),
}
impl fmt::Display for CodecError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Invalid(message) | Self::Windows(message) => formatter.write_str(message),
        }
    }
}
impl std::error::Error for CodecError {}
impl From<WindowsError> for CodecError {
    fn from(error: WindowsError) -> Self {
        Self::Windows(error.message().to_string())
    }
}
type Result<T> = std::result::Result<T, CodecError>;

pub struct RuntimeApartment {
    _thread_affine: PhantomData<std::rc::Rc<()>>,
}
impl RuntimeApartment {
    pub fn new() -> Result<Self> {
        // SAFETY: this initializes (or increments) the apartment for the current thread only.
        unsafe { RoInitialize(RO_INIT_SINGLETHREADED) }.map_err(CodecError::from)?;
        Ok(Self {
            _thread_affine: PhantomData,
        })
    }
}
impl Drop for RuntimeApartment {
    fn drop(&mut self) {
        // SAFETY: every successful RoInitialize call has a matching guard and uninitialize.
        unsafe {
            RoUninitialize();
        }
    }
}

fn invalid(message: impl Into<String>) -> CodecError {
    CodecError::Invalid(message.into())
}
fn key(value: &str) -> HSTRING {
    HSTRING::from(value)
}
fn value_type(value: &IJsonValue) -> Result<JsonValueType> {
    value.ValueType().map_err(CodecError::from)
}
fn required_string(object: &JsonObject, name: &str) -> Result<String> {
    let value = object.Lookup(&key(name)).map_err(CodecError::from)?;
    if value_type(&value)? != JsonValueType::String {
        return Err(invalid(format!("JSON field {name} is not a string")));
    }
    Ok(value
        .GetString()
        .map_err(CodecError::from)?
        .to_string_lossy())
}
fn nullable_string(object: &JsonObject, name: &str) -> Result<Option<String>> {
    if !object.HasKey(&key(name)).map_err(CodecError::from)? {
        return Ok(None);
    }
    let value = object.Lookup(&key(name)).map_err(CodecError::from)?;
    match value_type(&value)? {
        JsonValueType::Null => Ok(None),
        JsonValueType::String => Ok(Some(
            value
                .GetString()
                .map_err(CodecError::from)?
                .to_string_lossy(),
        )),
        _ => Err(invalid(format!(
            "nullable JSON field {name} is not a string"
        ))),
    }
}
fn parse_status(value: &str) -> Result<Status> {
    match value {
        "todo" => Ok(Status::Todo),
        "doing" => Ok(Status::Doing),
        "done" => Ok(Status::Done),
        _ => Err(invalid("unknown todo status")),
    }
}
fn parse_priority(value: &str) -> Result<Priority> {
    match value {
        "high" => Ok(Priority::High),
        "medium" => Ok(Priority::Medium),
        "low" => Ok(Priority::Low),
        _ => Err(invalid("unknown todo priority")),
    }
}
fn parse_mode(value: &str) -> Result<HudMode> {
    match value {
        "passthrough" => Ok(HudMode::Passthrough),
        "interactive" => Ok(HudMode::Interactive),
        _ => Err(invalid("unknown HUD mode")),
    }
}
fn parse_scope(value: &str) -> Result<HudScope> {
    match value {
        "all" => Ok(HudScope::All),
        "today" => Ok(HudScope::Today),
        _ => Err(invalid("unknown HUD scope")),
    }
}

fn parse_number(value: &str, offset: usize, length: usize) -> Result<i32> {
    let part = value
        .get(offset..offset + length)
        .ok_or_else(|| invalid("ISO 8601 date is too short"))?;
    if !part.bytes().all(|byte| byte.is_ascii_digit()) {
        return Err(invalid("ISO 8601 date contains a non-digit"));
    }
    part.parse::<i32>()
        .map_err(|_| invalid("ISO 8601 date number is too large"))
}
fn leap(year: i32) -> bool {
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}
fn days_in_month(year: i32, month: u32) -> u32 {
    [
        31,
        if leap(year) { 29 } else { 28 },
        31,
        30,
        31,
        30,
        31,
        31,
        30,
        31,
        30,
        31,
    ][month as usize - 1]
}
fn days_from_civil(mut year: i32, month: u32, day: u32) -> i64 {
    year -= (month <= 2) as i32;
    let era = if year >= 0 { year } else { year - 399 } / 400;
    let year_of_era = (year - era * 400) as u32;
    let day_of_year =
        (153 * (month as i32 + if month > 2 { -3 } else { 9 }) + 2) as u32 / 5 + day - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    era as i64 * 146097 + day_of_era as i64 - 719468
}
fn civil_from_days(mut days: i64) -> (i32, u32, u32) {
    days += 719468;
    let era = if days >= 0 { days } else { days - 146096 } / 146097;
    let day_of_era = (days - era * 146097) as u32;
    let year_of_era =
        (day_of_era - day_of_era / 1460 + day_of_era / 36524 - day_of_era / 146096) / 365;
    let mut year = year_of_era as i32 + era as i32 * 400;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let month_part = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * month_part + 2) / 5 + 1;
    let month = if month_part < 10 {
        month_part + 3
    } else {
        month_part - 9
    };
    year += (month <= 2) as i32;
    (year, month, day)
}
fn parse_iso8601(value: &str) -> Result<SystemTime> {
    let bytes = value.as_bytes();
    if value.len() < 20
        || bytes.get(4) != Some(&b'-')
        || bytes.get(7) != Some(&b'-')
        || bytes.get(10) != Some(&b'T')
        || bytes.get(13) != Some(&b':')
        || bytes.get(16) != Some(&b':')
    {
        return Err(invalid("invalid ISO 8601 date"));
    }
    let year = parse_number(value, 0, 4)?;
    let month = parse_number(value, 5, 2)? as u32;
    let day = parse_number(value, 8, 2)? as u32;
    let hour = parse_number(value, 11, 2)? as u32;
    let minute = parse_number(value, 14, 2)? as u32;
    let second = parse_number(value, 17, 2)? as u32;
    if !(1..=9999).contains(&year)
        || !(1..=12).contains(&month)
        || !(1..=days_in_month(year, month)).contains(&day)
        || hour > 23
        || minute > 59
        || second > 59
    {
        return Err(invalid("invalid ISO 8601 value"));
    }
    let mut cursor = 19;
    let mut millis = 0u64;
    if bytes.get(cursor) == Some(&b'.') {
        cursor += 1;
        let begin = cursor;
        while bytes.get(cursor).is_some_and(u8::is_ascii_digit) {
            cursor += 1;
        }
        if cursor == begin {
            return Err(invalid("invalid ISO 8601 fraction"));
        }
        millis = value[begin..cursor]
            .bytes()
            .take(3)
            .enumerate()
            .map(|(index, byte)| (byte - b'0') as u64 * [100, 10, 1][index])
            .sum();
    }
    let offset_minutes = if bytes.get(cursor) == Some(&b'Z') {
        cursor += 1;
        0i64
    } else if matches!(bytes.get(cursor), Some(b'+') | Some(b'-')) {
        let sign = if bytes[cursor] == b'+' { 1 } else { -1 };
        cursor += 1;
        let hours = parse_number(value, cursor, 2)?;
        cursor += 2;
        if bytes.get(cursor) != Some(&b':') {
            return Err(invalid("invalid ISO 8601 offset"));
        }
        cursor += 1;
        let minutes = parse_number(value, cursor, 2)?;
        cursor += 2;
        if hours > 14 || minutes > 59 || (hours == 14 && minutes != 0) {
            return Err(invalid("invalid ISO 8601 offset"));
        }
        sign * (hours as i64 * 60 + minutes as i64)
    } else {
        return Err(invalid("ISO 8601 date has no timezone"));
    };
    if cursor != value.len() {
        return Err(invalid("invalid ISO 8601 suffix"));
    }
    let seconds = days_from_civil(year, month, day) * 86400
        + hour as i64 * 3600
        + minute as i64 * 60
        + second as i64
        - offset_minutes * 60;
    if seconds >= 0 {
        Ok(UNIX_EPOCH + Duration::from_secs(seconds as u64) + Duration::from_millis(millis))
    } else {
        Ok(UNIX_EPOCH - Duration::from_secs((-seconds) as u64) + Duration::from_millis(millis))
    }
}
fn append_two(value: &mut String, number: u32) {
    value.push((b'0' + (number / 10) as u8) as char);
    value.push((b'0' + (number % 10) as u8) as char);
}
fn format_iso8601(value: SystemTime) -> Result<String> {
    let total_millis = match value.duration_since(UNIX_EPOCH) {
        Ok(duration) => duration.as_millis() as i64,
        Err(error) => -(error.duration().as_millis() as i64),
    };
    let total_seconds = total_millis.div_euclid(1000);
    let days = total_seconds.div_euclid(86400);
    let day_seconds = total_seconds.rem_euclid(86400);
    let (year, month, day) = civil_from_days(days);
    if !(1..=9999).contains(&year) {
        return Err(invalid("ISO 8601 year is outside 0001..9999"));
    }
    let mut result = format!("{year:04}-");
    append_two(&mut result, month);
    result.push('-');
    append_two(&mut result, day);
    result.push('T');
    append_two(&mut result, (day_seconds / 3600) as u32);
    result.push(':');
    append_two(&mut result, ((day_seconds % 3600) / 60) as u32);
    result.push(':');
    append_two(&mut result, (day_seconds % 60) as u32);
    result.push('Z');
    Ok(result)
}
fn normalize_uuid(value: &str) -> Result<String> {
    if value.len() != 36 {
        return Err(invalid("invalid todo UUID"));
    }
    let normalized = value.to_ascii_lowercase();
    for (index, byte) in value.bytes().enumerate() {
        if matches!(index, 8 | 13 | 18 | 23) {
            if byte != b'-' {
                return Err(invalid("invalid todo UUID"));
            }
        } else if !byte.is_ascii_hexdigit() {
            return Err(invalid("invalid todo UUID"));
        }
    }
    Ok(normalized)
}
fn optional_time(object: &JsonObject, name: &str) -> Result<Option<SystemTime>> {
    nullable_string(object, name)?
        .map(|value| parse_iso8601(&value))
        .transpose()
}

pub fn decode_todos(utf8_json: &str) -> Result<Vec<Todo>> {
    let array = JsonArray::Parse(&HSTRING::from(utf8_json)).map_err(CodecError::from)?;
    let size = array.Size().map_err(CodecError::from)?;
    let mut result = Vec::with_capacity(size as usize);
    for index in 0..size {
        let object = array.GetObjectAt(index).map_err(CodecError::from)?;
        let completed_at = optional_time(&object, "completedAt")?;
        let status = if !object.HasKey(&key("status")).map_err(CodecError::from)? {
            completed_at.map(|_| Status::Done).unwrap_or(Status::Todo)
        } else {
            let value = object.Lookup(&key("status")).map_err(CodecError::from)?;
            if value_type(&value)? == JsonValueType::Null {
                completed_at.map(|_| Status::Done).unwrap_or(Status::Todo)
            } else {
                parse_status(
                    &value
                        .GetString()
                        .map_err(CodecError::from)?
                        .to_string_lossy(),
                )?
            }
        };
        let priority = if !object.HasKey(&key("priority")).map_err(CodecError::from)? {
            Priority::Medium
        } else {
            let value = object.Lookup(&key("priority")).map_err(CodecError::from)?;
            if value_type(&value)? == JsonValueType::Null {
                Priority::Medium
            } else {
                parse_priority(
                    &value
                        .GetString()
                        .map_err(CodecError::from)?
                        .to_string_lossy(),
                )?
            }
        };
        result.push(Todo {
            id: normalize_uuid(&required_string(&object, "id")?)?,
            title: required_string(&object, "title")?,
            created_at: parse_iso8601(&required_string(&object, "createdAt")?)?,
            status,
            completed_at,
            reminder_at: optional_time(&object, "reminderAt")?,
            reminder_sent_at: optional_time(&object, "reminderSentAt")?,
            priority,
            due_at: optional_time(&object, "dueAt")?,
            description: nullable_string(&object, "description")?,
        });
    }
    Ok(result)
}

fn status_name(status: Status) -> &'static str {
    match status {
        Status::Todo => "todo",
        Status::Doing => "doing",
        Status::Done => "done",
    }
}
fn priority_name(priority: Priority) -> &'static str {
    match priority {
        Priority::High => "high",
        Priority::Medium => "medium",
        Priority::Low => "low",
    }
}
fn insert<P>(object: &JsonObject, name: &str, value: P) -> Result<()>
where
    P: Param<IJsonValue>,
{
    object
        .Insert(&key(name), value)
        .map(|_| ())
        .map_err(CodecError::from)
}
fn insert_string(object: &JsonObject, name: &str, value: &str) -> Result<()> {
    let json = JsonValue::CreateStringValue(&HSTRING::from(value)).map_err(CodecError::from)?;
    insert(object, name, &json)
}
fn insert_number(object: &JsonObject, name: &str, value: f64) -> Result<()> {
    let json = JsonValue::CreateNumberValue(value).map_err(CodecError::from)?;
    insert(object, name, &json)
}
fn insert_bool(object: &JsonObject, name: &str, value: bool) -> Result<()> {
    let json = JsonValue::CreateBooleanValue(value).map_err(CodecError::from)?;
    insert(object, name, &json)
}
fn insert_null(object: &JsonObject, name: &str) -> Result<()> {
    let json = JsonValue::CreateNullValue().map_err(CodecError::from)?;
    insert(object, name, &json)
}
fn insert_date(object: &JsonObject, name: &str, value: SystemTime) -> Result<()> {
    let text = format_iso8601(value)?;
    insert_string(object, name, &text)
}
fn insert_nullable_date(object: &JsonObject, name: &str, value: Option<SystemTime>) -> Result<()> {
    match value {
        Some(value) => insert_date(object, name, value),
        None => insert_null(object, name),
    }
}
pub fn encode_todos(items: &[Todo]) -> Result<String> {
    let array = JsonArray::new().map_err(CodecError::from)?;
    for item in items {
        let object = JsonObject::new().map_err(CodecError::from)?;
        let id = normalize_uuid(&item.id)?;
        insert_string(&object, "id", &id)?;
        insert_string(&object, "title", &item.title)?;
        insert_date(&object, "createdAt", item.created_at)?;
        insert_string(&object, "status", status_name(item.status))?;
        insert_nullable_date(&object, "completedAt", item.completed_at)?;
        insert_nullable_date(&object, "reminderAt", item.reminder_at)?;
        insert_nullable_date(&object, "reminderSentAt", item.reminder_sent_at)?;
        insert_string(&object, "priority", priority_name(item.priority))?;
        insert_nullable_date(&object, "dueAt", item.due_at)?;
        match &item.description {
            Some(value) => insert_string(&object, "description", value)?,
            None => insert_null(&object, "description")?,
        }
        array.Append(&object).map_err(CodecError::from)?;
    }
    Ok(array
        .Stringify()
        .map_err(CodecError::from)?
        .to_string_lossy())
}

fn read_setting<F>(object: &JsonObject, name: &str, apply: F)
where
    F: FnOnce(IJsonValue) -> Result<()>,
{
    if object.HasKey(&key(name)).ok() != Some(true) {
        return;
    }
    if let Ok(value) = object.Lookup(&key(name)) {
        let _ = apply(value);
    }
}
pub fn decode_settings(utf8_json: &str) -> Result<HudSettings> {
    let object = JsonObject::Parse(&HSTRING::from(utf8_json)).map_err(CodecError::from)?;
    let mut settings = HudSettings::default();
    read_setting(&object, "isVisible", |value| {
        if value_type(&value)? != JsonValueType::Boolean {
            return Err(invalid("isVisible is not boolean"));
        }
        settings.visible = value.GetBoolean().map_err(CodecError::from)?;
        Ok(())
    });
    read_setting(&object, "launchAtLogin", |value| {
        if value_type(&value)? != JsonValueType::Boolean {
            return Err(invalid("launchAtLogin is not boolean"));
        }
        settings.launch_at_login = value.GetBoolean().map_err(CodecError::from)?;
        Ok(())
    });
    read_setting(&object, "mode", |value| {
        if value_type(&value)? != JsonValueType::String {
            return Err(invalid("mode is not string"));
        }
        settings.mode = parse_mode(
            &value
                .GetString()
                .map_err(CodecError::from)?
                .to_string_lossy(),
        )?;
        Ok(())
    });
    read_setting(&object, "opacity", |value| {
        if value_type(&value)? != JsonValueType::Number {
            return Err(invalid("opacity is not number"));
        }
        settings.opacity = value.GetNumber().map_err(CodecError::from)?;
        Ok(())
    });
    read_setting(&object, "isTopmost", |value| {
        if value_type(&value)? != JsonValueType::Boolean {
            return Err(invalid("isTopmost is not boolean"));
        }
        settings.topmost = value.GetBoolean().map_err(CodecError::from)?;
        Ok(())
    });
    read_setting(&object, "scope", |value| {
        if value_type(&value)? != JsonValueType::String {
            return Err(invalid("scope is not string"));
        }
        settings.scope = parse_scope(
            &value
                .GetString()
                .map_err(CodecError::from)?
                .to_string_lossy(),
        )?;
        Ok(())
    });
    read_setting(&object, "maxItems", |value| {
        if value_type(&value)? != JsonValueType::Number {
            return Err(invalid("maxItems is not number"));
        }
        settings.max_items = value.GetNumber().map_err(CodecError::from)?.max(0.0) as usize;
        Ok(())
    });
    read_setting(&object, "hudModeHotKeyEnabled", |value| {
        if value_type(&value)? != JsonValueType::Boolean {
            return Err(invalid("hotkey enabled is not boolean"));
        }
        settings.hotkey_enabled = value.GetBoolean().map_err(CodecError::from)?;
        Ok(())
    });
    read_setting(&object, "hudModeHotKeyShortcut", |value| {
        if value_type(&value)? == JsonValueType::Null {
            settings.hotkey_modifiers = 0;
            settings.hotkey_key = 0;
            return Ok(());
        }
        if value_type(&value)? != JsonValueType::Object {
            return Err(invalid("hotkey shortcut is not object"));
        }
        let shortcut = value.GetObject().map_err(CodecError::from)?;
        if shortcut
            .HasKey(&key("modifiers"))
            .map_err(CodecError::from)?
        {
            settings.hotkey_modifiers = shortcut
                .Lookup(&key("modifiers"))
                .map_err(CodecError::from)?
                .GetNumber()
                .map_err(CodecError::from)? as u32;
        }
        if shortcut.HasKey(&key("key")).map_err(CodecError::from)? {
            settings.hotkey_key = shortcut
                .Lookup(&key("key"))
                .map_err(CodecError::from)?
                .GetNumber()
                .map_err(CodecError::from)? as u32;
        }
        Ok(())
    });
    read_setting(&object, "placement", |value| {
        if value_type(&value)? != JsonValueType::Object {
            return Err(invalid("placement is not object"));
        }
        let placement = value.GetObject().map_err(CodecError::from)?;
        if placement
            .HasKey(&key("monitorId"))
            .map_err(CodecError::from)?
        {
            let value = placement
                .Lookup(&key("monitorId"))
                .map_err(CodecError::from)?;
            settings.placement.monitor_id = if value_type(&value)? == JsonValueType::Null {
                String::new()
            } else {
                value
                    .GetString()
                    .map_err(CodecError::from)?
                    .to_string_lossy()
            };
        }
        if placement
            .HasKey(&key("relativeX"))
            .map_err(CodecError::from)?
        {
            settings.placement.relative_x = placement
                .Lookup(&key("relativeX"))
                .map_err(CodecError::from)?
                .GetNumber()
                .map_err(CodecError::from)?;
        }
        if placement
            .HasKey(&key("relativeY"))
            .map_err(CodecError::from)?
        {
            settings.placement.relative_y = placement
                .Lookup(&key("relativeY"))
                .map_err(CodecError::from)?
                .GetNumber()
                .map_err(CodecError::from)?;
        }
        if placement
            .HasKey(&key("logicalWidth"))
            .map_err(CodecError::from)?
        {
            settings.placement.logical_width = placement
                .Lookup(&key("logicalWidth"))
                .map_err(CodecError::from)?
                .GetNumber()
                .map_err(CodecError::from)?;
        }
        if placement
            .HasKey(&key("logicalHeight"))
            .map_err(CodecError::from)?
        {
            settings.placement.logical_height = placement
                .Lookup(&key("logicalHeight"))
                .map_err(CodecError::from)?
                .GetNumber()
                .map_err(CodecError::from)?;
        }
        if placement.HasKey(&key("dpi")).map_err(CodecError::from)? {
            settings.placement.dpi = placement
                .Lookup(&key("dpi"))
                .map_err(CodecError::from)?
                .GetNumber()
                .map_err(CodecError::from)? as u32;
        }
        Ok(())
    });
    Ok(core::normalize_settings(settings))
}
pub fn encode_settings(raw: &HudSettings) -> Result<String> {
    let settings = core::normalize_settings(raw.clone());
    let object = JsonObject::new().map_err(CodecError::from)?;
    insert_bool(&object, "isVisible", settings.visible)?;
    insert_bool(&object, "launchAtLogin", settings.launch_at_login)?;
    insert_string(
        &object,
        "mode",
        match settings.mode {
            HudMode::Passthrough => "passthrough",
            HudMode::Interactive => "interactive",
        },
    )?;
    insert_number(&object, "opacity", settings.opacity)?;
    insert_bool(&object, "isTopmost", settings.topmost)?;
    insert_string(
        &object,
        "scope",
        match settings.scope {
            HudScope::All => "all",
            HudScope::Today => "today",
        },
    )?;
    insert_number(&object, "maxItems", settings.max_items as f64)?;
    insert_bool(&object, "hudModeHotKeyEnabled", settings.hotkey_enabled)?;
    if settings.hotkey_enabled {
        let shortcut = JsonObject::new().map_err(CodecError::from)?;
        insert_number(&shortcut, "modifiers", settings.hotkey_modifiers as f64)?;
        insert_number(&shortcut, "key", settings.hotkey_key as f64)?;
        insert(&object, "hudModeHotKeyShortcut", &shortcut)?;
    } else {
        insert_null(&object, "hudModeHotKeyShortcut")?;
    }
    let placement = JsonObject::new().map_err(CodecError::from)?;
    insert_string(&placement, "monitorId", &settings.placement.monitor_id)?;
    insert_number(&placement, "relativeX", settings.placement.relative_x)?;
    insert_number(&placement, "relativeY", settings.placement.relative_y)?;
    insert_number(&placement, "logicalWidth", settings.placement.logical_width)?;
    insert_number(
        &placement,
        "logicalHeight",
        settings.placement.logical_height,
    )?;
    insert_number(&placement, "dpi", settings.placement.dpi as f64)?;
    insert(&object, "placement", &placement)?;
    Ok(object
        .Stringify()
        .map_err(CodecError::from)?
        .to_string_lossy())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn round_trip_todo_uses_windows_json() {
        std::thread::spawn(|| {
            let _apartment = RuntimeApartment::new().expect("WinRT apartment");
            let item = Todo {
                id: "123e4567-e89b-12d3-a456-426614174000".into(),
                title: "测试".into(),
                created_at: UNIX_EPOCH,
                status: Status::Todo,
                completed_at: None,
                reminder_at: None,
                reminder_sent_at: None,
                priority: Priority::High,
                due_at: None,
                description: Some("描述".into()),
            };
            let encoded = encode_todos(std::slice::from_ref(&item)).expect("encode");
            assert_eq!(decode_todos(&encoded).expect("decode"), vec![item]);
        })
        .join()
        .expect("WinRT test thread");
    }

    #[test]
    fn nested_apartment_guards_can_drop_in_reverse_order() {
        std::thread::spawn(|| {
            let outer = RuntimeApartment::new().expect("outer WinRT apartment");
            let item = Todo {
                id: "123e4567-e89b-12d3-a456-426614174001".into(),
                title: "嵌套 apartment".into(),
                created_at: UNIX_EPOCH,
                status: Status::Todo,
                completed_at: None,
                reminder_at: None,
                reminder_sent_at: None,
                priority: Priority::Medium,
                due_at: None,
                description: None,
            };
            let encoded = encode_todos(std::slice::from_ref(&item)).expect("encode");
            {
                let _inner = RuntimeApartment::new().expect("inner WinRT apartment");
                assert_eq!(
                    decode_todos(&encoded).expect("inner decode"),
                    vec![item.clone()]
                );
            }
            assert_eq!(decode_todos(&encoded).expect("outer decode"), vec![item]);
            drop(outer);
        })
        .join()
        .expect("WinRT nested apartment test thread");
    }
}
