import { PunctuationMode } from '../settings/ImeSettings';

const ENGLISH_PUNCTUATION: Record<string, string> = {
  '，': ',',
  '。': '.',
  '；': ';',
  '：': ':',
  '！': '!',
  '？': '?',
  '（': '(',
  '）': ')',
  '【': '[',
  '】': ']'
};

export function transformDirectText(
  text: string,
  punctuationMode: PunctuationMode,
  fullWidthEnabled: boolean
): string {
  let transformed = punctuationMode === PunctuationMode.ENGLISH ?
    (ENGLISH_PUNCTUATION[text] ?? text) : text;
  if (!fullWidthEnabled || transformed.length !== 1) {
    return transformed;
  }
  const code = transformed.charCodeAt(0);
  if (code === 0x20) {
    return '　';
  }
  if ((code >= 0x30 && code <= 0x39) || (code >= 0x41 && code <= 0x5A) ||
    (code >= 0x61 && code <= 0x7A)) {
    transformed = String.fromCharCode(code + 0xFEE0);
  }
  return transformed;
}
