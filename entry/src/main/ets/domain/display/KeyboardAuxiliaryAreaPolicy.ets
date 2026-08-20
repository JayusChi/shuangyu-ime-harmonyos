import { ScreenMetricsPx } from './ScreenMetrics';

export enum KeyboardDeviceFormFactor {
  PHONE = 'phone',
  TABLET = 'tablet'
}

export interface KeyboardAuxiliaryAreaPolicy {
  formFactor: KeyboardDeviceFormFactor;
  showInlineInputMethodKey: boolean;
  hasSystemInputMethodArea: boolean;
  bottomSystemInsetVp: number;
}

/** 所有阈值和尺寸均为 vp；系统面板 inset 在策略入口统一由 px 转换。 */
export const TABLET_MIN_SHORT_SIDE_VP: number = 600;
const NARROW_PHONE_MAX_WIDTH_VP: number = 320;
const WIDE_PHONE_MIN_WIDTH_VP: number = 500;

function clamp(value: number, minimum: number, maximum: number): number {
  return Math.max(minimum, Math.min(maximum, value));
}

/**
 * 只根据当前窗口快照决定形态和输入法切换入口，不读取机型、品牌或产品名称。
 * 手机永不新增底部辅助行；没有系统输入法区域或窗口尺寸特殊时，把显式入口放进
 * 现有功能键行。标准竖屏手机由“中/英”键长按提供后备入口。
 */
export function resolveKeyboardAuxiliaryAreaPolicy(
  screenMetrics: ScreenMetricsPx
): KeyboardAuxiliaryAreaPolicy {
  const density = Number.isFinite(screenMetrics.densityPixels) && screenMetrics.densityPixels > 0
    ? screenMetrics.densityPixels
    : 1;
  const widthVp = screenMetrics.widthPx / density;
  const heightVp = screenMetrics.heightPx / density;
  const bottomSystemInsetVp = clamp((screenMetrics.bottomSystemInsetPx ?? 0) / density, 0, heightVp);
  const availableHeightVp = Math.max(0, heightVp - bottomSystemInsetVp);
  const availableShortSideVp = Math.min(widthVp, availableHeightVp);
  const formFactor = availableShortSideVp >= TABLET_MIN_SHORT_SIDE_VP
    ? KeyboardDeviceFormFactor.TABLET
    : KeyboardDeviceFormFactor.PHONE;
  const hasSystemInputMethodArea = bottomSystemInsetVp > 0;
  const specialPhoneLayout = formFactor === KeyboardDeviceFormFactor.PHONE &&
    (screenMetrics.isLandscape || widthVp < NARROW_PHONE_MAX_WIDTH_VP || widthVp >= WIDE_PHONE_MIN_WIDTH_VP);
  const showInlineInputMethodKey = formFactor === KeyboardDeviceFormFactor.TABLET ||
    specialPhoneLayout || !hasSystemInputMethodArea;

  return {
    formFactor,
    showInlineInputMethodKey,
    hasSystemInputMethodArea,
    bottomSystemInsetVp
  };
}
