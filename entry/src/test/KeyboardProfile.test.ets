import { describe, it, expect } from '@ohos/hypium';
import {
  DEFAULT_KEYBOARD_PROFILE_ID,
  enabledKeyboardProfiles,
  findKeyboardProfile,
  isEnabledKeyboardProfile,
  keyboardProfileForLegacy,
  KeyboardLayoutKind,
  PINYIN_9_PROFILE_ID,
  QUANPIN_26_PROFILE_ID,
  XIAOHE_17_PROFILE_ID,
  XIAOHE_26_PROFILE_ID,
  XIAOHE_YINXING_17_PROFILE_ID
} from '../main/ets/domain/keyboard/KeyboardProfile';
import { SettingsMigration } from '../main/ets/infrastructure/storage/SettingsMigration';
import { SettingsValidator } from '../main/ets/infrastructure/storage/SettingsValidator';

export default function keyboardProfileTest() {
  describe('keyboard profile pinyin stage 4', () => {
    it('enables quanpin and the complete T9 profile', 0, () => {
      expect(findKeyboardProfile(QUANPIN_26_PROFILE_ID)?.layoutKind)
        .assertEqual(KeyboardLayoutKind.QWERTY_26_KEY);
      expect(findKeyboardProfile(PINYIN_9_PROFILE_ID)?.layoutKind)
        .assertEqual(KeyboardLayoutKind.T9_9_KEY);
      expect(isEnabledKeyboardProfile(QUANPIN_26_PROFILE_ID)).assertTrue();
      expect(isEnabledKeyboardProfile(PINYIN_9_PROFILE_ID)).assertTrue();
    });

    it('migrates legacy 17 and 26 key Xiaohe layout values', 0, () => {
      expect(keyboardProfileForLegacy('xiaohe', 'seventeen_key')).assertEqual(XIAOHE_17_PROFILE_ID);
      expect(keyboardProfileForLegacy('xiaohe', 'twenty_six_key')).assertEqual(XIAOHE_26_PROFILE_ID);
    });

    it('preserves the Xiaohe Yinxing scheme while migrating its legacy layout', 0, () => {
      expect(keyboardProfileForLegacy('xiaohe-yinxing', 'seventeen_key'))
        .assertEqual(XIAOHE_YINXING_17_PROFILE_ID);
    });

    it('recovers a legacy quanpin engine choice to the only legal QWERTY profile', 0, () => {
      expect(keyboardProfileForLegacy('quanpin', 'seventeen_key')).assertEqual(QUANPIN_26_PROFILE_ID);
    });

    it('falls an unknown legacy scheme back to xiaohe-26 even when layout says 17', 0, () => {
      const migrated = new SettingsMigration().migrate({
        schemeId: 'unknown', legacyKeyboardLayout: 'seventeen_key'
      });
      const settings = new SettingsValidator().validate(migrated);
      expect(settings.keyboardProfileId).assertEqual(DEFAULT_KEYBOARD_PROFILE_ID);
      expect(settings.schemeId).assertEqual('xiaohe');
    });

    it('uses profile as the validated source of scheme and rejects only disabled profiles', 0, () => {
      const valid = new SettingsValidator().validate({
        keyboardProfileId: XIAOHE_17_PROFILE_ID,
        schemeId: 'xiaohe-yinxing'
      });
      expect(valid.keyboardProfileId).assertEqual(XIAOHE_17_PROFILE_ID);
      expect(valid.schemeId).assertEqual('xiaohe');

      const quanpin = new SettingsValidator().validate({ keyboardProfileId: QUANPIN_26_PROFILE_ID });
      expect(quanpin.keyboardProfileId).assertEqual(QUANPIN_26_PROFILE_ID);
      expect(quanpin.schemeId).assertEqual('quanpin');

      const pinyin9 = new SettingsValidator().validate({ keyboardProfileId: PINYIN_9_PROFILE_ID });
      expect(pinyin9.keyboardProfileId).assertEqual(PINYIN_9_PROFILE_ID);
      expect(pinyin9.schemeId).assertEqual('pinyin-9');
    });

    it('restores persisted and legacy T9 profile selections', 0, () => {
      expect(keyboardProfileForLegacy('pinyin-9', 'twenty_six_key')).assertEqual(PINYIN_9_PROFILE_ID);
      const restored = new SettingsValidator().validate({
        keyboardProfileId: PINYIN_9_PROFILE_ID,
        schemeId: 'xiaohe'
      });
      expect(restored.keyboardProfileId).assertEqual(PINYIN_9_PROFILE_ID);
      expect(restored.schemeId).assertEqual('pinyin-9');
    });

    it('keeps every legal new profile unchanged and derives its matching engine scheme', 0, () => {
      const expected = [
        `${XIAOHE_17_PROFILE_ID}:xiaohe`,
        `${XIAOHE_26_PROFILE_ID}:xiaohe`,
        `${QUANPIN_26_PROFILE_ID}:quanpin`,
        `${PINYIN_9_PROFILE_ID}:pinyin-9`
      ];
      const actual = expected.map((entry: string): string => {
        const profileId = entry.split(':')[0];
        const settings = new SettingsValidator().validate({
          keyboardProfileId: profileId,
          schemeId: 'damaged-stale-value'
        });
        return `${settings.keyboardProfileId}:${settings.schemeId}`;
      });
      expect(actual.join('|')).assertEqual(expected.join('|'));
    });

    it('normalizes damaged profile data safely and migration is idempotent', 0, () => {
      const migration = new SettingsMigration();
      const first = migration.migrate({
        schemaVersion: 'not-a-number',
        keyboardProfileId: 'damaged-profile',
        schemeId: 'pinyin-9',
        keySoundEnabled: 'true',
        userLearningEnabled: 'false'
      });
      const firstValidated = new SettingsValidator().validate(first);
      const secondValidated = new SettingsValidator().validate(migration.migrate(first));
      expect(firstValidated.keyboardProfileId).assertEqual(DEFAULT_KEYBOARD_PROFILE_ID);
      expect(firstValidated.schemeId).assertEqual('xiaohe');
      expect(firstValidated.keySoundEnabled).assertTrue();
      expect(firstValidated.userLearningEnabled).assertFalse();
      expect(secondValidated.keyboardProfileId).assertEqual(firstValidated.keyboardProfileId);
      expect(secondValidated.schemeId).assertEqual(firstValidated.schemeId);
    });

    it('publishes unique enabled profile identifiers', 0, () => {
      const ids = enabledKeyboardProfiles().map((profile) => profile.profileId);
      expect(new Set<string>(ids).size).assertEqual(ids.length);
    });
  });
}
