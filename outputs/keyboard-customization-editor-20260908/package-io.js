(function (root) {
  'use strict';
  const MAX_ARCHIVE = 12 * 1024 * 1024;
  const MAX_EXTRACTED = 24 * 1024 * 1024;
  const ASSET = /^assets\/[a-zA-Z0-9][a-zA-Z0-9._-]{0,95}\.(png|jpg|jpeg|webp)$/;
  const IMAGE_KEYS = ['panelBackground', 'letterKey', 'functionKey', 'spaceKey', 'enterKey'];
  function parse(kind, value) {
    const content = typeof value === 'string' ? value : JSON.stringify(value);
    const result = kind === 'skin' ? root.KeyboardFormat.parseKeyboardSkinJson(content)
      : root.KeyboardFormat.parseKeyboardStructureJson(content);
    if (!result.success) throw new Error(result.message);
    return result.value;
  }
  function imageType(path) {
    const ext = path.split('.').pop();
    return ext === 'jpg' || ext === 'jpeg' ? 'image/jpeg' : `image/${ext}`;
  }
  function validateAssets(skin, assets) {
    let bytes = new TextEncoder().encode(JSON.stringify(skin)).length;
    const paths = [...new Set(Object.values(skin.images))];
    for (const path of paths) {
      if (!ASSET.test(path) || !assets.has(path)) throw new Error(`缺少图片：${path}。请在“图片”页补充。`);
      bytes += assets.get(path).size;
    }
    if (paths.length + 1 > 32 || bytes > MAX_EXTRACTED) throw new Error('图片总量超出模板限制，请缩小图片后重试。');
  }
  async function read(file) {
    if (!file.size || file.size > MAX_ARCHIVE) throw new Error('模板包需小于或等于 12MB，且不能为空。');
    if (file.name.toLowerCase().endsWith('.json')) {
      const text = (await file.text()).replace(/^\uFEFF/, '');
      let raw;
      try { raw = JSON.parse(text); } catch (_) { throw new Error('不是有效的 JSON 文件。'); }
      const kind = raw && Array.isArray(raw.rows) ? 'structure' : 'skin';
      return { kind, definition: parse(kind, raw), assets: new Map() };
    }
    const reader = new root.zip.ZipReader(new root.zip.BlobReader(file), { useWebWorkers: false });
    try {
      const entries = await reader.getEntries();
      const files = entries.filter(entry => !entry.directory);
      if (!files.length || files.length > 32 || files.reduce((sum, e) => sum + e.uncompressedSize, 0) > MAX_EXTRACTED)
        throw new Error('模板包最多 32 个文件，解压后最多 24MB。请打开单个皮肤或结构包，而不是模板合集。');
      const names = new Set();
      for (const entry of entries) {
        if (entry.encrypted || entry.filename.startsWith('/') || entry.filename.includes('\\') || entry.filename.includes(':') || entry.filename.split('/').some(part => part === '..' || part === '.'))
          throw new Error('模板包包含不支持的路径或加密文件。');
        if (names.has(entry.filename)) throw new Error('模板包包含重复文件。');
        names.add(entry.filename);
      }
      let manifest = files.find(e => e.filename === 'skin.json' || e.filename === 'layout.json');
      if (!manifest) {
        const roots = new Set(entries.map(e => e.filename.split('/')[0]));
        if (roots.size === 1) manifest = files.find(e => /^[^/]+\/(skin|layout)\.json$/.test(e.filename));
      }
      if (!manifest) throw new Error('找不到 skin.json 或 layout.json。请解压合集后打开单个模板包。');
      const prefix = manifest.filename.slice(0, manifest.filename.lastIndexOf('/') + 1);
      if (names.has(prefix + 'skin.json') && names.has(prefix + 'layout.json')) throw new Error('皮肤和结构应分别打包，请选择单个模板包。');
      const kind = manifest.filename.endsWith('skin.json') ? 'skin' : 'structure';
      const text = await manifest.getData(new root.zip.TextWriter(), { checkSignature: true });
      const definition = parse(kind, text.replace(/^\uFEFF/, ''));
      const assets = new Map();
      if (kind === 'skin') {
        for (const path of new Set(Object.values(definition.images))) {
          const entry = files.find(e => e.filename === prefix + path);
          if (!entry) throw new Error(`模板包缺少图片：${path}`);
          assets.set(path, await entry.getData(new root.zip.BlobWriter(imageType(path)), { checkSignature: true }));
        }
        validateAssets(definition, assets);
      }
      return { kind, definition, assets };
    } finally { await reader.close(); }
  }
  async function write(kind, value, assets = new Map()) {
    const definition = parse(kind, value);
    if (kind === 'skin') validateAssets(definition, assets);
    const writer = new root.zip.ZipWriter(new root.zip.BlobWriter('application/zip'), { useWebWorkers: false, zip64: false });
    let blob;
    try {
      await writer.add(kind === 'skin' ? 'skin.json' : 'layout.json', new root.zip.TextReader(JSON.stringify(definition, null, 2) + '\n'), { level: 6 });
      if (kind === 'skin') for (const path of new Set(Object.values(definition.images))) {
        await writer.add(path, new root.zip.BlobReader(assets.get(path)), { level: 0 });
      }
    } finally { blob = await writer.close(); }
    if (blob.size > MAX_ARCHIVE) throw new Error('导出包超过 12MB，请缩小图片后重试。');
    return blob;
  }
  root.EditorIO = { read, write, parse, validateAssets, imageType, IMAGE_KEYS };
})(globalThis);
