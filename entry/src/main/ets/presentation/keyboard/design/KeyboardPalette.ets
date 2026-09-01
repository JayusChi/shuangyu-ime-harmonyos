/**
 * 键盘颜色配置
 * 支持浅色和深色模式
 */

export interface KeyboardColorPalette {
  // “淡然”素材按日间/夜间分别提供位图图标；颜色模式同时决定图标版本。
  useDarkMedia: boolean;

  // 默认皮肤直接使用“淡然”九宫格键帽；其他内置/导入皮肤继续使用原有图片或纯色渲染。
  useDanranKeyImages: boolean;

  // 自定义皮肤包可以为面板和不同键帽提供本地图片。空字符串表示只使用颜色。
  panelBackgroundImage: string;
  letterKeyBackgroundImage: string;
  functionKeyBackgroundImage: string;
  spaceKeyBackgroundImage: string;
  enterKeyBackgroundImage: string;

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

export enum DanranKeyBackgroundKind {
  LETTER = 'letter',
  FUNCTION = 'function',
  SPACE = 'space',
  ENTER = 'enter'
}

/**
 * 将客户 Android .9 PNG 中的 npTc 拉伸区转换成 ArkUI 的固定边缘切片。
 * 显式使用 px，确保数值对应原始 PNG 像素，而不是随设备密度变化的 vp。
 */
export function resolveDanranKeyBackgroundSlice(
  kind: DanranKeyBackgroundKind,
  isDark: boolean,
  isPressed: boolean
): EdgeWidths {
  if (kind === DanranKeyBackgroundKind.LETTER) {
    if (isDark) {
      return isPressed
        ? { left: '47px', right: '44px', top: '47px', bottom: '47px' }
        : { left: '45px', right: '43px', top: '47px', bottom: '47px' };
    }
    return isPressed
      ? { left: '47px', right: '45px', top: '47px', bottom: '47px' }
      : { left: '49px', right: '45px', top: '47px', bottom: '47px' };
  }
  if (kind === DanranKeyBackgroundKind.SPACE) {
    return { left: '178px', right: '178px', top: '47px', bottom: '47px' };
  }
  return { left: '55px', right: '55px', top: '47px', bottom: '47px' };
}

/**
 * 浅色模式调色板
 */
export const LIGHT_PALETTE: KeyboardColorPalette = {
  useDarkMedia: false,
  useDanranKeyImages: true,
  panelBackgroundImage: '',
  letterKeyBackgroundImage: '',
  functionKeyBackgroundImage: '',
  spaceKeyBackgroundImage: '',
  enterKeyBackgroundImage: '',

  // 背景色
  panelBackground: '#DCE0EB',
  candidateBackground: '#ECEFF8',

  // 按键背景色
  letterKeyBackground: '#F8F8F8',
  functionKeyBackground: '#E8E8E8',
  spaceKeyBackground: '#F8F8F8',
  primaryFunctionBackground: '#D8D8D8',
  modeKeyBackgroundEnglish: '#F8F8F8',
  modeKeyBackgroundChinese: '#E8E8E8',

  // 按下状态
  letterKeyPressedBackground: '#C8CFDF',
  functionKeyPressedBackground: '#F8F8F8',
  primaryFunctionPressedBackground: '#F8F8F8',

  // 文字颜色
  letterKeyText: '#1B2927',
  functionKeyText: '#1B2927',
  primaryFunctionText: '#1B2927',
  modeKeyTextEnglish: '#505657',
  modeKeyTextChinese: '#D75642',
  errorText: '#D75642',

  // 预览气泡
  previewBackground: '#F8F8F8',
  previewText: '#1B2927',
  previewShadow: '#00000000',

  // 候选栏
  candidateText: '#666666',
  candidateReading: '#AAAAAA',
  candidateDivider: '#DDDDDD',

  // 边框
  keyBorder: '#DDDDDD'
};

/**
 * 深色模式调色板
 */
export const DARK_PALETTE: KeyboardColorPalette = {
  useDarkMedia: true,
  useDanranKeyImages: true,
  panelBackgroundImage: '',
  letterKeyBackgroundImage: '',
  functionKeyBackgroundImage: '',
  spaceKeyBackgroundImage: '',
  enterKeyBackgroundImage: '',

  // 背景色
  panelBackground: '#1C202B',
  candidateBackground: '#0C101B',

  // 按键背景色
  letterKeyBackground: '#444444',
  functionKeyBackground: '#343434',
  spaceKeyBackground: '#444444',
  primaryFunctionBackground: '#282828',
  modeKeyBackgroundEnglish: '#444444',
  modeKeyBackgroundChinese: '#343434',

  // 按下状态
  letterKeyPressedBackground: '#5E5E5E',
  functionKeyPressedBackground: '#444444',
  primaryFunctionPressedBackground: '#444444',

  // 文字颜色
  letterKeyText: '#FAFAFA',
  functionKeyText: '#FCFAFD',
  primaryFunctionText: '#FCFAFD',
  modeKeyTextEnglish: '#FFFDFF',
  modeKeyTextChinese: '#FFB5B0',
  errorText: '#FFB5B0',

  // 预览气泡
  previewBackground: '#444444',
  previewText: '#FAFAFA',
  previewShadow: '#00000000',

  // 候选栏
  candidateText: '#AAAAAA',
  candidateReading: '#888888',
  candidateDivider: '#2C3032',

  // 边框
  keyBorder: '#2C3032'
};

/**
 * 获取当前主题的调色板
 * 在实际使用中，应该根据系统主题动态返回
 */
export function getPaletteForColorMode(isDarkMode: boolean): KeyboardColorPalette {
  return isDarkMode ? DARK_PALETTE : LIGHT_PALETTE;
}
