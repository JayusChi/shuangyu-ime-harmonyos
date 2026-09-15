export const SHAPE_LOOKUP_CODE = 'oix';
export const SHAPE_LOOKUP_TARGET = 'flypy-shape';
export const SHAPE_LOOKUP_LABEL = '「查」：{last_0}';

function isHan(code: number): boolean {
  return (code >= 0x3400 && code <= 0x9fff) || (code >= 0xf900 && code <= 0xfaff) ||
    (code >= 0x20000 && code <= 0x323af) || code === 0x3007;
}

/** Keep a complete Unicode character; never pass an editor paragraph or raw command to the web. */
export function shapeLookupCharacter(text: string, fromEnd: boolean): string {
  const value = text.trim();
  if (value.length === 0) { return ''; }
  let index = fromEnd ? value.length - 1 : 0;
  const last = value.charCodeAt(index);
  if (fromEnd && last >= 0xdc00 && last <= 0xdfff && index > 0) { index -= 1; }
  const high = value.charCodeAt(index);
  const low = value.charCodeAt(index + 1);
  const pair = high >= 0xd800 && high <= 0xdbff && low >= 0xdc00 && low <= 0xdfff;
  const code = pair ? 0x10000 + (high - 0xd800) * 0x400 + low - 0xdc00 : high;
  return isHan(code) ? value.slice(index, index + (pair ? 2 : 1)) : '';
}

export function shapeLookupCursorCharacter(before: string, preview: string, previewActive: boolean): string {
  const committed = previewActive && preview.length > 0 && before.endsWith(preview)
    ? before.slice(0, before.length - preview.length) : before;
  return shapeLookupCharacter(committed, true);
}

export function shapeLookupUrl(character: string): string | undefined {
  return character.length > 0 && shapeLookupCharacter(character, false) === character
    ? 'https://flypy.cc/ix/?q=' + encodeURIComponent(character) : undefined;
}
