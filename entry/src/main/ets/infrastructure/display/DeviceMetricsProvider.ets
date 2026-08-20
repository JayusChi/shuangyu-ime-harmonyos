import display from '@ohos.display';
import {
  createScreenMetrics,
  RawScreenMetricsPx,
  SAFE_FALLBACK_SCREEN_METRICS_PX,
  ScreenMetricsPx
} from '../../domain/display/ScreenMetrics';

export interface DeviceMetricsProvider {
  getMetrics(preferredIsLandscape?: boolean): ScreenMetricsPx;
}

export class HarmonyDeviceMetricsProvider implements DeviceMetricsProvider {
  getMetrics(preferredIsLandscape?: boolean): ScreenMetricsPx {
    try {
      const displayInfo = display.getDefaultDisplaySync();
      const raw: RawScreenMetricsPx = {
        widthPx: displayInfo.width,
        heightPx: displayInfo.height,
        densityPixels: displayInfo.densityPixels
      };
      return createScreenMetrics(raw, preferredIsLandscape);
    } catch (err) {
      const fallback: RawScreenMetricsPx = {
        widthPx: SAFE_FALLBACK_SCREEN_METRICS_PX.widthPx,
        heightPx: SAFE_FALLBACK_SCREEN_METRICS_PX.heightPx,
        densityPixels: SAFE_FALLBACK_SCREEN_METRICS_PX.densityPixels
      };
      return createScreenMetrics(fallback, preferredIsLandscape);
    }
  }
}
