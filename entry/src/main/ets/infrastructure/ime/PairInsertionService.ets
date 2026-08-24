import { inputMethodEngine } from '@kit.IMEKit';
import { Logger } from '../../common/logging/Logger';
import {
  CompositionTextManager,
  HarmonyCompositionInputClient
} from './ImePreviewService';

const TAG = 'Stage0ImeConnection';
const LOGGER = new Logger(TAG);
const PAIR_JUMP_TTL_MS = 120000;

interface PendingPairJump {
  rightText: string;
  generation: number;
  expiresAtMs: number;
}

export enum PairInsertResult {
  SUCCESS = 'success',
  INSERT_FAILED = 'insert_failed',
  CURSOR_FAILED = 'cursor_failed'
}

export class PairInsertionService {
  private pendingJumps: PendingPairJump[] = [];

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
        this.clear();
        return PairInsertResult.CURSOR_FAILED;
      }
      const cursor = await inputClient.getTextIndexAtCursor();
      const target = cursor - cursorOffsetUtf16;
      if (!stillCurrent() || target < 0) {
        this.clear();
        return PairInsertResult.CURSOR_FAILED;
      }
      await inputClient.selectByRange({ start: target, end: target });
      if (!stillCurrent()) {
        this.clear();
        return PairInsertResult.CURSOR_FAILED;
      }
      const rightText = text.substring(text.length - cursorOffsetUtf16);
      this.pendingJumps.push({
        rightText,
        generation,
        expiresAtMs: Date.now() + PAIR_JUMP_TTL_MS
      });
      LOGGER.info(
        `pair cursor positioned: cursorAfterInsert=${cursor}, target=${target}, ` +
          `offsetUtf16=${cursorOffsetUtf16}, textUtf16Length=${text.length}`
      );
      return PairInsertResult.SUCCESS;
    } catch (err) {
      this.clear();
      LOGGER.warn('pair text inserted but cursor positioning failed');
      return PairInsertResult.CURSOR_FAILED;
    }
  }

  hasPending(generation: number): boolean {
    this.removeExpired();
    const pending = this.pendingJumps[this.pendingJumps.length - 1];
    return pending !== undefined && pending.generation === generation;
  }

  async jumpOut(
    inputClient: inputMethodEngine.InputClient | undefined,
    generation: number,
    stillCurrent: () => boolean
  ): Promise<boolean> {
    this.removeExpired();
    const pending = this.pendingJumps[this.pendingJumps.length - 1];
    if (!inputClient || !pending || pending.generation !== generation || !stillCurrent()) {
      if (pending && pending.generation !== generation) {
        this.clear();
      }
      return false;
    }
    try {
      const cursor = await inputClient.getTextIndexAtCursor();
      const afterCursor = await inputClient.getBackward(pending.rightText.length);
      if (!stillCurrent() || afterCursor !== pending.rightText) {
        this.clear();
        LOGGER.info('pair jump discarded because editor cursor or delimiter changed');
        return false;
      }
      const target = cursor + pending.rightText.length;
      await inputClient.selectByRange({ start: target, end: target });
      if (!stillCurrent()) {
        this.clear();
        return false;
      }
      this.pendingJumps.pop();
      LOGGER.info(`pair jump completed: rightUtf16Length=${pending.rightText.length}`);
      return true;
    } catch (err) {
      this.clear();
      LOGGER.warn('pair jump failed');
      return false;
    }
  }

  clear(): void {
    this.pendingJumps = [];
  }

  private removeExpired(): void {
    const now = Date.now();
    while (this.pendingJumps.length > 0 &&
      this.pendingJumps[this.pendingJumps.length - 1].expiresAtMs <= now) {
      this.pendingJumps.pop();
    }
  }

  private waitForEditorCommit(): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, 80);
    });
  }
}
