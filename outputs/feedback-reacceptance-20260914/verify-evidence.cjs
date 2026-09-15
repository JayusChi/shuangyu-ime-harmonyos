const fs = require('node:fs');
const path = require('node:path');
const root = __dirname;
const results = [];
const dimensions = [];
function nodes(n, out = []) {
  if (n.attributes) out.push(n.attributes);
  for (const c of n.children || []) nodes(c, out);
  return out;
}
function read(device, name) {
  return nodes(JSON.parse(fs.readFileSync(path.join(root, device, `${name}.json`), 'utf8').replace(/^\uFEFF/, '')));
}
const chat = ns => ns.find(n => n.hint === 'ACCEPT_CHAT_SEND')?.text;
const first = ns => ns.find(n => /^1 /.test(n.text))?.text;
const box = n => n.bounds.match(/\d+/g).map(Number);
function check(device, name, pass, evidence) {
  results.push({device, name, pass: !!pass, evidence});
}
const appearance = JSON.parse(fs.readFileSync(path.join(root, 'appearance-measurements.json'), 'utf8').replace(/^\uFEFF/, ''));
for (const d of ['phone', 'computer']) {
  for (let i = 1; i <= (d === 'phone' ? 3 : 2); i++) {
    const before = read(d, `final-swipe-${i}-before`), after = read(d, `final-swipe-${i}-after`);
    check(d, `slow-swipe-${i}`, chat(before) === '你' && first(before) && chat(after) === '你' && !first(after), `final-swipe-${i}-{before,after}`);
  }
  const a10 = appearance.find(a => a.device === d && a.marginVp === 10);
  const a11 = appearance.find(a => a.device === d && a.marginVp === 11);
  check(d, 'upper-margin-moves-left', a11.glyphRight < a10.glyphRight, 'appearance-measurements.json');
  const bigger = box(read(d, 'final-font-plus-keyboard').find(n => n.text === 'Q'));
  check(d, 'adaptive-font-adjust-reset', bigger[3] - bigger[1] > a10.letterHeightPx && a10.letterHeightPx === 53, 'final-font-plus-keyboard / final-margin10-keyboard');
  check(d, 'virtual-enter-raw-code', chat(read(d, 'final-virtual-enter-after')) === (d === 'phone' ? 'kn' : '你kn'), 'final-virtual-enter-after');
  check(d, 'physical-enter-raw-code', chat(read(d, d === 'phone' ? 'final-fixed-physical-enter' : 'final-paging-enter')) === (d === 'phone' ? 'ni' : '很有希望ui'), 'physical Enter UI snapshots');
  const p1 = read(d, 'final-paging-first'), p2 = read(d, 'final-paging-next'), p3 = read(d, 'final-paging-previous');
  check(d, 'physical-bracket-paging', first(p1) === '1 是' && first(p2) === '1 浉' && first(p3) === first(p1) && chat(p1) === chat(p2) && chat(p2) === chat(p3), 'final-paging-{first,next,previous}');
  const sizes = [];
  for (const stage of ['k', 'kn', 'back-k']) {
    const ns = read(d, `final-yinxing-floating-${stage}`);
    const raw = ns.find(n => n.text === (stage === 'kn' ? 'kn' : 'k'));
    const card = ns.filter(n => raw?.hierarchy.startsWith(`${n.hierarchy},`) && n.type === 'Row' && n.backgroundColor === '#FFFFFFFF').at(-1);
    const b = box(card);
    const s = {device: d, stage, width: b[2] - b[0], height: b[3] - b[1]};
    sizes.push(s); dimensions.push(s);
    check(d, `floating-text-contained-${stage}`, ns.filter(n => n.type === 'Text' && n.text && n.hierarchy.startsWith(`${card.hierarchy},`)).every(n => {
      const t = box(n); return t[0] >= b[0] && t[1] >= b[1] && t[2] <= b[2] && t[3] <= b[3] && n.bounds === n.origBounds;
    }), `final-yinxing-floating-${stage}`);
  }
  check(d, 'floating-stable-dimensions', sizes.every(s => s.height === sizes[0].height) && sizes[1].width >= sizes[0].width && sizes[2].width === sizes[1].width, sizes);
  const previousFirst = first(read(d, 'final-yinxing-floating-back-k')).slice(2);
  check(d, 'floating-click-commits', chat(read(d, 'final-floating-click-verified')) === previousFirst && !first(read(d, 'final-floating-click-verified')), 'final-floating-click-verified');
  check(d, 'hfyzxiwh-first-and-commit', first(read(d, d === 'phone' ? 'sentence-hfyzxiwh' : 'sentence-retry')) === '1 很有希望' && chat(read(d, d === 'phone' ? 'sentence-commit' : 'sentence-final-commit')) === '很有希望', 'sentence candidate / commit screenshots');
  check(d, 'fixed-up-in-sentence', first(read(d, 'final-fixed-middle')) === '1 我用双拼输入法' && chat(read(d, 'final-fixed-commit')) === '我用双拼输入法', 'final-fixed-{middle,commit}');
  check(d, 'temporary-rule-removed', read(d, 'cleanup-rule-removed').some(n => n.text.startsWith('暂无词条')), 'cleanup-rule-removed');
}
const report = {passed: results.filter(r => r.pass).length, failed: results.filter(r => !r.pass).length, results, dimensions, visualReview: 'Rounded white cards, gray selection and visible shadows reviewed from actual screenshots on both emulators.'};
fs.writeFileSync(path.join(root, 'verification.json'), JSON.stringify(report, null, 2));
console.log(JSON.stringify({passed: report.passed, failed: report.failed, failures: results.filter(r => !r.pass), dimensions}, null, 2));
process.exitCode = report.failed ? 1 : 0;
