import { describe, it, expect } from '@ohos/hypium';
import { SettingsValidator } from '../main/ets/infrastructure/storage/SettingsValidator';
import { DEFAULT_SCHEME_ID, SettingsRaw } from '../main/ets/domain/settings/ImeSettings';

export default function settingsMigrationTest() {
  describe('SettingsValidator scheme validation', () => {
    const validator = new SettingsValidator();

    it('should preserve valid xiaohe scheme', 0, () => {
      const raw: SettingsRaw = { schemeId: 'xiaohe' };
      const result = validator.validate(raw);
      expect(result.schemeId).assertEqual('xiaohe');
    });

    it('should preserve valid xiaohe-yinxing scheme', 0, () => {
      const raw: SettingsRaw = { schemeId: 'xiaohe-yinxing' };
      const result = validator.validate(raw);
      expect(result.schemeId).assertEqual('xiaohe-yinxing');
    });

    it('should migrate unknown scheme to xiaohe', 0, () => {
      const raw: SettingsRaw = { schemeId: 'unknown-scheme' };
      const result = validator.validate(raw);
      expect(result.schemeId).assertEqual(DEFAULT_SCHEME_ID);
    });

    it('should migrate empty scheme to xiaohe', 0, () => {
      const raw: SettingsRaw = { schemeId: '' };
      const result = validator.validate(raw);
      expect(result.schemeId).assertEqual(DEFAULT_SCHEME_ID);
    });

    it('should migrate missing scheme to xiaohe', 0, () => {
      const raw: SettingsRaw = {};
      const result = validator.validate(raw);
      expect(result.schemeId).assertEqual(DEFAULT_SCHEME_ID);
    });

    it('should migrate fixture scheme to xiaohe', 0, () => {
      const raw: SettingsRaw = { schemeId: 'xiaohe-fixture' };
      const result = validator.validate(raw);
      expect(result.schemeId).assertEqual(DEFAULT_SCHEME_ID);
    });

    it('should be idempotent for valid schemes', 0, () => {
      const raw1: SettingsRaw = { schemeId: 'xiaohe' };
      const result1a = validator.validate(raw1);
      const result1b = validator.validate({ schemeId: result1a.schemeId });
      expect(result1b.schemeId).assertEqual('xiaohe');

      const raw2: SettingsRaw = { schemeId: 'xiaohe-yinxing' };
      const result2a = validator.validate(raw2);
      const result2b = validator.validate({ schemeId: result2a.schemeId });
      expect(result2b.schemeId).assertEqual('xiaohe-yinxing');
    });

    it('should be idempotent for migrated schemes', 0, () => {
      const raw: SettingsRaw = { schemeId: 'invalid' };
      const result1 = validator.validate(raw);
      const result2 = validator.validate({ schemeId: result1.schemeId });
      expect(result2.schemeId).assertEqual(DEFAULT_SCHEME_ID);
    });
  });
}
