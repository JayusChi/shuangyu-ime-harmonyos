const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const flatten = node => [node, ...(node.children || []).flatMap(flatten)];
const read = (device, name) => JSON.parse(fs.readFileSync(path.join(__dirname, device, `${name}.json`), 'utf8').replace(/^\uFEFF/, ''));
const selected = tree => flatten(tree)
  .filter(node => (node.children || []).some(child => child.attributes?.text === '✓'))
  .map(node => flatten(node).map(child => child.attributes?.text).filter(Boolean));
for (const device of ['phone', 'computer']) {
  for (const kind of ['skin', 'layout']) {
    const original = selected(read(device, `original-${kind}`));
    const restored = selected(read(device, `${kind}-restored`));
    assert.ok(original.length, `${device} ${kind} selected row exists`);
    assert.deepEqual(restored, original, `${device} ${kind} original selection restored`);
    assert.ok(!flatten(read(device, `${kind}-restored`)).some(node => node.attributes?.text === 'roundtrippc'));
    console.log(`PASS ${device} ${kind} restored: ${JSON.stringify(restored)}`);
  }
  const actual = flatten(read(device, 'actual-keyboard')).map(node => node.attributes || {});
  assert.ok(actual.some(node => node.backgroundColor === '#FF123456'));
  assert.ok(actual.some(node => node.text === 'qa space'));
  const left = letter => Number(actual.find(node => node.text === letter).bounds.match(/\[(\d+),/)[1]);
  assert.ok(left('W') < left('Q'));
  const typed = flatten(read(device, 'typing-committed')).map(node => node.attributes || {});
  assert.ok(typed.some(node => node.text === '你' && node.hint === 'ACCEPT_CHAT_SEND'));
  console.log(`PASS ${device}: actual color, moved keys, custom label and committed input`);
}
