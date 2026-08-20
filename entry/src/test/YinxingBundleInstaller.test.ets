import { describe, it, expect } from '@ohos/hypium';
import { YinxingBundleInstaller } from '../main/ets/infrastructure/resource/YinxingBundleInstaller';

export default function yinxingBundleInstallerTest() {
  describe('YinxingBundleInstaller', () => {
    it('should create installer instance', 0, () => {
      const installer = new YinxingBundleInstaller();
      expect(installer !== null).assertTrue();
      expect(installer !== undefined).assertTrue();
    });
  });
}
