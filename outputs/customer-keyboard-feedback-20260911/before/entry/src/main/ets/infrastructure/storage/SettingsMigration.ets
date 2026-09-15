import {
  CURRENT_SETTINGS_SCHEMA_VERSION,
  DEFAULT_AI_ACTIONS,
  DEFAULT_LONG_PRESS_DURATION_MS,
  DEFAULT_SMART_PERIOD_TIMEOUT_MS,
  SettingsRaw,
  XIAOHE_YINXING_CATEGORY_IDS,
  XIAOHE_YINXING_DEFAULT_ENABLED_CATEGORY_IDS,
  XIAOHE_YINXING_CATEGORY_SCHEMA_VERSION
} from '../../domain/settings/ImeSettings';
import { keyboardProfileForLegacy } from '../../domain/keyboard/KeyboardProfile';
import { DEFAULT_SMART_PUNCTUATION_SYMBOLS } from '../../domain/keyboard/SmartPunctuation';
import {
  DEFAULT_CHINESE_LETTER_SWIPE_SYMBOLS,
  DEFAULT_ENGLISH_LETTER_SWIPE_SYMBOLS,
  hasOnlyEmptyLetterSwipeSymbols,
  LEGACY_ENGLISH_SINGLE_TILDE_LETTER_SWIPE_SYMBOLS,
  LEGACY_SHARED_LETTER_SWIPE_SYMBOLS,
  normalizeLetterSwipeSymbols
} from '../../domain/keyboard/LetterSwipeSymbols';

export class SettingsMigration {
  migrate(raw: SettingsRaw): SettingsRaw {
    const migrated: SettingsRaw = this.copyRaw(raw);
    const parsedVersion = Number.parseInt(raw.schemaVersion ?? '0');
    const isBeforeSwipePresetCorrection = !Number.isFinite(parsedVersion) || parsedVersion < 17;
    const isBeforeSmartSwipeWindowCorrection = !Number.isFinite(parsedVersion) || parsedVersion < 18;
    const isBeforeEnglishGSwipeCorrection = !Number.isFinite(parsedVersion) || parsedVersion < 19;

    if (!migrated.keyboardProfileId) {
      migrated.keyboardProfileId = keyboardProfileForLegacy(raw.schemeId, raw.legacyKeyboardLayout);
    }

    if (!Number.isFinite(parsedVersion) || parsedVersion <= 0) {
      if (!migrated.themeMode && raw.darkMode) {
        migrated.themeMode = raw.darkMode === 'true' ? 'dark' : 'light';
      }
      if (!migrated.keyboardHeightMode && raw.keyboardScale) {
        migrated.keyboardHeightMode = this.migrateHeight(raw.keyboardScale);
      }
      if (!migrated.candidateFontSizeMode && raw.candidateFontScale) {
        migrated.candidateFontSizeMode = this.migrateCandidateFont(raw.candidateFontScale);
      }
      if (!migrated.hapticLevel && raw.vibrationEnabled) {
        migrated.hapticLevel = raw.vibrationEnabled === 'false' ? 'off' : 'light';
      }
    }

    if (!migrated.xiaoheYinxingEnabledCategoryIds) {
      migrated.xiaoheYinxingEnabledCategoryIds = JSON.stringify(XIAOHE_YINXING_DEFAULT_ENABLED_CATEGORY_IDS);
    } else {
      const categoryVersion = Number.parseInt(raw.xiaoheYinxingCategorySchemaVersion ?? '0');
      if (!Number.isFinite(categoryVersion) || categoryVersion < 3) {
        migrated.xiaoheYinxingEnabledCategoryIds = this.enableNewYinxingCategories(
          migrated.xiaoheYinxingEnabledCategoryIds
        );
      }
      if (!Number.isFinite(categoryVersion) || categoryVersion < 4) {
        migrated.xiaoheYinxingEnabledCategoryIds = this.migrateLegacyDefaultCategories(
          migrated.xiaoheYinxingEnabledCategoryIds
        );
      }
      if (!Number.isFinite(categoryVersion) || categoryVersion < 5) {
        migrated.xiaoheYinxingEnabledCategoryIds = this.enableOkSpellingCategory(
          migrated.xiaoheYinxingEnabledCategoryIds
        );
      }
    }
    if (!migrated.spellingCorrectionEnabled) {
      migrated.spellingCorrectionEnabled = 'false';
    }
    if (!migrated.aiEnabled) {
      migrated.aiEnabled = 'false';
    }
    if (!migrated.localAssociationEnabled) {
      migrated.localAssociationEnabled = 'false';
    }
    if (!migrated.cloudAiEnabled) {
      migrated.cloudAiEnabled = 'false';
    }
    if (!migrated.cloudAiConsentVersion) {
      migrated.cloudAiConsentVersion = '0';
    }
    if (!migrated.preferredAiActions) {
      migrated.preferredAiActions = JSON.stringify(DEFAULT_AI_ACTIONS);
    }
    if (!migrated.voiceInputEnabled) {
      migrated.voiceInputEnabled = 'false';
    }
    if (!migrated.voiceLanguage) {
      migrated.voiceLanguage = 'zh-CN';
    }
    if (!migrated.voiceAutoCommit) {
      migrated.voiceAutoCommit = 'false';
    }
    if (!migrated.voiceCloudConsentVersion) {
      migrated.voiceCloudConsentVersion = '0';
    }
    if (!migrated.voicePunctuationEnabled) {
      migrated.voicePunctuationEnabled = 'true';
    }
    if (!migrated.fuzzyOptions) {
      migrated.fuzzyOptions = '[]';
    }
    if (!migrated.smartPeriodTimeoutMs ||
      (isBeforeSmartSwipeWindowCorrection && migrated.smartPeriodTimeoutMs === '500')) {
      migrated.smartPeriodTimeoutMs = `${DEFAULT_SMART_PERIOD_TIMEOUT_MS}`;
    }
    if (!migrated.longPressDurationMs) {
      migrated.longPressDurationMs = `${DEFAULT_LONG_PRESS_DURATION_MS}`;
    }
    if (migrated.smartPunctuationSymbols === undefined) {
      migrated.smartPunctuationSymbols = JSON.stringify(DEFAULT_SMART_PUNCTUATION_SYMBOLS);
    }
    if (migrated.chineseLetterSwipeSymbols === undefined ||
      (parsedVersion < 15 && hasOnlyEmptyLetterSwipeSymbols(migrated.chineseLetterSwipeSymbols)) ||
      (isBeforeSwipePresetCorrection &&
        normalizeLetterSwipeSymbols(migrated.chineseLetterSwipeSymbols) === LEGACY_SHARED_LETTER_SWIPE_SYMBOLS)) {
      migrated.chineseLetterSwipeSymbols = DEFAULT_CHINESE_LETTER_SWIPE_SYMBOLS;
    }
    if (migrated.englishLetterSwipeSymbols === undefined ||
      (parsedVersion < 15 && hasOnlyEmptyLetterSwipeSymbols(migrated.englishLetterSwipeSymbols)) ||
      (isBeforeSwipePresetCorrection &&
        normalizeLetterSwipeSymbols(migrated.englishLetterSwipeSymbols) === LEGACY_SHARED_LETTER_SWIPE_SYMBOLS) ||
      (isBeforeEnglishGSwipeCorrection &&
        normalizeLetterSwipeSymbols(migrated.englishLetterSwipeSymbols) ===
          LEGACY_ENGLISH_SINGLE_TILDE_LETTER_SWIPE_SYMBOLS)) {
      migrated.englishLetterSwipeSymbols = DEFAULT_ENGLISH_LETTER_SWIPE_SYMBOLS;
    }
    if (migrated.keyboardLiftLayerEnabled === undefined) {
      migrated.keyboardLiftLayerEnabled = 'true';
    }
    if (!migrated.punctuationMode) {
      migrated.punctuationMode = 'chinese';
    }
    if (!migrated.fullWidthEnabled) {
      migrated.fullWidthEnabled = 'false';
    }
    if (!migrated.numericPeriodEnabled) {
      migrated.numericPeriodEnabled = 'false';
    }
    if (!migrated.traditionalOutputEnabled) {
      migrated.traditionalOutputEnabled = 'false';
    }
    if (!migrated.codeTableEmptyClearLength) {
      migrated.codeTableEmptyClearLength = '4';
    }
    if (!migrated.codeTableAutoCommitEnabled) {
      migrated.codeTableAutoCommitEnabled = 'true';
    }
    if (!migrated.codeTableReverseSplitEnabled) {
      migrated.codeTableReverseSplitEnabled = 'false';
    }
    migrated.xiaoheYinxingCategorySchemaVersion = `${XIAOHE_YINXING_CATEGORY_SCHEMA_VERSION}`;
    migrated.schemaVersion = `${CURRENT_SETTINGS_SCHEMA_VERSION}`;
    return migrated;
  }

  private enableNewYinxingCategories(value: string): string {
    try {
      const parsed: Object[] = JSON.parse(value) as Object[];
      if (!Array.isArray(parsed)) {
        return JSON.stringify(XIAOHE_YINXING_CATEGORY_IDS);
      }
      const ids: string[] = [];
      parsed.forEach((item: Object) => {
        if (typeof item === 'string') {
          ids.push(item as string);
        }
      });
      if (ids.indexOf('quick-symbol') < 0) {
        ids.push('quick-symbol');
      }
      if (ids.indexOf('symbol') < 0) {
        ids.push('symbol');
      }
      if (ids.indexOf('symbol-group') < 0) {
        ids.push('symbol-group');
      }
      return JSON.stringify(ids);
    } catch (_err) {
      return JSON.stringify(XIAOHE_YINXING_CATEGORY_IDS);
    }
  }

  /**
   * Schema 3 enabled every category by default. Replace only that exact legacy
   * default profile; customized selections remain authoritative.
   */
  private migrateLegacyDefaultCategories(value: string): string {
    try {
      const parsed: Object[] = JSON.parse(value) as Object[];
      if (!Array.isArray(parsed)) {
        return JSON.stringify(XIAOHE_YINXING_DEFAULT_ENABLED_CATEGORY_IDS);
      }
      const legacyCategoryIds = XIAOHE_YINXING_CATEGORY_IDS.filter(
        (id: string): boolean => id !== 'ok-spelling'
      );
      const requested: Set<string> = new Set<string>();
      parsed.forEach((item: Object) => {
        if (typeof item === 'string' && legacyCategoryIds.indexOf(item as string) >= 0) {
          requested.add(item as string);
        }
      });
      const isLegacyDefault = requested.size === legacyCategoryIds.length &&
        legacyCategoryIds.every((id: string): boolean => requested.has(id));
      return isLegacyDefault ? JSON.stringify(XIAOHE_YINXING_DEFAULT_ENABLED_CATEGORY_IDS) : value;
    } catch (_err) {
      return JSON.stringify(XIAOHE_YINXING_DEFAULT_ENABLED_CATEGORY_IDS);
    }
  }

  private enableOkSpellingCategory(value: string): string {
    try {
      const parsed: Object[] = JSON.parse(value) as Object[];
      if (!Array.isArray(parsed)) {
        return JSON.stringify(XIAOHE_YINXING_DEFAULT_ENABLED_CATEGORY_IDS);
      }
      const ids: string[] = [];
      parsed.forEach((item: Object): void => {
        if (typeof item === 'string') {
          ids.push(item as string);
        }
      });
      if (ids.indexOf('ok-spelling') < 0) {
        ids.push('ok-spelling');
      }
      return JSON.stringify(ids);
    } catch (_err) {
      return JSON.stringify(XIAOHE_YINXING_DEFAULT_ENABLED_CATEGORY_IDS);
    }
  }

  private migrateHeight(value: string): string {
    if (value === '0' || value === 'compact') {
      return 'compact';
    }
    if (value === '2' || value === 'tall') {
      return 'tall';
    }
    return 'standard';
  }

  private migrateCandidateFont(value: string): string {
    if (value === '0' || value === 'small') {
      return 'small';
    }
    if (value === '2' || value === 'large') {
      return 'large';
    }
    return 'standard';
  }

  private copyRaw(raw: SettingsRaw): SettingsRaw {
    return {
      schemaVersion: raw.schemaVersion,
      keyboardProfileId: raw.keyboardProfileId,
      schemeId: raw.schemeId,
      legacyKeyboardLayout: raw.legacyKeyboardLayout,
      themeMode: raw.themeMode,
      keyboardStructureId: raw.keyboardStructureId,
      keyboardSkinId: raw.keyboardSkinId,
      keyboardHeightMode: raw.keyboardHeightMode,
      keyboardFontSize: raw.keyboardFontSize,
      keyboardLiftLayerEnabled: raw.keyboardLiftLayerEnabled,
      candidateFontSizeMode: raw.candidateFontSizeMode,
      candidateFontSize: raw.candidateFontSize,
      candidateDisplayCount: raw.candidateDisplayCount,
      floatingCandidateFontSize: raw.floatingCandidateFontSize,
      keySoundVolume: raw.keySoundVolume,
      hapticLevel: raw.hapticLevel,
      keySoundEnabled: raw.keySoundEnabled,
      userLearningEnabled: raw.userLearningEnabled,
      aiEnabled: raw.aiEnabled,
      localAssociationEnabled: raw.localAssociationEnabled,
      cloudAiEnabled: raw.cloudAiEnabled,
      cloudAiConsentVersion: raw.cloudAiConsentVersion,
      preferredAiActions: raw.preferredAiActions,
      voiceInputEnabled: raw.voiceInputEnabled,
      voiceLanguage: raw.voiceLanguage,
      voiceAutoCommit: raw.voiceAutoCommit,
      voiceCloudConsentVersion: raw.voiceCloudConsentVersion,
      voicePunctuationEnabled: raw.voicePunctuationEnabled,
      spellingCorrectionEnabled: raw.spellingCorrectionEnabled,
      fuzzyOptions: raw.fuzzyOptions,
      smartPeriodTimeoutMs: raw.smartPeriodTimeoutMs,
      longPressDurationMs: raw.longPressDurationMs,
      smartPunctuationSymbols: raw.smartPunctuationSymbols,
      chineseLetterSwipeSymbols: raw.chineseLetterSwipeSymbols,
      englishLetterSwipeSymbols: raw.englishLetterSwipeSymbols,
      punctuationMode: raw.punctuationMode,
      fullWidthEnabled: raw.fullWidthEnabled,
      numericPeriodEnabled: raw.numericPeriodEnabled,
      traditionalOutputEnabled: raw.traditionalOutputEnabled,
      codeTableEmptyClearLength: raw.codeTableEmptyClearLength,
      codeTableAutoCommitEnabled: raw.codeTableAutoCommitEnabled,
      codeTableReverseSplitEnabled: raw.codeTableReverseSplitEnabled,
      inputPresentationPreference: raw.inputPresentationPreference,
      candidatePresentationMode: raw.candidatePresentationMode,
      xiaoheYinxingCategorySchemaVersion: raw.xiaoheYinxingCategorySchemaVersion,
      xiaoheYinxingEnabledCategoryIds: raw.xiaoheYinxingEnabledCategoryIds,
      lexiconSources: raw.lexiconSources,
      darkMode: raw.darkMode,
      keyboardScale: raw.keyboardScale,
      candidateFontScale: raw.candidateFontScale,
      vibrationEnabled: raw.vibrationEnabled
    };
  }
}
