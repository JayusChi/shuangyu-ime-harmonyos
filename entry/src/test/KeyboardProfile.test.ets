import { describe, it, expect } from '@ohos/hypium';
import {
  DEFAULT_KEYBOARD_PROFILE_ID,
  enabledKeyboardProfiles,
  findKeyboardProfile,
  isEnabledKeyboardProfile,
  keyboardProfileForLegacy,
  KeyboardLayoutKind,
  normalizeKeyboardProfileId,
  PINYIN_9_PROFILE_ID,
  QUANPIN_26_PROFILE_ID,
  XIAOHE_18_PROFILE_ID,
  XIAOHE_26_PROFILE_ID,
  XIAOHE_YINXING_26_PROFILE_ID
} from '../main/ets/domain/keyboard/KeyboardProfile';
import { SettingsMigration } from '../main/ets/infrastructure/storage/SettingsMigration';
import { SettingsValidator } from '../main/ets/infrastructure/storage/SettingsValidator';
import { KeyboardMode } from '../main/ets/domain/keyboard/KeyboardAction';
import {
  ENGLISH_INPUT_METHOD_SUBTYPE_ID,
  QUANPIN_INPUT_METHOD_SUBTYPE_ID,
  resolveInputMethodSubtypeTarget,
  SHUANGPIN_INPUT_METHOD_SUBTYPE_ID,
  XIAOHE_YINXING_INPUT_METHOD_SUBTYPE_ID
} from '../main/ets/domain/keyboard/InputMethodSubtypeRouting';
import {
  inputMethodSubtypeIdForKeyboardProfile,
  InputMethodSubtypeBackend,
  InputMethodSubtypeDescriptor,
  InputMethodSubtypeSynchronizer
} from '../main/ets/infrastructure/ime/InputMethodSubtypeSynchronizer';

class FakeInputMethodSubtypeBackend implements InputMethodSubtypeBackend {
  currentInputMethodName: string = 'com.corrosion.shuangyuime';
  currentSubtypeId: string = QUANPIN_INPUT_METHOD_SUBTYPE_ID;
  switchedIds: string[] = [];

  getCurrentInputMethodName(): string {
    return this.currentInputMethodName;
  }

  getCurrentSubtypeId(): string {
    return this.currentSubtypeId;
  }

  async listCurrentSubtypes(): Promise<InputMethodSubtypeDescriptor[]> {
    return [
      QUANPIN_INPUT_METHOD_SUBTYPE_ID,
      SHUANGPIN_INPUT_METHOD_SUBTYPE_ID,
      XIAOHE_YINXING_INPUT_METHOD_SUBTYPE_ID
    ].map((id: string): InputMethodSubtypeDescriptor => ({
      name: 'com.corrosion.shuangyuime', id, locale: 'zh-CN', language: 'chinese'
    }));
  }

  async switchCurrentSubtype(target: InputMethodSubtypeDescriptor): Promise<boolean> {
    this.switchedIds.push(target.id);
    this.currentSubtypeId = target.id;
    return true;
  }
}

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

    it('migrates legacy 17 key Xiaohe to the replacement 18 key profile', 0, () => {
      expect(keyboardProfileForLegacy('xiaohe', 'seventeen_key')).assertEqual(XIAOHE_18_PROFILE_ID);
      expect(keyboardProfileForLegacy('xiaohe', 'eighteen_key')).assertEqual(XIAOHE_18_PROFILE_ID);
      expect(keyboardProfileForLegacy('xiaohe', 'twenty_six_key')).assertEqual(XIAOHE_26_PROFILE_ID);
    });

    it('migrates every legacy Xiaohe Yinxing layout to its full keyboard', 0, () => {
      expect(keyboardProfileForLegacy('xiaohe-yinxing', 'seventeen_key'))
        .assertEqual(XIAOHE_YINXING_26_PROFILE_ID);
      expect(keyboardProfileForLegacy('xiaohe-yinxing', 'twenty_six_key'))
        .assertEqual(XIAOHE_YINXING_26_PROFILE_ID);
      expect(normalizeKeyboardProfileId('xiaohe-yinxing-17'))
        .assertEqual(XIAOHE_YINXING_26_PROFILE_ID);
      const restored = new SettingsValidator().validate({
        keyboardProfileId: 'xiaohe-yinxing-17', schemeId: 'xiaohe-yinxing'
      });
      expect(restored.keyboardProfileId).assertEqual(XIAOHE_YINXING_26_PROFILE_ID);
      expect(restored.schemeId).assertEqual('xiaohe-yinxing');
    });

    it('upgrades the persisted 17 key profile id to the 18 key profile', 0, () => {
      expect(normalizeKeyboardProfileId('xiaohe-17')).assertEqual(XIAOHE_18_PROFILE_ID);
      const restored = new SettingsValidator().validate({ keyboardProfileId: 'xiaohe-17' });
      expect(restored.keyboardProfileId).assertEqual(XIAOHE_18_PROFILE_ID);
      expect(restored.schemeId).assertEqual('xiaohe');
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
        keyboardProfileId: XIAOHE_18_PROFILE_ID,
        schemeId: 'xiaohe-yinxing'
      });
      expect(valid.keyboardProfileId).assertEqual(XIAOHE_18_PROFILE_ID);
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
        `${XIAOHE_18_PROFILE_ID}:xiaohe`,
        `${XIAOHE_26_PROFILE_ID}:xiaohe`,
        `${QUANPIN_26_PROFILE_ID}:quanpin`,
        `${PINYIN_9_PROFILE_ID}:pinyin-9`,
        `${XIAOHE_YINXING_26_PROFILE_ID}:xiaohe-yinxing`
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

    it('offers Xiaohe Yinxing only as a full QWERTY keyboard', 0, () => {
      const yinxingProfiles = enabledKeyboardProfiles()
        .filter((profile) => profile.engineSchemeId === 'xiaohe-yinxing');
      expect(yinxingProfiles.length).assertEqual(1);
      expect(yinxingProfiles[0].profileId).assertEqual(XIAOHE_YINXING_26_PROFILE_ID);
      expect(yinxingProfiles[0].layoutKind).assertEqual(KeyboardLayoutKind.QWERTY_26_KEY);
    });

    it('routes every system input-method subtype to a real product mode', 0, () => {
      const quanpin = resolveInputMethodSubtypeTarget(QUANPIN_INPUT_METHOD_SUBTYPE_ID);
      expect(quanpin?.keyboardMode).assertEqual(KeyboardMode.CHINESE);
      expect(quanpin?.keyboardProfileId).assertEqual(QUANPIN_26_PROFILE_ID);

      const shuangpin = resolveInputMethodSubtypeTarget(SHUANGPIN_INPUT_METHOD_SUBTYPE_ID);
      expect(shuangpin?.keyboardMode).assertEqual(KeyboardMode.CHINESE);
      expect(shuangpin?.keyboardProfileId).assertEqual(XIAOHE_26_PROFILE_ID);

      const yinxing = resolveInputMethodSubtypeTarget(XIAOHE_YINXING_INPUT_METHOD_SUBTYPE_ID);
      expect(yinxing?.keyboardMode).assertEqual(KeyboardMode.CHINESE);
      expect(yinxing?.keyboardProfileId).assertEqual(XIAOHE_YINXING_26_PROFILE_ID);

      const english = resolveInputMethodSubtypeTarget(ENGLISH_INPUT_METHOD_SUBTYPE_ID);
      expect(english?.keyboardMode).assertEqual(KeyboardMode.ENGLISH);
      expect(english?.keyboardProfileId).assertUndefined();
      expect(resolveInputMethodSubtypeTarget('unknown-subtype')).assertUndefined();
    });

    it('retains directly selected 18 key shuangpin after the platform subtype echo', 0, async () => {
      for (const initialSubtype of [QUANPIN_INPUT_METHOD_SUBTYPE_ID, XIAOHE_YINXING_INPUT_METHOD_SUBTYPE_ID]) {
        const backend = new FakeInputMethodSubtypeBackend();
        backend.currentSubtypeId = initialSubtype;
        const synchronizer = new InputMethodSubtypeSynchronizer(backend);
        expect(await synchronizer.syncForKeyboardProfile(XIAOHE_18_PROFILE_ID)).assertTrue();
        const target = resolveInputMethodSubtypeTarget(backend.currentSubtypeId, XIAOHE_18_PROFILE_ID);
        expect(target?.keyboardProfileId).assertEqual(XIAOHE_18_PROFILE_ID);
        expect(target?.keyboardMode).assertEqual(KeyboardMode.CHINESE);
        expect(await synchronizer.syncForKeyboardProfile(target?.keyboardProfileId ?? '')).assertTrue();
        expect(backend.switchedIds.length).assertEqual(1);
      }
      expect(resolveInputMethodSubtypeTarget(SHUANGPIN_INPUT_METHOD_SUBTYPE_ID, XIAOHE_26_PROFILE_ID)
        ?.keyboardProfileId).assertEqual(XIAOHE_26_PROFILE_ID);
      expect(resolveInputMethodSubtypeTarget(SHUANGPIN_INPUT_METHOD_SUBTYPE_ID, QUANPIN_26_PROFILE_ID)
        ?.keyboardProfileId).assertEqual(XIAOHE_26_PROFILE_ID);
    });

    it('maps persisted keyboard profiles back to compatible system subtypes', 0, () => {
      expect(inputMethodSubtypeIdForKeyboardProfile(QUANPIN_26_PROFILE_ID))
        .assertEqual(QUANPIN_INPUT_METHOD_SUBTYPE_ID);
      expect(inputMethodSubtypeIdForKeyboardProfile(XIAOHE_18_PROFILE_ID))
        .assertEqual(SHUANGPIN_INPUT_METHOD_SUBTYPE_ID);
      expect(inputMethodSubtypeIdForKeyboardProfile(XIAOHE_26_PROFILE_ID))
        .assertEqual(SHUANGPIN_INPUT_METHOD_SUBTYPE_ID);
      expect(inputMethodSubtypeIdForKeyboardProfile(XIAOHE_YINXING_26_PROFILE_ID))
        .assertEqual(XIAOHE_YINXING_INPUT_METHOD_SUBTYPE_ID);
      expect(inputMethodSubtypeIdForKeyboardProfile(PINYIN_9_PROFILE_ID)).assertUndefined();
    });

    it('synchronizes a stale platform subtype without repeating an equal request', 0, async () => {
      const backend = new FakeInputMethodSubtypeBackend();
      const synchronizer = new InputMethodSubtypeSynchronizer(backend);

      expect(await synchronizer.syncForKeyboardProfile(XIAOHE_YINXING_26_PROFILE_ID)).assertTrue();
      expect(backend.switchedIds.join('|')).assertEqual(XIAOHE_YINXING_INPUT_METHOD_SUBTYPE_ID);
      expect(await synchronizer.syncForKeyboardProfile(XIAOHE_YINXING_26_PROFILE_ID)).assertTrue();
      expect(backend.switchedIds.length).assertEqual(1);
    });
  });
}
