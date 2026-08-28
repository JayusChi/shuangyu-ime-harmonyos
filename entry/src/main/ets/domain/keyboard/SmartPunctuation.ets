export interface SmartPunctuationOption {
  symbol: string;
  label: string;
}

/**
 * Customer-compatible intelligsymbol order. Backslash is represented as one
 * actual character in settings and only needs escaping in source/config text.
 */
export const SMART_PUNCTUATION_OPTIONS: SmartPunctuationOption[] = [
  { symbol: ',', label: ',' },
  { symbol: '.', label: '.' },
  { symbol: '/', label: '/' },
  { symbol: ';', label: ';' },
  { symbol: '\\', label: '\\' },
  { symbol: '!', label: '!' },
  { symbol: ':', label: ':' },
  { symbol: '?', label: '?' },
  { symbol: '"', label: '"' },
  { symbol: '$', label: '$' },
  { symbol: '(', label: '(' },
  { symbol: ')', label: ')' },
  { symbol: '[', label: '[' },
  { symbol: ']', label: ']' },
  { symbol: '^', label: '^' },
  { symbol: '_', label: '_' },
  { symbol: '<', label: '<' },
  { symbol: '>', label: '>' }
];

export const DEFAULT_SMART_PUNCTUATION_SYMBOLS: string = SMART_PUNCTUATION_OPTIONS
  .map((option: SmartPunctuationOption): string => option.symbol)
  .join('');

const CHINESE_TO_ENGLISH_PUNCTUATION: Record<string, string> = {
  '，': ',',
  '。': '.',
  '、': '/',
  '；': ';',
  '＼': '\\',
  '！': '!',
  '：': ':',
  '？': '?',
  '“': '"',
  '”': '"',
  '＂': '"',
  '￥': '$',
  '＄': '$',
  '（': '(',
  '）': ')',
  '【': '[',
  '［': '[',
  '】': ']',
  '］': ']',
  '……': '^',
  '＾': '^',
  '——': '_',
  '＿': '_',
  '《': '<',
  '＜': '<',
  '》': '>',
  '＞': '>'
};

const ENGLISH_TO_CHINESE_PUNCTUATION: Record<string, string> = {
  ',': '，',
  '.': '。',
  '/': '、',
  ';': '；',
  '\\': '＼',
  '!': '！',
  ':': '：',
  '?': '？',
  '"': '＂',
  '$': '￥',
  '(': '（',
  ')': '）',
  '[': '【',
  ']': '】',
  '^': '＾',
  '_': '＿',
  '<': '《',
  '>': '》'
};

/** Canonicalizes either a plain intelligsymbol value or its JSON string form. */
export function normalizeSmartPunctuationSymbols(value: string | undefined): string {
  if (value === undefined) {
    return DEFAULT_SMART_PUNCTUATION_SYMBOLS;
  }
  let candidate = value;
  try {
    const parsed: Object = JSON.parse(value) as Object;
    if (typeof parsed === 'string') {
      candidate = parsed as string;
    }
  } catch (_err) {
    // Plain intelligsymbol values are accepted directly.
  }
  return SMART_PUNCTUATION_OPTIONS
    .filter((option: SmartPunctuationOption): boolean => candidate.indexOf(option.symbol) >= 0)
    .map((option: SmartPunctuationOption): string => option.symbol)
    .join('');
}

export function smartPunctuationTarget(text: string): string | undefined {
  return CHINESE_TO_ENGLISH_PUNCTUATION[text];
}

export function chinesePunctuationForEnglishTarget(text: string): string {
  return ENGLISH_TO_CHINESE_PUNCTUATION[text] ?? text;
}

export function isSmartPunctuationEnabled(symbols: string, target: string): boolean {
  return target.length === 1 && symbols.indexOf(target) >= 0;
}
