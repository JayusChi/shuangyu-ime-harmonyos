// Host contract tests: isolated App/IME filesystems, mocked Harmony APIs.
// These verify the repository, not a device's provisioning or sandbox mount.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { createRequire } = require('node:module');
const sdkRequire = createRequire(path.join(process.env.DEVECO_STUDIO_ROOT ||
  'C:/Program Files/Huawei/DevEco Studio', 'tools/hvigor/hvigor/package.json'));
const ts = sdkRequire('typescript');
const zip = sdkRequire('@zip.js/zip.js');
const root = path.resolve(__dirname, '..');
const temp = fs.mkdtempSync(path.join(root, 'output/customization-sharing-test-'));
const { validate } = require('./configure-keyboard-customization-sharing.cjs');
let passed = 0;

function runtime(name, options = {}) {
  const base = path.join(temp, name);
  fs.mkdirSync(base, { recursive: true });
  const writes = [], reads = [], cache = new Map();
  function disk(input) {
    const relative = input.replace(/^\/(group-app|group-ime)(?=\/|$)/, '/shared');
    const target = path.resolve(base, '.' + relative);
    assert.ok(target.startsWith(base + path.sep), `Outside test sandbox: ${input}`);
    return target;
  }
  function write(input) {
    writes.push(input);
    if (options.readOnly || (options.failWrite && options.failWrite(input))) throw new Error('simulated write denied');
    return disk(input);
  }
  const api = {
    OpenMode: { READ_ONLY: 0 },
    accessSync: input => fs.existsSync(disk(input)),
    readTextSync: input => { reads.push(input); return fs.readFileSync(disk(input), 'utf8'); },
    listFileSync: input => fs.readdirSync(disk(input)),
    statSync: input => fs.statSync(disk(input)),
    mkdirSync: input => fs.mkdirSync(write(input), { recursive: true }),
    renameSync: (from, to) => fs.renameSync(write(from), write(to)),
    copyFileSync: (from, to) => {
      const target = write(to);
      if (typeof from === 'number') fs.writeFileSync(target, fs.readFileSync(from));
      else fs.copyFileSync(disk(from), target);
    },
    unlinkSync: input => fs.unlinkSync(write(input)),
    rmdirSync: input => fs.rmdirSync(write(input)),
    openSync: input => ({ fd: fs.openSync(disk(input), 'r') }),
    closeSync: file => fs.closeSync(file.fd)
  };
  async function archive(input, callback) {
    const reader = new zip.ZipReader(new zip.Uint8ArrayReader(new Uint8Array(fs.readFileSync(disk(input)))));
    try { return await callback(await reader.getEntries()); }
    catch (error) { console.error('Archive test backend:', error); throw error; }
    finally { await reader.close(); }
  }
  const zlib = {
    getOriginalSize: input => archive(input, async entries => entries.reduce((total, entry) => total + entry.uncompressedSize, 0)),
    decompressFile: (input, output) => archive(input, async entries => {
      for (const entry of entries) {
        const target = write(output + '/' + entry.filename);
        if (entry.directory) fs.mkdirSync(target, { recursive: true });
        else {
          fs.mkdirSync(path.dirname(target), { recursive: true });
          fs.writeFileSync(target, await entry.getData(new zip.Uint8ArrayWriter()));
        }
      }
    })
  };
  function load(file) {
    if (cache.has(file)) return cache.get(file);
    const exports = {}; cache.set(file, exports);
    const source = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
      compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
    }).outputText;
    vm.runInNewContext(source, { exports, console, $r: key => key, require(name) {
      if (name.endsWith('/KeyboardCustomizationStorageConfig')) return {
        KEYBOARD_CUSTOMIZATION_DATA_GROUP_ID: options.unconfigured ? '' : 'unit-test-group'
      };
      if (name === '@ohos.file.fs') return { default: api };
      if (name === '@ohos.zlib') return { default: zlib };
      if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, debug() {}, error() {} } };
      if (name.startsWith('.')) return load(path.resolve(path.dirname(file), name + '.ets'));
      throw new Error('Unexpected native API: ' + name);
    } }, { filename: file });
    return exports;
  }
  const Repository = load(path.join(root, 'entry/src/main/ets/infrastructure/customization/KeyboardCustomizationRepository.ets')).KeyboardCustomizationRepository;
  const app = { filesDir: '/app/files', cacheDir: '/app/cache', getGroupDir: async () => {
    if (options.failGroup) throw new Error('not provisioned');
    return '/group-app';
  } };
  const ime = { filesDir: '/ime/files', cacheDir: '/ime/cache', getGroupDir: async () => '/group-ime' };
  function put(input, content) {
    fs.mkdirSync(path.dirname(disk(input)), { recursive: true });
    fs.writeFileSync(disk(input), typeof content === 'object' && !Buffer.isBuffer(content) ? JSON.stringify(content) : content);
  }
  async function pack(input, files) {
    const writer = new zip.ZipWriter(new zip.Uint8ArrayWriter());
    for (const [name, data] of Object.entries(files)) {
      await writer.add(name, new zip.Uint8ArrayReader(new Uint8Array(Buffer.isBuffer(data) ? data : Buffer.from(JSON.stringify(data)))));
    }
    put(input, Buffer.from(await writer.close()));
  }
  return { Repository, app, ime, put, pack, disk, writes, reads, options };
}
const layout = JSON.parse(fs.readFileSync(path.join(root, 'examples/keyboard-customization/structure-standard/layout.json'), 'utf8'));
layout.id = 'test.shared.layout'; layout.name = 'Shared layout';
[layout.rows[0].keys[0], layout.rows[0].keys[1]] = [layout.rows[0].keys[1], layout.rows[0].keys[0]];
const skin = { schemaVersion: 1, id: 'test.shared.skin', name: 'Shared images',
  colors: { letterKeyBackground: '#E933B7', panelBackground: '#10203080' }, images: { letterKey: 'assets/key.png' } };
const png = fs.readFileSync(path.join(root, 'examples/keyboard-customization/skin-soft-blue/assets/letter-key.png'));
async function test(name, callback) { await callback(); console.log('PASS ' + name); passed++; }

(async () => {
  await test('missing authorization rejects imports, retains legacy files and built-ins', async () => {
    const r = runtime('unconfigured', { unconfigured: true });
    r.put('/app/files/keyboard-customization/skins/test.shared.skin/skin.json', skin);
    r.put('/app/files/keyboard-customization/skins/test.shared.skin/assets/key.png', png);
    const app = new r.Repository(); await app.initialize(r.app, true);
    assert.equal((await app.importSkinPackage(r.app, '/missing.zip')).success, false);
    assert.ok(app.listSkins().some(item => item.id === skin.id));
    assert.ok(app.selectionError('skin', skin.id));
    assert.equal(app.selectionError('skin', 'builtin.follow-system'), '');
    assert.equal(app.loadSkin(skin.id), undefined);
    assert.equal(r.writes.length, 0);
  });
  await test('getGroupDir rejection never falls back to private filesDir', async () => {
    const r = runtime('denied', { failGroup: true });
    const app = new r.Repository(); await app.initialize(r.app, true);
    assert.equal(app.canImport(), false);
    assert.ok(app.getStorageMessage().includes('无法访问'));
    assert.equal(r.writes.length, 0);
  });
  await test('App export/import reaches a separate IME repository for layout, colors and image bytes', async () => {
    const r = runtime('cross-process');
    await r.pack('/input/layout.zip', { 'layout.json': layout });
    await r.pack('/input/skin.zip', { 'skin.json': skin, 'assets/key.png': png });
    const app = new r.Repository();
    const layoutResult = await app.importStructurePackage(r.app, '/input/layout.zip');
    assert.equal(layoutResult.success, true, layoutResult.message);
    const skinResult = await app.importSkinPackage(r.app, '/input/skin.zip');
    assert.equal(skinResult.success, true, skinResult.message);
    const writesBefore = r.writes.length;
    r.options.readOnly = true;
    const ime = new r.Repository(); await ime.initialize(r.ime);
    assert.equal(ime.loadStructure(layout.id).rows[0].keys[0].id, layout.rows[0].keys[0].id);
    const result = ime.loadSkin(skin.id);
    assert.equal(result.definition.colors.letterKeyBackground, '#E933B7');
    assert.equal(result.definition.colors.panelBackground, '#10203080');
    assert.ok(result.assetRoot.startsWith('/group-ime/'));
    assert.deepEqual(fs.readFileSync(r.disk(result.assetRoot + '/assets/key.png')), png);
    assert.equal(r.writes.length, writesBefore);
    assert.ok(r.reads.every(input => !input.startsWith('/ime/files')));
    assert.equal(ime.canImport(), false);
  });
  await test('legacy migration copies assets once, keeps newer shared version, and deletion does not resurrect it', async () => {
    const r = runtime('migration');
    const legacy = '/app/files/keyboard-customization/skins/' + skin.id;
    r.put(legacy + '/skin.json', skin); r.put(legacy + '/assets/key.png', png);
    const app = new r.Repository(); await app.initialize(r.app, true);
    const ime = new r.Repository(); await ime.initialize(r.ime);
    assert.ok(ime.loadSkin(skin.id));
    const newer = { ...skin, name: 'Replacement', colors: { letterKeyBackground: '#123456' } };
    await r.pack('/input/new.zip', { 'skin.json': newer, 'assets/key.png': png });
    assert.equal((await app.importSkinPackage(r.app, '/input/new.zip')).success, true);
    await app.initialize(r.app, true);
    assert.equal(ime.loadSkin(skin.id).definition.name, 'Replacement');
    assert.equal(app.removeSkin(skin.id), true);
    await app.initialize(r.app, true);
    assert.equal(ime.loadSkin(skin.id), undefined);
    assert.equal(fs.existsSync(r.disk(legacy)), false);
  });
  await test('failed shared publication keeps the previous installed package and reports failure', async () => {
    const r = runtime('rollback');
    await r.pack('/input/good.zip', { 'skin.json': skin, 'assets/key.png': png });
    const app = new r.Repository(); await app.initialize(r.app, true);
    assert.equal((await app.importSkinPackage(r.app, '/input/good.zip')).success, true);
    r.options.failWrite = input => input.includes('.tmp-') && input.endsWith('/assets/key.png');
    const result = await app.importSkinPackage(r.app, '/input/good.zip');
    assert.equal(result.success, false);
    assert.equal(app.loadSkin(skin.id).definition.name, skin.name);
  });
  await test('missing skin assets cannot be selected or migrated successfully', async () => {
    const r = runtime('missing-image');
    r.put('/app/files/keyboard-customization/skins/' + skin.id + '/skin.json', skin);
    const app = new r.Repository(); await app.initialize(r.app, true);
    assert.ok(app.getStorageMessage().includes('迁移失败'));
    assert.ok(app.selectionError('skin', skin.id));
    assert.equal(app.loadSkin(skin.id), undefined);
  });
  await test('concurrent readers wait for the shared directory before loading', async () => {
    const r = runtime('async-reader', { readOnly: true });
    let resolveGroup, calls = 0;
    const group = new Promise(resolve => { resolveGroup = resolve; });
    r.ime.getGroupDir = () => { calls++; return group; };
    const ime = new r.Repository();
    const first = ime.initialize(r.ime), second = ime.initialize(r.ime);
    assert.equal(ime.loadSkin(skin.id), undefined);
    resolveGroup('/group-ime'); await Promise.all([first, second]);
    assert.equal(calls, 1); assert.equal(r.writes.length, 0);
  });
  await test('build guard requires matching runtime, extension and signed profile group declarations', () => {
    // Plain JSON here is a unit-test fixture, never a usable provisioning profile.
    const fixture = path.join(temp, 'unsigned-profile-fixture.json');
    fs.writeFileSync(fixture, JSON.stringify({ 'data-group-ids': ['unit-test-group'] }));
    const module = { module: { extensionAbilities: [{ type: 'inputMethod', dataGroupIds: ['unit-test-group'] }] } };
    assert.equal(validate('unit-test-group', module, fixture, true), true);
    assert.throws(() => validate('wrong', module, fixture, true));
    module.module.extensionAbilities[0].dataGroupIds = ['wrong'];
    assert.throws(() => validate('wrong', module, fixture, true));
    module.module.extensionAbilities[0].dataGroupIds = [];
    assert.equal(validate('', module, fixture, false), false);
    assert.throws(() => validate('', module, fixture, true));
  });
  console.log(`${passed} host storage contract tests passed. Device shared-group authorization remains a separate acceptance requirement.`);
})().catch(error => { console.error(error); process.exitCode = 1; });
