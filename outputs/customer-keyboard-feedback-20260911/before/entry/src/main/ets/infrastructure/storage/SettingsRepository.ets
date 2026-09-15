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
  KEYBOARD_STRUCTURE_ID: string;
  KEYBOARD_SKIN_ID: string;
  KEYBOARD_HEIGHT_MODE: string;
  KEYBOARD_FONT_SIZE: string;
  KEYBOARD_LIFT_LAYER_ENABLED: string;
  CANDIDATE_FONT_SIZE_MODE: string;
  CANDIDATE_FONT_SIZE: string;
  CANDIDATE_DISPLAY_COUNT: string;
  FLOATING_CANDIDATE_FONT_SIZE: string;
  KEY_SOUND_VOLUME: string;
  HAPTIC_LEVEL: string;
  KEY_SOUND_ENABLED: string;
  USER_LEARNING_ENABLED: string;
  AI_ENABLED: string;
  LOCAL_ASSOCIATION_ENABLED: string;
  CLOUD_AI_ENABLED: string;
  CLOUD_AI_CONSENT_VERSION: string;
  PREFERRED_AI_ACTIONS: string;
  VOICE_INPUT_ENABLED: string;
  VOICE_LANGUAGE: string;
  VOICE_AUTO_COMMIT: string;
  VOICE_CLOUD_CONSENT_VERSION: string;
  VOICE_PUNCTUATION_ENABLED: string;
  SPELLING_CORRECTION_ENABLED: string;
  FUZZY_OPTIONS: string;
  SMART_PERIOD_TIMEOUT_MS: string;
  LONG_PRESS_DURATION_MS: string;
  SMART_PUNCTUATION_SYMBOLS: string;
  CHINESE_LETTER_SWIPE_SYMBOLS: string;
  ENGLISH_LETTER_SWIPE_SYMBOLS: string;
  PUNCTUATION_MODE: string;
  FULL_WIDTH_ENABLED: string;
  NUMERIC_PERIOD_ENABLED: string;
  TRADITIONAL_OUTPUT_ENABLED: string;
  CODE_TABLE_EMPTY_CLEAR_LENGTH: string;
  CODE_TABLE_AUTO_COMMIT_ENABLED: string;
  CODE_TABLE_REVERSE_SPLIT_ENABLED: string;
  INPUT_PRESENTATION_PREFERENCE: string;
  CANDIDATE_PRESENTATION_MODE: string;
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
  KEYBOARD_STRUCTURE_ID: 'keyboard_structure_id',
  KEYBOARD_SKIN_ID: 'keyboard_skin_id',
  KEYBOARD_HEIGHT_MODE: 'keyboard_height_mode',
  KEYBOARD_FONT_SIZE: 'keyboard_font_size',
  KEYBOARD_LIFT_LAYER_ENABLED: 'keyboard_lift_layer_enabled',
  CANDIDATE_FONT_SIZE_MODE: 'candidate_font_size_mode',
  CANDIDATE_FONT_SIZE: 'candidate_font_size',
  CANDIDATE_DISPLAY_COUNT: 'candidate_display_count',
  FLOATING_CANDIDATE_FONT_SIZE: 'floating_candidate_font_size',
  KEY_SOUND_VOLUME: 'key_sound_volume',
  HAPTIC_LEVEL: 'haptic_level',
  KEY_SOUND_ENABLED: 'key_sound_enabled',
  USER_LEARNING_ENABLED: 'user_learning_enabled',
  AI_ENABLED: 'ai_enabled',
  LOCAL_ASSOCIATION_ENABLED: 'local_association_enabled',
  CLOUD_AI_ENABLED: 'cloud_ai_enabled',
  CLOUD_AI_CONSENT_VERSION: 'cloud_ai_consent_version',
  PREFERRED_AI_ACTIONS: 'preferred_ai_actions',
  VOICE_INPUT_ENABLED: 'voice_input_enabled',
  VOICE_LANGUAGE: 'voice_language',
  VOICE_AUTO_COMMIT: 'voice_auto_commit',
  VOICE_CLOUD_CONSENT_VERSION: 'voice_cloud_consent_version',
  VOICE_PUNCTUATION_ENABLED: 'voice_punctuation_enabled',
  SPELLING_CORRECTION_ENABLED: 'quanpin_spelling_correction_enabled',
  FUZZY_OPTIONS: 'quanpin_fuzzy_options',
  SMART_PERIOD_TIMEOUT_MS: 'smart_period_timeout_ms',
  LONG_PRESS_DURATION_MS: 'long_press_duration_ms',
  SMART_PUNCTUATION_SYMBOLS: 'smart_punctuation_symbols',
  CHINESE_LETTER_SWIPE_SYMBOLS: 'chinese_letter_swipe_symbols',
  ENGLISH_LETTER_SWIPE_SYMBOLS: 'english_letter_swipe_symbols',
  PUNCTUATION_MODE: 'punctuation_mode',
  FULL_WIDTH_ENABLED: 'full_width_enabled',
  NUMERIC_PERIOD_ENABLED: 'numeric_period_enabled',
  TRADITIONAL_OUTPUT_ENABLED: 'traditional_output_enabled',
  CODE_TABLE_EMPTY_CLEAR_LENGTH: 'code_table_empty_clear_length',
  CODE_TABLE_AUTO_COMMIT_ENABLED: 'code_table_auto_commit_enabled',
  CODE_TABLE_REVERSE_SPLIT_ENABLED: 'code_table_reverse_split_enabled',
  INPUT_PRESENTATION_PREFERENCE: 'input_presentation_preference',
  CANDIDATE_PRESENTATION_MODE: 'candidate_presentation_mode',
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
  private context?: common.Context;
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
    this.context = context;
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
      } catch (sharedErr) {
        const context = this.context;
        if (context) {
          try {
            const storage = await this.openPreferences(context);
            await this.writeRaw(storage, settingsToRaw(settings));
            await storage.flush();
            this.lastPersisted = copyImeSettings(settings);
            LOGGER.info(
              `settings saved to process-local fallback: process=${this.processName}, ${this.describe(settings)}`
            );
            return true;
          } catch (fallbackErr) {
            LOGGER.warn(`settings process-local fallback save failed: ${JSON.stringify(fallbackErr)}`);
          }
        }
        try {
          await this.writeSharedSnapshot(previous);
        } catch (rollbackErr) {
          LOGGER.warn(`settings snapshot rollback failed: ${JSON.stringify(rollbackErr)}`);
        }
        LOGGER.warn(`settings save failed: ${JSON.stringify(sharedErr)}`);
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
    try {
      const value = await storage.get(key, '');
      return typeof value === 'string' && value.length > 0 ? value : undefined;
    } catch (err) {
      throw new Error(`settings read failed for ${key}: ${JSON.stringify(err)}`);
    }
  }

  private async readRaw(storage: preferences.Preferences): Promise<SettingsRaw> {
    return {
      schemaVersion: await this.readString(storage, KEYS.SCHEMA_VERSION),
      keyboardProfileId: await this.readString(storage, KEYS.KEYBOARD_PROFILE_ID),
      schemeId: await this.readString(storage, KEYS.SCHEME_ID),
      themeMode: await this.readString(storage, KEYS.THEME_MODE),
      keyboardStructureId: await this.readString(storage, KEYS.KEYBOARD_STRUCTURE_ID),
      keyboardSkinId: await this.readString(storage, KEYS.KEYBOARD_SKIN_ID),
      keyboardHeightMode: await this.readString(storage, KEYS.KEYBOARD_HEIGHT_MODE),
      keyboardFontSize: await this.readString(storage, KEYS.KEYBOARD_FONT_SIZE),
      keyboardLiftLayerEnabled: await this.readString(storage, KEYS.KEYBOARD_LIFT_LAYER_ENABLED),
      candidateFontSizeMode: await this.readString(storage, KEYS.CANDIDATE_FONT_SIZE_MODE),
      candidateFontSize: await this.readString(storage, KEYS.CANDIDATE_FONT_SIZE),
      candidateDisplayCount: await this.readString(storage, KEYS.CANDIDATE_DISPLAY_COUNT),
      floatingCandidateFontSize: await this.readString(storage, KEYS.FLOATING_CANDIDATE_FONT_SIZE),
      keySoundVolume: await this.readString(storage, KEYS.KEY_SOUND_VOLUME),
      hapticLevel: await this.readString(storage, KEYS.HAPTIC_LEVEL),
      keySoundEnabled: await this.readString(storage, KEYS.KEY_SOUND_ENABLED),
      userLearningEnabled: await this.readString(storage, KEYS.USER_LEARNING_ENABLED),
      aiEnabled: await this.readString(storage, KEYS.AI_ENABLED),
      localAssociationEnabled: await this.readString(storage, KEYS.LOCAL_ASSOCIATION_ENABLED),
      cloudAiEnabled: await this.readString(storage, KEYS.CLOUD_AI_ENABLED),
      cloudAiConsentVersion: await this.readString(storage, KEYS.CLOUD_AI_CONSENT_VERSION),
      preferredAiActions: await this.readString(storage, KEYS.PREFERRED_AI_ACTIONS),
      voiceInputEnabled: await this.readString(storage, KEYS.VOICE_INPUT_ENABLED),
      voiceLanguage: await this.readString(storage, KEYS.VOICE_LANGUAGE),
      voiceAutoCommit: await this.readString(storage, KEYS.VOICE_AUTO_COMMIT),
      voiceCloudConsentVersion: await this.readString(storage, KEYS.VOICE_CLOUD_CONSENT_VERSION),
      voicePunctuationEnabled: await this.readString(storage, KEYS.VOICE_PUNCTUATION_ENABLED),
      spellingCorrectionEnabled: await this.readString(storage, KEYS.SPELLING_CORRECTION_ENABLED),
      fuzzyOptions: await this.readString(storage, KEYS.FUZZY_OPTIONS),
      smartPeriodTimeoutMs: await this.readString(storage, KEYS.SMART_PERIOD_TIMEOUT_MS),
      longPressDurationMs: await this.readString(storage, KEYS.LONG_PRESS_DURATION_MS),
      smartPunctuationSymbols: await this.readString(storage, KEYS.SMART_PUNCTUATION_SYMBOLS),
      chineseLetterSwipeSymbols: await this.readString(storage, KEYS.CHINESE_LETTER_SWIPE_SYMBOLS),
      englishLetterSwipeSymbols: await this.readString(storage, KEYS.ENGLISH_LETTER_SWIPE_SYMBOLS),
      punctuationMode: await this.readString(storage, KEYS.PUNCTUATION_MODE),
      fullWidthEnabled: await this.readString(storage, KEYS.FULL_WIDTH_ENABLED),
      numericPeriodEnabled: await this.readString(storage, KEYS.NUMERIC_PERIOD_ENABLED),
      traditionalOutputEnabled: await this.readString(storage, KEYS.TRADITIONAL_OUTPUT_ENABLED),
      codeTableEmptyClearLength: await this.readString(storage, KEYS.CODE_TABLE_EMPTY_CLEAR_LENGTH),
      codeTableAutoCommitEnabled: await this.readString(storage, KEYS.CODE_TABLE_AUTO_COMMIT_ENABLED),
      codeTableReverseSplitEnabled: await this.readString(storage, KEYS.CODE_TABLE_REVERSE_SPLIT_ENABLED),
      inputPresentationPreference: await this.readString(storage, KEYS.INPUT_PRESENTATION_PREFERENCE),
      candidatePresentationMode: await this.readString(storage, KEYS.CANDIDATE_PRESENTATION_MODE),
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
    await this.putString(storage, KEYS.SCHEMA_VERSION, raw.schemaVersion);
    await this.putString(storage, KEYS.KEYBOARD_PROFILE_ID, raw.keyboardProfileId);
    await this.putString(storage, KEYS.SCHEME_ID, raw.schemeId);
    await this.putString(storage, KEYS.THEME_MODE, raw.themeMode);
    await this.putString(storage, KEYS.KEYBOARD_STRUCTURE_ID, raw.keyboardStructureId);
    await this.putString(storage, KEYS.KEYBOARD_SKIN_ID, raw.keyboardSkinId);
    await this.putString(storage, KEYS.KEYBOARD_HEIGHT_MODE, raw.keyboardHeightMode);
    await this.putString(storage, KEYS.KEYBOARD_FONT_SIZE, raw.keyboardFontSize);
    await this.putString(storage, KEYS.KEYBOARD_LIFT_LAYER_ENABLED, raw.keyboardLiftLayerEnabled);
    await this.putString(storage, KEYS.CANDIDATE_FONT_SIZE_MODE, raw.candidateFontSizeMode);
    await this.putString(storage, KEYS.CANDIDATE_FONT_SIZE, raw.candidateFontSize);
    await this.putString(storage, KEYS.CANDIDATE_DISPLAY_COUNT, raw.candidateDisplayCount);
    await this.putString(storage, KEYS.FLOATING_CANDIDATE_FONT_SIZE, raw.floatingCandidateFontSize);
    await this.putString(storage, KEYS.KEY_SOUND_VOLUME, raw.keySoundVolume);
    await this.putString(storage, KEYS.HAPTIC_LEVEL, raw.hapticLevel);
    await this.putString(storage, KEYS.KEY_SOUND_ENABLED, raw.keySoundEnabled);
    await this.putString(storage, KEYS.USER_LEARNING_ENABLED, raw.userLearningEnabled);
    await this.putString(storage, KEYS.AI_ENABLED, raw.aiEnabled);
    await this.putString(storage, KEYS.LOCAL_ASSOCIATION_ENABLED, raw.localAssociationEnabled);
    await this.putString(storage, KEYS.CLOUD_AI_ENABLED, raw.cloudAiEnabled);
    await this.putString(storage, KEYS.CLOUD_AI_CONSENT_VERSION, raw.cloudAiConsentVersion);
    await this.putString(storage, KEYS.PREFERRED_AI_ACTIONS, raw.preferredAiActions);
    await this.putString(storage, KEYS.VOICE_INPUT_ENABLED, raw.voiceInputEnabled);
    await this.putString(storage, KEYS.VOICE_LANGUAGE, raw.voiceLanguage);
    await this.putString(storage, KEYS.VOICE_AUTO_COMMIT, raw.voiceAutoCommit);
    await this.putString(storage, KEYS.VOICE_CLOUD_CONSENT_VERSION, raw.voiceCloudConsentVersion);
    await this.putString(storage, KEYS.VOICE_PUNCTUATION_ENABLED, raw.voicePunctuationEnabled);
    await this.putString(storage, KEYS.SPELLING_CORRECTION_ENABLED, raw.spellingCorrectionEnabled);
    await this.putString(storage, KEYS.FUZZY_OPTIONS, raw.fuzzyOptions);
    await this.putString(storage, KEYS.SMART_PERIOD_TIMEOUT_MS, raw.smartPeriodTimeoutMs);
    await this.putString(storage, KEYS.LONG_PRESS_DURATION_MS, raw.longPressDurationMs);
    await this.putString(storage, KEYS.SMART_PUNCTUATION_SYMBOLS, raw.smartPunctuationSymbols);
    await this.putString(storage, KEYS.CHINESE_LETTER_SWIPE_SYMBOLS, raw.chineseLetterSwipeSymbols);
    await this.putString(storage, KEYS.ENGLISH_LETTER_SWIPE_SYMBOLS, raw.englishLetterSwipeSymbols);
    await this.putString(storage, KEYS.PUNCTUATION_MODE, raw.punctuationMode);
    await this.putString(storage, KEYS.FULL_WIDTH_ENABLED, raw.fullWidthEnabled);
    await this.putString(storage, KEYS.NUMERIC_PERIOD_ENABLED, raw.numericPeriodEnabled);
    await this.putString(storage, KEYS.TRADITIONAL_OUTPUT_ENABLED, raw.traditionalOutputEnabled);
    await this.putString(storage, KEYS.CODE_TABLE_EMPTY_CLEAR_LENGTH, raw.codeTableEmptyClearLength);
    await this.putString(storage, KEYS.CODE_TABLE_AUTO_COMMIT_ENABLED, raw.codeTableAutoCommitEnabled);
    await this.putString(storage, KEYS.CODE_TABLE_REVERSE_SPLIT_ENABLED, raw.codeTableReverseSplitEnabled);
    await this.putString(storage, KEYS.INPUT_PRESENTATION_PREFERENCE, raw.inputPresentationPreference);
    await this.putString(storage, KEYS.CANDIDATE_PRESENTATION_MODE, raw.candidatePresentationMode);
    await this.putString(
      storage,
      KEYS.XIAOHE_YINXING_CATEGORY_SCHEMA_VERSION,
      raw.xiaoheYinxingCategorySchemaVersion
    );
    await this.putString(
      storage,
      KEYS.XIAOHE_YINXING_ENABLED_CATEGORY_IDS,
      raw.xiaoheYinxingEnabledCategoryIds
    );
    await this.putString(storage, KEYS.LEXICON_SOURCES, raw.lexiconSources);
  }

  private async putString(
    storage: preferences.Preferences,
    key: string,
    value: string | undefined
  ): Promise<void> {
    try {
      await storage.put(key, value ?? '');
    } catch (err) {
      throw new Error(`settings write failed for ${key}: ${JSON.stringify(err)}`);
    }
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
    try {
      preferences.removePreferencesFromCacheSync(context, options);
      const storage = await preferences.getPreferences(context, options);
      this.storage = storage;
      return storage;
    } catch (err) {
      throw new Error(`settings storage open failed: ${JSON.stringify(err)}`);
    }
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
      `themeMode=${settings.themeMode}, keyboardStructureId=${settings.keyboardStructureId}, ` +
      `keyboardSkinId=${settings.keyboardSkinId}, keyboardHeightMode=${settings.keyboardHeightMode}, ` +
      `candidateFontSizeMode=${settings.candidateFontSizeMode}, hapticLevel=${settings.hapticLevel}, ` +
      `keySoundEnabled=${settings.keySoundEnabled}, userLearningEnabled=${settings.userLearningEnabled}, ` +
      `smartPeriodTimeoutMs=${settings.smartPeriodTimeoutMs}, ` +
      `longPressDurationMs=${settings.longPressDurationMs}, ` +
      `smartPunctuationSymbols=${JSON.stringify(settings.smartPunctuationSymbols)}, ` +
      `inputPresentationPreference=${settings.inputPresentationPreference}, ` +
      `candidatePresentationMode=${settings.candidatePresentationMode}, ` +
      `xiaoheYinxingCategorySchemaVersion=${settings.xiaoheYinxingCategorySchemaVersion}, ` +
      `xiaoheYinxingEnabledCategoryCount=${settings.xiaoheYinxingEnabledCategoryIds.length}`;
  }
}
