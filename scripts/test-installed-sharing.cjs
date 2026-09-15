const assert = require('node:assert/strict');
const { verifyInstalledSharing } = require('./verify-installed-sharing.cjs');
const group = 'group.test';
const dump = valid => 'com.example.app:\n' + JSON.stringify({
  appIdentifier: valid ? 'test-app' : '',
  hapModuleInfos: [{ extensionInfos: [{ type: 2, dataGroupIds: [group], validDataGroupIds: valid ? [group] : [] }] }]
});
assert.deepEqual(verifyInstalledSharing(dump(true), [group]), [group]);
assert.throws(() => verifyInstalledSharing(dump(false), [group]), /authorization is inactive/);
assert.throws(() => verifyInstalledSharing('installation failed', [group]));
console.log('PASS installed authorization: active group accepted, declared-only group rejected, invalid dump rejected');
