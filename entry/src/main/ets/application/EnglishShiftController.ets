import { ShiftState } from '../domain/editor/EditorContext';

export const SHIFT_DOUBLE_TAP_WINDOW_MS = 400;

export class EnglishShiftController {
  private state: ShiftState = ShiftState.LOWERCASE;
  private lastShiftTapTimestamp: number = -1;

  getState(): ShiftState {
    return this.state;
  }

  pressShift(timestamp: number): ShiftState {
    if (this.state === ShiftState.CAPS_LOCK) {
      this.reset();
      return this.state;
    }

    if (this.state === ShiftState.ONE_SHOT_UPPERCASE) {
      const elapsed = timestamp - this.lastShiftTapTimestamp;
      if (elapsed >= 0 && elapsed <= SHIFT_DOUBLE_TAP_WINDOW_MS) {
        this.state = ShiftState.CAPS_LOCK;
        this.lastShiftTapTimestamp = -1;
        return this.state;
      }
      this.reset();
      return this.state;
    }

    this.state = ShiftState.ONE_SHOT_UPPERCASE;
    this.lastShiftTapTimestamp = timestamp;
    return this.state;
  }

  transformLetter(letter: string): string {
    if (this.state === ShiftState.LOWERCASE) {
      return letter.toLowerCase();
    }
    return letter.toUpperCase();
  }

  letterCommitted(): ShiftState {
    if (this.state === ShiftState.ONE_SHOT_UPPERCASE) {
      this.reset();
    }
    return this.state;
  }

  reset(): void {
    this.state = ShiftState.LOWERCASE;
    this.lastShiftTapTimestamp = -1;
  }
}
