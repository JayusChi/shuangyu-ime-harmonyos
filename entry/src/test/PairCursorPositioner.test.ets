import { describe, expect, it } from '@ohos/hypium';
import { inputMethodEngine } from '@kit.IMEKit';
import { PairCursorClient, PairCursorPositioner } from '../main/ets/infrastructure/ime/PairCursorPositioner';
import { LineEndCursorMover } from '../main/ets/infrastructure/ime/LineEndCursorMover';

class FakePairCursorClient implements PairCursorClient {
  text: string = '前文〔〕后文';
  cursor: number = 4;
  selectionCalls: number = 0;
  moveCalls: number = 0;
  ignoreSelection: boolean = false;
  rejectSelection: boolean = false;
  ignoreMove: boolean = false;
  rightward: boolean = false;
  staleReads: number = 0;
  selectionDelayReads: number = 0;
  pendingSelection: number = -1;
  onSelection: () => void = (): void => {};

  async getTextIndexAtCursor(): Promise<number> {
    if (this.staleReads > 0) {
      this.staleReads -= 1;
      return 2;
    }
    if (this.pendingSelection >= 0) {
      if (this.selectionDelayReads > 0) {
        this.selectionDelayReads -= 1;
      } else {
        this.cursor = this.pendingSelection;
        this.pendingSelection = -1;
      }
    }
    return this.cursor;
  }

  async getForward(length: number): Promise<string> {
    return this.text.substring(Math.max(0, this.cursor - length), this.cursor);
  }

  async getBackward(length: number): Promise<string> {
    return this.text.substring(this.cursor, this.cursor + length);
  }

  async selectByRange(range: inputMethodEngine.Range): Promise<void> {
    this.selectionCalls += 1;
    this.onSelection();
    if (this.rejectSelection) {
      throw new Error('collapsed selection unsupported');
    }
    if (!this.ignoreSelection) {
      if (this.selectionDelayReads > 0) {
        this.pendingSelection = range.start;
      } else {
        this.cursor = range.start;
      }
    }
  }

  async moveCursor(direction: inputMethodEngine.Direction): Promise<void> {
    expect(direction).assertEqual(this.rightward ? inputMethodEngine.Direction.CURSOR_RIGHT :
      inputMethodEngine.Direction.CURSOR_LEFT);
    this.moveCalls += 1;
    if (!this.ignoreMove) {
      if (this.rightward) {
        const head = this.text.charCodeAt(this.cursor);
        this.cursor += head >= 0xD800 && head <= 0xDBFF ? 2 : 1;
      } else {
        const tail = this.text.charCodeAt(this.cursor - 1);
        this.cursor -= tail >= 0xDC00 && tail <= 0xDFFF ? 2 : 1;
      }
    }
  }
}

export default function pairCursorPositionerTest() {
  describe('PairCursorPositioner', () => {
    it('jumps over closing symbols when selection is silently ignored', 0, async () => {
      for (const right of ['〕', '”', '’', '】', '｝', '」', '』', '）', '》', '〉', '😀', '】）']) {
        const client = new FakePairCursorClient();
        client.rightward = true;
        client.text = `前文【内容${right}后文`;
        client.cursor = 5;
        client.ignoreSelection = true;
        expect(await new PairCursorPositioner().advance(client, right, () => true)).assertTrue();
        expect(client.cursor).assertEqual(5 + right.length);
        expect(client.moveCalls).assertEqual(right === '】）' ? 2 : 1);
        expect(client.text).assertEqual(`前文【内容${right}后文`);
      }
    });

    it('jumps with rejected selection and waits for delayed selection without overshooting', 0, async () => {
      for (const rejected of [true, false]) {
        const client = new FakePairCursorClient();
        client.rightward = true;
        client.cursor = 3;
        client.rejectSelection = rejected;
        client.selectionDelayReads = 5;
        expect(await new PairCursorPositioner().advance(client, '〕', () => true)).assertTrue();
        expect(client.cursor).assertEqual(4);
        expect(client.moveCalls).assertEqual(rejected ? 1 : 0);
      }
    });

    it('does not report success or retry when both jump methods are ignored', 0, async () => {
      const client = new FakePairCursorClient();
      client.rightward = true;
      client.cursor = 3;
      client.ignoreSelection = true;
      client.ignoreMove = true;
      expect(await new PairCursorPositioner().advance(client, '〕', () => true)).assertFalse();
      expect(client.cursor).assertEqual(3);
      expect(client.moveCalls).assertEqual(1);
    });

    it('rejects jumping across a changed delimiter', 0, async () => {
      const client = new FakePairCursorClient();
      client.rightward = true;
      client.cursor = 3;
      expect(await new PairCursorPositioner().advance(client, '）', () => true)).assertFalse();
      expect(client.selectionCalls).assertEqual(0);
      expect(client.moveCalls).assertEqual(0);
    });

    it('stops jumping when the cursor or session changes during selection', 0, async () => {
      for (const changeSession of [true, false]) {
        const client = new FakePairCursorClient();
        client.rightward = true;
        client.cursor = 3;
        client.ignoreSelection = true;
        let current = true;
        client.onSelection = (): void => {
          if (changeSession) { current = false; } else { client.cursor = 0; }
        };
        expect(await new PairCursorPositioner().advance(client, '〕', () => current)).assertFalse();
        expect(client.moveCalls).assertEqual(0);
      }
    });

    it('moves End past a closing symbol up to LF CRLF CR or document end', 0, async () => {
      for (const ending of ['\n下一行', '\r\n下一行', '\r下一行', '']) {
        const client = new FakePairCursorClient();
        client.rightward = true;
        client.text = `前文【内容】😀尾${ending}`;
        client.cursor = 5;
        client.ignoreSelection = true;
        expect(await new LineEndCursorMover().move(client, () => true)).assertTrue();
        expect(client.cursor).assertEqual(9);
        expect(client.text).assertEqual(`前文【内容】😀尾${ending}`);
        expect(client.moveCalls).assertEqual(3);
      }
    });

    it('moves End with rejected selection and leaves the next line unchanged', 0, async () => {
      const client = new FakePairCursorClient();
      client.rightward = true;
      client.text = '【内容】\n下一行';
      client.cursor = 3;
      client.rejectSelection = true;
      expect(await new LineEndCursorMover().move(client, () => true)).assertTrue();
      expect(client.cursor).assertEqual(4);
      expect(client.moveCalls).assertEqual(1);
    });

    it('does not move End when already at a line boundary or document end', 0, async () => {
      for (const text of ['前文\n下一行', '前文']) {
        const client = new FakePairCursorClient();
        client.rightward = true;
        client.text = text;
        client.cursor = 2;
        expect(await new LineEndCursorMover().move(client, () => true)).assertTrue();
        expect(client.cursor).assertEqual(2);
        expect(client.selectionCalls).assertEqual(0);
        expect(client.moveCalls).assertEqual(0);
      }
    });

    it('verifies each End query window without splitting supplementary characters', 0, async () => {
      const client = new FakePairCursorClient();
      client.rightward = true;
      client.text = '字'.repeat(4095) + '😀尾\n下一行';
      client.cursor = 0;
      client.selectionDelayReads = 5;
      expect(await new LineEndCursorMover().move(client, () => true)).assertTrue();
      expect(client.cursor).assertEqual(4098);
      expect(client.selectionCalls).assertEqual(2);
      expect(client.moveCalls).assertEqual(0);
    });

    it('does not claim End success when the editor ignores both movement APIs', 0, async () => {
      const client = new FakePairCursorClient();
      client.rightward = true;
      client.cursor = 3;
      client.ignoreSelection = true;
      client.ignoreMove = true;
      expect(await new LineEndCursorMover().move(client, () => true)).assertFalse();
      expect(client.cursor).assertEqual(3);
      expect(client.selectionCalls).assertEqual(1);
      expect(client.moveCalls).assertEqual(1);
    });

    it('centers Chinese pairs without changing surrounding text', 0, async () => {
      for (const pair of ['〔〕', '“”', '‘’', '【】', '｛｝', '「」', '『』', '（）', '《》', '〈〉']) {
        const client = new FakePairCursorClient();
        client.text = `前文${pair}后文`;
        expect(await new PairCursorPositioner().position(client, pair, 1, () => true)).assertTrue();
        expect(client.cursor).assertEqual(3);
        expect(client.text).assertEqual(`前文${pair}后文`);
        expect(client.moveCalls).assertEqual(0);
      }
    });

    it('waits for a stale commit cursor and delayed selection', 0, async () => {
      const client = new FakePairCursorClient();
      client.staleReads = 5;
      client.selectionDelayReads = 5;
      expect(await new PairCursorPositioner().position(client, '〔〕', 1, () => true)).assertTrue();
      expect(client.cursor).assertEqual(3);
      expect(client.selectionCalls).assertEqual(1);
      expect(client.moveCalls).assertEqual(0);
    });

    it('falls back when an editor silently ignores collapsed selection', 0, async () => {
      const client = new FakePairCursorClient();
      client.ignoreSelection = true;
      expect(await new PairCursorPositioner().position(client, '〔〕', 1, () => true)).assertTrue();
      expect(client.cursor).assertEqual(3);
      expect(client.moveCalls).assertEqual(1);
    });

    it('handles rejected selection and a supplementary Unicode right delimiter', 0, async () => {
      const client = new FakePairCursorClient();
      client.text = '前文「😀后文';
      client.cursor = 5;
      client.rejectSelection = true;
      expect(await new PairCursorPositioner().position(client, '「😀', 2, () => true)).assertTrue();
      expect(client.cursor).assertEqual(3);
      expect(client.moveCalls).assertEqual(1);
    });

    it('does not claim success or repeat ignored movement', 0, async () => {
      const client = new FakePairCursorClient();
      client.ignoreSelection = true;
      client.ignoreMove = true;
      expect(await new PairCursorPositioner().position(client, '〔〕', 1, () => true)).assertFalse();
      expect(client.cursor).assertEqual(4);
      expect(client.moveCalls).assertEqual(1);
    });

    it('does not move when the committed pair cannot be confirmed', 0, async () => {
      const client = new FakePairCursorClient();
      client.text = '前文其他后文';
      expect(await new PairCursorPositioner().position(client, '〔〕', 1, () => true)).assertFalse();
      expect(client.selectionCalls).assertEqual(0);
      expect(client.moveCalls).assertEqual(0);
    });

    it('stops when the session changes during selection', 0, async () => {
      const client = new FakePairCursorClient();
      let current = true;
      client.ignoreSelection = true;
      client.onSelection = (): void => { current = false; };
      expect(await new PairCursorPositioner().position(client, '〔〕', 1, () => current)).assertFalse();
      expect(client.moveCalls).assertEqual(0);
    });

    it('does not move after the user changes the cursor', 0, async () => {
      const client = new FakePairCursorClient();
      client.ignoreSelection = true;
      client.onSelection = (): void => { client.cursor = 0; };
      expect(await new PairCursorPositioner().position(client, '〔〕', 1, () => true)).assertFalse();
      expect(client.cursor).assertEqual(0);
      expect(client.moveCalls).assertEqual(0);
    });
  });
}
