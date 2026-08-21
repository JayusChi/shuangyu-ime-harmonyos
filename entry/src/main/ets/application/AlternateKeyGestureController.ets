import {
  ShortLongPressController,
  ShortLongPressState
} from './ShortLongPressController';

export const KEY_SWIPE_UP_THRESHOLD_VP: number = 18;

/**
 * Keeps tap, long-press and upward-swipe mutually exclusive for a key.
 * ArkUI emits onClick after touch-up, so the internal short/long controller
 * also consumes that click after either alternate gesture has fired.
 */
export class AlternateKeyGestureController {
  private readonly pressController: ShortLongPressController;
  private readonly onSwipeUp: () => void;
  private startX: number = 0;
  private startY: number = 0;
  private swipeTriggered: boolean = false;

  constructor(
    onShortPress: () => void,
    onLongPress: () => void,
    onSwipeUp: () => void,
    longPressThresholdMs?: number
  ) {
    this.pressController = new ShortLongPressController(
      onShortPress,
      onLongPress,
      longPressThresholdMs
    );
    this.onSwipeUp = onSwipeUp;
  }

  start(x: number, y: number): void {
    this.startX = x;
    this.startY = y;
    this.swipeTriggered = false;
    this.pressController.start();
  }

  move(x: number, y: number): boolean {
    if (this.swipeTriggered || this.pressController.getState() !== ShortLongPressState.PRESSING) {
      return false;
    }
    const upwardDistance = this.startY - y;
    const horizontalDistance = Math.abs(x - this.startX);
    if (upwardDistance < KEY_SWIPE_UP_THRESHOLD_VP || upwardDistance <= horizontalDistance) {
      return false;
    }
    this.swipeTriggered = true;
    this.pressController.cancel();
    this.onSwipeUp();
    return true;
  }

  release(): void {
    if (!this.swipeTriggered) {
      this.pressController.release();
    }
  }

  click(): void {
    this.pressController.click();
    this.swipeTriggered = false;
  }

  cancel(): void {
    this.pressController.cancel();
    this.swipeTriggered = false;
  }

  destroy(): void {
    this.pressController.destroy();
    this.swipeTriggered = false;
  }
}
