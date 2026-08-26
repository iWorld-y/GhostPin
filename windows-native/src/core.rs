use std::time::SystemTime;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Status {
    Todo,
    Doing,
    Done,
}

#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
pub enum Priority {
    Low,
    Medium,
    High,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum HudScope {
    All,
    Today,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum HudMode {
    Passthrough,
    Interactive,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Todo {
    pub id: String,
    pub title: String,
    pub created_at: SystemTime,
    pub status: Status,
    pub completed_at: Option<SystemTime>,
    pub reminder_at: Option<SystemTime>,
    pub reminder_sent_at: Option<SystemTime>,
    pub priority: Priority,
    pub due_at: Option<SystemTime>,
    pub description: Option<String>,
}

#[derive(Clone, Copy, Debug)]
pub struct ProjectionOptions {
    pub scope: HudScope,
    pub max_count: usize,
    pub now: SystemTime,
    pub today_start: SystemTime,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Projection {
    pub items: Vec<Todo>,
    pub doing: Vec<Todo>,
    pub todo: Vec<Todo>,
}

pub fn is_completed(item: &Todo) -> bool {
    item.status == Status::Done
}

pub fn is_overdue(item: &Todo, now: SystemTime) -> bool {
    item.due_at
        .is_some_and(|due| !is_completed(item) && due < now)
}

pub fn project(source: &[Todo], options: ProjectionOptions) -> Projection {
    let mut ordered: Vec<Todo> = source
        .iter()
        .filter(|item| !is_completed(item))
        .filter(|item| options.scope == HudScope::All || item.created_at >= options.today_start)
        .cloned()
        .collect();
    ordered.sort_by(|left, right| {
        let status = |item: &Todo| (item.status != Status::Doing) as u8;
        status(left)
            .cmp(&status(right))
            .then_with(|| is_overdue(left, options.now).cmp(&is_overdue(right, options.now)))
            .then_with(|| right.priority.cmp(&left.priority))
            .then_with(|| left.due_at.cmp(&right.due_at))
            .then_with(|| right.created_at.cmp(&left.created_at))
    });
    ordered.truncate(options.max_count);
    let doing = ordered
        .iter()
        .filter(|item| item.status == Status::Doing)
        .cloned()
        .collect();
    let todo = ordered
        .iter()
        .filter(|item| item.status == Status::Todo)
        .cloned()
        .collect();
    Projection {
        items: ordered,
        doing,
        todo,
    }
}

pub fn next_status(status: Status) -> Option<Status> {
    match status {
        Status::Todo => Some(Status::Doing),
        Status::Doing => Some(Status::Done),
        Status::Done => None,
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct AdvanceResult {
    pub index: usize,
    pub status: Status,
}

pub struct AdvanceService<F = fn() -> u64>
where
    F: Fn() -> u64,
{
    clock: F,
    last_successful: Vec<(String, u64)>,
}

impl Default for AdvanceService<fn() -> u64> {
    fn default() -> Self {
        Self::new(monotonic_millis)
    }
}

impl<F> AdvanceService<F>
where
    F: Fn() -> u64,
{
    pub fn new(clock: F) -> Self {
        Self {
            clock,
            last_successful: Vec::new(),
        }
    }
    pub fn is_cooling_down(&self, id: &str) -> bool {
        self.last_successful
            .iter()
            .find(|(key, _)| key == id)
            .is_some_and(|(_, at)| (self.clock)().saturating_sub(*at) < 500)
    }
    pub fn rollback(&mut self, id: &str) {
        self.last_successful.retain(|(key, _)| key != id);
    }
    pub fn advance(&mut self, item: &mut Todo, completed_at: SystemTime) -> bool {
        let Some(next) = next_status(item.status) else {
            return false;
        };
        if self.is_cooling_down(&item.id) {
            return false;
        }
        item.status = next;
        item.completed_at = (next == Status::Done).then_some(completed_at);
        let now = (self.clock)();
        if let Some((_, at)) = self
            .last_successful
            .iter_mut()
            .find(|(id, _)| id == &item.id)
        {
            *at = now;
        } else {
            self.last_successful.push((item.id.clone(), now));
        }
        true
    }
    pub fn advance_by_id(
        &mut self,
        items: &mut [Todo],
        id: &str,
        completed_at: SystemTime,
    ) -> Option<AdvanceResult> {
        let (index, item) = items
            .iter_mut()
            .enumerate()
            .find(|(_, item)| item.id == id)?;
        self.advance(item, completed_at).then_some(AdvanceResult {
            index,
            status: item.status,
        })
    }
}

fn monotonic_millis() -> u64 {
    static ORIGIN: std::sync::OnceLock<std::time::Instant> = std::sync::OnceLock::new();
    ORIGIN
        .get_or_init(std::time::Instant::now)
        .elapsed()
        .as_millis() as u64
}

#[derive(Clone, Debug, PartialEq)]
pub struct Placement {
    pub monitor_id: String,
    pub relative_x: f64,
    pub relative_y: f64,
    pub logical_width: f64,
    pub logical_height: f64,
    pub dpi: u32,
}
impl Default for Placement {
    fn default() -> Self {
        Self {
            monitor_id: String::new(),
            relative_x: 0.0,
            relative_y: 0.0,
            logical_width: 360.0,
            logical_height: 460.0,
            dpi: 96,
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct HudSettings {
    pub visible: bool,
    pub launch_at_login: bool,
    pub mode: HudMode,
    pub topmost: bool,
    pub opacity: f64,
    pub scope: HudScope,
    pub max_items: usize,
    pub hotkey_enabled: bool,
    pub hotkey_modifiers: u32,
    pub hotkey_key: u32,
    pub placement: Placement,
}
impl Default for HudSettings {
    fn default() -> Self {
        Self {
            visible: true,
            launch_at_login: false,
            mode: HudMode::Passthrough,
            topmost: true,
            opacity: 1.0,
            scope: HudScope::All,
            max_items: 8,
            hotkey_enabled: false,
            hotkey_modifiers: 0,
            hotkey_key: 0,
            placement: Placement::default(),
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct HotkeyCandidate {
    pub modifiers: u32,
    pub key: u32,
}
pub const HOTKEY_ALT: u32 = 0x0001;
pub const HOTKEY_CONTROL: u32 = 0x0002;
pub const HOTKEY_SHIFT: u32 = 0x0004;
pub const HOTKEY_WIN: u32 = 0x0008;
pub const HOTKEY_NOREPEAT: u32 = 0x4000;

pub fn normalize_placement(mut placement: Placement) -> Placement {
    if !placement.relative_x.is_finite() {
        placement.relative_x = 0.0;
    }
    if !placement.relative_y.is_finite() {
        placement.relative_y = 0.0;
    }
    if !placement.logical_width.is_finite() || !(300.0..=1920.0).contains(&placement.logical_width)
    {
        placement.logical_width = 360.0;
    }
    if !placement.logical_height.is_finite()
        || !(280.0..=1600.0).contains(&placement.logical_height)
    {
        placement.logical_height = 460.0;
    }
    if !(48..=768).contains(&placement.dpi) {
        placement.dpi = 96;
    }
    placement
}

fn modifier_key(key: u32) -> bool {
    matches!(key, 0x10 | 0x11 | 0x12 | 0x5b | 0x5c | 0xa0..=0xa5)
}
pub fn normalize_hotkey(mut modifiers: u32, key: u32) -> Option<HotkeyCandidate> {
    modifiers &= HOTKEY_ALT | HOTKEY_CONTROL | HOTKEY_SHIFT | HOTKEY_WIN;
    if modifier_key(key) {
        return None;
    }
    let has_modifier = modifiers != 0;
    let function_key = (0x70..=0x83).contains(&key);
    let regular_key = (1..=0xff).contains(&key);
    (has_modifier && regular_key || !has_modifier && function_key)
        .then_some(HotkeyCandidate { modifiers, key })
}
pub fn valid_hotkey(modifiers: u32, key: u32) -> bool {
    normalize_hotkey(modifiers, key).is_some()
}

pub fn normalize_settings(mut settings: HudSettings) -> HudSettings {
    if !settings.opacity.is_finite() || !(0.5..=1.0).contains(&settings.opacity) {
        settings.opacity = 1.0;
    }
    if !(1..=20).contains(&settings.max_items) {
        settings.max_items = 8;
    }
    settings.placement = normalize_placement(settings.placement);
    if let Some(hotkey) = normalize_hotkey(settings.hotkey_modifiers, settings.hotkey_key) {
        settings.hotkey_modifiers = hotkey.modifiers;
        settings.hotkey_key = hotkey.key;
    } else {
        settings.hotkey_enabled = false;
        settings.hotkey_modifiers = 0;
        settings.hotkey_key = 0;
    }
    settings
}

#[derive(Clone, Debug, PartialEq)]
pub struct MonitorWorkArea {
    pub id: String,
    pub left: i32,
    pub top: i32,
    pub right: i32,
    pub bottom: i32,
    pub dpi: u32,
    pub primary: bool,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct PixelRect {
    pub left: i32,
    pub top: i32,
    pub right: i32,
    pub bottom: i32,
}

pub fn restore_placement(
    placement: &Placement,
    monitors: &[MonitorWorkArea],
    primary_id: &str,
) -> PixelRect {
    let placement = normalize_placement(placement.clone());
    let monitor = monitors
        .iter()
        .find(|m| m.id.eq_ignore_ascii_case(&placement.monitor_id))
        .or_else(|| {
            monitors
                .iter()
                .find(|m| m.primary || m.id.eq_ignore_ascii_case(primary_id))
        })
        .or_else(|| monitors.first());
    let Some(monitor) = monitor else {
        return PixelRect {
            left: 0,
            top: 0,
            right: 300,
            bottom: 280,
        };
    };
    let scale = monitor.dpi.max(1) as f64 / 96.0;
    let area_width = (monitor.right - monitor.left).max(1) as f64;
    let area_height = (monitor.bottom - monitor.top).max(1) as f64;
    let width = (placement.logical_width * scale)
        .round()
        .clamp((300.0 * scale).min(area_width), area_width)
        .max(1.0) as i32;
    let height = (placement.logical_height * scale)
        .round()
        .clamp((280.0 * scale).min(area_height), area_height)
        .max(1.0) as i32;
    let left_max = (monitor.right - width).max(monitor.left) as f64;
    let top_max = (monitor.bottom - height).max(monitor.top) as f64;
    let left = (monitor.left as f64
        + placement
            .relative_x
            .clamp(0.0, (left_max - monitor.left as f64) / scale)
            * scale)
        .round()
        .clamp(monitor.left as f64, left_max) as i32;
    let top = (monitor.top as f64
        + placement
            .relative_y
            .clamp(0.0, (top_max - monitor.top as f64) / scale)
            * scale)
        .round()
        .clamp(monitor.top as f64, top_max) as i32;
    PixelRect {
        left,
        top,
        right: left.saturating_add(width),
        bottom: top.saturating_add(height),
    }
}

pub fn save_placement(rect: PixelRect, monitor: &MonitorWorkArea) -> Placement {
    let dpi = if (48..=768).contains(&monitor.dpi) {
        monitor.dpi
    } else {
        96
    };
    let scale = 96.0 / dpi as f64;
    normalize_placement(Placement {
        monitor_id: monitor.id.clone(),
        relative_x: (rect.left - monitor.left) as f64 * scale,
        relative_y: (rect.top - monitor.top) as f64 * scale,
        logical_width: (rect.right - rect.left) as f64 * scale,
        logical_height: (rect.bottom - rect.top) as f64 * scale,
        dpi,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    fn item(id: &str, status: Status, priority: Priority) -> Todo {
        Todo {
            id: id.into(),
            title: id.into(),
            created_at: SystemTime::UNIX_EPOCH,
            status,
            completed_at: None,
            reminder_at: None,
            reminder_sent_at: None,
            priority,
            due_at: None,
            description: None,
        }
    }

    #[test]
    fn projection_orders_doing_before_todo_and_hides_done() {
        let source = vec![
            item("todo", Status::Todo, Priority::High),
            item("done", Status::Done, Priority::High),
            item("doing", Status::Doing, Priority::Low),
        ];
        let result = project(
            &source,
            ProjectionOptions {
                scope: HudScope::All,
                max_count: 8,
                now: SystemTime::now(),
                today_start: SystemTime::UNIX_EPOCH,
            },
        );
        assert_eq!(
            result
                .items
                .iter()
                .map(|item| item.id.as_str())
                .collect::<Vec<_>>(),
            ["doing", "todo"]
        );
    }

    #[test]
    fn advance_has_cooldown_and_completion_time() {
        let now = std::cell::Cell::new(0u64);
        let mut service = AdvanceService::new(|| now.get());
        let mut todo = item("a", Status::Todo, Priority::Medium);
        assert!(service.advance(&mut todo, SystemTime::UNIX_EPOCH));
        assert!(!service.advance(&mut todo, SystemTime::UNIX_EPOCH));
        now.set(500);
        assert!(service.advance(&mut todo, SystemTime::UNIX_EPOCH));
        assert_eq!(todo.status, Status::Done);
    }

    #[test]
    fn invalid_hotkeys_are_rejected() {
        assert!(valid_hotkey(HOTKEY_CONTROL, 0x47));
        assert!(!valid_hotkey(0, 0x47));
        assert!(valid_hotkey(0, 0x70));
        assert!(!valid_hotkey(HOTKEY_SHIFT, 0x10));
    }
}
