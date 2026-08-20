import { describe, expect, it } from '@ohos/hypium';
import { ImeErrorCode } from '../main/ets/common/error/ImeError';
import { createUnknownEditorContext } from '../main/ets/domain/editor/EditorContext';
import {
  Candidate,
  CompositionResult,
  ParserState
} from '../main/ets/infrastructure/native/NativeEngineTypes';
import { InputSessionStore } from '../main/ets/state/InputSessionStore';
import { resolveCandidateSourceIndex } from '../main/ets/domain/candidate/CandidateUiPolicy';

function candidate(id: string, text: string, reading: string): Candidate {
  return {
    id,
    text,
    reading,
    source: 'candidate-stage4-contract'
  };
}

function result(
  rawInput: string,
  parserState: ParserState,
  candidates: Candidate[],
  page: number = 0,
  hasPreviousPage: boolean = false,
  hasNextPage: boolean = false
): CompositionResult {
  return {
    success: true,
    errorCode: ImeErrorCode.SUCCESS,
    errorMessage: '',
    rawInput,
    preeditText: rawInput,
    parsedSyllables: [],
    pendingCode: parserState === 'incomplete' ? rawInput.slice(-1) : '',
    parserState,
    candidates,
    highlightedIndex: candidates.length > 0 ? 0 : -1,
    hasNextPage,
    hasPreviousPage,
    candidatePage: page,
    commitText: '',
    action: null,
    compositionFinished: false
  };
}

function readyStore(): InputSessionStore {
  const store = new InputSessionStore();
  store.markSessionStarted();
  store.applyEditorContext(createUnknownEditorContext());
  store.markKeyboardVisible();
  return store;
}

export default function candidateStage4ContractTest() {
  describe('candidate improvement stage 4 UI state boundary', () => {
    it('resolves copied render candidates by stable id instead of object identity', 0, () => {
      const candidates = [
        candidate('first', '今天', 'jin tian'),
        candidate('second', '天气', 'tian qi'),
        candidate('third', '怎么样', 'zen me yang')
      ];
      const copiedSecond = candidate('second', '天气', 'tian qi');

      expect(candidates.indexOf(copiedSecond)).assertEqual(-1);
      expect(resolveCandidateSourceIndex(candidates, copiedSecond)).assertEqual(1);
      expect(resolveCandidateSourceIndex(
        candidates,
        candidate('stale', '旧候选', 'jiu hou xuan')
      )).assertEqual(-1);
    });

    it('renders the engine snapshot without inferring single-key final meanings', 0, () => {
      const store = readyStore();
      store.updateComposition(result('h', 'incomplete', [
        candidate('he', '和', 'he'),
        candidate('hao', '好', 'hao')
      ]));

      const snapshot = store.getSnapshot();
      expect(snapshot.rawInput).assertEqual('h');
      expect(snapshot.parserState).assertEqual('incomplete');
      expect(snapshot.candidates.length).assertEqual(2);
      expect(snapshot.candidates[0].reading).assertEqual('he');
      expect(snapshot.candidates[1].reading).assertEqual('hao');
    });

    it('atomically replaces mode candidates and pagination while deleting to empty', 0, () => {
      const store = readyStore();
      store.updateComposition(result('nihc', 'complete', [
        candidate('ni-hao', '你好', 'ni hao')
      ], 1, true, true));

      store.updateComposition(result('nih', 'incomplete', [
        candidate('ni-hao-prefix', '你好', 'ni hao')
      ]));
      let snapshot = store.getSnapshot();
      expect(snapshot.rawInput).assertEqual('nih');
      expect(snapshot.candidatePage).assertEqual(0);
      expect(snapshot.hasPreviousPage).assertFalse();
      expect(snapshot.hasNextPage).assertFalse();
      expect(snapshot.candidates[0].id).assertEqual('ni-hao-prefix');

      store.updateComposition(result('ni', 'complete', [
        candidate('ni', '你', 'ni')
      ]));
      snapshot = store.getSnapshot();
      expect(snapshot.rawInput).assertEqual('ni');
      expect(snapshot.parserState).assertEqual('complete');
      expect(snapshot.candidates[0].reading).assertEqual('ni');

      store.updateComposition(result('n', 'incomplete', [
        candidate('ni-prefix', '你', 'ni')
      ]));
      snapshot = store.getSnapshot();
      expect(snapshot.rawInput).assertEqual('n');
      expect(snapshot.parserState).assertEqual('incomplete');

      store.updateComposition(result('', 'empty', []));
      snapshot = store.getSnapshot();
      expect(snapshot.rawInput).assertEqual('');
      expect(snapshot.parserState).assertEqual('empty');
      expect(snapshot.candidates.length).assertEqual(0);
      expect(snapshot.candidatePage).assertEqual(0);
      expect(snapshot.hasPreviousPage).assertFalse();
      expect(snapshot.hasNextPage).assertFalse();
    });
  });
}
