const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('C:/Program Files/Huawei/DevEco Studio/tools/hvigor/hvigor/node_modules/typescript');
const root = path.resolve(__dirname, '..');
const tests = [];
const kit = { inputMethodEngine: { Direction: { CURSOR_LEFT: 1 } } };
function load(file, imports) {
  const source = fs.readFileSync(path.join(root, file), 'utf8');
  const compiled = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
  }).outputText;
  const exports = {};
  vm.runInNewContext(compiled, {
    exports, setTimeout, Date,
    require(name) {
      if (!(name in imports)) throw new Error(`Unexpected import: ${name}`);
      return imports[name];
    }
  }, { filename: file });
  return exports;
}
const positioner = load('entry/src/main/ets/infrastructure/ime/PairCursorPositioner.ets', { '@kit.IMEKit': kit });
load('entry/src/test/PairCursorPositioner.test.ets', {
  '@kit.IMEKit': kit,
  '../main/ets/infrastructure/ime/PairCursorPositioner': positioner,
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
(async () => {
  for (const test of tests) {
    await test.fn();
    console.log(`PASS ${test.name}`);
  }
  console.log(`${tests.length}/${tests.length} pair cursor regression tests passed (host runner, mocked IME API).`);
})().catch(err => { console.error(err); process.exitCode = 1; });
