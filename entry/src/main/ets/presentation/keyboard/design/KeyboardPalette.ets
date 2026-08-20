/**
 * 键盘颜色配置
 * 支持浅色和深色模式
 */

export interface KeyboardColorPalette {
  // 背景色
  panelBackground: string;
  candidateBackground: string;

  // 按键背景色
  letterKeyBackground: string;
  functionKeyBackground: string;
  spaceKeyBackground: string;
  primaryFunctionBackground: string;
  modeKeyBackgroundEnglish: string;
  modeKeyBackgroundChinese: string;

  // 按下状态背景色
  letterKeyPressedBackground: string;
  functionKeyPressedBackground: string;
  primaryFunctionPressedBackground: string;

  // 文字颜色
  letterKeyText: string;
  functionKeyText: string;
  primaryFunctionText: string;
  modeKeyTextEnglish: string;
  modeKeyTextChinese: string;
  errorText: string;

  // 预览气泡
  previewBackground: string;
  previewText: string;
  previewShadow: string;

  // 候选栏
  candidateText: string;
  candidateReading: string;
  candidateDivider: string;

  // 边框
  keyBorder: string;
}

/**
 * 浅色模式调色板
 */
export const LIGHT_PALETTE: KeyboardColorPalette = {
  // 背景色
  panelBackground: '#F8FAFC',
  candidateBackground: '#FFFFFF',

  // 按键背景色
  letterKeyBackground: '#FFFFFF',
  functionKeyBackground: '#E5E7EB',
  spaceKeyBackground: '#F1F5F9',
  primaryFunctionBackground: '#3B82F6',
  modeKeyBackgroundEnglish: '#E8F3FF',
  modeKeyBackgroundChinese: '#FFF4E5',

  // 按下状态
  letterKeyPressedBackground: '#E5E7EB',
  functionKeyPressedBackground: '#D1D5DB',
  primaryFunctionPressedBackground: '#2563EB',

  // 文字颜色
  letterKeyText: '#111827',
  functionKeyText: '#111827',
  primaryFunctionText: '#FFFFFF',
  modeKeyTextEnglish: '#0A59F7',
  modeKeyTextChinese: '#B45309',
  errorText: '#B91C1C',

  // 预览气泡
  previewBackground: '#FFFFFF',
  previewText: '#111827',
  previewShadow: 'rgba(0, 0, 0, 0.15)',

  // 候选栏
  candidateText: '#111827',
  candidateReading: '#6B7280',
  candidateDivider: '#E5E7EB',

  // 边框
  keyBorder: '#E5E7EB'
};

/**
 * 深色模式调色板
 */
export const DARK_PALETTE: KeyboardColorPalette = {
  // 背景色
  panelBackground: '#1F2937',
  candidateBackground: '#374151',

  // 按键背景色
  letterKeyBackground: '#374151',
  functionKeyBackground: '#4B5563',
  spaceKeyBackground: '#374151',
  primaryFunctionBackground: '#3B82F6',
  modeKeyBackgroundEnglish: '#1E3A5F',
  modeKeyBackgroundChinese: '#4A3419',

  // 按下状态
  letterKeyPressedBackground: '#4B5563',
  functionKeyPressedBackground: '#6B7280',
  primaryFunctionPressedBackground: '#2563EB',

  // 文字颜色
  letterKeyText: '#F9FAFB',
  functionKeyText: '#F9FAFB',
  primaryFunctionText: '#FFFFFF',
  modeKeyTextEnglish: '#60A5FA',
  modeKeyTextChinese: '#FCD34D',
  errorText: '#F87171',

  // 预览气泡
  previewBackground: '#374151',
  previewText: '#F9FAFB',
  previewShadow: 'rgba(0, 0, 0, 0.5)',

  // 候选栏
  candidateText: '#F9FAFB',
  candidateReading: '#9CA3AF',
  candidateDivider: '#4B5563',

  // 边框
  keyBorder: '#4B5563'
};

/**
 * 获取当前主题的调色板
 * 在实际使用中，应该根据系统主题动态返回
 */
export function getPaletteForColorMode(isDarkMode: boolean): KeyboardColorPalette {
  return isDarkMode ? DARK_PALETTE : LIGHT_PALETTE;
}
