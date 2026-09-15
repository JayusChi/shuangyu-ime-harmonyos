import { describe, it, expect } from '@ohos/hypium';
import { SettingsValidator } from '../main/ets/infrastructure/storage/SettingsValidator';
import {
  CURRENT_SETTINGS_SCHEMA_VERSION,
  DEFAULT_SCHEME_ID,
  SettingsRaw
} from '../main/ets/domain/settings/ImeSettings';
import { SettingsMigration } from '../main/ets/infrastructure/storage/SettingsMigration';
import {
  LEGACY_ENGLISH_SINGLE_TILDE_LETTER_SWIPE_SYMBOLS,
  resolveLetterSwipeSymbol,
  updateLetterSwipeSymbol
} from '../main/ets/domain/keyboard/LetterSwipeSymbols';

export default function settingsMigrationTest() {
  describe('SettingsValidator scheme validation', () => {
    const validator = new SettingsValidator();

    it('migrates the five-item candidate default and preserves a chosen limit', 0, () => {
      const migration = new SettingsMigration();
      expect(validator.validate(migration.migrate({ schemaVersion: '22' })).candidateDisplayCount).assertEqual(5);
      expect(validator.validate(migration.migrate({ candidateDisplayCount: '8' })).candidateDisplayCount).assertEqual(8);
      expect(validator.validate({ candidateDisplayCount: 'bad' }).candidateDisplayCount).assertEqual(5);
      expect(validator.validate({ candidateDisplayCount: '100' }).candidateDisplayCount).assertEqual(5);
      expect(validator.validate({ candidateDisplayCount: '0' }).candidateDisplayCount).assertEqual(5);
    });

    it('defaults old installs to traditional and preserves explicit split choices', 0, () => {
      const migration = new SettingsMigration();
      expect(validator.validate(migration.migrate({ schemaVersion: '19' }))
        .codeTableReverseSplitEnabled).assertFalse();
      expect(validator.validate(migration.migrate({ codeTableReverseSplitEnabled: 'true' }))
        .codeTableReverseSplitEnabled).assertTrue();
      expect(validator.validate(migration.migrate({ codeTableReverseSplitEnabled: 'false' }))
        .codeTableReverseSplitEnabled).assertFalse();
      expect(validator.validate({ codeTableReverseSplitEnabled: 'invalid' })
        .codeTableReverseSplitEnabled).assertFalse();
    });

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

    it('uses the current smart punctuation default when migrating legacy defaults', 0, () => {
      const corrected = new SettingsMigration().migrate({
        schemaVersion: '17',
        smartPeriodTimeoutMs: '500'
      });
      const customized = new SettingsMigration().migrate({
        schemaVersion: '17',
        smartPeriodTimeoutMs: '800'
      });

      expect(corrected.smartPeriodTimeoutMs).assertEqual('300');
      expect(customized.smartPeriodTimeoutMs).assertEqual('800');
      expect(corrected.schemaVersion).assertEqual(`${CURRENT_SETTINGS_SCHEMA_VERSION}`);
      expect(validator.validate(new SettingsMigration().migrate({})).smartPeriodTimeoutMs).assertEqual(300);
      expect(validator.validate(new SettingsMigration().migrate({
        schemaVersion: `${CURRENT_SETTINGS_SCHEMA_VERSION}`, smartPeriodTimeoutMs: '1000'
      })).smartPeriodTimeoutMs).assertEqual(1000);
    });

    it('upgrades only the untouched English G down-swipe preset to backslash-tilde', 0, () => {
      const corrected = new SettingsMigration().migrate({
        schemaVersion: '18',
        englishLetterSwipeSymbols: LEGACY_ENGLISH_SINGLE_TILDE_LETTER_SWIPE_SYMBOLS
      });
      const customizedMap = updateLetterSwipeSymbol(
        LEGACY_ENGLISH_SINGLE_TILDE_LETTER_SWIPE_SYMBOLS,
        'a',
        '&'
      );
      const customized = new SettingsMigration().migrate({
        schemaVersion: '18',
        englishLetterSwipeSymbols: customizedMap
      });

      expect(resolveLetterSwipeSymbol(corrected.englishLetterSwipeSymbols, 'g')).assertEqual('\\~');
      expect(resolveLetterSwipeSymbol(customized.englishLetterSwipeSymbols, 'g')).assertEqual('~');
      expect(resolveLetterSwipeSymbol(customized.englishLetterSwipeSymbols, 'a')).assertEqual('&');
    });
  });
}
