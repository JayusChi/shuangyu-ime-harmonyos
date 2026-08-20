export interface SmartPeriodInputAction {
  sequence: number;
  timestampMs: number;
}

interface RecordedPeriod {
  sequence: number;
  timestampMs: number;
  generation: number;
}

/**
 * Tracks user input arrival order separately from the asynchronous editor
 * queue. This keeps the double-press window tied to the actual key presses,
 * even when committing a candidate delays the first period operation.
 */
export class SmartPeriodController {
  private nextSequence: number = 0;
  private previousPeriod?: RecordedPeriod;

  beginInput(timestampMs: number = Date.now()): SmartPeriodInputAction {
    this.nextSequence += 1;
    return {
      sequence: this.nextSequence,
      timestampMs: Number.isFinite(timestampMs) ? timestampMs : Date.now()
    };
  }

  shouldReplace(
    action: SmartPeriodInputAction,
    generation: number,
    timeoutMs: number
  ): boolean {
    const previous = this.previousPeriod;
    if (!previous || timeoutMs <= 0 || previous.generation !== generation ||
      action.sequence !== previous.sequence + 1) {
      return false;
    }
    const elapsed = action.timestampMs - previous.timestampMs;
    return elapsed >= 0 && elapsed <= timeoutMs;
  }

  recordPeriod(action: SmartPeriodInputAction, generation: number): void {
    this.previousPeriod = {
      sequence: action.sequence,
      timestampMs: action.timestampMs,
      generation
    };
  }

  clear(): void {
    this.previousPeriod = undefined;
  }
}
