// Runs the actual repository with isolated preferences and a read-only BASIC mount.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('C:/Program Files/Huawei/DevEco Studio/tools/hvigor/hvigor/node_modules/typescript');
const root = path.resolve(__dirname, '..');
const dir = fs.mkdtempSync(path.join(root, 'output/settings-shared-test-'));
const prefs = new Map();
let proxyRecord, failRename = false;
function runtime(basic = false) {
  const cache = new Map(), writes = [], timers = new Map();
  let timerId = 0;
  const disk = p => path.join(dir, path.basename(p));
  const writable = p => { writes.push(p); assert.equal(basic, false, 'BASIC must not write the shared directory'); return disk(p); };
  const api = {
    OpenMode: { CREATE: 64, WRITE_ONLY: 1, TRUNC: 512 },
    accessSync: p => fs.existsSync(disk(p)), statSync: p => fs.statSync(disk(p)),
    readTextSync: p => fs.readFileSync(disk(p), 'utf8'),
    openSync: p => ({ fd: fs.openSync(writable(p), 'w') }),
    writeSync: (fd, data) => fs.writeSync(fd, data), fsyncSync: fd => fs.fsyncSync(fd),
    closeSync: file => fs.closeSync(file.fd), unlinkSync: p => fs.unlinkSync(writable(p)),
    renameSync: (a, b) => { if (failRename) throw new Error('simulated atomic replace failure'); fs.renameSync(writable(a), writable(b)); }
  };
  function load(file) {
    if (cache.has(file)) return cache.get(file);
    const exports = {}; cache.set(file, exports);
    const output = ts.transpileModule(fs.readFileSync(file, 'utf8'), { compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS } }).outputText;
    vm.runInNewContext(output, { exports, console, $r: key => key,
      setInterval: fn => { timers.set(++timerId, fn); return timerId; },
      clearInterval: id => timers.delete(id), require(name) {
      if (name === '@ohos.file.fs') return { default: api };
      if (name === '@kit.ArkData') return {
        preferences: {
          removePreferencesFromCacheSync() {},
          async getPreferences(context) {
            const key = context.processName;
            if (!prefs.has(key)) prefs.set(key, new Map());
            const values = prefs.get(key);
            return { get: async (k, fallback) => values.get(k) ?? fallback, put: async (k, v) => values.set(k, v), delete: async k => values.delete(k), flush: async () => {} };
          }
        },
        dataShare: { DataProxyType: { SHARED_CONFIG: 1 }, DataProxyErrorCode: { SUCCESS: 0 },
          async createDataProxyHandle() {
            if (basic) throw new Error('DataProxy unavailable in BASIC');
            return { get: async () => proxyRecord ? [{ result: 0, value: proxyRecord }] : [],
              publish: async records => { proxyRecord = records[0].value; return [{ result: 0 }]; } };
          }
        }
      };
      if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, debug() {}, error() {} } };
      if (name === '@kit.BasicServicesKit') return { commonEventManager: new Proxy({}, { get() { throw new Error('BASIC must not use common events'); } }) };
      if (name.startsWith('.')) return load(path.resolve(path.dirname(file), name + '.ets'));
      throw new Error('Unexpected native dependency: ' + name);
    } }, { filename: file });
    return exports;
  }
  const Repository = load(path.join(root, 'entry/src/main/ets/infrastructure/storage/SettingsRepository.ets')).SettingsRepository;
  const SyncBus = load(path.join(root, 'entry/src/main/ets/infrastructure/storage/SettingsSyncBus.ets')).SettingsSyncBus;
  return { repository: new Repository(), bus: new SyncBus(), timers, writes, context: { processName: basic ? 'com.corrosion.shuangyuime:inputMethod' : 'com.corrosion.shuangyuime', filesDir: '/private/files', cacheDir: '/private/cache', getGroupDir: async () => basic ? '/ime-group' : '/app-group' } };
}
(async () => {
  const app = runtime();
  const settings = await app.repository.load(app.context);
  settings.keyboardSkinId = 'test.shared.skin'; settings.keyboardStructureId = 'test.shared.layout'; settings.smartPeriodTimeoutMs = 500;
  assert.equal(await app.repository.save(settings), true);
  const basic = runtime(true);
  let actual = await basic.repository.load(basic.context);
  assert.equal(actual.keyboardSkinId, settings.keyboardSkinId); assert.equal(actual.keyboardStructureId, settings.keyboardStructureId);
  assert.equal(actual.smartPeriodTimeoutMs, 500); assert.equal(basic.writes.length, 0);
  console.log('PASS BASIC reads main-app settings with DataProxy denied and no shared writes');
  settings.keyboardSkinId = 'test.updated.skin'; assert.equal(await app.repository.save(settings), true);
  actual = await basic.repository.load(basic.context); assert.equal(actual.keyboardSkinId, settings.keyboardSkinId);
  const restarted = runtime(true); actual = await restarted.repository.load(restarted.context);
  assert.equal(actual.keyboardSkinId, settings.keyboardSkinId); assert.equal(restarted.writes.length, 0);
  console.log('PASS changed settings and process restart read the latest snapshot');
  const events = [];
  assert.equal(await basic.bus.subscribe(raw => events.push(raw), basic.context), true);
  for (const tick of basic.timers.values()) { tick(); tick(); }
  assert.equal(events.length, 1);
  settings.keyboardSkinId = 'test.live.skin'; assert.equal(await app.repository.save(settings), true);
  for (const tick of basic.timers.values()) tick();
  assert.equal(events.length, 2); assert.equal(events[1].keyboardSkinId, settings.keyboardSkinId);
  basic.bus.unsubscribe(); assert.equal(basic.timers.size, 0); assert.equal(basic.writes.length, 0);
  const pending = basic.bus.subscribe(() => { throw new Error('stale subscription'); }, basic.context);
  basic.bus.unsubscribe(); assert.equal(await pending, false); assert.equal(basic.timers.size, 0);
  console.log('PASS BASIC live sync uses no common events and stops pending subscriptions on destruction');
  const before = fs.readFileSync(path.join(dir, 'ime-settings.json'), 'utf8');
  failRename = true; settings.keyboardSkinId = 'test.rejected.skin'; assert.equal(await app.repository.save(settings), false); failRename = false;
  assert.equal(fs.readFileSync(path.join(dir, 'ime-settings.json'), 'utf8'), before);
  assert.equal(fs.existsSync(path.join(dir, 'ime-settings.json.pending')), false);
  console.log('PASS failed atomic replace retains the previous snapshot and rejects save');
  for (const invalid of ['{broken', '{}', 'x'.repeat(65537)]) {
    fs.writeFileSync(path.join(dir, 'ime-settings.json'), invalid);
    const consumer = runtime(true); actual = await consumer.repository.load(consumer.context);
    assert.equal(actual.keyboardSkinId, 'builtin.follow-system'); assert.equal(consumer.writes.length, 0);
  }
  console.log('PASS corrupt, empty and oversized snapshots are rejected without shared writes');
})().catch(e => { console.error(e); process.exitCode = 1; }).finally(() => fs.rmSync(dir, { recursive: true, force: true }));
