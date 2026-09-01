import {
  ShortLongPressController,
  ShortLongPressState
} from './ShortLongPressController';

export const KEY_SWIPE_UP_THRESHOLD_VP: number = 18;
export const KEY_SWIPE_DOWN_THRESHOLD_VP: number = KEY_SWIPE_UP_THRESHOLD_VP;
// Letter keys are the fastest and most frequent touch targets. Requiring a
// longer, more vertical travel keeps a quick diagonal tap from selecting the
// upper-deck symbol while function-key gestures retain their existing reach.
export const LETTER_KEY_SWIPE_THRESHOLD_VP: number = 28;
export const KEY_SWIPE_VERTICAL_DOMINANCE_RATIO: number = 1.35;

/**
 * Keeps tap, long-press and vertical swipes mutually exclusive for a key.
 * ArkUI emits onClick after touch-up, so the internal short/long controller
 * also consumes that click after either alternate gesture has fired.
 */
export class AlternateKeyGestureController {
  private readonly pressController: ShortLongPressController;
  private readonly onSwipeUp: () => void;
  private readonly onSwipeDown: () => void;
  private readonly swipeThresholdVp: number;
  private startX: number = 0;
  private startY: number = 0;
  private swipeTriggered: boolean = false;

  constructor(
    onShortPress: () => void,
    onLongPress: () => void,
    onSwipeUp: () => void,
    longPressThresholdMs?: number,
    onSwipeDown: () => void = (): void => {},
    swipeThresholdVp: number = KEY_SWIPE_UP_THRESHOLD_VP
  ) {
    this.pressController = new ShortLongPressController(
      onShortPress,
      onLongPress,
      longPressThresholdMs
    );
    this.onSwipeUp = onSwipeUp;
    this.onSwipeDown = onSwipeDown;
    this.swipeThresholdVp = swipeThresholdVp;
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
    const verticalDistance = y - this.startY;
    const absoluteVerticalDistance = Math.abs(verticalDistance);
    const horizontalDistance = Math.abs(x - this.startX);
    if (absoluteVerticalDistance < this.swipeThresholdVp ||
      absoluteVerticalDistance < horizontalDistance * KEY_SWIPE_VERTICAL_DOMINANCE_RATIO) {
      return false;
    }
    this.swipeTriggered = true;
    this.pressController.cancel();
    if (verticalDistance < 0) {
      this.onSwipeUp();
    } else {
      this.onSwipeDown();
    }
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
