/* Configure only an ID present in a Huawei-issued profile; never alter profiles. */
const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');
const root = path.resolve(__dirname, '..');
const devEco = process.env.DEVECO_STUDIO_ROOT || 'C:/Program Files/Huawei/DevEco Studio';
const ts = createRequire(path.join(devEco, 'tools/hvigor/hvigor/package.json'))('typescript');
function readConfig(file) {
  const parsed = ts.parseConfigFileTextToJson(file, fs.readFileSync(file, 'utf8'));
  if (parsed.error) throw new Error(`Cannot parse configuration: ${file}`);
  return parsed.config;
}
const modulePath = path.join(root, 'entry/src/main/module.json5');
const configPath = path.join(root, 'entry/src/main/ets/infrastructure/customization/KeyboardCustomizationStorageConfig.ets');
const declaration = /KEYBOARD_CUSTOMIZATION_DATA_GROUP_ID: string = (['"])(.*?)\1;/;

function profileGroups(profilePath) {
  const text = fs.readFileSync(profilePath).toString('utf8');
  const match = text.match(/"data-group-ids"\s*:\s*(\[[^\]]*\])/);
  return match ? JSON.parse(match[1]) : [];
}

function validate(groupId, moduleConfig, profilePath, required) {
  const extensions = moduleConfig.module.extensionAbilities.filter(item => item.type === 'inputMethod');
  if (extensions.length !== 1) throw new Error('Expected exactly one inputMethod extension.');
  const declared = extensions[0].dataGroupIds || [];
  if (!groupId) {
    if (declared.length) throw new Error('Extension declares groups but the runtime group ID is empty.');
    if (required) throw new Error('Custom packages cannot be delivered: no provisioned data-group-id is configured.');
    return false;
  }
  if (!declared.includes(groupId)) throw new Error('Runtime group ID is missing from inputMethod.dataGroupIds.');
  if (!profileGroups(profilePath).includes(groupId)) {
    throw new Error('The selected signing profile does not authorize the configured data-group-id.');
  }
  return true;
}

function main(args) {
  const value = key => args[args.indexOf(key) + 1];
  const moduleConfig = readConfig(modulePath);
  const configSource = fs.readFileSync(configPath, 'utf8');
  const configured = configSource.match(declaration);
  if (!configured) throw new Error('Cannot locate the runtime group ID declaration.');
  if (args.includes('--check')) {
    const productName = args.includes('--product') ? value('--product') : 'release';
    const build = readConfig(path.join(root, 'build-profile.json5'));
    const product = build.app.products.find(item => item.name === productName);
    const signing = build.app.signingConfigs.find(item => item.name === product?.signingConfig);
    if (!signing?.material?.profile) throw new Error('Cannot resolve the selected product signing profile.');
    const enabled = validate(configured[2], moduleConfig, signing.material.profile, args.includes('--require-shared'));
    console.log(enabled ? 'Customization shared group: configuration/profile match.' :
      'WARNING: Customization shared group is not provisioned. Imported packages are disabled in this build.');
    return;
  }
  if (!args.includes('--group-id') || !args.includes('--profile')) {
    throw new Error('Usage: node scripts/configure-keyboard-customization-sharing.cjs --group-id <issued ID> --profile <issued p7b>');
  }
  const groupId = value('--group-id');
  if (!groupId || /[\r\n]/.test(groupId) || !profileGroups(value('--profile')).includes(groupId)) {
    throw new Error('The requested ID is not authorized by the supplied profile; no files changed.');
  }
  const extension = moduleConfig.module.extensionAbilities.find(item => item.type === 'inputMethod');
  if (!extension) throw new Error('Input method extension is missing.');
  extension.dataGroupIds = [...new Set([...(extension.dataGroupIds || []), groupId])];
  validate(groupId, moduleConfig, value('--profile'), true);
  const newSource = configSource.replace(declaration,
    () => `KEYBOARD_CUSTOMIZATION_DATA_GROUP_ID: string = ${JSON.stringify(groupId)};`);
  // Both files are restored if either write fails. Signing files remain untouched.
  const oldModule = fs.readFileSync(modulePath, 'utf8');
  try {
    fs.writeFileSync(modulePath, JSON.stringify(moduleConfig, null, 2) + '\n');
    fs.writeFileSync(configPath, newSource);
  } catch (error) {
    fs.writeFileSync(modulePath, oldModule);
    fs.writeFileSync(configPath, configSource);
    throw error;
  }
  console.log('Shared group configured. Point each build product at its newly issued matching profile, then run --check --product <name> --require-shared.');
}

module.exports = { validate, profileGroups };
if (require.main === module) {
  try { main(process.argv.slice(2)); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
