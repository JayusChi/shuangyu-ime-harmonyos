import { describe, it, expect } from '@ohos/hypium';
import {
  CompositionPreeditDecoration,
  CompositionPreeditView,
  formatTwoCodePreedit,
  resolveCompositionPreeditView
} from '../main/ets/domain/candidate/CompositionPreeditView';
import { ImeErrorCode } from '../main/ets/common/error/ImeError';
import { Candidate, CompositionResult } from '../main/ets/infrastructure/native/NativeEngineTypes';
import { InputSessionStore } from '../main/ets/state/InputSessionStore';
import { createUnknownEditorContext } from '../main/ets/domain/editor/EditorContext';

// ── 辅助类型 ─────────────────────────────────────────────────────────────────

interface PreeditTestCase {
  raw: string;
  preedit: string;
}

// ── 辅助构造器 ───────────────────────────────────────────────────────────────

function makeResult(rawInput: string, preeditText: string, candidates: Candidate[]): CompositionResult {
  return {
    success: true,
    errorCode: ImeErrorCode.SUCCESS,
    errorMessage: '',
    rawInput,
    preeditText,
    parsedSyllables: rawInput.length > 0 ? [rawInput] : [],
    pendingCode: '',
    parserState: rawInput.length > 0 ? 'complete' : 'empty',
    candidates,
    highlightedIndex: candidates.length > 0 ? 0 : -1,
    hasNextPage: false,
    hasPreviousPage: false,
    candidatePage: 0,
    commitText: '',
    action: null,
    compositionFinished: false
  };
}

function makeCandidate(id: string, text: string): Candidate {
  return { id, text, reading: text, source: 'stage-4.1-test' };
}

export default function stage41Test() {
  // ── 8.1 预编辑展示状态 ────────────────────────────────────────────────────

  describe('stage 4.1 preedit view pure function', () => {
    it('empty rawInput → not visible', 0, () => {
      const view: CompositionPreeditView = resolveCompositionPreeditView({
        rawInput: '',
        preeditText: ''
      });
      expect(view.visible).assertFalse();
      expect(view.displayText).assertEqual('');
      expect(view.decoration).assertEqual(CompositionPreeditDecoration.NONE);
    });

    it('non-empty rawInput with matching preeditText → visible with preeditText', 0, () => {
      const view = resolveCompositionPreeditView({
        rawInput: 'ni',
        preeditText: 'ni'
      });
      expect(view.visible).assertTrue();
      expect(view.displayText).assertEqual('ni');
      expect(view.decoration).assertEqual(CompositionPreeditDecoration.UNDERLINE);
    });

    it('non-empty rawInput, empty preeditText → falls back to rawInput', 0, () => {
      const view = resolveCompositionPreeditView({
        rawInput: 'ni',
        preeditText: ''
      });
      expect(view.visible).assertTrue();
      expect(view.displayText).assertEqual('ni');
      expect(view.decoration).assertEqual(CompositionPreeditDecoration.UNDERLINE);
    });

    it('preedit text with full-pinyin separator still displays two-code raw input', 0, () => {
      const view = resolveCompositionPreeditView({
        rawInput: "nihc",
        preeditText: "ni'hao",
        displaySegments: ['ni', 'hc']
      });
      expect(view.visible).assertTrue();
      expect(view.displayText).assertEqual("ni'hc");
      expect(view.decoration).assertEqual(CompositionPreeditDecoration.UNDERLINE);
    });

    it('long rawInput: display text is fully segmented, no underline chars injected', 0, () => {
      const longInput = 'nihaoaoaoao';
      const view = resolveCompositionPreeditView({
        rawInput: longInput,
        preeditText: longInput,
        displaySegments: ['ni', 'ha', 'oa', 'oa', 'oa', 'o']
      });
      expect(view.visible).assertTrue();
      expect(view.displayText).assertEqual("ni'ha'oa'oa'oa'o");
      // The display text must not contain underscores injected by the preedit logic
      expect(view.displayText.indexOf('_')).assertEqual(-1);
    });

    it('underline is only decoration — raw code can be recovered from displayText', 0, () => {
      const raw = 'shuangpin';
      const view = resolveCompositionPreeditView({
        rawInput: raw,
        preeditText: raw,
        displaySegments: ['sh', 'ua', 'ng', 'pi', 'n']
      });
      expect(view.displayText).assertEqual("sh'ua'ng'pi'n");
      expect(view.displayText.split("'").join('')).assertEqual(raw);
    });

    it('decoration enum is UNDERLINE (not NONE) when visible', 0, () => {
      const view = resolveCompositionPreeditView({ rawInput: 'a', preeditText: 'a' });
      expect(view.visible).assertTrue();
      expect(view.decoration).assertEqual(CompositionPreeditDecoration.UNDERLINE);
    });
  });

  // ── 8.2 InputSessionStore 中 rawInput 正确清空 ────────────────────────────

  describe('stage 4.1 store preedit lifecycle', () => {
    it('rawInput present → preedit view visible', 0, () => {
      const store = new InputSessionStore();
      store.applyEditorContext(createUnknownEditorContext());
      store.updateComposition(makeResult('ni', 'ni', [makeCandidate('c1', '你')]));
      const snap = store.getSnapshot();
      const view = resolveCompositionPreeditView({ rawInput: snap.rawInput, preeditText: snap.preeditText });
      expect(view.visible).assertTrue();
      expect(view.displayText).assertEqual('ni');
      expect(view.decoration).assertEqual(CompositionPreeditDecoration.UNDERLINE);
    });

    it('rawInput cleared after clearComposition → preedit view not visible', 0, () => {
      const store = new InputSessionStore();
      store.applyEditorContext(createUnknownEditorContext());
      store.updateComposition(makeResult('ni', 'ni', [makeCandidate('c1', '你')]));
      store.clearComposition();
      const snap = store.getSnapshot();
      expect(snap.rawInput).assertEqual('');
      const view = resolveCompositionPreeditView({ rawInput: snap.rawInput, preeditText: snap.preeditText });
      expect(view.visible).assertFalse();
    });

    it('markSessionStopped clears rawInput → preedit view not visible', 0, () => {
      const store = new InputSessionStore();
      store.applyEditorContext(createUnknownEditorContext());
      store.updateComposition(makeResult('ni', 'ni', []));
      store.markSessionStopped();
      const snap = store.getSnapshot();
      expect(snap.rawInput).assertEqual('');
      const view = resolveCompositionPreeditView({ rawInput: snap.rawInput, preeditText: snap.preeditText });
      expect(view.visible).assertFalse();
    });

    it('resetAll clears rawInput → preedit view not visible', 0, () => {
      const store = new InputSessionStore();
      store.applyEditorContext(createUnknownEditorContext());
      store.updateComposition(makeResult('ni', 'ni', []));
      store.resetAll();
      const snap = store.getSnapshot();
      expect(snap.rawInput).assertEqual('');
      const view = resolveCompositionPreeditView({ rawInput: snap.rawInput, preeditText: snap.preeditText });
      expect(view.visible).assertFalse();
    });

    it('applyEditorContext clears rawInput → preedit view not visible', 0, () => {
      const store = new InputSessionStore();
      store.applyEditorContext(createUnknownEditorContext());
      store.updateComposition(makeResult('ni', 'ni', []));
      // Switching editor context must reset composition
      store.applyEditorContext(createUnknownEditorContext());
      const snap = store.getSnapshot();
      expect(snap.rawInput).assertEqual('');
      const view = resolveCompositionPreeditView({ rawInput: snap.rawInput, preeditText: snap.preeditText });
      expect(view.visible).assertFalse();
    });

    it('candidates non-empty + rawInput non-empty: preedit still visible (underline prompt alongside candidates)', 0, () => {
      const store = new InputSessionStore();
      store.applyEditorContext(createUnknownEditorContext());
      const candidates = [
        makeCandidate('c1', '你'),
        makeCandidate('c2', '尼'),
        makeCandidate('c3', '逆')
      ];
      store.updateComposition(makeResult('ni', 'ni', candidates));
      const snap = store.getSnapshot();
      expect(snap.rawInput).assertEqual('ni');
      expect(snap.candidates.length).assertEqual(3);
      const view = resolveCompositionPreeditView({ rawInput: snap.rawInput, preeditText: snap.preeditText });
      expect(view.visible).assertTrue();
      expect(view.decoration).assertEqual(CompositionPreeditDecoration.UNDERLINE);
    });
  });

  // ── 8.3 并发保护：旧查询不能恢复已清除的编码 ──────────────────────────────

  describe('stage 4.1 stale-result protection (pure state)', () => {
    it('generation advance prevents stale update from making rawInput reappear', 0, () => {
      const store = new InputSessionStore();
      store.applyEditorContext(createUnknownEditorContext());
      const gen1 = store.getSessionGeneration();
      store.updateComposition(makeResult('ni', 'ni', []));
      // Advance generation (simulates session switch or focus change)
      store.advanceSessionGeneration();
      const gen2 = store.getSessionGeneration();
      expect(gen2).assertLarger(gen1);
      // Simulate stale async result updating the store — in production the
      // generation check in InputSessionController prevents this call, but we
      // test the store directly: a later clearComposition always wins over a
      // stale update that happened to land.
      store.clearComposition();
      const snap = store.getSnapshot();
      expect(snap.rawInput).assertEqual('');
      const view = resolveCompositionPreeditView({ rawInput: snap.rawInput, preeditText: snap.preeditText });
      expect(view.visible).assertFalse();
    });

    it('rawInput empty after delete-to-empty → preedit not visible', 0, () => {
      const store = new InputSessionStore();
      store.applyEditorContext(createUnknownEditorContext());
      store.updateComposition(makeResult('ni', 'ni', []));
      // After deleting to empty the engine returns empty rawInput
      store.updateComposition(makeResult('', '', []));
      const snap = store.getSnapshot();
      expect(snap.rawInput).assertEqual('');
      const view = resolveCompositionPreeditView({ rawInput: snap.rawInput, preeditText: snap.preeditText });
      expect(view.visible).assertFalse();
    });

    it('preedit underline does not include the _ character in displayText', 0, () => {
      // Cross-check that neither rawInput nor preeditText is ever injected with
      // the underscore character `_` by the preedit view logic.
      const testCases: PreeditTestCase[] = [
        { raw: 'ni', preedit: 'ni' } as PreeditTestCase,
        { raw: 'nihao', preedit: "ni'hao" } as PreeditTestCase,
        { raw: 'abc', preedit: 'abc' } as PreeditTestCase
      ];
      testCases.forEach((tc: PreeditTestCase) => {
        const view = resolveCompositionPreeditView({ rawInput: tc.raw, preeditText: tc.preedit });
        expect(view.displayText.indexOf('_')).assertEqual(-1);
      });
    });
  });

  // ── 8.4 回归：display 逻辑不改变 candidates/rawInput 数据结构 ─────────────

  describe('stage 4.1 regression: data structures untouched', () => {
    it('rawInput stored in snapshot is not modified', 0, () => {
      const store = new InputSessionStore();
      store.applyEditorContext(createUnknownEditorContext());
      store.updateComposition(makeResult('nih', 'nih', []));
      const snap = store.getSnapshot();
      expect(snap.rawInput).assertEqual('nih');
      // rawInput must not contain any underline or separator injected by display layer
      expect(snap.rawInput.indexOf('_')).assertEqual(-1);
    });

    it('preeditText stored in snapshot is not modified', 0, () => {
      const store = new InputSessionStore();
      store.applyEditorContext(createUnknownEditorContext());
      store.updateComposition(makeResult('nihc', "ni'hao", []));
      const snap = store.getSnapshot();
      expect(snap.preeditText).assertEqual("ni'hao");
    });

    it('candidate list order and count not affected by preedit underline logic', 0, () => {
      const store = new InputSessionStore();
      store.applyEditorContext(createUnknownEditorContext());
      const candidates = [
        makeCandidate('a', '你'),
        makeCandidate('b', '尼'),
        makeCandidate('c', '泥')
      ];
      store.updateComposition(makeResult('ni', 'ni', candidates));
      const snap = store.getSnapshot();
      expect(snap.candidates.length).assertEqual(3);
      expect(snap.candidates[0].id).assertEqual('a');
      expect(snap.candidates[1].id).assertEqual('b');
      expect(snap.candidates[2].id).assertEqual('c');
    });

    it('error state from last error code does not affect preedit view function', 0, () => {
      // Error state is controlled by candidateBarState ERROR, not by this function
      const view = resolveCompositionPreeditView({ rawInput: 'ni', preeditText: 'ni' });
      expect(view.visible).assertTrue();
      expect(view.decoration).assertEqual(CompositionPreeditDecoration.UNDERLINE);
    });

    it('two-code display formatter never mutates the stored source string', 0, () => {
      const raw = 'vegewt';
      expect(formatTwoCodePreedit(raw, ['ve', 'ge', 'wt'])).assertEqual("ve'ge'wt");
      expect(raw).assertEqual('vegewt');
    });
  });
}
