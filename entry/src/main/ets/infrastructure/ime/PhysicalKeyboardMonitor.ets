import inputDevice from '@ohos.multimodalInput.inputDevice';
import { Logger } from '../../common/logging/Logger';

const TAG = 'PhysicalKeyboardMonitor';
const LOGGER = new Logger(TAG);

export type PhysicalKeyboardListener = (present: boolean) => void;

export interface PhysicalKeyboardStateProvider {
  start(listener: PhysicalKeyboardListener): void;
  stop(): void;
  isPresent(): boolean;
}

/** Detects a full hardware keyboard from InputKit device capabilities. */
export class PhysicalKeyboardMonitor implements PhysicalKeyboardStateProvider {
  private present: boolean = false;
  private started: boolean = false;
  private listener?: PhysicalKeyboardListener;
  private readonly onDeviceChanged = (_event: inputDevice.DeviceListener): void => {
    this.refresh();
  };

  start(listener: PhysicalKeyboardListener): void {
    this.listener = listener;
    if (!this.started) {
      try {
        inputDevice.on('change', this.onDeviceChanged);
        this.started = true;
      } catch (err) {
        LOGGER.warn(`device listener unavailable: ${JSON.stringify(err)}`);
      }
    }
    this.refresh();
  }

  stop(): void {
    if (this.started) {
      try {
        inputDevice.off('change', this.onDeviceChanged);
      } catch (err) {
        LOGGER.warn(`device listener cleanup failed: ${JSON.stringify(err)}`);
      }
    }
    this.started = false;
    this.listener = undefined;
    this.present = false;
  }

  isPresent(): boolean {
    return this.present;
  }

  private refresh(): void {
    inputDevice.getDeviceList().then(async (deviceIds: number[]): Promise<void> => {
      let detected = false;
      for (let index = 0; index < deviceIds.length; index += 1) {
        try {
          const type = await inputDevice.getKeyboardType(deviceIds[index]);
          if (type === inputDevice.KeyboardType.ALPHABETIC_KEYBOARD) {
            detected = true;
            break;
          }
        } catch (err) {
          LOGGER.debug(`keyboard type query skipped: ${JSON.stringify(err)}`);
        }
      }
      if (this.present !== detected) {
        this.present = detected;
        this.listener?.(detected);
      }
    }).catch((err: Object): void => {
      LOGGER.warn(`input device list unavailable: ${JSON.stringify(err)}`);
      if (this.present) {
        this.present = false;
        this.listener?.(false);
      }
    });
  }
}
