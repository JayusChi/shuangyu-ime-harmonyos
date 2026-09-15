import { common, wantConstant } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';

/** The generic HTML handler is a document preview; use the HarmonyOS browser to run the editor. */
export async function openKeyboardSkinEditor(context: common.UIAbilityContext): Promise<void> {
  const content = await context.resourceManager.getRawFileContent('keyboard-skin-editor.html');
  const path = `${context.cacheDir}/keyboard-skin-editor.html`;
  const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
  try {
    const bytes = content.buffer.slice(content.byteOffset, content.byteOffset + content.byteLength);
    if (fs.writeSync(file.fd, bytes) !== content.byteLength) {
      throw new Error('Editor file was not written completely');
    }
  } finally {
    fs.closeSync(file);
  }
  await context.startAbility({
    bundleName: 'com.huawei.hmos.browser',
    abilityName: 'MainAbility',
    action: 'ohos.want.action.viewData',
    uri: fileUri.getUriFromPath(path),
    type: 'text/html',
    flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION
  });
}
