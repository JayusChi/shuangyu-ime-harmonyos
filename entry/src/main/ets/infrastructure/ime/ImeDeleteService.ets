import { inputMethodEngine } from '@kit.IMEKit';
import { Logger } from '../../common/logging/Logger';

const TAG = 'Stage0ImeConnection';
const LOGGER = new Logger(TAG);

const DELETE_OBSERVATION_LIMIT = 2;

export enum DeleteResult {
  CONFIRMED_SUCCESS = 'CONFIRMED_SUCCESS',
  CONFIRMED_FAILURE = 'CONFIRMED_FAILURE',
  INDETERMINATE = 'INDETERMINATE'
}

export abstract class DeleteInputClient {
  abstract deleteBackward(length: number): Promise<boolean>;
  abstract deleteBackwardSync(length: number): void;
  abstract getTextIndexAtCursor(): Promise<number>;
  abstract selectByRange(range: inputMethodEngine.Range): Promise<void>;
  abstract insertText(text: string): Promise<boolean>;
}

export class HarmonyDeleteInputClient extends DeleteInputClient {
  private readonly inputClient: inputMethodEngine.InputClient;

  constructor(inputClient: inputMethodEngine.InputClient) {
    super();
    this.inputClient = inputClient;
  }

  async deleteBackward(length: number): Promise<boolean> {
    try {
      // HarmonyOS names deletion by the direction of the remaining text:
      // deleteForward removes text before the cursor (the Backspace action).
      return await this.inputClient.deleteForward(length);
    } catch (err) {
      throw new Error('InputClient deleteBackward failed');
    }
  }

  deleteBackwardSync(length: number): void {
    try {
      this.inputClient.deleteForwardSync(length);
    } catch (err) {
      throw new Error('InputClient deleteBackwardSync failed');
    }
  }

  async getTextIndexAtCursor(): Promise<number> {
    try {
      return await this.inputClient.getTextIndexAtCursor();
    } catch (err) {
      throw new Error('InputClient cursor query failed');
    }
  }

  async selectByRange(range: inputMethodEngine.Range): Promise<void> {
    try {
      await this.inputClient.selectByRange(range);
    } catch (err) {
      throw new Error('InputClient selectByRange failed');
    }
  }

  async insertText(text: string): Promise<boolean> {
    try {
      return await this.inputClient.insertText(text);
    } catch (err) {
      throw new Error('InputClient insertText failed');
    }
  }
}


interface DeleteOperationContext {
  operationId: number;
  startedAt: number;
  primaryDeleteCalled: boolean;
  fallbackDeleteCalled: boolean;
  cursorBefore?: number;
  cursorAfter?: number;
  result: DeleteResult;
}

/**
 * Executes one editor deletion without repeating a side effect when the
 * result of an earlier delete request is uncertain.
 */
export class SafeDeleteExecutor {
  private nextOperationId: number = 0;

  async execute(inputClient: DeleteInputClient, count: number = 1): Promise<DeleteResult> {
    const context = this.createContext();
    if (count <= 0) {
      LOGGER.warn(`delete operation=${context.operationId} rejected invalid count=${count}`);
      return this.finish(context, DeleteResult.CONFIRMED_FAILURE);
    }

    context.cursorBefore = await this.readCursorIndex(inputClient, context, 'before-primary');
    const effectiveCount = context.cursorBefore === undefined || context.cursorBefore === 0 ?
      count : Math.min(count, context.cursorBefore);

    context.primaryDeleteCalled = true;
    const primaryResult = await this.tryPrimaryDelete(inputClient, effectiveCount, context);
    if (primaryResult === DeleteResult.CONFIRMED_SUCCESS) {
      await this.observeCursorAfterDelete(inputClient, context, effectiveCount, 'primary');
      LOGGER.debug(`delete operation=${context.operationId} primary confirmed successful; fallback not executed`);
      return this.finish(context, DeleteResult.CONFIRMED_SUCCESS);
    }

    if (primaryResult === DeleteResult.INDETERMINATE) {
      const observedSuccess = await this.observeCursorAfterDelete(
        inputClient,
        context,
        effectiveCount,
        'primary-indeterminate'
      );
      if (observedSuccess) {
        LOGGER.info(`delete operation=${context.operationId} primary confirmed by observation; fallback not executed`);
        return this.finish(context, DeleteResult.CONFIRMED_SUCCESS);
      }
      LOGGER.warn(`delete operation=${context.operationId} primary result indeterminate; fallback not executed`);
      return this.finish(context, DeleteResult.INDETERMINATE);
    }

    LOGGER.warn(`delete operation=${context.operationId} primary confirmed failed; selecting one fallback`);
    const fallbackResult = await this.trySingleFallback(inputClient, effectiveCount, context);
    if (fallbackResult === DeleteResult.INDETERMINATE) {
      const observedSuccess = await this.observeCursorAfterDelete(
        inputClient,
        context,
        effectiveCount,
        'fallback-indeterminate'
      );
      if (observedSuccess) {
        LOGGER.info(`delete operation=${context.operationId} fallback confirmed by observation`);
        return this.finish(context, DeleteResult.CONFIRMED_SUCCESS);
      }
      LOGGER.warn(`delete operation=${context.operationId} fallback result indeterminate; no further delete executed`);
      return this.finish(context, DeleteResult.INDETERMINATE);
    }

    if (fallbackResult === DeleteResult.CONFIRMED_SUCCESS) {
      await this.observeCursorAfterDelete(inputClient, context, effectiveCount, 'fallback');
    }
    return this.finish(context, fallbackResult);
  }

  private createContext(): DeleteOperationContext {
    this.nextOperationId += 1;
    return {
      operationId: this.nextOperationId,
      startedAt: Date.now(),
      primaryDeleteCalled: false,
      fallbackDeleteCalled: false,
      result: DeleteResult.INDETERMINATE
    };
  }

  private async tryPrimaryDelete(
    inputClient: DeleteInputClient,
    count: number,
    context: DeleteOperationContext
  ): Promise<DeleteResult> {
    try {
      const deleted = await inputClient.deleteBackward(count);
      if (deleted) {
        LOGGER.debug(`delete operation=${context.operationId} primary returned true: count=${count}`);
        return DeleteResult.CONFIRMED_SUCCESS;
      }
      LOGGER.warn(`delete operation=${context.operationId} primary returned false: count=${count}`);
      return DeleteResult.CONFIRMED_FAILURE;
    } catch (err) {
      // Input-client and IPC errors do not prove that the request was never
      // submitted, so an exception is deliberately not treated as failure.
      LOGGER.warn(`delete operation=${context.operationId} primary threw; result indeterminate`);
      return DeleteResult.INDETERMINATE;
    }
  }

  private async trySingleFallback(
    inputClient: DeleteInputClient,
    count: number,
    context: DeleteOperationContext
  ): Promise<DeleteResult> {
    if (context.cursorBefore === undefined || context.cursorBefore === 0) {
      context.fallbackDeleteCalled = true;
      try {
        inputClient.deleteBackwardSync(count);
        LOGGER.info(`delete operation=${context.operationId} sync fallback executed once: count=${count}`);
        return DeleteResult.CONFIRMED_SUCCESS;
      } catch (err) {
        LOGGER.warn(`delete operation=${context.operationId} sync fallback threw; result indeterminate`);
        return DeleteResult.INDETERMINATE;
      }
    }

    const start = Math.max(0, context.cursorBefore - count);
    const range: inputMethodEngine.Range = {
      start,
      end: context.cursorBefore
    };
    try {
      await inputClient.selectByRange(range);
      LOGGER.debug(
        `delete operation=${context.operationId} range fallback selected: start=${start}, end=${context.cursorBefore}`
      );
    } catch (err) {
      LOGGER.warn(`delete operation=${context.operationId} range fallback selection failed; no delete executed`);
      return DeleteResult.CONFIRMED_FAILURE;
    }

    context.fallbackDeleteCalled = true;
    try {
      const deleted = await inputClient.insertText('');
      if (deleted) {
        LOGGER.info(`delete operation=${context.operationId} range fallback executed once: count=${count}`);
        return DeleteResult.CONFIRMED_SUCCESS;
      }
      LOGGER.warn(`delete operation=${context.operationId} range fallback returned false; no further delete executed`);
      return DeleteResult.CONFIRMED_FAILURE;
    } catch (err) {
      LOGGER.warn(`delete operation=${context.operationId} range fallback threw; result indeterminate`);
      return DeleteResult.INDETERMINATE;
    }
  }

  private async observeCursorAfterDelete(
    inputClient: DeleteInputClient,
    context: DeleteOperationContext,
    count: number,
    reason: string
  ): Promise<boolean> {
    for (let attempt = 1; attempt <= DELETE_OBSERVATION_LIMIT; attempt += 1) {
      const cursorAfter = await this.readCursorIndex(inputClient, context, `${reason}-${attempt}`);
      if (cursorAfter !== undefined) {
        context.cursorAfter = cursorAfter;
        if (context.cursorBefore !== undefined) {
          const expected = Math.max(0, context.cursorBefore - count);
          if (cursorAfter <= expected) {
            LOGGER.debug(
              `delete operation=${context.operationId} observation confirmed: before=${context.cursorBefore}, ` +
              `after=${cursorAfter}, attempt=${attempt}`
            );
            return true;
          }
        }
      }

      if (attempt < DELETE_OBSERVATION_LIMIT) {
        await this.waitForNextObservationTurn();
      }
    }

    LOGGER.debug(
      `delete operation=${context.operationId} observation limit reached: reason=${reason}; ` +
      'unchanged or unavailable cursor is not treated as failure'
    );
    return false;
  }

  private waitForNextObservationTurn(): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, 0);
    });
  }

  private async readCursorIndex(
    inputClient: DeleteInputClient,
    context: DeleteOperationContext,
    reason: string
  ): Promise<number | undefined> {
    try {
      const index = await inputClient.getTextIndexAtCursor();
      LOGGER.debug(`delete operation=${context.operationId} cursor ${reason}: ${index}`);
      return index;
    } catch (err) {
      LOGGER.warn(`delete operation=${context.operationId} cursor unavailable: reason=${reason}`);
      return undefined;
    }
  }

  private finish(context: DeleteOperationContext, result: DeleteResult): DeleteResult {
    context.result = result;
    const before = context.cursorBefore === undefined ? 'unavailable' : `${context.cursorBefore}`;
    const after = context.cursorAfter === undefined ? 'unavailable' : `${context.cursorAfter}`;
    LOGGER.debug(
      `delete operation=${context.operationId} finished: result=${result}, ` +
      `primaryCalled=${context.primaryDeleteCalled}, fallbackCalled=${context.fallbackDeleteCalled}, ` +
      `before=${before}, after=${after}, durationMs=${Date.now() - context.startedAt}`
    );
    return result;
  }
}


