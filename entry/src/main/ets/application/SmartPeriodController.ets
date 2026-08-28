export interface SmartPeriodInputAction {
  sequence: number;
  timestampMs: number;
}

interface RecordedPunctuation {
  sequence: number;
  timestampMs: number;
  generation: number;
  sourceText: string;
  targetText: string;
}

/**
 * Tracks user input arrival order separately from the asynchronous editor
 * queue. This keeps the double-press window tied to the actual key presses,
 * even when committing a candidate delays the first punctuation operation.
 */
export class SmartPeriodController {
  private nextSequence: number = 0;
  private previousPunctuation?: RecordedPunctuation;

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
    timeoutMs: number,
    targetText: string
  ): string | undefined {
    const previous = this.previousPunctuation;
    if (!previous || timeoutMs <= 0 || previous.generation !== generation ||
      action.sequence !== previous.sequence + 1 || previous.targetText !== targetText) {
      return undefined;
    }
    const elapsed = action.timestampMs - previous.timestampMs;
    return elapsed >= 0 && elapsed <= timeoutMs ? previous.sourceText : undefined;
  }

  recordPunctuation(
    action: SmartPeriodInputAction,
    generation: number,
    sourceText: string,
    targetText: string
  ): void {
    this.previousPunctuation = {
      sequence: action.sequence,
      timestampMs: action.timestampMs,
      generation,
      sourceText,
      targetText
    };
  }

  clear(): void {
    this.previousPunctuation = undefined;
  }
}
