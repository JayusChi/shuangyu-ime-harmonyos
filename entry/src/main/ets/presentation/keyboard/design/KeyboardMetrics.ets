import {
  DEFAULT_LONG_PRESS_DURATION_MS,
  DEFAULT_KEYBOARD_FONT_SIZE,
  MIN_KEYBOARD_FONT_SIZE,
  MAX_KEYBOARD_FONT_SIZE,
  DEFAULT_UPPER_LABEL_RIGHT_MARGIN,
  MIN_UPPER_LABEL_RIGHT_MARGIN,
  MAX_UPPER_LABEL_RIGHT_MARGIN,
  KeyboardHeightMode,
  keyboardHeightScale
} from '../../../domain/settings/ImeSettings';
import {
  SAFE_FALLBACK_SCREEN_METRICS_PX,
  ScreenMetricsPx,
  createScreenMetrics,
  pxToVp,
  vpToPx
} from '../../../domain/display/ScreenMetrics';
import {
  KeyboardDeviceFormFactor,
  resolveKeyboardAuxiliaryAreaPolicy
} from '../../../domain/display/KeyboardAuxiliaryAreaPolicy';

/**
 * 键盘尺寸和布局常量
 * 集中管理所有键盘相关的尺寸、间距、字体大小等
 */

export interface OrientationMetrics {
  layoutForm: KeyboardLayoutForm;
  candidateBarHeight: number;
  pinyinCombinationBarHeight: number;
  statusBarActionWidth: number;
  letterKeyHeight: number;
  functionKeyRowHeight: number;
  rowSpacing: number;
  keySpacing: number;
  horizontalPadding: number;
  secondRowInset: number;
  topPadding: number;
  bottomPadding: number;
  keyBorderRadius: number;
  letterFontSize: number;
  functionFontSize: number;
  previewFontSize: number;
  upperLabelRightMargin: number;
}

export interface KeyboardKeyWeights {
  LETTER: number;
  SHIFT: number;
  MODE_SWITCH: number;
  DELETE: number;
  ENTER: number;
  SPACE: number;
  PRIMARY_ENTER: number;
  NUMERIC_ONLY_ENTER: number;
  SYMBOL_SPACE: number;
  SYMBOL_ENTER: number;
}

export enum KeyboardLayoutForm {
  PHONE_PORTRAIT = 'phonePortrait',
  PHONE_LANDSCAPE = 'phoneLandscape',
  TABLET = 'tablet'
}

export interface DeleteRepeatConfig {
  LONG_PRESS_DELAY_MS: number;
  REPEAT_INTERVAL_MS: number;
  FAST_REPEAT_THRESHOLD: number;
  FAST_REPEAT_INTERVAL_MS: number;
}

export interface KeyPreviewConfig {
  OFFSET_Y: number;
  WIDTH: number;
  HEIGHT: number;
  BORDER_RADIUS: number;
  ANIMATION_DURATION: number;
}

/**
 * 最后一行按键到底部系统功能区域分界线的统一视觉间距（vp）。
 * 该间距只由活动键盘根容器负责，具体布局和按键行不得重复添加。
 */
export const KEYBOARD_BOTTOM_PADDING: number = 15;
/**
 * 竖屏模式尺寸配置
 */
export const PORTRAIT_METRICS: OrientationMetrics = {
  layoutForm: KeyboardLayoutForm.PHONE_PORTRAIT,
  candidateBarHeight: 52,
  pinyinCombinationBarHeight: 36,
  statusBarActionWidth: 48,
  letterKeyHeight: 42,
  functionKeyRowHeight: 44,
  rowSpacing: 6,
  keySpacing: 5,
  horizontalPadding: 10,
  secondRowInset: 17,
  topPadding: 6,
  bottomPadding: KEYBOARD_BOTTOM_PADDING,
  keyBorderRadius: 9,
  letterFontSize: DEFAULT_KEYBOARD_FONT_SIZE,
  functionFontSize: DEFAULT_KEYBOARD_FONT_SIZE - 3,
  previewFontSize: 18,
  upperLabelRightMargin: DEFAULT_UPPER_LABEL_RIGHT_MARGIN
};

/**
 * 横屏模式尺寸配置（更紧凑）
 */
export const LANDSCAPE_METRICS: OrientationMetrics = {
  layoutForm: KeyboardLayoutForm.PHONE_LANDSCAPE,
  candidateBarHeight: 44,
  pinyinCombinationBarHeight: 30,
  statusBarActionWidth: 44,
  letterKeyHeight: 36,
  functionKeyRowHeight: 38,
  rowSpacing: 4,
  keySpacing: 4,
  horizontalPadding: 8,
  secondRowInset: 20,
  topPadding: 6,
  bottomPadding: KEYBOARD_BOTTOM_PADDING,
  keyBorderRadius: 8,
  letterFontSize: DEFAULT_KEYBOARD_FONT_SIZE,
  functionFontSize: DEFAULT_KEYBOARD_FONT_SIZE - 3,
  previewFontSize: 18,
  upperLabelRightMargin: DEFAULT_UPPER_LABEL_RIGHT_MARGIN
};

/**
 * 按键权重配置
 */
export const KEY_WEIGHTS: KeyboardKeyWeights = {
  LETTER: 1,
  SHIFT: 1.5,
  MODE_SWITCH: 1.1,
  DELETE: 1.5,
  // 3.2：原隐藏键的权重只分配给空格和回车，其他功能键宽度保持稳定。
  ENTER: 1.65,
  SPACE: 4.6,
  PRIMARY_ENTER: 2.4,
  NUMERIC_ONLY_ENTER: 2,
  SYMBOL_SPACE: 3.8,
  SYMBOL_ENTER: 1.6
};

/**
 * 长按删除配置
 */
export const DELETE_REPEAT_CONFIG: DeleteRepeatConfig = {
  LONG_PRESS_DELAY_MS: DEFAULT_LONG_PRESS_DURATION_MS, // 未传入用户设置时的长按触发阈值
  REPEAT_INTERVAL_MS: 50,       // 连续删除间隔
  FAST_REPEAT_THRESHOLD: 10,    // 加速阈值（第N次后加速）
  FAST_REPEAT_INTERVAL_MS: 30   // 加速后的间隔
};

/**
 * 按键预览配置
 */
export const KEY_PREVIEW_CONFIG: KeyPreviewConfig = {
  OFFSET_Y: -50,           // 预览相对按键的Y偏移
  WIDTH: 44,               // 预览宽度
  HEIGHT: 54,              // 预览高度
  BORDER_RADIUS: 8,        // 预览圆角
  ANIMATION_DURATION: 100  // 动画时长(ms)
};

/**
 * 根据方向获取度量标准
 */
export function getMetricsForOrientation(
  isLandscape: boolean,
  heightMode: KeyboardHeightMode = KeyboardHeightMode.STANDARD,
  screenMetrics?: ScreenMetricsPx,
  keyboardFontSize: number = DEFAULT_KEYBOARD_FONT_SIZE,
  upperLabelRightMargin: number = DEFAULT_UPPER_LABEL_RIGHT_MARGIN
): OrientationMetrics {
  if (screenMetrics) {
    return calculateDynamicMetrics(screenMetrics, heightMode, keyboardFontSize, upperLabelRightMargin);
  }
  const base = isLandscape ? LANDSCAPE_METRICS : PORTRAIT_METRICS;
  const scale = keyboardHeightScale(heightMode);
  if (scale === 1 && keyboardFontSize === DEFAULT_KEYBOARD_FONT_SIZE &&
    upperLabelRightMargin === DEFAULT_UPPER_LABEL_RIGHT_MARGIN) {
    return base;
  }
  return {
    layoutForm: base.layoutForm,
    candidateBarHeight: base.candidateBarHeight,
    pinyinCombinationBarHeight: base.pinyinCombinationBarHeight,
    statusBarActionWidth: base.statusBarActionWidth,
    letterKeyHeight: Math.round(base.letterKeyHeight * scale),
    functionKeyRowHeight: Math.round(base.functionKeyRowHeight * scale),
    rowSpacing: base.rowSpacing,
    keySpacing: base.keySpacing,
    horizontalPadding: base.horizontalPadding,
    secondRowInset: base.secondRowInset,
    topPadding: base.topPadding,
    bottomPadding: KEYBOARD_BOTTOM_PADDING,
    keyBorderRadius: base.keyBorderRadius,
    letterFontSize: normalizeKeyboardFontSize(keyboardFontSize),
    functionFontSize: Math.max(8, normalizeKeyboardFontSize(keyboardFontSize) - 3),
    previewFontSize: Math.max(18, Math.round(normalizeKeyboardFontSize(keyboardFontSize) * 1.5)),
    upperLabelRightMargin: normalizeUpperLabelRightMargin(upperLabelRightMargin)
  };
}

/**
 * 根据同一份屏幕 px 快照计算 ArkUI 使用的 vp 度量。
 */
function normalizeKeyboardFontSize(value: number): number {
  return Number.isFinite(value) ? clamp(Math.round(value), MIN_KEYBOARD_FONT_SIZE, MAX_KEYBOARD_FONT_SIZE) :
    DEFAULT_KEYBOARD_FONT_SIZE;
}

function normalizeUpperLabelRightMargin(value: number): number {
  return Number.isFinite(value) ? clamp(Math.round(value), MIN_UPPER_LABEL_RIGHT_MARGIN,
    MAX_UPPER_LABEL_RIGHT_MARGIN) : DEFAULT_UPPER_LABEL_RIGHT_MARGIN;
}

/** 按逻辑短边适配；相同逻辑尺寸和横竖屏得到相同的默认字号。 */
export function resolveDefaultKeyboardFontSize(screenMetrics: ScreenMetricsPx): number {
  const valid = createScreenMetrics({ widthPx: screenMetrics.widthPx, heightPx: screenMetrics.heightPx,
    densityPixels: screenMetrics.densityPixels }, screenMetrics.isLandscape);
  const shortSideVp = pxToVp(Math.min(valid.widthPx, valid.heightPx), valid);
  return clamp(Math.round(DEFAULT_KEYBOARD_FONT_SIZE * shortSideVp / 360), DEFAULT_KEYBOARD_FONT_SIZE, 24);
}

export function calculateDynamicMetrics(
  screenMetrics: ScreenMetricsPx,
  heightMode: KeyboardHeightMode = KeyboardHeightMode.STANDARD,
  keyboardFontSize: number = DEFAULT_KEYBOARD_FONT_SIZE,
  upperLabelRightMargin: number = DEFAULT_UPPER_LABEL_RIGHT_MARGIN
): OrientationMetrics {
  const validMetrics = createScreenMetrics({
    widthPx: screenMetrics.widthPx,
    heightPx: screenMetrics.heightPx,
    densityPixels: screenMetrics.densityPixels,
    bottomSystemInsetPx: screenMetrics.bottomSystemInsetPx
  }, screenMetrics.isLandscape);
  const screenWidthVp = pxToVp(validMetrics.widthPx, validMetrics);
  const screenHeightVp = pxToVp(
    validMetrics.heightPx - (validMetrics.bottomSystemInsetPx ?? 0),
    validMetrics
  );
  const isLandscape = validMetrics.isLandscape;
  const auxiliaryPolicy = resolveKeyboardAuxiliaryAreaPolicy(validMetrics);
  const layoutForm = auxiliaryPolicy.formFactor === KeyboardDeviceFormFactor.TABLET
    ? KeyboardLayoutForm.TABLET
    : (isLandscape ? KeyboardLayoutForm.PHONE_LANDSCAPE : KeyboardLayoutForm.PHONE_PORTRAIT);

  const keyboardHeightRatio = (isLandscape ? 0.55 : 0.38) * keyboardHeightScale(heightMode);

  const totalKeyboardHeight = Math.max(195, Math.min(screenHeightVp, Math.round(screenHeightVp * keyboardHeightRatio)));
  const candidateBarHeight = clamp(Math.round(totalKeyboardHeight * 0.15), 40, 60);
  const pinyinCombinationBarHeight = clamp(Math.round(candidateBarHeight * 0.7), 28, 40);
  const statusBarActionWidth = clamp(candidateBarHeight, 44, 52);
  const bottomPadding = KEYBOARD_BOTTOM_PADDING;

  const topPadding = 6;
  const availableKeyboardHeight = totalKeyboardHeight - candidateBarHeight - bottomPadding - topPadding;
  const numRows = 4;
  const rowSpacing = isLandscape ? 4 : 6;
  const totalRowSpacing = rowSpacing * (numRows - 1);
  const equalRowHeight = (availableKeyboardHeight - totalRowSpacing) / 4.05;
  const letterKeyHeight = clamp(Math.round(equalRowHeight), 30, 140);
  const functionKeyRowHeight = clamp(Math.round(letterKeyHeight * 1.05), 32, 147);

  const keySpacing = isLandscape ? 4 : 5;
  // Pad 预留更宽的两侧辅助区域；手机仍优先把可用宽度留给字母区。
  const horizontalPadding = layoutForm === KeyboardLayoutForm.TABLET
    ? clamp(Math.round(screenWidthVp * 0.025), 20, 36)
    : clamp(Math.round(screenWidthVp * 0.015), 8, 24);
  const usableRowWidth = screenWidthVp - (horizontalPadding * 2);
  // A-L 行相对十列基准缩进半个字母槽，所有设备形态使用同一计算方式。
  const secondRowInset = clamp(Math.round((usableRowWidth + keySpacing) / 20), 14, 48);

  // 旧版 12 为零增减；保留已保存的相对调整，平板默认随逻辑短边放大。
  const fontSizeOffset = normalizeKeyboardFontSize(keyboardFontSize) - DEFAULT_KEYBOARD_FONT_SIZE;
  const letterFontSize = clamp(resolveDefaultKeyboardFontSize(validMetrics) + fontSizeOffset,
    MIN_KEYBOARD_FONT_SIZE, MAX_KEYBOARD_FONT_SIZE);
  const functionFontSize = Math.max(8, letterFontSize - 3);
  const previewFontSize = Math.max(18, Math.round(letterFontSize * 1.5));

  // “淡然”键帽使用明显的柔和圆角；按实际键高等比例缩放并限制极端屏幕。
  const keyBorderRadius = clamp(Math.round(letterKeyHeight * 0.2), 7, 12);

  return {
    layoutForm,
    candidateBarHeight,
    pinyinCombinationBarHeight,
    statusBarActionWidth,
    letterKeyHeight,
    functionKeyRowHeight,
    rowSpacing,
    keySpacing,
    horizontalPadding,
    secondRowInset,
    topPadding,
    bottomPadding,
    keyBorderRadius,
    letterFontSize,
    functionFontSize,
    previewFontSize,
    upperLabelRightMargin: normalizeUpperLabelRightMargin(upperLabelRightMargin)
  };
}

export function panelHeightForMode(
  mode: KeyboardHeightMode,
  screenMetrics: ScreenMetricsPx = SAFE_FALLBACK_SCREEN_METRICS_PX,
  pinyin9ChineseLayout: boolean = false,
  keyboardLiftLayerEnabled: boolean = false,
  candidateBarVisible: boolean = true
): number {
  const validMetrics = createScreenMetrics({
    widthPx: screenMetrics.widthPx,
    heightPx: screenMetrics.heightPx,
    densityPixels: screenMetrics.densityPixels,
    bottomSystemInsetPx: screenMetrics.bottomSystemInsetPx
  }, screenMetrics.isLandscape);
  const metrics = calculateDynamicMetrics(validMetrics, mode);
  const panelHeightVp = calculateTotalKeyboardHeight(
    metrics,
    pinyin9ChineseLayout,
    keyboardLiftLayerEnabled,
    candidateBarVisible
  ) + 6;
  let panelHeightPx = vpToPx(panelHeightVp, validMetrics);
  if (pinyin9ChineseLayout && validMetrics.isLandscape) {
    // A fixed IME panel above roughly 60% of a landscape display is rejected by
    // some Pad/2-in-1 runtimes (12800008). T9 has one more key row and a pinyin
    // bar, but every rendered row uses layoutWeight, so it can safely share this
    // bounded panel and distribute the available height instead of overflowing.
    const qwertyHeightPx = vpToPx(
      calculateTotalKeyboardHeight(metrics, false, keyboardLiftLayerEnabled, candidateBarVisible) + 6,
      validMetrics
    );
    const usableHeightPx = validMetrics.heightPx - (validMetrics.bottomSystemInsetPx ?? 0);
    const landscapeT9LimitPx = Math.round(usableHeightPx * 0.6);
    panelHeightPx = Math.min(panelHeightPx, Math.max(qwertyHeightPx, landscapeT9LimitPx));
  }
  return clamp(panelHeightPx, 1, Math.round(validMetrics.heightPx));
}

/**
 * 计算键盘总高度
 */
export function calculateTotalKeyboardHeight(
  metrics: OrientationMetrics,
  pinyin9ChineseLayout: boolean = false,
  keyboardLiftLayerEnabled: boolean = false,
  candidateBarVisible: boolean = true
): number {
  const candidateSection = candidateBarVisible ? metrics.candidateBarHeight : 0;
  const keyboardRows = pinyin9ChineseLayout ? 5 : 4;
  const primaryRows = pinyin9ChineseLayout ? 4 : 3;
  const keyboardHeight =
    (metrics.letterKeyHeight * primaryRows) +
    metrics.functionKeyRowHeight +
    (metrics.rowSpacing * (keyboardRows - 1));
  const pinyinSection = pinyin9ChineseLayout ? metrics.pinyinCombinationBarHeight : 0;

  const liftLayer = keyboardLiftLayerEnabled ? metrics.letterKeyHeight : 0;
  return candidateSection + pinyinSection + keyboardHeight + liftLayer + metrics.bottomPadding;
}

function clamp(value: number, minimum: number, maximum: number): number {
  return Math.max(minimum, Math.min(maximum, value));
}
