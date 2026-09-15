import { inputMethodEngine } from '@kit.IMEKit';
import { Logger } from '../../common/logging/Logger';

const TAG = 'Stage0ImeConnection';
const LOGGER = new Logger(TAG);

const FULL_PREVIEW_RANGE: inputMethodEngine.Range = { start: -1, end: -1 };
const COMPOSITION_RANGE_OBSERVATION_LIMIT = 3;
const PREVIEW_FINISH_SETTLEMENT_MAX_MS = 80;
const PREVIEW_FINISH_POLL_MS = 8;

export abstract class TextPreviewInputClient {
  abstract getTextIndexAtCursor(): Promise<number>;
  abstract setPreviewText(text: string, range: inputMethodEngine.Range): Promise<void>;
  abstract finishTextPreview(): Promise<void>;
}

const TEXT_PREVIEW_NOT_SUPPORTED = 12800011;

interface PreviewBusinessError extends Error {
  code: number;
}

class PreviewClientError extends Error {
  code: number;

  constructor(code: number) {
    super('InputClient setPreviewText failed');
    this.code = code;
  }
}

export enum PreviewUpdateResult {
  SUCCESS = 'SUCCESS',
  UNSUPPORTED = 'UNSUPPORTED',
  INDETERMINATE = 'INDETERMINATE'
}

export enum CompositionTextMode {
  NONE = 'NONE',
  PREVIEW = 'PREVIEW',
  /** 输入码仅由输入法候选区域自绘，不写入宿主编辑器。 */
  CANDIDATE_BAR = 'CANDIDATE_BAR',
  COMPATIBLE = 'COMPATIBLE'
}

export enum PreviewOwnershipState {
  CLEARED = 'CLEARED',
  ATTACHING = 'ATTACHING',
  OWNED = 'OWNED',
  CLEARING = 'CLEARING',
  COMMITTING = 'COMMITTING',
  FINISHING = 'FINISHING',
  CLOSED = 'CLOSED'
}

interface CandidateBarCommitResult {
  success: boolean;
  replacementStart?: number;
}

export abstract class CompositionInputClient extends TextPreviewInputClient {
  abstract getForward(length: number): Promise<string>;
  abstract selectByRange(range: inputMethodEngine.Range): Promise<void>;
  abstract insertText(text: string): Promise<boolean>;
  abstract deleteTextBeforeCursor(length: number): Promise<boolean>;
}

export class HarmonyCompositionInputClient extends CompositionInputClient {
  private readonly inputClient: inputMethodEngine.InputClient;

  constructor(inputClient: inputMethodEngine.InputClient) {
    super();
    this.inputClient = inputClient;
  }

  async getTextIndexAtCursor(): Promise<number> {
    try {
      return await this.inputClient.getTextIndexAtCursor();
    } catch (err) {
      throw new Error('InputClient composition cursor query failed');
    }
  }

  async getForward(length: number): Promise<string> {
    try {
      return await this.inputClient.getForward(length);
    } catch (err) {
      throw new Error('InputClient composition text query failed');
    }
  }

  async setPreviewText(text: string, range: inputMethodEngine.Range): Promise<void> {
    try {
      await this.inputClient.setPreviewText(text, range);
    } catch (err) {
      const error = err as PreviewBusinessError;
      throw new PreviewClientError(error.code);
    }
  }

  async finishTextPreview(): Promise<void> {
    try {
      await this.inputClient.finishTextPreview();
    } catch (err) {
      throw new Error('InputClient finishTextPreview failed');
    }
  }

  async selectByRange(range: inputMethodEngine.Range): Promise<void> {
    try {
      await this.inputClient.selectByRange(range);
    } catch (err) {
      throw new Error('InputClient composition selection failed');
    }
  }

  async insertText(text: string): Promise<boolean> {
    try {
      return await this.inputClient.insertText(text);
    } catch (err) {
      throw new Error('InputClient composition insert failed');
    }
  }

  async deleteTextBeforeCursor(length: number): Promise<boolean> {
    try {
      // HarmonyOS names deletion by the direction of the remaining text:
      // deleteForward removes text immediately before the cursor.
      return await this.inputClient.deleteForward(length);
    } catch (err) {
      throw new Error('InputClient composition delete failed');
    }
  }
}

/**
 * Owns the editor-side preview range for one bound InputClient.
 *
 * The first preview is inserted at the absolute editor cursor. Later updates
 * use HarmonyOS' {-1, -1} sentinel to replace the whole active preview range.
 */
export class TextPreviewManager {
  private previewStart: number = -1;
  private previewText: string = '';

  hasPreviewText(): boolean {
    return this.previewStart >= 0 && this.previewText.length > 0;
  }

  getPreviewText(): string {
    return this.previewText;
  }

  getPreviewStart(): number {
    return this.previewStart;
  }

  reset(): void {
    this.previewStart = -1;
    this.previewText = '';
  }

  async update(inputClient: TextPreviewInputClient, text: string): Promise<boolean> {
    return await this.updateDetailed(inputClient, text) === PreviewUpdateResult.SUCCESS;
  }

  async updateDetailed(inputClient: TextPreviewInputClient, text: string): Promise<PreviewUpdateResult> {
    if (text.length === 0) {
      return await this.clear(inputClient) ? PreviewUpdateResult.SUCCESS : PreviewUpdateResult.INDETERMINATE;
    }

    const range = this.hasPreviewText()
      ? FULL_PREVIEW_RANGE
      : await this.resolveReplacementRange(inputClient);
    if (!range) {
      return PreviewUpdateResult.INDETERMINATE;
    }
    try {
      await inputClient.setPreviewText(text, range);
      this.previewText = text;
      return PreviewUpdateResult.SUCCESS;
    } catch (err) {
      const error = err as PreviewBusinessError;
      return error.code === TEXT_PREVIEW_NOT_SUPPORTED
        ? PreviewUpdateResult.UNSUPPORTED
        : PreviewUpdateResult.INDETERMINATE;
    }
  }

  async commitReplacement(inputClient: TextPreviewInputClient, text: string): Promise<boolean> {
    if (!this.hasPreviewText() || text.length === 0) {
      return false;
    }
    try {
      const expectedCursor = this.previewStart + text.length;
      await inputClient.setPreviewText(text, FULL_PREVIEW_RANGE);
      this.previewText = text;
      await inputClient.finishTextPreview();
      // On HarmonyOS 6.1 the finish promise can resolve one task turn before
      // the editor has fully released its preview range. Give editor state a
      // turn to settle before a caller queries the cursor to anchor a new
      // compatible composition range.
      await this.waitForPreviewFinishSettlement(inputClient, expectedCursor);
      this.reset();
      return true;
    } catch (err) {
      // The request may already have reached the editor. Keep the last known
      // preview state and never retry with insertText/delete fallbacks.
      return false;
    }
  }

  async finish(inputClient: TextPreviewInputClient): Promise<boolean> {
    if (!this.hasPreviewText()) {
      return true;
    }
    try {
      await inputClient.finishTextPreview();
      this.reset();
      return true;
    } catch (err) {
      return false;
    }
  }

  async clear(inputClient: TextPreviewInputClient): Promise<boolean> {
    if (!this.hasPreviewText()) {
      this.reset();
      return true;
    }
    try {
      const expectedCursor = this.previewStart;
      await inputClient.setPreviewText('', FULL_PREVIEW_RANGE);
      this.previewText = '';
      await inputClient.finishTextPreview();
      // finishTextPreview() may resolve before an ArkUI editor publishes the
      // removal of the composing range.  Closed guide actions immediately
      // query or move the caret, so wait for the same bounded settlement used
      // by preview commits before reporting that the range has been cleared.
      await this.waitForPreviewFinishSettlement(inputClient, expectedCursor);
      this.reset();
      return true;
    } catch (err) {
      return false;
    }
  }

  private async resolveReplacementRange(
    inputClient: TextPreviewInputClient
  ): Promise<inputMethodEngine.Range | undefined> {
    if (this.hasPreviewText()) {
      return this.currentRange();
    }
    try {
      const cursor = await inputClient.getTextIndexAtCursor();
      if (!Number.isInteger(cursor) || cursor < 0) {
        return undefined;
      }
      this.previewStart = cursor;
      return { start: cursor, end: cursor };
    } catch (err) {
      return undefined;
    }
  }

  private currentRange(): inputMethodEngine.Range {
    return {
      start: this.previewStart,
      end: this.previewStart + this.previewText.length
    };
  }

  private async waitForPreviewFinishSettlement(
    inputClient: TextPreviewInputClient,
    expectedCursor: number
  ): Promise<void> {
    const deadline = Date.now() + PREVIEW_FINISH_SETTLEMENT_MAX_MS;
    while (true) {
      try {
        const cursor = await inputClient.getTextIndexAtCursor();
        if (cursor === expectedCursor) {
          return;
        }
      } catch (err) {
        // An editor may temporarily reject observation while releasing its
        // preview. Keep the same bounded fallback instead of retrying writes.
      }
      const remaining = deadline - Date.now();
      if (remaining <= 0) {
        return;
      }
      await new Promise<void>((resolve: () => void) => {
        setTimeout(resolve, Math.min(PREVIEW_FINISH_POLL_MS, remaining));
      });
    }
  }
}

/**
 * Synchronizes one IME-owned composition range with one input session.
 * It never retries an indeterminate preview write with insertText.
 */
export class CompositionTextManager {
  private mode: CompositionTextMode = CompositionTextMode.NONE;
  private generation: number = -1;
  private compatibleStart: number = -1;
  private compatibleText: string = '';
  private candidateBarText: string = '';
  private lastCommittedEnd: number = -1;
  private readonly previewManager: TextPreviewManager = new TextPreviewManager();
  private ownershipState: PreviewOwnershipState = PreviewOwnershipState.CLEARED;
  private operationTail: Promise<void> = Promise.resolve();

  getMode(): CompositionTextMode {
    return this.mode;
  }

  getTextLength(): number {
    if (this.mode === CompositionTextMode.PREVIEW) {
      return this.previewManager.getPreviewText().length;
    }
    if (this.mode === CompositionTextMode.CANDIDATE_BAR) {
      return this.candidateBarText.length;
    }
    return this.compatibleText.length;
  }

  getOwnershipState(): PreviewOwnershipState {
    return this.ownershipState;
  }

  reset(): void {
    this.mode = CompositionTextMode.NONE;
    this.generation = -1;
    this.compatibleStart = -1;
    this.compatibleText = '';
    this.candidateBarText = '';
    this.lastCommittedEnd = -1;
    this.previewManager.reset();
    this.ownershipState = PreviewOwnershipState.CLEARED;
  }

  private enqueue(operation: () => Promise<boolean>): Promise<boolean> {
    const current = this.operationTail.then(operation);
    this.operationTail = current.then(
      (): void => {
      },
      (): void => {
      }
    );
    return current;
  }

  /**
   * Returns false only when the editor can be read successfully and no longer
   * contains the IME-owned text immediately before its cursor. Read failures
   * are treated as indeterminate/attached so a transient platform error never
   * makes us duplicate text.
   */
  isTextAttached(
    inputClient: CompositionInputClient,
    generation: number,
    isCurrent: () => boolean = (): boolean => true
  ): Promise<boolean> {
    return this.enqueue((): Promise<boolean> => this.isTextAttachedNow(inputClient, generation, isCurrent));
  }

  private async isTextAttachedNow(
    inputClient: CompositionInputClient,
    generation: number,
    isCurrent: () => boolean
  ): Promise<boolean> {
    if (this.mode === CompositionTextMode.NONE) {
      return true;
    }
    if (!this.isBoundTo(generation) || !isCurrent()) {
      return true;
    }
    if (this.mode === CompositionTextMode.CANDIDATE_BAR) {
      return true;
    }
    const text = this.mode === CompositionTextMode.PREVIEW
      ? this.previewManager.getPreviewText()
      : this.compatibleText;
    if (text.length === 0) {
      return true;
    }

    let lastObservedCursor: number | undefined;
    for (let attempt = 0; attempt < COMPOSITION_RANGE_OBSERVATION_LIMIT; attempt += 1) {
      if (!isCurrent()) {
        return true;
      }
      try {
        const cursor = await inputClient.getTextIndexAtCursor();
        if (!Number.isInteger(cursor) || cursor < 0) {
          return true;
        }
        lastObservedCursor = cursor;
        if (cursor >= text.length) {
          const before = await inputClient.getForward(text.length);
          if (before === text && isCurrent()) {
            if (this.mode === CompositionTextMode.COMPATIBLE) {
              this.compatibleStart = cursor - text.length;
            }
            return true;
          }
        }
      } catch (err) {
        return true;
      }
      if (attempt + 1 < COMPOSITION_RANGE_OBSERVATION_LIMIT) {
        await this.waitForEditorSettlement();
      }
    }
    if (this.mode === CompositionTextMode.COMPATIBLE && this.compatibleStart >= 0 &&
      lastObservedCursor === this.compatibleStart + this.compatibleText.length) {
      // Browser Search can advance the cursor immediately while getForward()
      // still exposes the previous frame. The exact owned-range end is enough
      // to keep ownership: replaceCompatible() will append the next letter at
      // that cursor without freezing the existing raw text as committed ASCII.
      LOGGER.debug(
        `composition attachment text read lagged at owned end: length=${text.length}, generation=${generation}`
      );
      return true;
    }
    LOGGER.info(
      `composition text detached by editor: mode=${this.mode}, length=${text.length}, ` +
        `generation=${generation}`
    );
    return false;
  }

  update(
    inputClient: CompositionInputClient,
    text: string,
    previewSupported: boolean,
    generation: number,
    isCurrent: () => boolean = (): boolean => true,
    anchorAfterCandidateCommit: boolean = false,
    serializedContinuation: boolean = false
  ): Promise<boolean> {
    return this.enqueue((): Promise<boolean> => this.updateNow(
      inputClient,
      text,
      previewSupported,
      generation,
      isCurrent,
      anchorAfterCandidateCommit,
      serializedContinuation
    ));
  }

  private async updateNow(
    inputClient: CompositionInputClient,
    text: string,
    previewSupported: boolean,
    generation: number,
    isCurrent: () => boolean,
    anchorAfterCandidateCommit: boolean,
    serializedContinuation: boolean
  ): Promise<boolean> {
    if (!this.bindGeneration(generation) || !isCurrent()) {
      this.ownershipState = PreviewOwnershipState.CLOSED;
      this.logResult('update', generation, false);
      return false;
    }

    if (this.mode === CompositionTextMode.NONE && text.length === 0) {
      this.reset();
      return true;
    }

    const compatibleStartHint = anchorAfterCandidateCommit ? this.lastCommittedEnd : -1;
    this.lastCommittedEnd = -1;
    const previousOwnership = this.ownershipState;
    this.ownershipState = PreviewOwnershipState.ATTACHING;

    if (this.mode === CompositionTextMode.NONE && previewSupported) {
      const previewResult = await this.previewManager.updateDetailed(inputClient, text);
      if (!isCurrent()) {
        this.ownershipState = PreviewOwnershipState.CLOSED;
        return false;
      }
      if (previewResult === PreviewUpdateResult.SUCCESS) {
        this.mode = CompositionTextMode.PREVIEW;
        this.ownershipState = text.length > 0 ? PreviewOwnershipState.OWNED : PreviewOwnershipState.CLEARED;
        this.logResult('update', generation, true);
        return true;
      }
      if (previewResult !== PreviewUpdateResult.UNSUPPORTED) {
        this.ownershipState = previousOwnership;
        this.logResult('update-preview-indeterminate', generation, false);
        return false;
      }
      LOGGER.warn(`composition preview unsupported; using candidate-bar mode: generation=${generation}`);
    }

    if (this.mode === CompositionTextMode.PREVIEW) {
      const updated = await this.previewManager.update(inputClient, text);
      if (!isCurrent()) {
        this.ownershipState = PreviewOwnershipState.CLOSED;
        return false;
      }
      if (updated && text.length === 0) {
        this.reset();
      }
      this.ownershipState = updated && text.length > 0 ? PreviewOwnershipState.OWNED :
        (updated ? PreviewOwnershipState.CLEARED : previousOwnership);
      this.logResult('update', generation, updated);
      return updated;
    }

    if (this.mode === CompositionTextMode.NONE || this.mode === CompositionTextMode.CANDIDATE_BAR) {
      this.mode = CompositionTextMode.CANDIDATE_BAR;
      this.candidateBarText = text;
      if (text.length === 0) {
        this.reset();
      } else {
        this.ownershipState = PreviewOwnershipState.OWNED;
      }
      this.logResult('update-candidate-bar', generation, true);
      return true;
    }

    this.mode = CompositionTextMode.COMPATIBLE;
    const updated = await this.replaceCompatible(
      inputClient,
      text,
      generation,
      isCurrent,
      compatibleStartHint,
      serializedContinuation
    );
    if (updated && text.length === 0) {
      this.reset();
    } else if (updated) {
      this.ownershipState = PreviewOwnershipState.OWNED;
    } else {
      this.ownershipState = previousOwnership;
    }
    this.logResult('update', generation, updated);
    return updated;
  }

  commit(
    inputClient: CompositionInputClient,
    text: string,
    generation: number,
    isCurrent: () => boolean = (): boolean => true
  ): Promise<boolean> {
    return this.enqueue((): Promise<boolean> => this.commitNow(inputClient, text, generation, isCurrent));
  }

  /**
   * Commits the selected Chinese prefix and keeps any unconsumed raw tail in
   * the candidate bar. The remaining input code is never frozen into the
   * editor as plain committed ASCII.
   */
  commitWithRemaining(
    inputClient: CompositionInputClient,
    committedText: string,
    remainingRawInput: string,
    generation: number,
    isCurrent: () => boolean = (): boolean => true
  ): Promise<boolean> {
    return this.enqueue((): Promise<boolean> => this.commitWithRemainingNow(
      inputClient,
      committedText,
      remainingRawInput,
      generation,
      isCurrent
    ));
  }

  private async commitWithRemainingNow(
    inputClient: CompositionInputClient,
    committedText: string,
    remainingRawInput: string,
    generation: number,
    isCurrent: () => boolean
  ): Promise<boolean> {
    if (!this.isBoundTo(generation) || !isCurrent() || committedText.length === 0) {
      this.logResult('commit-with-remaining', generation, false);
      return false;
    }

    this.ownershipState = PreviewOwnershipState.COMMITTING;
    let replacementStart = -1;

    if (this.mode === CompositionTextMode.PREVIEW) {
      replacementStart = this.previewManager.getPreviewStart();
      const committed = await this.previewManager.commitReplacement(inputClient, committedText);
      if (!committed || !isCurrent()) {
        this.ownershipState = isCurrent() ? PreviewOwnershipState.OWNED : PreviewOwnershipState.CLOSED;
        this.logResult('commit-with-remaining', generation, false);
        return false;
      }
    } else if (this.mode === CompositionTextMode.CANDIDATE_BAR) {
      const commitResult = await this.commitCandidateBarText(
        inputClient,
        committedText,
        generation,
        isCurrent
      );
      if (!commitResult.success || !isCurrent()) {
        this.ownershipState = isCurrent() ? PreviewOwnershipState.OWNED : PreviewOwnershipState.CLOSED;
        this.logResult('commit-with-remaining', generation, false);
        return false;
      }
      if (commitResult.replacementStart !== undefined) {
        replacementStart = commitResult.replacementStart;
      }
    } else if (this.mode === CompositionTextMode.COMPATIBLE) {
      const replaced = await this.replaceCompatible(
        inputClient,
        committedText,
        generation,
        isCurrent
      );
      if (!replaced || !isCurrent()) {
        this.ownershipState = isCurrent() ? PreviewOwnershipState.OWNED : PreviewOwnershipState.CLOSED;
        this.logResult('commit-with-remaining', generation, false);
        return false;
      }
      replacementStart = this.compatibleStart;
      const observedStart = await this.waitForCandidateReplacementStart(
        inputClient,
        committedText,
        isCurrent
      );
      if (observedStart !== undefined) {
        replacementStart = observedStart;
      }
    } else {
      this.logResult('commit-with-remaining', generation, false);
      return false;
    }

    const committedEnd = replacementStart >= 0 ? replacementStart + committedText.length : -1;
    if (remainingRawInput.length === 0) {
      this.reset();
      if (committedEnd >= 0) {
        this.lastCommittedEnd = committedEnd;
      }
      this.logResult('commit-with-remaining', generation, true);
      return true;
    }

    this.mode = CompositionTextMode.CANDIDATE_BAR;
    this.generation = generation;
    this.compatibleStart = -1;
    this.compatibleText = '';
    this.candidateBarText = remainingRawInput;
    if (committedEnd >= 0) {
      this.lastCommittedEnd = committedEnd;
    }
    this.ownershipState = PreviewOwnershipState.OWNED;
    this.logResult('commit-with-remaining', generation, true);
    return true;
  }

  private async commitNow(
    inputClient: CompositionInputClient,
    text: string,
    generation: number,
    isCurrent: () => boolean
  ): Promise<boolean> {
    if (!isCurrent() || text.length === 0) {
      this.logResult('commit', generation, false);
      return false;
    }
    // Literal paired symbols can be pressed while no Chinese composition is
    // active. Bind that idle transaction and insert the pair once through the
    // same observed candidate-bar commit path; the caller can then position
    // the cursor between the two delimiters without synthesizing a raw input.
    if (this.mode === CompositionTextMode.NONE) {
      if (!this.bindGeneration(generation)) {
        this.logResult('commit-idle', generation, false);
        return false;
      }
      this.ownershipState = PreviewOwnershipState.COMMITTING;
      const idleCommit = await this.commitCandidateBarText(inputClient, text, generation, isCurrent);
      if (!isCurrent()) {
        this.ownershipState = PreviewOwnershipState.CLOSED;
        return false;
      }
      this.reset();
      if (idleCommit.success && idleCommit.replacementStart !== undefined) {
        this.lastCommittedEnd = idleCommit.replacementStart + text.length;
      }
      this.logResult('commit-idle', generation, idleCommit.success);
      return idleCommit.success;
    }
    if (!this.isBoundTo(generation)) {
      this.logResult('commit', generation, false);
      return false;
    }
    this.ownershipState = PreviewOwnershipState.COMMITTING;
    if (this.mode === CompositionTextMode.PREVIEW) {
      const committedEnd = this.previewManager.getPreviewStart() + text.length;
      const committed = await this.previewManager.commitReplacement(inputClient, text);
      if (!isCurrent()) {
        this.ownershipState = PreviewOwnershipState.CLOSED;
        return false;
      }
      if (!committed) {
        this.ownershipState = PreviewOwnershipState.OWNED;
      }
      if (committed) {
        this.reset();
        this.lastCommittedEnd = committedEnd;
      }
      this.logResult('commit', generation, committed);
      return committed;
    }
    if (this.mode === CompositionTextMode.CANDIDATE_BAR) {
      const commitResult = await this.commitCandidateBarText(inputClient, text, generation, isCurrent);
      if (!isCurrent()) {
        this.ownershipState = PreviewOwnershipState.CLOSED;
        return false;
      }
      if (commitResult.success) {
        this.reset();
        if (commitResult.replacementStart !== undefined) {
          this.lastCommittedEnd = commitResult.replacementStart + text.length;
        }
      } else {
        this.ownershipState = PreviewOwnershipState.OWNED;
      }
      this.logResult('commit-candidate-bar', generation, commitResult.success);
      return commitResult.success;
    }
    if (this.mode !== CompositionTextMode.COMPATIBLE) {
      return false;
    }
    const committed = await this.replaceCompatible(inputClient, text, generation, isCurrent);
    if (committed) {
      // replaceCompatible may have repaired a stale editor cursor anchor.
      // Preserve the end derived from that authoritative range, not the
      // pre-repair value, for a following partial composition.
      const committedEnd = this.compatibleStart + text.length;
      this.reset();
      this.lastCommittedEnd = committedEnd;
    } else {
      this.ownershipState = PreviewOwnershipState.OWNED;
    }
    this.logResult('commit', generation, committed);
    return committed;
  }

  finish(
    inputClient: CompositionInputClient,
    generation: number,
    isCurrent: () => boolean = (): boolean => true
  ): Promise<boolean> {
    return this.enqueue((): Promise<boolean> => this.finishNow(inputClient, generation, isCurrent));
  }

  private async finishNow(
    inputClient: CompositionInputClient,
    generation: number,
    isCurrent: () => boolean
  ): Promise<boolean> {
    if (this.mode === CompositionTextMode.NONE) {
      return true;
    }
    if (!this.isBoundTo(generation) || !isCurrent()) {
      this.ownershipState = PreviewOwnershipState.CLOSED;
      return false;
    }
    this.ownershipState = PreviewOwnershipState.FINISHING;
    if (this.mode === CompositionTextMode.COMPATIBLE || this.mode === CompositionTextMode.CANDIDATE_BAR) {
      this.reset();
      this.logResult('finish', generation, true);
      return true;
    }
    const finished = await this.previewManager.finish(inputClient);
    if (!isCurrent()) {
      this.ownershipState = PreviewOwnershipState.CLOSED;
      return false;
    }
    if (finished) {
      this.reset();
    } else {
      this.ownershipState = PreviewOwnershipState.OWNED;
    }
    this.logResult('finish', generation, finished);
    return finished;
  }

  clear(
    inputClient: CompositionInputClient,
    generation: number,
    isCurrent: () => boolean = (): boolean => true
  ): Promise<boolean> {
    return this.enqueue((): Promise<boolean> => this.clearNow(inputClient, generation, isCurrent));
  }

  private async clearNow(
    inputClient: CompositionInputClient,
    generation: number,
    isCurrent: () => boolean
  ): Promise<boolean> {
    if (this.mode === CompositionTextMode.NONE) {
      this.reset();
      return true;
    }
    if (!this.isBoundTo(generation) || !isCurrent()) {
      this.ownershipState = PreviewOwnershipState.CLOSED;
      return false;
    }
    this.ownershipState = PreviewOwnershipState.CLEARING;
    if (this.mode === CompositionTextMode.CANDIDATE_BAR) {
      this.reset();
      this.logResult('clear-candidate-bar', generation, true);
      return true;
    }
    if (this.mode === CompositionTextMode.PREVIEW) {
      const cleared = await this.previewManager.clear(inputClient);
      if (!isCurrent()) {
        this.ownershipState = PreviewOwnershipState.CLOSED;
        return false;
      }
      if (cleared) {
        this.reset();
      } else {
        this.ownershipState = PreviewOwnershipState.OWNED;
      }
      this.logResult('clear', generation, cleared);
      return cleared;
    }
    const cleared = await this.replaceCompatible(inputClient, '', generation, isCurrent);
    if (cleared) {
      this.reset();
    } else {
      this.ownershipState = PreviewOwnershipState.OWNED;
    }
    this.logResult('clear', generation, cleared);
    return cleared;
  }

  private bindGeneration(generation: number): boolean {
    if (this.generation < 0) {
      this.generation = generation;
    }
    return this.generation === generation;
  }

  private isBoundTo(generation: number): boolean {
    return this.generation === generation;
  }

  private async replaceCompatible(
    inputClient: CompositionInputClient,
    text: string,
    generation: number,
    isCurrent: () => boolean,
    compatibleStartHint: number = -1,
    serializedContinuation: boolean = false
  ): Promise<boolean> {
    if (this.compatibleStart < 0 || this.compatibleText.length === 0) {
      if (text.length === 0) {
        return true;
      }
      let cursorBeforeInsert: number | undefined;
      if (compatibleStartHint >= 0) {
        try {
          await inputClient.selectByRange({
            start: compatibleStartHint,
            end: compatibleStartHint
          });
        } catch (err) {
          return false;
        }
        if (!isCurrent()) {
          return false;
        }
        cursorBeforeInsert = compatibleStartHint;
      } else {
        cursorBeforeInsert = await this.readCursor(inputClient);
      }
      if (cursorBeforeInsert === undefined || cursorBeforeInsert < 0 || !isCurrent()) {
        return false;
      }
      let inserted = false;
      try {
        inserted = await inputClient.insertText(text);
      } catch (err) {
        LOGGER.warn(`composition compatible insert indeterminate: generation=${generation}`);
        return false;
      }
      if (!inserted || !isCurrent()) {
        return false;
      }
      // Some HarmonyOS editors resolve insertText before their cursor query
      // catches up.  The pre-insert cursor can therefore be one character
      // ahead of the real insertion point (notably browser Search fields).
      // Re-anchor from the confirmed text immediately before the live cursor;
      // keep the old/hinted anchor only when the editor has not settled yet.
      const liveStart = await this.resolveCompatibleTextStart(
        inputClient,
        text,
        isCurrent
      );
      if (!isCurrent()) {
        return false;
      }
      this.compatibleStart = liveStart ?? cursorBeforeInsert;
      this.compatibleText = text;
      return true;
    }

    // Fast typing normally extends the owned raw composition by one letter.
    // If the cursor is still exactly at the verified range end, append only
    // that suffix. This avoids reading the whole prefix again, selecting the
    // old range and reinserting an ever-growing string on every hardware key.
    if (text.length > this.compatibleText.length && text.startsWith(this.compatibleText)) {
      if (!isCurrent()) {
        return false;
      }
      // A rapid hardware continuation cannot be separated from its preceding
      // successful action by another editor operation: both are in the same
      // FIFO. Append the suffix immediately instead of paying for another
      // cursor round-trip. Non-burst updates retain the full ownership check.
      if (serializedContinuation) {
        const suffix = text.slice(this.compatibleText.length);
        try {
          const inserted = await inputClient.insertText(suffix);
          if (!inserted || !isCurrent()) {
            return false;
          }
        } catch (err) {
          LOGGER.warn(`composition compatible serialized append indeterminate: generation=${generation}`);
          return false;
        }
        this.compatibleText = text;
        return true;
      }
      const cursor = await this.readCursor(inputClient);
      const expectedEnd = this.compatibleStart + this.compatibleText.length;
      if (cursor === expectedEnd && isCurrent()) {
        const suffix = text.slice(this.compatibleText.length);
        try {
          const inserted = await inputClient.insertText(suffix);
          if (!inserted || !isCurrent()) {
            return false;
          }
        } catch (err) {
          LOGGER.warn(`composition compatible append indeterminate: generation=${generation}`);
          return false;
        }
        this.compatibleText = text;
        return true;
      }
    }

    const storedRange = this.compatibleRange();
    let range = await this.resolveCompatibleRange(inputClient, isCurrent);
    if (!range && text.length === 0 && isCurrent()) {
      const cursor = await this.readCursor(inputClient);
      if (cursor === storedRange.end && isCurrent()) {
        // Some HarmonyOS TextInput implementations accept our serialized
        // insertions but cannot immediately return them through getForward.
        // Clearing is still safe while the live cursor remains exactly at the
        // end of the IME-owned range; a moved cursor never takes this path.
        range = storedRange;
      }
    }
    if (!range || !isCurrent()) {
      LOGGER.warn(
        `composition compatible range detached: start=${storedRange.start}, ` +
          `end=${storedRange.end}, generation=${generation}`
      );
      return false;
    }
    if (text.length === 0) {
      try {
        const deleted = await inputClient.deleteTextBeforeCursor(range.end - range.start);
        if (!deleted || !isCurrent()) {
          return false;
        }
      } catch (err) {
        LOGGER.warn(`composition compatible clear indeterminate: generation=${generation}`);
        return false;
      }
      this.compatibleText = '';
      this.compatibleStart = -1;
      return true;
    }
    try {
      await inputClient.selectByRange(range);
    } catch (err) {
      return false;
    }
    if (!isCurrent()) {
      return false;
    }
    try {
      const inserted = await inputClient.insertText(text);
      if (!inserted || !isCurrent()) {
        return false;
      }
    } catch (err) {
      LOGGER.warn(`composition compatible replacement indeterminate: generation=${generation}`);
      return false;
    }
    this.compatibleText = text;
    if (text.length === 0) {
      this.compatibleStart = -1;
    }
    return true;
  }

  /**
   * Commits candidate text without ever staging the raw input code in the
   * editor. PC compatibility editors can require an explicit collapsed
   * selection before accepting insertText, and some adapters report false
   * even though the mutation has already reached the document. Anchor first,
   * then use the observable text at the cursor as the final acknowledgement.
   */
  private async commitCandidateBarText(
    inputClient: CompositionInputClient,
    text: string,
    generation: number,
    isCurrent: () => boolean
  ): Promise<CandidateBarCommitResult> {
    if (text.length === 0 || !isCurrent()) {
      return { success: false };
    }

    const cursorBeforeInsert = await this.readCursor(inputClient);
    if (!isCurrent()) {
      return { success: false };
    }
    if (cursorBeforeInsert !== undefined) {
      try {
        await inputClient.selectByRange({
          start: cursorBeforeInsert,
          end: cursorBeforeInsert
        });
      } catch (err) {
        // Native Harmony editors accept insertion without an explicit anchor.
        // Keep that standard path available when a host cannot select ranges.
        LOGGER.warn(`candidate commit cursor anchor unavailable: generation=${generation}`);
      }
      if (!isCurrent()) {
        return { success: false };
      }
    }

    let acknowledged = false;
    try {
      acknowledged = await inputClient.insertText(text);
    } catch (err) {
      // A thrown IPC result is indeterminate: do not retry the write and risk
      // duplicating text that may already have reached the host application.
      LOGGER.warn(`candidate commit insert indeterminate: generation=${generation}`);
      return { success: false };
    }
    if (!isCurrent()) {
      return { success: false };
    }

    const observedStart = await this.waitForCandidateReplacementStart(inputClient, text, isCurrent);
    if (!isCurrent()) {
      return { success: false };
    }
    if (observedStart !== undefined) {
      if (!acknowledged) {
        LOGGER.warn(`candidate commit accepted from editor observation: generation=${generation}`);
      }
      return { success: true, replacementStart: observedStart };
    }
    if (!acknowledged) {
      return { success: false };
    }
    return {
      success: true,
      replacementStart: cursorBeforeInsert
    };
  }

  private async resolveCompatibleRange(
    inputClient: CompositionInputClient,
    isCurrent: () => boolean
  ): Promise<inputMethodEngine.Range | undefined> {
    const start = await this.resolveCompatibleTextStart(
      inputClient,
      this.compatibleText,
      isCurrent
    );
    if (start === undefined || !isCurrent()) {
      return undefined;
    }
    // The text immediately before the current cursor is authoritative.  This
    // repairs a stale initial cursor anchor without touching unrelated text.
    this.compatibleStart = start;
    return this.compatibleRange();
  }

  private async resolveCompatibleTextStart(
    inputClient: CompositionInputClient,
    text: string,
    isCurrent: () => boolean
  ): Promise<number | undefined> {
    if (text.length === 0) {
      return undefined;
    }
    for (let attempt = 0; attempt < COMPOSITION_RANGE_OBSERVATION_LIMIT; attempt += 1) {
      if (!isCurrent()) {
        return undefined;
      }
      try {
        const cursor = await inputClient.getTextIndexAtCursor();
        if (Number.isInteger(cursor) && cursor >= text.length) {
          const before = await inputClient.getForward(text.length);
          if (before === text && isCurrent()) {
            return cursor - text.length;
          }
        }
      } catch (err) {
        return undefined;
      }
      if (attempt + 1 < COMPOSITION_RANGE_OBSERVATION_LIMIT) {
        await this.waitForEditorSettlement();
      }
    }
    return undefined;
  }

  private async waitForCandidateReplacementStart(
    inputClient: CompositionInputClient,
    text: string,
    isCurrent: () => boolean
  ): Promise<number | undefined> {
    for (let attempt = 0; attempt < 6; attempt += 1) {
      if (!isCurrent()) {
        return undefined;
      }
      try {
        const cursor = await inputClient.getTextIndexAtCursor();
        if (Number.isInteger(cursor) && cursor >= text.length) {
          const before = await inputClient.getForward(text.length);
          if (before === text && isCurrent()) {
            return cursor - text.length;
          }
        }
      } catch (err) {
        return undefined;
      }
      if (attempt < 5) {
        await new Promise<void>((resolve: () => void) => setTimeout(resolve, 16));
      }
    }
    LOGGER.warn(`candidate replacement settlement not observable: length=${text.length}`);
    return undefined;
  }

  private async readCursor(inputClient: CompositionInputClient): Promise<number | undefined> {
    try {
      const cursor = await inputClient.getTextIndexAtCursor();
      return Number.isInteger(cursor) && cursor >= 0 ? cursor : undefined;
    } catch (err) {
      return undefined;
    }
  }

  private compatibleRange(): inputMethodEngine.Range {
    return {
      start: this.compatibleStart,
      end: this.compatibleStart + this.compatibleText.length
    };
  }

  private waitForEditorSettlement(): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, 0);
    });
  }

  private logResult(operation: string, generation: number, success: boolean): void {
    const range = this.mode === CompositionTextMode.COMPATIBLE && this.compatibleStart >= 0
      ? `${this.compatibleStart}-${this.compatibleStart + this.compatibleText.length}`
      : 'none';
    LOGGER.debug(
      `composition operation=${operation}, mode=${this.mode}, length=${this.getTextLength()}, ` +
        `range=${range}, generation=${generation}, success=${success}`
    );
  }
}
