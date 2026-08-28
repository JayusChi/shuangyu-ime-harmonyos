import { describe, expect, it } from '@ohos/hypium';
import { inputMethodEngine } from '@kit.IMEKit';
import { EditorExtendAction } from '../main/ets/domain/keyboard/KeyboardAction';
import {
  EditorExtendActionExecutor,
  EditorExtendInputClient
} from '../main/ets/infrastructure/ime/ImeConnectionService';

class EditorActionInputClient extends EditorExtendInputClient {
  readonly actions: inputMethodEngine.ExtendAction[] = [];
  readonly cursorMovements: inputMethodEngine.Direction[] = [];
  readonly ranges: inputMethodEngine.Range[] = [];
  cursorIndex: number = 7;
  failCursorMovement: boolean = false;
  copySelectionObserved: boolean = false;
  copyReadyAtMovement: boolean = false;
  beforeText: string = 'selected';
  afterText: string = '';
  readonly insertedTexts: string[] = [];

  async getTextIndexAtCursor(): Promise<number> {
    return this.cursorIndex;
  }

  async getTextBeforeCursor(_length: number): Promise<string> {
    return this.beforeText;
  }

  async getTextAfterCursor(_length: number): Promise<string> {
    return this.afterText;
  }

  async insertText(text: string): Promise<boolean> {
    this.insertedTexts.push(text);
    return true;
  }

  async sendExtendAction(action: inputMethodEngine.ExtendAction): Promise<void> {
    this.actions.push(action);
    if (action === inputMethodEngine.ExtendAction.COPY) {
      setTimeout((): void => {
        this.copySelectionObserved = true;
      }, 5);
    }
  }

  async moveCursor(direction: inputMethodEngine.Direction): Promise<void> {
    if (this.failCursorMovement) {
      throw new Error('movement unavailable');
    }
    this.copyReadyAtMovement = this.copySelectionObserved;
    this.cursorMovements.push(direction);
  }

  async selectByRange(range: inputMethodEngine.Range): Promise<void> {
    this.ranges.push({ start: range.start, end: range.end });
  }
}

export default function editorExtendActionTest() {
  describe('editorExtendAction', () => {
    it('collapsesCopySelectionAndLetsFollowingPasteTargetTheCaret', 0, async () => {
      const client = new EditorActionInputClient();
      client.cursorIndex = 8;
      const executor = new EditorExtendActionExecutor(10);

      const selected = await executor.execute(client, EditorExtendAction.SELECT_ALL);
      const copied = await executor.execute(client, EditorExtendAction.COPY);
      const pasted = await executor.execute(client, EditorExtendAction.PASTE);

      expect(selected).assertTrue();
      expect(copied).assertTrue();
      expect(pasted).assertTrue();
      expect(client.actions.length).assertEqual(2);
      expect(client.actions[0]).assertEqual(inputMethodEngine.ExtendAction.SELECT_ALL);
      expect(client.actions[1]).assertEqual(inputMethodEngine.ExtendAction.COPY);
      expect(client.insertedTexts.length).assertEqual(1);
      expect(client.insertedTexts[0]).assertEqual('selected');
      expect(client.cursorMovements.length).assertEqual(1);
      expect(client.cursorMovements[0]).assertEqual(inputMethodEngine.Direction.CURSOR_RIGHT);
      expect(client.copyReadyAtMovement).assertTrue();
      expect(client.ranges.length).assertEqual(0);
    });

    it('fallsBackToRangeCollapseWhenCursorMovementIsUnavailable', 0, async () => {
      const client = new EditorActionInputClient();
      client.failCursorMovement = true;
      const executor = new EditorExtendActionExecutor(10);

      expect(await executor.execute(client, EditorExtendAction.COPY)).assertTrue();
      expect(client.ranges.length).assertEqual(1);
      expect(client.ranges[0].start).assertEqual(7);
      expect(client.ranges[0].end).assertEqual(7);
    });

    it('usesNativePasteWhenNothingWasCopiedThroughThisKeyboard', 0, async () => {
      const client = new EditorActionInputClient();
      const executor = new EditorExtendActionExecutor(0);

      expect(await executor.execute(client, EditorExtendAction.PASTE)).assertTrue();
      expect(client.actions.length).assertEqual(1);
      expect(client.actions[0]).assertEqual(inputMethodEngine.ExtendAction.PASTE);
      expect(client.insertedTexts.length).assertEqual(0);
    });
  });
}
