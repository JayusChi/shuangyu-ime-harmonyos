import { inputMethodEngine } from '@kit.IMEKit';
import { Logger } from '../../common/logging/Logger';
import { HarmonyPairCursorClient, PairCursorPositioner } from './PairCursorPositioner';
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
  private readonly cursorPositioner: PairCursorPositioner = new PairCursorPositioner();

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
      const positioned = await this.cursorPositioner.position(
        new HarmonyPairCursorClient(inputClient), text, cursorOffsetUtf16, stillCurrent
      );
      if (!positioned || !stillCurrent()) {
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
        `pair cursor verified: offsetUtf16=${cursorOffsetUtf16}, textUtf16Length=${text.length}`
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
      const jumped = await this.cursorPositioner.advance(
        new HarmonyPairCursorClient(inputClient), pending.rightText, stillCurrent
      );
      if (!jumped || !stillCurrent()) {
        this.clear();
        LOGGER.info('pair jump could not verify cursor movement');
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

}
