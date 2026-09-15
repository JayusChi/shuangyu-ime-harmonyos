// Host adapter regression; the native bridge and OS logger are mocked.
// Run: node scripts/test-reverse-split-gateway.cjs
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const devEcoRoot = process.env.DEVECO_STUDIO_ROOT || 'C:/Program Files/Huawei/DevEco Studio';
const ts = require(path.join(devEcoRoot, 'tools/hvigor/hvigor/node_modules/typescript'));
const root = path.resolve(__dirname, '..');

function load(file, imports = {}) {
  const source = fs.readFileSync(path.join(root, file), 'utf8');
  const compiled = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
  }).outputText;
  const exports = {};
  vm.runInNewContext(compiled, {
    exports,
    require(name) {
      assert.ok(name in imports, `Unexpected import: ${name}`);
      return imports[name];
    }
  }, { filename: file });
  return exports;
}

function composition(overrides = {}) {
  return {
    success: true, errorCode: 0, errorMessage: '', rawInput: '', preeditText: '',
    parsedSyllables: [], pendingCode: '', displaySegments: [], segmentBoundaries: [],
    currentPinyin: '', pinyinCombinations: [], parserState: 'empty', candidates: [],
    highlightedIndex: -1, hasNextPage: false, hasPreviousPage: false, candidatePage: 0,
    commitText: '', action: null, compositionFinished: false, ...overrides
  };
}

let response = composition();
let sentPolicy;
const bridge = {
  setCodeTableCommitPolicy(_handle, json) { sentPolicy = JSON.parse(json); return response; },
  selectCandidate() { return response; },
  processKey() { return response; }
};
const { NativeEngineGateway } = load('entry/src/main/ets/infrastructure/native/NativeEngineGateway.ets', {
  '../../domain/direct/ExternalDirectTarget': load('entry/src/main/ets/domain/direct/ExternalDirectTarget.ets'),
  'libime_bridge.so': { default: bridge },
  '../../common/error/ImeError': load('entry/src/main/ets/common/error/ImeError.ets'),
  '../../common/logging/Logger': { Logger: class { info() {} error() {} } }
});
const gateway = new NativeEngineGateway();
assert.equal(gateway.setCodeTableCommitPolicy(1, true, 4, true).success, true);
assert.deepEqual(sentPolicy, { autoCommitLength: 4, emptyClearLength: 4, reverseSplitEnabled: true });
assert.equal(gateway.setCodeTableCommitPolicy(1, false, 12, false).success, true);
assert.deepEqual(sentPolicy, { autoCommitLength: 64, emptyClearLength: 12, reverseSplitEnabled: false });

for (const target of ['traditional', 'split']) {
  response = composition({
    action: { type: 'DIRECT_CONTROL', formatId: 'settings.split-mode', text: target, cursorOffsetUtf16: 0 },
    compositionFinished: true
  });
  const selected = gateway.selectCandidate(1, target === 'traditional' ? 0 : 1);
  assert.equal(selected.success, true);
  assert.equal(selected.action.text, target);
  assert.equal(selected.commitText, '');
}
response = composition({
  action: { type: 'DIRECT_CONTROL', formatId: 'settings.split-mode', text: 'unknown', cursorOffsetUtf16: 0 }
});
assert.equal(gateway.selectCandidate(1, 0).success, false);

response = composition({
  rawInput: 'hfkn', preeditText: 'hfkn', displaySegments: ['hf', 'kn'], parserState: 'complete',
  candidates: [
    { id: 'split:first', text: '很可能', displayText: '很可能', reading: 'hfkn', source: 'reverse-split', consumedRawLen: 4 },
    { id: 'split:second', text: '很困难', displayText: '困难', reading: 'hfkn', source: 'reverse-split', consumedRawLen: 4 }
  ]
});
const result = gateway.processKey(1, 'n');
assert.equal(result.success, true);
const ui = load('entry/src/main/ets/domain/candidate/CandidateUiPolicy.ets', {
  '../settings/ImeSettings': { XIAOHE_YINXING_SCHEME_ID: 'xiaohe-yinxing' },
  './CandidateExpansionPolicy': { MIN_CANDIDATES_FOR_EXPANSION: 4 }
});
const visible = ui.resolveVisibleCandidates(ui.CandidateUiMode.PRECISE_MATCH, result.rawInput, result.candidates);
assert.equal(visible.length, 2);
assert.equal(visible[1].displayText, '困难');
assert.equal(visible[1].text, '很困难');
assert.equal(visible[1].consumedRawLen, 4);
response = composition({ rawInput: 'n', preeditText: 'n', parserState: 'incomplete', commitText: '很可能' });
const fifth = gateway.processKey(1, 'n');
assert.equal(fifth.success, true);
assert.equal(fifth.rawInput, 'n');
assert.equal(fifth.commitText, '很可能');
console.log('PASS: policy payload, both oit actions, invalid target rejection, candidate display/commit, fifth-key tail (mocked native bridge).');

const newDirectCodes = ['ohx', 'ojg', 'ohz', 'ofz', 'ofa', 'ovd', 'oyx'];
const directData = JSON.parse(fs.readFileSync(path.join(root,
  'engine-rust/crates/code-table-runtime/data/production-direct-actions.json'), 'utf8'));
const displayActions = directData.records.filter(record => newDirectCodes.includes(record.code));
assert.equal(displayActions.length, 18);
for (const record of displayActions) {
  response = composition({
    action: { type: 'DIRECT_CONTROL', formatId: record.action, text: record.target, cursorOffsetUtf16: 0 },
    compositionFinished: true
  });
  const selected = gateway.selectCandidate(1, 0);
  assert.equal(selected.success, true, `${record.code}: ${record.target}`);
  assert.equal(selected.action.formatId, record.action);
  assert.equal(selected.action.text, record.target);
  assert.equal(selected.commitText, '');
  response.action.text = 'unapproved';
  assert.equal(gateway.selectCandidate(1, 0).success, false, record.code);
}
console.log('PASS: all 18 display/feedback direct actions cross the native gateway; unapproved targets are rejected.');

for (const [action, target] of [
  ['url.open', 'https://example.com/Help?q=a,b#Part'],
  ['directory.open', 'file://docs/storage/Users/currentUser/Documents'],
  ['settings.keyboard-profile', 'quanpin-26']
]) {
  response = composition({ action: { type: 'DIRECT_CONTROL', formatId: action, text: target, cursorOffsetUtf16: 0 } });
  const result = gateway.selectCandidate(1, 0);
  assert.equal(result.success, true);
  assert.equal(result.action.text, target);
  assert.equal(result.commitText, '');
}
for (const [action, target] of [['url.open', 'javascript:alert(1)'], ['directory.open', 'file://private.app/path'], ['settings.keyboard-profile', 'pinyin-9']]) {
  response = composition({ action: { type: 'DIRECT_CONTROL', formatId: action, text: target, cursorOffsetUtf16: 0 } });
  assert.equal(gateway.selectCandidate(1, 0).success, false);
}
console.log('External shortcuts and all three ofa profiles pass gateway validation.');
