import { inputMethodEngine } from '@kit.IMEKit';
import { Logger } from '../../common/logging/Logger';
import { EnterAction } from '../../domain/editor/EditorContext';
import { EditorExtendAction } from '../../domain/keyboard/KeyboardAction';
import {
  CompositionTextMode,
  CompositionTextManager,
  HarmonyCompositionInputClient
} from './ImePreviewService';
import {
  DeleteResult,
  HarmonyDeleteInputClient,
  SafeDeleteExecutor
} from './ImeDeleteService';
import { PairInsertionService, PairInsertResult } from './PairInsertionService';
import { ImeConnectionLifecycle } from './ImeConnectionLifecycle';
import { resolveCurrentLineRange } from '../../domain/editor/CurrentLineRange';
import {
  DELETION_RECOVERY_CONTEXT_UNITS,
  DeletionRecoveryManager,
  DeletionRecoveryRecord
} from '../../domain/editor/DeletionRecovery';

export {
  CompositionInputClient,
  CompositionTextManager,
  CompositionTextMode,
  PreviewOwnershipState,
  PreviewUpdateResult,
  TextPreviewInputClient,
  TextPreviewManager
} from './ImePreviewService';
export {
  DeleteInputClient,
  DeleteResult,
  SafeDeleteExecutor
} from './ImeDeleteService';
export { PairInsertResult } from './PairInsertionService';

const TAG = 'Stage0ImeConnection';
const LOGGER = new Logger(TAG);

const LINE_END_QUERY_UNITS = 4096;
const LINE_END_QUERY_LIMIT = 128;
const CURRENT_LINE_QUERY_UNITS = 4096;
const COPY_DISPATCH_SETTLE_MS = 500;
const EDITOR_ACTION_TEXT_QUERY_UNITS = 65536;

interface EditorSelectionSnapshot {
  readonly text: string;
  readonly caretAfterSelection: number;
}

export abstract class EditorExtendInputClient {
  abstract getTextIndexAtCursor(): Promise<number>;
  abstract getTextBeforeCursor(length: number): Promise<string>;
  abstract getTextAfterCursor(length: number): Promise<string>;
  abstract insertText(text: string): Promise<boolean>;
  abstract sendExtendAction(action: inputMethodEngine.ExtendAction): Promise<void>;
  abstract moveCursor(direction: inputMethodEngine.Direction): Promise<void>;
  abstract selectByRange(range: inputMethodEngine.Range): Promise<void>;
}

export class HarmonyEditorExtendInputClient extends EditorExtendInputClient {
  private readonly inputClient: inputMethodEngine.InputClient;

  constructor(inputClient: inputMethodEngine.InputClient) {
    super();
    this.inputClient = inputClient;
  }

  async getTextIndexAtCursor(): Promise<number> {
    try {
      return this.inputClient.getTextIndexAtCursor();
    } catch (err) {
      throw new Error(`cursor index query failed: ${JSON.stringify(err)}`);
    }
  }

  async getTextBeforeCursor(length: number): Promise<string> {
    try {
      return this.inputClient.getForward(length);
    } catch (err) {
      throw new Error(`forward text query failed: ${JSON.stringify(err)}`);
    }
  }

  async getTextAfterCursor(length: number): Promise<string> {
    try {
      return this.inputClient.getBackward(length);
    } catch (err) {
      throw new Error(`backward text query failed: ${JSON.stringify(err)}`);
    }
  }

  async insertText(text: string): Promise<boolean> {
    try {
      return this.inputClient.insertText(text);
    } catch (err) {
      throw new Error(`editor text insertion failed: ${JSON.stringify(err)}`);
    }
  }

  async sendExtendAction(action: inputMethodEngine.ExtendAction): Promise<void> {
    try {
      await this.inputClient.sendExtendAction(action);
    } catch (err) {
      throw new Error(`editor extend action failed: ${JSON.stringify(err)}`);
    }
  }

  async moveCursor(direction: inputMethodEngine.Direction): Promise<void> {
    try {
      await this.inputClient.moveCursor(direction);
    } catch (err) {
      throw new Error(`editor cursor movement failed: ${JSON.stringify(err)}`);
    }
  }

  async selectByRange(range: inputMethodEngine.Range): Promise<void> {
    try {
      await this.inputClient.selectByRange(range);
    } catch (err) {
      throw new Error(`editor range selection failed: ${JSON.stringify(err)}`);
    }
  }
}

export class EditorExtendActionExecutor {
  private readonly copyDispatchSettleMs: number;
  private selectedText: EditorSelectionSnapshot | undefined = undefined;
  private copiedText: string | undefined = undefined;

  constructor(copyDispatchSettleMs: number = COPY_DISPATCH_SETTLE_MS) {
    this.copyDispatchSettleMs = Math.max(0, copyDispatchSettleMs);
  }

  async execute(
    inputClient: EditorExtendInputClient,
    action: EditorExtendAction,
    stillConnected: () => boolean = (): boolean => true
  ): Promise<boolean> {
    try {
      if (action === EditorExtendAction.SELECT_ALL) {
        this.selectedText = await this.captureAllText(inputClient);
        if (!stillConnected()) {
          return false;
        }
      }
      if (action === EditorExtendAction.PASTE && this.copiedText !== undefined) {
        // HarmonyOS 6.1 independent editors reject a PASTE extend action with
        // READ_PASTEBOARD/SECURE_PASTE even when it follows a visible keyboard
        // gesture. Text copied through this keyboard is already available in
        // process, so insert it directly and keep the native action as the
        // fallback for clipboard content copied elsewhere.
        const inserted = await inputClient.insertText(this.copiedText);
        LOGGER.info(`editor cached paste: success=${inserted}, length=${this.copiedText.length}`);
        return inserted && stillConnected();
      }
      // HarmonyOS COPY deliberately preserves the editor selection. Capture
      // its caret end before dispatch so a successful copy has visible
      // feedback and a following PASTE inserts after the copied range instead
      // of replacing that same range with identical text.
      let copyCaret: number = -1;
      if (action === EditorExtendAction.COPY) {
        try {
          copyCaret = await inputClient.getTextIndexAtCursor();
        } catch (_cursorErr) {
          LOGGER.warn('copy caret query failed; preserving host selection');
        }
        if (!stillConnected()) {
          return false;
        }
        if (this.selectedText !== undefined &&
          this.selectedText.caretAfterSelection === copyCaret) {
          this.copiedText = this.selectedText.text;
        }
      }
      let nativeAction = inputMethodEngine.ExtendAction.SELECT_ALL;
      if (action === EditorExtendAction.CUT) {
        nativeAction = inputMethodEngine.ExtendAction.CUT;
      } else if (action === EditorExtendAction.COPY) {
        nativeAction = inputMethodEngine.ExtendAction.COPY;
      } else if (action === EditorExtendAction.PASTE) {
        nativeAction = inputMethodEngine.ExtendAction.PASTE;
      }
      await inputClient.sendExtendAction(nativeAction);
      if (!stillConnected()) {
        return false;
      }
      if (action === EditorExtendAction.COPY && Number.isInteger(copyCaret) && copyCaret >= 0) {
        // sendExtendAction resolves when the command has been queued, while
        // several ArkUI text controls read the selected range on the next UI
        // turn. Keep the selection alive for that bounded dispatch window so
        // the host copies real text before we collapse it.
        await this.waitForCopyDispatch();
        if (!stillConnected()) {
          return false;
        }
        try {
          // `selectByRange` resolves without changing selection in some 6.1
          // independent text controls because their range listener is absent.
          // A native right-cursor command follows the editor's ordinary arrow
          // semantics and collapses an active selection to its trailing caret.
          await inputClient.moveCursor(inputMethodEngine.Direction.CURSOR_RIGHT);
        } catch (_movementErr) {
          try {
            await inputClient.selectByRange({ start: copyCaret, end: copyCaret });
          } catch (_selectionErr) {
            // The copy itself already completed; failure to collapse selection
            // must not incorrectly report that the clipboard operation failed.
            LOGGER.warn('copy completed but selection collapse failed');
          }
        }
      }
      if (action === EditorExtendAction.CUT && this.selectedText !== undefined) {
        this.copiedText = this.selectedText.text;
      }
      if (action === EditorExtendAction.CUT || action === EditorExtendAction.COPY) {
        this.selectedText = undefined;
      }
      LOGGER.info(`editor extend action ok: action=${action}`);
      return stillConnected();
    } catch (_err) {
      LOGGER.warn(`editor extend action failed: action=${action}`);
      return false;
    }
  }

  private waitForCopyDispatch(): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, this.copyDispatchSettleMs);
    });
  }

  private async captureAllText(
    inputClient: EditorExtendInputClient
  ): Promise<EditorSelectionSnapshot | undefined> {
    try {
      const cursor = await inputClient.getTextIndexAtCursor();
      const before = await inputClient.getTextBeforeCursor(EDITOR_ACTION_TEXT_QUERY_UNITS);
      const after = await inputClient.getTextAfterCursor(EDITOR_ACTION_TEXT_QUERY_UNITS);
      if (before.length >= EDITOR_ACTION_TEXT_QUERY_UNITS ||
        after.length >= EDITOR_ACTION_TEXT_QUERY_UNITS) {
        LOGGER.warn('select-all text exceeds cached clipboard limit');
        return undefined;
      }
      return {
        text: before + after,
        caretAfterSelection: cursor + after.length
      };
    } catch (_err) {
      LOGGER.warn('select-all text snapshot failed; using native clipboard only');
      return undefined;
    }
  }
}

export abstract class CurrentLineInputClient {
  abstract getTextIndexAtCursor(): Promise<number>;
  abstract getTextBeforeCursor(length: number): Promise<string>;
  abstract getTextAfterCursor(length: number): Promise<string>;
  abstract deleteTextBeforeCursor(length: number): Promise<boolean>;
  abstract deleteTextAfterCursor(length: number): Promise<boolean>;
  abstract insertText(text: string): Promise<boolean>;
}

export class HarmonyCurrentLineInputClient extends CurrentLineInputClient {
  private readonly inputClient: inputMethodEngine.InputClient;

  constructor(inputClient: inputMethodEngine.InputClient) {
    super();
    this.inputClient = inputClient;
  }

  async getTextIndexAtCursor(): Promise<number> {
    try {
      return this.inputClient.getTextIndexAtCursor();
    } catch (err) {
      throw new Error(`line cursor index query failed: ${JSON.stringify(err)}`);
    }
  }

  async getTextBeforeCursor(length: number): Promise<string> {
    try {
      return this.inputClient.getForward(length);
    } catch (err) {
      throw new Error(`line forward text query failed: ${JSON.stringify(err)}`);
    }
  }

  async getTextAfterCursor(length: number): Promise<string> {
    try {
      return this.inputClient.getBackward(length);
    } catch (err) {
      throw new Error(`line backward text query failed: ${JSON.stringify(err)}`);
    }
  }

  async deleteTextBeforeCursor(length: number): Promise<boolean> {
    try {
      return this.inputClient.deleteForward(length);
    } catch (err) {
      throw new Error(`line forward deletion failed: ${JSON.stringify(err)}`);
    }
  }

  async deleteTextAfterCursor(length: number): Promise<boolean> {
    try {
      return this.inputClient.deleteBackward(length);
    } catch (err) {
      throw new Error(`line backward deletion failed: ${JSON.stringify(err)}`);
    }
  }

  async insertText(text: string): Promise<boolean> {
    try {
      return this.inputClient.insertText(text);
    } catch (err) {
      throw new Error(`line recovery insertion failed: ${JSON.stringify(err)}`);
    }
  }
}

/** Deletes one logical line without depending on the optional range listener. */
export class CurrentLineDeleteExecutor {
  async execute(
    inputClient: CurrentLineInputClient,
    stillConnected: () => boolean = (): boolean => true
  ): Promise<DeletionRecoveryRecord | undefined> {
    const cursor = await inputClient.getTextIndexAtCursor();
    const before = await inputClient.getTextBeforeCursor(CURRENT_LINE_QUERY_UNITS);
    const after = await inputClient.getTextAfterCursor(CURRENT_LINE_QUERY_UNITS);
    if (!stillConnected()) {
      return undefined;
    }
    const range = resolveCurrentLineRange(
      cursor,
      before,
      after,
      before.length >= CURRENT_LINE_QUERY_UNITS,
      after.length >= CURRENT_LINE_QUERY_UNITS
    );
    if (range === undefined) {
      return undefined;
    }

    const beforeUnits = cursor - range.start;
    const afterUnits = range.end - cursor;
    const beforeText = before.slice(before.length - beforeUnits);
    const afterText = after.slice(0, afterUnits);
    const record: DeletionRecoveryRecord = {
      text: beforeText + afterText,
      start: range.start,
      beforeContext: before.slice(0, before.length - beforeUnits),
      afterContext: after.slice(afterUnits)
    };

    // Delete the right half first so the caret remains at the original index;
    // deleting the left half then lands it exactly at record.start. HarmonyOS
    // names these APIs after the remaining-text direction: deleteBackward
    // removes text after the caret and deleteForward removes text before it.
    if (afterUnits > 0) {
      const deletedAfter = await inputClient.deleteTextAfterCursor(afterUnits);
      if (!deletedAfter || !stillConnected()) {
        return undefined;
      }
    }
    if (beforeUnits > 0) {
      const deletedBefore = await inputClient.deleteTextBeforeCursor(beforeUnits);
      if (!deletedBefore || !stillConnected()) {
        // The right half may already be gone. Restore it while we still own
        // the same editor so a failed gesture never leaves a partial line.
        if (afterText.length > 0 && stillConnected()) {
          try {
            await inputClient.insertText(afterText);
          } catch (_rollbackErr) {
          }
        }
        return undefined;
      }
    }
    return stillConnected() ? record : undefined;
  }
}

export class ImeConnectionService extends ImeConnectionLifecycle {
  private readonly safeDeleteExecutor: SafeDeleteExecutor = new SafeDeleteExecutor();
  private readonly pairInsertionService: PairInsertionService = new PairInsertionService();
  private readonly editorExtendActionExecutor: EditorExtendActionExecutor =
    new EditorExtendActionExecutor();
  private readonly currentLineDeleteExecutor: CurrentLineDeleteExecutor = new CurrentLineDeleteExecutor();
  private readonly deletionRecoveryManager: DeletionRecoveryManager = new DeletionRecoveryManager();
  private deletionOwner?: inputMethodEngine.InputClient;

  async insertText(text: string): Promise<boolean> {
    const inputClient = ImeConnectionService.inputClient;
    if (!inputClient) {
      LOGGER.error('insertText failed: no input client');
      return false;
    }

    try {
      const inserted = await inputClient.insertText(text);
      if (!inserted) {
        LOGGER.warn(`insertText returned false: length=${text.length}`);
        return false;
      }
      this.clearDeletionRecovery();
      LOGGER.info(`insertText ok: length=${text.length}`);
      return true;
    } catch (err) {
      LOGGER.error('insertText failed');
      return false;
    }
  }

  async setPreviewText(
    text: string,
    previewSupported: boolean = true,
    generation: number = 0,
    anchorAfterCandidateCommit: boolean = false,
    serializedContinuation: boolean = false
  ): Promise<boolean> {
    const inputClient = ImeConnectionService.inputClient;
    if (!inputClient) {
      LOGGER.error('setPreviewText failed: no input client');
      return false;
    }
    const manager = ImeConnectionService.compositionTextManager;
    const updated = await manager.update(
      new HarmonyCompositionInputClient(inputClient),
      text,
      previewSupported,
      generation,
      (): boolean => ImeConnectionService.inputClient === inputClient &&
        ImeConnectionService.compositionTextManager === manager,
      anchorAfterCandidateCommit,
      serializedContinuation
    );
    if (!updated) {
      LOGGER.warn(`setPreviewText failed: length=${text.length}`);
      return false;
    }
    LOGGER.debug(`setPreviewText ok: length=${text.length}`);
    return true;
  }

  isCursorPreviewActive(): boolean {
    return ImeConnectionService.compositionTextManager.getMode() === CompositionTextMode.PREVIEW;
  }

  async isPreviewTextAttached(generation: number = 0): Promise<boolean> {
    const inputClient = ImeConnectionService.inputClient;
    if (!inputClient) {
      return true;
    }
    const manager = ImeConnectionService.compositionTextManager;
    return manager.isTextAttached(
      new HarmonyCompositionInputClient(inputClient),
      generation,
      (): boolean => ImeConnectionService.inputClient === inputClient &&
        ImeConnectionService.compositionTextManager === manager
    );
  }

  async commitPreviewText(text: string, generation: number = 0): Promise<boolean> {
    const inputClient = ImeConnectionService.inputClient;
    if (!inputClient) {
      LOGGER.error('commitPreviewText failed: no input client');
      return false;
    }
    const manager = ImeConnectionService.compositionTextManager;
    const committed = await manager.commit(
      new HarmonyCompositionInputClient(inputClient),
      text,
      generation,
      (): boolean => ImeConnectionService.inputClient === inputClient &&
        ImeConnectionService.compositionTextManager === manager
    );
    if (!committed) {
      LOGGER.warn(`commitPreviewText failed: length=${text.length}`);
      return false;
    }
    LOGGER.info(`commitPreviewText ok: length=${text.length}`);
    return true;
  }

  async commitCandidatePreviewText(
    committedText: string,
    remainingRawInput: string,
    generation: number = 0
  ): Promise<boolean> {
    const inputClient = ImeConnectionService.inputClient;
    if (!inputClient) {
      LOGGER.error('commitCandidatePreviewText failed: no input client');
      return false;
    }
    const manager = ImeConnectionService.compositionTextManager;
    const committed = await manager.commitWithRemaining(
      new HarmonyCompositionInputClient(inputClient),
      committedText,
      remainingRawInput,
      generation,
      (): boolean => ImeConnectionService.inputClient === inputClient &&
        ImeConnectionService.compositionTextManager === manager
    );
    if (!committed) {
      LOGGER.warn(
        `commitCandidatePreviewText failed: committedLength=${committedText.length}, ` +
          `remainingLength=${remainingRawInput.length}`
      );
      return false;
    }
    LOGGER.info(
      `commitCandidatePreviewText ok: committedLength=${committedText.length}, ` +
        `remainingLength=${remainingRawInput.length}`
    );
    return true;
  }

  async insertPairText(
    text: string,
    cursorOffsetUtf16: number,
    generation: number = 0
  ): Promise<PairInsertResult> {
    const inputClient = ImeConnectionService.inputClient;
    const manager = ImeConnectionService.compositionTextManager;
    return this.pairInsertionService.insert(
      inputClient,
      manager,
      text,
      cursorOffsetUtf16,
      generation,
      (): boolean => ImeConnectionService.inputClient === inputClient &&
        ImeConnectionService.compositionTextManager === manager
    );
  }

  hasPendingPair(generation: number = 0): boolean {
    return this.pairInsertionService.hasPending(generation);
  }

  async jumpOutPair(generation: number = 0): Promise<boolean> {
    const inputClient = ImeConnectionService.inputClient;
    return this.pairInsertionService.jumpOut(
      inputClient,
      generation,
      (): boolean => ImeConnectionService.inputClient === inputClient
    );
  }

  clearPairState(): void {
    this.pairInsertionService.clear();
  }

  async finishPreviewText(generation: number = 0): Promise<boolean> {
    const inputClient = ImeConnectionService.inputClient;
    if (!inputClient) {
      LOGGER.error('finishPreviewText failed: no input client');
      return false;
    }
    const manager = ImeConnectionService.compositionTextManager;
    const finished = await manager.finish(
      new HarmonyCompositionInputClient(inputClient),
      generation,
      (): boolean => ImeConnectionService.inputClient === inputClient &&
        ImeConnectionService.compositionTextManager === manager
    );
    if (!finished) {
      LOGGER.warn('finishPreviewText failed');
    }
    return finished;
  }

  async clearPreviewText(generation: number = 0): Promise<boolean> {
    const inputClient = ImeConnectionService.inputClient;
    if (!inputClient) {
      ImeConnectionService.compositionTextManager.reset();
      return true;
    }
    const manager = ImeConnectionService.compositionTextManager;
    const cleared = await manager.clear(
      new HarmonyCompositionInputClient(inputClient),
      generation,
      // The captured manager/client pair belongs to the retiring generation.
      // It is safe—and necessary—to finish clearing it after a new static
      // session has been bound. The manager's generation check prevents a
      // stale request from targeting a different ownership transaction.
      (): boolean => true
    );
    if (!cleared) {
      LOGGER.warn('clearPreviewText failed');
    }
    return cleared;
  }

  resetPreviewState(): void {
    ImeConnectionService.resetCompositionTextManager();
  }

  async deleteBackward(count: number = 1): Promise<boolean> {
    const inputClient = ImeConnectionService.inputClient;
    if (!inputClient) {
      LOGGER.error('delete connection invalid: no input client');
      return false;
    }

    const pending = await this.captureBackwardDeletion(inputClient, count);
    const result = await this.safeDeleteExecutor.execute(new HarmonyDeleteInputClient(inputClient), count);
    const deleted = ImeConnectionService.inputClient === inputClient &&
      result === DeleteResult.CONFIRMED_SUCCESS;
    if (deleted && pending !== undefined && this.deletionRecoveryManager.record(
      pending.text,
      pending.start,
      pending.beforeContext,
      pending.afterContext
    )) {
      this.deletionOwner = inputClient;
    } else if (deleted) {
      this.clearDeletionRecovery();
    }
    return deleted;
  }

  async deleteBackwardIfMatches(text: string): Promise<boolean> {
    const inputClient = ImeConnectionService.inputClient;
    if (!inputClient || text.length <= 0) {
      return false;
    }
    try {
      const observed = await inputClient.getForward(text.length);
      if (ImeConnectionService.inputClient !== inputClient || observed !== text) {
        LOGGER.warn('undo rejected because text before cursor no longer matches');
        return false;
      }
      const result = await this.safeDeleteExecutor.execute(
        new HarmonyDeleteInputClient(inputClient),
        text.length
      );
      const deleted = ImeConnectionService.inputClient === inputClient &&
        result === DeleteResult.CONFIRMED_SUCCESS;
      if (deleted) {
        this.clearDeletionRecovery();
      }
      return deleted;
    } catch (err) {
      LOGGER.warn('undo text verification failed');
      return false;
    }
  }

  async textBeforeCursorMatches(text: string): Promise<boolean> {
    const inputClient = ImeConnectionService.inputClient;
    if (!inputClient || text.length <= 0) {
      return false;
    }
    try {
      const observed = await inputClient.getForward(text.length);
      return ImeConnectionService.inputClient === inputClient && observed === text;
    } catch (_err) {
      return false;
    }
  }

  async getCursorIndex(): Promise<number | undefined> {
    const inputClient = ImeConnectionService.inputClient;
    if (!inputClient) {
      return undefined;
    }
    try {
      const cursor = await inputClient.getTextIndexAtCursor();
      return ImeConnectionService.inputClient === inputClient && Number.isInteger(cursor) && cursor >= 0
        ? cursor : undefined;
    } catch (_err) {
      return undefined;
    }
  }

  async getTextBeforeCursor(maxUnits: number): Promise<string | undefined> {
    const inputClient = ImeConnectionService.inputClient;
    if (!inputClient || !Number.isInteger(maxUnits) || maxUnits <= 0 || maxUnits > 4096) {
      return undefined;
    }
    try {
      const text = await inputClient.getForward(maxUnits);
      return ImeConnectionService.inputClient === inputClient ? text : undefined;
    } catch (_err) {
      return undefined;
    }
  }

  async replaceTextBeforeCursorIfMatches(
    sourceText: string,
    replacementText: string,
    stillOwned: () => boolean = (): boolean => true,
    expectedCursorUtf16?: number
  ): Promise<boolean> {
    const inputClient = ImeConnectionService.inputClient;
    if (!inputClient || sourceText.length <= 0 || replacementText.length <= 0) {
      return false;
    }
    let originalCursor: number = -1;
    try {
      originalCursor = await inputClient.getTextIndexAtCursor();
      const observed = await inputClient.getForward(sourceText.length);
      if (ImeConnectionService.inputClient !== inputClient || !stillOwned() || observed !== sourceText ||
        (expectedCursorUtf16 !== undefined && originalCursor !== expectedCursorUtf16) ||
        originalCursor < sourceText.length) {
        LOGGER.warn('verified replacement rejected because source ownership no longer matches');
        return false;
      }
      await inputClient.selectByRange({
        start: originalCursor - sourceText.length,
        end: originalCursor
      });
      if (ImeConnectionService.inputClient !== inputClient || !stillOwned()) {
        await inputClient.selectByRange({ start: originalCursor, end: originalCursor });
        return false;
      }
      const inserted = await inputClient.insertText(replacementText);
      if (!inserted || ImeConnectionService.inputClient !== inputClient) {
        try {
          await inputClient.selectByRange({ start: originalCursor, end: originalCursor });
        } catch (_restoreErr) {
        }
        LOGGER.warn('verified replacement insert was rejected');
        return false;
      }
      this.clearDeletionRecovery();
      LOGGER.info(
        `verified replacement ok: sourceLength=${sourceText.length}, replacementLength=${replacementText.length}`
      );
      return true;
    } catch (_err) {
      if (originalCursor >= 0 && ImeConnectionService.inputClient === inputClient) {
        try {
          await inputClient.selectByRange({ start: originalCursor, end: originalCursor });
        } catch (_restoreErr) {
        }
      }
      LOGGER.warn('verified replacement failed');
      return false;
    }
  }

  async moveToLineEnd(): Promise<boolean> {
    const inputClient = ImeConnectionService.inputClient;
    if (!inputClient) {
      return false;
    }
    let originalCursor: number = -1;
    try {
      originalCursor = await inputClient.getTextIndexAtCursor();
      let cursor = originalCursor;
      for (let attempt = 0; attempt < LINE_END_QUERY_LIMIT; attempt += 1) {
        if (ImeConnectionService.inputClient !== inputClient) {
          return false;
        }
        const after = await inputClient.getBackward(LINE_END_QUERY_UNITS);
        const lf = after.indexOf('\n');
        const cr = after.indexOf('\r');
        let boundary = -1;
        if (lf >= 0 && cr >= 0) {
          boundary = Math.min(lf, cr);
        } else {
          boundary = Math.max(lf, cr);
        }
        if (boundary >= 0) {
          const target = cursor + boundary;
          await inputClient.selectByRange({ start: target, end: target });
          return ImeConnectionService.inputClient === inputClient;
        }
        const target = cursor + after.length;
        if (after.length < LINE_END_QUERY_UNITS) {
          await inputClient.selectByRange({ start: target, end: target });
          return ImeConnectionService.inputClient === inputClient;
        }
        await inputClient.selectByRange({ start: target, end: target });
        cursor = target;
      }
    } catch (err) {
      LOGGER.warn('move to line end failed');
    }
    if (originalCursor >= 0 && ImeConnectionService.inputClient === inputClient) {
      try {
        await inputClient.selectByRange({ start: originalCursor, end: originalCursor });
      } catch (restoreErr) {
        LOGGER.warn('move to line end cursor restore failed');
      }
    }
    return false;
  }

  async deleteCurrentLine(): Promise<boolean> {
    const inputClient = ImeConnectionService.inputClient;
    if (!inputClient) {
      return false;
    }
    try {
      const record = await this.currentLineDeleteExecutor.execute(
        new HarmonyCurrentLineInputClient(inputClient),
        (): boolean => ImeConnectionService.inputClient === inputClient
      );
      if (record === undefined) {
        return false;
      }
      if (this.deletionRecoveryManager.record(
        record.text,
        record.start,
        record.beforeContext,
        record.afterContext
      )) {
        this.deletionOwner = inputClient;
      } else {
        this.clearDeletionRecovery();
      }
      return true;
    } catch (_err) {
      LOGGER.warn('delete current line failed');
    }
    return false;
  }

  async restoreLastDeletion(): Promise<boolean> {
    const inputClient = ImeConnectionService.inputClient;
    const record: DeletionRecoveryRecord | undefined = this.deletionRecoveryManager.getRecord();
    if (!inputClient || this.deletionOwner !== inputClient || record === undefined) {
      return false;
    }
    try {
      const cursor = await inputClient.getTextIndexAtCursor();
      const before = record.beforeContext.length > 0
        ? await inputClient.getForward(record.beforeContext.length) : '';
      const after = record.afterContext.length > 0
        ? await inputClient.getBackward(record.afterContext.length) : '';
      if (ImeConnectionService.inputClient !== inputClient) {
        return false;
      }
      const text = this.deletionRecoveryManager.resolve(cursor, before, after);
      if (text === undefined) {
        LOGGER.warn('restore deletion rejected because editor context changed');
        return false;
      }
      const restored = await inputClient.insertText(text);
      if (!restored || ImeConnectionService.inputClient !== inputClient) {
        return false;
      }
      this.clearDeletionRecovery();
      LOGGER.info(`restore deletion ok: length=${text.length}`);
      return true;
    } catch (_err) {
      LOGGER.warn('restore deletion failed');
      return false;
    }
  }

  clearDeletionRecovery(): void {
    this.deletionRecoveryManager.clear();
    this.deletionOwner = undefined;
  }

  private async captureBackwardDeletion(
    inputClient: inputMethodEngine.InputClient,
    count: number
  ): Promise<DeletionRecoveryRecord | undefined> {
    if (!Number.isInteger(count) || count <= 0) {
      return undefined;
    }
    try {
      const cursor = await inputClient.getTextIndexAtCursor();
      const effectiveCount = Math.min(count, cursor);
      if (effectiveCount <= 0) {
        return undefined;
      }
      const before = await inputClient.getForward(effectiveCount + DELETION_RECOVERY_CONTEXT_UNITS);
      const after = await inputClient.getBackward(DELETION_RECOVERY_CONTEXT_UNITS);
      if (ImeConnectionService.inputClient !== inputClient || before.length < effectiveCount) {
        return undefined;
      }
      const split = before.length - effectiveCount;
      return {
        text: before.slice(split),
        start: cursor - effectiveCount,
        beforeContext: before.slice(0, split),
        afterContext: after
      };
    } catch (_err) {
      return undefined;
    }
  }

  async sendExtendAction(action: EditorExtendAction): Promise<boolean> {
    const inputClient = ImeConnectionService.inputClient;
    if (!inputClient) {
      LOGGER.error('editor extend action failed: no input client');
      return false;
    }
    return this.editorExtendActionExecutor.execute(
      new HarmonyEditorExtendInputClient(inputClient),
      action,
      (): boolean => ImeConnectionService.inputClient === inputClient
    );
  }

  async sendEnter(action: EnterAction = EnterAction.ENTER): Promise<boolean> {
    const inputClient = ImeConnectionService.inputClient;
    if (!inputClient) {
      LOGGER.error('sendEnter failed: no input client');
      return false;
    }

    const keyType = this.enterKeyTypeForAction(action);
    try {
      const sent = await inputClient.sendKeyFunction(keyType);
      if (sent) {
        LOGGER.info(`sendEnter ok: action=${action}`);
        return true;
      }
      LOGGER.warn(`sendEnter returned false: action=${action}`);
    } catch (err) {
      LOGGER.warn(`sendEnter action failed: action=${action}`);
    }

    if (keyType === inputMethodEngine.ENTER_KEY_TYPE_NEWLINE) {
      return false;
    }
    try {
      const fallbackSent = await inputClient.sendKeyFunction(
        inputMethodEngine.ENTER_KEY_TYPE_NEWLINE
      );
      LOGGER.info(`sendEnter newline fallback: success=${fallbackSent}`);
      return fallbackSent;
    } catch (err) {
      LOGGER.error('sendEnter newline fallback failed');
      return false;
    }
  }

  private enterKeyTypeForAction(action: EnterAction): number {
    switch (action) {
      case EnterAction.SEARCH:
        return inputMethodEngine.ENTER_KEY_TYPE_SEARCH;
      case EnterAction.DONE:
        return inputMethodEngine.ENTER_KEY_TYPE_DONE;
      case EnterAction.NEXT:
        return inputMethodEngine.ENTER_KEY_TYPE_NEXT;
      case EnterAction.GO:
        return inputMethodEngine.ENTER_KEY_TYPE_GO;
      case EnterAction.SEND:
        return inputMethodEngine.ENTER_KEY_TYPE_SEND;
      default:
        return inputMethodEngine.ENTER_KEY_TYPE_NEWLINE;
    }
  }

  async hideKeyboard(): Promise<boolean> {
    const keyboardController = ImeConnectionService.keyboardController;
    if (!keyboardController) {
      LOGGER.error('hideKeyboard failed: no keyboard controller');
      return false;
    }

    try {
      await keyboardController.hide();
      LOGGER.info('hideKeyboard ok');
      return true;
    } catch (err) {
      LOGGER.error(`hideKeyboard failed: ${JSON.stringify(err)}`);
      return false;
    }
  }
}
