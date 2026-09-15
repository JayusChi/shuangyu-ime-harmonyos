const fs = require('node:fs');
function verifyInstalledSharing(dump, requiredGroups) {
  const bundle = JSON.parse(dump.slice(dump.indexOf('{')));
  const extensions = (bundle.hapModuleInfos || []).flatMap(module => module.extensionInfos || [])
    .filter(extension => extension.type === 2);
  const validGroups = extensions.flatMap(extension => extension.validDataGroupIds || []);
  const missing = requiredGroups.filter(group => !validGroups.includes(group));
  if (missing.length) {
    throw new Error(`Installed shared-group authorization is inactive: ${missing.join(', ')}. ` +
      `appIdentifier=${bundle.appIdentifier || '(empty)'}. A simulator can accept an untrusted AppGallery release ` +
      'package without its Profile identity. Use the authorized AppGallery test channel; bm install success alone is not acceptance.');
  }
  return validGroups;
}
module.exports = { verifyInstalledSharing };
if (require.main === module) {
  try {
    const groups = verifyInstalledSharing(fs.readFileSync(process.argv[2], 'utf8'), process.argv.slice(3));
    console.log('INSTALLED_SHARED_GROUPS=PASS ' + groups.join(','));
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
