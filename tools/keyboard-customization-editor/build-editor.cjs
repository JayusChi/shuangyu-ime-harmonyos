// Run with Node. Generates browser data directly from the current ArkTS format.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '../..');
const ts = require(process.env.KEYBOARD_EDITOR_TYPESCRIPT || 'C:/Program Files/Huawei/DevEco Studio/tools/hvigor/hvigor/node_modules/typescript');
const zipRoot = process.env.KEYBOARD_EDITOR_ZIPJS || 'C:/Program Files/Huawei/DevEco Studio/tools/hvigor/hvigor/node_modules/@zip.js/zip.js';
const compile = file => ts.transpileModule(fs.readFileSync(path.join(root, file), 'utf8'), { compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS } }).outputText;
const format = compile('entry/src/main/ets/domain/customization/KeyboardCustomization.ets');
fs.writeFileSync(path.join(__dirname, 'format.js'), '// Generated from KeyboardCustomization.ets. Run build-editor.cjs to refresh.\n' + 'globalThis.KeyboardFormat = (() => { const exports = {};\n' + format + '\nreturn exports; })();\n');
const paletteExports = {};
vm.runInNewContext(compile('entry/src/main/ets/presentation/keyboard/design/KeyboardPalette.ets'), { exports: paletteExports, require: () => ({ KeyboardMode: {} }) });
const colors = palette => Object.fromEntries(Object.entries(palette).filter(([key, value]) => typeof value === 'string' && value.startsWith('#')));
const defaults = {
  layout: JSON.parse(fs.readFileSync(path.join(root, 'examples/keyboard-customization/structure-standard/layout.json'), 'utf8')),
  skin: JSON.parse(fs.readFileSync(path.join(root, 'examples/keyboard-customization/skin-soft-blue/skin.json'), 'utf8')),
  light: colors(paletteExports.LIGHT_PALETTE), dark: colors(paletteExports.DARK_PALETTE)
};
defaults.layout.id = 'my.layout.standard'; defaults.layout.name = '我的键盘结构';
defaults.skin.id = 'my.skin.blue'; defaults.skin.name = '我的纯色皮肤'; defaults.skin.images = {};
defaults.skin.colors = { ...defaults.light, ...defaults.skin.colors,
  modeKeyBackgroundEnglish: '#C7D8EE', modeKeyBackgroundChinese: '#C7D8EE',
  modeKeyTextEnglish: '#18324F', modeKeyTextChinese: '#18324F',
  previewBackground: '#F8FBFF', previewText: '#18324F' };
fs.writeFileSync(path.join(__dirname, 'defaults.js'), '// Generated from project templates and palette.\nglobalThis.EditorDefaults = ' + JSON.stringify(defaults, null, 2) + ';\n');
fs.mkdirSync(path.join(__dirname, 'vendor'), { recursive: true });
fs.copyFileSync(path.join(zipRoot, 'dist/zip-no-worker.min.js'), path.join(__dirname, 'vendor/zip-no-worker.min.js'));
fs.copyFileSync(path.join(zipRoot, 'LICENSE'), path.join(__dirname, 'vendor/zip.js-LICENSE.txt'));
console.log('Built offline editor data and vendored zip.js ' + JSON.parse(fs.readFileSync(path.join(zipRoot, 'package.json'))).version);
let standalone = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
standalone = standalone.replace('<link rel="stylesheet" href="styles.css">', () => '<style>\n' + fs.readFileSync(path.join(__dirname, 'styles.css'), 'utf8') + '\n</style>');
const scripts = [];
standalone = standalone.replace(/<script defer src="([^"]+)"><\/script>/g, (_, name) => {
  const code = fs.readFileSync(path.join(__dirname, name), 'utf8').replace(/<\/script/gi, '<\\/script');
  scripts.push('<script>\n' + code + '\n</script>');
  return '';
});
standalone = standalone.replace('</body>', () => scripts.join('\n') + '\n</body>');
fs.writeFileSync(path.join(__dirname, 'standalone.html'), standalone);
fs.writeFileSync(path.join(root, 'entry/src/main/resources/rawfile/keyboard-skin-editor.html'), standalone);
console.log('Generated standalone.html: one offline file, no sibling resources required.');
