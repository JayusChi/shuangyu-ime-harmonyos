import { InputPresentationPreference } from '../display/InputPresentationMode';
import {
  DEFAULT_KEYBOARD_PROFILE_ID,
  keyboardProfileEngineSchemeId
} from '../keyboard/KeyboardProfile';
import {
  BUILTIN_KEYBOARD_SKIN_ID,
  BUILTIN_KEYBOARD_STRUCTURE_ID
} from '../customization/KeyboardCustomization';
import {
  DEFAULT_SMART_PUNCTUATION_SYMBOLS,
  normalizeSmartPunctuationSymbols
} from '../keyboard/SmartPunctuation';
import {
  DEFAULT_CHINESE_LETTER_SWIPE_SYMBOLS,
  DEFAULT_ENGLISH_LETTER_SWIPE_SYMBOLS,
  normalizeLetterSwipeSymbols
} from '../keyboard/LetterSwipeSymbols';

export enum ThemeMode {
  FOLLOW_SYSTEM = 'followSystem',
  LIGHT = 'light',
  DARK = 'dark'
}

export enum EffectiveTheme {
  LIGHT = 'light',
  DARK = 'dark'
}

export enum KeyboardHeightMode {
  EXTRA_COMPACT = 'extraCompact',
  SCALE_085 = 'scale085',
  SCALE_095 = 'scale095',
  SCALE_105 = 'scale105',
  SCALE_115 = 'scale115',
  COMPACT = 'compact',
  STANDARD = 'standard',
  TALL = 'tall',
  EXTRA_TALL = 'extraTall'
}

export const KEYBOARD_HEIGHT_MODE_OPTIONS: KeyboardHeightMode[] = [
  KeyboardHeightMode.EXTRA_COMPACT,
  KeyboardHeightMode.SCALE_085,
  KeyboardHeightMode.COMPACT,
  KeyboardHeightMode.SCALE_095,
  KeyboardHeightMode.STANDARD,
  KeyboardHeightMode.SCALE_105,
  KeyboardHeightMode.TALL,
  KeyboardHeightMode.SCALE_115,
  KeyboardHeightMode.EXTRA_TALL
];

export function keyboardHeightScale(mode: KeyboardHeightMode): number {
  const index = KEYBOARD_HEIGHT_MODE_OPTIONS.indexOf(mode);
  return index < 0 ? 1 : (80 + index * 5) / 100;
}

export const DEFAULT_CANDIDATE_FONT_SIZE = 15;
export const DEFAULT_CANDIDATE_DISPLAY_COUNT = 5;
export const MIN_CANDIDATE_DISPLAY_COUNT = 1;
export const MAX_CANDIDATE_DISPLAY_COUNT = 10;
export const DEFAULT_KEYBOARD_FONT_SIZE = 12;
export const MIN_KEYBOARD_FONT_SIZE = 8;
export const MAX_KEYBOARD_FONT_SIZE = 32;
export const DEFAULT_FLOATING_CANDIDATE_FONT_SIZE = 17;
export const MIN_CANDIDATE_FONT_SIZE = 10;
export const MAX_CANDIDATE_FONT_SIZE = 32;
export const DEFAULT_KEY_SOUND_VOLUME = 16;

export function legacyCandidateFontSize(mode: CandidateFontSizeMode, floating: boolean): number {
  if (mode === CandidateFontSizeMode.SMALL) { return 12; }
  if (mode === CandidateFontSizeMode.LARGE) { return 17; }
  return floating ? DEFAULT_FLOATING_CANDIDATE_FONT_SIZE : DEFAULT_CANDIDATE_FONT_SIZE;
}

export enum CandidateFontSizeMode {
  SMALL = 'small',
  STANDARD = 'standard',
  LARGE = 'large'
}

export enum HapticLevel {
  OFF = 'off',
  LIGHT = 'light',
  MEDIUM = 'medium',
  STRONG = 'strong'
}

/**
 * 候选展示模式。BAR 为固定键盘候选栏；FLOATING 在触屏模式表示输入框下方，
 * AUTO 保留给电脑实体键盘路线和旧设置兼容，不作为手机/平板设置页选项展示。
 */
export enum CandidatePresentationMode {
  BAR = 'bar',
  FLOATING = 'floating',
  AUTO = 'auto'
}

export enum PunctuationMode {
  CHINESE = 'chinese',
  ENGLISH = 'english'
}

export type LexiconImportMode = 'REPLACE' | 'APPEND' | 'MERGE';

export type QuanpinFuzzyOption = 'n_l' | 'z_zh' | 'c_ch' | 's_sh' |
  'in_ing' | 'en_eng' | 'an_ang' | 'ian_iang';

export const QUANPIN_FUZZY_OPTIONS: QuanpinFuzzyOption[] = [
  'n_l', 'z_zh', 'c_ch', 's_sh', 'in_ing', 'en_eng', 'an_ang', 'ian_iang'
];

export interface LexiconSourceConfig {
  id: string;
  displayName: string;
  filePath: string;
  enabled: boolean;
  priority: number;
  mode: LexiconImportMode;
}

export interface ImeSettings {
  schemaVersion: number;
  keyboardProfileId: string;
  schemeId: string;
  themeMode: ThemeMode;
  keyboardStructureId: string;
  keyboardSkinId: string;
  keyboardHeightMode: KeyboardHeightMode;
  keyboardFontSize: number;
  keyboardLiftLayerEnabled: boolean;
  candidateFontSizeMode: CandidateFontSizeMode;
  candidateFontSize: number;
  candidateDisplayCount: number;
  floatingCandidateFontSize: number;
  keySoundVolume: number;
  hapticLevel: HapticLevel;
  keySoundEnabled: boolean;
  userLearningEnabled: boolean;
  aiEnabled: boolean;
  localAssociationEnabled: boolean;
  cloudAiEnabled: boolean;
  cloudAiConsentVersion: number;
  preferredAiActions: string[];
  voiceInputEnabled: boolean;
  voiceLanguage: string;
  voiceAutoCommit: boolean;
  voiceCloudConsentVersion: number;
  voicePunctuationEnabled: boolean;
  spellingCorrectionEnabled: boolean;
  fuzzyOptions: QuanpinFuzzyOption[];
  smartPeriodTimeoutMs: number;
  longPressDurationMs: number;
  smartPunctuationSymbols: string;
  chineseLetterSwipeSymbols: string;
  englishLetterSwipeSymbols: string;
  punctuationMode: PunctuationMode;
  fullWidthEnabled: boolean;
  numericPeriodEnabled: boolean;
  traditionalOutputEnabled: boolean;
  codeTableEmptyClearLength: number;
  codeTableAutoCommitEnabled: boolean;
  codeTableReverseSplitEnabled: boolean;
  inputPresentationPreference: InputPresentationPreference;
  candidatePresentationMode: CandidatePresentationMode;
  xiaoheYinxingCategorySchemaVersion: number;
  xiaoheYinxingEnabledCategoryIds: string[];
  lexiconSources: LexiconSourceConfig[];
}

export interface SettingsRaw {
  schemaVersion?: string;
  keyboardProfileId?: string;
  schemeId?: string;
  legacyKeyboardLayout?: string;
  themeMode?: string;
  keyboardStructureId?: string;
  keyboardSkinId?: string;
  keyboardHeightMode?: string;
  keyboardFontSize?: string;
  keyboardLiftLayerEnabled?: string;
  candidateFontSizeMode?: string;
  candidateFontSize?: string;
  candidateDisplayCount?: string;
  floatingCandidateFontSize?: string;
  keySoundVolume?: string;
  hapticLevel?: string;
  keySoundEnabled?: string;
  userLearningEnabled?: string;
  aiEnabled?: string;
  localAssociationEnabled?: string;
  cloudAiEnabled?: string;
  cloudAiConsentVersion?: string;
  preferredAiActions?: string;
  voiceInputEnabled?: string;
  voiceLanguage?: string;
  voiceAutoCommit?: string;
  voiceCloudConsentVersion?: string;
  voicePunctuationEnabled?: string;
  spellingCorrectionEnabled?: string;
  fuzzyOptions?: string;
  smartPeriodTimeoutMs?: string;
  longPressDurationMs?: string;
  smartPunctuationSymbols?: string;
  chineseLetterSwipeSymbols?: string;
  englishLetterSwipeSymbols?: string;
  punctuationMode?: string;
  fullWidthEnabled?: string;
  numericPeriodEnabled?: string;
  traditionalOutputEnabled?: string;
  codeTableEmptyClearLength?: string;
  codeTableAutoCommitEnabled?: string;
  codeTableReverseSplitEnabled?: string;
  inputPresentationPreference?: string;
  candidatePresentationMode?: string;
  xiaoheYinxingCategorySchemaVersion?: string;
  xiaoheYinxingEnabledCategoryIds?: string;
  lexiconSources?: string;
  darkMode?: string;
  keyboardScale?: string;
  candidateFontScale?: string;
  vibrationEnabled?: string;
}

export interface ShuangpinSchemeOption {
  id: string;
  displayName: string;
}

export const CURRENT_SETTINGS_SCHEMA_VERSION: number = 23;
export const DEFAULT_AI_ACTIONS: string[] = ['continue', 'concise', 'polite', 'formal', 'translate'];
export const DEFAULT_SMART_PERIOD_TIMEOUT_MS: number = 300;
export const SMART_PERIOD_TIMEOUT_OPTIONS_MS: number[] = [0, 300, 500, 800, 1000];
export const DEFAULT_LONG_PRESS_DURATION_MS: number = 300;
export const MIN_LONG_PRESS_DURATION_MS: number = 150;
export const MAX_LONG_PRESS_DURATION_MS: number = 1000;
export const LONG_PRESS_DURATION_OPTIONS_MS: number[] = [200, 300, 500, 700];
export const XIAOHE_YINXING_CATEGORY_SCHEMA_VERSION: number = 5;
export const XIAOHE_YINXING_CATEGORY_IDS: string[] = [
  'core',
  'category-secondary',
  'quick-symbol',
  'one-key-secondary',
  'two-key-secondary',
  'out-of-table-character',
  'full-code-word',
  'symbol',
  'symbol-group',
  'rare-character',
  'full-code-character',
  'ok-spelling'
];
export const XIAOHE_YINXING_DEFAULT_DISABLED_CATEGORY_IDS: string[] = [
  'two-key-secondary',
  'full-code-word',
  'rare-character',
  'full-code-character'
];
export const XIAOHE_YINXING_DEFAULT_ENABLED_CATEGORY_IDS: string[] = XIAOHE_YINXING_CATEGORY_IDS.filter(
  (id: string): boolean => XIAOHE_YINXING_DEFAULT_DISABLED_CATEGORY_IDS.indexOf(id) < 0
);
export const XIAOHE_YINXING_CATEGORY_UI_IDS: string[] = [
  'core',
  'category-secondary',
  'one-key-secondary',
  'two-key-secondary',
  'symbol',
  'full-code-word',
  'rare-character',
  'full-code-character',
  'quick-symbol',
  'ok-spelling'
];
export const DEFAULT_SCHEME_ID: string = 'xiaohe';
export const QUANPIN_SCHEME_ID: string = 'quanpin';
export const PINYIN_9_SCHEME_ID: string = 'pinyin-9';
export const XIAOHE_YINXING_SCHEME_ID: string = 'xiaohe-yinxing';
export const AVAILABLE_SHUANGPIN_SCHEMES: ShuangpinSchemeOption[] = [
  { id: DEFAULT_SCHEME_ID, displayName: '小鹤双拼' },
  { id: QUANPIN_SCHEME_ID, displayName: '26 键全拼' },
  { id: PINYIN_9_SCHEME_ID, displayName: '9 键拼音' },
  { id: XIAOHE_YINXING_SCHEME_ID, displayName: '小鹤音形' }
];

export const DEFAULT_IME_SETTINGS: ImeSettings = {
  schemaVersion: CURRENT_SETTINGS_SCHEMA_VERSION,
  keyboardProfileId: DEFAULT_KEYBOARD_PROFILE_ID,
  schemeId: keyboardProfileEngineSchemeId(DEFAULT_KEYBOARD_PROFILE_ID),
  themeMode: ThemeMode.FOLLOW_SYSTEM,
  keyboardStructureId: BUILTIN_KEYBOARD_STRUCTURE_ID,
  keyboardSkinId: BUILTIN_KEYBOARD_SKIN_ID,
  keyboardHeightMode: KeyboardHeightMode.STANDARD,
  keyboardFontSize: DEFAULT_KEYBOARD_FONT_SIZE,
  keyboardLiftLayerEnabled: true,
  candidateFontSizeMode: CandidateFontSizeMode.STANDARD,
  candidateFontSize: DEFAULT_CANDIDATE_FONT_SIZE,
  candidateDisplayCount: DEFAULT_CANDIDATE_DISPLAY_COUNT,
  floatingCandidateFontSize: DEFAULT_FLOATING_CANDIDATE_FONT_SIZE,
  keySoundVolume: DEFAULT_KEY_SOUND_VOLUME,
  hapticLevel: HapticLevel.LIGHT,
  keySoundEnabled: false,
  userLearningEnabled: true,
  aiEnabled: false,
  localAssociationEnabled: false,
  cloudAiEnabled: false,
  cloudAiConsentVersion: 0,
  preferredAiActions: DEFAULT_AI_ACTIONS.slice(),
  voiceInputEnabled: false,
  voiceLanguage: 'zh-CN',
  voiceAutoCommit: false,
  voiceCloudConsentVersion: 0,
  voicePunctuationEnabled: true,
  spellingCorrectionEnabled: false,
  fuzzyOptions: [],
  smartPeriodTimeoutMs: DEFAULT_SMART_PERIOD_TIMEOUT_MS,
  longPressDurationMs: DEFAULT_LONG_PRESS_DURATION_MS,
  smartPunctuationSymbols: DEFAULT_SMART_PUNCTUATION_SYMBOLS,
  chineseLetterSwipeSymbols: DEFAULT_CHINESE_LETTER_SWIPE_SYMBOLS,
  englishLetterSwipeSymbols: DEFAULT_ENGLISH_LETTER_SWIPE_SYMBOLS,
  punctuationMode: PunctuationMode.CHINESE,
  fullWidthEnabled: false,
  numericPeriodEnabled: false,
  traditionalOutputEnabled: false,
  codeTableEmptyClearLength: 4,
  codeTableAutoCommitEnabled: true,
  codeTableReverseSplitEnabled: false,
  inputPresentationPreference: InputPresentationPreference.AUTO,
  candidatePresentationMode: CandidatePresentationMode.AUTO,
  xiaoheYinxingCategorySchemaVersion: XIAOHE_YINXING_CATEGORY_SCHEMA_VERSION,
  xiaoheYinxingEnabledCategoryIds: XIAOHE_YINXING_DEFAULT_ENABLED_CATEGORY_IDS.slice(),
  lexiconSources: []
};

export function isCandidatePresentationMode(value: string | undefined): boolean {
  return value === CandidatePresentationMode.BAR ||
    value === CandidatePresentationMode.FLOATING ||
    value === CandidatePresentationMode.AUTO;
}

/**
 * Resolves the only theme value presentation code should consume.
 * Unknown persisted values follow the same defaulting rule as SettingsValidator.
 */
export function resolveEffectiveTheme(themeMode: string | undefined, systemDarkMode: boolean): EffectiveTheme {
  if (themeMode === ThemeMode.DARK) {
    return EffectiveTheme.DARK;
  }
  if (themeMode === ThemeMode.LIGHT) {
    return EffectiveTheme.LIGHT;
  }
  return systemDarkMode ? EffectiveTheme.DARK : EffectiveTheme.LIGHT;
}

export function copyImeSettings(settings: ImeSettings): ImeSettings {
  return {
    schemaVersion: settings.schemaVersion,
    keyboardProfileId: settings.keyboardProfileId,
    schemeId: settings.schemeId,
    themeMode: settings.themeMode,
    keyboardStructureId: settings.keyboardStructureId,
    keyboardSkinId: settings.keyboardSkinId,
    keyboardHeightMode: settings.keyboardHeightMode,
    keyboardFontSize: settings.keyboardFontSize,
    keyboardLiftLayerEnabled: settings.keyboardLiftLayerEnabled,
    candidateFontSizeMode: settings.candidateFontSizeMode,
    candidateFontSize: settings.candidateFontSize,
    candidateDisplayCount: settings.candidateDisplayCount,
    floatingCandidateFontSize: settings.floatingCandidateFontSize,
    keySoundVolume: settings.keySoundVolume,
    hapticLevel: settings.hapticLevel,
    keySoundEnabled: settings.keySoundEnabled,
    userLearningEnabled: settings.userLearningEnabled,
    aiEnabled: settings.aiEnabled,
    localAssociationEnabled: settings.localAssociationEnabled,
    cloudAiEnabled: settings.cloudAiEnabled,
    cloudAiConsentVersion: settings.cloudAiConsentVersion,
    preferredAiActions: settings.preferredAiActions.slice(),
    voiceInputEnabled: settings.voiceInputEnabled,
    voiceLanguage: settings.voiceLanguage,
    voiceAutoCommit: settings.voiceAutoCommit,
    voiceCloudConsentVersion: settings.voiceCloudConsentVersion,
    voicePunctuationEnabled: settings.voicePunctuationEnabled,
    spellingCorrectionEnabled: settings.spellingCorrectionEnabled,
    fuzzyOptions: settings.fuzzyOptions.slice(),
    smartPeriodTimeoutMs: settings.smartPeriodTimeoutMs,
    longPressDurationMs: settings.longPressDurationMs,
    smartPunctuationSymbols: settings.smartPunctuationSymbols,
    chineseLetterSwipeSymbols: settings.chineseLetterSwipeSymbols,
    englishLetterSwipeSymbols: settings.englishLetterSwipeSymbols,
    punctuationMode: settings.punctuationMode,
    fullWidthEnabled: settings.fullWidthEnabled,
    numericPeriodEnabled: settings.numericPeriodEnabled,
    traditionalOutputEnabled: settings.traditionalOutputEnabled,
    codeTableEmptyClearLength: settings.codeTableEmptyClearLength,
    codeTableAutoCommitEnabled: settings.codeTableAutoCommitEnabled,
    codeTableReverseSplitEnabled: settings.codeTableReverseSplitEnabled,
    inputPresentationPreference: settings.inputPresentationPreference,
    candidatePresentationMode: settings.candidatePresentationMode,
    xiaoheYinxingCategorySchemaVersion: settings.xiaoheYinxingCategorySchemaVersion,
    xiaoheYinxingEnabledCategoryIds: settings.xiaoheYinxingEnabledCategoryIds.slice(),
    lexiconSources: settings.lexiconSources.map((src: LexiconSourceConfig): LexiconSourceConfig => ({
      id: src.id,
      displayName: src.displayName,
      filePath: src.filePath,
      enabled: src.enabled,
      priority: src.priority,
      mode: src.mode
    }))
  };
}

export function imeSettingsEqual(left: ImeSettings, right: ImeSettings): boolean {
  return left.schemaVersion === right.schemaVersion &&
    left.keyboardProfileId === right.keyboardProfileId &&
    left.schemeId === right.schemeId &&
    left.themeMode === right.themeMode &&
    left.keyboardStructureId === right.keyboardStructureId &&
    left.keyboardSkinId === right.keyboardSkinId &&
    left.keyboardHeightMode === right.keyboardHeightMode &&
    left.keyboardFontSize === right.keyboardFontSize &&
    left.keyboardLiftLayerEnabled === right.keyboardLiftLayerEnabled &&
    left.candidateFontSizeMode === right.candidateFontSizeMode &&
    left.candidateFontSize === right.candidateFontSize &&
    left.candidateDisplayCount === right.candidateDisplayCount &&
    left.floatingCandidateFontSize === right.floatingCandidateFontSize &&
    left.keySoundVolume === right.keySoundVolume &&
    left.hapticLevel === right.hapticLevel &&
    left.keySoundEnabled === right.keySoundEnabled &&
    left.userLearningEnabled === right.userLearningEnabled &&
    left.aiEnabled === right.aiEnabled &&
    left.localAssociationEnabled === right.localAssociationEnabled &&
    left.cloudAiEnabled === right.cloudAiEnabled &&
    left.cloudAiConsentVersion === right.cloudAiConsentVersion &&
    left.preferredAiActions.length === right.preferredAiActions.length &&
    left.preferredAiActions.every((action: string, index: number): boolean =>
      action === right.preferredAiActions[index]) &&
    left.voiceInputEnabled === right.voiceInputEnabled &&
    left.voiceLanguage === right.voiceLanguage &&
    left.voiceAutoCommit === right.voiceAutoCommit &&
    left.voiceCloudConsentVersion === right.voiceCloudConsentVersion &&
    left.voicePunctuationEnabled === right.voicePunctuationEnabled &&
    left.spellingCorrectionEnabled === right.spellingCorrectionEnabled &&
    left.smartPeriodTimeoutMs === right.smartPeriodTimeoutMs &&
    left.longPressDurationMs === right.longPressDurationMs &&
    left.smartPunctuationSymbols === right.smartPunctuationSymbols &&
    left.chineseLetterSwipeSymbols === right.chineseLetterSwipeSymbols &&
    left.englishLetterSwipeSymbols === right.englishLetterSwipeSymbols &&
    left.punctuationMode === right.punctuationMode &&
    left.fullWidthEnabled === right.fullWidthEnabled &&
    left.numericPeriodEnabled === right.numericPeriodEnabled &&
    left.traditionalOutputEnabled === right.traditionalOutputEnabled &&
    left.codeTableEmptyClearLength === right.codeTableEmptyClearLength &&
    left.codeTableAutoCommitEnabled === right.codeTableAutoCommitEnabled &&
    left.codeTableReverseSplitEnabled === right.codeTableReverseSplitEnabled &&
    left.fuzzyOptions.length === right.fuzzyOptions.length &&
    left.fuzzyOptions.every((option: QuanpinFuzzyOption, index: number): boolean =>
      option === right.fuzzyOptions[index]) &&
    left.inputPresentationPreference === right.inputPresentationPreference &&
    left.candidatePresentationMode === right.candidatePresentationMode &&
    left.xiaoheYinxingCategorySchemaVersion === right.xiaoheYinxingCategorySchemaVersion &&
    left.xiaoheYinxingEnabledCategoryIds.length === right.xiaoheYinxingEnabledCategoryIds.length &&
    left.xiaoheYinxingEnabledCategoryIds.every((id: string, index: number) =>
      id === right.xiaoheYinxingEnabledCategoryIds[index]) &&
    left.lexiconSources.length === right.lexiconSources.length &&
    left.lexiconSources.every((source: LexiconSourceConfig, index: number): boolean => {
      const other = right.lexiconSources[index];
      return source.id === other.id &&
        source.displayName === other.displayName &&
        source.filePath === other.filePath &&
        source.enabled === other.enabled &&
        source.priority === other.priority &&
        source.mode === other.mode;
    });
}

export function isAvailableScheme(schemeId: string): boolean {
  return AVAILABLE_SHUANGPIN_SCHEMES.some((scheme: ShuangpinSchemeOption) => scheme.id === schemeId);
}

export function settingsToRaw(settings: ImeSettings): SettingsRaw {
  return {
    schemaVersion: `${settings.schemaVersion}`,
    keyboardProfileId: settings.keyboardProfileId,
    schemeId: settings.schemeId,
    themeMode: settings.themeMode,
    keyboardStructureId: settings.keyboardStructureId,
    keyboardSkinId: settings.keyboardSkinId,
    keyboardHeightMode: settings.keyboardHeightMode,
    keyboardFontSize: `${settings.keyboardFontSize}`,
    keyboardLiftLayerEnabled: settings.keyboardLiftLayerEnabled ? 'true' : 'false',
    candidateFontSizeMode: settings.candidateFontSizeMode,
    candidateFontSize: `${settings.candidateFontSize}`,
    candidateDisplayCount: `${settings.candidateDisplayCount}`,
    floatingCandidateFontSize: `${settings.floatingCandidateFontSize}`,
    keySoundVolume: `${settings.keySoundVolume}`,
    hapticLevel: settings.hapticLevel,
    keySoundEnabled: settings.keySoundEnabled ? 'true' : 'false',
    userLearningEnabled: settings.userLearningEnabled ? 'true' : 'false',
    aiEnabled: settings.aiEnabled ? 'true' : 'false',
    localAssociationEnabled: settings.localAssociationEnabled ? 'true' : 'false',
    cloudAiEnabled: settings.cloudAiEnabled ? 'true' : 'false',
    cloudAiConsentVersion: `${settings.cloudAiConsentVersion}`,
    preferredAiActions: JSON.stringify(settings.preferredAiActions),
    voiceInputEnabled: settings.voiceInputEnabled ? 'true' : 'false',
    voiceLanguage: settings.voiceLanguage,
    voiceAutoCommit: settings.voiceAutoCommit ? 'true' : 'false',
    voiceCloudConsentVersion: `${settings.voiceCloudConsentVersion}`,
    voicePunctuationEnabled: settings.voicePunctuationEnabled ? 'true' : 'false',
    spellingCorrectionEnabled: settings.spellingCorrectionEnabled ? 'true' : 'false',
    fuzzyOptions: JSON.stringify(settings.fuzzyOptions),
    smartPeriodTimeoutMs: `${settings.smartPeriodTimeoutMs}`,
    longPressDurationMs: `${settings.longPressDurationMs}`,
    smartPunctuationSymbols: JSON.stringify(
      normalizeSmartPunctuationSymbols(settings.smartPunctuationSymbols)
    ),
    chineseLetterSwipeSymbols: normalizeLetterSwipeSymbols(settings.chineseLetterSwipeSymbols),
    englishLetterSwipeSymbols: normalizeLetterSwipeSymbols(settings.englishLetterSwipeSymbols),
    punctuationMode: settings.punctuationMode,
    fullWidthEnabled: settings.fullWidthEnabled ? 'true' : 'false',
    numericPeriodEnabled: settings.numericPeriodEnabled ? 'true' : 'false',
    traditionalOutputEnabled: settings.traditionalOutputEnabled ? 'true' : 'false',
    codeTableEmptyClearLength: `${settings.codeTableEmptyClearLength}`,
    codeTableAutoCommitEnabled: settings.codeTableAutoCommitEnabled ? 'true' : 'false',
    codeTableReverseSplitEnabled: settings.codeTableReverseSplitEnabled ? 'true' : 'false',
    inputPresentationPreference: settings.inputPresentationPreference,
    candidatePresentationMode: settings.candidatePresentationMode,
    xiaoheYinxingCategorySchemaVersion: `${settings.xiaoheYinxingCategorySchemaVersion}`,
    xiaoheYinxingEnabledCategoryIds: JSON.stringify(settings.xiaoheYinxingEnabledCategoryIds),
    lexiconSources: JSON.stringify(settings.lexiconSources)
  };
}

export function normalizeXiaoheYinxingCategoryIds(values: string[]): string[] {
  const requested: Set<string> = new Set<string>();
  values.forEach((id: string) => {
    if (XIAOHE_YINXING_CATEGORY_IDS.indexOf(id) >= 0) {
      requested.add(id);
    }
  });
  if (requested.has('category-secondary') || requested.has('out-of-table-character')) {
    requested.add('category-secondary');
    requested.add('out-of-table-character');
  }
  if (requested.has('symbol') || requested.has('symbol-group')) {
    requested.add('symbol');
    requested.add('symbol-group');
  }
  requested.add('core');
  return XIAOHE_YINXING_CATEGORY_IDS.filter((id: string) => requested.has(id));
}
