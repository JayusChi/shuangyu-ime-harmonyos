import common from '@ohos.app.ability.common';
import { dataShare, preferences } from '@kit.ArkData';
import { Logger } from '../../common/logging/Logger';
import {
  copyImeSettings,
  DEFAULT_IME_SETTINGS,
  ImeSettings,
  SettingsRaw,
  settingsToRaw
} from '../../domain/settings/ImeSettings';
import { SettingsMigration } from './SettingsMigration';
import { SettingsValidator } from './SettingsValidator';

const LOGGER = new Logger('SettingsRepository');
const PREFERENCES_NAME = 'ime_settings';
const LEGACY_LAYOUT_PREFERENCES_NAME = 'keyboard_layout_preferences';
const LEGACY_LAYOUT_KEY = 'shuangpin_keyboard_layout';
const MAIN_PROCESS_NAME = 'com.corrosion.shuangyuime';
const SHARED_SETTINGS_URI = 'datashareproxy://com.corrosion.shuangyuime/ime_settings_v2';
const SHARED_SETTINGS_CONFIG: dataShare.DataProxyConfig = {
  type: dataShare.DataProxyType.SHARED_CONFIG
};

interface SettingsPreferenceKeys {
  SCHEMA_VERSION: string;
  KEYBOARD_PROFILE_ID: string;
  SCHEME_ID: string;
  THEME_MODE: string;
  KEYBOARD_HEIGHT_MODE: string;
  CANDIDATE_FONT_SIZE_MODE: string;
  HAPTIC_LEVEL: string;
  KEY_SOUND_ENABLED: string;
  USER_LEARNING_ENABLED: string;
  SPELLING_CORRECTION_ENABLED: string;
  FUZZY_OPTIONS: string;
  INPUT_PRESENTATION_PREFERENCE: string;
  CANDIDATE_PRESENTATION_MODE: string;
  XIAOHE_YINXING_HINT_CANDIDATE_COUNT: string;
  XIAOHE_YINXING_CATEGORY_SCHEMA_VERSION: string;
  XIAOHE_YINXING_ENABLED_CATEGORY_IDS: string;
  LEXICON_SOURCES: string;
  LEGACY_DARK_MODE: string;
  LEGACY_KEYBOARD_SCALE: string;
  LEGACY_CANDIDATE_FONT_SCALE: string;
  LEGACY_VIBRATION_ENABLED: string;
}

const KEYS: SettingsPreferenceKeys = {
  SCHEMA_VERSION: 'schema_version',
  KEYBOARD_PROFILE_ID: 'keyboard_profile_id',
  SCHEME_ID: 'scheme_id',
  THEME_MODE: 'theme_mode',
  KEYBOARD_HEIGHT_MODE: 'keyboard_height_mode',
  CANDIDATE_FONT_SIZE_MODE: 'candidate_font_size_mode',
  HAPTIC_LEVEL: 'haptic_level',
  KEY_SOUND_ENABLED: 'key_sound_enabled',
  USER_LEARNING_ENABLED: 'user_learning_enabled',
  SPELLING_CORRECTION_ENABLED: 'quanpin_spelling_correction_enabled',
  FUZZY_OPTIONS: 'quanpin_fuzzy_options',
  INPUT_PRESENTATION_PREFERENCE: 'input_presentation_preference',
  CANDIDATE_PRESENTATION_MODE: 'candidate_presentation_mode',
  XIAOHE_YINXING_HINT_CANDIDATE_COUNT: 'xiaohe_yinxing_hint_candidate_count',
  XIAOHE_YINXING_CATEGORY_SCHEMA_VERSION: 'xiaohe_yinxing_category_schema_version',
  XIAOHE_YINXING_ENABLED_CATEGORY_IDS: 'xiaohe_yinxing_enabled_category_ids',
  LEXICON_SOURCES: 'lexicon_sources',
  LEGACY_DARK_MODE: 'dark_mode',
  LEGACY_KEYBOARD_SCALE: 'keyboard_scale',
  LEGACY_CANDIDATE_FONT_SCALE: 'candidate_font_scale',
  LEGACY_VIBRATION_ENABLED: 'vibration_enabled'
};

export interface SettingsRepositoryContract {
  load(context: common.Context): Promise<ImeSettings>;
  save(settings: ImeSettings): Promise<boolean>;
  reset(): Promise<boolean>;
}

export class SettingsRepositoryRecordCodec {
  encode(settings: ImeSettings): string {
    return JSON.stringify(settingsToRaw(settings));
  }

  decode(record: string): SettingsRaw {
    return JSON.parse(record) as SettingsRaw;
  }
}

export class SettingsRepository implements SettingsRepositoryContract {
  private storage?: preferences.Preferences;
  private sharedStorage?: dataShare.DataProxyHandle;
  private processName: string = 'unknown';
  private lastPersisted?: ImeSettings;
  private readonly migration: SettingsMigration;
  private readonly validator: SettingsValidator;
  private readonly recordCodec: SettingsRepositoryRecordCodec = new SettingsRepositoryRecordCodec();

  constructor(
    migration: SettingsMigration = new SettingsMigration(),
    validator: SettingsValidator = new SettingsValidator()
  ) {
    this.migration = migration;
    this.validator = validator;
  }

  async load(context: common.Context): Promise<ImeSettings> {
    this.processName = context.processName;
    await this.openSharedStorage();
    const sharedSnapshot = await this.readSharedSnapshot(context);
    if (sharedSnapshot) {
      if (this.processName === MAIN_PROCESS_NAME) {
        try {
          const storage = await this.openPreferences(context);
          await this.writeRaw(storage, settingsToRaw(sharedSnapshot));
          await storage.flush();
        } catch (err) {
          this.storage = undefined;
          LOGGER.warn(`settings snapshot mirror failed: ${JSON.stringify(err)}`);
        }
      }
      this.lastPersisted = copyImeSettings(sharedSnapshot);
      LOGGER.info(`settings snapshot loaded: process=${this.processName}, ${this.describe(sharedSnapshot)}`);
      return sharedSnapshot;
    }
    if (this.processName !== MAIN_PROCESS_NAME) {
      const preferenceSnapshot = await this.readPreferencesSnapshot(context);
      if (preferenceSnapshot) {
        this.lastPersisted = copyImeSettings(preferenceSnapshot);
        LOGGER.info(`settings preferences fallback loaded: process=${this.processName}, ` +
          `${this.describe(preferenceSnapshot)}`);
        return preferenceSnapshot;
      }
      LOGGER.info(`settings snapshot unavailable; using defaults: process=${this.processName}`);
      return copyImeSettings(DEFAULT_IME_SETTINGS);
    }
    try {
      const storage = await this.openPreferences(context);
      const raw = await this.readRaw(storage);
      if (!raw.keyboardProfileId) {
        raw.legacyKeyboardLayout = await this.readLegacyKeyboardLayout(context);
      }
      const normalized = this.validator.validate(this.migration.migrate(raw));
      await this.writeRaw(storage, settingsToRaw(normalized));
      await storage.flush();
      try {
        await this.writeSharedSnapshot(normalized);
      } catch (snapshotErr) {
        LOGGER.warn(`settings snapshot refresh failed: ${JSON.stringify(snapshotErr)}`);
      }
      this.lastPersisted = copyImeSettings(normalized);
      LOGGER.info(`settings loaded: process=${this.processName}, ${this.describe(normalized)}`);
      return normalized;
    } catch (err) {
      this.storage = undefined;
      LOGGER.warn(`settings load failed; using defaults: process=${this.processName}, error=${JSON.stringify(err)}`);
      return copyImeSettings(DEFAULT_IME_SETTINGS);
    }
  }

  async save(settings: ImeSettings): Promise<boolean> {
    const previous = copyImeSettings(this.lastPersisted ?? DEFAULT_IME_SETTINGS);
    if (this.processName !== MAIN_PROCESS_NAME) {
      try {
        await this.writeSharedSnapshot(settings);
        this.lastPersisted = copyImeSettings(settings);
        LOGGER.info(`settings saved: process=${this.processName}, ${this.describe(settings)}`);
        return true;
      } catch (err) {
        try {
          await this.writeSharedSnapshot(previous);
        } catch (rollbackErr) {
          LOGGER.warn(`settings snapshot rollback failed: ${JSON.stringify(rollbackErr)}`);
        }
        LOGGER.warn(`settings save failed: ${JSON.stringify(err)}`);
        return false;
      }
    }
    if (!this.storage) {
      LOGGER.warn('settings save skipped because storage is not initialized');
      return false;
    }
    try {
      await this.writeRaw(this.storage, settingsToRaw(settings));
      await this.storage.flush();
      await this.writeSharedSnapshot(settings);
      this.lastPersisted = copyImeSettings(settings);
      LOGGER.info(`settings saved: process=${this.processName}, ${this.describe(settings)}`);
      return true;
    } catch (err) {
      try {
        await this.writeRaw(this.storage, settingsToRaw(previous));
        await this.storage.flush();
        await this.writeSharedSnapshot(previous);
      } catch (rollbackErr) {
        LOGGER.warn(`settings persistence rollback failed: ${JSON.stringify(rollbackErr)}`);
      }
      LOGGER.warn(`settings save failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  async reset(): Promise<boolean> {
    return this.save(copyImeSettings(DEFAULT_IME_SETTINGS));
  }

  private async readString(storage: preferences.Preferences, key: string): Promise<string | undefined> {
    const value = await storage.get(key, '');
    return typeof value === 'string' && value.length > 0 ? value : undefined;
  }

  private async readRaw(storage: preferences.Preferences): Promise<SettingsRaw> {
    return {
      schemaVersion: await this.readString(storage, KEYS.SCHEMA_VERSION),
      keyboardProfileId: await this.readString(storage, KEYS.KEYBOARD_PROFILE_ID),
      schemeId: await this.readString(storage, KEYS.SCHEME_ID),
      themeMode: await this.readString(storage, KEYS.THEME_MODE),
      keyboardHeightMode: await this.readString(storage, KEYS.KEYBOARD_HEIGHT_MODE),
      candidateFontSizeMode: await this.readString(storage, KEYS.CANDIDATE_FONT_SIZE_MODE),
      hapticLevel: await this.readString(storage, KEYS.HAPTIC_LEVEL),
      keySoundEnabled: await this.readString(storage, KEYS.KEY_SOUND_ENABLED),
      userLearningEnabled: await this.readString(storage, KEYS.USER_LEARNING_ENABLED),
      spellingCorrectionEnabled: await this.readString(storage, KEYS.SPELLING_CORRECTION_ENABLED),
      fuzzyOptions: await this.readString(storage, KEYS.FUZZY_OPTIONS),
      inputPresentationPreference: await this.readString(storage, KEYS.INPUT_PRESENTATION_PREFERENCE),
      candidatePresentationMode: await this.readString(storage, KEYS.CANDIDATE_PRESENTATION_MODE),
      xiaoheYinxingHintCandidateCount: await this.readString(
        storage,
        KEYS.XIAOHE_YINXING_HINT_CANDIDATE_COUNT
      ),
      xiaoheYinxingCategorySchemaVersion: await this.readString(
        storage,
        KEYS.XIAOHE_YINXING_CATEGORY_SCHEMA_VERSION
      ),
      xiaoheYinxingEnabledCategoryIds: await this.readString(
        storage,
        KEYS.XIAOHE_YINXING_ENABLED_CATEGORY_IDS
      ),
      lexiconSources: await this.readString(storage, KEYS.LEXICON_SOURCES),
      darkMode: await this.readString(storage, KEYS.LEGACY_DARK_MODE),
      keyboardScale: await this.readString(storage, KEYS.LEGACY_KEYBOARD_SCALE),
      candidateFontScale: await this.readString(storage, KEYS.LEGACY_CANDIDATE_FONT_SCALE),
      vibrationEnabled: await this.readString(storage, KEYS.LEGACY_VIBRATION_ENABLED)
    };
  }

  private async writeRaw(storage: preferences.Preferences, raw: SettingsRaw): Promise<void> {
    await storage.put(KEYS.SCHEMA_VERSION, raw.schemaVersion ?? '');
    await storage.put(KEYS.KEYBOARD_PROFILE_ID, raw.keyboardProfileId ?? '');
    await storage.put(KEYS.SCHEME_ID, raw.schemeId ?? '');
    await storage.put(KEYS.THEME_MODE, raw.themeMode ?? '');
    await storage.put(KEYS.KEYBOARD_HEIGHT_MODE, raw.keyboardHeightMode ?? '');
    await storage.put(KEYS.CANDIDATE_FONT_SIZE_MODE, raw.candidateFontSizeMode ?? '');
    await storage.put(KEYS.HAPTIC_LEVEL, raw.hapticLevel ?? '');
    await storage.put(KEYS.KEY_SOUND_ENABLED, raw.keySoundEnabled ?? '');
    await storage.put(KEYS.USER_LEARNING_ENABLED, raw.userLearningEnabled ?? '');
    await storage.put(KEYS.SPELLING_CORRECTION_ENABLED, raw.spellingCorrectionEnabled ?? '');
    await storage.put(KEYS.FUZZY_OPTIONS, raw.fuzzyOptions ?? '');
    await storage.put(KEYS.INPUT_PRESENTATION_PREFERENCE, raw.inputPresentationPreference ?? '');
    await storage.put(KEYS.CANDIDATE_PRESENTATION_MODE, raw.candidatePresentationMode ?? '');
    await storage.put(
      KEYS.XIAOHE_YINXING_HINT_CANDIDATE_COUNT,
      raw.xiaoheYinxingHintCandidateCount ?? ''
    );
    await storage.put(
      KEYS.XIAOHE_YINXING_CATEGORY_SCHEMA_VERSION,
      raw.xiaoheYinxingCategorySchemaVersion ?? ''
    );
    await storage.put(
      KEYS.XIAOHE_YINXING_ENABLED_CATEGORY_IDS,
      raw.xiaoheYinxingEnabledCategoryIds ?? ''
    );
    await storage.put(KEYS.LEXICON_SOURCES, raw.lexiconSources ?? '');
  }

  private async openSharedStorage(): Promise<void> {
    try {
      this.sharedStorage = await dataShare.createDataProxyHandle();
    } catch (err) {
      this.sharedStorage = undefined;
      LOGGER.warn(`settings shared storage open failed: ${JSON.stringify(err)}`);
    }
  }

  private async openPreferences(context: common.Context): Promise<preferences.Preferences> {
    const options: preferences.Options = { name: PREFERENCES_NAME };
    preferences.removePreferencesFromCacheSync(context, options);
    const storage = await preferences.getPreferences(context, options);
    this.storage = storage;
    return storage;
  }

  private async readPreferencesSnapshot(context: common.Context): Promise<ImeSettings | undefined> {
    try {
      const options: preferences.Options = { name: PREFERENCES_NAME };
      preferences.removePreferencesFromCacheSync(context, options);
      const storage = await preferences.getPreferences(context, options);
      const raw = await this.readRaw(storage);
      if (!raw.keyboardProfileId) {
        raw.legacyKeyboardLayout = await this.readLegacyKeyboardLayout(context);
      }
      return this.validator.validate(this.migration.migrate(raw));
    } catch (err) {
      LOGGER.warn(`settings preferences fallback failed: ${JSON.stringify(err)}`);
      return undefined;
    }
  }

  private async readSharedSnapshot(context: common.Context): Promise<ImeSettings | undefined> {
    if (!this.sharedStorage) {
      return undefined;
    }
    try {
      const results = await this.sharedStorage.get([SHARED_SETTINGS_URI], SHARED_SETTINGS_CONFIG);
      if (results.length !== 1 ||
        results[0].result !== dataShare.DataProxyErrorCode.SUCCESS ||
        typeof results[0].value !== 'string') {
        return undefined;
      }
      const record = results[0].value;
      const raw = this.recordCodec.decode(record);
      if (!raw.keyboardProfileId) {
        raw.legacyKeyboardLayout = await this.readLegacyKeyboardLayout(context);
      }
      return this.validator.validate(this.migration.migrate(raw));
    } catch (err) {
      LOGGER.warn(`settings snapshot read failed: ${JSON.stringify(err)}`);
      return undefined;
    }
  }

  private async writeSharedSnapshot(settings: ImeSettings): Promise<void> {
    if (!this.sharedStorage) {
      throw new Error('settings shared storage is unavailable');
    }
    const record = this.recordCodec.encode(settings);
    try {
      const results = await this.sharedStorage.publish([{
        uri: SHARED_SETTINGS_URI,
        value: record,
        allowList: []
      }], SHARED_SETTINGS_CONFIG);
      if (results.length !== 1 || results[0].result !== dataShare.DataProxyErrorCode.SUCCESS) {
        throw new Error('shared settings publish was rejected');
      }
    } catch (err) {
      const detail = err instanceof Error ? err.message : JSON.stringify(err);
      throw new Error(`settings snapshot write failed: ${detail}`);
    }
  }

  private async readLegacyKeyboardLayout(context: common.Context): Promise<string | undefined> {
    try {
      const options: preferences.Options = { name: LEGACY_LAYOUT_PREFERENCES_NAME };
      preferences.removePreferencesFromCacheSync(context, options);
      const storage = await preferences.getPreferences(context, options);
      return this.readString(storage, LEGACY_LAYOUT_KEY);
    } catch (err) {
      LOGGER.warn(`legacy keyboard layout read failed: ${JSON.stringify(err)}`);
      return undefined;
    }
  }

  private describe(settings: ImeSettings): string {
    return `schemaVersion=${settings.schemaVersion}, keyboardProfileId=${settings.keyboardProfileId}, ` +
      `schemeId=${settings.schemeId}, ` +
      `themeMode=${settings.themeMode}, keyboardHeightMode=${settings.keyboardHeightMode}, ` +
      `candidateFontSizeMode=${settings.candidateFontSizeMode}, hapticLevel=${settings.hapticLevel}, ` +
      `keySoundEnabled=${settings.keySoundEnabled}, userLearningEnabled=${settings.userLearningEnabled}, ` +
      `inputPresentationPreference=${settings.inputPresentationPreference}, ` +
      `candidatePresentationMode=${settings.candidatePresentationMode}, ` +
      `xiaoheYinxingHintCandidateCount=${settings.xiaoheYinxingHintCandidateCount}, ` +
      `xiaoheYinxingCategorySchemaVersion=${settings.xiaoheYinxingCategorySchemaVersion}, ` +
      `xiaoheYinxingEnabledCategoryCount=${settings.xiaoheYinxingEnabledCategoryIds.length}`;
  }
}
