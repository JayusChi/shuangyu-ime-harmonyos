// Host regressions for editor cursor compatibility; OS IME calls are mocked.
// Run with the DevEco bundled node or node scripts/test-pair-navigation.cjs.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const devEcoRoot = process.env.DEVECO_STUDIO_ROOT || 'C:/Program Files/Huawei/DevEco Studio';
const ts = require(path.join(devEcoRoot, 'tools/hvigor/hvigor/node_modules/typescript'));
const root = path.resolve(__dirname, '..');
const tests = [];
const kit = { inputMethodEngine: { Direction: { CURSOR_LEFT: 1, CURSOR_RIGHT: 2 } } };
function load(file, imports) {
  const compiled = ts.transpileModule(fs.readFileSync(path.join(root, file), 'utf8'), {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
  }).outputText;
  const exports = {};
  vm.runInNewContext(compiled, {
    exports, setTimeout, Date,
    require(name) {
      assert.ok(name in imports, `Unexpected import: ${name}`);
      return imports[name];
    }
  }, { filename: file });
  return exports;
}
const positioner = load('entry/src/main/ets/infrastructure/ime/PairCursorPositioner.ets', { '@kit.IMEKit': kit });
const lineEnd = load('entry/src/main/ets/infrastructure/ime/LineEndCursorMover.ets', { './PairCursorPositioner': positioner });
load('entry/src/test/PairCursorPositioner.test.ets', {
  '@kit.IMEKit': kit,
  '../main/ets/infrastructure/ime/PairCursorPositioner': positioner,
  '../main/ets/infrastructure/ime/LineEndCursorMover': lineEnd,
  '@ohos/hypium': {
    describe: (_name, fn) => fn(),
    it: (name, _flags, fn) => tests.push({ name, fn }),
    expect: actual => ({
      assertTrue: () => assert.equal(actual, true),
      assertFalse: () => assert.equal(actual, false),
      assertEqual: expected => assert.equal(actual, expected)
    })
  }
}).default();
const { PairInsertionService, PairInsertResult } = load('entry/src/main/ets/infrastructure/ime/PairInsertionService.ets', {
  '@kit.IMEKit': kit,
  './PairCursorPositioner': positioner,
  '../../common/logging/Logger': { Logger: class { info() {} warn() {} } },
  './ImePreviewService': { HarmonyCompositionInputClient: class {} }
});
function editor() {
  return {
    text: '前文后文', cursor: 2, ignoreMove: false,
    async getTextIndexAtCursor() { return this.cursor; },
    async getForward(n) { return this.text.substring(Math.max(0, this.cursor - n), this.cursor); },
    async getBackward(n) { return this.text.substring(this.cursor, this.cursor + n); },
    async selectByRange() {}, // Reproduces a rich editor silently ignoring selection.
    async moveCursor(direction) {
      if (!this.ignoreMove) this.cursor += direction === kit.inputMethodEngine.Direction.CURSOR_LEFT ? -1 : 1;
    }
  };
}
function manager(client) {
  return { async commit(_adapter, text) {
    client.text = client.text.slice(0, client.cursor) + text + client.text.slice(client.cursor);
    client.cursor += text.length;
    return true;
  } };
}
tests.push({ name: 'production pair service inserts and jumps nested pairs with ignored selections', async fn() {
  const service = new PairInsertionService();
  const client = editor();
  const commit = manager(client);
  assert.equal(await service.insert(client, commit, '【】', 1, 7, () => true), PairInsertResult.SUCCESS);
  assert.equal(await service.insert(client, commit, '（）', 1, 7, () => true), PairInsertResult.SUCCESS);
  assert.equal(client.text, '前文【（）】后文');
  assert.equal(client.cursor, 4);
  assert.equal(await service.jumpOut(client, 7, () => true), true);
  assert.equal(client.cursor, 5);
  assert.equal(service.hasPending(7), true);
  assert.equal(await service.jumpOut(client, 7, () => true), true);
  assert.equal(client.cursor, 6);
  assert.equal(service.hasPending(7), false);
  assert.equal(client.text, '前文【（）】后文');
} });
tests.push({ name: 'production pair service rejects ignored jumps and stale generations', async fn() {
  for (const stale of [false, true]) {
    const service = new PairInsertionService();
    const client = editor();
    assert.equal(await service.insert(client, manager(client), '【】', 1, 7, () => true), PairInsertResult.SUCCESS);
    client.ignoreMove = true;
    assert.equal(await service.jumpOut(client, stale ? 8 : 7, () => true), false);
    assert.equal(client.cursor, 3);
    assert.equal(client.text, '前文【】后文');
    assert.equal(service.hasPending(7), false);
  }
} });
(async () => {
  for (const test of tests) {
    await test.fn();
    console.log(`PASS ${test.name}`);
  }
  console.log(`${tests.length}/${tests.length} cursor and pair navigation regressions passed (mocked IME APIs).`);
})().catch(err => { console.error(err); process.exitCode = 1; });
