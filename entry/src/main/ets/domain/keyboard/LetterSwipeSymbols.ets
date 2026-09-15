export const LETTER_SWIPE_KEYS: string[] = 'qwertyuiopasdfghjklzxcvbnm'.split('');
export const MAX_LETTER_SWIPE_SYMBOL_UNITS: number = 8;
export const LETTER_SWIPE_TAB_SYMBOL: string = '\t';
export const LETTER_SWIPE_SYMBOL_PROFILE_SCHEMA_VERSION: number = 1;
export const LETTER_SWIPE_SYMBOL_PROFILE_TYPE: string = 'shuangyu-letter-swipe-symbols';

export interface LetterSwipeSymbolProfile {
  chineseSymbols: string[];
  englishSymbols: string[];
}

export interface LetterSwipeSymbolProfileParseResult {
  success: boolean;
  message: string;
  value?: LetterSwipeSymbolProfile;
}

interface BindingMapParseResult {
  success: boolean;
  message: string;
  symbols: string[];
}

interface LetterSwipeSymbolProfileDocument {
  schemaVersion: number;
  type: string;
  chinese: Record<string, string>;
  english: Record<string, string>;
}

function emptyBindings(): string[] {
  return LETTER_SWIPE_KEYS.map((): string => '');
}

const LEGACY_SHARED_BINDINGS: string[] = [
  '[', ']', '%', '&', '<', '>', '"', "'", '(', ')',
  '_', '-', '$', '《', '》', '”', '“', '(', ')',
  '', '', '', '', '🍀', '乚', '→'
];

const RECOMMENDED_CHINESE_BINDINGS: string[] = [
  '[', ']', '%', '&', '<', '>', '"', "'", '(', ')',
  '——', '……', '$', '《', '》', '“', '”', '（', '）',
  LETTER_SWIPE_TAB_SYMBOL, '', '', '', '', '', '→'
];

const RECOMMENDED_ENGLISH_BINDINGS: string[] = [
  '[', ']', '%', '&', '<', '>', '"', "'", '(', ')',
  '—', '…', '$', '¥', '\\~', '{', '}', '^', '|',
  LETTER_SWIPE_TAB_SYMBOL, '', '', '', '🍀', '乚', '→'
];

/** The schema-18 English preset, retained so untouched installs can receive the corrected G binding. */
const LEGACY_ENGLISH_SINGLE_TILDE_BINDINGS: string[] = [
  '[', ']', '%', '&', '<', '>', '"', "'", '(', ')',
  '—', '…', '$', '¥', '~', '{', '}', '^', '|',
  LETTER_SWIPE_TAB_SYMBOL, '', '', '', '🍀', '乚', '→'
];

/** The former default, retained so migrations can distinguish untouched settings. */
export const EMPTY_LETTER_SWIPE_SYMBOLS: string = JSON.stringify(emptyBindings());

/** The previously shipped shared preset, retained only for upgrading untouched settings. */
export const LEGACY_SHARED_LETTER_SWIPE_SYMBOLS: string = JSON.stringify(LEGACY_SHARED_BINDINGS);
export const LEGACY_ENGLISH_SINGLE_TILDE_LETTER_SWIPE_SYMBOLS: string = JSON.stringify(
  LEGACY_ENGLISH_SINGLE_TILDE_BINDINGS
);

/** Language-specific direct-text bindings confirmed by the customer. */
export const RECOMMENDED_CHINESE_LETTER_SWIPE_SYMBOLS: string = JSON.stringify(
  RECOMMENDED_CHINESE_BINDINGS
);
export const RECOMMENDED_ENGLISH_LETTER_SWIPE_SYMBOLS: string = JSON.stringify(
  RECOMMENDED_ENGLISH_BINDINGS
);

export const DEFAULT_CHINESE_LETTER_SWIPE_SYMBOLS: string = RECOMMENDED_CHINESE_LETTER_SWIPE_SYMBOLS;
export const DEFAULT_ENGLISH_LETTER_SWIPE_SYMBOLS: string = RECOMMENDED_ENGLISH_LETTER_SWIPE_SYMBOLS;

function isValidLetterSwipeSymbol(value: string): boolean {
  const containsUnsupportedTab = value.indexOf(LETTER_SWIPE_TAB_SYMBOL) >= 0 &&
    value !== LETTER_SWIPE_TAB_SYMBOL;
  return value.length <= MAX_LETTER_SWIPE_SYMBOL_UNITS && !/[\r\n]/.test(value) && !containsUnsupportedTab;
}

export function normalizeLetterSwipeSymbol(value: string): string {
  return isValidLetterSwipeSymbol(value) ? value : '';
}

export function parseLetterSwipeSymbols(value: string | undefined): string[] {
  if (!value) {
    return emptyBindings();
  }
  try {
    const parsed: Object[] = JSON.parse(value) as Object[];
    if (!Array.isArray(parsed)) {
      return emptyBindings();
    }
    return LETTER_SWIPE_KEYS.map((_letter: string, index: number): string => {
      const item = parsed[index];
      return typeof item === 'string' ? normalizeLetterSwipeSymbol(item as string) : '';
    });
  } catch (_err) {
    return emptyBindings();
  }
}

export function normalizeLetterSwipeSymbols(value: string | undefined): string {
  return JSON.stringify(parseLetterSwipeSymbols(value));
}

export function hasOnlyEmptyLetterSwipeSymbols(value: string | undefined): boolean {
  return parseLetterSwipeSymbols(value).every((symbol: string): boolean => symbol.length === 0);
}

export function resolveLetterSwipeSymbol(value: string | undefined, letter: string): string {
  const index = LETTER_SWIPE_KEYS.indexOf(letter.toLowerCase());
  return index >= 0 ? parseLetterSwipeSymbols(value)[index] : '';
}

export function updateLetterSwipeSymbol(value: string | undefined, letter: string, symbol: string): string {
  const index = LETTER_SWIPE_KEYS.indexOf(letter.toLowerCase());
  if (index < 0) {
    return normalizeLetterSwipeSymbols(value);
  }
  const bindings = parseLetterSwipeSymbols(value);
  bindings[index] = normalizeLetterSwipeSymbol(symbol);
  return JSON.stringify(bindings);
}

function profileFailure(message: string): LetterSwipeSymbolProfileParseResult {
  return { success: false, message };
}

function parseProfileBindingMap(value: Object | undefined, label: string): BindingMapParseResult {
  if (value === null || value === undefined || typeof value !== 'object' || Array.isArray(value)) {
    return { success: false, message: `${label}映射必须是对象`, symbols: emptyBindings() };
  }
  const record = value as Record<string, Object>;
  const keys = Object.keys(record);
  for (const key of keys) {
    if (LETTER_SWIPE_KEYS.indexOf(key) < 0) {
      return { success: false, message: `${label}映射包含不支持的按键：${key}`, symbols: emptyBindings() };
    }
  }
  const symbols: string[] = [];
  for (const letter of LETTER_SWIPE_KEYS) {
    const rawSymbol = record[letter];
    if (rawSymbol === undefined) {
      symbols.push('');
      continue;
    }
    if (typeof rawSymbol !== 'string' || !isValidLetterSwipeSymbol(rawSymbol as string)) {
      return {
        success: false,
        message: `${label}映射中 ${letter.toUpperCase()} 的符号格式无效`,
        symbols: emptyBindings()
      };
    }
    symbols.push(rawSymbol);
  }
  return { success: true, message: '', symbols };
}

function toProfileBindingMap(symbols: string[]): Record<string, string> {
  const normalized = parseLetterSwipeSymbols(JSON.stringify(symbols));
  const result = {} as Record<string, string>;
  LETTER_SWIPE_KEYS.forEach((letter: string, index: number): void => {
    result[letter] = normalized[index];
  });
  return result;
}

/**
 * Serializes both language-specific maps into the user-editable .sy-swipe format.
 */
export function serializeLetterSwipeSymbolProfile(
  chineseSymbols: string[],
  englishSymbols: string[]
): string {
  const document: LetterSwipeSymbolProfileDocument = {
    schemaVersion: LETTER_SWIPE_SYMBOL_PROFILE_SCHEMA_VERSION,
    type: LETTER_SWIPE_SYMBOL_PROFILE_TYPE,
    chinese: toProfileBindingMap(chineseSymbols),
    english: toProfileBindingMap(englishSymbols)
  };
  return JSON.stringify(document, null, 2);
}

/**
 * Parses a complete, portable down-swipe profile. Missing letter entries mean no binding.
 */
export function parseLetterSwipeSymbolProfile(content: string): LetterSwipeSymbolProfileParseResult {
  let record: Record<string, Object>;
  try {
    record = JSON.parse(content) as Record<string, Object>;
  } catch (_err) {
    return profileFailure('下滑符号文件不是有效的 JSON');
  }
  if (record === null || typeof record !== 'object' || Array.isArray(record)) {
    return profileFailure('下滑符号文件根节点必须是对象');
  }
  if (record['schemaVersion'] !== LETTER_SWIPE_SYMBOL_PROFILE_SCHEMA_VERSION) {
    return profileFailure('下滑符号文件版本不受支持');
  }
  if (record['type'] !== LETTER_SWIPE_SYMBOL_PROFILE_TYPE) {
    return profileFailure('所选文件不是双羽下滑符号配置');
  }
  const chinese = parseProfileBindingMap(record['chinese'], '中文');
  if (!chinese.success) {
    return profileFailure(chinese.message);
  }
  const english = parseProfileBindingMap(record['english'], '英文');
  if (!english.success) {
    return profileFailure(english.message);
  }
  return {
    success: true,
    message: '',
    value: {
      chineseSymbols: chinese.symbols,
      englishSymbols: english.symbols
    }
  };
}
