export const LETTER_SWIPE_KEYS: string[] = 'qwertyuiopasdfghjklzxcvbnm'.split('');
export const MAX_LETTER_SWIPE_SYMBOL_UNITS: number = 8;

function emptyBindings(): string[] {
  return LETTER_SWIPE_KEYS.map((): string => '');
}

const RECOMMENDED_BINDINGS: string[] = [
  '[', ']', '%', '&', '<', '>', '"', "'", '(', ')',
  '_', '-', '$', '《', '》', '”', '“', '(', ')',
  '', '', '', '', '🍀', '乚', '→'
];

/** The former default, retained so migrations can distinguish untouched settings. */
export const EMPTY_LETTER_SWIPE_SYMBOLS: string = JSON.stringify(emptyBindings());

/** Recommended direct-text bindings derived from the customer's reference keyboard. */
export const RECOMMENDED_LETTER_SWIPE_SYMBOLS: string = JSON.stringify(RECOMMENDED_BINDINGS);

export const DEFAULT_LETTER_SWIPE_SYMBOLS: string = RECOMMENDED_LETTER_SWIPE_SYMBOLS;

export function normalizeLetterSwipeSymbol(value: string): string {
  if (value.length > MAX_LETTER_SWIPE_SYMBOL_UNITS || /[\r\n\t]/.test(value)) {
    return '';
  }
  return value;
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
