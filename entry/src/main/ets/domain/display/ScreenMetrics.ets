export interface RawScreenMetricsPx {
  widthPx: number;
  heightPx: number;
  densityPixels: number;
  bottomSystemInsetPx?: number;
}

export interface ScreenMetricsPx {
  widthPx: number;
  heightPx: number;
  densityPixels: number;
  isLandscape: boolean;
  /** IME fixed panel 与底部系统面板之间的距离，单位 px。 */
  bottomSystemInsetPx?: number;
}

const MIN_SHORT_SIDE_VP: number = 240;
const MIN_LONG_SIDE_VP: number = 320;
const MAX_SIDE_VP: number = 10000;
const MIN_DENSITY: number = 0.5;
const MAX_DENSITY: number = 8;

export const SAFE_FALLBACK_SCREEN_METRICS_PX: ScreenMetricsPx = {
  widthPx: 1080,
  heightPx: 2340,
  densityPixels: 3,
  isLandscape: false,
  bottomSystemInsetPx: 0
};

function isFinitePositive(value: number): boolean {
  return Number.isFinite(value) && value > 0;
}

export function isRawScreenMetricsUsable(metrics: RawScreenMetricsPx): boolean {
  if (!isFinitePositive(metrics.widthPx) || !isFinitePositive(metrics.heightPx) ||
    !isFinitePositive(metrics.densityPixels)) {
    return false;
  }
  if (metrics.densityPixels < MIN_DENSITY || metrics.densityPixels > MAX_DENSITY) {
    return false;
  }
  const widthVp = metrics.widthPx / metrics.densityPixels;
  const heightVp = metrics.heightPx / metrics.densityPixels;
  const shortSideVp = Math.min(widthVp, heightVp);
  const longSideVp = Math.max(widthVp, heightVp);
  return shortSideVp >= MIN_SHORT_SIDE_VP && longSideVp >= MIN_LONG_SIDE_VP &&
    longSideVp <= MAX_SIDE_VP;
}

export function createScreenMetrics(
  rawMetrics: RawScreenMetricsPx,
  preferredIsLandscape?: boolean
): ScreenMetricsPx {
  const usable = isRawScreenMetricsUsable(rawMetrics);
  let widthPx = usable ? rawMetrics.widthPx : SAFE_FALLBACK_SCREEN_METRICS_PX.widthPx;
  let heightPx = usable ? rawMetrics.heightPx : SAFE_FALLBACK_SCREEN_METRICS_PX.heightPx;
  const densityPixels = usable ? rawMetrics.densityPixels : SAFE_FALLBACK_SCREEN_METRICS_PX.densityPixels;
  const rawBottomInset = usable ? rawMetrics.bottomSystemInsetPx : 0;
  const bottomSystemInsetPx = rawBottomInset !== undefined && Number.isFinite(rawBottomInset) && rawBottomInset >= 0
    ? Math.min(rawBottomInset, heightPx)
    : 0;
  const dimensionsAreLandscape = widthPx > heightPx;
  const isLandscape = preferredIsLandscape === undefined ? dimensionsAreLandscape : preferredIsLandscape;

  // Configuration is authoritative during rotation. Some devices update display dimensions one callback later,
  // so normalize the pair instead of publishing a new direction with stale portrait dimensions (or vice versa).
  if (isLandscape !== dimensionsAreLandscape) {
    const previousWidth = widthPx;
    widthPx = heightPx;
    heightPx = previousWidth;
  }
  return { widthPx, heightPx, densityPixels, isLandscape, bottomSystemInsetPx };
}

export function copyScreenMetrics(metrics: ScreenMetricsPx): ScreenMetricsPx {
  return {
    widthPx: metrics.widthPx,
    heightPx: metrics.heightPx,
    densityPixels: metrics.densityPixels,
    isLandscape: metrics.isLandscape,
    bottomSystemInsetPx: metrics.bottomSystemInsetPx ?? 0
  };
}

export function withBottomSystemInset(metrics: ScreenMetricsPx, bottomSystemInsetPx: number): ScreenMetricsPx {
  return createScreenMetrics({
    widthPx: metrics.widthPx,
    heightPx: metrics.heightPx,
    densityPixels: metrics.densityPixels,
    bottomSystemInsetPx
  }, metrics.isLandscape);
}

export function screenMetricsEqual(left: ScreenMetricsPx, right: ScreenMetricsPx): boolean {
  return left.widthPx === right.widthPx && left.heightPx === right.heightPx &&
    left.densityPixels === right.densityPixels && left.isLandscape === right.isLandscape &&
    (left.bottomSystemInsetPx ?? 0) === (right.bottomSystemInsetPx ?? 0);
}

export function pxToVp(px: number, metrics: ScreenMetricsPx): number {
  return px / metrics.densityPixels;
}

export function vpToPx(vp: number, metrics: ScreenMetricsPx): number {
  return Math.round(vp * metrics.densityPixels);
}
