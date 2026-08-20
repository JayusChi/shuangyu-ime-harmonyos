export enum ShuangpinKeyboardLayout {
  SEVENTEEN_KEY = 'seventeen_key',
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
    id: ShuangpinKeyboardLayout.SEVENTEEN_KEY,
    displayName: '17 键双拼',
    description: '紧凑分组按键'
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
  return value === ShuangpinKeyboardLayout.SEVENTEEN_KEY
    ? ShuangpinKeyboardLayout.SEVENTEEN_KEY
    : DEFAULT_SHUANGPIN_KEYBOARD_LAYOUT;
}

export function shuangpinKeyboardLayoutDisplayName(layout: ShuangpinKeyboardLayout): string {
  return layout === ShuangpinKeyboardLayout.SEVENTEEN_KEY ? '17 键双拼' : '26 键双拼';
}
