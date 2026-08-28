import { vibrator } from '@kit.SensorServiceKit';
import { Logger } from '../../common/logging/Logger';
import { HapticLevel } from '../../domain/settings/ImeSettings';
import { SettingsStore, getSharedSettingsStore } from '../../state/SettingsStore';

const LOGGER = new Logger('HapticFeedback');

export interface HapticBackend {
  vibrate(durationMs: number): Promise<void>;
}

export class HarmonyHapticBackend implements HapticBackend {
  async vibrate(durationMs: number): Promise<void> {
    try {
      await vibrator.startVibration(
        { type: 'time', duration: durationMs },
        { usage: 'unknown' }
      );
    } catch (err) {
      throw new Error(`haptic request failed: ${JSON.stringify(err)}`);
    }
  }
}

export class HapticFeedbackService {
  private readonly backend: HapticBackend;
  private readonly settingsStore: SettingsStore;
  private lastDeleteFeedbackAt: number = 0;

  constructor(
    backend: HapticBackend = new HarmonyHapticBackend(),
    settingsStore: SettingsStore = getSharedSettingsStore()
  ) {
    this.backend = backend;
    this.settingsStore = settingsStore;
  }

  trigger(isRepeatedDelete: boolean = false, now: number = Date.now()): void {
    const level = this.settingsStore.getSnapshot().hapticLevel;
    if (level === HapticLevel.OFF) {
      return;
    }
    if (isRepeatedDelete && now - this.lastDeleteFeedbackAt < 120) {
      return;
    }
    if (isRepeatedDelete) {
      this.lastDeleteFeedbackAt = now;
    }
    this.backend.vibrate(this.duration(level)).catch((err: Object) => {
      LOGGER.debug(`haptic unavailable: ${JSON.stringify(err)}`);
    });
  }

  dispose(): void {
    this.lastDeleteFeedbackAt = 0;
  }

  private duration(level: HapticLevel): number {
    if (level === HapticLevel.STRONG) {
      return 24;
    }
    if (level === HapticLevel.MEDIUM) {
      return 16;
    }
    return 9;
  }
}
