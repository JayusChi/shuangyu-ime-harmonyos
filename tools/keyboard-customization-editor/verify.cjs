const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
globalThis.zip = require('./vendor/zip-no-worker.min.js');
require('./format.js'); require('./defaults.js'); require('./package-io.js');
const root = path.resolve(__dirname, '../..');
const file = (blob, name) => Object.assign(blob, { name });
const copy = value => JSON.parse(JSON.stringify(value));
async function archive(entries) {
  const writer = new zip.ZipWriter(new zip.BlobWriter(), { useWebWorkers: false });
  for (const [name, value] of entries) await writer.add(name, new zip.TextReader(value));
  return writer.close();
}
(async () => {
  let count = 0;
  async function test(name, run) { await run(); count++; console.log('PASS ' + name); }
  await test('App bundles the same self-contained offline editor', async () => {
    const standalone = fs.readFileSync(path.join(__dirname, 'standalone.html'), 'utf8');
    assert.equal(fs.readFileSync(path.join(root, 'entry/src/main/resources/rawfile/keyboard-skin-editor.html'), 'utf8'), standalone);
    assert.ok(!/<script[^>]+src=|<link[^>]+href=["']styles\.css/.test(standalone));
  });
  await test('skin edit/export/reopen preserves all colors', async () => {
    const skin = copy(EditorDefaults.skin); skin.colors.panelBackground = '#F7E4EA';
    const blob = await EditorIO.write('skin',skin);
    const result = await EditorIO.read(file(blob, 'edited.sy-skin'));
    assert.deepEqual(result.definition,skin);
  });
  await test('structure reorder and custom width survive export', async () => {
    const layout = copy(EditorDefaults.layout);
    [layout.rows[0].keys[0],layout.rows[0].keys[1]] = [layout.rows[0].keys[1],layout.rows[0].keys[0]];
    layout.rows[3].keys[2].weight = 6.3; layout.rows[3].keys[2].label = '我的空格';
    const result = await EditorIO.read(file(await EditorIO.write('structure',layout),'edited.sy-layout'));
    assert.deepEqual(result.definition,layout);
  });
  await test('image template export/reopen preserves image bytes', async () => {
    const dir = path.join(root,'examples/keyboard-customization/skin-soft-blue');
    const skin = JSON.parse(fs.readFileSync(path.join(dir,'skin.json'),'utf8'));
    const assets = new Map(Object.values(skin.images).map(name => [name,new Blob([fs.readFileSync(path.join(dir,name))])]));
    const result = await EditorIO.read(file(await EditorIO.write('skin',skin,assets),'images.sy-skin'));
    for (const [name,original] of assets) assert.deepEqual(Buffer.from(await result.assets.get(name).arrayBuffer()),Buffer.from(await original.arrayBuffer()));
  });
  await test('existing PowerShell-compressed packages import', async () => {
    for (const name of ['my-color-skin.sy-skin','my-image-skin.sy-skin','my-keyboard.sy-layout']) {
      const data = fs.readFileSync(path.join(root,'outputs/keyboard-customization-templates-20260908/packages',name));
      await EditorIO.read(file(new Blob([data]),name));
    }
  });
  await test('malformed colors, reserved ID and duplicate keys are rejected', async () => {
    const skin = copy(EditorDefaults.skin); skin.colors.panelBackground = 'red';
    await assert.rejects(() => EditorIO.write('skin',skin), /颜色/);
    skin.colors.panelBackground = '#FFFFFF'; skin.id = 'builtin.fake';
    await assert.rejects(() => EditorIO.write('skin',skin), /ID/);
    const layout = copy(EditorDefaults.layout); layout.rows[0].keys[0].id = 'letter-w';
    await assert.rejects(() => EditorIO.write('structure',layout), /重复/);
  });
  await test('missing image blocks export', async () => {
    const skin = copy(EditorDefaults.skin); skin.images.letterKey = 'assets/missing.png';
    await assert.rejects(() => EditorIO.write('skin',skin), /缺少图片/);
  });
  await test('JSON import can defer images until user supplies them', async () => {
    const skin = copy(EditorDefaults.skin); skin.images.letterKey = 'assets/missing.png';
    const result = await EditorIO.read(file(new Blob([JSON.stringify(skin)]),'skin.json'));
    assert.equal(result.assets.size,0); assert.equal(result.definition.images.letterKey,'assets/missing.png');
  });
  await test('single enclosing directory is supported', async () => {
    const blob = await archive([['template/skin.json',JSON.stringify(EditorDefaults.skin)]]);
    assert.equal((await EditorIO.read(file(blob,'skin.zip'))).kind,'skin');
  });
  await test('mixed packages and unsafe paths are rejected', async () => {
    const mixed = await archive([['skin.json',JSON.stringify(EditorDefaults.skin)],['layout.json',JSON.stringify(EditorDefaults.layout)]]);
    await assert.rejects(() => EditorIO.read(file(mixed,'mixed.zip')), /分别打包/);
    const unsafe = await archive([['skin.json',JSON.stringify(EditorDefaults.skin)],['../escape.txt','bad']]);
    await assert.rejects(() => EditorIO.read(file(unsafe,'unsafe.zip')), /路径/);
  });
  await test('file count limit is enforced before extraction', async () => {
    const entries = [['skin.json',JSON.stringify(EditorDefaults.skin)]];
    for (let i=0;i<32;i++) entries.push(['extra'+i+'.txt','x']);
    const blob = await archive(entries);
    await assert.rejects(() => EditorIO.read(file(blob,'many.zip')), /32/);
  });
  console.log(`${count} integration checks passed.`);
})().catch(error => { console.error(error); process.exitCode = 1; });
