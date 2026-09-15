import { shapeLookupCharacter } from './ShapeLookup';

export const CLIPBOARD_REVERSE_CODE = 'ofi';
export const CLIPBOARD_REVERSE_LABEL = '[复制反查]';

/** Only a single complete Han character is a reverse lookup request. */
export function clipboardReverseCharacter(text: string): string {
  const value = text.trim();
  return value.length > 0 && value.length <= 2 && shapeLookupCharacter(value, false) === value ? value : '';
}
