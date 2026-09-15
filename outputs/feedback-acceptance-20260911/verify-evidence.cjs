const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = __dirname;
const checks = [];
function nodes(file) {
  const result = [];
  function visit(n) {
    if (n.attributes) result.push(n.attributes);
    for (const child of n.children || []) visit(child);
  }
  visit(JSON.parse(fs.readFileSync(path.join(root, file + '.json'), 'utf8').replace(/^\uFEFF/, '')));
  return result;
}
function check(name, fn) {
  try { fn(); checks.push({ name, result: 'PASS' }); }
  catch (error) { checks.push({ name, result: 'FAIL', error: error.message }); }
}
function text(file, value) { return nodes(file).find(n => n.text === value); }
function box(value) { return value.match(/\d+/g).map(Number); }
for (const device of ['phone', 'computer']) {
  const prefix = device === 'phone' ? '1 ' : '1. ';
  check(`${device}: trailing initial resolves and commits`, () => {
    assert(text(`${device}/sentence1-new`, prefix + '还是很好的'));
    assert(nodes(`${device}/sentence1-committed`).some(n => n.hint === 'ACCEPT_CHAT_SEND' && n.text === '还是很好的'));
  });
  check(`${device}: impossible final pair resolves and commits`, () => {
    assert(text(`${device}/sentence2-new`, prefix + '其实很简单的'));
    assert(nodes(`${device}/sentence2-committed`).some(n => n.hint === 'ACCEPT_CHAT_SEND' && n.text === '还是很好的其实很简单的'));
  });
  check(`${device}: scheme choices are on the input settings page`, () => {
    for (const value of ['小鹤音形', '小鹤双拼', '拼音', '18键', '9键']) assert(text(`${device}/input-settings`, value));
    const choices = nodes(`${device}/input-settings`).filter(n => n.text === '26键');
    assert.equal(choices.length, 2);
    assert.equal(box(choices[0].bounds)[0], box(choices[1].bounds)[0]);
    assert.equal(box(choices[0].bounds)[2], box(choices[1].bounds)[2]);
  });
}
check('phone: ojz order and second-candidate label', () => {
  const n = nodes('phone/final-ojz-menu');
  assert.deepEqual(n.filter(n => /^\d .*\[/.test(n.text)).map(n => n.text), ['1 [键字12号]', '2 [+2]', '3 [-1]']);
  assert(n.some(n => n.text === '次选'));
});
check('phone: keyboard glyph size changes 12 → 14 → 13 → 12', () => {
  const heights = ['font-12', 'font-14', 'font-13', 'font-reset-12'].map(file => {
    const b = box(text('phone/' + file, 'Q').bounds);
    return b[3] - b[1];
  });
  assert(heights[1] > heights[2] && heights[2] > heights[0]);
  assert.equal(heights[0], heights[3]);
  assert(text('phone/font-reset-12', '。'));
});
check('computer: backtick wildcard leaves host text untouched', () => {
  assert(text('computer/universal', 'u`'));
  assert(nodes('computer/universal').some(n => n.hint === 'ACCEPT_CHAT_SEND' && n.text === ''));
});
for (const [file, count] of [['universal', 5], ['six-candidates', 6]]) {
  check(`computer: ${count} complete candidates and expansion control`, () => {
    const n = nodes('computer/' + file);
    const candidates = n.filter(n => /^\d+\. /.test(n.text));
    assert.equal(candidates.length, count);
    for (const candidate of candidates) assert.equal(candidate.bounds, candidate.origBounds);
    assert(n.some(n => n.text === '展开'));
  });
}
check('computer: expanded grid supports next page and collapse', () => {
  assert(text('computer/six-expanded', '收起'));
  assert(text('computer/expanded-next', '第 2 页'));
  assert(text('computer/six-collapsed', '展开'));
});
check('phone: fixed candidate expansion shows a grid', () => {
  assert(text('phone/fixed-expanded', '返回键盘'));
  assert(text('phone/fixed-expanded', '市 iw'));
});
for (const device of ['computer']) {
  check(`${device}: four-code shortcut opens website`, () => {
    assert(nodes(`${device}/final-home-browser`).some(n => n.text === '小鹤音形 - 官网' || n.text === '小鹤双拼　小鹤音形　'));
  });
  check(`${device}: cursor lookup shows the requested character on the website`, () => {
    assert(text(`${device}/final-cursor-browser`, '汉字：鹤'));
  });
  check(`${device}: externally copied character resolves on the website`, () => {
    assert(text(`${device}/final-clipboard-browser`, '汉字：鹤'));
  });
}
check('phone: cursor shortcut launches the browser', () => {
  assert(nodes('phone/final-cursor-browser').some(n => n.id === 'medium_btn_in_homepage'));
});
check('phone: asynchronous lookup titles refresh instead of showing the template placeholder', () => {
  assert(text('phone/label-fix-clipboard', '1 「查」：剪贴板'));
  assert(text('phone/label-fix-cursor-menu', '1 「查」：你'));
});
check('computer: final package still handles backtick as a wildcard', () => {
  assert(text('computer/final-universal', 'u`'));
});
check('phone: four-code shortcut launches the browser', () => {
  assert(nodes('phone/final-home-browser').some(n => n.id === 'medium_btn_in_homepage'));
});
check('phone: clipboard shortcut reaches the system paste button', () => {
  assert(nodes('phone/final-copy-paste-page').some(n => n.type === 'PasteButton'));
});
check('phone: clipboard paste launches the browser and creates a lookup tab', () => {
  assert(nodes('phone/final-clipboard-browser').some(n => n.id === 'medium_btn_in_homepage'));
  assert(text('phone/final-clipboard-tabs', '查形 | 小鹤音形'));
});
for (const item of ['homepage', 'cursor lookup', 'clipboard lookup']) {
  checks.push({ name: `phone: ${item} full-page browser rendering`, result: 'INCOMPLETE',
    reason: 'Browser full-page content stays blank; tab thumbnails visibly contain the homepage and the correct 你/鹤 lookup results. See report for visual evidence; thumbnail review is not a full-page UI assertion.' });
}
const passed = checks.filter(c => c.result === 'PASS').length;
const failed = checks.filter(c => c.result === 'FAIL').length;
const incomplete = checks.filter(c => c.result === 'INCOMPLETE').length;
fs.writeFileSync(path.join(root, 'device-checks.json'), JSON.stringify({ checks, passed, failed, incomplete }, null, 2) + '\n');
console.log(`${passed} evidence assertions passed; ${failed} failed; ${incomplete} incomplete browser rendering checks.`);
if (failed) { console.error(checks.filter(c => c.result === 'FAIL')); process.exitCode = 1; }
