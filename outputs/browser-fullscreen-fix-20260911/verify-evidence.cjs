const fs = require('fs');
const path = require('path');
const base = __dirname;
const read = p => JSON.parse(fs.readFileSync(p, 'utf8').replace(/^\uFEFF/, ''));
function flatten(node, out = []) {
  if (node.attributes) out.push(node.attributes);
  for (const child of node.children || []) flatten(child, out);
  return out;
}
function box(value) {
  const match = /^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$/.exec(value || '');
  return match ? match.slice(1).map(Number) : [0, 0, 0, 0];
}
const checks = [];
for (const surface of ['phone', 'computer']) {
  for (const [name, expected] of [
    ['cold-home', '小鹤双拼　小鹤音形　'], ['cold-cursor', '汉字：你'],
    ['repeat-cursor', '汉字：你'], ['refresh-cursor', '汉字：你'],
    ['warm-changed-character', '汉字：鹤'], ['cold-clipboard', '汉字：鹤']
  ]) {
    const root = path.join(base, surface, name);
    const status = read(root + '-status.json');
    const nodes = flatten(read(root + '.json'));
    const web = nodes.find(n => n.type === 'Web' && nodes.some(t =>
      t.text === 'flypy.cc' && t.hostWindowId === n.hostWindowId));
    const [x1, y1, x2, y2] = box(web?.bounds);
    const visibleResult = web && nodes.some(n => n.text === expected && n.visible === 'true' &&
      n.hostWindowId === web.hostWindowId);
    const passed = status.passed === true && !!visibleResult && x2 - x1 >= 300 && y2 - y1 >= 400 &&
      fs.statSync(root + '.png').size > 10000;
    checks.push({ surface, name, expected, passed, webBounds: web?.bounds });
  }
  for (const name of ['home-return', 'cursor-return', 'repeat-return']) {
    const status = read(path.join(base, surface, name + '-status.json'));
    checks.push({ surface, name, expected: status.expected, actual: status.actual, passed: status.passed === true });
  }
}
const result = { passed: checks.filter(c => c.passed).length,
  failed: checks.filter(c => !c.passed).length, checks };
fs.writeFileSync(path.join(base, 'device-checks.json'), JSON.stringify(result, null, 2));
console.log(JSON.stringify(result, null, 2));
if (result.failed) process.exitCode = 1;
