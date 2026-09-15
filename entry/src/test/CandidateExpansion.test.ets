import { describe, it, expect } from '@ohos/hypium';
import { resolveCollapsedCandidates, shouldShowCandidateExpansionAction, CandidateUiMode } from '../main/ets/domain/candidate/CandidateUiPolicy';
import { ImeErrorCode } from '../main/ets/common/error/ImeError';
import {
  canExpandCandidates,
  canNavigateCandidatePage,
  candidateGridColumnsTemplate,
  CandidateExpansionAvailability,
  CandidatePageDirection,
  resolveCandidateExpansionLayout
} from '../main/ets/domain/candidate/CandidateExpansionPolicy';
import { KeyboardDeviceFormFactor } from '../main/ets/domain/display/KeyboardAuxiliaryAreaPolicy';
import { createUnknownEditorContext } from '../main/ets/domain/editor/EditorContext';
import { Candidate, CompositionResult } from '../main/ets/infrastructure/native/NativeEngineTypes';
import {
  COLLAPSED_CANDIDATE_LIMIT,
  CANDIDATE_EXPANSION_ACTION,
  KEYBOARD_STATUS_BAR_LAYOUT
} from '../main/ets/presentation/candidate/CandidateBar';
import { CANDIDATE_PAGER_ACCESSIBILITY } from '../main/ets/presentation/candidate/CandidateExpansionPanel';
import {
  FLOATING_CANDIDATE_NEXT_PAGE_ACCESSIBILITY,
  FLOATING_CANDIDATE_PREVIOUS_PAGE_ACCESSIBILITY
} from '../main/ets/presentation/candidate/FloatingCandidateRoot';
import { InputSessionStore } from '../main/ets/state/InputSessionStore';

function makeCandidates(count: number, prefix: string = 'p0'): Candidate[] {
  const candidates: Candidate[] = [];
  for (let index = 0; index < count; index += 1) {
    candidates.push({
      id: `${prefix}-${index}`,
      text: `${prefix}候选${index}`,
      reading: `${prefix}-${index}`,
      source: 'candidate-expansion-test'
    });
  }
  return candidates;
}

function makeComposition(
  candidates: Candidate[],
  page: number = 0,
  hasPreviousPage: boolean = false,
  hasNextPage: boolean = false
): CompositionResult {
  return {
    success: true,
    errorCode: ImeErrorCode.SUCCESS,
    errorMessage: '',
    rawInput: 'h',
    preeditText: 'h',
    parsedSyllables: [],
    pendingCode: 'h',
    parserState: 'incomplete',
    candidates,
    highlightedIndex: -1,
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

function availability(): CandidateExpansionAvailability {
  return {
    sessionActive: true,
    keyboardVisible: true,
    candidateBarVisible: true,
    candidateCount: 50,
    hasPreviousPage: false,
    hasNextPage: true,
    pageLoading: false,
    hasError: false
  };
}

export default function candidateExpansionTest() {
  describe('candidate improvement stage 2 expansion and paging', () => {
    it('allows nonempty expansion for configurable collapsed limits', 0, () => {
      const store = readyStore();
      expect(store.setCandidatePanelExpanded(true)).assertFalse();
      store.updateComposition(makeComposition(makeCandidates(2)));
      expect(store.setCandidatePanelExpanded(true)).assertTrue();
      store.updateComposition(makeComposition(makeCandidates(3)));
      expect(store.setCandidatePanelExpanded(true)).assertTrue();
      store.setCandidatePanelExpanded(false);
      store.updateComposition(makeComposition(makeCandidates(50), 0, false, true));
      expect(store.setCandidatePanelExpanded(true)).assertTrue();
      expect(store.getSnapshot().candidatePanelExpanded).assertTrue();
      expect(store.setCandidatePanelExpanded(false)).assertFalse();
      expect(store.getSnapshot().candidatePanelExpanded).assertFalse();
    });

    it('caps collapsed candidates and exposes count, page and width overflow', 0, () => {
      const candidates = makeCandidates(8);
      expect(resolveCollapsedCandidates(candidates, 5).length).assertEqual(5);
      expect(resolveCollapsedCandidates(candidates, 1)[0].id).assertEqual(candidates[0].id);
      expect(candidates.length).assertEqual(8);
      expect(shouldShowCandidateExpansionAction(CandidateUiMode.BROWSABLE, 5)).assertFalse();
      expect(shouldShowCandidateExpansionAction(CandidateUiMode.BROWSABLE, 6)).assertTrue();
      expect(shouldShowCandidateExpansionAction(CandidateUiMode.PRECISE_MATCH, 2, 'obh', 1)).assertTrue();
      expect(shouldShowCandidateExpansionAction(CandidateUiMode.BROWSABLE, 5, 'ni', 5, true)).assertTrue();
      expect(shouldShowCandidateExpansionAction(CandidateUiMode.BROWSABLE, 3, 'ni', 5, false, true)).assertTrue();
      expect(shouldShowCandidateExpansionAction(CandidateUiMode.BROWSABLE, 0, '', 5, true)).assertFalse();
    });

    it('expands a standalone floating window and keeps paging but resets for a new code', 0, () => {
      const store = readyStore();
      store.markKeyboardHidden();
      store.updateComposition(makeComposition(makeCandidates(8)));
      expect(store.setFloatingCandidateExpanded(true)).assertTrue();
      expect(store.getSnapshot().candidatePanelExpanded).assertFalse();
      store.updateComposition(makeComposition(makeCandidates(2), 1, true));
      expect(store.getSnapshot().floatingCandidateExpanded).assertTrue();
      const next = makeComposition(makeCandidates(8));
      next.rawInput = 'ha';
      store.updateComposition(next);
      expect(store.getSnapshot().floatingCandidateExpanded).assertFalse();
      store.setFloatingCandidateExpanded(true);
      store.clearComposition();
      expect(store.getSnapshot().floatingCandidateExpanded).assertFalse();
    });

    it('keeps expansion through a non-empty refresh and closes on empty candidates', 0, () => {
      const store = readyStore();
      store.updateComposition(makeComposition(makeCandidates(50), 0, false, true));
      store.setCandidatePanelExpanded(true);
      store.updateComposition(makeComposition(makeCandidates(14, 'refresh'), 1, true, false));
      expect(store.getSnapshot().candidatePanelExpanded).assertTrue();
      expect(store.getSnapshot().candidatePage).assertEqual(1);
      expect(store.getSnapshot().candidates[0].id).assertEqual('refresh-0');
      store.updateComposition(makeComposition([]));
      expect(store.getSnapshot().candidatePanelExpanded).assertFalse();
      expect(store.getSnapshot().candidatePage).assertEqual(0);
    });

    it('clears expanded and loading state for hide editor switch mode switch and error', 0, () => {
      const store = readyStore();
      store.updateComposition(makeComposition(makeCandidates(50), 0, false, true));
      store.setCandidatePanelExpanded(true);
      store.setCandidatePageLoading(true);
      store.markKeyboardHidden();
      expect(store.getSnapshot().candidatePanelExpanded).assertFalse();
      expect(store.getSnapshot().candidatePageLoading).assertFalse();

      store.markKeyboardVisible();
      store.updateComposition(makeComposition(makeCandidates(50), 0, false, true));
      store.setCandidatePanelExpanded(true);
      store.applyEditorContext(createUnknownEditorContext());
      expect(store.getSnapshot().candidatePanelExpanded).assertFalse();
      expect(store.getSnapshot().candidatePage).assertEqual(0);

      store.updateComposition(makeComposition(makeCandidates(50), 0, false, true));
      store.setCandidatePanelExpanded(true);
      store.toggleKeyboardMode();
      expect(store.getSnapshot().candidatePanelExpanded).assertFalse();
      expect(store.getSnapshot().candidatePage).assertEqual(0);

      store.updateComposition(makeComposition(makeCandidates(50), 0, false, true));
      store.setCandidatePanelExpanded(true);
      store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'page failed');
      const failed = store.getSnapshot();
      expect(failed.candidatePanelExpanded).assertFalse();
      expect(failed.candidates.length).assertEqual(50);
    });

    it('blocks unavailable and repeated page navigation', 0, () => {
      const first = availability();
      expect(canExpandCandidates(first)).assertTrue();
      expect(canNavigateCandidatePage(first, CandidatePageDirection.PREVIOUS)).assertFalse();
      expect(canNavigateCandidatePage(first, CandidatePageDirection.NEXT)).assertTrue();

      const loading: CandidateExpansionAvailability = {
        sessionActive: first.sessionActive,
        keyboardVisible: first.keyboardVisible,
        candidateBarVisible: first.candidateBarVisible,
        candidateCount: first.candidateCount,
        hasPreviousPage: first.hasPreviousPage,
        hasNextPage: first.hasNextPage,
        pageLoading: true,
        hasError: first.hasError
      };
      expect(canNavigateCandidatePage(loading, CandidatePageDirection.NEXT)).assertFalse();

      const last: CandidateExpansionAvailability = {
        sessionActive: first.sessionActive,
        keyboardVisible: first.keyboardVisible,
        candidateBarVisible: first.candidateBarVisible,
        candidateCount: first.candidateCount,
        hasPreviousPage: true,
        hasNextPage: false,
        pageLoading: false,
        hasError: first.hasError
      };
      expect(canNavigateCandidatePage(last, CandidatePageDirection.PREVIOUS)).assertTrue();
      expect(canNavigateCandidatePage(last, CandidatePageDirection.NEXT)).assertFalse();

      const shortPage: CandidateExpansionAvailability = {
        sessionActive: first.sessionActive,
        keyboardVisible: first.keyboardVisible,
        candidateBarVisible: first.candidateBarVisible,
        candidateCount: 7,
        hasPreviousPage: false,
        hasNextPage: false,
        pageLoading: false,
        hasError: first.hasError
      };
      expect(canExpandCandidates(shortPage)).assertTrue();
      expect(canNavigateCandidatePage(shortPage, CandidatePageDirection.PREVIOUS)).assertFalse();
      expect(canNavigateCandidatePage(shortPage, CandidatePageDirection.NEXT)).assertFalse();

      const tooShort: CandidateExpansionAvailability = {
        sessionActive: first.sessionActive,
        keyboardVisible: first.keyboardVisible,
        candidateBarVisible: first.candidateBarVisible,
        candidateCount: 0,
        hasPreviousPage: false,
        hasNextPage: false,
        pageLoading: false,
        hasError: false
      };
      expect(canExpandCandidates(tooShort)).assertFalse();

      const shortFinalPage: CandidateExpansionAvailability = {
        sessionActive: first.sessionActive,
        keyboardVisible: first.keyboardVisible,
        candidateBarVisible: first.candidateBarVisible,
        candidateCount: 1,
        hasPreviousPage: true,
        hasNextPage: false,
        pageLoading: false,
        hasError: false
      };
      expect(canNavigateCandidatePage(shortFinalPage, CandidatePageDirection.PREVIOUS)).assertTrue();
    });

    it('uses a four-column full-keyboard phone grid and a 50-cell pad grid', 0, () => {
      const portrait = resolveCandidateExpansionLayout(KeyboardDeviceFormFactor.PHONE, false);
      const landscape = resolveCandidateExpansionLayout(KeyboardDeviceFormFactor.PHONE, true);
      const pad = resolveCandidateExpansionLayout(KeyboardDeviceFormFactor.TABLET, false);
      expect(portrait.columnCount).assertEqual(4);
      expect(portrait.visibleRowCount).assertEqual(5);
      expect(landscape.columnCount).assertEqual(8);
      expect(pad.columnCount * pad.visibleRowCount >= 30).assertTrue();
      expect(pad.columnCount * pad.visibleRowCount).assertEqual(50);
      expect(candidateGridColumnsTemplate(3)).assertEqual('1fr 1fr 1fr');
    });

    it('keeps expansion paging and keyboard hide accessibility labels distinct', 0, () => {
      expect(COLLAPSED_CANDIDATE_LIMIT).assertEqual(5);
      expect(CANDIDATE_EXPANSION_ACTION.expandAccessibilityText).assertEqual('展开候选');
      expect(CANDIDATE_EXPANSION_ACTION.collapseAccessibilityText).assertEqual('收起候选');
      expect(KEYBOARD_STATUS_BAR_LAYOUT.actionAccessibilityText).assertEqual('收起键盘');
      expect(CANDIDATE_PAGER_ACCESSIBILITY.previous).assertEqual('上一页候选');
      expect(CANDIDATE_PAGER_ACCESSIBILITY.next).assertEqual('下一页候选');
      expect(CANDIDATE_PAGER_ACCESSIBILITY.back).assertEqual('返回键盘');
      expect(FLOATING_CANDIDATE_PREVIOUS_PAGE_ACCESSIBILITY).assertEqual('浮动候选上一页');
      expect(FLOATING_CANDIDATE_NEXT_PAGE_ACCESSIBILITY).assertEqual('浮动候选下一页');
      expect(CANDIDATE_EXPANSION_ACTION.actionId === KEYBOARD_STATUS_BAR_LAYOUT.actionId).assertFalse();
    });
  });
}
