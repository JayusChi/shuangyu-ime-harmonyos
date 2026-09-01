import { describe, expect, it } from '@ohos/hypium';
import { EnglishShiftController } from '../main/ets/application/EnglishShiftController';
import { EngineCoordinator } from '../main/ets/application/EngineCoordinator';
import { InputSessionController, ImeInputService } from '../main/ets/application/InputSessionController';
import { KeyboardModePolicy } from '../main/ets/application/KeyboardModePolicy';
import { ImeErrorCode } from '../main/ets/common/error/ImeError';
import {
  EditorContext,
  EditorKind,
  EnterAction,
  ShiftState
} from '../main/ets/domain/editor/EditorContext';
import { KeyboardActionType, KeyboardMode } from '../main/ets/domain/keyboard/KeyboardAction';
import {
  normalizeShuangpinKeyboardLayout,
  ShuangpinKeyboardLayout
} from '../main/ets/domain/keyboard/ShuangpinKeyboardLayout';
import {
  EditorAttributeCatalog,
  EditorAttributeMapper
} from '../main/ets/infrastructure/ime/EditorAttributeMapper';
import { CompositionResult, UserModelStatus } from '../main/ets/infrastructure/native/NativeEngineTypes';
import { InputSessionStore } from '../main/ets/state/InputSessionStore';
import { createStage10KeyboardLayout } from '../main/ets/presentation/keyboard/layouts/Stage10KeyboardLayouts';
import { KeyboardKeySpec } from '../main/ets/presentation/keyboard/model/KeyboardLayoutSpec';
import { KEYBOARD_STATUS_BAR_LAYOUT } from '../main/ets/presentation/candidate/CandidateBar';
import {
  KeyboardLayoutForm,
  KEYBOARD_BOTTOM_PADDING,
  KEY_WEIGHTS,
  LANDSCAPE_METRICS,
  PORTRAIT_METRICS,
  calculateDynamicMetrics
} from '../main/ets/presentation/keyboard/design/KeyboardMetrics';
import { createScreenMetrics } from '../main/ets/domain/display/ScreenMetrics';

const CATALOG: EditorAttributeCatalog = {
  patternNull: 0,
  patternText: 1,
  patternNumber: 2,
  patternPhone: 3,
  patternEmail: 5,
  patternUri: 6,
  patternPassword: 7,
  patternScreenLockPassword: 8,
  patternNumberPassword: 9,
  patternNewPassword: 11,
  patternNumberDecimal: 12,
  enterUnspecified: 100,
  enterGo: 101,
  enterSearch: 102,
  enterSend: 103,
  enterNext: 104,
  enterDone: 105,
  enterNewline: 106
};

function emptyComposition(): CompositionResult {
  return {
    success: true,
    errorCode: ImeErrorCode.SUCCESS,
    errorMessage: '',
    rawInput: '',
    preeditText: '',
    parsedSyllables: [],
    pendingCode: '',
    parserState: 'empty',
    candidates: [],
    highlightedIndex: -1,
    hasNextPage: false,
    hasPreviousPage: false,
    candidatePage: 0,
    commitText: '',
    action: null,
    compositionFinished: false
  };
}

function learningStatus(allowed: boolean): UserModelStatus {
  return {
    loaded: true,
    enabled: true,
    sessionLearningAllowed: allowed,
    dirty: false,
    recordCount: 0,
    formatVersion: 1,
    dataVersion: 1,
    lastErrorCode: ''
  };
}

class Stage10FakeEngineCoordinator extends EngineCoordinator {
  processCount: number = 0;
  processedKeys: string[] = [];
  selectCount: number = 0;
  resetCount: number = 0;
  sessionLearningValues: boolean[] = [];
  globalLearningChangeCount: number = 0;
  flushUserModelCount: number = 0;
  private rawInput: string = '';

  isInitialized(): boolean {
    return true;
  }

  reset(): CompositionResult {
    this.resetCount += 1;
    this.rawInput = '';
    return emptyComposition();
  }

  processKey(key: string): CompositionResult {
    this.processCount += 1;
    this.processedKeys.push(key);
    this.rawInput += key;
    const result = emptyComposition();
    result.rawInput = this.rawInput;
    result.preeditText = this.rawInput;
    result.parserState = 'complete';
    result.parsedSyllables = [key];
    result.candidates = [{ id: 'candidate-1', text: '你', reading: 'ni', source: 'test' }];
    result.highlightedIndex = 0;
    return result;
  }

  insertSegmentBoundary(): CompositionResult {
    const result = emptyComposition();
    if (this.rawInput.length === 0 || this.rawInput.endsWith("'")) {
      result.success = false;
      result.errorCode = ImeErrorCode.INVALID_ARGUMENT;
      result.errorMessage = 'invalid segment boundary';
      return result;
    }
    this.rawInput += "'";
    result.rawInput = this.rawInput;
    result.preeditText = this.rawInput;
    result.segmentBoundaries = [this.rawInput.length - 1];
    result.parserState = 'complete';
    result.candidates = [{ id: 'candidate-1', text: '你', reading: 'ni', source: 'test' }];
    result.highlightedIndex = 0;
    return result;
  }

  backspace(): CompositionResult {
    if (this.rawInput.length > 0) {
      this.rawInput = this.rawInput.slice(0, this.rawInput.length - 1);
    }
    const result = emptyComposition();
    result.rawInput = this.rawInput;
    result.preeditText = this.rawInput;
    if (this.rawInput.length > 0) {
      result.parserState = 'complete';
      result.candidates = [{ id: 'candidate-1', text: '你', reading: 'ni', source: 'test' }];
      result.highlightedIndex = 0;
    }
    return result;
  }

  selectCandidate(candidateIndex: number): CompositionResult {
    this.selectCount += 1;
    this.rawInput = '';
    const result = emptyComposition();
    result.commitText = '你';
    result.compositionFinished = true;
    return result;
  }

  setSessionLearningAllowed(allowed: boolean): UserModelStatus {
    this.sessionLearningValues.push(allowed);
    return learningStatus(allowed);
  }

  setUserLearningEnabled(enabled: boolean): UserModelStatus {
    this.globalLearningChangeCount += 1;
    return learningStatus(true);
  }

  flushUserModel(): UserModelStatus {
    this.flushUserModelCount += 1;
    return learningStatus(true);
  }
}

class Stage10GuideRepeatEngineCoordinator extends Stage10FakeEngineCoordinator {
  private guidePressCount: number = 0;

  processKey(key: string): CompositionResult {
    if (key === 'q' && this.guidePressCount === 1) {
      this.processCount += 1;
      this.processedKeys.push(key);
      const result = emptyComposition();
      result.commitText = '：“';
      result.compositionFinished = true;
      return result;
    }
    if (key !== ';') {
      return super.processKey(key);
    }
    this.processCount += 1;
    this.processedKeys.push(key);
    this.guidePressCount += 1;
    const result = emptyComposition();
    if (this.guidePressCount === 1) {
      result.rawInput = ';';
      result.preeditText = ';';
      result.parserState = 'incomplete';
      result.candidates = [{ id: 'quick:_', text: '：', reading: '_', source: 'quick-symbol' }];
      result.highlightedIndex = 0;
    } else {
      result.commitText = '；';
      result.compositionFinished = true;
    }
    return result;
  }

  selectCandidate(candidateIndex: number): CompositionResult {
    if (this.guidePressCount === 1 && candidateIndex === 0) {
      this.selectCount += 1;
      const result = emptyComposition();
      result.commitText = '：';
      result.compositionFinished = true;
      return result;
    }
    return super.selectCandidate(candidateIndex);
  }
}

class Stage10YinxingEngineCoordinator extends Stage10FakeEngineCoordinator {
  getActiveSchemeId(): string {
    return 'xiaohe-yinxing';
  }
}

class Stage10FakeImeService implements ImeInputService {
  insertedTexts: string[] = [];
  editorText: string = '';
  previewTexts: string[] = [];
  compatibleTexts: string[] = [];
  finishPreviewCount: number = 0;
  clearPreviewCount: number = 0;
  failNextPreview: boolean = false;
  failNextPreviewCommit: boolean = false;
  enterActions: EnterAction[] = [];
  deleteCount: number = 0;
  resetPreviewStateCount: number = 0;
  hideCount: number = 0;
  previewTextAttached: boolean = true;

  async insertText(text: string): Promise<boolean> {
    this.insertedTexts.push(text);
    this.editorText += text;
    return true;
  }

  async setPreviewText(text: string, previewSupported: boolean = true): Promise<boolean> {
    if (previewSupported) {
      this.previewTexts.push(text);
    } else {
      this.compatibleTexts.push(text);
    }
    if (this.failNextPreview) {
      this.failNextPreview = false;
      return false;
    }
    return true;
  }

  async commitPreviewText(text: string): Promise<boolean> {
    if (this.failNextPreviewCommit) {
      this.failNextPreviewCommit = false;
      return false;
    }
    return this.insertText(text);
  }

  async finishPreviewText(): Promise<boolean> {
    this.finishPreviewCount += 1;
    return true;
  }

  async clearPreviewText(): Promise<boolean> {
    this.clearPreviewCount += 1;
    return true;
  }

  async isPreviewTextAttached(): Promise<boolean> {
    return this.previewTextAttached;
  }

  resetPreviewState(): void {
    this.resetPreviewStateCount += 1;
  }

  async deleteBackward(count?: number): Promise<boolean> {
    const requested = count ?? 1;
    this.deleteCount += requested;
    this.editorText = this.editorText.slice(0, Math.max(0, this.editorText.length - requested));
    return true;
  }

  async deleteBackwardIfMatches(text: string): Promise<boolean> {
    if (!this.editorText.endsWith(text)) {
      return false;
    }
    this.editorText = this.editorText.slice(0, this.editorText.length - text.length);
    return true;
  }

  async sendEnter(action: EnterAction = EnterAction.ENTER): Promise<boolean> {
    this.enterActions.push(action);
    return true;
  }

  async hideKeyboard(): Promise<boolean> {
    this.hideCount += 1;
    return true;
  }
}

class PreviewGate {
  private resolver?: (value: boolean) => void;
  readonly promise: Promise<boolean> = new Promise<boolean>((resolve: (value: boolean) => void) => {
    this.resolver = resolve;
  });

  resolve(value: boolean = true): void {
    this.resolver?.(value);
  }
}

class DeferredPreviewImeService extends Stage10FakeImeService {
  private gate?: PreviewGate;

  gateNextPreview(): PreviewGate {
    const gate = new PreviewGate();
    this.gate = gate;
    return gate;
  }

  async setPreviewText(text: string): Promise<boolean> {
    this.previewTexts.push(text);
    const gate = this.gate;
    this.gate = undefined;
    if (gate) {
      return gate.promise;
    }
    return true;
  }
}

function nextTask(): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, 0);
  });
}

function mapper(): EditorAttributeMapper {
  return new EditorAttributeMapper(CATALOG);
}

export default function stage10Test() {
  describe('stage10EditorAttributeMapping', () => {
    it('mapsNormalPasswordNumberAndNumberPassword', 0, () => {
      const target = mapper();
      expect(target.mapValues(CATALOG.patternText, CATALOG.enterDone).kind).assertEqual(EditorKind.NORMAL_TEXT);
      expect(target.mapValues(CATALOG.patternPassword, CATALOG.enterDone).isPassword).assertTrue();
      expect(target.mapValues(CATALOG.patternNumber, CATALOG.enterDone).preferredKeyboardMode)
        .assertEqual(KeyboardMode.NUMBER);
      const numberPassword = target.mapValues(CATALOG.patternNumberPassword, CATALOG.enterDone);
      expect(numberPassword.isPassword).assertTrue();
      expect(numberPassword.preferredKeyboardMode).assertEqual(KeyboardMode.NUMBER);
    });

    it('mapsPhoneEmailUrlSearchAndMultiline', 0, () => {
      const target = mapper();
      expect(target.mapValues(CATALOG.patternPhone, CATALOG.enterDone).kind).assertEqual(EditorKind.PHONE);
      expect(target.mapValues(CATALOG.patternEmail, CATALOG.enterNext).kind).assertEqual(EditorKind.EMAIL);
      expect(target.mapValues(CATALOG.patternUri, CATALOG.enterGo).kind).assertEqual(EditorKind.URL);
      expect(target.mapValues(CATALOG.patternText, CATALOG.enterSearch).kind).assertEqual(EditorKind.SEARCH);
      const multiline = target.mapValues(CATALOG.patternText, CATALOG.enterNewline);
      expect(multiline.kind).assertEqual(EditorKind.MULTILINE);
      expect(multiline.isMultiline).assertTrue();
    });

    it('mapsDecimalAndUnknownSafely', 0, () => {
      const target = mapper();
      const decimal = target.mapValues(CATALOG.patternNumberDecimal, CATALOG.enterDone);
      expect(decimal.kind).assertEqual(EditorKind.NUMBER);
      expect(decimal.numberDecimalAllowed).assertTrue();

      const compatibilityDecimal = target.mapValues(CATALOG.patternNumber, CATALOG.enterDone, 'number_decimal');
      expect(compatibilityDecimal.kind).assertEqual(EditorKind.NUMBER);
      expect(compatibilityDecimal.numberDecimalAllowed).assertTrue();
      const unknown = target.mapValues(9999, 9999);
      expect(unknown.kind).assertEqual(EditorKind.UNKNOWN);
      expect(unknown.preferredKeyboardMode).assertEqual(KeyboardMode.CHINESE);
      expect(unknown.learningAllowed).assertTrue();
      expect(unknown.candidateBarVisible).assertTrue();
      expect(target.mapValues(undefined, undefined).kind).assertEqual(EditorKind.UNKNOWN);
    });

    it('mapsAllSupportedEnterActions', 0, () => {
      const target = mapper();
      expect(target.mapEnterAction(CATALOG.enterSearch)).assertEqual(EnterAction.SEARCH);
      expect(target.mapEnterAction(CATALOG.enterDone)).assertEqual(EnterAction.DONE);
      expect(target.mapEnterAction(CATALOG.enterNext)).assertEqual(EnterAction.NEXT);
      expect(target.mapEnterAction(CATALOG.enterGo)).assertEqual(EnterAction.GO);
      expect(target.mapEnterAction(CATALOG.enterSend)).assertEqual(EnterAction.SEND);
      expect(target.mapEnterAction(9999)).assertEqual(EnterAction.ENTER);
    });
  });

  describe('stage10KeyboardModePolicy', () => {
    it('normalTextDefaultsChineseAndRestoresTextPreference', 0, () => {
      const store = new InputSessionStore();
      const normal = mapper().mapValues(CATALOG.patternText, CATALOG.enterDone);
      store.applyEditorContext(normal);
      expect(store.getSnapshot().keyboardMode).assertEqual(KeyboardMode.CHINESE);
      store.switchKeyboardMode(KeyboardMode.ENGLISH, true);
      store.applyEditorContext(normal);
      expect(store.getSnapshot().keyboardMode).assertEqual(KeyboardMode.ENGLISH);
    });

    it('restrictedEditorsAlwaysUseTheirSafeMode', 0, () => {
      const store = new InputSessionStore();
      const target = mapper();
      store.applyEditorContext(target.mapValues(CATALOG.patternEmail, CATALOG.enterNext));
      expect(store.getSnapshot().keyboardMode).assertEqual(KeyboardMode.ENGLISH);
      store.switchKeyboardMode(KeyboardMode.CHINESE, true);
      expect(store.getSnapshot().keyboardMode).assertEqual(KeyboardMode.ENGLISH);
      store.applyEditorContext(target.mapValues(CATALOG.patternUri, CATALOG.enterGo));
      expect(store.getSnapshot().keyboardMode).assertEqual(KeyboardMode.ENGLISH);
      store.applyEditorContext(target.mapValues(CATALOG.patternNumber, CATALOG.enterDone));
      expect(store.getSnapshot().keyboardMode).assertEqual(KeyboardMode.NUMBER);
      store.switchKeyboardMode(KeyboardMode.CHINESE, true);
      expect(store.getSnapshot().keyboardMode).assertEqual(KeyboardMode.NUMBER);
      store.applyEditorContext(target.mapValues(CATALOG.patternPhone, CATALOG.enterDone));
      expect(store.getSnapshot().keyboardMode).assertEqual(KeyboardMode.PHONE);
    });

    it('passwordNeverEntersChineseAndSymbolRestoresPreviousMode', 0, () => {
      const store = new InputSessionStore();
      const target = mapper();
      store.applyEditorContext(target.mapValues(CATALOG.patternPassword, CATALOG.enterDone));
      expect(store.getSnapshot().keyboardMode).assertEqual(KeyboardMode.ENGLISH);
      store.switchKeyboardMode(KeyboardMode.CHINESE, true);
      expect(store.getSnapshot().keyboardMode).assertEqual(KeyboardMode.ENGLISH);

      const normal = target.mapValues(CATALOG.patternText, CATALOG.enterDone);
      store.applyEditorContext(normal);
      store.switchKeyboardMode(KeyboardMode.SYMBOL, true);
      expect(store.getSnapshot().keyboardMode).assertEqual(KeyboardMode.SYMBOL);
      store.switchKeyboardMode(KeyboardMode.SYMBOL, true);
      expect(store.getSnapshot().keyboardMode).assertEqual(KeyboardMode.CHINESE);
    });

    it('candidateBarReservesTextKeyboardSpaceWithoutCandidates', 0, () => {
      const store = new InputSessionStore();
      const target = mapper();
      store.applyEditorContext(target.mapValues(CATALOG.patternText, CATALOG.enterDone));
      expect(store.getSnapshot().candidateBarVisible).assertTrue();
      store.switchKeyboardMode(KeyboardMode.ENGLISH, true);
      expect(store.getSnapshot().candidateBarVisible).assertTrue();
      store.switchKeyboardMode(KeyboardMode.CHINESE, true);
      expect(store.getSnapshot().candidateBarVisible).assertTrue();
      const composition = emptyComposition();
      composition.rawInput = 'n';
      composition.preeditText = 'n';
      store.updateComposition(composition);
      expect(store.getSnapshot().candidateBarVisible).assertTrue();
      store.clearComposition();
      expect(store.getSnapshot().candidateBarVisible).assertTrue();
      store.applyEditorContext(target.mapValues(CATALOG.patternPassword, CATALOG.enterDone));
      expect(store.getSnapshot().candidateBarVisible).assertFalse();
      store.applyEditorContext(target.mapValues(CATALOG.patternNumber, CATALOG.enterDone));
      expect(store.getSnapshot().candidateBarVisible).assertFalse();
      store.applyEditorContext(target.mapValues(CATALOG.patternPhone, CATALOG.enterDone));
      expect(store.getSnapshot().candidateBarVisible).assertFalse();
      store.applyEditorContext(target.mapValues(CATALOG.patternEmail, CATALOG.enterDone));
      expect(store.getSnapshot().candidateBarVisible).assertTrue();
      store.applyEditorContext(target.mapValues(CATALOG.patternUri, CATALOG.enterDone));
      expect(store.getSnapshot().candidateBarVisible).assertTrue();
    });

    it('candidatePagerStateStaysStableAcrossLongCandidatePages', 0, () => {
      const store = new InputSessionStore();
      const target = mapper();
      store.applyEditorContext(target.mapValues(CATALOG.patternText, CATALOG.enterDone));
      const composition = emptyComposition();
      composition.rawInput = 'abcdefghijklmnopqrstuvwxyz';
      composition.preeditText = 'abcdefghijklmnopqrstuvwxyz';
      composition.candidates = [{
        id: 'long-candidate',
        text: '这是一个用于验证候选内容宽度保护的超长候选词',
        reading: 'abcdefghijklmnopqrstuvwxyz',
        source: 'test'
      }];
      composition.hasPreviousPage = true;
      composition.hasNextPage = true;
      composition.candidatePage = 7;

      store.updateComposition(composition);
      const state = store.getSnapshot();
      expect(state.candidates.length).assertEqual(1);
      expect(state.hasPreviousPage).assertTrue();
      expect(state.hasNextPage).assertTrue();
      expect(state.candidatePage).assertEqual(7);
    });

    it('policyRejectsUnsupportedMode', 0, () => {
      const policy = new KeyboardModePolicy();
      const email = mapper().mapValues(CATALOG.patternEmail, CATALOG.enterDone);
      expect(policy.isAllowed(email, KeyboardMode.CHINESE)).assertFalse();
      expect(policy.fallbackMode(email)).assertEqual(KeyboardMode.ENGLISH);
    });
  });

  describe('stage10EnglishShift', () => {
    it('singleShiftUppercasesOneCommittedLetter', 0, () => {
      const shift = new EnglishShiftController();
      expect(shift.getState()).assertEqual(ShiftState.LOWERCASE);
      shift.pressShift(1000);
      expect(shift.transformLetter('a')).assertEqual('A');
      shift.letterCommitted();
      expect(shift.getState()).assertEqual(ShiftState.LOWERCASE);
    });

    it('nonLetterDoesNotConsumeOneShotState', 0, () => {
      const shift = new EnglishShiftController();
      shift.pressShift(1000);
      expect(shift.getState()).assertEqual(ShiftState.ONE_SHOT_UPPERCASE);
      expect(shift.getState()).assertEqual(ShiftState.ONE_SHOT_UPPERCASE);
    });

    it('doubleShiftEnablesAndDisablesCapsLock', 0, () => {
      const shift = new EnglishShiftController();
      shift.pressShift(1000);
      shift.pressShift(1200);
      expect(shift.getState()).assertEqual(ShiftState.CAPS_LOCK);
      expect(shift.transformLetter('a')).assertEqual('A');
      shift.letterCommitted();
      expect(shift.transformLetter('b')).assertEqual('B');
      shift.pressShift(1600);
      expect(shift.getState()).assertEqual(ShiftState.LOWERCASE);
    });

    it('editorSwitchAndPasswordClearShiftState', 0, () => {
      const store = new InputSessionStore();
      const target = mapper();
      store.applyEditorContext(target.mapValues(CATALOG.patternEmail, CATALOG.enterDone));
      store.pressShift(1000);
      store.pressShift(1200);
      expect(store.getSnapshot().shiftState).assertEqual(ShiftState.CAPS_LOCK);
      store.applyEditorContext(target.mapValues(CATALOG.patternPassword, CATALOG.enterDone));
      expect(store.getSnapshot().shiftState).assertEqual(ShiftState.LOWERCASE);
    });

    it('controllerCommitsUppercaseValueAndKeepsOneShotForNonLetter', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const engine = new Stage10FakeEngineCoordinator();
      const controller = new InputSessionController(store, ime, engine);
      store.markSessionStarted();
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternEmail, CATALOG.enterNext));
      controller.pressShift(1000);
      await controller.insertCharacter('1');
      expect(store.getSnapshot().shiftState).assertEqual(ShiftState.ONE_SHOT_UPPERCASE);
      await controller.deleteBackward();
      expect(store.getSnapshot().shiftState).assertEqual(ShiftState.ONE_SHOT_UPPERCASE);
      await controller.insertLetter('a');
      expect(ime.insertedTexts[0]).assertEqual('1');
      expect(ime.insertedTexts[1]).assertEqual('A');
      expect(store.getSnapshot().shiftState).assertEqual(ShiftState.LOWERCASE);
    });

    it('controllerCapsLockCommitsConsecutiveUppercaseLetters', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const engine = new Stage10FakeEngineCoordinator();
      const controller = new InputSessionController(store, ime, engine);
      store.markSessionStarted();
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternUri, CATALOG.enterGo));
      controller.pressShift(1000);
      controller.pressShift(1200);
      await controller.insertLetter('a');
      await controller.insertLetter('b');
      expect(ime.insertedTexts[0]).assertEqual('A');
      expect(ime.insertedTexts[1]).assertEqual('B');
      expect(store.getSnapshot().shiftState).assertEqual(ShiftState.CAPS_LOCK);
      controller.pressShift(1600);
      expect(store.getSnapshot().shiftState).assertEqual(ShiftState.LOWERCASE);
    });
  });

  describe('stage33ChineseDynamicKey', () => {
    it('replaces a virtual double Chinese period with one ASCII period inside the configured window', 0,
      async () => {
        const store = new InputSessionStore();
        const ime = new Stage10FakeImeService();
        const controller = new InputSessionController(store, ime, new Stage10FakeEngineCoordinator());
        store.markSessionStarted();
        controller.applyEditorContext(mapper().mapValues(CATALOG.patternText, CATALOG.enterDone));

        await controller.insertCharacter('。', controller.getInputSessionGeneration(),
          controller.beginInputAction(1000));
        await controller.insertCharacter('。', controller.getInputSessionGeneration(),
          controller.beginInputAction(1500));

        expect(ime.editorText).assertEqual('.');
      });

    it('replaces a physical double Chinese period through the same safe editor contract', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const controller = new InputSessionController(store, ime, new Stage10FakeEngineCoordinator());
      store.markSessionStarted();
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternText, CATALOG.enterDone));

      await controller.insertPhysicalPunctuation('。', controller.getInputSessionGeneration(),
        controller.beginInputAction(2000));
      await controller.insertPhysicalPunctuation('。', controller.getInputSessionGeneration(),
        controller.beginInputAction(2300));

      expect(ime.editorText).assertEqual('.');
    });

    it('replaces each configured Chinese punctuation with its matching ASCII symbol', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const controller = new InputSessionController(store, ime, new Stage10FakeEngineCoordinator());
      store.markSessionStarted();
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternText, CATALOG.enterDone));

      await controller.insertCharacter('，', controller.getInputSessionGeneration(),
        controller.beginInputAction(2400));
      await controller.insertCharacter('，', controller.getInputSessionGeneration(),
        controller.beginInputAction(2700));
      await controller.insertCharacter('？', controller.getInputSessionGeneration(),
        controller.beginInputAction(3000));
      await controller.insertCharacter('？', controller.getInputSessionGeneration(),
        controller.beginInputAction(3300));

      expect(ime.editorText).assertEqual(',?');
    });

    it('does not merge two different smart punctuation targets', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const controller = new InputSessionController(store, ime, new Stage10FakeEngineCoordinator());
      store.markSessionStarted();
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternText, CATALOG.enterDone));

      await controller.insertCharacter('，', controller.getInputSessionGeneration(),
        controller.beginInputAction(3400));
      await controller.insertCharacter('。', controller.getInputSessionGeneration(),
        controller.beginInputAction(3600));

      expect(ime.editorText).assertEqual('，。');
    });

    it('maps ASCII keys from the Chinese symbol page before smart punctuation replacement', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const controller = new InputSessionController(store, ime, new Stage10FakeEngineCoordinator());
      store.markSessionStarted();
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternText, CATALOG.enterDone));
      await controller.toggleSymbolMode();

      await controller.insertCharacter('?', controller.getInputSessionGeneration(),
        controller.beginInputAction(3700));
      await controller.insertCharacter('?', controller.getInputSessionGeneration(),
        controller.beginInputAction(3900));

      expect(ime.editorText).assertEqual('?');
    });

    it('keeps both Chinese periods when the second press exceeds the configured window', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const controller = new InputSessionController(store, ime, new Stage10FakeEngineCoordinator());
      store.markSessionStarted();
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternText, CATALOG.enterDone));

      await controller.insertCharacter('。', controller.getInputSessionGeneration(),
        controller.beginInputAction(3000));
      await controller.insertCharacter('。', controller.getInputSessionGeneration(),
        controller.beginInputAction(3501));

      expect(ime.editorText).assertEqual('。。');
    });

    it('routesSemicolonFromChineseSymbolPageIntoGuideEngine', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const engine = new Stage10FakeEngineCoordinator();
      const controller = new InputSessionController(store, ime, engine);
      store.markSessionStarted();
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternText, CATALOG.enterDone));
      store.switchKeyboardMode(KeyboardMode.CHINESE);

      await controller.toggleSymbolMode();
      expect(store.getSnapshot().keyboardMode).assertEqual(KeyboardMode.SYMBOL);
      expect(store.getSnapshot().modeBeforeTransient).assertEqual(KeyboardMode.CHINESE);
      await controller.insertCharacter(';');

      expect(engine.processedKeys.join('')).assertEqual(';');
      expect(ime.insertedTexts.length).assertEqual(0);
      expect(ime.compatibleTexts[0]).assertEqual(';');
    });

    it('commitsTheQuickSymbolRepeatTriggerOnTheSecondSemicolon', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const engine = new Stage10GuideRepeatEngineCoordinator();
      const controller = new InputSessionController(store, ime, engine);
      store.markSessionStarted();
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternText, CATALOG.enterDone));
      store.switchKeyboardMode(KeyboardMode.CHINESE);

      expect((await controller.insertCharacter(';')).success).assertTrue();
      expect(store.getSnapshot().candidates[0].text).assertEqual('：');
      expect((await controller.insertCharacter(';')).success).assertTrue();

      expect(engine.processedKeys.join('')).assertEqual(';;');
      expect(ime.insertedTexts.join('')).assertEqual('；');
      expect(store.getSnapshot().rawInput).assertEqual('');
      expect(store.getSnapshot().candidates.length).assertEqual(0);
    });

    it('commitsTheBareSemicolonColonCandidateWithSpace', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const engine = new Stage10GuideRepeatEngineCoordinator();
      const controller = new InputSessionController(store, ime, engine);
      store.markSessionStarted();
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternText, CATALOG.enterDone));
      store.switchKeyboardMode(KeyboardMode.CHINESE);

      expect((await controller.insertCharacter(';')).success).assertTrue();
      expect((await controller.insertSpace()).success).assertTrue();

      expect(ime.insertedTexts.join('')).assertEqual('：');
      expect(store.getSnapshot().rawInput).assertEqual('');
    });

    it('commitsAUniqueQuickSymbolAsSoonAsItsGuideLetterArrives', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const engine = new Stage10GuideRepeatEngineCoordinator();
      const controller = new InputSessionController(store, ime, engine);
      store.markSessionStarted();
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternText, CATALOG.enterDone));
      store.switchKeyboardMode(KeyboardMode.CHINESE);

      expect((await controller.insertCharacter(';')).success).assertTrue();
      expect((await controller.insertLetter('q')).success).assertTrue();

      expect(engine.processedKeys.join('')).assertEqual(';q');
      expect(ime.insertedTexts.join('')).assertEqual('：“');
      expect(store.getSnapshot().rawInput).assertEqual('');
      expect(store.getSnapshot().candidates.length).assertEqual(0);
    });

    it('outputs upper-deck punctuation exactly as printed instead of converting it', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const engine = new Stage10FakeEngineCoordinator();
      const controller = new InputSessionController(store, ime, engine);
      store.markSessionStarted();
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternText, CATALOG.enterDone));
      store.switchKeyboardMode(KeyboardMode.CHINESE);

      expect((await controller.insertLiteralCharacter('/')).success).assertTrue();
      expect((await controller.insertLiteralCharacter(';')).success).assertTrue();
      expect((await controller.insertLiteralCharacter('!')).success).assertTrue();

      expect(ime.insertedTexts.join('')).assertEqual('/;!');
      expect(engine.processedKeys.length).assertEqual(0);
      expect(store.getSnapshot().rawInput).assertEqual('');
    });

    it('routes the skin universal key through the Xiaohe Yinxing wildcard engine', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const engine = new Stage10YinxingEngineCoordinator();
      const controller = new InputSessionController(store, ime, engine);
      store.markSessionStarted();
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternText, CATALOG.enterDone));
      store.switchKeyboardMode(KeyboardMode.CHINESE);

      expect((await controller.insertLetter('u')).success).assertTrue();
      expect((await controller.insertUniversalKey()).success).assertTrue();

      expect(engine.processedKeys.join('')).assertEqual('u`');
      expect(store.getSnapshot().rawInput).assertEqual('u`');
      expect(store.getSnapshot().candidates.length > 0).assertTrue();
      expect(ime.insertedTexts.length).assertEqual(0);
    });

    it('togglesChineseCapsAndCommitsUppercaseWithoutComposition', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const engine = new Stage10FakeEngineCoordinator();
      const controller = new InputSessionController(store, ime, engine);
      store.markSessionStarted();
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternText, CATALOG.enterDone));

      expect(controller.toggleChineseCapsLock().success).assertTrue();
      expect(store.getSnapshot().chineseCapsLock).assertTrue();
      await controller.insertLetter('a');
      await controller.insertLetter('b');

      expect(ime.insertedTexts.join('')).assertEqual('AB');
      expect(engine.processCount).assertEqual(0);
      expect(store.getSnapshot().rawInput).assertEqual('');
      expect(store.getSnapshot().candidates.length).assertEqual(0);
      expect(store.getSnapshot().preeditText).assertEqual('');
      expect(controller.toggleChineseCapsLock().success).assertTrue();
      expect(store.getSnapshot().chineseCapsLock).assertFalse();
    });

    it('clearsChineseCapsAcrossModeEditorHideAndResetLifecycles', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const controller = new InputSessionController(store, ime, new Stage10FakeEngineCoordinator());
      const normal = mapper().mapValues(CATALOG.patternText, CATALOG.enterDone);
      store.markSessionStarted();
      controller.applyEditorContext(normal);

      controller.toggleChineseCapsLock();
      store.switchKeyboardMode(KeyboardMode.ENGLISH);
      expect(store.getSnapshot().chineseCapsLock).assertFalse();
      store.switchKeyboardMode(KeyboardMode.CHINESE);
      controller.toggleChineseCapsLock();
      controller.applyEditorContext(normal);
      expect(store.getSnapshot().chineseCapsLock).assertFalse();
      controller.toggleChineseCapsLock();
      store.markKeyboardVisible();
      await controller.hideKeyboard();
      expect(store.getSnapshot().chineseCapsLock).assertFalse();
      store.markKeyboardVisible();
      controller.toggleChineseCapsLock();
      store.resetAll();
      expect(store.getSnapshot().chineseCapsLock).assertFalse();
    });

    it('insertsAndDeletesStructuredSegmentBoundaryWithoutEditorCommit', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const engine = new Stage10FakeEngineCoordinator();
      const controller = new InputSessionController(store, ime, engine);
      store.markSessionStarted();
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternText, CATALOG.enterDone));
      await controller.insertLetter('n');
      await controller.insertLetter('i');

      const segmented = await controller.insertSegmentBoundary();
      expect(segmented.success).assertTrue();
      expect(store.getSnapshot().rawInput).assertEqual("ni'");
      expect(store.getSnapshot().segmentBoundaries.join(',')).assertEqual('2');
      expect(store.getSnapshot().candidatePage).assertEqual(0);
      expect(ime.insertedTexts.length).assertEqual(0);
      expect(ime.compatibleTexts[ime.compatibleTexts.length - 1]).assertEqual("ni'");

      await controller.deleteBackward();
      expect(store.getSnapshot().rawInput).assertEqual('ni');
      await controller.deleteBackward();
      await controller.deleteBackward();
      expect(store.getSnapshot().rawInput).assertEqual('');
      const layout = createStage10KeyboardLayout(
        KeyboardMode.CHINESE,
        mapper().mapValues(CATALOG.patternText, CATALOG.enterDone),
        ShiftState.LOWERCASE,
        store.getSnapshot().rawInput,
        false
      );
      expect(layout.rows[2].keys[0].action.type)
        .assertEqual(KeyboardActionType.TOGGLE_CHINESE_CAPS_LOCK);
    });

    it('rejectsEmptyOrRepeatedSegmentBoundaryWithoutLosingComposition', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const engine = new Stage10FakeEngineCoordinator();
      const controller = new InputSessionController(store, ime, engine);
      store.markSessionStarted();
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternText, CATALOG.enterDone));
      expect((await controller.insertSegmentBoundary()).success).assertFalse();
      await controller.insertLetter('n');
      await controller.insertLetter('i');
      expect((await controller.insertSegmentBoundary()).success).assertTrue();
      const before = store.getSnapshot().rawInput;
      expect((await controller.insertSegmentBoundary()).success).assertFalse();
      expect(store.getSnapshot().rawInput).assertEqual(before);
      expect(ime.insertedTexts.length).assertEqual(0);
    });
  });

  describe('stage10KeyboardLayouts', () => {
    it('usesOneBottomPaddingConstantForBothOrientations', 0, () => {
      expect(KEYBOARD_BOTTOM_PADDING).assertEqual(15);
      expect(PORTRAIT_METRICS.bottomPadding).assertEqual(KEYBOARD_BOTTOM_PADDING);
      expect(LANDSCAPE_METRICS.bottomPadding).assertEqual(KEYBOARD_BOTTOM_PADDING);
    });

    it('keepsLetterTypographyCompactAcrossPhoneLandscapeAndTablet', 0, () => {
      expect(PORTRAIT_METRICS.letterFontSize).assertEqual(14);
      expect(LANDSCAPE_METRICS.letterFontSize).assertEqual(13);
      const phone = calculateDynamicMetrics(
        createScreenMetrics({ widthPx: 1320, heightPx: 2856, densityPixels: 3.5 }, false)
      );
      const tablet = calculateDynamicMetrics(
        createScreenMetrics({ widthPx: 2880, heightPx: 1920, densityPixels: 2 }, true)
      );
      expect(phone.letterFontSize <= 18).assertTrue();
      expect(tablet.letterFontSize <= 18).assertTrue();
      expect(phone.previewFontSize <= 27).assertTrue();
      expect(tablet.previewFontSize <= 27).assertTrue();
    });

    it('sharesStandardQwertyStructureAcrossChineseAndEnglish', 0, () => {
      const context = mapper().mapValues(CATALOG.patternText, CATALOG.enterDone);
      const chinese = createStage10KeyboardLayout(KeyboardMode.CHINESE, context, ShiftState.LOWERCASE);
      const english = createStage10KeyboardLayout(KeyboardMode.ENGLISH, context, ShiftState.LOWERCASE);
      const expectedRows: string[] = ['qwertyuiop', 'asdfghjkl', 'zxcvbnm'];

      [chinese, english].forEach((layout): void => {
        expectedRows.forEach((expected: string, index: number): void => {
          const letters = layout.rows[index].keys
            .filter((item) => item.action.type === KeyboardActionType.LETTER)
            .map((item) => item.action.letter)
            .join('');
          expect(letters).assertEqual(expected);
        });
        expect(layout.rows[0].keys.length).assertEqual(10);
        expect(layout.rows[1].keys.length).assertEqual(9);
        expect(layout.rows[2].keys.length).assertEqual(9);
        expect(layout.rows[2].keys[1].action.letter).assertEqual('z');
        expect(layout.rows[2].keys[7].action.letter).assertEqual('m');
        expect(layout.rows[2].keys[8].action.type).assertEqual(KeyboardActionType.DELETE);
      });

      expect(chinese.rows[2].keys[0].action.type)
        .assertEqual(KeyboardActionType.TOGGLE_CHINESE_CAPS_LOCK);
      expect(english.rows[2].keys[0].action.type).assertEqual(KeyboardActionType.SHIFT);

      expect(chinese.rows[0].keys.map((item) => item.id).join(','))
        .assertEqual(english.rows[0].keys.map((item) => item.id).join(','));
      expect(chinese.rows[1].keys.map((item) => item.id).join(','))
        .assertEqual(english.rows[1].keys.map((item) => item.id).join(','));
      expect(chinese.rows[2].keys.slice(1).map((item) => item.id).join(','))
        .assertEqual(english.rows[2].keys.slice(1).map((item) => item.id).join(','));
    });

    it('mapsEveryReferenceUpperDeckActionToLongPressAndSwipeUp', 0, () => {
      const context = mapper().mapValues(CATALOG.patternText, CATALOG.enterDone);
      const layout = createStage10KeyboardLayout(
        KeyboardMode.CHINESE,
        context,
        ShiftState.LOWERCASE
      );
      expect(layout.rows[0].keys.map((item) => item.upperLabel ?? '').join(''))
        .assertEqual('1234567890');
      expect(layout.rows[1].keys.map((item) => item.upperLabel ?? '').join(''))
        .assertEqual('全选*/;!-#+@');
      expect(layout.rows[2].keys.slice(1, 8).map((item) => item.upperLabel ?? '').join(''))
        .assertEqual('万能剪切复制粘贴_`：');

      const upperActions: KeyboardActionType[] = [
        KeyboardActionType.SELECT_ALL,
        KeyboardActionType.UNIVERSAL_KEY,
        KeyboardActionType.CUT,
        KeyboardActionType.COPY,
        KeyboardActionType.PASTE
      ];
      const keys: KeyboardKeySpec[] = [
        layout.rows[1].keys[0],
        layout.rows[2].keys[1],
        layout.rows[2].keys[2],
        layout.rows[2].keys[3],
        layout.rows[2].keys[4]
      ];
      keys.forEach((item: KeyboardKeySpec, index: number): void => {
        expect(item.longPressAction?.type).assertEqual(upperActions[index]);
        expect(item.swipeUpAction?.type).assertEqual(upperActions[index]);
      });

      const literalUpperDeck: KeyboardKeySpec[] = [];
      layout.rows.forEach((row): void => {
        row.keys.forEach((item: KeyboardKeySpec): void => {
          if (item.longPressAction?.type === KeyboardActionType.CHARACTER) {
            literalUpperDeck.push(item);
          }
        });
      });
      expect(literalUpperDeck.length > 0).assertTrue();
      literalUpperDeck.forEach((item: KeyboardKeySpec): void => {
        expect(item.longPressAction?.literal === true).assertTrue();
        expect(item.swipeUpAction?.literal === true).assertTrue();
        expect(item.longPressAction?.character).assertEqual(item.upperLabel);
      });
    });

    it('keepsAllChineseLetterLabelsUppercaseAndActionsLowercaseInEveryChineseState', 0, () => {
      const context = mapper().mapValues(CATALOG.patternText, CATALOG.enterDone);
      const expectedUpperRows: string[] = ['QWERTYUIOP', 'ASDFGHJKL', 'ZXCVBNM'];
      const expectedLowerRows: string[] = ['qwertyuiop', 'asdfghjkl', 'zxcvbnm'];
      const layouts = [
        createStage10KeyboardLayout(KeyboardMode.CHINESE, context, ShiftState.LOWERCASE, '', false),
        createStage10KeyboardLayout(KeyboardMode.CHINESE, context, ShiftState.CAPS_LOCK, '', true),
        createStage10KeyboardLayout(KeyboardMode.CHINESE, context, ShiftState.ONE_SHOT_UPPERCASE, 'ni', false)
      ];

      layouts.forEach((layout): void => {
        expectedUpperRows.forEach((expectedLabels: string, rowIndex: number): void => {
          const letters = layout.rows[rowIndex].keys
            .filter((item) => item.action.type === KeyboardActionType.LETTER);
          expect(letters.map((item) => item.label).join('')).assertEqual(expectedLabels);
          expect(letters.map((item) => item.action.letter).join('')).assertEqual(expectedLowerRows[rowIndex]);
          letters.forEach((item): void => {
            expect(item.id).assertEqual(`letter-${item.action.letter}`);
            expect(item.previewEnabled).assertTrue();
            expect(item.accessibilityLabel.indexOf(`字母 ${item.label}`)).assertEqual(0);
          });
        });
      });
    });

    it('normalizesAnUppercaseChineseKeyActionBeforeEngineAndRawInput', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const engine = new Stage10FakeEngineCoordinator();
      const controller = new InputSessionController(store, ime, engine);
      store.markSessionStarted();
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternText, CATALOG.enterDone));

      const result = await controller.insertLetter('N');
      expect(result.success).assertTrue();
      expect(engine.processedKeys.join('')).assertEqual('n');
      expect(store.getSnapshot().rawInput).assertEqual('n');
      expect(ime.compatibleTexts[0]).assertEqual('n');
    });

    it('showsChineseShiftOnlyWhileIdleAndEscOnlyWhileComposing', 0, () => {
      const context = mapper().mapValues(CATALOG.patternText, CATALOG.enterDone);
      const shift = createStage10KeyboardLayout(
        KeyboardMode.CHINESE,
        context,
        ShiftState.LOWERCASE,
        '',
        true
      );
      const segment = createStage10KeyboardLayout(
        KeyboardMode.CHINESE,
        context,
        ShiftState.LOWERCASE,
        'ni',
        false
      );
      const idleShiftKey = shift.rows[2].keys[0];
      const composingEscapeKey = segment.rows[2].keys[0];
      expect(idleShiftKey.id).assertEqual('shift');
      expect(composingEscapeKey.id).assertEqual('escape');
      expect(idleShiftKey.weight).assertEqual(composingEscapeKey.weight);
      expect(shift.rows[2].keys.slice(1).map((item) => item.id).join(','))
        .assertEqual(segment.rows[2].keys.slice(1).map((item) => item.id).join(','));
      expect(idleShiftKey.action.type).assertEqual(KeyboardActionType.TOGGLE_CHINESE_CAPS_LOCK);
      expect(idleShiftKey.active).assertTrue();
      expect(idleShiftKey.accessibilityLabel).assertEqual('关闭大写直输');
      expect(composingEscapeKey.action.type).assertEqual(KeyboardActionType.CANCEL_COMPOSITION);
      expect(composingEscapeKey.label).assertEqual('Esc');
      expect(composingEscapeKey.active).assertFalse();
    });

    it('createsTheReference18KeyRowsInQwertyOrderWithDirectLetterTargets', 0, () => {
      const context = mapper().mapValues(CATALOG.patternText, CATALOG.enterSearch);
      const layout = createStage10KeyboardLayout(
        KeyboardMode.CHINESE,
        context,
        ShiftState.LOWERCASE,
        '',
        false,
        false,
        ShuangpinKeyboardLayout.EIGHTEEN_KEY
      );
      expect(layout.rows.length).assertEqual(4);
      expect(layout.rows[0].keys.map((item) => item.label).join('|'))
        .assertEqual('Q|W E|R T|Y|U|I O|P');
      expect(layout.rows[1].keys.map((item) => item.label).join('|'))
        .assertEqual('A|S D|F G|H|J K|L');
      expect(layout.rows[2].keys.map((item) => item.label).join('|'))
        .assertEqual('⇧|Z|X C|V|B N|M|删除');
      expect(layout.rows[0].keys[1].alternatives?.map((item) => item.label).join(','))
        .assertEqual('W,E');
      const letters: string[] = [];
      layout.rows.slice(0, 3).forEach((row) => {
        row.keys.forEach((item) => {
          (item.alternatives ?? []).forEach((alternative) => {
            if (alternative.action.type === KeyboardActionType.LETTER) {
              letters.push(alternative.action.letter ?? '');
            }
          });
        });
      });
      expect(letters.join('')).assertEqual('qwertyuiopasdfghjklzxcvbnm');
      expect(layout.rows[2].keys[0].action.type)
        .assertEqual(KeyboardActionType.TOGGLE_CHINESE_CAPS_LOCK);
      const composingLayout = createStage10KeyboardLayout(
        KeyboardMode.CHINESE,
        context,
        ShiftState.LOWERCASE,
        'ni',
        false,
        false,
        ShuangpinKeyboardLayout.EIGHTEEN_KEY
      );
      expect(composingLayout.rows[2].keys[0].label).assertEqual('Esc');
      expect(composingLayout.rows[2].keys[0].action.type)
        .assertEqual(KeyboardActionType.CANCEL_COMPOSITION);
      expect(layout.rows[2].keys[6].action.type).assertEqual(KeyboardActionType.DELETE);
      expect(layout.rows[3].keys.map((item) => item.id).join(','))
        .assertEqual('number,punctuation-comma,space,punctuation-period,enter');
      expect(layout.rows[3].keys[2].longPressAction?.type)
        .assertEqual(KeyboardActionType.TOGGLE_LANGUAGE);
      expect(layout.rows[3].keys[2].swipeUpAction?.type)
        .assertEqual(KeyboardActionType.EXPAND_CANDIDATES);
      expect(normalizeShuangpinKeyboardLayout('seventeen_key'))
        .assertEqual(ShuangpinKeyboardLayout.EIGHTEEN_KEY);
      expect(normalizeShuangpinKeyboardLayout('eighteen_key'))
        .assertEqual(ShuangpinKeyboardLayout.EIGHTEEN_KEY);
      expect(normalizeShuangpinKeyboardLayout('unknown'))
        .assertEqual(ShuangpinKeyboardLayout.TWENTY_SIX_KEY);
    });

    it('usesABaselineIndependentCenteredVectorForTheHideAction', 0, () => {
      expect(KEYBOARD_STATUS_BAR_LAYOUT.actionIconSize).assertEqual(24);
    });

    it('keepsTextBottomActionsInStandardOrderWithoutHidePlaceholder', 0, () => {
      const context = mapper().mapValues(CATALOG.patternText, CATALOG.enterSearch);
      [KeyboardMode.CHINESE, KeyboardMode.ENGLISH].forEach((mode: KeyboardMode): void => {
        const layout = createStage10KeyboardLayout(mode, context, ShiftState.LOWERCASE);
        const bottom = layout.rows[layout.rows.length - 1].keys;
        expect(bottom.map((item) => item.id).join(','))
          .assertEqual('number,punctuation-comma,space,punctuation-period,enter');
        expect(bottom.map((item) => item.action.type).join(','))
          .assertEqual([
            KeyboardActionType.TOGGLE_NUMBER,
            mode === KeyboardMode.CHINESE
              ? KeyboardActionType.THIRD_CANDIDATE_OR_COMMA
              : KeyboardActionType.CHARACTER,
            KeyboardActionType.SPACE,
            mode === KeyboardMode.CHINESE
              ? KeyboardActionType.SECOND_CANDIDATE_OR_PERIOD
              : KeyboardActionType.CHARACTER,
            KeyboardActionType.ENTER
          ].join(','));
        expect(bottom.filter((item) => item.action.type === KeyboardActionType.SPACE).length).assertEqual(1);
        expect(bottom.filter((item) => item.action.type === KeyboardActionType.DELETE).length).assertEqual(0);
        expect(bottom.filter((item) => item.action.type === KeyboardActionType.HIDE_KEYBOARD).length).assertEqual(0);
        expect(bottom[2].longPressAction?.type).assertEqual(KeyboardActionType.TOGGLE_LANGUAGE);
        expect(bottom[2].swipeUpAction?.type).assertEqual(KeyboardActionType.EXPAND_CANDIDATES);
        expect(bottom[2].weight > bottom[4].weight).assertTrue();
      });
    });

    it('removesBottomHideFromEveryProductionKeyboardVariant', 0, () => {
      const target = mapper();
      const normal = target.mapValues(CATALOG.patternText, CATALOG.enterDone);
      const layouts = [
        createStage10KeyboardLayout(KeyboardMode.CHINESE, normal, ShiftState.LOWERCASE),
        createStage10KeyboardLayout(KeyboardMode.ENGLISH, normal, ShiftState.LOWERCASE),
        createStage10KeyboardLayout(
          KeyboardMode.ENGLISH,
          target.mapValues(CATALOG.patternPassword, CATALOG.enterDone),
          ShiftState.LOWERCASE
        ),
        createStage10KeyboardLayout(
          KeyboardMode.NUMBER,
          target.mapValues(CATALOG.patternNumber, CATALOG.enterDone),
          ShiftState.LOWERCASE
        ),
        createStage10KeyboardLayout(
          KeyboardMode.NUMBER,
          target.mapValues(CATALOG.patternNumberDecimal, CATALOG.enterDone),
          ShiftState.LOWERCASE
        ),
        createStage10KeyboardLayout(
          KeyboardMode.PHONE,
          target.mapValues(CATALOG.patternPhone, CATALOG.enterDone),
          ShiftState.LOWERCASE
        ),
        createStage10KeyboardLayout(
          KeyboardMode.ENGLISH,
          target.mapValues(CATALOG.patternEmail, CATALOG.enterNext),
          ShiftState.LOWERCASE
        ),
        createStage10KeyboardLayout(
          KeyboardMode.ENGLISH,
          target.mapValues(CATALOG.patternUri, CATALOG.enterGo),
          ShiftState.LOWERCASE
        ),
        createStage10KeyboardLayout(
          KeyboardMode.ENGLISH,
          target.mapValues(CATALOG.patternText, CATALOG.enterSearch),
          ShiftState.LOWERCASE
        ),
        createStage10KeyboardLayout(
          KeyboardMode.ENGLISH,
          target.mapValues(CATALOG.patternText, CATALOG.enterNewline),
          ShiftState.LOWERCASE
        ),
        createStage10KeyboardLayout(KeyboardMode.SYMBOL, normal, ShiftState.LOWERCASE)
      ];

      layouts.forEach((layout): void => {
        const ids = layout.rows.map((row) => row.keys.map((item) => item.id)).reduce(
          (all: string[], rowIds: string[]) => all.concat(rowIds), [] as string[]
        );
        const actions = layout.rows.map((row) => row.keys.map((item) => item.action.type)).reduce(
          (all: KeyboardActionType[], rowActions: KeyboardActionType[]) => all.concat(rowActions),
          [] as KeyboardActionType[]
        );
        expect(ids.filter((id: string) => id === 'hide').length).assertEqual(0);
        expect(actions.filter((action: KeyboardActionType) =>
          action === KeyboardActionType.HIDE_KEYBOARD).length).assertEqual(0);
      });
    });

    it('keepsHideActionInOneFixedAccessibleStatusBarRegion', 0, () => {
      expect(KEYBOARD_STATUS_BAR_LAYOUT.contentLayoutWeight).assertEqual(1);
      expect(KEYBOARD_STATUS_BAR_LAYOUT.actionScrollable).assertFalse();
      expect(KEYBOARD_STATUS_BAR_LAYOUT.actionId).assertEqual('status-bar-hide-keyboard');
      expect(KEYBOARD_STATUS_BAR_LAYOUT.actionAccessibilityText).assertEqual('收起键盘');
      expect(KEYBOARD_STATUS_BAR_LAYOUT.action.type).assertEqual(KeyboardActionType.HIDE_KEYBOARD);
      expect(PORTRAIT_METRICS.statusBarActionWidth >= 44).assertTrue();
      expect(LANDSCAPE_METRICS.statusBarActionWidth >= 44).assertTrue();
    });

    it('createsUniqueTextKeyIdsForPhoneLandscapeAndTabletStrategies', 0, () => {
      const context = mapper().mapValues(CATALOG.patternText, CATALOG.enterDone);
      const screens = [
        createScreenMetrics({ widthPx: 1080, heightPx: 2340, densityPixels: 3 }, false),
        createScreenMetrics({ widthPx: 2340, heightPx: 1080, densityPixels: 3 }, true),
        createScreenMetrics({ widthPx: 1920, heightPx: 2880, densityPixels: 2 }, false),
        createScreenMetrics({ widthPx: 2880, heightPx: 1920, densityPixels: 2 }, true)
      ];
      screens.forEach((screen): void => {
        const metrics = calculateDynamicMetrics(screen);
        expect(metrics.secondRowInset > 0).assertTrue();
        [KeyboardMode.CHINESE, KeyboardMode.ENGLISH].forEach((mode: KeyboardMode): void => {
          const layout = createStage10KeyboardLayout(mode, context, ShiftState.LOWERCASE);
          const ids = layout.rows.map((row) => row.keys.map((item) => item.id)).reduce(
            (all: string[], rowIds: string[]) => all.concat(rowIds), [] as string[]
          );
          expect(new Set<string>(ids).size).assertEqual(ids.length);
          expect(ids.filter((id: string) => id === 'delete').length).assertEqual(1);
          expect(ids.filter((id: string) => id === 'space').length).assertEqual(1);
        });
      });
    });

    it('classifiesPhoneAndTabletMetricsWithoutModelNames', 0, () => {
      const portrait = calculateDynamicMetrics(
        createScreenMetrics({ widthPx: 1080, heightPx: 2340, densityPixels: 3 }, false)
      );
      const landscape = calculateDynamicMetrics(
        createScreenMetrics({ widthPx: 2340, heightPx: 1080, densityPixels: 3 }, true)
      );
      const tablet = calculateDynamicMetrics(
        createScreenMetrics({ widthPx: 1920, heightPx: 2880, densityPixels: 2 }, false)
      );
      expect(portrait.layoutForm).assertEqual(KeyboardLayoutForm.PHONE_PORTRAIT);
      expect(landscape.layoutForm).assertEqual(KeyboardLayoutForm.PHONE_LANDSCAPE);
      expect(tablet.layoutForm).assertEqual(KeyboardLayoutForm.TABLET);
      expect(tablet.horizontalPadding > portrait.horizontalPadding).assertTrue();
    });

    it('numberAndDecimalBottomRowsUseEqualGridWeights', 0, () => {
      const number = mapper().mapValues(CATALOG.patternNumber, CATALOG.enterDone);
      const numberLayout = createStage10KeyboardLayout(KeyboardMode.NUMBER, number, ShiftState.LOWERCASE);
      const numberGridRow = numberLayout.rows[3].keys;
      expect(numberGridRow.length).assertEqual(2);
      expect(numberGridRow[0].weight).assertEqual(numberGridRow[1].weight);
      const numberActions = numberLayout.rows[4].keys;
      expect(numberActions.length).assertEqual(1);
      expect(numberActions[0].action.type).assertEqual(KeyboardActionType.ENTER);
      expect(numberActions[0].weight).assertEqual(KEY_WEIGHTS.NUMERIC_ONLY_ENTER);

      const decimal = mapper().mapValues(CATALOG.patternNumberDecimal, CATALOG.enterDone);
      const decimalLayout = createStage10KeyboardLayout(KeyboardMode.NUMBER, decimal, ShiftState.LOWERCASE);
      const decimalGridRow = decimalLayout.rows[3].keys;
      expect(decimalGridRow.length).assertEqual(3);
      expect(decimalGridRow[0].weight).assertEqual(decimalGridRow[1].weight);
      expect(decimalGridRow[1].weight).assertEqual(decimalGridRow[2].weight);
      expect(decimalGridRow[0].weight).assertEqual(decimalLayout.rows[2].keys[0].weight);
      const decimalActions = decimalLayout.rows[4].keys;
      expect(decimalActions.length).assertEqual(1);
      expect(decimalActions[0].weight).assertEqual(KEY_WEIGHTS.NUMERIC_ONLY_ENTER);

      const email = mapper().mapValues(CATALOG.patternEmail, CATALOG.enterDone);
      const emailNumberLayout = createStage10KeyboardLayout(
        KeyboardMode.NUMBER,
        email,
        ShiftState.LOWERCASE
      );
      expect(emailNumberLayout.rows.length).assertEqual(4);
      emailNumberLayout.rows.forEach((row): void => {
        expect(row.keys.length).assertEqual(5);
      });
      expect(emailNumberLayout.rows[0].keys.map((item) => item.label).join(','))
        .assertEqual('+,1,2,3,/');
      expect(emailNumberLayout.rows[1].keys.map((item) => item.label).join(','))
        .assertEqual('-,4,5,6,=');
      expect(emailNumberLayout.rows[2].keys.map((item) => item.label).join(','))
        .assertEqual('*,7,8,9,删除');
      expect(emailNumberLayout.rows[3].keys.map((item) => item.label).join(','))
        .assertEqual('返回,,,0,.,完成');
      expect(emailNumberLayout.rows[0].keys[0].upperLabel).assertEqual('@');
      expect(emailNumberLayout.rows[3].keys[2].upperLabel).assertEqual('$');
    });

    it('phoneLayoutContainsRequiredDirectKeys', 0, () => {
      const context = mapper().mapValues(CATALOG.patternPhone, CATALOG.enterDone);
      const layout = createStage10KeyboardLayout(KeyboardMode.PHONE, context, ShiftState.LOWERCASE);
      const labels = layout.rows.map((row) => row.keys.map((item) => item.label).join('')).join('');
      expect(labels).assertContain('0');
      expect(labels).assertContain('*');
      expect(labels).assertContain('#');
      expect(labels).assertContain('+');
      expect(labels).assertContain('删除');
    });

    it('emailAndUrlLayoutsExposeConvenientSymbols', 0, () => {
      const email = mapper().mapValues(CATALOG.patternEmail, CATALOG.enterNext);
      const emailLayout = createStage10KeyboardLayout(KeyboardMode.ENGLISH, email, ShiftState.LOWERCASE);
      const emailLabels = emailLayout.rows.map((row) => row.keys.map((item) => item.label).join('')).join('');
      expect(emailLabels).assertContain('@');
      expect(emailLabels).assertContain('.');

      const url = mapper().mapValues(CATALOG.patternUri, CATALOG.enterGo);
      const urlLayout = createStage10KeyboardLayout(KeyboardMode.ENGLISH, url, ShiftState.LOWERCASE);
      const urlLabels = urlLayout.rows.map((row) => row.keys.map((item) => item.label).join('')).join('');
      expect(urlLabels).assertContain('.');
      expect(urlLabels).assertContain('/');
      expect(urlLabels).assertContain(':');
      expect(urlLabels).assertContain('-');
      expect(urlLabels).assertContain('_');
    });

    it('decimalAndShiftLabelsFollowState', 0, () => {
      const decimal = mapper().mapValues(CATALOG.patternNumberDecimal, CATALOG.enterDone);
      const numberLayout = createStage10KeyboardLayout(KeyboardMode.NUMBER, decimal, ShiftState.LOWERCASE);
      const numberLabels = numberLayout.rows.map((row) => row.keys.map((item) => item.label).join('')).join('');
      expect(numberLabels).assertContain('.');

      const email = mapper().mapValues(CATALOG.patternEmail, CATALOG.enterDone);
      const lower = createStage10KeyboardLayout(KeyboardMode.ENGLISH, email, ShiftState.LOWERCASE);
      const oneShot = createStage10KeyboardLayout(KeyboardMode.ENGLISH, email, ShiftState.ONE_SHOT_UPPERCASE);
      const upper = createStage10KeyboardLayout(KeyboardMode.ENGLISH, email, ShiftState.CAPS_LOCK);
      expect(lower.rows[0].keys[0].label).assertEqual('q');
      expect(oneShot.rows[0].keys[0].label).assertEqual('Q');
      expect(upper.rows[0].keys[0].label).assertEqual('Q');
      expect(upper.rows[2].keys[0].label).assertEqual('⇧锁');
      expect(lower.rows[2].keys[0].action.type).assertEqual(KeyboardActionType.SHIFT);
      expect(upper.rows[2].keys[8].action.type).assertEqual(KeyboardActionType.DELETE);
    });
  });

  describe('stage10PrivacyLearningAndEnter', () => {
    it('userModeSwitchCommitsFirstCandidateButEditorSwitchDoesNotLeakComposition', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const engine = new Stage10FakeEngineCoordinator();
      const controller = new InputSessionController(store, ime, engine);
      store.markSessionStarted();
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternText, CATALOG.enterDone));
      await controller.insertLetter('n');
      await controller.toggleSymbolMode();
      expect(engine.selectCount).assertEqual(1);
      expect(ime.insertedTexts[0]).assertEqual('你');
      expect(store.getSnapshot().keyboardMode).assertEqual(KeyboardMode.SYMBOL);
      expect(store.getSnapshot().candidates.length).assertEqual(0);

      store.switchKeyboardMode(KeyboardMode.CHINESE, true);
      await controller.insertLetter('n');
      const insertCountBeforeEditorSwitch = ime.insertedTexts.length;
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternEmail, CATALOG.enterNext));
      expect(ime.insertedTexts.length).assertEqual(insertCountBeforeEditorSwitch);
      expect(store.getSnapshot().rawInput).assertEqual('');
      expect(store.getSnapshot().keyboardMode).assertEqual(KeyboardMode.ENGLISH);
    });

    it('passwordDisablesLearningAndNeverCallsCandidateEngine', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const engine = new Stage10FakeEngineCoordinator();
      const controller = new InputSessionController(store, ime, engine);
      store.markSessionStarted();
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternPassword, CATALOG.enterDone));
      await controller.insertLetter('a');
      const candidateResult = await controller.commitCandidate(0);
      expect(engine.sessionLearningValues[engine.sessionLearningValues.length - 1]).assertFalse();
      expect(engine.processCount).assertEqual(0);
      expect(engine.selectCount).assertEqual(0);
      expect(candidateResult.success).assertFalse();
      expect(ime.insertedTexts[0]).assertEqual('a');
      expect(engine.globalLearningChangeCount).assertEqual(0);
    });

    it('leavingPasswordRestoresLearningAndChineseCandidateFlow', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const engine = new Stage10FakeEngineCoordinator();
      const controller = new InputSessionController(store, ime, engine);
      store.markSessionStarted();
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternPassword, CATALOG.enterDone));
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternText, CATALOG.enterDone));
      await controller.insertLetter('n');
      await controller.commitCandidate(0);
      expect(engine.sessionLearningValues[engine.sessionLearningValues.length - 1]).assertTrue();
      expect(engine.processCount).assertEqual(1);
      expect(engine.selectCount).assertEqual(1);
      expect(ime.insertedTexts[0]).assertEqual('你');
      expect(engine.globalLearningChangeCount).assertEqual(0);
    });

    it('searchAndMultilineUseMappedEnterActions', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const engine = new Stage10FakeEngineCoordinator();
      const controller = new InputSessionController(store, ime, engine);
      store.markSessionStarted();
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternText, CATALOG.enterSearch));
      await controller.sendEnter();
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternText, CATALOG.enterNewline));
      await controller.sendEnter();
      expect(ime.enterActions[0]).assertEqual(EnterAction.SEARCH);
      expect(ime.enterActions[1]).assertEqual(EnterAction.ENTER);
    });
  });

  describe('chineseEditorPreviewLifecycle', () => {
    it('unsupportedPreviewComposesInCandidateBarAndCommitsDirectly', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const engine = new Stage10FakeEngineCoordinator();
      const controller = new InputSessionController(store, ime, engine);
      store.markSessionStarted();
      controller.applyEditorContext(
        mapper().mapValues(CATALOG.patternText, CATALOG.enterSearch, undefined, false)
      );

      await controller.insertLetter('n');
      await controller.insertLetter('i');
      expect(ime.previewTexts.length).assertEqual(0);
      expect(ime.compatibleTexts[0]).assertEqual('n');
      expect(ime.compatibleTexts[1]).assertEqual('ni');
      expect(store.getSnapshot().rawInput).assertEqual('ni');
      expect(store.getSnapshot().cursorPreeditVisible === true).assertFalse();
      expect(store.getSnapshot().candidates.length > 0).assertTrue();

      const committed = await controller.commitCandidate(0);
      expect(committed.success).assertTrue();
      expect(ime.insertedTexts.length).assertEqual(1);
      expect(ime.insertedTexts[0]).assertEqual('你');
      expect(engine.selectCount).assertEqual(1);
      expect(store.getSnapshot().rawInput).assertEqual('');
    });

    it('updatesEveryLetterAndDeletesInCandidateBarWithoutCommittedLetters', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const controller = new InputSessionController(store, ime, new Stage10FakeEngineCoordinator());
      store.markSessionStarted();
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternText, CATALOG.enterDone));

      await controller.insertLetter('n');
      await controller.insertLetter('i');
      expect(ime.compatibleTexts[0]).assertEqual('n');
      expect(ime.compatibleTexts[1]).assertEqual('ni');
      expect(ime.insertedTexts.length).assertEqual(0);
      expect(store.getSnapshot().rawInput).assertEqual('ni');
      expect(store.getSnapshot().cursorPreeditVisible === true).assertFalse();
      expect(store.getSnapshot().candidateBarVisible).assertTrue();

      await controller.deleteBackward();
      expect(ime.compatibleTexts[2]).assertEqual('n');
      expect(store.getSnapshot().rawInput).assertEqual('n');
      await controller.deleteBackward();
      expect(ime.compatibleTexts[3]).assertEqual('');
      expect(store.getSnapshot().rawInput).assertEqual('');
      expect(store.getSnapshot().cursorPreeditVisible === true).assertFalse();
      expect(store.getSnapshot().candidateBarVisible).assertTrue();
      expect(ime.deleteCount).assertEqual(0);
      await controller.deleteBackward();
      expect(ime.deleteCount).assertEqual(1);
    });

    it('physicalPunctuationCommitsTopCandidateOnceThenInsertsAndDeletesTheSuffix', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const controller = new InputSessionController(store, ime, new Stage10FakeEngineCoordinator());
      store.markSessionStarted();
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternText, CATALOG.enterDone));

      await controller.insertLetter('a');
      expect(store.getSnapshot().rawInput).assertEqual('a');
      await controller.insertPhysicalPunctuation('，');
      expect(ime.insertedTexts.join('|')).assertEqual('你|，');
      expect(store.getSnapshot().rawInput).assertEqual('');

      await controller.deletePhysicalPunctuationSuffix();
      expect(ime.deleteCount).assertEqual(1);
      expect(store.getSnapshot().rawInput).assertEqual('');

      await controller.deleteBackward();
      expect(store.getSnapshot().rawInput).assertEqual('');
      expect(ime.deleteCount).assertEqual(2);
    });

    it('deletesCommittedTextAndDirectInputModesThroughImeService', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const controller = new InputSessionController(store, ime, new Stage10FakeEngineCoordinator());
      const target = mapper();
      store.markSessionStarted();
      controller.applyEditorContext(target.mapValues(CATALOG.patternText, CATALOG.enterDone));

      await controller.insertLetter('n');
      await controller.commitCandidate(0);
      expect(store.getSnapshot().rawInput).assertEqual('');
      await controller.deleteBackward();

      store.switchKeyboardMode(KeyboardMode.ENGLISH, true);
      await controller.deleteBackward();
      controller.applyEditorContext(target.mapValues(CATALOG.patternNumber, CATALOG.enterDone));
      await controller.deleteBackward();
      controller.applyEditorContext(target.mapValues(CATALOG.patternNumberDecimal, CATALOG.enterDone));
      await controller.deleteBackward();
      controller.applyEditorContext(target.mapValues(CATALOG.patternPhone, CATALOG.enterDone));
      await controller.deleteBackward();
      controller.applyEditorContext(target.mapValues(CATALOG.patternEmail, CATALOG.enterNext));
      await controller.deleteBackward();
      controller.applyEditorContext(target.mapValues(CATALOG.patternUri, CATALOG.enterGo));
      await controller.deleteBackward();
      controller.applyEditorContext(target.mapValues(CATALOG.patternText, CATALOG.enterSearch));
      await controller.deleteBackward();
      controller.applyEditorContext(target.mapValues(CATALOG.patternText, CATALOG.enterNewline));
      await controller.deleteBackward();

      expect(ime.deleteCount).assertEqual(9);
    });

    it('candidateSpaceAndEnterCommitPreviewExactlyOnce', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const engine = new Stage10FakeEngineCoordinator();
      const controller = new InputSessionController(store, ime, engine);
      store.markSessionStarted();
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternText, CATALOG.enterSearch));

      await controller.insertLetter('n');
      await controller.insertLetter('i');
      await controller.commitCandidate(0);
      expect(ime.insertedTexts.length).assertEqual(1);
      expect(ime.insertedTexts[0]).assertEqual('你');
      expect(engine.selectCount).assertEqual(1);
      expect(store.getSnapshot().rawInput).assertEqual('');

      await controller.insertLetter('n');
      await controller.insertSpace();
      expect(ime.insertedTexts.length).assertEqual(2);
      expect(ime.insertedTexts[1]).assertEqual('你');

      await controller.insertLetter('n');
      await controller.sendEnter();
      expect(ime.insertedTexts.length).assertEqual(3);
      expect(ime.insertedTexts[2]).assertEqual('你');
      expect(ime.enterActions[0]).assertEqual(EnterAction.SEARCH);
    });

    it('languageSwitchEndsCompositionAndRestrictedEditorsNeverPreview', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const controller = new InputSessionController(store, ime, new Stage10FakeEngineCoordinator());
      store.markSessionStarted();
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternText, CATALOG.enterDone));
      await controller.insertLetter('n');
      await controller.toggleLanguageMode();
      expect(store.getSnapshot().keyboardMode).assertEqual(KeyboardMode.ENGLISH);
      expect(store.getSnapshot().rawInput).assertEqual('');
      expect(ime.insertedTexts[0]).assertEqual('你');

      const previewCount = ime.previewTexts.length;
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternPassword, CATALOG.enterDone));
      await controller.insertLetter('a');
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternNumber, CATALOG.enterDone));
      await controller.insertCharacter('1');
      expect(ime.previewTexts.length).assertEqual(previewCount);
      expect(ime.insertedTexts[1]).assertEqual('a');
      expect(ime.insertedTexts[2]).assertEqual('1');
    });

    it('languageSwitchFromATransientPanelUsesTheUnderlyingTextMode', 0, async () => {
      const store = new InputSessionStore();
      const controller = new InputSessionController(
        store,
        new Stage10FakeImeService(),
        new Stage10FakeEngineCoordinator()
      );
      store.markSessionStarted();
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternText, CATALOG.enterDone));

      store.switchKeyboardMode(KeyboardMode.ENGLISH);
      await controller.toggleNumberMode();
      expect(store.getSnapshot().modeBeforeTransient).assertEqual(KeyboardMode.ENGLISH);
      await controller.toggleLanguageMode();
      expect(store.getSnapshot().keyboardMode).assertEqual(KeyboardMode.CHINESE);

      await controller.toggleSymbolMode();
      expect(store.getSnapshot().modeBeforeTransient).assertEqual(KeyboardMode.CHINESE);
      await controller.toggleLanguageMode();
      expect(store.getSnapshot().keyboardMode).assertEqual(KeyboardMode.ENGLISH);
    });

    it('stalePreviewCompletionCannotUpdateNewEditor', 0, async () => {
      const store = new InputSessionStore();
      const ime = new DeferredPreviewImeService();
      const controller = new InputSessionController(store, ime, new Stage10FakeEngineCoordinator());
      store.markSessionStarted();
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternText, CATALOG.enterDone));
      const gate = ime.gateNextPreview();

      const pending = controller.insertLetter('n');
      await nextTask();
      store.advanceSessionGeneration();
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternPassword, CATALOG.enterDone));
      gate.resolve(true);
      const result = await pending;

      expect(result.success).assertFalse();
      expect(store.getSnapshot().keyboardMode).assertEqual(KeyboardMode.ENGLISH);
      expect(store.getSnapshot().rawInput).assertEqual('');
      expect(ime.insertedTexts.length).assertEqual(0);
    });

    it('candidateBarUpdateFailureHasNoInsertOrDeleteFallback', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const controller = new InputSessionController(store, ime, new Stage10FakeEngineCoordinator());
      store.markSessionStarted();
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternText, CATALOG.enterDone));
      ime.failNextPreview = true;

      const result = await controller.insertLetter('n');
      expect(result.success).assertFalse();
      expect(ime.compatibleTexts.length).assertEqual(1);
      expect(ime.insertedTexts.length).assertEqual(0);
      expect(ime.deleteCount).assertEqual(0);
      expect(store.getSnapshot().rawInput).assertEqual('');
    });

    it('editorDiscardTypingTextClearsLocalCompositionWithoutWritingItBack', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const engine = new Stage10FakeEngineCoordinator();
      const controller = new InputSessionController(store, ime, engine);
      store.markSessionStarted();
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternText, CATALOG.enterDone));
      await controller.insertLetter('n');

      const previewWritesBeforeDiscard = ime.previewTexts.length;
      controller.handleDiscardTypingText();

      expect(store.getSnapshot().rawInput).assertEqual('');
      expect(store.getSnapshot().candidates.length).assertEqual(0);
      expect(ime.resetPreviewStateCount).assertEqual(2);
      expect(ime.previewTexts.length).assertEqual(previewWritesBeforeDiscard);
    });

    it('silentEditorClearStartsTheNextLetterAsAFreshComposition', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const engine = new Stage10FakeEngineCoordinator();
      const controller = new InputSessionController(store, ime, engine);
      store.markSessionStarted();
      controller.applyEditorContext(mapper().mapValues(
        CATALOG.patternText,
        CATALOG.enterSearch,
        undefined,
        false
      ));
      await controller.insertLetter('e');
      ime.previewTextAttached = false;

      const result = await controller.insertLetter('b');

      expect(result.success).assertTrue();
      expect(store.getSnapshot().rawInput).assertEqual('b');
      expect(store.getSnapshot().lastErrorCode).assertEqual(ImeErrorCode.SUCCESS);
      expect(ime.compatibleTexts[ime.compatibleTexts.length - 1]).assertEqual('b');
    });

    it('silentEditorClearConsumesDeleteWithoutDeletingUnrelatedText', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const engine = new Stage10FakeEngineCoordinator();
      const controller = new InputSessionController(store, ime, engine);
      store.markSessionStarted();
      controller.applyEditorContext(mapper().mapValues(
        CATALOG.patternText,
        CATALOG.enterSearch,
        undefined,
        false
      ));
      await controller.insertLetter('e');
      ime.previewTextAttached = false;

      const result = await controller.deleteBackward();

      expect(result.success).assertTrue();
      expect(store.getSnapshot().rawInput).assertEqual('');
      expect(store.getSnapshot().lastErrorCode).assertEqual(ImeErrorCode.SUCCESS);
      expect(ime.deleteCount).assertEqual(0);
    });

    it('rapidHideRunsCleanupModelFlushAndSystemHideOnlyOnce', 0, async () => {
      const store = new InputSessionStore();
      const ime = new Stage10FakeImeService();
      const engine = new Stage10FakeEngineCoordinator();
      const controller = new InputSessionController(store, ime, engine);
      store.markSessionStarted();
      store.markKeyboardVisible();
      controller.applyEditorContext(mapper().mapValues(CATALOG.patternText, CATALOG.enterDone));
      await controller.insertLetter('n');
      const resetCountBeforeHide = engine.resetCount;

      const results = await Promise.all([controller.hideKeyboard(), controller.hideKeyboard()]);

      expect(results[0].success).assertTrue();
      expect(results[1].success).assertTrue();
      expect(ime.hideCount).assertEqual(1);
      expect(ime.clearPreviewCount).assertEqual(1);
      expect(engine.flushUserModelCount).assertEqual(1);
      expect(engine.resetCount - resetCountBeforeHide).assertEqual(1);
      expect(store.getSnapshot().keyboardVisible).assertFalse();
      expect(store.getSnapshot().rawInput).assertEqual('');
      expect(store.getSnapshot().candidates.length).assertEqual(0);
    });
  });
}
