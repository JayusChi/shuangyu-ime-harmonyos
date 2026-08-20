import { InputPresentationPreference } from '../display/InputPresentationMode';
import {
  DEFAULT_KEYBOARD_PROFILE_ID,
  keyboardProfileEngineSchemeId
} from '../keyboard/KeyboardProfile';

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
  COMPACT = 'compact',
  STANDARD = 'standard',
  TALL = 'tall'
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
  keyboardHeightMode: KeyboardHeightMode;
  candidateFontSizeMode: CandidateFontSizeMode;
  hapticLevel: HapticLevel;
  keySoundEnabled: boolean;
  userLearningEnabled: boolean;
  spellingCorrectionEnabled: boolean;
  fuzzyOptions: QuanpinFuzzyOption[];
  inputPresentationPreference: InputPresentationPreference;
  candidatePresentationMode: CandidatePresentationMode;
  xiaoheYinxingHintCandidateCount: number;
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
  keyboardHeightMode?: string;
  candidateFontSizeMode?: string;
  hapticLevel?: string;
  keySoundEnabled?: string;
  userLearningEnabled?: string;
  spellingCorrectionEnabled?: string;
  fuzzyOptions?: string;
  inputPresentationPreference?: string;
  candidatePresentationMode?: string;
  xiaoheYinxingHintCandidateCount?: string;
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

export const CURRENT_SETTINGS_SCHEMA_VERSION: number = 7;
export const MIN_XIAOHE_YINXING_HINT_CANDIDATE_COUNT: number = 1;
export const MAX_XIAOHE_YINXING_HINT_CANDIDATE_COUNT: number = 9;
export const DEFAULT_XIAOHE_YINXING_HINT_CANDIDATE_COUNT: number = 9;
export const XIAOHE_YINXING_CATEGORY_SCHEMA_VERSION: number = 3;
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
  'full-code-character'
];
export const XIAOHE_YINXING_CATEGORY_UI_IDS: string[] = XIAOHE_YINXING_CATEGORY_IDS.filter(
  (id: string): boolean => id !== 'symbol-group'
);
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
  keyboardHeightMode: KeyboardHeightMode.STANDARD,
  candidateFontSizeMode: CandidateFontSizeMode.STANDARD,
  hapticLevel: HapticLevel.LIGHT,
  keySoundEnabled: false,
  userLearningEnabled: true,
  spellingCorrectionEnabled: false,
  fuzzyOptions: [],
  inputPresentationPreference: InputPresentationPreference.AUTO,
  candidatePresentationMode: CandidatePresentationMode.AUTO,
  xiaoheYinxingHintCandidateCount: DEFAULT_XIAOHE_YINXING_HINT_CANDIDATE_COUNT,
  xiaoheYinxingCategorySchemaVersion: XIAOHE_YINXING_CATEGORY_SCHEMA_VERSION,
  xiaoheYinxingEnabledCategoryIds: XIAOHE_YINXING_CATEGORY_IDS.slice(),
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
    keyboardHeightMode: settings.keyboardHeightMode,
    candidateFontSizeMode: settings.candidateFontSizeMode,
    hapticLevel: settings.hapticLevel,
    keySoundEnabled: settings.keySoundEnabled,
    userLearningEnabled: settings.userLearningEnabled,
    spellingCorrectionEnabled: settings.spellingCorrectionEnabled,
    fuzzyOptions: settings.fuzzyOptions.slice(),
    inputPresentationPreference: settings.inputPresentationPreference,
    candidatePresentationMode: settings.candidatePresentationMode,
    xiaoheYinxingHintCandidateCount: settings.xiaoheYinxingHintCandidateCount,
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
    left.keyboardHeightMode === right.keyboardHeightMode &&
    left.candidateFontSizeMode === right.candidateFontSizeMode &&
    left.hapticLevel === right.hapticLevel &&
    left.keySoundEnabled === right.keySoundEnabled &&
    left.userLearningEnabled === right.userLearningEnabled &&
    left.spellingCorrectionEnabled === right.spellingCorrectionEnabled &&
    left.fuzzyOptions.length === right.fuzzyOptions.length &&
    left.fuzzyOptions.every((option: QuanpinFuzzyOption, index: number): boolean =>
      option === right.fuzzyOptions[index]) &&
    left.inputPresentationPreference === right.inputPresentationPreference &&
    left.candidatePresentationMode === right.candidatePresentationMode &&
    left.xiaoheYinxingHintCandidateCount === right.xiaoheYinxingHintCandidateCount &&
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
    keyboardHeightMode: settings.keyboardHeightMode,
    candidateFontSizeMode: settings.candidateFontSizeMode,
    hapticLevel: settings.hapticLevel,
    keySoundEnabled: settings.keySoundEnabled ? 'true' : 'false',
    userLearningEnabled: settings.userLearningEnabled ? 'true' : 'false',
    spellingCorrectionEnabled: settings.spellingCorrectionEnabled ? 'true' : 'false',
    fuzzyOptions: JSON.stringify(settings.fuzzyOptions),
    inputPresentationPreference: settings.inputPresentationPreference,
    candidatePresentationMode: settings.candidatePresentationMode,
    xiaoheYinxingHintCandidateCount: `${settings.xiaoheYinxingHintCandidateCount}`,
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
  requested.add('core');
  return XIAOHE_YINXING_CATEGORY_IDS.filter((id: string) => requested.has(id));
}
