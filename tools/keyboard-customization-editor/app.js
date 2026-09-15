(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const copy = value => JSON.parse(JSON.stringify(value));
  const D = EditorDefaults;
  const state = { skin: copy(D.skin), layout: copy(D.layout), assets: new Map(), urls: new Map(), tab: 'colors', selected: 'space', theme: 'light', language: 'chinese', shift: false, skinDirty: false, layoutDirty: false };
  const colorGroups = [
    ['面板与候选栏', [['panelBackground','面板背景'],['candidateBackground','候选栏背景'],['candidateText','候选文字'],['candidateReading','编码文字'],['candidateDivider','候选分隔线']]],
    ['按键', [['letterKeyBackground','字母键背景'],['functionKeyBackground','功能键背景'],['spaceKeyBackground','空格背景'],['primaryFunctionBackground','回车背景'],['letterKeyText','字母文字'],['functionKeyText','功能键文字'],['primaryFunctionText','回车文字'],['keyBorder','键帽边框']]],
    ['按下状态', [['letterKeyPressedBackground','字母键按下'],['functionKeyPressedBackground','功能键按下'],['primaryFunctionPressedBackground','回车按下']]],
    ['模式与提示', [['modeKeyBackgroundEnglish','英文模式键背景'],['modeKeyBackgroundChinese','中文模式键背景'],['modeKeyTextEnglish','英文模式键文字'],['modeKeyTextChinese','中文模式键文字'],['previewBackground','预览气泡背景'],['previewText','预览气泡文字'],['previewShadow','预览气泡阴影'],['errorText','错误提示文字']]]
  ];
  const imageLabels = { panelBackground:'面板背景', letterKey:'字母键帽', functionKey:'功能键帽', spaceKey:'空格键帽', enterKey:'回车键帽' };
  const keyLabels = { 'left-action':'Esc', delete:'⌫', space:'空格', enter:'↵', number:'ϟ12', 'punctuation-comma':'，', 'punctuation-period':'。', symbol:'符', 'punctuation-comma-period':'，。', 'input-method-switch':'切换' };
  const defaultWeights = { 'left-action':1.35, delete:1.3, space:4.8, enter:1.35, number:1.35, 'punctuation-comma':0.9, 'punctuation-period':0.9, 'input-method-switch':1.35 };
  const groupFields = new Map();
  let busy = false;
  let dragging = '';
  const syncHeaderHeight = () => document.documentElement.style.setProperty('--topbar-height', document.querySelector('.topbar').getBoundingClientRect().height + 'px');
  if (typeof ResizeObserver === 'function') new ResizeObserver(syncHeaderHeight).observe(document.querySelector('.topbar'));
  addEventListener('resize', syncHeaderHeight);
  syncHeaderHeight();
  function el(tag, attrs = {}, text) {
    const element = document.createElement(tag);
    for (const [key,value] of Object.entries(attrs)) {
      if (key === 'class') element.className = value;
      else element.setAttribute(key, value);
    }
    if (text !== undefined) element.textContent = text;
    return element;
  }
  function status(message, error = false) { $('status').textContent = message; $('status').classList.toggle('error', error); }
  function palette() { return { ...D[state.theme], ...state.skin.colors }; }
  function effectiveWeight(key) { return key.weight ?? defaultWeights[key.id] ?? 1; }
  function locate(id = state.selected) {
    for (let r = 0; r < state.layout.rows.length; r++) {
      const k = state.layout.rows[r].keys.findIndex(key => key.id === id);
      if (k >= 0) return { r, k, key: state.layout.rows[r].keys[k] };
    }
  }
  function label(key) {
    if (key.label !== undefined) return key.label;
    if (key.id.startsWith('letter-')) {
      const letter = key.id.slice(-1);
      return state.language === 'english' && !state.shift ? letter : letter.toUpperCase();
    }
    if (key.id === 'left-action' && state.language === 'english') return '⇧';
    if (key.id === 'space' && state.language === 'english') return 'space';
    if (state.language === 'english' && key.id === 'punctuation-comma') return ',';
    if (state.language === 'english' && key.id === 'punctuation-period') return '.';
    return keyLabels[key.id] || key.id;
  }
  function syncIdentity() {
    for (const kind of ['skin','layout']) for (const field of ['name','id']) $(kind + '-' + field).value = state[kind][field];
    $('preview-name').textContent = state.skin.name;
  }
  function buildColorFields() {
    for (const [title, fields] of colorGroups) {
      const section = el('div', { class:'color-group' });
      section.append(el('h3', {}, title));
      for (const [token,title] of fields) {
        const row = el('div', { class:'color-row' });
        const caption = el('label', { for:`color-${token}` }, title);
        const color = el('input', { type:'color', id:`color-${token}`, 'aria-label':`${title}选色`, title });
        const text = el('input', { type:'text', id:`hex-${token}`, 'aria-label':`${title}颜色值`, maxlength:'9', spellcheck:'false', pattern:'#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?' });
        const reset = el('button', { title:'继承系统颜色', 'aria-label':`${title}继承系统` }, '↶');
        row.append(caption, color, text, reset); section.append(row);
        groupFields.set(token, { row, color, text });
        color.addEventListener('input', () => {
          state.skin.colors[token] = color.value.toUpperCase(); state.skinDirty = true;
          text.value = state.skin.colors[token]; text.setCustomValidity(''); row.classList.remove('inherited'); renderPreview();
        });
        text.addEventListener('input', () => {
          if (!/^#[\da-fA-F]{6}([\da-fA-F]{2})?$/.test(text.value)) { text.setCustomValidity('请输入 #RRGGBB 或八位十六进制颜色。'); return; }
          text.setCustomValidity(''); state.skin.colors[token] = text.value.toUpperCase(); state.skinDirty = true;
          color.value = text.value.slice(0,7); row.classList.remove('inherited'); renderPreview();
        });
        reset.addEventListener('click', () => { delete state.skin.colors[token]; state.skinDirty = true; syncColors(); renderPreview(); });
      }
      $('color-fields').append(section);
    }
  }
  function syncColors() {
    const p = palette();
    for (const [token, field] of groupFields) {
      field.color.value = p[token].slice(0,7); field.text.value = p[token]; field.text.setCustomValidity('');
      field.row.classList.toggle('inherited', state.skin.colors[token] === undefined);
    }
  }
  function rebuildUrls() {
    for (const url of state.urls.values()) URL.revokeObjectURL(url);
    state.urls.clear();
    for (const [path,blob] of state.assets) state.urls.set(path, URL.createObjectURL(blob));
  }
  function pruneAssets() {
    const used = new Set(Object.values(state.skin.images));
    for (const key of state.assets.keys()) if (!used.has(key)) state.assets.delete(key);
    rebuildUrls();
  }
  async function checkImage(blob) {
    const url = URL.createObjectURL(blob);
    try {
      const img = new Image(); img.src = url;
      await img.decode();
      if (!img.naturalWidth || !img.naturalHeight) throw new Error('empty image');
    } catch (_) { throw new Error('图片无法读取，请选择有效的 PNG、JPG 或 WebP 图片。'); }
    finally { URL.revokeObjectURL(url); }
  }
  function renderImages() {
    $('image-fields').replaceChildren();
    for (const slot of EditorIO.IMAGE_KEYS) {
      const row = el('div', { class:'image-row' });
      const header = el('header'); header.append(el('strong', {}, imageLabels[slot])); row.append(header);
      const thumb = el('div', { class:'image-thumb' });
      const path = state.skin.images[slot];
      if (state.urls.has(path)) thumb.append(el('img', { src:state.urls.get(path), alt:`${imageLabels[slot]}素材` }));
      else thumb.textContent = path ? '缺少图片，请重新选择' : '使用颜色';
      row.append(thumb);
      const actions = el('div', { class:'actions' });
      const pick = el('button', { 'aria-label':`选择${imageLabels[slot]}图片` }, '选择图片');
      const remove = el('button', { 'aria-label':`移除${imageLabels[slot]}图片` }, '移除'); remove.disabled = !path;
      const file = el('input', { type:'file', accept:'.png,.jpg,.jpeg,.webp', hidden:'' });
      actions.append(pick, remove, file); row.append(actions);
      if (path) row.append(el('small', {}, path));
      pick.addEventListener('click', () => file.click());
      file.addEventListener('change', () => withBusy(async () => {
        const image = file.files[0]; if (!image) return;
        const extension = image.name.split('.').pop().toLowerCase();
        if (!['png','jpg','jpeg','webp'].includes(extension) || image.size > 12*1024*1024) throw new Error('请选择不超过 12MB 的 PNG、JPG、WebP 图片。');
        await checkImage(image);
        // A package may share an image between slots. Replacing one must not change another.
        let suffix = 0;
        let path = `assets/${slot}.${extension}`;
        while (Object.entries(state.skin.images).some(([other, ref]) => other !== slot && ref === path)) {
          path = `assets/${slot}-${++suffix}.${extension}`;
        }
        const skin = copy(state.skin); skin.images[slot] = path;
        const assets = new Map(state.assets); assets.set(path, image);
        // Other slots from a raw JSON import may still be missing. Export will check all.
        const total = [...new Set(Object.values(skin.images))].reduce((sum, ref) => sum + (assets.get(ref)?.size || 0), 0);
        if (total > 24*1024*1024) throw new Error('图片总量超过 24MB，请缩小图片。');
        state.skin = skin; state.assets = assets; state.skinDirty = true; pruneAssets(); renderImages(); renderPreview();
        status(`已替换${imageLabels[slot]}，可导出皮肤包保存。`);
      }));
      remove.addEventListener('click', () => { delete state.skin.images[slot]; state.skinDirty = true; pruneAssets(); renderImages(); renderPreview(); });
      $('image-fields').append(row);
    }
  }
  function syncInspector() {
    const pos = locate(); if (!pos) return;
    $('selected-title').textContent = label(pos.key); $('selected-id').textContent = pos.key.id;
    $('key-weight').value = effectiveWeight(pos.key); $('key-weight').setCustomValidity('');
    $('key-label').value = pos.key.label ?? '';
    $('move-left').disabled = pos.k === 0; $('move-right').disabled = pos.k === state.layout.rows[pos.r].keys.length-1;
    $('move-up').disabled = pos.r === 0 || state.layout.rows[pos.r].keys.length === 1 || state.layout.rows[pos.r-1]?.keys.length >= 12;
    $('move-down').disabled = pos.r === state.layout.rows.length-1 || state.layout.rows[pos.r].keys.length === 1 || state.layout.rows[pos.r+1]?.keys.length >= 12;
  }
  function setTab(tab) {
    state.tab = tab;
    document.querySelectorAll('[data-tab]').forEach(button => button.setAttribute('aria-pressed', button.dataset.tab === tab));
    for (const name of ['colors','images','layout']) $('tab-' + name).hidden = name !== tab;
    $('skin-identity').hidden = tab === 'layout';
    renderPreview();
  }
  function renderPreview() {
    const p = palette();
    $('preview-name').textContent = state.skin.name || '未命名皮肤';
    $('keyboard-panel').style.backgroundColor = p.panelBackground;
    const bg = state.urls.get(state.skin.images.panelBackground);
    $('keyboard-panel').style.backgroundImage = bg ? `url("${bg}")` : '';
    $('candidates').style.backgroundColor = p.candidateBackground;
    $('candidates').style.color = p.candidateText;
    $('candidates').style.borderBottom = `1px solid ${p.candidateDivider}`;
    $('reading').style.color = p.candidateReading;
    $('reading').textContent = state.language === 'english' ? 'hello' : 'shuang yu';
    const candidates = $('candidates').querySelectorAll('.candidate-list span');
    ['双羽','双语','双鱼'].forEach((word,i) => candidates[i].textContent = state.language === 'english' ? ['hello','help','hey'][i] : word);
    $('keyboard-mode').textContent = state.language === 'english' ? 'English' : '中文';
    document.querySelector('.keyboard-bottom').style.color = p.functionKeyText;
    $('keyboard').replaceChildren();
    for (const rowDef of state.layout.rows) {
      const row = el('div', { class:'key-row', 'data-kind':rowDef.kind ?? '' });
      for (const key of rowDef.keys) {
        const isLetter = key.id.startsWith('letter-');
        const isEnter = key.id === 'enter';
        const slot = isLetter ? 'letterKey' : key.id === 'space' ? 'spaceKey' : isEnter ? 'enterKey' : 'functionKey';
        let background = isLetter ? p.letterKeyBackground : key.id === 'space' ? p.spaceKeyBackground : isEnter ? p.primaryFunctionBackground : p.functionKeyBackground;
        let foreground = isLetter ? p.letterKeyText : isEnter ? p.primaryFunctionText : p.functionKeyText;
        if (key.id === 'number') {
          background = state.language === 'english' ? p.modeKeyBackgroundEnglish : p.modeKeyBackgroundChinese;
          foreground = state.language === 'english' ? p.modeKeyTextEnglish : p.functionKeyText;
        }
        const button = el('button', { class:'key' + (isLetter ? '' : ' function'), 'data-key-id':key.id, 'aria-label':`${label(key)}按键`, title:state.tab === 'layout' ? '点选编辑，拖动交换位置' : '按住查看按下效果', draggable:state.tab === 'layout' ? 'true' : 'false' });
        button.style.flexGrow = effectiveWeight(key); button.style.borderColor = p.keyBorder;
        button.style.setProperty('--key-bg', background); button.style.setProperty('--key-fg', foreground);
        button.style.setProperty('--key-pressed', isLetter ? p.letterKeyPressedBackground : isEnter ? p.primaryFunctionPressedBackground : p.functionKeyPressedBackground);
        const image = state.urls.get(state.skin.images[slot]); if (image) button.style.backgroundImage = `url("${image}")`;
        button.classList.toggle('selected', state.tab === 'layout' && state.selected === key.id);
        if (key.id === 'punctuation-comma' || key.id === 'punctuation-period') button.append(el('span', { class:'upper', 'aria-hidden':'true' }, key.id === 'punctuation-comma' ? '=' : (state.language === 'english' ? '?' : '？')));
        button.append(el('span', { class:'main-label' }, label(key)));
        button.addEventListener('click', () => {
          if (state.tab === 'layout') { state.selected = key.id; syncInspector(); renderPreview(); return; }
          const out = $('demo-output');
          if (isLetter) out.textContent = (out.textContent + label(key)).slice(-80);
          else if (key.id === 'space') out.textContent += ' ';
          else if (key.id === 'delete') out.textContent = Array.from(out.textContent).slice(0,-1).join('');
          else if (key.id === 'left-action') { if (state.language === 'english') { state.shift = !state.shift; renderPreview(); } else out.textContent = ''; }
          else if (key.id === 'enter') out.textContent += '\n';
          else if (key.id.startsWith('punctuation-')) out.textContent += label(key);
          else status('这里预览 26 键的外观与按下效果；模式切换和候选输入请在设备上体验。');
        });
        button.addEventListener('dragstart', event => { dragging = key.id; event.dataTransfer.setData('text/plain', key.id); event.dataTransfer.effectAllowed = 'move'; });
        button.addEventListener('dragover', event => { if (state.tab === 'layout') event.preventDefault(); });
        button.addEventListener('drop', event => {
          event.preventDefault(); const from = locate(dragging), to = locate(key.id);
          if (state.tab !== 'layout' || !from || !to) return;
          [state.layout.rows[from.r].keys[from.k], state.layout.rows[to.r].keys[to.k]] = [to.key, from.key];
          state.selected = from.key.id; state.layoutDirty = true; dragging = ''; syncInspector(); renderPreview();
        });
        button.addEventListener('dragend', () => { dragging = ''; });
        row.append(button);
      }
      $('keyboard').append(row);
    }
  }
  function changePosition(dr, dk) {
    const pos = locate(); if (!pos) return;
    const rows = state.layout.rows, nextRow = rows[pos.r + dr];
    if (!nextRow) return;
    if (dr) {
      if (rows[pos.r].keys.length <= 1 || nextRow.keys.length >= 12) return;
      rows[pos.r].keys.splice(pos.k,1); nextRow.keys.splice(Math.min(pos.k,nextRow.keys.length),0,pos.key);
    } else {
      const next = pos.k + dk; if (next < 0 || next >= nextRow.keys.length) return;
      [nextRow.keys[pos.k],nextRow.keys[next]] = [nextRow.keys[next],nextRow.keys[pos.k]];
    }
    state.layoutDirty = true; syncInspector(); renderPreview();
  }
  async function withBusy(action) {
    if (busy) return;
    busy = true;
    const controls = [...document.querySelectorAll('button,input,select')].map(control => [control,control.disabled]);
    controls.forEach(([control]) => control.disabled = true);
    try { await action(); } catch (error) { console.error(error); status(error.message || '操作失败，请检查文件格式后重试。', true); }
    finally { busy = false; controls.forEach(([control,disabled]) => control.disabled = disabled); }
  }
  function checkFields(kind) {
    const section = kind === 'skin' ? $('skin-identity') : $('tab-layout');
    for (const input of section.querySelectorAll('input')) if (!input.checkValidity()) {
      setTab(kind === 'skin' ? 'colors' : 'layout'); input.reportValidity(); return false;
    }
    if (kind === 'skin') for (const {text} of groupFields.values()) if (!text.checkValidity()) { setTab('colors'); text.reportValidity(); return false; }
    return true;
  }
  async function exportPackage(kind) {
    if (!checkFields(kind)) return;
    const value = kind === 'skin' ? state.skin : state.layout;
    status('正在打包…');
    const blob = await EditorIO.write(kind, value, state.assets);
    const filename = `${value.id}.${kind === 'skin' ? 'sy-skin' : 'sy-layout'}`;
    const url = URL.createObjectURL(blob);
    const a = el('a', { href:url, download:filename }); document.body.append(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 60000);
    state[kind === 'skin' ? 'skinDirty' : 'layoutDirty'] = false;
    status(`已生成 ${filename}（${(blob.size/1024).toFixed(1)} KB）。请保留下载文件，再到输入法设置中导入。`);
  }
  buildColorFields();
  document.querySelectorAll('[data-tab]').forEach(button => button.addEventListener('click', () => setTab(button.dataset.tab)));
  for (const kind of ['skin','layout']) for (const field of ['name','id']) {
    $(kind+'-'+field).addEventListener('input', event => { state[kind][field] = event.target.value; state[kind+'Dirty'] = true; renderPreview(); });
  }
  $('key-weight').addEventListener('input', event => {
    const value = Number(event.target.value);
    if (!Number.isFinite(value) || value < 0.4 || value > 8) { event.target.setCustomValidity('相对宽度必须在 0.4～8 之间。'); return; }
    event.target.setCustomValidity(''); locate().key.weight = value; state.layoutDirty = true; renderPreview();
  });
  $('key-label').addEventListener('input', event => {
    const key = locate().key; if (event.target.value) key.label = event.target.value; else delete key.label;
    state.layoutDirty = true; $('selected-title').textContent = label(key); renderPreview();
  });
  $('move-left').addEventListener('click', () => changePosition(0,-1)); $('move-right').addEventListener('click', () => changePosition(0,1));
  $('move-up').addEventListener('click', () => changePosition(-1,0)); $('move-down').addEventListener('click', () => changePosition(1,0));
  $('preview-width').addEventListener('change', event => { $('device').style.width = event.target.value + 'px'; });
  $('preview-language').addEventListener('change', event => { state.language = event.target.value; syncInspector(); renderPreview(); });
  $('preview-theme').addEventListener('change', event => { state.theme = event.target.value; syncColors(); renderPreview(); });
  document.querySelectorAll('[data-preset]').forEach(button => button.addEventListener('click', () => {
    const preset = button.dataset.preset;
    state.skin.colors = copy(D.skin.colors);
    if (preset === 'pink') Object.assign(state.skin.colors, { panelBackground:'#F7E4EA',candidateBackground:'#FFF4F7',letterKeyBackground:'#FFFAFC',functionKeyBackground:'#F1CAD6',spaceKeyBackground:'#FFF8FB',primaryFunctionBackground:'#D77C9A',letterKeyPressedBackground:'#EEC5D2',functionKeyPressedBackground:'#DFADC0',primaryFunctionPressedBackground:'#B85C7A',letterKeyText:'#542536',functionKeyText:'#542536',candidateText:'#542536',candidateReading:'#936174',candidateDivider:'#E3B7C5',keyBorder:'#E3B7C5',modeKeyBackgroundEnglish:'#F1CAD6',modeKeyBackgroundChinese:'#F1CAD6',modeKeyTextEnglish:'#542536',modeKeyTextChinese:'#542536',previewBackground:'#FFFAFC',previewText:'#542536' });
    if (preset === 'dark') Object.assign(state.skin.colors, D.dark, { panelBackground:'#191724',candidateBackground:'#211E2E',letterKeyBackground:'#302C42',functionKeyBackground:'#45405B',spaceKeyBackground:'#302C42',primaryFunctionBackground:'#8B6FC7',letterKeyPressedBackground:'#514A6B',functionKeyPressedBackground:'#5E5679',primaryFunctionPressedBackground:'#6E51A8',modeKeyBackgroundEnglish:'#45405B',modeKeyBackgroundChinese:'#45405B' });
    state.skinDirty = true; syncColors(); renderPreview();
    status('配色已替换。名称和 ID 保持当前值；有图片的区域请在“图片”页调整。');
  }));
  $('import-button').addEventListener('click', () => $('import-file').click());
  $('import-file').addEventListener('change', () => withBusy(async () => {
    const file = $('import-file').files[0]; $('import-file').value = ''; if (!file) return;
    status('正在读取模板…');
    const result = await EditorIO.read(file);
    const field = result.kind === 'skin' ? 'skin' : 'layout';
    if (state[field+'Dirty'] && !confirm(`当前${field === 'skin' ? '皮肤' : '结构'}尚未导出，打开新文件会替换它。继续打开？`)) { status('已取消打开，保留当前编辑。'); return; }
    for (const blob of result.assets.values()) await checkImage(blob);
    state[field] = result.definition; state[field+'Dirty'] = false;
    if (field === 'skin') { state.assets = result.assets; rebuildUrls(); renderImages(); syncColors(); }
    else { state.selected = state.layout.rows[0].keys[0].id; syncInspector(); }
    syncIdentity(); setTab(field === 'skin' ? 'colors' : 'layout');
    const missing = field === 'skin' && Object.values(state.skin.images).some(path => !state.assets.has(path));
    status(missing ? '已打开 JSON；它引用的图片尚未导入。请到“图片”页补充后导出。' : `已打开“${result.definition.name}”，可以继续编辑。`, missing);
  }));
  $('export-skin').addEventListener('click', () => { if (checkFields('skin')) withBusy(() => exportPackage('skin')); });
  $('export-layout').addEventListener('click', () => { if (checkFields('structure')) withBusy(() => exportPackage('structure')); });
  addEventListener('beforeunload', event => { if (state.skinDirty || state.layoutDirty) { event.preventDefault(); event.returnValue = ''; } });
  syncIdentity(); syncColors(); renderImages(); syncInspector(); renderPreview();
})();
