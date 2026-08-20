import { inputMethodEngine } from '@kit.IMEKit';
import { Logger } from '../../common/logging/Logger';
import {
  CompositionTextManager,
  HarmonyCompositionInputClient
} from './ImePreviewService';

const TAG = 'Stage0ImeConnection';
const LOGGER = new Logger(TAG);

export enum PairInsertResult {
  SUCCESS = 'success',
  INSERT_FAILED = 'insert_failed',
  CURSOR_FAILED = 'cursor_failed'
}

export class PairInsertionService {
  async insert(
    inputClient: inputMethodEngine.InputClient | undefined,
    manager: CompositionTextManager,
    text: string,
    cursorOffsetUtf16: number,
    generation: number,
    stillCurrent: () => boolean
  ): Promise<PairInsertResult> {
    if (!inputClient || text.length <= 1 || text.length > 64 ||
      !Number.isInteger(cursorOffsetUtf16) || cursorOffsetUtf16 <= 0 ||
      cursorOffsetUtf16 >= text.length || cursorOffsetUtf16 > 16) {
      return PairInsertResult.INSERT_FAILED;
    }
    const committed = await manager.commit(
      new HarmonyCompositionInputClient(inputClient),
      text,
      generation,
      stillCurrent
    );
    if (!committed) {
      return PairInsertResult.INSERT_FAILED;
    }
    if (!stillCurrent()) {
      return PairInsertResult.CURSOR_FAILED;
    }
    try {
      // HarmonyOS can resolve the editor write promise one or more render
      // turns before getTextIndexAtCursor observes the replacement of the
      // active preview range. Waiting here never repeats the insertion; it
      // only prevents positioning from using the stale pre-commit cursor.
      await this.waitForEditorCommit();
      if (!stillCurrent()) {
        return PairInsertResult.CURSOR_FAILED;
      }
      const cursor = await inputClient.getTextIndexAtCursor();
      const target = cursor - cursorOffsetUtf16;
      if (!stillCurrent() || target < 0) {
        return PairInsertResult.CURSOR_FAILED;
      }
      await inputClient.selectByRange({ start: target, end: target });
      if (!stillCurrent()) {
        return PairInsertResult.CURSOR_FAILED;
      }
      LOGGER.info(
        `pair cursor positioned: cursorAfterInsert=${cursor}, target=${target}, ` +
          `offsetUtf16=${cursorOffsetUtf16}, textUtf16Length=${text.length}`
      );
      return PairInsertResult.SUCCESS;
    } catch (err) {
      LOGGER.warn('pair text inserted but cursor positioning failed');
      return PairInsertResult.CURSOR_FAILED;
    }
  }

  private waitForEditorCommit(): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, 80);
    });
  }
}

