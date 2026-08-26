import {
  CandidateFontSizeMode,
  CandidatePresentationMode,
  CURRENT_SETTINGS_SCHEMA_VERSION,
  DEFAULT_AI_ACTIONS,
  DEFAULT_IME_SETTINGS,
  HapticLevel,
  ImeSettings,
  KeyboardHeightMode,
  LexiconSourceConfig,
  normalizeXiaoheYinxingCategoryIds,
  QUANPIN_FUZZY_OPTIONS,
  QuanpinFuzzyOption,
  PunctuationMode,
  SettingsRaw,
  ThemeMode,
  XIAOHE_YINXING_CATEGORY_SCHEMA_VERSION
} from '../../domain/settings/ImeSettings';
import { InputPresentationPreference } from '../../domain/display/InputPresentationMode';
import {
  keyboardProfileForLegacy,
  keyboardProfileEngineSchemeId,
  normalizeKeyboardProfileId
} from '../../domain/keyboard/KeyboardProfile';

export class SettingsValidator {
  validate(raw: SettingsRaw): ImeSettings {
    const keyboardProfileId = normalizeKeyboardProfileId(
      raw.keyboardProfileId ?? keyboardProfileForLegacy(raw.schemeId, raw.legacyKeyboardLayout)
    );
    return {
      schemaVersion: CURRENT_SETTINGS_SCHEMA_VERSION,
      keyboardProfileId,
      schemeId: keyboardProfileEngineSchemeId(keyboardProfileId),
      themeMode: this.theme(raw.themeMode),
      keyboardHeightMode: this.height(raw.keyboardHeightMode),
      candidateFontSizeMode: this.candidateFont(raw.candidateFontSizeMode),
      hapticLevel: this.haptic(raw.hapticLevel),
      keySoundEnabled: this.booleanValue(raw.keySoundEnabled, DEFAULT_IME_SETTINGS.keySoundEnabled),
      userLearningEnabled: this.booleanValue(
        raw.userLearningEnabled,
        DEFAULT_IME_SETTINGS.userLearningEnabled
      ),
      aiEnabled: this.booleanValue(raw.aiEnabled, DEFAULT_IME_SETTINGS.aiEnabled),
      localAssociationEnabled: this.booleanValue(
        raw.localAssociationEnabled,
        DEFAULT_IME_SETTINGS.localAssociationEnabled
      ),
      cloudAiEnabled: this.booleanValue(raw.cloudAiEnabled, DEFAULT_IME_SETTINGS.cloudAiEnabled),
      cloudAiConsentVersion: this.nonNegativeInteger(
        raw.cloudAiConsentVersion,
        DEFAULT_IME_SETTINGS.cloudAiConsentVersion
      ),
      preferredAiActions: this.preferredAiActions(raw.preferredAiActions),
      voiceInputEnabled: this.booleanValue(
        raw.voiceInputEnabled,
        DEFAULT_IME_SETTINGS.voiceInputEnabled
      ),
      voiceLanguage: raw.voiceLanguage === 'zh-CN' ? raw.voiceLanguage : DEFAULT_IME_SETTINGS.voiceLanguage,
      voiceAutoCommit: this.booleanValue(raw.voiceAutoCommit, DEFAULT_IME_SETTINGS.voiceAutoCommit),
      voiceCloudConsentVersion: this.nonNegativeInteger(
        raw.voiceCloudConsentVersion,
        DEFAULT_IME_SETTINGS.voiceCloudConsentVersion
      ),
      voicePunctuationEnabled: this.booleanValue(
        raw.voicePunctuationEnabled,
        DEFAULT_IME_SETTINGS.voicePunctuationEnabled
      ),
      spellingCorrectionEnabled: this.booleanValue(
        raw.spellingCorrectionEnabled,
        DEFAULT_IME_SETTINGS.spellingCorrectionEnabled
      ),
      fuzzyOptions: this.fuzzyOptions(raw.fuzzyOptions),
      smartPeriodTimeoutMs: this.smartPeriodTimeout(raw.smartPeriodTimeoutMs),
      punctuationMode: raw.punctuationMode === PunctuationMode.ENGLISH ?
        PunctuationMode.ENGLISH : PunctuationMode.CHINESE,
      fullWidthEnabled: this.booleanValue(raw.fullWidthEnabled, DEFAULT_IME_SETTINGS.fullWidthEnabled),
      numericPeriodEnabled: this.booleanValue(
        raw.numericPeriodEnabled,
        DEFAULT_IME_SETTINGS.numericPeriodEnabled
      ),
      traditionalOutputEnabled: this.booleanValue(
        raw.traditionalOutputEnabled,
        DEFAULT_IME_SETTINGS.traditionalOutputEnabled
      ),
      codeTableEmptyClearLength: this.approvedInteger(
        raw.codeTableEmptyClearLength,
        [4, 12],
        DEFAULT_IME_SETTINGS.codeTableEmptyClearLength
      ),
      codeTableAutoCommitEnabled: this.booleanValue(
        raw.codeTableAutoCommitEnabled,
        DEFAULT_IME_SETTINGS.codeTableAutoCommitEnabled
      ),
      inputPresentationPreference: this.inputPresentationPreference(raw.inputPresentationPreference),
      candidatePresentationMode: this.candidatePresentation(raw.candidatePresentationMode),
      xiaoheYinxingCategorySchemaVersion: XIAOHE_YINXING_CATEGORY_SCHEMA_VERSION,
      xiaoheYinxingEnabledCategoryIds: this.yinxingCategories(raw.xiaoheYinxingEnabledCategoryIds),
      lexiconSources: this.lexiconSources(raw.lexiconSources)
    };
  }

  private fuzzyOptions(value?: string): QuanpinFuzzyOption[] {
    if (!value) {
      return [];
    }
    try {
      const parsed: Object[] = JSON.parse(value) as Object[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      const requested: Set<string> = new Set<string>();
      parsed.forEach((item: Object) => {
        if (typeof item === 'string' && QUANPIN_FUZZY_OPTIONS.indexOf(item as QuanpinFuzzyOption) >= 0) {
          requested.add(item as string);
        }
      });
      return QUANPIN_FUZZY_OPTIONS.filter((option: QuanpinFuzzyOption): boolean => requested.has(option));
    } catch (_err) {
      return [];
    }
  }

  private preferredAiActions(value?: string): string[] {
    if (!value) {
      return DEFAULT_AI_ACTIONS.slice();
    }
    try {
      const parsed: Object[] = JSON.parse(value) as Object[];
      if (!Array.isArray(parsed)) {
        return DEFAULT_AI_ACTIONS.slice();
      }
      const requested: Set<string> = new Set<string>();
      parsed.forEach((item: Object): void => {
        if (typeof item === 'string' && DEFAULT_AI_ACTIONS.indexOf(item as string) >= 0) {
          requested.add(item as string);
        }
      });
      const actions = DEFAULT_AI_ACTIONS.filter((action: string): boolean => requested.has(action));
      return actions.length > 0 ? actions : DEFAULT_AI_ACTIONS.slice();
    } catch (_err) {
      return DEFAULT_AI_ACTIONS.slice();
    }
  }

  private nonNegativeInteger(value: string | undefined, defaultValue: number): number {
    if (!value) {
      return defaultValue;
    }
    const parsed = Number(value);
    return Number.isInteger(parsed) && parsed >= 0 ? parsed : defaultValue;
  }

  private approvedInteger(value: string | undefined, approved: number[], defaultValue: number): number {
    const parsed = Number(value);
    return Number.isInteger(parsed) && approved.indexOf(parsed) >= 0 ? parsed : defaultValue;
  }

  private inputPresentationPreference(value?: string): InputPresentationPreference {
    if (value === InputPresentationPreference.AUTO ||
      value === InputPresentationPreference.TOUCH ||
      value === InputPresentationPreference.HARDWARE) {
      return value as InputPresentationPreference;
    }
    return DEFAULT_IME_SETTINGS.inputPresentationPreference;
  }

  private smartPeriodTimeout(value?: string): number {
    if (!value) {
      return DEFAULT_IME_SETTINGS.smartPeriodTimeoutMs;
    }
    const parsed = Number(value);
    if (!Number.isInteger(parsed) || parsed < 0 || parsed > 2000) {
      return DEFAULT_IME_SETTINGS.smartPeriodTimeoutMs;
    }
    return parsed;
  }

  private yinxingCategories(value?: string): string[] {
    if (!value) {
      return DEFAULT_IME_SETTINGS.xiaoheYinxingEnabledCategoryIds.slice();
    }
    try {
      const parsed: Object[] = JSON.parse(value) as Object[];
      if (!Array.isArray(parsed)) {
        return DEFAULT_IME_SETTINGS.xiaoheYinxingEnabledCategoryIds.slice();
      }
      const ids: string[] = [];
      parsed.forEach((id: Object) => {
        if (typeof id === 'string') {
          ids.push(id as string);
        }
      });
      return normalizeXiaoheYinxingCategoryIds(ids);
    } catch (_err) {
      return DEFAULT_IME_SETTINGS.xiaoheYinxingEnabledCategoryIds.slice();
    }
  }

  private candidatePresentation(value?: string): CandidatePresentationMode {
    if (value === CandidatePresentationMode.BAR ||
      value === CandidatePresentationMode.FLOATING ||
      value === CandidatePresentationMode.AUTO) {
      return value as CandidatePresentationMode;
    }
    return DEFAULT_IME_SETTINGS.candidatePresentationMode;
  }

  private theme(value?: string): ThemeMode {
    if (value === ThemeMode.LIGHT || value === ThemeMode.DARK || value === ThemeMode.FOLLOW_SYSTEM) {
      return value as ThemeMode;
    }
    return DEFAULT_IME_SETTINGS.themeMode;
  }

  private height(value?: string): KeyboardHeightMode {
    if (value === KeyboardHeightMode.COMPACT || value === KeyboardHeightMode.STANDARD ||
      value === KeyboardHeightMode.TALL) {
      return value as KeyboardHeightMode;
    }
    return DEFAULT_IME_SETTINGS.keyboardHeightMode;
  }

  private candidateFont(value?: string): CandidateFontSizeMode {
    if (value === CandidateFontSizeMode.SMALL || value === CandidateFontSizeMode.STANDARD ||
      value === CandidateFontSizeMode.LARGE) {
      return value as CandidateFontSizeMode;
    }
    return DEFAULT_IME_SETTINGS.candidateFontSizeMode;
  }

  private haptic(value?: string): HapticLevel {
    if (value === HapticLevel.OFF || value === HapticLevel.LIGHT || value === HapticLevel.MEDIUM ||
      value === HapticLevel.STRONG) {
      return value as HapticLevel;
    }
    return DEFAULT_IME_SETTINGS.hapticLevel;
  }

  private booleanValue(value: string | undefined, defaultValue: boolean): boolean {
    if (value === 'true') {
      return true;
    }
    if (value === 'false') {
      return false;
    }
    return defaultValue;
  }

  private lexiconSources(value?: string): LexiconSourceConfig[] {
    if (!value) {
      return [];
    }
    try {
      const parsed: Object[] = JSON.parse(value) as Object[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      const sources: LexiconSourceConfig[] = [];
      const seenIds: string[] = [];
      parsed.forEach((item: Object) => {
        const obj = item as Record<string, Object>;
        if (typeof obj['id'] === 'string' &&
          typeof obj['displayName'] === 'string' &&
          typeof obj['filePath'] === 'string' &&
          typeof obj['enabled'] === 'boolean' &&
          typeof obj['priority'] === 'number' && Number.isInteger(obj['priority'] as number) &&
          (obj['priority'] as number) >= 0 &&
          (obj['mode'] === 'REPLACE' || obj['mode'] === 'APPEND' || obj['mode'] === 'MERGE') &&
          (obj['id'] as string).length > 0 && (obj['id'] as string).length <= 128 &&
          (obj['displayName'] as string).length > 0 && (obj['displayName'] as string).length <= 256 &&
          (obj['filePath'] as string).length > 0 && (obj['filePath'] as string).length <= 4096 &&
          seenIds.indexOf(obj['id'] as string) < 0) {
          seenIds.push(obj['id'] as string);
          sources.push({
            id: obj['id'] as string,
            displayName: obj['displayName'] as string,
            filePath: obj['filePath'] as string,
            enabled: obj['enabled'] as boolean,
            priority: obj['priority'] as number,
            mode: obj['mode'] as 'REPLACE' | 'APPEND' | 'MERGE'
          });
        }
      });
      return sources;
    } catch (_err) {
      return [];
    }
  }
}
