import { KeyboardHeightMode } from '../../../domain/settings/ImeSettings';
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
  keyBorderRadius: 6,
  letterFontSize: 14,
  functionFontSize: 11,
  previewFontSize: 22
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
  keyBorderRadius: 5,
  letterFontSize: 13,
  functionFontSize: 10,
  previewFontSize: 20
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
  LONG_PRESS_DELAY_MS: 500,    // 长按触发阈值
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
  screenMetrics?: ScreenMetricsPx
): OrientationMetrics {
  if (screenMetrics) {
    return calculateDynamicMetrics(screenMetrics, heightMode);
  }
  const base = isLandscape ? LANDSCAPE_METRICS : PORTRAIT_METRICS;
  if (heightMode === KeyboardHeightMode.STANDARD) {
    return base;
  }
  const scale = heightMode === KeyboardHeightMode.COMPACT ? 0.88 : 1.12;
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
    letterFontSize: base.letterFontSize,
    functionFontSize: base.functionFontSize,
    previewFontSize: base.previewFontSize
  };
}

/**
 * 根据同一份屏幕 px 快照计算 ArkUI 使用的 vp 度量。
 */
export function calculateDynamicMetrics(
  screenMetrics: ScreenMetricsPx,
  heightMode: KeyboardHeightMode = KeyboardHeightMode.STANDARD
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

  let keyboardHeightRatio = isLandscape ? 0.55 : 0.38;
  if (heightMode === KeyboardHeightMode.COMPACT) {
    keyboardHeightRatio *= 0.88;
  } else if (heightMode === KeyboardHeightMode.TALL) {
    keyboardHeightRatio *= 1.12;
  }

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

  // 字母保持清晰但不抢占键帽留白；手机、横屏和 Pad 共用同一比例与上限。
  const letterFontSize = clamp(Math.round(letterKeyHeight * 0.31), 12, 18);
  const functionFontSize = clamp(Math.round(letterKeyHeight * 0.24), 9, 14);
  const previewFontSize = clamp(Math.round(letterFontSize * 1.5), 18, 27);

  const keyBorderRadius = isLandscape ? 5 : 6;

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
    previewFontSize
  };
}

export function panelHeightForMode(
  mode: KeyboardHeightMode,
  screenMetrics: ScreenMetricsPx = SAFE_FALLBACK_SCREEN_METRICS_PX,
  pinyin9ChineseLayout: boolean = false
): number {
  const validMetrics = createScreenMetrics({
    widthPx: screenMetrics.widthPx,
    heightPx: screenMetrics.heightPx,
    densityPixels: screenMetrics.densityPixels,
    bottomSystemInsetPx: screenMetrics.bottomSystemInsetPx
  }, screenMetrics.isLandscape);
  const metrics = calculateDynamicMetrics(validMetrics, mode);
  const panelHeightVp = calculateTotalKeyboardHeight(metrics, pinyin9ChineseLayout) + 6;
  const panelHeightPx = vpToPx(panelHeightVp, validMetrics);
  return clamp(panelHeightPx, 1, Math.round(validMetrics.heightPx));
}

/**
 * 计算键盘总高度
 */
export function calculateTotalKeyboardHeight(
  metrics: OrientationMetrics,
  pinyin9ChineseLayout: boolean = false
): number {
  // 3.2 起顶部状态栏始终存在；候选内容可隐藏，但固定收起按钮不能消失。
  const candidateSection = metrics.candidateBarHeight;
  const keyboardRows = pinyin9ChineseLayout ? 5 : 4;
  const primaryRows = pinyin9ChineseLayout ? 4 : 3;
  const keyboardHeight =
    (metrics.letterKeyHeight * primaryRows) +
    metrics.functionKeyRowHeight +
    (metrics.rowSpacing * (keyboardRows - 1));
  const pinyinSection = pinyin9ChineseLayout ? metrics.pinyinCombinationBarHeight : 0;

  return candidateSection + pinyinSection + keyboardHeight + metrics.bottomPadding;
}

function clamp(value: number, minimum: number, maximum: number): number {
  return Math.max(minimum, Math.min(maximum, value));
}
