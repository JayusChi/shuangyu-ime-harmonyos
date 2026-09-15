import { describe, expect, it } from '@ohos/hypium';
import { ImeErrorCode } from '../main/ets/common/error/ImeError';
import { KeyboardController } from '../main/ets/application/KeyboardController';
import { InputOperationResult, inputOperationOk } from '../main/ets/application/InputOperationResult';
import { InputSessionController } from '../main/ets/application/InputSessionController';
import { createUnknownEditorContext } from '../main/ets/domain/editor/EditorContext';
import { KeyboardMode } from '../main/ets/domain/keyboard/KeyboardAction';
import { resolveSymbolGuide } from '../main/ets/domain/keyboard/SymbolGuideMap';
import {
  PhysicalKeyCommandType,
  PhysicalKeyConsumptionTracker,
  PhysicalEditorSuffixTracker,
  PhysicalShiftLanguageToggleTracker,
  PhysicalKeySnapshot,
  PhysicalKeyStartupDeferral,
  PhysicalKeySessionSnapshot,
  resolveUnmodifiedPhysicalLetter,
  resolvePhysicalKeyCommand
} from '../main/ets/domain/keyboard/PhysicalKeyboardRouting';
import { Candidate, CompositionResult } from '../main/ets/infrastructure/native/NativeEngineTypes';
import { InputSessionStore } from '../main/ets/state/InputSessionStore';

function key(
  keyCode: number,
  unicodeChar: number = 0,
  isDown: boolean = true,
  ctrlKey: boolean = false,
  altKey: boolean = false,
  logoKey: boolean = false
): PhysicalKeySnapshot {
  return { isDown, unicodeChar, keyCode, ctrlKey, altKey, logoKey };
}

function session(rawInput: string = 'ni', compositionPending: boolean = false): PhysicalKeySessionSnapshot {
  return {
    sessionActive: true,
    editorConnected: true,
    candidateBarVisible: true,
    keyboardMode: KeyboardMode.CHINESE,
    rawInput,
    candidateCount: 3,
    compositionPending
  };
}

function composition(
  highlightedIndex: number = 0,
  hasNextPage: boolean = true,
  hasPreviousPage: boolean = false
): CompositionResult {
  const candidates: Candidate[] = [
    { id: '1', text: '你', reading: 'ni', source: 'stage3' },
    { id: '2', text: '拟', reading: 'ni', source: 'stage3' },
    { id: '3', text: '尼', reading: 'ni', source: 'stage3' }
  ];
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
    highlightedIndex,
    hasNextPage,
    hasPreviousPage,
    candidatePage: hasPreviousPage ? 1 : 0,
    commitText: '',
    action: null,
    compositionFinished: false
  };
}

class Stage3SessionController extends InputSessionController {
  readonly stage3Store: InputSessionStore;
  committedIndices: number[] = [];
  cancelCount: number = 0;
  nextPageCount: number = 0;
  previousPageCount: number = 0;
  physicalLetters: string[] = [];
  physicalContinuationFlags: boolean[] = [];
  insertedCharacters: string[] = [];
  pairJumpCount: number = 0;
  pairAvailable: boolean = false;
  createPairOnCommit: boolean = false;

  constructor(store: InputSessionStore) {
    super(store);
    this.stage3Store = store;
  }

  async insertLetter(
    letter: string | undefined,
    _generation: number = this.getInputSessionGeneration(),
    serializedPhysicalContinuation: boolean = false
  ): Promise<InputOperationResult> {
    this.physicalLetters.push(letter ?? '');
    this.physicalContinuationFlags.push(serializedPhysicalContinuation);
    return inputOperationOk();
  }

  async commitCandidate(
    candidateIndex: number,
    _generation: number = this.getInputSessionGeneration()
  ): Promise<InputOperationResult> {
    this.committedIndices.push(candidateIndex);
    this.stage3Store.clearComposition();
    this.pairAvailable = this.createPairOnCommit;
    return inputOperationOk();
  }

  async insertCharacter(
    character: string | undefined,
    _generation: number = this.getInputSessionGeneration()
  ): Promise<InputOperationResult> {
    this.insertedCharacters.push(character ?? '');
    return inputOperationOk();
  }

  async cancelComposition(
    _generation: number = this.getInputSessionGeneration()
  ): Promise<InputOperationResult> {
    this.cancelCount += 1;
    this.stage3Store.clearComposition();
    return inputOperationOk();
  }

  async nextCandidatePage(
    _generation: number = this.getInputSessionGeneration()
  ): Promise<InputOperationResult> {
    this.nextPageCount += 1;
    this.stage3Store.updateComposition(composition(0, false, true));
    return inputOperationOk();
  }

  async previousCandidatePage(
    _generation: number = this.getInputSessionGeneration()
  ): Promise<InputOperationResult> {
    this.previousPageCount += 1;
    this.stage3Store.updateComposition(composition(0, true, false));
    return inputOperationOk();
  }

  canJumpOutPair(_generation: number = this.getInputSessionGeneration()): boolean {
    return this.pairAvailable;
  }

  async jumpOutPair(
    _generation: number = this.getInputSessionGeneration()
  ): Promise<InputOperationResult> {
    this.pairJumpCount += 1;
    return inputOperationOk();
  }
}

interface ControllerFixture {
  store: InputSessionStore;
  sessionController: Stage3SessionController;
  controller: KeyboardController;
}

function createControllerFixture(): ControllerFixture {
  const store = new InputSessionStore();
  store.markSessionStarted();
  store.applyEditorContext(createUnknownEditorContext());
  store.updateComposition(composition());
  const sessionController = new Stage3SessionController(store);
  const controller = new KeyboardController(sessionController);
  return { store, sessionController, controller };
}

export default function computerStage3PhysicalKeyboardTest() {
  describe('computer remediation stage 3 physical keyboard', () => {
    it('routes physical backticks as universal code keys only for enabled Chinese sessions', 0, () => {
      const active = session('u');
      active.universalKeyEnabled = true;
      for (const raw of ['', 'u', 'u`', 'abcd']) {
        active.rawInput = raw;
        for (const unicode of [0, 96]) {
          expect(resolvePhysicalKeyCommand(key(2056, unicode), active).type)
            .assertEqual(PhysicalKeyCommandType.UNIVERSAL);
        }
      }
      active.rawInput = '';
      active.compositionPending = true;
      expect(resolvePhysicalKeyCommand(key(2056), active).type).assertEqual(PhysicalKeyCommandType.UNIVERSAL);
      active.rawInput = 'u';
      const shifted = key(2056);
      shifted.shiftKey = true;
      expect(resolvePhysicalKeyCommand(shifted, active).character).assertEqual('~');
      expect(resolvePhysicalKeyCommand(key(2056, 126), active).type).assertEqual(PhysicalKeyCommandType.PUNCTUATION);
      expect(resolvePhysicalKeyCommand(key(2056, 96, false), active).type).assertEqual(PhysicalKeyCommandType.NONE);
      expect(resolvePhysicalKeyCommand(key(2056, 96, true, true), active).type).assertEqual(PhysicalKeyCommandType.NONE);
      expect(resolvePhysicalKeyCommand(key(2056, 96, true, false, true), active).type).assertEqual(PhysicalKeyCommandType.NONE);
      expect(resolvePhysicalKeyCommand(key(2056, 96, true, false, false, true), active).type).assertEqual(PhysicalKeyCommandType.NONE);
      active.rawInput = "'1+2";
      expect(resolvePhysicalKeyCommand(key(2056), active).type).assertEqual(PhysicalKeyCommandType.PUNCTUATION);
      active.rawInput = 'u';
      active.universalKeyEnabled = false;
      expect(resolvePhysicalKeyCommand(key(2056), active).type).assertEqual(PhysicalKeyCommandType.PUNCTUATION);
      active.universalKeyEnabled = true;
      active.keyboardMode = KeyboardMode.ENGLISH;
      expect(resolvePhysicalKeyCommand(key(2056), active).type).assertEqual(PhysicalKeyCommandType.NONE);
      active.keyboardMode = KeyboardMode.CHINESE;
      active.chineseInputAllowed = false;
      expect(resolvePhysicalKeyCommand(key(2056), active).type).assertEqual(PhysicalKeyCommandType.NONE);
      active.chineseInputAllowed = true;
      active.editorConnected = false;
      expect(resolvePhysicalKeyCommand(key(2056), active).type).assertEqual(PhysicalKeyCommandType.NONE);
    });

    it('letters and the apostrophe guide begin composition while idle', 0, () => {
      expect(resolvePhysicalKeyCommand(key(2030), session('')).type)
        .assertEqual(PhysicalKeyCommandType.LETTER);
      const returnedKeyCodes: number[] = [
        2002, 2050, 2054, 2043, 2044, 2059, 2060, 2068, 2069, 2070, 2012, 2015
      ];
      returnedKeyCodes.forEach((keyCode: number): void => {
        expect(resolvePhysicalKeyCommand(key(keyCode), session('')).type)
          .assertEqual(PhysicalKeyCommandType.NONE);
      });
      // Backspace remains owned by the IME while the Chinese hardware session
      // is active so committed editor text can still be deleted without a
      // fixed software keyboard panel.
      expect(resolvePhysicalKeyCommand(key(2055), session('')).type)
        .assertEqual(PhysicalKeyCommandType.DELETE);
    });

    it('convenience owns digits operators case and a guide that is still queued', 0, () => {
      const pending = session('', true);
      pending.conveniencePendingRaw = "'";
      for (const code of [2000, 2001, 2010, 2066, 2103, 2113, 2114, 2115, 2116, 2117, 2063]) {
        expect(resolvePhysicalKeyCommand(key(code), pending).type).assertEqual(PhysicalKeyCommandType.CONVENIENCE);
      }
      expect(resolvePhysicalKeyCommand(key(2017, 65), session("'Ab")).character).assertEqual('A');
      expect(resolvePhysicalKeyCommand(key(2005), session("'2026.")).character).assertEqual('5');
      expect(resolvePhysicalKeyCommand(key(2050), pending).type).assertEqual(PhysicalKeyCommandType.SPACE);
      expect(resolvePhysicalKeyCommand(key(2070), pending).type).assertEqual(PhysicalKeyCommandType.CANCEL);
      const shiftedPlus = key(2058);
      shiftedPlus.shiftKey = true;
      expect(resolvePhysicalKeyCommand(shiftedPlus, pending).character).assertEqual('+');
      shiftedPlus.keyCode = 2008;
      expect(resolvePhysicalKeyCommand(shiftedPlus, pending).character).assertEqual('*');
      pending.chineseInputAllowed = false;
      expect(resolvePhysicalKeyCommand(key(2001), pending).type).assertEqual(PhysicalKeyCommandType.NONE);
    });

    it('routes edit, cancel, selection and page commands only during composition', 0, () => {
      expect(resolvePhysicalKeyCommand(key(2055), session()).type).assertEqual(PhysicalKeyCommandType.DELETE);
      expect(resolvePhysicalKeyCommand(key(2050), session()).type).assertEqual(PhysicalKeyCommandType.SPACE);
      expect(resolvePhysicalKeyCommand(key(2054), session()).type).assertEqual(PhysicalKeyCommandType.ENTER);
      // Apostrophe selects the third candidate when it exists.
      expect(resolvePhysicalKeyCommand(key(2063), session()).type)
        .assertEqual(PhysicalKeyCommandType.THIRD_CANDIDATE);
      expect(resolvePhysicalKeyCommand(key(2070), session()).type).assertEqual(PhysicalKeyCommandType.CANCEL);
      expect(resolvePhysicalKeyCommand(key(2014), session()).type)
        .assertEqual(PhysicalKeyCommandType.SELECT_PREVIOUS);
      expect(resolvePhysicalKeyCommand(key(2012), session()).type)
        .assertEqual(PhysicalKeyCommandType.SELECT_PREVIOUS);
      expect(resolvePhysicalKeyCommand(key(2015), session()).type)
        .assertEqual(PhysicalKeyCommandType.SELECT_NEXT);
      expect(resolvePhysicalKeyCommand(key(2013), session()).type)
        .assertEqual(PhysicalKeyCommandType.SELECT_NEXT);
      expect(resolvePhysicalKeyCommand(key(2068), session()).type)
        .assertEqual(PhysicalKeyCommandType.PREVIOUS_PAGE);
      expect(resolvePhysicalKeyCommand(key(2069), session()).type)
        .assertEqual(PhysicalKeyCommandType.NEXT_PAGE);
      expect(resolvePhysicalKeyCommand(key(2059), session()).type)
        .assertEqual(PhysicalKeyCommandType.PREVIOUS_PAGE);
      expect(resolvePhysicalKeyCommand(key(2060), session()).type)
        .assertEqual(PhysicalKeyCommandType.NEXT_PAGE);
      expect(resolvePhysicalKeyCommand(key(2059, 91), session()).type)
        .assertEqual(PhysicalKeyCommandType.PREVIOUS_PAGE);
      expect(resolvePhysicalKeyCommand(key(2060, 93), session()).type)
        .assertEqual(PhysicalKeyCommandType.NEXT_PAGE);
    });

    it('pages with unmodified brackets while preserving Shift braces and host shortcuts', 0, () => {
      for (const code of [2059, 2060]) {
        const bracket = code === 2059 ? '[' : ']';
        const brace = code === 2059 ? '{' : '}';
        const page = code === 2059 ? PhysicalKeyCommandType.PREVIOUS_PAGE : PhysicalKeyCommandType.NEXT_PAGE;
        for (const unicode of [0, bracket.charCodeAt(0)]) {
          expect(resolvePhysicalKeyCommand(key(code, unicode), session()).type).assertEqual(page);
          expect(resolvePhysicalKeyCommand(key(code, unicode), session('', true)).type).assertEqual(page);
          expect(resolvePhysicalKeyCommand(key(code, unicode), session('')).type).assertEqual(PhysicalKeyCommandType.NONE);
          expect(resolvePhysicalKeyCommand(key(code, unicode, false), session()).type).assertEqual(PhysicalKeyCommandType.NONE);
          expect(resolvePhysicalKeyCommand(key(code, unicode, true, true), session()).type).assertEqual(PhysicalKeyCommandType.NONE);
          expect(resolvePhysicalKeyCommand(key(code, unicode, true, false, true), session()).type).assertEqual(PhysicalKeyCommandType.NONE);
          expect(resolvePhysicalKeyCommand(key(code, unicode, true, false, false, true), session()).type).assertEqual(PhysicalKeyCommandType.NONE);
        }
        for (const unicode of [0, brace.charCodeAt(0)]) {
          const shifted = key(code, unicode);
          shifted.shiftKey = true;
          const result = resolvePhysicalKeyCommand(shifted, session());
          expect(result.type).assertEqual(PhysicalKeyCommandType.PUNCTUATION);
          expect(result.character).assertEqual(brace);
        }
        const english = session();
        english.keyboardMode = KeyboardMode.ENGLISH;
        expect(resolvePhysicalKeyCommand(key(code), english).type).assertEqual(PhysicalKeyCommandType.NONE);
        const restricted = session();
        restricted.chineseInputAllowed = false;
        expect(resolvePhysicalKeyCommand(key(code), restricted).type).assertEqual(PhysicalKeyCommandType.NONE);
      }
    });

    it('routes Tab and Enter with composition then pair-jump priority', 0, () => {
      expect(resolvePhysicalKeyCommand(key(2049), session()).type)
        .assertEqual(PhysicalKeyCommandType.TAB);

      const pair = session('');
      pair.candidateCount = 0;
      pair.pairJumpAvailable = true;
      expect(resolvePhysicalKeyCommand(key(2049), pair).type)
        .assertEqual(PhysicalKeyCommandType.JUMP_OUT_PAIR);
      expect(resolvePhysicalKeyCommand(key(2054), pair).type)
        .assertEqual(PhysicalKeyCommandType.JUMP_OUT_PAIR);

      pair.pairJumpAvailable = false;
      expect(resolvePhysicalKeyCommand(key(2049), pair).type)
        .assertEqual(PhysicalKeyCommandType.NONE);
      expect(resolvePhysicalKeyCommand(key(2054), pair).type)
        .assertEqual(PhysicalKeyCommandType.NONE);
    });

    it('falls back to standard and numpad keyCode when unicodeChar is absent', 0, () => {
      expect(resolvePhysicalKeyCommand(key(2030), session('')).letter).assertEqual('n');
      const topDigit = resolvePhysicalKeyCommand(key(2002), session());
      expect(topDigit.type).assertEqual(PhysicalKeyCommandType.CANDIDATE);
      expect(topDigit.candidateIndex).assertEqual(1);
      const numpadDigit = resolvePhysicalKeyCommand(key(2105), session());
      expect(numpadDigit.type).assertEqual(PhysicalKeyCommandType.CANDIDATE);
      expect(numpadDigit.candidateIndex).assertEqual(1);
    });

    it('routes common punctuation as an editor suffix without closing composition', 0, () => {
      const byUnicode = resolvePhysicalKeyCommand(key(2043, 44), session('a'));
      expect(byUnicode.type).assertEqual(PhysicalKeyCommandType.PUNCTUATION);
      expect(byUnicode.character).assertEqual('，');

      const byKeyCode = resolvePhysicalKeyCommand(key(2043), session('a'));
      expect(byKeyCode.type).assertEqual(PhysicalKeyCommandType.PUNCTUATION);
      expect(byKeyCode.character).assertEqual('，');
      expect(resolvePhysicalKeyCommand(key(2044), session('a')).character).assertEqual('。');
      expect(resolvePhysicalKeyCommand(key(2062, 58), session('a')).character).assertEqual('：');
      expect(resolvePhysicalKeyCommand(key(2043), session('')).type)
        .assertEqual(PhysicalKeyCommandType.NONE);

      const smartPeriodContinuation = session('');
      smartPeriodContinuation.smartPunctuationContinuation = '.';
      const secondPeriod = resolvePhysicalKeyCommand(key(2044), smartPeriodContinuation);
      expect(secondPeriod.type).assertEqual(PhysicalKeyCommandType.PUNCTUATION);
      expect(secondPeriod.character).assertEqual('。');
      expect(resolvePhysicalKeyCommand(key(2043), smartPeriodContinuation).type)
        .assertEqual(PhysicalKeyCommandType.NONE);

      const smartCommaContinuation = session('');
      smartCommaContinuation.smartPunctuationContinuation = ',';
      const secondComma = resolvePhysicalKeyCommand(key(2043), smartCommaContinuation);
      expect(secondComma.type).assertEqual(PhysicalKeyCommandType.PUNCTUATION);
      expect(secondComma.character).assertEqual('，');
    });

    it('consumes dependent controls while earlier rapid input is still queued', 0, () => {
      const pending = session('', true);
      expect(resolvePhysicalKeyCommand(key(2050), pending).type).assertEqual(PhysicalKeyCommandType.SPACE);
      expect(resolvePhysicalKeyCommand(key(2002), pending).type).assertEqual(PhysicalKeyCommandType.CANDIDATE);
      expect(resolvePhysicalKeyCommand(key(2070), pending).type).assertEqual(PhysicalKeyCommandType.CANCEL);
    });

    it('keeps owning Chinese letters while candidate UI is temporarily hidden', 0, () => {
      const hiddenPanel = session('', true);
      hiddenPanel.candidateBarVisible = false;
      hiddenPanel.chineseInputAllowed = true;
      const randomLetterKeys = [2017, 2022, 2030, 2035, 2042];
      randomLetterKeys.forEach((keyCode: number): void => {
        expect(resolvePhysicalKeyCommand(key(keyCode), hiddenPanel).type)
          .assertEqual(PhysicalKeyCommandType.LETTER);
      });
    });

    it('returns key-up and all Ctrl Alt Logo shortcuts to the routing boundary', 0, () => {
      expect(resolvePhysicalKeyCommand(key(2030, 0, false), session()).type)
        .assertEqual(PhysicalKeyCommandType.NONE);
      expect(resolvePhysicalKeyCommand(key(2030, 0, true, true), session()).type)
        .assertEqual(PhysicalKeyCommandType.NONE);
      expect(resolvePhysicalKeyCommand(key(2050, 0, true, false, true), session()).type)
        .assertEqual(PhysicalKeyCommandType.NONE);
      expect(resolvePhysicalKeyCommand(key(2054, 0, true, false, false, true), session()).type)
        .assertEqual(PhysicalKeyCommandType.NONE);
    });

    it('pairs a consumed DOWN with exactly one UP and tolerates repeated DOWN', 0, () => {
      const tracker = new PhysicalKeyConsumptionTracker();
      tracker.recordConsumedDown(2030);
      tracker.recordConsumedDown(2030);
      expect(tracker.consumeRelease(2030)).assertTrue();
      expect(tracker.consumeRelease(2030)).assertFalse();
      tracker.recordConsumedDown(2031);
      tracker.reset();
      expect(tracker.consumeRelease(2031)).assertFalse();
    });

    it('toggles language only for a standalone left or right Shift tap', 0, () => {
      const tracker = new PhysicalShiftLanguageToggleTracker();
      expect(tracker.observe(key(2047))).assertFalse();
      expect(tracker.observe(key(2047, 0, false))).assertTrue();
      expect(tracker.observe(key(2048))).assertFalse();
      expect(tracker.observe(key(2048, 0, false))).assertTrue();
    });

    it('keeps Shift combinations and incomplete presses out of language toggling', 0, () => {
      const tracker = new PhysicalShiftLanguageToggleTracker();
      expect(tracker.observe(key(2047))).assertFalse();
      const shiftedLetter = key(2017);
      shiftedLetter.shiftKey = true;
      expect(tracker.observe(shiftedLetter)).assertFalse();
      expect(tracker.observe(key(2047, 0, false))).assertFalse();

      expect(tracker.observe(key(2048))).assertFalse();
      tracker.reset();
      expect(tracker.observe(key(2048, 0, false))).assertFalse();

      expect(tracker.observe(key(2047, 0, true, true))).assertFalse();
      expect(tracker.observe(key(2047, 0, false, true))).assertFalse();
    });

    it('defers a cold-start letter DOWN and UP pair without claiming other host keys', 0, () => {
      const deferral = new PhysicalKeyStartupDeferral();
      expect(deferral.shouldDefer(key(2030))).assertTrue();
      expect(deferral.shouldDefer(key(2030, 0, false))).assertTrue();
      expect(deferral.shouldDefer(key(2030, 0, false))).assertFalse();
      expect(deferral.shouldDefer(key(2002))).assertFalse();
      expect(deferral.shouldDefer(key(2030, 0, true, true))).assertFalse();
      expect(deferral.shouldDefer(key(2031))).assertTrue();
      deferral.reset();
      expect(deferral.shouldDefer(key(2031, 0, false))).assertFalse();
    });

    it('preserves the literal letter for a deferred English or password fallback', 0, () => {
      expect(resolveUnmodifiedPhysicalLetter(key(2030, 78))).assertEqual('N');
      const shiftedFallback = key(2030);
      shiftedFallback.shiftKey = true;
      expect(resolveUnmodifiedPhysicalLetter(shiftedFallback)).assertEqual('N');
      expect(resolveUnmodifiedPhysicalLetter(key(2030, 0, true, true))).assertUndefined();
    });

    it('deletes appended punctuation before handing Backspace to composition', 0, () => {
      const tracker = new PhysicalEditorSuffixTracker();
      expect(tracker.consumePunctuationDelete()).assertFalse();
      tracker.recordPunctuation();
      tracker.recordPunctuation();
      expect(tracker.consumePunctuationDelete()).assertTrue();
      expect(tracker.consumePunctuationDelete()).assertTrue();
      expect(tracker.consumePunctuationDelete()).assertFalse();
      tracker.recordPunctuation();
      tracker.reset();
      expect(tracker.consumePunctuationDelete()).assertFalse();
    });

    it('clamps repeated direction navigation to the current candidate page', 0, () => {
      const fixture = createControllerFixture();
      fixture.store.moveCandidateHighlight(-1);
      expect(fixture.store.getSnapshot().highlightedIndex).assertEqual(0);
      fixture.store.moveCandidateHighlight(1);
      fixture.store.moveCandidateHighlight(1);
      fixture.store.moveCandidateHighlight(1);
      expect(fixture.store.getSnapshot().highlightedIndex).assertEqual(2);
    });

    it('serializes rapid selection then Space and commits the selected candidate', 0, async () => {
      const fixture = createControllerFixture();
      const selection = fixture.controller.selectNextHardwareCandidate();
      const commit = fixture.controller.handlePhysicalSpace();
      await selection;
      await commit;
      expect(fixture.sessionController.committedIndices.length).assertEqual(1);
      expect(fixture.sessionController.committedIndices[0]).assertEqual(1);
      expect(fixture.store.getSnapshot().rawInput).assertEqual('');
    });

    it('preserves every arbitrary rapid hardware letter in FIFO order', 0, async () => {
      const fixture = createControllerFixture();
      const randomInput = 'qazwsxedcrfvtgbyhnujmikolp';
      const operations: Promise<InputOperationResult>[] = [];
      for (let index = 0; index < randomInput.length; index += 1) {
        operations.push(fixture.controller.handlePhysicalLetter(randomInput.charAt(index), index > 0));
      }
      await Promise.all(operations);
      expect(fixture.sessionController.physicalLetters.join('')).assertEqual(randomInput);
      expect(fixture.sessionController.physicalContinuationFlags[0]).assertFalse();
      expect(fixture.sessionController.physicalContinuationFlags[randomInput.length - 1]).assertTrue();
    });

    it('allows hardware PageDown and PageUp without a fixed keyboard panel', 0, async () => {
      const fixture = createControllerFixture();
      expect(fixture.store.getSnapshot().keyboardVisible).assertFalse();
      await fixture.controller.nextHardwareCandidatePage();
      await fixture.controller.previousHardwareCandidatePage();
      expect(fixture.sessionController.nextPageCount).assertEqual(1);
      expect(fixture.sessionController.previousPageCount).assertEqual(1);
    });

    it('allows floating candidate pager buttons without an expanded keyboard panel', 0, async () => {
      const fixture = createControllerFixture();
      expect(fixture.store.getSnapshot().candidatePanelExpanded).assertFalse();
      await fixture.controller.nextFloatingCandidatePage();
      await fixture.controller.previousFloatingCandidatePage();
      expect(fixture.sessionController.nextPageCount).assertEqual(1);
      expect(fixture.sessionController.previousPageCount).assertEqual(1);
    });

    it('resolves rapid Tab and Enter after a queued pair candidate commit', 0, async () => {
      for (const keyCode of [2049, 2054, 2119]) {
        const fixture = createControllerFixture();
        fixture.sessionController.createPairOnCommit = true;
        const pending = session('', true);
        const command = resolvePhysicalKeyCommand(key(keyCode), pending);
        expect(command.type).assertEqual(keyCode === 2049 ? PhysicalKeyCommandType.TAB : PhysicalKeyCommandType.ENTER);
        const commit = fixture.controller.commitCandidate(0);
        const jump = keyCode === 2049 ? fixture.controller.handlePhysicalTab() :
          fixture.controller.handlePhysicalEnter();
        expect((await commit).success).assertTrue();
        expect((await jump).success).assertTrue();
        expect(fixture.sessionController.pairJumpCount).assertEqual(1);
        expect(fixture.sessionController.cancelCount).assertEqual(0);
      }
    });

    it('keeps Tab cancellation while composing inside a pair', 0, async () => {
      const fixture = createControllerFixture();
      fixture.sessionController.pairAvailable = true;
      await fixture.controller.handlePhysicalTab();
      expect(fixture.sessionController.cancelCount).assertEqual(1);
      expect(fixture.sessionController.pairJumpCount).assertEqual(0);
    });

    it('serializes Esc cancellation without committing a candidate', 0, async () => {
      const fixture = createControllerFixture();
      await fixture.controller.cancelPhysicalComposition();
      expect(fixture.sessionController.cancelCount).assertEqual(1);
      expect(fixture.sessionController.committedIndices.length).assertEqual(0);
      expect(fixture.store.getSnapshot().rawInput).assertEqual('');
    });

    it('serializes a routed physical pair jump through the keyboard controller', 0, async () => {
      const fixture = createControllerFixture();
      await fixture.controller.jumpOutPhysicalPair();
      expect(fixture.sessionController.pairJumpCount).assertEqual(1);
    });

    it('does not consume letters for English password or disabled-candidate editors', 0, () => {
      const password = session('');
      password.chineseInputAllowed = false;
      password.candidateBarVisible = false;
      expect(resolvePhysicalKeyCommand(key(2030), password).type).assertEqual(PhysicalKeyCommandType.NONE);
    });

    it('semicolon selects the second candidate or arms the symbol guide', 0, () => {
      const noCandidate: PhysicalKeySessionSnapshot = {
        sessionActive: true,
        editorConnected: true,
        candidateBarVisible: true,
        keyboardMode: KeyboardMode.CHINESE,
        rawInput: '',
        candidateCount: 0,
        compositionPending: false
      };
      expect(resolvePhysicalKeyCommand(key(2062), noCandidate).type)
        .assertEqual(PhysicalKeyCommandType.SYMBOL_GUIDE);

      const oneCandidate: PhysicalKeySessionSnapshot = {
        sessionActive: true,
        editorConnected: true,
        candidateBarVisible: true,
        keyboardMode: KeyboardMode.CHINESE,
        rawInput: 'ni',
        candidateCount: 1,
        compositionPending: false
      };
      const oneCandidateCommand = resolvePhysicalKeyCommand(key(2062), oneCandidate);
      expect(oneCandidateCommand.type).assertEqual(PhysicalKeyCommandType.CANDIDATE);
      expect(oneCandidateCommand.candidateIndex).assertEqual(0);

      const command = resolvePhysicalKeyCommand(key(2062), session());
      expect(command.type).assertEqual(PhysicalKeyCommandType.SECOND_CANDIDATE);
      expect(command.candidateIndex).assertEqual(1);
    });

    it('semicolon plus a letter resolves the configured symbol when no second candidate exists', 0, () => {
      const noSecondCandidate = session('');
      noSecondCandidate.candidateCount = 0;
      const guide = resolvePhysicalKeyCommand(key(2062), noSecondCandidate);
      expect(guide.type).assertEqual(PhysicalKeyCommandType.SYMBOL_GUIDE);
      noSecondCandidate.rawInput = ';';
      noSecondCandidate.candidateCount = 1;
      expect(resolvePhysicalKeyCommand(key(2062), noSecondCandidate).type)
        .assertEqual(PhysicalKeyCommandType.SYMBOL_GUIDE);
      const letter = resolvePhysicalKeyCommand(key(2017), noSecondCandidate);
      expect(letter.type).assertEqual(PhysicalKeyCommandType.LETTER);
      expect(resolveSymbolGuide(letter.letter ?? '')).assertEqual('……');
    });

    it('resolves a code-table semicolon from the live unique candidate and arms the guide', 0, async () => {
      const fixture = createControllerFixture();
      const liveComposition = composition();
      liveComposition.candidates = liveComposition.candidates.slice(0, 1);
      fixture.store.updateComposition(liveComposition);

      const result = await fixture.controller.handlePhysicalCodeTableSemicolon();

      expect(result.success).assertTrue();
      expect(fixture.sessionController.committedIndices.join(',')).assertEqual('0');
      expect(fixture.sessionController.insertedCharacters.join('')).assertEqual(';');
    });

    it('apostrophe selects the third candidate or inserts a syllable boundary', 0, () => {
      const twoCandidate: PhysicalKeySessionSnapshot = {
        sessionActive: true,
        editorConnected: true,
        candidateBarVisible: true,
        keyboardMode: KeyboardMode.CHINESE,
        rawInput: 'ni',
        candidateCount: 2,
        compositionPending: false
      };
      expect(resolvePhysicalKeyCommand(key(2063), twoCandidate).type)
        .assertEqual(PhysicalKeyCommandType.SEGMENT_BOUNDARY);

      const third = resolvePhysicalKeyCommand(key(2063), session());
      expect(third.type).assertEqual(PhysicalKeyCommandType.THIRD_CANDIDATE);
      expect(third.candidateIndex).assertEqual(2);

      const noComposition: PhysicalKeySessionSnapshot = {
        sessionActive: true,
        editorConnected: true,
        candidateBarVisible: true,
        keyboardMode: KeyboardMode.CHINESE,
        rawInput: '',
        candidateCount: 0,
        compositionPending: false
      };
      expect(resolvePhysicalKeyCommand(key(2063), noComposition).type)
        .assertEqual(PhysicalKeyCommandType.CONVENIENCE);
    });
  });
}
