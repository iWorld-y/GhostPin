/* 示例数据和任务状态逻辑。独立于 DOM，不读取或写入真实任务。 */
window.GhostPinModel = (() => {
  const NOW = Date.parse('2026-11-17T14:30:00+08:00');
  const DAY_START = Date.parse('2026-11-17T00:00:00+08:00');
  const COOLDOWN = 500;
  const priorities = { high: 3, medium: 2, low: 1 };
  const day = 86400000;
  const rows = [
    [10001, 'doing', '整理本周项目进展', '汇总已完成事项和下一步安排', 'high', '工作', 3, 0],
    [10002, 'doing', '更新组件说明', '补充键盘焦点与禁用状态', 'medium', 'GhostPin', 25, 0],
    [10003, 'doing', '核对交付清单', '逐项确认附件与说明', 'low', '默认', null, 1],
    [10004, 'todo', '准备周会材料', '整理需要讨论的问题', 'high', '工作', 4, 0],
    [10005, 'todo', '阅读界面设计笔记', '记录原生控件的行为差异', 'medium', '学习', 28, 0],
    [10006, 'todo', '整理书桌', '', 'low', '生活', null, 1],
    [10007, 'todo', '归档上周会议记录', '补齐遗漏的行动项', 'high', '工作', -20, 1],
    [10008, 'todo', '检查长分组名称的展示', '完整组名只用于示例', 'medium', '设计系统维护', null, 0],
    [10009, 'done', '整理参考资料', '已完成任务不会显示在 HUD 中', 'low', '默认', null, 0],
  ];
  function sample(scenario = 'standard') {
    if (scenario === 'empty') return [];
    const items = rows.map(([id, status, title, description, priority, group, hours, ago], i) => ({
      id, status, title, description, priority, group,
      createdAt: NOW - ago * day - i * 60000,
      dueAt: hours === null ? null : NOW + hours * 3600000,
    }));
    if (scenario === 'long') {
      items[0].title = '核对桌面便签在较窄窗口中的标题换行与右侧标记对齐方式';
      items[0].description = '这是一段用于展示单行省略行为的较长说明文字，完整内容可在组件说明中查看。';
      items[0].group = '公共组件与设计规范';
    }
    if (scenario === 'overflow') {
      for (let i = 10; i < 24; i++) items.push({ ...items[1], id: 10000 + i, title: `整理组件状态记录 ${i - 9}`, status: i % 3 ? 'todo' : 'doing' });
    }
    return items;
  }
  function defaults(platform = 'mac') {
    return { platform, mode: 'passthrough', scope: 'all', max: 8, focusDoing: platform === 'mac',
      passthroughOpacity: 100, interactiveOpacity: 100, opacity: 100,
      visible: true, topmost: true, allSpaces: true, login: false,
      hotkeyEnabled: false, shortcut: '', hotkeyState: 'disabled' };
  }
  const overdue = item => item.status !== 'done' && item.dueAt !== null && item.dueAt < NOW;
  function compare(a, b) {
    if (a.status !== b.status) return a.status === 'doing' ? -1 : 1;
    if (overdue(a) !== overdue(b)) return overdue(a) ? 1 : -1;
    if (a.priority !== b.priority) return priorities[b.priority] - priorities[a.priority];
    if (a.dueAt !== b.dueAt) return a.dueAt === null ? 1 : b.dueAt === null ? -1 : a.dueAt - b.dueAt;
    return b.createdAt - a.createdAt || b.id - a.id;
  }
  function project(items, prefs) {
    const all = items.filter(x => x.status !== 'done' && (prefs.scope !== 'today' || x.createdAt >= DAY_START)).sort(compare);
    const doing = all.filter(x => x.status === 'doing');
    const todo = all.filter(x => x.status === 'todo');
    const focused = prefs.platform === 'mac' && prefs.focusDoing && doing.length > 0;
    const visible = (focused ? doing : all).slice(0, prefs.max);
    return { doing: visible.filter(x => x.status === 'doing'), todo: visible.filter(x => x.status === 'todo'), doingCount: doing.length, todoCount: todo.length, visibleCount: visible.length };
  }
  function advance(items, id, cooldowns, now = performance.now()) {
    const item = items.find(x => x.id === id);
    if (!item || item.status === 'done' || now - (cooldowns.get(id) ?? -Infinity) < COOLDOWN) return null;
    item.status = item.status === 'todo' ? 'doing' : 'done';
    cooldowns.set(id, now);
    return item;
  }
  function dateLabel(value) {
    if (!value) return '';
    const d = new Date(value + 8 * 3600000);
    return `${d.getUTCMonth() + 1}月${d.getUTCDate()}日 ${String(d.getUTCHours()).padStart(2, '0')}:${String(d.getUTCMinutes()).padStart(2, '0')}`;
  }
  return { NOW, COOLDOWN, sample, defaults, overdue, project, advance, dateLabel };
})();
