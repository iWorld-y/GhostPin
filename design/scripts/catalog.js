/* 共用组件的状态目录；示例只在本页面内变化。 */
(() => {
  const UI = window.GhostPinUI, M = window.GhostPinModel;
  const $ = id => document.getElementById(id);
  let theme = 'light', demoItems = M.sample(), demoPrefs = { ...M.defaults(), mode:'interactive', focusDoing:false };
  const cooldowns = new Map();
  function specimen(title,code,content,description) {
    return `<article class="specimen"><header class="specimen-top"><h3>${title}</h3><small>${code}</small></header><div class="specimen-body" data-theme="${theme}">${content}</div><p class="specimen-description">${description}</p></article>`;
  }
  function renderRows() {
    const items = M.sample('long');
    const states = [
      ['Todo 默认','task / todo',M.sample()[3],{},'空心圆表示 Todo；点击后进入 Doing。'],
      ['Doing 悬停','task / hover',M.sample()[0],{hover:true},'行背景使用主文字色的 6% 不透明度，文字颜色不变。'],
      ['键盘焦点','task / focus',M.sample()[1],{focus:true},'状态按钮保留焦点描边，支持空格和 Enter。'],
      ['穿透模式','task / disabled',M.sample()[2],{disabled:true},'状态按钮不可操作，任务文字仍然可读。'],
      ['逾期任务','task / overdue',M.sample()[6],{},'标题显示红色删除线，截止日期使用红色；状态仍为 Todo。'],
      ['长标题与组别','task / overflow',items[0],{},'标题最多两行，描述单行省略，组别最多约三个汉字宽度。完整示例文字见悬停提示。'],
    ];
    $('row-states').innerHTML = states.map(([title,code,item,opt,description])=>specimen(title,code,`<div class="row-sample">${UI.row(item,!opt.disabled,opt)}</div>`,description)).join('');
  }
  function renderBoards() {
    const items = M.sample(), p = {...M.defaults(), mode:'interactive'};
    $('board-states').innerHTML = [
      specimen('默认聚焦 Doing','hud / focused',UI.hud(items,p),'头部保留当前范围的完整计数。默认开启聚焦 Doing，因此 Todo 可以有计数而没有可见任务。'),
      specimen('空列表','hud / empty',UI.hud([],{...p,mode:'passthrough'}),'保持 80px 空状态区域；新增提示沿用 CLI 文案，不增加新增任务表单。'),
      specimen('Windows 卡片','hud / windows',UI.hud(items,{...M.defaults('windows'),mode:'interactive',max:4}),'白色半透明面板、绿色边框与 72px 任务卡片。没有套用 macOS 的紧凑行样式。'),
    ].join('');
  }
  function renderColors() {
    const tokens = [['面板背景','--hud-surface','网页近似系统材质'],['分区背景','--hud-section','网页近似 regularMaterial'],['主文字','--hud-ink','primary'],['次要文字','--hud-secondary','secondary'],['强调色','--hud-accent','系统 accentColor 的近似值'],['高优先级 / 逾期','--hud-red','系统 red 的近似值']];
    $('color-tokens').innerHTML = tokens.map(([label,token,note])=>`<div class="swatch"><div class="swatch-color" data-theme="${theme}" style="background:var(${token})"></div><strong>${label}</strong><code>${token}</code><span>${note}</span></div>`).join('');
  }
  function renderSettings() {
    const state = $('hotkey-example').value;
    const prefs = {...M.defaults(), hotkeyState:state};
    let recording=false, error='';
    if(state==='registered') { prefs.shortcut='⌃⌥G';prefs.hotkeyEnabled=true; }
    if(state==='recording') { recording=true;prefs.hotkeyState='pendingConfiguration'; }
    if(state==='invalid') { recording=true;prefs.hotkeyState='pendingConfiguration';error='请包含 Command、Option、Control 或 Shift 修饰键，或使用 F1 至 F20 功能键。'; }
    $('settings-example').dataset.theme=theme;
    $('settings-example').innerHTML=UI.settings(prefs,'advanced',recording,error);
  }
  function renderDemo() {
    $('state-demo').dataset.theme=theme;
    $('state-demo').innerHTML=UI.hud(demoItems,demoPrefs);
  }
  function renderAll() { renderRows();renderBoards();renderColors();renderSettings();renderDemo(); }
  $('catalog-theme').addEventListener('change',()=> { theme=$('catalog-theme').value;renderAll(); });
  $('hotkey-example').addEventListener('change',renderSettings);
  $('demo-reset').addEventListener('click',()=> {demoItems=M.sample();cooldowns.clear();renderDemo();$('demo-feedback').textContent='已重置示例。点击圆形按钮推进任务状态。';});
  $('state-demo').addEventListener('click',event=> {
    const button=event.target.closest('[data-action]');
    if(!button)return;
    if(button.dataset.action==='hide') { $('demo-feedback').textContent='此处展示 HUD 组件。隐藏与恢复流程请在“界面原型”中操作。';return; }
    const item=M.advance(demoItems,Number(button.dataset.id),cooldowns);
    $('demo-feedback').textContent=item ? `示例任务 ${item.id} 已进入 ${item.status}。` : '同一任务的状态变化间隔为 500ms。';
    renderDemo();
  });
  // 静态状态样本只展示其状态，避免样本之间共享或误改示例数据。
  document.querySelectorAll('#row-states, #board-states, #settings-example').forEach(host=>host.addEventListener('click',event=> {
    if(event.target.closest('button,input')) { event.preventDefault(); $('catalog-feedback').textContent='此区域是指定状态样本。完整操作请使用下方状态推进演示或返回界面原型。'; }
  }));
  renderAll();
})();
