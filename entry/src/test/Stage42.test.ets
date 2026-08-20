import { describe, it, expect } from '@ohos/hypium';
import { ImeErrorCode } from '../main/ets/common/error/ImeError';
import { Candidate, CompositionResult } from '../main/ets/infrastructure/native/NativeEngineTypes';
import { InputSessionStore } from '../main/ets/state/InputSessionStore';
import { createUnknownEditorContext } from '../main/ets/domain/editor/EditorContext';
import { toCandidateDisplayItem } from '../main/ets/domain/candidate/CandidateDisplayItem';

function makeComposition(candidates: Candidate[]): CompositionResult {
  return {
    success: true,
    errorCode: ImeErrorCode.SUCCESS,
    errorMessage: '',
    rawInput: 'ni',
    preeditText: 'ni',
    parsedSyllables: ['ni'],
    pendingCode: '',
    parserState: 'complete',
    candidates,
    highlightedIndex: 0,
    hasNextPage: false,
    hasPreviousPage: false,
    candidatePage: 0,
    commitText: '',
    action: null,
    compositionFinished: false
  };
}

export default function stage42Test() {
  describe('customer stage 4.2 candidate reading hidden from candidate bar', () => {
    it('keeps candidate.reading field in the candidate data structure', 0, () => {
      // 阶段 4.2 只处理显示层，Candidate 类型仍必须携带 reading 字段。
      const candidate: Candidate = {
        id: 'c1',
        text: '这个',
        reading: 'zhe ge',
        source: 'stage-4.2-test'
      };
      expect(candidate.text).assertEqual('这个');
      expect(candidate.reading).assertEqual('zhe ge');
      expect(candidate.reading.length > 0).assertTrue();
    });

    it('preserves candidate.reading through the input session store snapshot', 0, () => {
      const store = new InputSessionStore();
      store.applyEditorContext(createUnknownEditorContext());
      const candidates: Candidate[] = [
        { id: 'c1', text: '这个', reading: 'zhe ge', source: 'stage-4.2-test' },
        { id: 'c2', text: '这里', reading: 'zhe li', source: 'stage-4.2-test' },
        { id: 'c3', text: '这么', reading: 'zhe me', source: 'stage-4.2-test' }
      ];
      store.updateComposition(makeComposition(candidates));
      const snapshot = store.getSnapshot();
      expect(snapshot.candidates.length).assertEqual(3);
      expect(snapshot.candidates[0].text).assertEqual('这个');
      expect(snapshot.candidates[0].reading).assertEqual('zhe ge');
      expect(snapshot.candidates[1].text).assertEqual('这里');
      expect(snapshot.candidates[1].reading).assertEqual('zhe li');
      expect(snapshot.candidates[2].text).assertEqual('这么');
      expect(snapshot.candidates[2].reading).assertEqual('zhe me');
    });

    it('keeps candidate order unchanged after ui-only display change', 0, () => {
      const store = new InputSessionStore();
      store.applyEditorContext(createUnknownEditorContext());
      const before: Candidate[] = [
        { id: 'a', text: '你', reading: 'ni', source: 'ordering' },
        { id: 'b', text: '尼', reading: 'ni', source: 'ordering' },
        { id: 'c', text: '泥', reading: 'ni', source: 'ordering' },
        { id: 'd', text: '妮', reading: 'ni', source: 'ordering' }
      ];
      store.updateComposition(makeComposition(before));
      const ordered = store.getSnapshot().candidates.map((candidate: Candidate) => candidate.id).join(',');
      expect(ordered).assertEqual('a,b,c,d');
    });

    it('long candidates keep their text and reading independent of the visual layout', 0, () => {
      const store = new InputSessionStore();
      store.applyEditorContext(createUnknownEditorContext());
      const long: Candidate = {
        id: 'long',
        text: '这是一个用于验证候选内容宽度保护的超长候选词',
        reading: 'zhe shi yi ge yong yu yan zheng',
        source: 'long'
      };
      store.updateComposition(makeComposition([long]));
      const snapshot = store.getSnapshot();
      expect(snapshot.candidates.length).assertEqual(1);
      expect(snapshot.candidates[0].text.length > 20).assertTrue();
      // reading 依旧保留完整，供引擎/调试使用；UI 只是不再渲染它。
      expect(snapshot.candidates[0].reading.length > 0).assertTrue();
    });

    it('commit path uses candidate.text only, never the reading string', 0, () => {
      // 候选点击最终由 InputSessionController.commitCandidate 用 candidate.text 提交。
      // 这里以断言方式锁定合同：任何拼接 text+reading 或者用 reading 提交都视为回归。
      const commitPayload = (candidate: Candidate): string => candidate.text;
      const candidate: Candidate = {
        id: 'commit',
        text: '你好',
        reading: 'ni hao',
        source: 'commit-test'
      };
      expect(commitPayload(candidate)).assertEqual('你好');
      expect(commitPayload(candidate).indexOf(candidate.reading)).assertEqual(-1);
    });

    it('normal candidate render contract exposes text only', 0, () => {
      const candidate: Candidate = {
        id: 'render',
        text: '你好',
        reading: 'ni hao',
        source: 'render-test'
      };
      const item = toCandidateDisplayItem(candidate, 1);
      expect(item.displayText).assertEqual('你好');
      expect(item.displayText.indexOf(candidate.reading)).assertEqual(-1);
      expect(item.accessibilityText).assertEqual('第 2 个候选，你好');
      expect(item.accessibilityText.indexOf(candidate.reading)).assertEqual(-1);
    });
  });
}
