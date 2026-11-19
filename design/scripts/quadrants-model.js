/* 四象限草案的示例数据和分类规则；不访问真实待办。 */
window.GhostPinQuadrants = (() => {
  const M = window.GhostPinModel;
  const HOUR = 3600000;
  const DAY = 24 * HOUR;
  const nextDay = Math.floor((M.NOW + 8 * HOUR) / DAY) * DAY - 8 * HOUR + DAY;
  const definitions = [
    { id: 'first', title: '优先处理', subtitle: '重要 · 紧急' },
    { id: 'second', title: '安排时间', subtitle: '重要 · 不紧急' },
    { id: 'third', title: '及时处理', subtitle: '一般 · 紧急' },
    { id: 'fourth', title: '稍后处理', subtitle: '一般 · 不紧急' },
  ];

  // 截止时间只决定紧急程度；未设置截止日期的任务归为不紧急。
  function category(item) {
    const important = item.priority === 'high';
    const urgent = item.dueAt !== null && item.dueAt < nextDay;
    return important ? (urgent ? 'first' : 'second') : (urgent ? 'third' : 'fourth');
  }

  function sample(scene = 'normal') {
    if (scene === 'empty') return [];
    const rows = [
      [10001, 'doing', '提交周会材料', '汇总本周进展，补充需要讨论的问题', 'high', '工作', 3, 0],
      [10002, 'todo', '核对项目交付清单', '确认附件和使用说明是否齐全', 'high', '工作', 4, 0],
      [10003, 'todo', '归档上周会议记录', '补齐遗漏的行动项', 'high', '工作', -20, 1],
      [10004, 'doing', '梳理下一阶段计划', '明确交付范围与先后顺序', 'high', '工作', 72, 1],
      [10005, 'todo', '补充组件使用说明', '整理键盘操作与空状态的使用约定', 'high', 'GhostPin', 25, 0],
      [10006, 'doing', '回复日程确认', '确认明天的会议时间', 'medium', '工作', 3, 0],
      [10007, 'todo', '预约设备检修', '联系服务人员确认可预约时间', 'low', '生活', 5, 0],
      [10008, 'doing', '阅读设计笔记', '记录紧凑界面中的信息层级', 'medium', '学习', 48, 0],
      [10009, 'todo', '整理参考资料', '将截图和记录归入对应项目', 'low', '默认', null, 1],
      [10010, 'todo', '核对较长任务标题在四象限窗口中的换行与信息展示', '这条示例用于查看较长的任务标题、说明和分组名称。点击标题可以阅读全部内容。', 'medium', '公共组件与设计规范', null, 0],
    ];
    let items = rows.map(([id, status, title, description, priority, group, hours, daysAgo], index) => ({
      id, status, title, description, priority, group,
      createdAt: M.NOW - daysAgo * DAY - index * 60000,
      dueAt: hours === null ? null : M.NOW + hours * HOUR,
    }));
    if (scene === 'one-empty') items = items.filter(item => category(item) !== 'third');
    if (scene === 'overflow') {
      for (let index = 1; index <= 12; index++) {
        items.push({ ...items[1], id: 10100 + index, title: `核对交付附件 ${index}`, description: '逐项核对名称、版本和说明', status: index <= 3 ? 'doing' : 'todo' });
      }
    }
    return items;
  }

  // 复用现有排序；四象限不应用单列的数量上限和 Doing 聚焦。
  function project(items, scope) {
    const projected = M.project(items, { ...M.defaults(), scope, max: items.length, focusDoing: false });
    const all = [...projected.doing, ...projected.todo];
    return {
      ...projected,
      quadrants: definitions.map(definition => ({ ...definition, items: all.filter(item => category(item) === definition.id) })),
    };
  }

  return { definitions, category, sample, project };
})();
