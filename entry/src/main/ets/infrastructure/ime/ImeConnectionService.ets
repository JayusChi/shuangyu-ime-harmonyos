import { inputMethodEngine } from '@kit.IMEKit';
import { Logger } from '../../common/logging/Logger';
import { EnterAction } from '../../domain/editor/EditorContext';
import { EditorExtendAction } from '../../domain/keyboard/KeyboardAction';
import {
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

export class ImeConnectionService extends ImeConnectionLifecycle {
  private readonly safeDeleteExecutor: SafeDeleteExecutor = new SafeDeleteExecutor();
  private readonly pairInsertionService: PairInsertionService = new PairInsertionService();

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

    const result = await this.safeDeleteExecutor.execute(new HarmonyDeleteInputClient(inputClient), count);
    return result === DeleteResult.CONFIRMED_SUCCESS;
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
      return ImeConnectionService.inputClient === inputClient &&
        result === DeleteResult.CONFIRMED_SUCCESS;
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

  async sendExtendAction(action: EditorExtendAction): Promise<boolean> {
    const inputClient = ImeConnectionService.inputClient;
    if (!inputClient) {
      LOGGER.error('editor extend action failed: no input client');
      return false;
    }
    try {
      let nativeAction = inputMethodEngine.ExtendAction.SELECT_ALL;
      if (action === EditorExtendAction.CUT) {
        nativeAction = inputMethodEngine.ExtendAction.CUT;
      } else if (action === EditorExtendAction.COPY) {
        nativeAction = inputMethodEngine.ExtendAction.COPY;
      } else if (action === EditorExtendAction.PASTE) {
        nativeAction = inputMethodEngine.ExtendAction.PASTE;
      }
      await inputClient.sendExtendAction(nativeAction);
      LOGGER.info(`editor extend action ok: action=${action}`);
      return ImeConnectionService.inputClient === inputClient;
    } catch (err) {
      LOGGER.warn(`editor extend action failed: action=${action}`);
      return false;
    }
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
