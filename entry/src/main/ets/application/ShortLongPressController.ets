import { DEFAULT_LONG_PRESS_DURATION_MS } from '../domain/settings/ImeSettings';

export const INPUT_METHOD_SWITCH_LONG_PRESS_MS: number = DEFAULT_LONG_PRESS_DURATION_MS;

export enum ShortLongPressState {
  IDLE = 'idle',
  PRESSING = 'pressing',
  SHORT_PENDING = 'short_pending',
  LONG_TRIGGERED = 'long_triggered',
  CANCELLED = 'cancelled'
}

/**
 * 单个双动作按键的互斥状态机。长按回调一旦触发，随后 ArkUI onClick 会被消费，
 * 不会再触发短按。组件消失、Touch Cancel 或输入会话结束时可显式 cancel。
 */
export class ShortLongPressController {
  private readonly onShortPress: () => void;
  private readonly onLongPress: () => void;
  private readonly thresholdMs: number;
  private timer: number | null = null;
  private state: ShortLongPressState = ShortLongPressState.IDLE;

  constructor(
    onShortPress: () => void,
    onLongPress: () => void,
    thresholdMs: number = INPUT_METHOD_SWITCH_LONG_PRESS_MS
  ) {
    this.onShortPress = onShortPress;
    this.onLongPress = onLongPress;
    this.thresholdMs = thresholdMs;
  }

  start(): void {
    this.clearTimer();
    this.state = ShortLongPressState.PRESSING;
    this.timer = setTimeout((): void => {
      this.timer = null;
      if (this.state !== ShortLongPressState.PRESSING) {
        return;
      }
      this.state = ShortLongPressState.LONG_TRIGGERED;
      this.onLongPress();
    }, this.thresholdMs);
  }

  release(): void {
    this.clearTimer();
    if (this.state === ShortLongPressState.PRESSING) {
      this.state = ShortLongPressState.SHORT_PENDING;
    }
  }

  click(): void {
    // ArkUI may deliver onClick before TouchType.Up for injected/accessibility clicks, and
    // accessibility activation may produce only onClick. Both are valid short presses.
    if (this.state === ShortLongPressState.PRESSING) {
      this.clearTimer();
      this.state = ShortLongPressState.IDLE;
      this.onShortPress();
      return;
    }
    if (this.state === ShortLongPressState.SHORT_PENDING || this.state === ShortLongPressState.IDLE) {
      this.state = ShortLongPressState.IDLE;
      this.onShortPress();
      return;
    }
    if (this.state === ShortLongPressState.LONG_TRIGGERED || this.state === ShortLongPressState.CANCELLED) {
      this.state = ShortLongPressState.IDLE;
    }
  }

  cancel(): void {
    this.clearTimer();
    this.state = ShortLongPressState.CANCELLED;
  }

  destroy(): void {
    this.clearTimer();
    this.state = ShortLongPressState.IDLE;
  }

  getState(): ShortLongPressState {
    return this.state;
  }

  private clearTimer(): void {
    if (this.timer !== null) {
      clearTimeout(this.timer);
      this.timer = null;
    }
  }
}
