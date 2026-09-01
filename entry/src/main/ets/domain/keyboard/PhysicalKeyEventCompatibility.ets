import { PhysicalKeySnapshot } from './PhysicalKeyboardRouting';

/** Input-method framework event channel used for physical keyboard delivery. */
export enum PhysicalKeyEventChannel {
  MODERN = 'modern',
  LEGACY = 'legacy'
}

interface PhysicalKeyDecisionRecord {
  channel: PhysicalKeyEventChannel;
  keyCode: number;
  isDown: boolean;
  timestampMs: number;
  handled: boolean;
}

const KEYCODE_ALT_LEFT = 2045;
const KEYCODE_ALT_RIGHT = 2046;
const KEYCODE_SHIFT_LEFT = 2047;
const KEYCODE_SHIFT_RIGHT = 2048;
const KEYCODE_CTRL_LEFT = 2072;
const KEYCODE_CTRL_RIGHT = 2073;
const KEYCODE_META_LEFT = 2076;
const KEYCODE_META_RIGHT = 2077;

/**
 * Reconstructs modifier state for the API 8 keyDown/keyUp callback. That
 * callback only exposes keyCode/keyAction, unlike the API 10 keyEvent shape.
 */
export class LegacyPhysicalKeyState {
  private pressedModifierKeyCodes: number[] = [];

  snapshot(keyCode: number, isDown: boolean): PhysicalKeySnapshot {
    this.updateModifierState(keyCode, isDown);
    return {
      isDown,
      unicodeChar: 0,
      keyCode,
      ctrlKey: this.hasEither(KEYCODE_CTRL_LEFT, KEYCODE_CTRL_RIGHT),
      altKey: this.hasEither(KEYCODE_ALT_LEFT, KEYCODE_ALT_RIGHT),
      logoKey: this.hasEither(KEYCODE_META_LEFT, KEYCODE_META_RIGHT),
      shiftKey: this.hasEither(KEYCODE_SHIFT_LEFT, KEYCODE_SHIFT_RIGHT)
    };
  }

  reset(): void {
    this.pressedModifierKeyCodes = [];
  }

  private updateModifierState(keyCode: number, isDown: boolean): void {
    if (!this.isModifier(keyCode)) {
      return;
    }
    const index = this.pressedModifierKeyCodes.indexOf(keyCode);
    if (isDown && index < 0) {
      this.pressedModifierKeyCodes.push(keyCode);
    } else if (!isDown && index >= 0) {
      this.pressedModifierKeyCodes.splice(index, 1);
    }
  }

  private hasEither(leftKeyCode: number, rightKeyCode: number): boolean {
    return this.pressedModifierKeyCodes.indexOf(leftKeyCode) >= 0 ||
      this.pressedModifierKeyCodes.indexOf(rightKeyCode) >= 0;
  }

  private isModifier(keyCode: number): boolean {
    return keyCode === KEYCODE_ALT_LEFT || keyCode === KEYCODE_ALT_RIGHT ||
      keyCode === KEYCODE_SHIFT_LEFT || keyCode === KEYCODE_SHIFT_RIGHT ||
      keyCode === KEYCODE_CTRL_LEFT || keyCode === KEYCODE_CTRL_RIGHT ||
      keyCode === KEYCODE_META_LEFT || keyCode === KEYCODE_META_RIGHT;
  }
}

/**
 * Some hosts emit both keyboard-delegate APIs for one native key. Preserve the
 * first callback's consumed decision for the matching cross-channel callback,
 * while never suppressing repeat events delivered through the same channel.
 *
 * DOWN and UP callbacks can be delivered as a complete pair on one API before
 * the other API starts its pair. Keeping only the globally last callback loses
 * the earlier DOWN and dispatches one physical key twice. Recent decisions are
 * therefore matched by `(keyCode, phase)` and consumed exactly once.
 */
export class PhysicalKeyEventDeduplicator {
  private recentDecisions: PhysicalKeyDecisionRecord[] = [];
  private readonly duplicateWindowMs: number;

  constructor(duplicateWindowMs: number = 80) {
    this.duplicateWindowMs = duplicateWindowMs;
  }

  findDuplicateDecision(
    channel: PhysicalKeyEventChannel,
    key: PhysicalKeySnapshot,
    timestampMs: number
  ): boolean | undefined {
    this.prune(timestampMs);
    for (let index = this.recentDecisions.length - 1; index >= 0; index -= 1) {
      const decision = this.recentDecisions[index];
      if (decision.channel !== channel && decision.keyCode === key.keyCode &&
        decision.isDown === key.isDown) {
        this.recentDecisions.splice(index, 1);
        return decision.handled;
      }
    }
    return undefined;
  }

  record(
    channel: PhysicalKeyEventChannel,
    key: PhysicalKeySnapshot,
    handled: boolean,
    timestampMs: number
  ): void {
    this.prune(timestampMs);
    this.recentDecisions.push({
      channel,
      keyCode: key.keyCode,
      isDown: key.isDown,
      timestampMs,
      handled
    });
  }

  reset(): void {
    this.recentDecisions = [];
  }

  private prune(timestampMs: number): void {
    this.recentDecisions = this.recentDecisions.filter((decision: PhysicalKeyDecisionRecord): boolean => {
      const elapsedMs = timestampMs - decision.timestampMs;
      return elapsedMs >= 0 && elapsedMs <= this.duplicateWindowMs;
    });
  }
}
