import { describe, expect, it } from '@ohos/hypium';
import { inputMethodEngine } from '@kit.IMEKit';
import {
  CompositionInputClient,
  CompositionTextManager,
  CompositionTextMode,
  PreviewOwnershipState,
  TextPreviewInputClient,
  TextPreviewManager
} from '../main/ets/infrastructure/ime/ImeConnectionService';

interface PreviewCall {
  text: string;
  start: number;
  end: number;
}

class FakeTextPreviewClient extends TextPreviewInputClient {
  cursor: number = 5;
  cursorReadCount: number = 0;
  calls: PreviewCall[] = [];
  finishCount: number = 0;
  failSet: boolean = false;
  failFinish: boolean = false;

  async getTextIndexAtCursor(): Promise<number> {
    this.cursorReadCount += 1;
    return this.cursor;
  }

  async setPreviewText(text: string, range: inputMethodEngine.Range): Promise<void> {
    this.calls.push({ text, start: range.start, end: range.end });
    if (this.failSet) {
      throw new Error('simulated setPreviewText failure');
    }
    const start = range.start === -1 ? this.calls[0].start : range.start;
    this.cursor = start + text.length;
  }

  async finishTextPreview(): Promise<void> {
    this.finishCount += 1;
    if (this.failFinish) {
      throw new Error('simulated finishTextPreview failure');
    }
  }
}

class DelayedFinishTextPreviewClient extends FakeTextPreviewClient {
  unsafeRestartCount: number = 0;
  private finishSettled: boolean = true;
  private cursorBeforeLatestSet: number = 0;

  async setPreviewText(text: string, range: inputMethodEngine.Range): Promise<void> {
    if (!this.finishSettled) {
      this.unsafeRestartCount += 1;
    }
    this.cursorBeforeLatestSet = this.cursor;
    await super.setPreviewText(text, range);
  }

  async finishTextPreview(): Promise<void> {
    await super.finishTextPreview();
    const settledCursor = this.cursor;
    this.cursor = this.cursorBeforeLatestSet;
    this.finishSettled = false;
    setTimeout((): void => {
      this.cursor = settledCursor;
      this.finishSettled = true;
    }, 40);
  }
}

class PreviewNotSupportedError extends Error {
  code: number = 12800011;
}

class FakeCompositionClient extends CompositionInputClient {
  text: string = '';
  cursor: number = 0;
  insertCount: number = 0;
  compatibleDeleteCount: number = 0;
  previewCount: number = 0;
  cursorReadCount: number = 0;
  forwardReadCount: number = 0;
  failInsert: boolean = false;
  insertApplyDelayMs: number = 0;
  failPreviewUnsupported: boolean = false;
  failPreviewIndeterminate: boolean = false;
  private selectionStart: number = 0;
  private selectionEnd: number = 0;
  private previewStart: number = -1;
  private previewText: string = '';

  async getTextIndexAtCursor(): Promise<number> {
    this.cursorReadCount += 1;
    return this.cursor;
  }

  async getForward(length: number): Promise<string> {
    this.forwardReadCount += 1;
    return this.text.slice(Math.max(0, this.cursor - length), this.cursor);
  }

  async setPreviewText(text: string, range: inputMethodEngine.Range): Promise<void> {
    this.previewCount += 1;
    if (this.failPreviewUnsupported) {
      this.failPreviewUnsupported = false;
      throw new PreviewNotSupportedError('preview unsupported');
    }
    if (this.failPreviewIndeterminate) {
      this.failPreviewIndeterminate = false;
      throw new Error('preview indeterminate');
    }
    const start = range.start === -1 && range.end === -1 ? this.previewStart : range.start;
    const end = range.start === -1 && range.end === -1
      ? this.previewStart + this.previewText.length
      : range.end;
    this.text = this.text.slice(0, start) + text + this.text.slice(end);
    this.previewStart = start;
    this.previewText = text;
    this.cursor = start + text.length;
    this.selectionStart = this.cursor;
    this.selectionEnd = this.cursor;
  }

  async finishTextPreview(): Promise<void> {
    this.previewStart = -1;
    this.previewText = '';
  }

  async selectByRange(range: inputMethodEngine.Range): Promise<void> {
    this.selectionStart = range.start;
    this.selectionEnd = range.end;
    this.cursor = range.end;
  }

  async insertText(text: string): Promise<boolean> {
    this.insertCount += 1;
    if (this.failInsert) {
      this.failInsert = false;
      return false;
    }
    if (this.selectionStart === this.selectionEnd && this.selectionEnd !== this.cursor) {
      this.selectionStart = this.cursor;
      this.selectionEnd = this.cursor;
    }
    const replacementStart = this.selectionStart;
    const replacementEnd = this.selectionEnd;
    const applyInsert = (): void => {
      this.text = this.text.slice(0, replacementStart) + text + this.text.slice(replacementEnd);
      this.cursor = replacementStart + text.length;
      this.selectionStart = this.cursor;
      this.selectionEnd = this.cursor;
    };
    if (this.insertApplyDelayMs > 0) {
      setTimeout(applyInsert, this.insertApplyDelayMs);
      return true;
    }
    applyInsert();
    return true;
  }

  async deleteTextBeforeCursor(length: number): Promise<boolean> {
    this.compatibleDeleteCount += 1;
    const start = Math.max(0, this.cursor - length);
    this.text = this.text.slice(0, start) + this.text.slice(this.cursor);
    this.cursor = start;
    this.selectionStart = this.cursor;
    this.selectionEnd = this.cursor;
    return true;
  }
}

class StaleCursorCompositionClient extends FakeCompositionClient {
  private staleReadCount: number = 1;

  async getTextIndexAtCursor(): Promise<number> {
    if (this.staleReadCount > 0) {
      this.staleReadCount -= 1;
      return this.cursor + 1;
    }
    return this.cursor;
  }
}

class UnreadableForwardCompositionClient extends FakeCompositionClient {
  async getForward(length: number): Promise<string> {
    throw new Error(`simulated unreadable forward text: ${length}`);
  }
}

class LaggingForwardCompositionClient extends FakeCompositionClient {
  async getForward(_length: number): Promise<string> {
    this.forwardReadCount += 1;
    return '';
  }
}

class DeferredFinishCompositionClient extends FakeCompositionClient {
  private finishResolver?: () => void;
  private readonly finishGate: Promise<void> = new Promise<void>((resolve: () => void) => {
    this.finishResolver = resolve;
  });

  async finishTextPreview(): Promise<void> {
    await this.finishGate;
    await super.finishTextPreview();
  }

  releaseFinish(): void {
    this.finishResolver?.();
  }
}

class PcSelectionRequiredCompositionClient extends FakeCompositionClient {
  private cursorAnchored: boolean = false;

  async selectByRange(range: inputMethodEngine.Range): Promise<void> {
    await super.selectByRange(range);
    this.cursorAnchored = range.start === range.end;
  }

  async insertText(text: string): Promise<boolean> {
    if (!this.cursorAnchored) {
      return false;
    }
    this.cursorAnchored = false;
    return await super.insertText(text);
  }
}

class PcFalseAcknowledgementCompositionClient extends FakeCompositionClient {
  async insertText(text: string): Promise<boolean> {
    await super.insertText(text);
    return false;
  }
}

function nextTurn(): Promise<void> {
  return new Promise<void>((resolve: () => void) => setTimeout(resolve, 0));
}

export default function textPreviewManagerTest() {
  describe('TextPreviewManager', () => {
    it('embeddedCodesReplaceAndCancelWithoutLeavingLettersInExistingText', 0, async () => {
      const manager = new CompositionTextManager();
      const client = new FakeCompositionClient();
      client.text = '原文';
      client.cursor = 2;
      for (const raw of ['k', 'kj', 'kjk', 'kj']) {
        expect(await manager.update(client, raw, true, 91)).assertTrue();
        expect(client.text).assertEqual(`原文${raw}`);
      }
      expect(await manager.commitWithRemaining(client, '看看', '', 91)).assertTrue();
      expect(client.text).assertEqual('原文看看');
      expect(await manager.update(client, 'kj', true, 91)).assertTrue();
      expect(await manager.clear(client, 91)).assertTrue();
      expect(client.text).assertEqual('原文看看');
      expect(client.insertCount).assertEqual(0);
      expect(client.compatibleDeleteCount).assertEqual(0);
    });

    it('anchorsFirstPreviewAtCursorAndReplacesPreviousPreviewRange', 0, async () => {
      const manager = new TextPreviewManager();
      const client = new FakeTextPreviewClient();

      expect(await manager.update(client, 'n')).assertTrue();
      expect(await manager.update(client, 'ni')).assertTrue();
      expect(client.calls[0].text).assertEqual('n');
      expect(client.calls[0].start).assertEqual(5);
      expect(client.calls[0].end).assertEqual(5);
      expect(client.calls[1].text).assertEqual('ni');
      expect(client.calls[1].start).assertEqual(-1);
      expect(client.calls[1].end).assertEqual(-1);
    });

    it('deleteUpdatesPreviewAndDeleteToEmptyClearsAndFinishes', 0, async () => {
      const manager = new TextPreviewManager();
      const client = new FakeTextPreviewClient();

      await manager.update(client, 'ni');
      expect(await manager.update(client, 'n')).assertTrue();
      expect(client.calls[1].start).assertEqual(-1);
      expect(client.calls[1].end).assertEqual(-1);
      expect(await manager.update(client, '')).assertTrue();
      expect(client.calls[2].text).assertEqual('');
      expect(client.calls[2].start).assertEqual(-1);
      expect(client.calls[2].end).assertEqual(-1);
      expect(client.finishCount).assertEqual(1);
      expect(manager.hasPreviewText()).assertFalse();
    });

    it('candidateReplacesPreviewBeforeFinishing', 0, async () => {
      const manager = new TextPreviewManager();
      const client = new FakeTextPreviewClient();

      await manager.update(client, 'ni');
      expect(await manager.commitReplacement(client, '你')).assertTrue();
      expect(client.calls[1].text).assertEqual('你');
      expect(client.calls[1].start).assertEqual(-1);
      expect(client.calls[1].end).assertEqual(-1);
      expect(client.finishCount).assertEqual(1);
      expect(manager.hasPreviewText()).assertFalse();
    });

    it('confirmedPreviewFinishDoesNotPayTheFullFallbackWindow', 0, async () => {
      const manager = new TextPreviewManager();
      const client = new FakeTextPreviewClient();

      await manager.update(client, 'ni');
      let completed = false;
      const committing = manager.commitReplacement(client, '你').then((result: boolean): boolean => {
        completed = true;
        return result;
      });
      await nextTurn();

      expect(completed).assertTrue();
      expect(await committing).assertTrue();
      expect(client.cursorReadCount > 1).assertTrue();
    });

    it('waitsForFinishedPreviewBeforeStartingRemainingRawInputPreview', 0, async () => {
      const manager = new TextPreviewManager();
      const client = new DelayedFinishTextPreviewClient();

      expect(await manager.update(client, 'uurufa')).assertTrue();
      expect(await manager.commitReplacement(client, '输入')).assertTrue();
      expect(await manager.update(client, 'fa')).assertTrue();
      expect(client.unsafeRestartCount).assertEqual(0);
      expect(client.calls[2].text).assertEqual('fa');
    });

    it('previewFailureDoesNotRetryOrInvokeFinish', 0, async () => {
      const manager = new TextPreviewManager();
      const client = new FakeTextPreviewClient();
      client.failSet = true;

      expect(await manager.update(client, 'n')).assertFalse();
      expect(client.calls.length).assertEqual(1);
      expect(client.finishCount).assertEqual(0);
      expect(manager.hasPreviewText()).assertFalse();
    });
  });

  describe('CompositionTextManager', () => {
    it('commits literal paired symbols while the composition manager is idle', 0, async () => {
      const manager = new CompositionTextManager();
      const client = new FakeCompositionClient();
      client.text = '前';
      client.cursor = 1;

      expect(await manager.commit(client, '（）', 7)).assertTrue();
      expect(client.text).assertEqual('前（）');
      expect(client.cursor).assertEqual(3);
      expect(client.insertCount).assertEqual(1);
      expect(manager.getMode()).assertEqual(CompositionTextMode.NONE);
    });

    it('supportedEditorKeepsPreviewPath', 0, async () => {
      const manager = new CompositionTextManager();
      const client = new FakeCompositionClient();

      expect(await manager.update(client, 'n', true, 7)).assertTrue();
      expect(await manager.update(client, 'ni', true, 7)).assertTrue();
      expect(manager.getMode()).assertEqual(CompositionTextMode.PREVIEW);
      expect(client.previewCount).assertEqual(2);
      expect(client.insertCount).assertEqual(0);
      expect(client.text).assertEqual('ni');
    });

    it('candidateBarCompositionNeverLeaksFirstLetterIntoExistingEditorText', 0, async () => {
      const manager = new CompositionTextManager();
      const client = new FakeCompositionClient();
      client.text = '原文';
      client.cursor = 2;

      for (const code of ['n', 'ni', 'n', '']) {
        expect(await manager.update(client, code, false, 8)).assertTrue();
        expect(client.text).assertEqual('原文');
        expect(client.cursor).assertEqual(2);
        expect(client.previewCount).assertEqual(0);
        expect(client.insertCount).assertEqual(0);
      }
      expect(await manager.update(client, 'ni', false, 8)).assertTrue();
      expect(await manager.commit(client, '你', 8)).assertTrue();
      expect(client.text).assertEqual('原文你');
      expect(client.insertCount).assertEqual(1);
      expect(client.previewCount).assertEqual(0);
    });

    it('unsupportedEditorKeepsRawInputOnlyInCandidateBar', 0, async () => {
      const manager = new CompositionTextManager();
      const client = new FakeCompositionClient();
      const inputs = ['n', 'ni', 'nih', 'niha', 'nihao'];

      for (let index = 0; index < inputs.length; index += 1) {
        expect(await manager.update(client, inputs[index], false, 9)).assertTrue();
      }
      expect(manager.getMode()).assertEqual(CompositionTextMode.CANDIDATE_BAR);
      expect(manager.getTextLength()).assertEqual(5);
      expect(client.text).assertEqual('');
      expect(client.insertCount).assertEqual(0);
    });

    it('unsupportedEditorUpdatesCandidateBarWithoutEditorWrites', 0, async () => {
      const manager = new CompositionTextManager();
      const client = new FakeCompositionClient();

      expect(await manager.update(client, 'n', false, 10)).assertTrue();
      expect(await manager.update(client, 'nihao', false, 10)).assertTrue();

      expect(manager.getMode()).assertEqual(CompositionTextMode.CANDIDATE_BAR);
      expect(manager.getTextLength()).assertEqual(5);
      expect(client.text).assertEqual('');
      expect(client.insertCount).assertEqual(0);
    });

    it('serializedHardwareContinuationDoesNotWaitForRedundantEditorReads', 0, async () => {
      const manager = new CompositionTextManager();
      const client = new FakeCompositionClient();

      expect(await manager.update(client, 'q', false, 42)).assertTrue();
      const cursorReadsAfterFirstKey = client.cursorReadCount;
      const forwardReadsAfterFirstKey = client.forwardReadCount;
      expect(await manager.update(
        client,
        'qazwsxedcrfvtgby',
        false,
        42,
        (): boolean => true,
        false,
        true
      )).assertTrue();

      expect(client.text).assertEqual('');
      expect(client.cursorReadCount).assertEqual(cursorReadsAfterFirstKey);
      expect(client.forwardReadCount).assertEqual(forwardReadsAfterFirstKey);
      expect(client.insertCount).assertEqual(0);
      expect(manager.getTextLength()).assertEqual(16);
    });

    it('candidateBarCompositionCommitsDirectlyAtTheCursor', 0, async () => {
      const manager = new CompositionTextManager();
      const client = new FakeCompositionClient();
      client.text = 'A';
      client.cursor = 1;

      await manager.update(client, 'nihao', false, 11);
      expect(await manager.commit(client, '你好', 11)).assertTrue();
      expect(client.text).assertEqual('A你好');
      expect(manager.getMode()).assertEqual(CompositionTextMode.NONE);
    });

    it('pcHostCandidateCommitAnchorsTheCursorWithoutWritingRawCode', 0, async () => {
      const manager = new CompositionTextManager();
      const client = new PcSelectionRequiredCompositionClient();
      client.text = 'PC:';
      client.cursor = 3;

      expect(await manager.update(client, 'nihao', false, 44)).assertTrue();
      expect(client.text).assertEqual('PC:');
      expect(await manager.commit(client, '你好', 44)).assertTrue();
      expect(client.text).assertEqual('PC:你好');
      expect(client.text.indexOf('nihao')).assertEqual(-1);
      expect(manager.getMode()).assertEqual(CompositionTextMode.NONE);
    });

    it('pcHostObservedInsertionOverridesAFalseCompatibilityAcknowledgement', 0, async () => {
      const manager = new CompositionTextManager();
      const client = new PcFalseAcknowledgementCompositionClient();

      expect(await manager.update(client, 'ni', false, 45)).assertTrue();
      expect(await manager.commit(client, '你', 45)).assertTrue();
      expect(client.text).assertEqual('你');
      expect(client.insertCount).assertEqual(1);
      expect(manager.getMode()).assertEqual(CompositionTextMode.NONE);
    });

    it('partialCandidateUsesCommittedEndWhenHarmonyCursorIsStale', 0, async () => {
      const manager = new CompositionTextManager();
      const client = new FakeCompositionClient();

      expect(await manager.update(client, 'uurufa', true, 12)).assertTrue();
      expect(await manager.commit(client, '输入', 12)).assertTrue();
      client.cursor = 6;
      expect(await manager.update(client, 'fa', false, 12, (): boolean => true, true)).assertTrue();
      client.cursor = 4;
      expect(await manager.commit(client, '法', 12)).assertTrue();
      expect(client.text).assertEqual('输入法');
    });

    it('twoPartialNumberSelectionsNeverDuplicateTheOldRawComposition', 0, async () => {
      const manager = new CompositionTextManager();
      const client = new FakeCompositionClient();
      const rawInput = 'jintiandetiangidaodizmy';

      expect(await manager.update(client, rawInput, false, 43)).assertTrue();
      // Desktop browser InputClient may resolve insertText before its editor
      // mutation is visible. Both commits remain serialized, while the raw
      // tail stays exclusively in the candidate bar.
      client.insertApplyDelayMs = 20;
      expect(await manager.commitWithRemaining(
        client,
        '今天的天气到底',
        'zmy',
        43
      )).assertTrue();
      expect(client.text).assertEqual('今天的天气到底');
      expect(manager.getMode()).assertEqual(CompositionTextMode.CANDIDATE_BAR);
      expect(manager.getTextLength()).assertEqual(3);

      expect(await manager.commitWithRemaining(client, '怎么样', '', 43)).assertTrue();
      expect(client.text).assertEqual('今天的天气到底怎么样');
      expect(manager.getMode()).assertEqual(CompositionTextMode.NONE);
    });

    it('remainingCandidateBarInputCommitsAfterThePreviousChineseText', 0, async () => {
      const manager = new CompositionTextManager();
      const client = new FakeCompositionClient();

      expect(await manager.update(client, 'wxq', true, 29)).assertTrue();
      expect(await manager.commit(client, '正向切分段', 29)).assertTrue();
      expect(await manager.update(client, 'r', false, 29, (): boolean => true, true)).assertTrue();
      expect(client.text).assertEqual('正向切分段');
      expect(manager.getMode()).assertEqual(CompositionTextMode.CANDIDATE_BAR);
      expect(manager.getTextLength()).assertEqual(1);
      expect(await manager.commit(client, '续', 29)).assertTrue();
      expect(client.text).assertEqual('正向切分段续');
    });

    it('candidateBarDeleteNeverMutatesEditorText', 0, async () => {
      const manager = new CompositionTextManager();
      const client = new FakeCompositionClient();

      await manager.update(client, 'ni', false, 13);
      expect(await manager.update(client, 'n', false, 13)).assertTrue();
      expect(client.text).assertEqual('');
      expect(manager.getTextLength()).assertEqual(1);
      expect(await manager.update(client, '', false, 13)).assertTrue();
      expect(client.text).assertEqual('');
      expect(manager.getMode()).assertEqual(CompositionTextMode.NONE);
    });

    it('candidateBarClearDoesNotReadAnUnsupportedEditor', 0, async () => {
      const manager = new CompositionTextManager();
      const client = new UnreadableForwardCompositionClient();

      expect(await manager.update(client, 'vut', false, 31)).assertTrue();
      expect(client.text).assertEqual('');
      expect(await manager.update(client, '', false, 31)).assertTrue();
      expect(client.text).assertEqual('');
      expect(manager.getMode()).assertEqual(CompositionTextMode.NONE);
    });

    it('candidateBarClearDoesNotDeleteCommittedEditorText', 0, async () => {
      const manager = new CompositionTextManager();
      const client = new FakeCompositionClient();

      expect(await manager.update(client, 'vut', false, 37)).assertTrue();
      expect(client.text).assertEqual('');
      expect(await manager.update(client, '', false, 37)).assertTrue();
      expect(client.text).assertEqual('');
      expect(client.compatibleDeleteCount).assertEqual(0);
      expect(manager.getMode()).assertEqual(CompositionTextMode.NONE);
    });

    it('confirmedUnsupportedPreviewFallsBackExactlyOnce', 0, async () => {
      const manager = new CompositionTextManager();
      const client = new FakeCompositionClient();
      client.failPreviewUnsupported = true;

      expect(await manager.update(client, 'n', true, 15)).assertTrue();
      expect(client.previewCount).assertEqual(1);
      expect(client.insertCount).assertEqual(0);
      expect(client.text).assertEqual('');
      expect(manager.getMode()).assertEqual(CompositionTextMode.CANDIDATE_BAR);
    });

    it('indeterminatePreviewFailureNeverFallsBackToInsert', 0, async () => {
      const manager = new CompositionTextManager();
      const client = new FakeCompositionClient();
      client.failPreviewIndeterminate = true;

      expect(await manager.update(client, 'n', true, 17)).assertFalse();
      expect(client.previewCount).assertEqual(1);
      expect(client.insertCount).assertEqual(0);
      expect(client.text).assertEqual('');
    });

    it('failedCandidateCommitRetainsCandidateBarCompositionForRetry', 0, async () => {
      const manager = new CompositionTextManager();
      const client = new FakeCompositionClient();
      await manager.update(client, 'nihao', false, 19);
      client.failInsert = true;

      expect(await manager.commit(client, '你好', 19)).assertFalse();
      expect(manager.getMode()).assertEqual(CompositionTextMode.CANDIDATE_BAR);
      expect(client.text).assertEqual('');
      expect(await manager.commit(client, '你好', 19)).assertTrue();
      expect(client.text).assertEqual('你好');
    });

    it('candidateBarUpdatesIgnoreCursorMovementButRejectOldGeneration', 0, async () => {
      const manager = new CompositionTextManager();
      const client = new FakeCompositionClient();
      await manager.update(client, 'ni', false, 21);
      client.cursor = 0;

      expect(await manager.update(client, 'nih', false, 21)).assertTrue();
      expect(client.text).assertEqual('');
      expect(manager.getTextLength()).assertEqual(3);
      client.cursor = 2;
      expect(await manager.update(client, 'nih', false, 22)).assertFalse();
      expect(client.text).assertEqual('');
    });

    it('serializesClearAndNextUpdateWithoutDroppingPreviewOwnership', 0, async () => {
      const manager = new CompositionTextManager();
      const client = new DeferredFinishCompositionClient();
      expect(await manager.update(client, 'ni', true, 41)).assertTrue();
      expect(manager.getOwnershipState()).assertEqual(PreviewOwnershipState.OWNED);

      const clearing = manager.clear(client, 41);
      const nextUpdate = manager.update(client, 'n', true, 41);
      await nextTurn();
      expect(manager.getOwnershipState()).assertEqual(PreviewOwnershipState.CLEARING);
      expect(client.previewCount).assertEqual(2);

      client.releaseFinish();
      expect(await clearing).assertTrue();
      expect(await nextUpdate).assertTrue();
      expect(manager.getOwnershipState()).assertEqual(PreviewOwnershipState.OWNED);
      expect(client.text).assertEqual('n');
    });

    it('candidateBarUpdateDoesNotPerformMultiStepEditorReplacement', 0, async () => {
      const manager = new CompositionTextManager();
      const client = new FakeCompositionClient();
      await manager.update(client, 'n', false, 23);
      let checks = 0;
      const guard = (): boolean => {
        checks += 1;
        return checks < 3;
      };

      expect(await manager.update(client, 'ni', false, 23, guard)).assertTrue();
      expect(checks).assertEqual(1);
      expect(client.text).assertEqual('');
      expect(client.insertCount).assertEqual(0);
    });

    it('candidateBarInputNeverTouchesAStaleCursorAnchor', 0, async () => {
      const manager = new CompositionTextManager();
      const client = new StaleCursorCompositionClient();
      client.text = '你好刚';
      client.cursor = 3;

      expect(await manager.update(client, 'b', false, 25)).assertTrue();
      expect(client.text).assertEqual('你好刚');
      expect(await manager.update(client, 'be', false, 25)).assertTrue();
      expect(client.text).assertEqual('你好刚');
      expect(manager.getTextLength()).assertEqual(2);
    });

    it('candidateBarCompositionDoesNotDependOnHostEditorText', 0, async () => {
      const manager = new CompositionTextManager();
      const client = new FakeCompositionClient();

      expect(await manager.update(client, 'e', false, 26)).assertTrue();
      expect(await manager.isTextAttached(client, 26)).assertTrue();
      client.text = '';
      client.cursor = 0;

      expect(await manager.isTextAttached(client, 26)).assertTrue();
    });

    it('keepsCandidateBarOwnershipWithoutCursorQueries', 0, async () => {
      const manager = new CompositionTextManager();
      const client = new LaggingForwardCompositionClient();

      expect(await manager.update(client, 's', false, 28)).assertTrue();
      expect(await manager.isTextAttached(client, 28)).assertTrue();
      expect(await manager.update(client, 'so', false, 28)).assertTrue();
      expect(client.text).assertEqual('');
      expect(manager.getTextLength()).assertEqual(2);
    });

    it('exhaustivelyKeepsCandidateBarTextOutOfTheEditor', 0, async () => {
      const actions = ['b', 'e', 'x', 'delete'];
      let passed = true;
      let failedSequence = '';

      for (let encoded = 0; encoded < 1024 && passed; encoded += 1) {
        const manager = new CompositionTextManager();
        const client = new FakeCompositionClient();
        client.text = '前缀';
        client.cursor = 2;
        let rawInput = '';
        let value = encoded;
        let sequence = '';

        for (let step = 0; step < 5; step += 1) {
          const action = actions[value % actions.length];
          value = Math.floor(value / actions.length);
          sequence = sequence.length === 0 ? action : `${sequence},${action}`;
          rawInput = action === 'delete'
            ? rawInput.slice(0, Math.max(0, rawInput.length - 1))
            : rawInput + action;
          const updated = await manager.update(client, rawInput, false, 27);
          if (!updated || client.text !== '前缀' || manager.getTextLength() !== rawInput.length) {
            passed = false;
            failedSequence = sequence;
            break;
          }
        }
      }

      expect(passed).assertTrue();
      expect(failedSequence).assertEqual('');
    });
  });
}
