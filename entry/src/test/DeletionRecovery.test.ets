import { describe, expect, it } from '@ohos/hypium';
import { DeletionRecoveryManager } from '../main/ets/domain/editor/DeletionRecovery';
import {
  CurrentLineDeleteExecutor,
  CurrentLineInputClient
} from '../main/ets/infrastructure/ime/ImeConnectionService';

class LineInputClient extends CurrentLineInputClient {
  text: string;
  cursor: number;
  failBeforeDelete: boolean = false;
  ignoreAfterDelete: boolean = false;
  falseAfterApplied: boolean = false;
  afterDeleteDelayMs: number = 0;
  beforeDeleteCalls: number = 0;
  afterDeleteCalls: number = 0;

  constructor(text: string, cursor: number) {
    super();
    this.text = text;
    this.cursor = cursor;
  }

  async getTextIndexAtCursor(): Promise<number> {
    return this.cursor;
  }

  async getTextBeforeCursor(length: number): Promise<string> {
    return this.text.slice(Math.max(0, this.cursor - length), this.cursor);
  }

  async getTextAfterCursor(length: number): Promise<string> {
    return this.text.slice(this.cursor, this.cursor + length);
  }

  async deleteTextBeforeCursor(length: number): Promise<boolean> {
    this.beforeDeleteCalls += 1;
    if (this.failBeforeDelete) {
      return false;
    }
    const start = Math.max(0, this.cursor - length);
    this.text = this.text.slice(0, start) + this.text.slice(this.cursor);
    this.cursor = start;
    return !this.falseAfterApplied;
  }

  async deleteTextAfterCursor(length: number): Promise<boolean> {
    this.afterDeleteCalls += 1;
    if (this.ignoreAfterDelete) {
      return true;
    }
    if (this.afterDeleteDelayMs > 0) {
      setTimeout((): void => {
        this.text = this.text.slice(0, this.cursor) + this.text.slice(this.cursor + length);
      }, this.afterDeleteDelayMs);
      return true;
    }
    this.text = this.text.slice(0, this.cursor) + this.text.slice(this.cursor + length);
    return true;
  }

  async insertText(text: string): Promise<boolean> {
    this.text = this.text.slice(0, this.cursor) + text + this.text.slice(this.cursor);
    this.cursor += text.length;
    return true;
  }
}

export default function deletionRecoveryTest() {
  describe('DeletionRecovery', () => {
    it('restores only at the recorded caret and unchanged surrounding text', 0, () => {
      const manager = new DeletionRecoveryManager();
      expect(manager.record('当前行\n', 4, '上一行\n', '下一行')).assertTrue();
      expect(manager.resolve(4, '上一行\n', '下一行')).assertEqual('当前行\n');
      expect(manager.resolve(5, '上一行\n', '下一行')).assertUndefined();
      expect(manager.resolve(4, '已改变', '下一行')).assertUndefined();
    });

    it('keeps only the latest valid deletion and clears after recovery', 0, () => {
      const manager = new DeletionRecoveryManager();
      manager.record('a', 0, '', 'b');
      manager.record('二', 2, '一', '三');
      expect(manager.resolve(2, '一', '三')).assertEqual('二');
      manager.clear();
      expect(manager.getRecord()).assertUndefined();
      expect(manager.record('', 0, '', '')).assertFalse();
    });

    it('deletesBothSidesOfTheCurrentLineWithoutRangeSelection', 0, async () => {
      const client = new LineInputClient('first\ncurrent\nlast', 9);
      const record = await new CurrentLineDeleteExecutor().execute(client);

      expect(client.text).assertEqual('first\nlast');
      expect(client.cursor).assertEqual(6);
      expect(record?.text).assertEqual('current\n');
      expect(record?.start).assertEqual(6);
      expect(record?.beforeContext).assertEqual('first\n');
      expect(record?.afterContext).assertEqual('last');
    });

    it('waitsForTheRightDeletionBeforeDeletingTheLeftHalf', 0, async () => {
      const client = new LineInputClient('first\ncurrent\nlast', 9);
      client.afterDeleteDelayMs = 60;
      const record = await new CurrentLineDeleteExecutor().execute(client);
      expect(record?.text).assertEqual('current\n');
      expect(client.text).assertEqual('first\nlast');
      expect(client.cursor).assertEqual(6);
      expect(client.afterDeleteCalls).assertEqual(1);
      expect(client.beforeDeleteCalls).assertEqual(1);
    });

    it('doesNotDeleteTheLeftHalfWhenTheHostIgnoresRightDeletion', 0, async () => {
      const client = new LineInputClient('first\ncurrent\nlast', 9);
      client.ignoreAfterDelete = true;
      expect(await new CurrentLineDeleteExecutor().execute(client)).assertUndefined();
      expect(client.text).assertEqual('first\ncurrent\nlast');
      expect(client.beforeDeleteCalls).assertEqual(0);
    });

    it('acceptsAnAppliedDeletionDespiteAFalseReturnWithoutDuplicatingRollbackText', 0, async () => {
      const client = new LineInputClient('first\ncurrent\nlast', 9);
      client.falseAfterApplied = true;
      expect((await new CurrentLineDeleteExecutor().execute(client))?.text).assertEqual('current\n');
      expect(client.text).assertEqual('first\nlast');
      expect(client.beforeDeleteCalls).assertEqual(1);
    });

    it('stopsBeforeTheLeftDeletionWhenTheSessionChanges', 0, async () => {
      const client = new LineInputClient('first\ncurrent\nlast', 9);
      expect(await new CurrentLineDeleteExecutor().execute(client,
        (): boolean => client.afterDeleteCalls === 0)).assertUndefined();
      expect(client.beforeDeleteCalls).assertEqual(0);
    });

    it('rollsBackTheRightHalfWhenTheBeforeCursorDeleteFails', 0, async () => {
      const client = new LineInputClient('first\ncurrent\nlast', 9);
      client.failBeforeDelete = true;

      expect(await new CurrentLineDeleteExecutor().execute(client)).assertUndefined();
      expect(client.text).assertEqual('first\ncurrent\nlast');
    });
  });
}
