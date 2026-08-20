import { inputMethodEngine } from '@kit.IMEKit';
import { describe, it, expect } from '@ohos/hypium';
import {
  DeleteInputClient,
  DeleteResult,
  SafeDeleteExecutor
} from '../main/ets/infrastructure/ime/ImeConnectionService';
import { SerialActionExecutor } from '../main/ets/application/SerialActionExecutor';

enum PrimaryBehavior {
  SUCCESS = 'SUCCESS',
  FAILURE = 'FAILURE',
  THROW_BEFORE_DELETE = 'THROW_BEFORE_DELETE',
  THROW_AFTER_DELETE = 'THROW_AFTER_DELETE'
}

enum FallbackBehavior {
  SUCCESS = 'SUCCESS',
  FAILURE = 'FAILURE',
  THROW_AFTER_DELETE = 'THROW_AFTER_DELETE'
}

class MockDeleteInputClient extends DeleteInputClient {
  text: string;
  cursor: number;
  primaryBehavior: PrimaryBehavior = PrimaryBehavior.SUCCESS;
  fallbackBehavior: FallbackBehavior = FallbackBehavior.SUCCESS;
  cursorResponses: number[] = [];
  cursorAlwaysFails: boolean = false;
  primaryCalls: number = 0;
  rangeSelectionCalls: number = 0;
  rangeFallbackCalls: number = 0;
  syncFallbackCalls: number = 0;
  actualDeleteCount: number = 0;
  private cursorResponseIndex: number = 0;
  private selectionStart?: number;
  private selectionEnd?: number;

  constructor(text: string, cursor: number) {
    super();
    this.text = text;
    this.cursor = cursor;
  }

  setSelection(start: number, end: number): void {
    this.selectionStart = start;
    this.selectionEnd = end;
    this.cursor = end;
  }

  async deleteBackward(length: number): Promise<boolean> {
    this.primaryCalls += 1;
    switch (this.primaryBehavior) {
      case PrimaryBehavior.SUCCESS:
        this.applyDelete(length);
        return true;
      case PrimaryBehavior.FAILURE:
        return false;
      case PrimaryBehavior.THROW_AFTER_DELETE:
        this.applyDelete(length);
        throw new Error('simulated ambiguous primary failure');
      default:
        throw new Error('simulated pre-submit primary failure');
    }
  }

  deleteBackwardSync(length: number): void {
    this.syncFallbackCalls += 1;
    if (this.fallbackBehavior === FallbackBehavior.SUCCESS) {
      this.applyDelete(length);
      return;
    }
    if (this.fallbackBehavior === FallbackBehavior.THROW_AFTER_DELETE) {
      this.applyDelete(length);
    }
    throw new Error('simulated sync fallback failure');
  }

  async getTextIndexAtCursor(): Promise<number> {
    if (this.cursorAlwaysFails) {
      throw new Error('simulated cursor query failure');
    }
    if (this.cursorResponseIndex < this.cursorResponses.length) {
      const response = this.cursorResponses[this.cursorResponseIndex];
      this.cursorResponseIndex += 1;
      return response;
    }
    return this.cursor;
  }

  async selectByRange(range: inputMethodEngine.Range): Promise<void> {
    this.rangeSelectionCalls += 1;
    this.selectionStart = range.start;
    this.selectionEnd = range.end;
    this.cursor = range.end;
  }

  async insertText(text: string): Promise<boolean> {
    this.rangeFallbackCalls += 1;
    if (text.length > 0) {
      throw new Error('mock only supports the empty range-delete replacement');
    }
    if (this.fallbackBehavior === FallbackBehavior.SUCCESS) {
      this.applyDelete(0);
      return true;
    }
    if (this.fallbackBehavior === FallbackBehavior.THROW_AFTER_DELETE) {
      this.applyDelete(0);
      throw new Error('simulated ambiguous range fallback failure');
    }
    return false;
  }

  totalFallbackDeleteCalls(): number {
    return this.rangeFallbackCalls + this.syncFallbackCalls;
  }

  private applyDelete(length: number): void {
    if (this.selectionStart !== undefined && this.selectionEnd !== undefined &&
      this.selectionStart !== this.selectionEnd) {
      const start = Math.min(this.selectionStart, this.selectionEnd);
      const end = Math.max(this.selectionStart, this.selectionEnd);
      this.text = this.text.substring(0, start) + this.text.substring(end);
      this.cursor = start;
      this.selectionStart = undefined;
      this.selectionEnd = undefined;
      this.actualDeleteCount += 1;
      return;
    }

    const start = Math.max(0, this.cursor - length);
    if (start === this.cursor) {
      return;
    }
    this.text = this.text.substring(0, start) + this.text.substring(this.cursor);
    this.cursor = start;
    this.actualDeleteCount += 1;
  }
}

export default function safeDeleteExecutorTest() {
  describe('SafeDeleteExecutor', () => {
    it('accepts immediate primary success without fallback', 0, async () => {
      const client = new MockDeleteInputClient('abcde', 5);
      client.cursorResponses = [5, 4];

      const result = await new SafeDeleteExecutor().execute(client, 1);

      expect(result).assertEqual(DeleteResult.CONFIRMED_SUCCESS);
      expect(client.primaryCalls).assertEqual(1);
      expect(client.totalFallbackDeleteCalls()).assertEqual(0);
      expect(client.actualDeleteCount).assertEqual(1);
      expect(client.text).assertEqual('abcd');
    });

    it('does not fallback when successful primary cursor update is delayed', 0, async () => {
      const client = new MockDeleteInputClient('abcde', 5);
      client.cursorResponses = [5, 5, 4];

      const result = await new SafeDeleteExecutor().execute(client, 1);

      expect(result).assertEqual(DeleteResult.CONFIRMED_SUCCESS);
      expect(client.primaryCalls).assertEqual(1);
      expect(client.totalFallbackDeleteCalls()).assertEqual(0);
      expect(client.actualDeleteCount).assertEqual(1);
      expect(client.text).assertEqual('abcd');
    });

    it('returns indeterminate and never falls back when primary outcome cannot be confirmed', 0, async () => {
      const client = new MockDeleteInputClient('abcde', 5);
      client.primaryBehavior = PrimaryBehavior.THROW_AFTER_DELETE;
      client.cursorResponses = [5, 5, 5];

      const result = await new SafeDeleteExecutor().execute(client, 1);

      expect(result).assertEqual(DeleteResult.INDETERMINATE);
      expect(client.primaryCalls).assertEqual(1);
      expect(client.totalFallbackDeleteCalls()).assertEqual(0);
      expect(client.actualDeleteCount).assertEqual(1);
      expect(client.text).assertEqual('abcd');
    });

    it('uses exactly one range fallback after explicit primary failure', 0, async () => {
      const client = new MockDeleteInputClient('abcde', 5);
      client.primaryBehavior = PrimaryBehavior.FAILURE;
      client.cursorResponses = [5];

      const result = await new SafeDeleteExecutor().execute(client, 1);

      expect(result).assertEqual(DeleteResult.CONFIRMED_SUCCESS);
      expect(client.primaryCalls).assertEqual(1);
      expect(client.rangeSelectionCalls).assertEqual(1);
      expect(client.totalFallbackDeleteCalls()).assertEqual(1);
      expect(client.actualDeleteCount).assertEqual(1);
      expect(client.text).assertEqual('abcd');
    });

    it('uses exactly one sync fallback after explicit failure when cursor is unavailable', 0, async () => {
      const client = new MockDeleteInputClient('abcde', 5);
      client.primaryBehavior = PrimaryBehavior.FAILURE;
      client.cursorAlwaysFails = true;

      const result = await new SafeDeleteExecutor().execute(client, 1);

      expect(result).assertEqual(DeleteResult.CONFIRMED_SUCCESS);
      expect(client.primaryCalls).assertEqual(1);
      expect(client.rangeSelectionCalls).assertEqual(0);
      expect(client.syncFallbackCalls).assertEqual(1);
      expect(client.totalFallbackDeleteCalls()).assertEqual(1);
      expect(client.actualDeleteCount).assertEqual(1);
      expect(client.text).assertEqual('abcd');
    });

    it('does not fallback after a primary exception even if it happened before delete', 0, async () => {
      const client = new MockDeleteInputClient('abcde', 5);
      client.primaryBehavior = PrimaryBehavior.THROW_BEFORE_DELETE;
      client.cursorResponses = [5, 5, 5];

      const result = await new SafeDeleteExecutor().execute(client, 1);

      expect(result).assertEqual(DeleteResult.INDETERMINATE);
      expect(client.primaryCalls).assertEqual(1);
      expect(client.totalFallbackDeleteCalls()).assertEqual(0);
      expect(client.actualDeleteCount).assertEqual(0);
      expect(client.text).assertEqual('abcde');
    });

    it('does not chain another delete when the only fallback is indeterminate', 0, async () => {
      const client = new MockDeleteInputClient('abcde', 5);
      client.primaryBehavior = PrimaryBehavior.FAILURE;
      client.fallbackBehavior = FallbackBehavior.THROW_AFTER_DELETE;
      client.cursorResponses = [5, 5, 5];

      const result = await new SafeDeleteExecutor().execute(client, 1);

      expect(result).assertEqual(DeleteResult.INDETERMINATE);
      expect(client.primaryCalls).assertEqual(1);
      expect(client.rangeSelectionCalls).assertEqual(1);
      expect(client.rangeFallbackCalls).assertEqual(1);
      expect(client.syncFallbackCalls).assertEqual(0);
      expect(client.actualDeleteCount).assertEqual(1);
      expect(client.text).assertEqual('abcd');
    });

    it('deletes a selected range without deleting an extra preceding character', 0, async () => {
      const client = new MockDeleteInputClient('abcdef', 5);
      client.setSelection(2, 5);
      client.cursorResponses = [5, 2];

      const result = await new SafeDeleteExecutor().execute(client, 1);

      expect(result).assertEqual(DeleteResult.CONFIRMED_SUCCESS);
      expect(client.primaryCalls).assertEqual(1);
      expect(client.totalFallbackDeleteCalls()).assertEqual(0);
      expect(client.actualDeleteCount).assertEqual(1);
      expect(client.text).assertEqual('abf');
    });

    it('is safe at the start of text and never triggers fallback after a successful no-op', 0, async () => {
      const client = new MockDeleteInputClient('abc', 0);
      client.cursorResponses = [0, 0, 0];

      const result = await new SafeDeleteExecutor().execute(client, 1);

      expect(result).assertEqual(DeleteResult.CONFIRMED_SUCCESS);
      expect(client.primaryCalls).assertEqual(1);
      expect(client.totalFallbackDeleteCalls()).assertEqual(0);
      expect(client.actualDeleteCount).assertEqual(0);
      expect(client.text).assertEqual('abc');
    });

    it('keeps rapid independent delete requests one-for-one', 0, async () => {
      const client = new MockDeleteInputClient('abcdefghij', 10);
      const executor = new SafeDeleteExecutor();
      for (let index = 0; index < 5; index += 1) {
        const result = await executor.execute(client, 1);
        expect(result).assertEqual(DeleteResult.CONFIRMED_SUCCESS);
      }

      expect(client.primaryCalls).assertEqual(5);
      expect(client.totalFallbackDeleteCalls()).assertEqual(0);
      expect(client.actualDeleteCount).assertEqual(5);
      expect(client.text).assertEqual('abcde');
    });

    it('lets serialized long-press ticks continue with one delete per tick', 0, async () => {
      const client = new MockDeleteInputClient('abcdefghij', 10);
      const safeDeleteExecutor = new SafeDeleteExecutor();
      const actionExecutor = new SerialActionExecutor();
      const ticks: Promise<DeleteResult>[] = [];
      for (let index = 0; index < 5; index += 1) {
        ticks.push(actionExecutor.enqueue(async (): Promise<DeleteResult> => {
          return safeDeleteExecutor.execute(client, 1);
        }));
      }
      for (let index = 0; index < ticks.length; index += 1) {
        expect(await ticks[index]).assertEqual(DeleteResult.CONFIRMED_SUCCESS);
      }

      expect(client.primaryCalls).assertEqual(5);
      expect(client.totalFallbackDeleteCalls()).assertEqual(0);
      expect(client.actualDeleteCount).assertEqual(5);
      expect(client.text).assertEqual('abcde');
    });
  });
}
