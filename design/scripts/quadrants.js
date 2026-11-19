/* 四象限草案的渲染和事件编排；分类与数据由 quadrants-model.js 提供。 */
(() => {
  const M = window.GhostPinModel;
  const UI = window.GhostPinUI;
  const Q = window.GhostPinQuadrants;
  const board = document.querySelector('#board');
  const content = document.querySelector('#board-content');
  const detail = document.querySelector('#task-detail');
  const feedback = document.querySelector('#draft-feedback');
  const cooldowns = new Map();
  const state = { view: 'quadrants', scope: 'all', focusDoing: true, scene: 'normal', items: Q.sample(), detailId: null };
  const labels = { high: '高', medium: '中', low: '低', doing: 'Doing · 进行中', todo: 'Todo · 待处理' };

  function section(status, items) {
    if (!items.length) return '';
    return `<section aria-label="${labels[status]}"><h3 class="hud-section-title ${status === 'doing' ? 'is-doing' : ''}">${status === 'doing' ? '<span class="doing-dot" aria-hidden="true"></span>' : ''}${status.toUpperCase()}<span class="section-count">${items.length}</span></h3>${items.map(item => UI.row(item)).join('')}</section>`;
  }

  function quadrantMarkup(quadrant) {
    const doing = quadrant.items.filter(item => item.status === 'doing');
    const todo = quadrant.items.filter(item => item.status === 'todo');
    const empty = `<div class="quadrant-empty"><p>暂无任务</p><small>${state.scope === 'today' ? '今天新增的任务中没有此类待办' : '符合分类的未完成任务会显示在这里'}</small></div>`;
    return `<section class="quadrant" data-quadrant="${quadrant.id}" aria-labelledby="heading-${quadrant.id}"><header class="quadrant-heading"><div class="od-field"><h2 id="heading-${quadrant.id}">${quadrant.title}</h2><p>${quadrant.subtitle}</p></div><span class="quadrant-count" aria-label="${quadrant.items.length} 个未完成任务">${quadrant.items.length}</span></header><div class="quadrant-list od-scroll" data-scroll="${quadrant.id}" tabindex="0" role="region" aria-label="${quadrant.title}任务列表">${quadrant.items.length ? section('doing', doing) + section('todo', todo) : empty}</div></section>`;
  }

  // 保留共享任务行的内容与样式，让被截断的文字可通过原生按钮打开详情。
  function bindTaskDetails() {
    content.querySelectorAll('.task-row').forEach(row => {
      const status = row.querySelector('.status-button');
      const copy = row.querySelector('.task-copy');
      const item = state.items.find(candidate => candidate.id === Number(status.dataset.id));
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'task-copy task-open';
      button.dataset.action = 'detail';
      button.dataset.id = String(item.id);
      button.setAttribute('aria-label', `查看任务详情：${item.title}`);
      button.append(...copy.childNodes);
      copy.replaceWith(button);
      const remaining = M.COOLDOWN - (performance.now() - (cooldowns.get(item.id) ?? -Infinity));
      if (remaining > 0) {
        status.disabled = true;
        window.setTimeout(() => {
          if (performance.now() - (cooldowns.get(item.id) ?? -Infinity) >= M.COOLDOWN) {
            const current = content.querySelector(`[data-action="advance"][data-id="${item.id}"]`);
            if (current) current.disabled = false;
          }
        }, Math.ceil(remaining) + 1);
      }
    });
  }

  function render(preserveScroll = false) {
    const offsets = new Map([...content.querySelectorAll('[data-scroll]')].map(node => [node.dataset.scroll, node.scrollTop]));
    const projected = Q.project(state.items, state.scope);
    board.dataset.view = state.view;
    document.querySelectorAll('[data-view-button]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.viewButton === state.view)));
    document.querySelector('#board-count').textContent = `Doing ${projected.doingCount} · Todo ${projected.todoCount}`;
    document.querySelector('#footer-scope').textContent = state.scope === 'all' ? '全部未完成' : '今天新增';
    document.querySelector('#focus-doing').disabled = state.view === 'quadrants';
    let visibleCount = projected.visibleCount;
    if (state.view === 'quadrants') {
      content.innerHTML = `<div class="quadrant-grid">${projected.quadrants.map(quadrantMarkup).join('')}</div>`;
    } else {
      const single = M.project(state.items, { ...M.defaults(), scope: state.scope, focusDoing: state.focusDoing });
      visibleCount = single.visibleCount;
      const notice = state.focusDoing && projected.doingCount ? '<p class="list-notice">当前仅显示 Doing 任务</p>' : '';
      const empty = `<div class="list-empty"><p>${state.scope === 'today' ? '今天新增的任务中没有未完成待办' : '没有未完成待办'}</p></div>`;
      content.innerHTML = `${notice}<div class="hud-list od-scroll" data-scroll="list" tabindex="0" role="region" aria-label="单列任务列表">${single.visibleCount ? section('doing', single.doing) + section('todo', single.todo) : empty}</div>`;
    }
    document.querySelector('#footer-count').textContent = `${visibleCount} / ${projected.visibleCount}`;
    bindTaskDetails();
    if (preserveScroll) content.querySelectorAll('[data-scroll]').forEach(node => { node.scrollTop = offsets.get(node.dataset.scroll) || 0; });
  }

  function announce(message) {
    feedback.textContent = message;
  }

  function activeViewButton() {
    return document.querySelector(`[data-view-button="${state.view}"]`);
  }

  function advance(id, trigger) {
    const buttons = [...content.querySelectorAll('[data-action="advance"]')];
    const index = buttons.indexOf(trigger);
    const item = M.advance(state.items, id, cooldowns);
    if (!item) return;
    render(true);
    const sameTask = content.querySelector(`[data-action="detail"][data-id="${id}"]`);
    const nextTask = content.querySelectorAll('[data-action="detail"]')[Math.max(0, index)];
    (sameTask || nextTask || activeViewButton()).focus({ preventScroll: true });
    announce(item.status === 'done' ? `已完成：${item.title}。任务已从当前视图移除。` : `已开始：${item.title}。500ms 内重复点击不会推进状态。`);
  }

  function showDetail(id) {
    const item = state.items.find(candidate => candidate.id === id);
    if (!item) return;
    state.detailId = id;
    const quadrant = Q.definitions.find(definition => definition.id === Q.category(item));
    document.querySelector('#detail-body').innerHTML = `<h3>${UI.escape(item.title)}</h3><p>${UI.escape(item.description || '暂无说明')}</p><dl><dt>当前状态</dt><dd>${labels[item.status]}</dd><dt>所属象限</dt><dd>${quadrant.title}（${quadrant.subtitle}）</dd><dt>优先级</dt><dd>${labels[item.priority]}</dd><dt>分组</dt><dd>${UI.escape(item.group)}</dd><dt>截止时间</dt><dd>${item.dueAt ? `${M.dateLabel(item.dueAt)}${M.overdue(item) ? ' · 已逾期' : ''}` : '未设置'}</dd><dt>创建时间</dt><dd>${M.dateLabel(item.createdAt)}</dd></dl>`;
    detail.showModal();
    document.querySelector('#close-detail').focus();
  }

  function setVisible(visible) {
    board.hidden = !visible;
    document.querySelector('#hidden-board').hidden = visible;
    (visible ? activeViewButton() : document.querySelector('#show-board')).focus();
  }

  function resetScene() {
    state.items = Q.sample(state.scene);
    cooldowns.clear();
    render();
    board.hidden = false;
    document.querySelector('#hidden-board').hidden = true;
    announce('示例任务已重置。参考时间为 2026 年 11 月 17 日 14:30（北京时间）。');
  }

  board.addEventListener('click', event => {
    const button = event.target.closest('button');
    if (!button) return;
    if (button.dataset.viewButton) {
      state.view = button.dataset.viewButton;
      render();
      announce(state.view === 'quadrants' ? '已切换为四象限，显示当前范围内的全部未完成任务。' : '已切换为单列，沿用单列的显示上限和 Doing 聚焦设置。');
    } else if (button.dataset.action === 'advance') advance(Number(button.dataset.id), button);
    else if (button.dataset.action === 'detail') showDetail(Number(button.dataset.id));
    else if (button.dataset.action === 'hide') setVisible(false);
  });
  document.querySelector('#scope').addEventListener('change', event => {
    state.scope = event.target.value;
    render();
    announce(state.scope === 'all' ? '已显示全部未完成任务。' : '已筛选今天新增的未完成任务，截止日期不影响此筛选。');
  });
  document.querySelector('#scene').addEventListener('change', event => {
    state.scene = event.target.value;
    resetScene();
  });
  document.querySelector('#theme').addEventListener('change', event => { document.body.dataset.theme = event.target.value; });
  document.querySelector('#focus-doing').addEventListener('change', event => {
    state.focusDoing = event.target.checked;
    render();
  });
  document.querySelector('#reset-scene').addEventListener('click', resetScene);
  document.querySelector('#show-board').addEventListener('click', () => setVisible(true));
  document.querySelector('#close-detail').addEventListener('click', () => detail.close());
  detail.addEventListener('close', () => {
    const trigger = content.querySelector(`[data-action="detail"][data-id="${state.detailId}"]`);
    (trigger || activeViewButton()).focus({ preventScroll: true });
  });
  render();
})();
