import { describe, it, expect } from '@ohos/hypium';
import { SettingsValidator } from '../main/ets/infrastructure/storage/SettingsValidator';
import {
  CURRENT_SETTINGS_SCHEMA_VERSION,
  DEFAULT_SCHEME_ID,
  SettingsRaw
} from '../main/ets/domain/settings/ImeSettings';
import { SettingsMigration } from '../main/ets/infrastructure/storage/SettingsMigration';

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

    it('should migrate AI-0 settings with cloud and voice disabled by default', 0, () => {
      const migrated = new SettingsMigration().migrate({ schemaVersion: '8' });
      const result = validator.validate(migrated);
      expect(result.schemaVersion).assertEqual(CURRENT_SETTINGS_SCHEMA_VERSION);
      expect(result.aiEnabled).assertFalse();
      expect(result.cloudAiEnabled).assertFalse();
      expect(result.voiceInputEnabled).assertFalse();
      expect(result.voiceAutoCommit).assertFalse();
      expect(result.voiceLanguage).assertEqual('zh-CN');
      expect(result.preferredAiActions.length).assertEqual(5);
    });

    it('should preserve explicit local AI-0 feature choices across migration', 0, () => {
      const raw: SettingsRaw = {
        schemaVersion: '8',
        aiEnabled: 'true',
        cloudAiEnabled: 'false',
        voiceInputEnabled: 'true',
        voiceLanguage: 'zh-CN',
        voiceAutoCommit: 'false'
      };
      const result = validator.validate(new SettingsMigration().migrate(raw));
      expect(result.aiEnabled).assertTrue();
      expect(result.cloudAiEnabled).assertFalse();
      expect(result.voiceInputEnabled).assertTrue();
      expect(result.voiceAutoCommit).assertFalse();
    });
  });
}
