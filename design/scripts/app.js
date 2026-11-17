/* 页面编排：连接共用组件与示例状态，不调用系统或真实 GhostPin CLI。 */
(() => {
  const M = window.GhostPinModel, UI = window.GhostPinUI;
  let prefs = M.defaults(), items = M.sample(), tab = 'hud', settingsOpen = false;
  let menuOpen = false, recording = false, hotkeyError = '', hovered = false, quit = false;
  const cooldowns = new Map();
  const $ = id => document.getElementById(id);
  const announce = text => { $('interaction-note').textContent = text; };
  function applyOpacity() {
    const hud = $('hud-host').querySelector('[data-native-hud]');
    if (!hud) return;
    const ghosted = prefs.platform === 'mac' && prefs.mode === 'passthrough' && hovered;
    hud.style.opacity = ghosted ? '0' : String((prefs.platform === 'windows' ? prefs.opacity : prefs.mode === 'interactive' ? prefs.interactiveOpacity : prefs.passthroughOpacity) / 100);
  }
  function render() {
    const focused = document.activeElement;
    const focusPref = focused?.dataset.pref, focusAction = focused?.dataset.action, focusId = focused?.dataset.id;
    const theme = prefs.platform === 'windows' ? 'light' : $('appearance').value;
    $('desktop-stage').dataset.theme = theme;
    $('appearance').disabled = prefs.platform === 'windows';
    $('appearance-note').textContent = prefs.platform === 'windows' ? 'Windows 当前实现仅定义浅色外观' : '网页颜色近似系统语义色';
    $('platform-caption').textContent = prefs.platform === 'mac' ? 'macOS 桌面模拟' : 'Windows 桌面模拟';
    $('surface-label').textContent = prefs.platform === 'mac' ? '桌面 HUD' : 'Windows HUD';
    $('hud-host').innerHTML = prefs.visible && !quit ? UI.hud(items,prefs) : `<div class="hidden-message"><strong>${quit?'演示已退出':'桌面便签已隐藏'}</strong>${quit?'点击“重置示例”重新开始。':'从菜单栏选择“显示桌面便签”可恢复。'}</div>`;
    const hud = $('hud-host').querySelector('.hud');
    if (hud) hud.style.width = `${$('preview-width').value}px`;
    $('settings-host').innerHTML = settingsOpen && !quit ? UI.settings(prefs,tab,recording,hotkeyError) : '';
    $('menu-host').innerHTML = menuOpen && !quit ? UI.menu(prefs) : '';
    $('menu-host').hidden = !menuOpen || quit;
    $('tray-button').setAttribute('aria-expanded',String(menuOpen && !quit));
    $('tray-button').disabled = quit;
    $('tray-count').textContent = String(items.filter(x => x.status!=='done').length || '');
    $('mode-button').textContent = prefs.mode === 'passthrough' ? '切换到交互模式' : '切换到穿透模式';
    $('mode-button').disabled = quit;
    $('open-settings').disabled = quit;
    $('width-output').textContent = `${$('preview-width').value} px`;
    $('mode-explanation').textContent = prefs.platform === 'mac' && prefs.mode === 'passthrough' ? '穿透模式下，指针进入 HUD 区域会暂时隐藏便签。点击左侧按钮或菜单切换交互模式。' : prefs.mode === 'interactive' ? '点击任务圆形按钮推进状态；完成后任务从列表移除。操作只影响示例。' : '穿透模式下任务按钮不可用。浏览器演示不改变系统鼠标事件。';
    applyOpacity();
    const selector = focusPref ? `[data-pref="${focusPref}"]` : focusAction === 'advance' && focusId ? `[data-action="advance"][data-id="${focusId}"]` : null;
    if (selector) document.querySelector(selector)?.focus({preventScroll:true});
  }
  function reset() {
    prefs = M.defaults($('platform').value); items = M.sample($('scenario').value);
    if (['mixed','long','overflow'].includes($('scenario').value)) prefs.focusDoing = false;
    if ($('scenario').value === 'overflow') prefs.max = 20;
    cooldowns.clear(); recording = false; hotkeyError = ''; hovered = false; quit = false;
    menuOpen = false; settingsOpen = false; tab = 'hud';
    $('preview-width').min = prefs.platform === 'mac' ? '320' : '300';
    $('preview-width').value = prefs.platform === 'mac' ? '380' : '360';
    render(); announce('示例已重置。任务与设置未写入真实应用。');
  }
  function setPreference(input) {
    const key = input.dataset.pref;
    let value = input.type === 'checkbox' ? input.checked : input.value;
    if (key === 'mode') value = input.checked ? 'interactive' : 'passthrough';
    if (['max','opacity','passthroughOpacity','interactiveOpacity'].includes(key)) {
      const min = key==='max'?1:key==='opacity'?50:10, max = key==='max'?20:100;
      value = Math.max(min,Math.min(max, Number(value) || min));
    }
    if (key==='hotkeyEnabled') {
      prefs.hotkeyEnabled = Boolean(value && prefs.shortcut);
      prefs.hotkeyState = value ? prefs.shortcut ? 'registered' : 'pendingConfiguration' : 'disabled';
      recording = false; hotkeyError = '';
    } else prefs[key] = value;
    render();
    announce(['allSpaces','topmost','login'].includes(key) ? '已更新演示状态，未更改系统窗口或登录设置。' : '设置已应用于示例 HUD；刷新页面会恢复初始值。');
  }
  function action(name, id) {
    if (name==='advance') {
      if (prefs.mode!=='interactive') return;
      const item = M.advance(items,Number(id),cooldowns);
      if (!item) { announce('同一任务的状态推进间隔为 500ms，请稍后再试。'); return; }
      render(); announce(`“${item.title}”已${item.status==='done'?'完成并从 HUD 移除':'进入 Doing'}，仅修改示例。`); return;
    }
    if (name==='hide') { prefs.visible=false; announce('桌面便签已隐藏，可从菜单栏重新显示。'); }
    if (name==='toggle-visible') { prefs.visible=!prefs.visible; menuOpen=false; }
    if (name==='toggle-mode') { prefs.mode=prefs.mode==='interactive'?'passthrough':'interactive'; menuOpen=false; }
    if (name==='settings') { settingsOpen=true; menuOpen=false; }
    if (name==='close-settings') { settingsOpen=false; recording=false; }
    if (name==='quit') { quit=true; menuOpen=false; settingsOpen=false; announce('仅退出本次演示，真实 GhostPin 未受影响。'); }
    if (name==='record') { recording=true; hotkeyError=''; announce('录制仅在当前页面接收按键，Esc 可取消。'); }
    if (name==='clear-hotkey') { prefs.shortcut=''; prefs.hotkeyEnabled=false; prefs.hotkeyState='disabled'; recording=false; hotkeyError=''; }
    if (name==='default-hotkey') { prefs.shortcut='Ctrl+Alt+G'; prefs.hotkeyEnabled=true; prefs.hotkeyState='registered'; hotkeyError=''; }
    render();
    if (name==='settings') document.querySelector('[role="tab"][aria-selected="true"]')?.focus();
  }
  document.addEventListener('click',event=> {
    const target = event.target.closest('[data-action], [data-tab]');
    if (!target || target.disabled) return;
    if (target.dataset.tab) { tab=target.dataset.tab; recording=false; hotkeyError=''; render(); document.querySelector(`[data-tab="${tab}"]`)?.focus(); }
    else action(target.dataset.action,target.dataset.id);
  });
  document.addEventListener('change',event=> { if(event.target.dataset.pref) setPreference(event.target); });
  document.addEventListener('input',event=> {
    const input = event.target;
    if (input.type!=='range' || !input.dataset.pref) return;
    prefs[input.dataset.pref]=Number(input.value);
    document.querySelectorAll(`[data-pref="${input.dataset.pref}"]`).forEach(x=>x.value=input.value);
    applyOpacity();
  });
  document.addEventListener('keydown',event=> {
    if (recording) {
      event.preventDefault();
      if (event.key==='Escape') { recording=false; hotkeyError=''; render(); return; }
      if (['Meta','Alt','Control','Shift'].includes(event.key)) return;
      if (!(event.metaKey||event.altKey||event.ctrlKey||event.shiftKey||/^F([1-9]|1[0-9]|20)$/.test(event.key))) { hotkeyError='请包含修饰键，或使用 F1 至 F20 功能键。'; render(); return; }
      const modifiers = prefs.platform==='mac' ? [[event.ctrlKey,'⌃'],[event.altKey,'⌥'],[event.shiftKey,'⇧'],[event.metaKey,'⌘']] : [[event.ctrlKey,'Ctrl'],[event.altKey,'Alt'],[event.shiftKey,'Shift'],[event.metaKey,'Win']];
      prefs.shortcut=[...modifiers.filter(x=>x[0]).map(x=>x[1]),event.key.toUpperCase()].join(prefs.platform==='mac'?'':'+');
      prefs.hotkeyEnabled=true; prefs.hotkeyState='registered'; recording=false; hotkeyError=''; render();
      announce('组合键已用于演示；未注册系统快捷键。'); return;
    }
    if (event.key==='Escape') { menuOpen=false; if(settingsOpen)settingsOpen=false; render(); }
    if (event.target.matches('[role="tab"]') && ['ArrowLeft','ArrowRight','Home','End'].includes(event.key)) {
      event.preventDefault(); tab=event.key==='Home'?'hud':event.key==='End'?'advanced':tab==='hud'?'advanced':'hud'; render(); document.querySelector(`[data-tab="${tab}"]`)?.focus();
    }
  });
  $('tray-button').addEventListener('click',()=> {menuOpen=!menuOpen;render();});
  $('mode-button').addEventListener('click',()=>action('toggle-mode'));
  $('open-settings').addEventListener('click',()=>action('settings'));
  $('reset').addEventListener('click',reset);
  $('platform').addEventListener('change',reset);
  $('scenario').addEventListener('change',reset);
  $('appearance').addEventListener('change',render);
  $('preview-width').addEventListener('input',()=> { const h=$('hud-host').querySelector('.hud');if(h)h.style.width=`${$('preview-width').value}px`;$('width-output').textContent=`${$('preview-width').value} px`; });
  $('hud-zone').addEventListener('pointerenter',()=> {hovered=true;applyOpacity();});
  $('hud-zone').addEventListener('pointerleave',()=> {hovered=false;applyOpacity();});
  render();
})();
