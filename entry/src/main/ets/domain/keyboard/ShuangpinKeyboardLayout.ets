export enum ShuangpinKeyboardLayout {
  EIGHTEEN_KEY = 'eighteen_key',
  TWENTY_SIX_KEY = 'twenty_six_key'
}

export interface ShuangpinKeyboardLayoutOption {
  id: ShuangpinKeyboardLayout;
  displayName: string;
  description: string;
}

export const DEFAULT_SHUANGPIN_KEYBOARD_LAYOUT: ShuangpinKeyboardLayout =
  ShuangpinKeyboardLayout.TWENTY_SIX_KEY;

export const SHUANGPIN_KEYBOARD_LAYOUT_OPTIONS: ShuangpinKeyboardLayoutOption[] = [
  {
    id: ShuangpinKeyboardLayout.EIGHTEEN_KEY,
    displayName: '18 键双拼',
    description: '参考 QWERTY 顺序的分组按键'
  },
  {
    id: ShuangpinKeyboardLayout.TWENTY_SIX_KEY,
    displayName: '26 键双拼',
    description: '标准 QWERTY 按键'
  }
];

export function normalizeShuangpinKeyboardLayout(
  value: string | undefined
): ShuangpinKeyboardLayout {
  return value === ShuangpinKeyboardLayout.EIGHTEEN_KEY || value === 'seventeen_key'
    ? ShuangpinKeyboardLayout.EIGHTEEN_KEY
    : DEFAULT_SHUANGPIN_KEYBOARD_LAYOUT;
}

export function shuangpinKeyboardLayoutDisplayName(layout: ShuangpinKeyboardLayout): string {
  return layout === ShuangpinKeyboardLayout.EIGHTEEN_KEY ? '18 键双拼' : '26 键双拼';
}
