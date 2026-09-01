import { describe, it, expect } from '@ohos/hypium';
import { inputMethodEngine } from '@kit.IMEKit';
import {
  createT9PinyinDigitAction,
  KeyboardActionType,
  KeyboardMode
} from '../main/ets/domain/keyboard/KeyboardAction';
import { ImeErrorCode } from '../main/ets/common/error/ImeError';
import { KeyboardController } from '../main/ets/application/KeyboardController';
import { EngineCoordinator } from '../main/ets/application/EngineCoordinator';
import { InputSessionController, ImeInputService } from '../main/ets/application/InputSessionController';
import { InputSessionStore } from '../main/ets/state/InputSessionStore';
import {
  CodeTableCategoryConfig,
  CompositionResult,
  EngineConfig,
  NativeEngineGatewayContract,
  UserLexiconDocument,
  UserModelStatus
} from '../main/ets/infrastructure/native/NativeEngineTypes';
import { QWERTY_KEY_ROWS } from '../main/ets/presentation/keyboard/KeyboardLayout';
import { createUnknownEditorContext } from '../main/ets/domain/editor/EditorContext';
import { copyImeSettings, DEFAULT_IME_SETTINGS, ImeSettings } from '../main/ets/domain/settings/ImeSettings';
import { ChineseTextConverter } from '../main/ets/infrastructure/text/ChineseTextConverter';

class FakeImeInputService implements ImeInputService {
  insertedTexts: string[] = [];
  previewTexts: string[] = [];
  previewSupportedValues: boolean[] = [];
  previewAnchorValues: boolean[] = [];
  finishPreviewCount: number = 0;
  clearPreviewCount: number = 0;
  deleteCount: number = 0;
  deleteLineCount: number = 0;
  restoreDeletionCount: number = 0;
  enterCount: number = 0;
  hideCount: number = 0;
  cursorDirections: inputMethodEngine.Direction[] = [];
  failNextPreview: boolean = false;

  async insertText(text: string): Promise<boolean> {
    this.insertedTexts.push(text);
    return true;
  }

  async setPreviewText(
    text: string,
    previewSupported: boolean = true,
    generation: number = 0,
    anchorAfterCandidateCommit: boolean = false
  ): Promise<boolean> {
    this.previewTexts.push(text);
    this.previewSupportedValues.push(previewSupported);
    this.previewAnchorValues.push(anchorAfterCandidateCommit);
    if (this.failNextPreview) {
      this.failNextPreview = false;
      return false;
    }
    return true;
  }

  async commitPreviewText(text: string): Promise<boolean> {
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
    return true;
  }

  resetPreviewState(): void {
  }

  async deleteBackward(count?: number): Promise<boolean> {
    this.deleteCount += count ?? 1;
    return true;
  }

  async deleteCurrentLine(): Promise<boolean> {
    this.deleteLineCount += 1;
    return true;
  }

  async restoreLastDeletion(): Promise<boolean> {
    this.restoreDeletionCount += 1;
    return true;
  }

  async sendEnter(): Promise<boolean> {
    this.enterCount += 1;
    return true;
  }

  async hideKeyboard(): Promise<boolean> {
    this.hideCount += 1;
    return true;
  }

  async moveCursor(direction: inputMethodEngine.Direction): Promise<void> {
    this.cursorDirections.push(direction);
  }
}

class DeferredBoolean {
  private resolver?: (value: boolean) => void;
  readonly promise: Promise<boolean> = new Promise<boolean>((resolve: (value: boolean) => void) => {
    this.resolver = resolve;
  });

  resolve(value: boolean = true): void {
    this.resolver?.(value);
  }
}

class OrderedImeInputService extends FakeImeInputService {
  events: string[] = [];
  failNextInsert: boolean = false;
  private insertGate?: DeferredBoolean;
  private deleteGate?: DeferredBoolean;

  gateNextInsert(): DeferredBoolean {
    const gate = new DeferredBoolean();
    this.insertGate = gate;
    return gate;
  }

  gateNextDelete(): DeferredBoolean {
    const gate = new DeferredBoolean();
    this.deleteGate = gate;
    return gate;
  }

  async insertText(text: string): Promise<boolean> {
    this.events.push(`insert-start:${text}`);
    if (this.failNextInsert) {
      this.failNextInsert = false;
      this.events.push(`insert-failed:${text}`);
      throw new Error('simulated ordered insert failure');
    }
    const gate = this.insertGate;
    this.insertGate = undefined;
    if (gate && !(await gate.promise)) {
      return false;
    }
    this.insertedTexts.push(text);
    this.events.push(`insert-end:${text}`);
    return true;
  }

  async deleteBackward(count?: number): Promise<boolean> {
    this.events.push('delete-start');
    const gate = this.deleteGate;
    this.deleteGate = undefined;
    if (gate && !(await gate.promise)) {
      return false;
    }
    this.deleteCount += count ?? 1;
    this.events.push('delete-end');
    return true;
  }
}

function nextTask(): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, 0);
  });
}

class FakeNativeGateway implements NativeEngineGatewayContract {
  createdCount: number = 0;
  destroyedCount: number = 0;
  processKeys: string[] = [];
  backspaceCount: number = 0;
  resetCount: number = 0;
  loadUserModelPath: string = '';
  flushUserModelCount: number = 0;
  clearUserModelCount: number = 0;
  sessionLearningAllowedValues: boolean[] = [];
  userLearningEnabledValues: boolean[] = [];

  getInterfaceVersion(): number {
    return 11;
  }

  getEngineVersion(): string {
    return '0.0.1-direct-display';
  }

  getNativeBuildInfo(): string {
    return 'abi=test;rustArchiveSha256=test;fingerprint=test';
  }

  createEngine(config: EngineConfig): number {
    if (config.interfaceVersion !== 11 || config.schemeId !== 'xiaohe') {
      throw new Error('bad config');
    }
    this.createdCount += 1;
    return 7;
  }

  destroyEngine(handle: number): void {
    if (handle === 7) {
      this.destroyedCount += 1;
    }
  }

  processKey(handle: number, key: string): CompositionResult {
    this.processKeys.push(key);
    return createCompositionResult(key, key, key === 'q' ? 'incomplete' : 'complete');
  }

  insertSegmentBoundary(handle: number): CompositionResult {
    return createCompositionResult("ni'", "ni'", 'complete');
  }

  backspace(handle: number): CompositionResult {
    this.backspaceCount += 1;
    return createCompositionResult('', '', 'empty');
  }

  reset(handle: number): CompositionResult {
    this.resetCount += 1;
    return createCompositionResult('', '', 'empty');
  }

  changeScheme(handle: number, schemeId: string): CompositionResult {
    return {
      success: false,
      errorCode: ImeErrorCode.INVALID_SCHEME,
      errorMessage: 'invalid scheme',
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

  selectCandidate(handle: number, candidateIndex: number): CompositionResult {
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
      commitText: '你',
      action: null,
      compositionFinished: true
    };
  }

  selectPinyinCombination(_handle: number, _combinationIndex: number): CompositionResult {
    return createCompositionResult('64', 'ni', 'ambiguous');
  }

  nextCandidatePage(handle: number): CompositionResult {
    return createCompositionResult('n', 'n', 'incomplete');
  }

  previousCandidatePage(handle: number): CompositionResult {
    return createCompositionResult('n', 'n', 'incomplete');
  }

  getCodeTableCategoryConfig(_handle: number): CodeTableCategoryConfig {
    return {
      schemaVersion: 1,
      categories: [],
      enabledCategoryIds: []
    };
  }

  setCodeTableCategories(_handle: number, _enabledCategoryIds: string[]): CompositionResult {
    return createCompositionResult('', '', 'empty');
  }

  reloadUserLexicon(_handle: number): CompositionResult {
    return createCompositionResult('', '', 'empty');
  }

  loadUserLexicon(_path: string): UserLexiconDocument {
    return createUserLexiconDocument();
  }

  saveUserLexicon(_path: string, _expectedRevision: string, _content: string): UserLexiconDocument {
    return createUserLexiconDocument();
  }

  setUserModelPath(handle: number, path: string): UserModelStatus {
    this.loadUserModelPath = path;
    return createUserModelStatus(false, true, true, false, 0, '');
  }

  loadUserModel(handle: number): UserModelStatus {
    return createUserModelStatus(true, true, true, false, 0, '');
  }

  flushUserModel(handle: number): UserModelStatus {
    this.flushUserModelCount += 1;
    return createUserModelStatus(true, true, true, false, 0, '');
  }

  clearUserModel(handle: number): UserModelStatus {
    this.clearUserModelCount += 1;
    return createUserModelStatus(true, true, true, false, 0, '');
  }

  setUserLearningEnabled(handle: number, enabled: boolean): UserModelStatus {
    this.userLearningEnabledValues.push(enabled);
    return createUserModelStatus(true, enabled, true, false, 0, '');
  }

  setSessionLearningAllowed(handle: number, allowed: boolean): UserModelStatus {
    this.sessionLearningAllowedValues.push(allowed);
    return createUserModelStatus(true, true, allowed, false, 0, '');
  }

}

class FakeTraditionalConverter implements ChineseTextConverter {
  toTraditional(text: string): string {
    return text === '你' ? '妳' : `繁:${text}`;
  }
}

class TraditionalGateway extends FakeNativeGateway {
  processKey(_handle: number, key: string): CompositionResult {
    this.processKeys.push(key);
    return createCandidateComposition('你');
  }
}

class AsyncNativeGateway extends FakeNativeGateway {
  asyncCreateCount: number = 0;

  async createEngineAsync(config: EngineConfig): Promise<number> {
    this.asyncCreateCount += 1;
    await nextTask();
    return this.createEngine(config);
  }
}

class ReloadableSchemeGateway extends FakeNativeGateway {
  configs: EngineConfig[] = [];
  destroyedHandles: number[] = [];
  failProductionBundle: boolean = false;
  private nextHandle: number = 40;

  createEngine(config: EngineConfig): number {
    this.configs.push({
      interfaceVersion: config.interfaceVersion,
      schemeId: config.schemeId,
      lexiconPath: config.lexiconPath,
      codeTableBundlePath: config.codeTableBundlePath,
      userLexiconPath: config.userLexiconPath,
      codeTableActionFixturePath: config.codeTableActionFixturePath,
      codeTableActionFixtureSha256: config.codeTableActionFixtureSha256,
      candidatePageSize: config.candidatePageSize
    });
    if (config.interfaceVersion !== 11) {
      throw new Error('bad interface version');
    }
    if (config.schemeId === 'xiaohe-yinxing') {
      if (this.failProductionBundle || config.codeTableBundlePath !== '/files/production.hsyx') {
        throw new Error('production bundle rejected');
      }
    } else if (config.schemeId !== 'xiaohe') {
      throw new Error('bad scheme');
    }
    this.createdCount += 1;
    this.nextHandle += 1;
    return this.nextHandle;
  }

  destroyEngine(handle: number): void {
    this.destroyedCount += 1;
    this.destroyedHandles.push(handle);
  }

  changeScheme(_handle: number, schemeId: string): CompositionResult {
    if (schemeId === 'xiaohe') {
      return createCompositionResult('', '', 'empty');
    }
    const rejected = createCompositionResult('', '', 'empty');
    rejected.success = false;
    rejected.errorCode = ImeErrorCode.INVALID_SCHEME;
    rejected.errorMessage = 'bundle was not loaded';
    return rejected;
  }
}

class QuanpinGateway extends FakeNativeGateway {
  configs: EngineConfig[] = [];

  createEngine(config: EngineConfig): number {
    if (config.interfaceVersion !== 11 || config.schemeId !== 'quanpin') {
      throw new Error('bad quanpin config');
    }
    this.configs.push({
      interfaceVersion: config.interfaceVersion,
      schemeId: config.schemeId,
      lexiconPath: config.lexiconPath,
      codeTableBundlePath: config.codeTableBundlePath,
      userLexiconPath: config.userLexiconPath,
      codeTableActionFixturePath: config.codeTableActionFixturePath,
      codeTableActionFixtureSha256: config.codeTableActionFixtureSha256,
      candidatePageSize: config.candidatePageSize,
      quanpinConfigVersion: config.quanpinConfigVersion,
      spellingCorrectionEnabled: config.spellingCorrectionEnabled,
      fuzzyOptions: config.fuzzyOptions?.slice(),
      quanpinContextRerankingConfigVersion: config.quanpinContextRerankingConfigVersion,
      quanpinContextRerankingEnabled: config.quanpinContextRerankingEnabled,
      quanpinContextModelPath: config.quanpinContextModelPath,
      quanpinContextModelSha256: config.quanpinContextModelSha256
    });
    this.createdCount += 1;
    return 7;
  }
}

class AsyncQuanpinKeyGateway extends QuanpinGateway {
  asyncProcessKeyCount: number = 0;

  async processKeyAsync(_handle: number, key: string): Promise<CompositionResult> {
    this.asyncProcessKeyCount += 1;
    await nextTask();
    this.processKeys.push(key);
    return createCompositionResult(key, key, 'complete');
  }
}

class T9Gateway extends FakeNativeGateway {
  rawDigits: string = '';
  selectedCombinationIndexes: number[] = [];
  boundaryCount: number = 0;

  createEngine(config: EngineConfig): number {
    if (config.interfaceVersion !== 11 || config.schemeId !== 'pinyin-9') {
      throw new Error('bad pinyin-9 config');
    }
    this.createdCount += 1;
    return 7;
  }

  processKey(_handle: number, key: string): CompositionResult {
    this.processKeys.push(key);
    this.rawDigits += key;
    return this.currentResult();
  }

  insertSegmentBoundary(_handle: number): CompositionResult {
    this.boundaryCount += 1;
    const result = this.currentResult();
    result.segmentBoundaries = [this.rawDigits.length];
    return result;
  }

  backspace(_handle: number): CompositionResult {
    this.backspaceCount += 1;
    this.rawDigits = this.rawDigits.slice(0, Math.max(0, this.rawDigits.length - 1));
    return this.currentResult();
  }

  reset(_handle: number): CompositionResult {
    this.resetCount += 1;
    this.rawDigits = '';
    return this.currentResult();
  }

  selectPinyinCombination(_handle: number, combinationIndex: number): CompositionResult {
    this.selectedCombinationIndexes.push(combinationIndex);
    const result = this.currentResult();
    if (this.rawDigits === '64' && combinationIndex === 1) {
      result.currentPinyin = 'ni';
      result.preeditText = 'ni';
      result.pinyinCombinations = ['ng', 'mi'];
      result.candidates = [{ id: 't9-ni', text: '你', reading: 'ni', source: 'test-rust' }];
      result.highlightedIndex = 0;
    }
    return result;
  }

  selectCandidate(_handle: number, _candidateIndex: number): CompositionResult {
    const result = this.currentResult();
    result.rawInput = '';
    result.preeditText = '';
    result.currentPinyin = '';
    result.pinyinCombinations = [];
    result.candidates = [];
    result.highlightedIndex = -1;
    result.commitText = this.rawDigits === '64426' ? '你好' : '你';
    result.compositionFinished = true;
    this.rawDigits = '';
    return result;
  }

  private currentResult(): CompositionResult {
    if (this.rawDigits.length === 0) {
      const empty = createCompositionResult('', '', 'empty');
      empty.currentPinyin = '';
      empty.pinyinCombinations = [];
      return empty;
    }
    const currentPinyin = this.rawDigits === '64426' ? "ni'hao" : (this.rawDigits === '64' ? 'ng' : 'm');
    const result = createCompositionResult(this.rawDigits, currentPinyin, 'ambiguous');
    result.currentPinyin = currentPinyin;
    result.pinyinCombinations = this.rawDigits === '64' ? ['ni', 'mi'] : [];
    result.displaySegments = [this.rawDigits];
    result.candidates = [{
      id: `t9-${this.rawDigits}`,
      text: this.rawDigits === '64426' ? '你好' : '你',
      reading: currentPinyin,
      source: 'test-rust'
    }];
    result.highlightedIndex = 0;
    return result;
  }
}

class BrokenQuanpinCommitGateway extends QuanpinGateway {
  processKey(handle: number, key: string): CompositionResult {
    this.processKeys.push(key);
    const result = createCompositionResult(key, key, 'complete');
    result.commitText = '禁止提交';
    result.compositionFinished = true;
    return result;
  }
}

function createUserModelStatus(
  loaded: boolean,
  enabled: boolean,
  sessionLearningAllowed: boolean,
  dirty: boolean,
  recordCount: number,
  lastErrorCode: string
): UserModelStatus {
  return {
    loaded,
    enabled,
    sessionLearningAllowed,
    dirty,
    recordCount,
    formatVersion: 1,
    dataVersion: 1,
    lastErrorCode
  };
}

function createUserLexiconDocument(): UserLexiconDocument {
  return {
    success: true,
    errorCode: '',
    errorLine: 0,
    errorField: '',
    message: '',
    warningCode: '',
    revision: 'test-revision',
    entries: [],
    stats: { accepted: 0, effective: 0, added: 0, deleted: 0, fixed: 0, positioned: 0 }
  };
}

class PartialCommitGateway extends FakeNativeGateway {
  selectCandidate(handle: number, candidateIndex: number): CompositionResult {
    return {
      success: true,
      errorCode: ImeErrorCode.SUCCESS,
      errorMessage: '',
      rawInput: 'fa',
      preeditText: 'fa',
      parsedSyllables: ['fa'],
      pendingCode: '',
      parserState: 'complete',
      candidates: [
        {
          id: 'stage8-fa',
          text: '法',
          reading: 'fa',
          source: 'stage8'
        }
      ],
      highlightedIndex: 0,
      hasNextPage: false,
      hasPreviousPage: false,
      candidatePage: 0,
      commitText: '输入',
      action: null,
      compositionFinished: false
    };
  }
}

class FullSentenceCommitGateway extends FakeNativeGateway {
  selectCandidate(handle: number, candidateIndex: number): CompositionResult {
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
      commitText: '输入法',
      action: null,
      compositionFinished: true
    };
  }
}

class AutomaticCommitGateway extends FakeNativeGateway {
  private readonly remainingRawInput: string;
  private readonly automaticCommitText: string;
  private readonly remainingCandidateText: string;

  constructor(
    remainingRawInput: string,
    automaticCommitText: string = '𠮷😀',
    remainingCandidateText: string = '新段'
  ) {
    super();
    this.remainingRawInput = remainingRawInput;
    this.automaticCommitText = automaticCommitText;
    this.remainingCandidateText = remainingCandidateText;
  }

  processKey(handle: number, key: string): CompositionResult {
    this.processKeys.push(key);
    const result = createCompositionResult(
      this.remainingRawInput,
      this.remainingRawInput,
      this.remainingRawInput.length > 0 ? 'complete' : 'empty'
    );
    result.commitText = this.automaticCommitText;
    result.compositionFinished = this.remainingRawInput.length === 0;
    if (this.remainingRawInput.length > 0) {
      result.candidates = [{
        id: 'stage11-6-7-new-segment',
        text: this.remainingCandidateText,
        reading: this.remainingRawInput,
        source: 'core'
      }];
      result.highlightedIndex = 0;
    }
    return result;
  }
}

class StatefulTopScreenGateway extends FakeNativeGateway {
  private rawCode: string = '';

  processKey(handle: number, key: string): CompositionResult {
    this.processKeys.push(key);
    if (this.rawCode.length >= 4) {
      this.rawCode = key;
      const replayed = createCompositionResult(this.rawCode, this.rawCode, 'complete');
      replayed.commitText = '𠮷😀';
      replayed.candidates = [{
        id: 'stage2-next-segment',
        text: '新段',
        reading: this.rawCode,
        source: 'core'
      }];
      replayed.highlightedIndex = 0;
      return replayed;
    }

    this.rawCode += key;
    const result = createCompositionResult(this.rawCode, this.rawCode, 'complete');
    if (this.rawCode.length === 4) {
      result.candidates = [
        {
          id: 'stage2-old-first',
          text: '𠮷😀',
          reading: this.rawCode,
          source: 'core'
        },
        {
          id: 'stage2-old-second',
          text: '旧段次选',
          reading: this.rawCode,
          source: 'core'
        }
      ];
      result.highlightedIndex = 0;
    }
    return result;
  }

  backspace(handle: number): CompositionResult {
    this.backspaceCount += 1;
    this.rawCode = this.rawCode.slice(0, Math.max(0, this.rawCode.length - 1));
    return createCompositionResult(
      this.rawCode,
      this.rawCode,
      this.rawCode.length > 0 ? 'complete' : 'empty'
    );
  }

  reset(handle: number): CompositionResult {
    this.resetCount += 1;
    this.rawCode = '';
    return createCompositionResult('', '', 'empty');
  }
}

class CandidateTransactionImeService extends FakeImeInputService {
  insertAttempts: number = 0;
  private readonly outcomes: number[];

  constructor(outcomes: number[]) {
    super();
    this.outcomes = outcomes.slice();
  }

  async insertText(text: string): Promise<boolean> {
    this.insertAttempts += 1;
    const outcome = this.outcomes.length > 0 ? this.outcomes[0] : 1;
    if (this.outcomes.length > 0) {
      this.outcomes.splice(0, 1);
    }
    if (outcome < 0) {
      throw new Error('simulated insert failure');
    }
    if (outcome === 0) {
      return false;
    }
    this.insertedTexts.push(text);
    return true;
  }
}

class AtomicCandidatePreviewImeService extends FakeImeInputService {
  committedCandidateTexts: string[] = [];
  predictedRemainingRawInputs: string[] = [];

  async commitCandidatePreviewText(
    committedText: string,
    remainingRawInput: string
  ): Promise<boolean> {
    this.committedCandidateTexts.push(committedText);
    this.predictedRemainingRawInputs.push(remainingRawInput);
    return true;
  }
}

class CandidateTransactionGateway extends FakeNativeGateway {
  selectCount: number = 0;
  learningCount: number = 0;
  private readonly confirmationSucceeds: boolean;

  constructor(confirmationSucceeds: boolean = true) {
    super();
    this.confirmationSucceeds = confirmationSucceeds;
  }

  selectCandidate(handle: number, candidateIndex: number): CompositionResult {
    this.selectCount += 1;
    if (!this.confirmationSucceeds) {
      const result = createCompositionResult('ni', 'ni', 'complete');
      result.success = false;
      result.errorCode = ImeErrorCode.ENGINE_INTERNAL_ERROR;
      result.errorMessage = 'simulated native confirmation failure';
      return result;
    }
    this.learningCount += 1;
    return super.selectCandidate(handle, candidateIndex);
  }
}

function createCompositionResult(
  rawInput: string,
  preeditText: string,
  parserState: 'empty' | 'incomplete' | 'complete' | 'invalid' | 'ambiguous'
): CompositionResult {
  return {
    success: true,
    errorCode: ImeErrorCode.SUCCESS,
    errorMessage: '',
    rawInput,
    preeditText,
    parsedSyllables: parserState === 'complete' ? [preeditText] : [],
    pendingCode: parserState === 'incomplete' ? rawInput : '',
    parserState,
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

function createCandidateComposition(text: string = '你'): CompositionResult {
  const result = createCompositionResult('ni', 'ni', 'complete');
  result.candidates = [{
    id: `candidate-${text.length}`,
    text,
    reading: 'ni',
    source: 'transaction-test'
  }];
  result.highlightedIndex = 0;
  return result;
}

function createFakeEngineCoordinator(gateway: FakeNativeGateway = new FakeNativeGateway()): EngineCoordinator {
  return new EngineCoordinator(gateway);
}

export default function stage2ControllerTest() {
  describe('stage2ControllerTest', () => {
    it('converts normal candidates and commit text after the approved traditional toggle', 0, () => {
      const engine = new EngineCoordinator(new TraditionalGateway(), new FakeTraditionalConverter());
      expect(engine.initialize().success).assertTrue();
      engine.setTraditionalOutputEnabled(true);

      const composing = engine.processKey('n');
      expect(composing.candidates[0].text).assertEqual('妳');
      const committed = engine.selectCandidate(0);
      expect(committed.commitText).assertEqual('妳');
    });

    it('initializesTheEngineThroughTheAsyncNativePath', 0, async () => {
      const gateway = new AsyncNativeGateway();
      const engineCoordinator = new EngineCoordinator(gateway);

      const initialization = engineCoordinator.initializeAsync();
      expect(gateway.asyncCreateCount).assertEqual(1);
      expect(gateway.createdCount).assertEqual(0);

      const result = await initialization;
      expect(result.success).assertTrue();
      expect(gateway.createdCount).assertEqual(1);
      expect(engineCoordinator.isInitialized()).assertTrue();
    });

    it('routesQuanpinKeyProcessingThroughTheAsyncNativePath', 0, async () => {
      const gateway = new AsyncQuanpinKeyGateway();
      const engineCoordinator = new EngineCoordinator(gateway);
      expect(engineCoordinator.initialize('quanpin', '/files/production.lex').success).assertTrue();

      const pending = engineCoordinator.processKeyAsync('n');
      expect(gateway.asyncProcessKeyCount).assertEqual(1);
      expect(gateway.processKeys.length).assertEqual(0);

      const result = await pending;
      expect(result.rawInput).assertEqual('n');
      expect(gateway.processKeys.join('')).assertEqual('n');
    });

    it('sharesOverlappingAsyncInitializationAndDestroysAStaleHandle', 0, async () => {
      const gateway = new AsyncNativeGateway();
      const engineCoordinator = new EngineCoordinator(gateway);

      const first = engineCoordinator.initializeAsync();
      const second = engineCoordinator.initializeAsync();
      expect(gateway.asyncCreateCount).assertEqual(1);
      await Promise.all([first, second]);
      expect(gateway.createdCount).assertEqual(1);

      engineCoordinator.dispose();
      const stale = engineCoordinator.initializeAsync();
      engineCoordinator.dispose();
      await stale;
      expect(gateway.createdCount).assertEqual(2);
      expect(gateway.destroyedCount).assertEqual(2);
      expect(engineCoordinator.isInitialized()).assertFalse();
    });

    it('initializesThePersistedQuanpinProfileBeforeHardwareInputCanStart', 0, async () => {
      const store = new InputSessionStore();
      const gateway = new QuanpinGateway();
      const engineCoordinator = new EngineCoordinator(gateway);
      const controller = new InputSessionController(store, new FakeImeInputService(), engineCoordinator);
      const settings: ImeSettings = copyImeSettings(DEFAULT_IME_SETTINGS);
      settings.keyboardProfileId = 'quanpin-26';
      settings.schemeId = 'quanpin';

      await controller.handleAbilityCreated(undefined, Promise.resolve(settings));

      expect(gateway.createdCount).assertEqual(1);
      expect(engineCoordinator.getActiveSchemeId()).assertEqual('quanpin');
    });

    it('transportsPersistedQuanpinFeaturesAndReconfiguresTransactionally', 0, async () => {
      const store = new InputSessionStore();
      const gateway = new QuanpinGateway();
      const engineCoordinator = new EngineCoordinator(gateway);
      const controller = new InputSessionController(store, new FakeImeInputService(), engineCoordinator);
      const settings: ImeSettings = copyImeSettings(DEFAULT_IME_SETTINGS);
      settings.keyboardProfileId = 'quanpin-26';
      settings.schemeId = 'quanpin';
      settings.spellingCorrectionEnabled = true;
      settings.fuzzyOptions = ['n_l', 'ian_iang'];

      await controller.handleAbilityCreated(undefined, Promise.resolve(settings));
      expect(gateway.configs[0].quanpinConfigVersion).assertEqual(1);
      expect(gateway.configs[0].spellingCorrectionEnabled).assertTrue();
      expect(gateway.configs[0].fuzzyOptions?.join('|')).assertEqual('n_l|ian_iang');

      const updated = engineCoordinator.reconfigureQuanpin(false, ['z_zh']);
      expect(updated.success).assertTrue();
      expect(gateway.configs.length).assertEqual(2);
      expect(gateway.configs[1].spellingCorrectionEnabled).assertFalse();
      expect(gateway.configs[1].fuzzyOptions?.join('|')).assertEqual('z_zh');
    });

    it('transportsVersionedQuanpinContextModelConfigAcrossEngineRecreation', 0, () => {
      const gateway = new QuanpinGateway();
      const engine = new EngineCoordinator(gateway);
      const modelHash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

      const initialized = engine.initialize(
        'quanpin',
        '/files/production.lex',
        undefined,
        7,
        undefined,
        undefined,
        undefined,
        false,
        [],
        '/files/quanpin-context-v2.qng',
        modelHash
      );
      expect(initialized.success).assertTrue();
      expect(gateway.configs[0].quanpinContextRerankingConfigVersion).assertEqual(2);
      expect(gateway.configs[0].quanpinContextRerankingEnabled).assertTrue();
      expect(gateway.configs[0].quanpinContextModelPath).assertEqual('/files/quanpin-context-v2.qng');
      expect(gateway.configs[0].quanpinContextModelSha256).assertEqual(modelHash);

      expect(engine.reconfigureQuanpin(true, ['n_l']).success).assertTrue();
      expect(gateway.configs[1].quanpinContextRerankingConfigVersion).assertEqual(2);
      expect(gateway.configs[1].quanpinContextRerankingEnabled).assertTrue();
      expect(gateway.configs[1].quanpinContextModelPath).assertEqual('/files/quanpin-context-v2.qng');
      expect(gateway.configs[1].quanpinContextModelSha256).assertEqual(modelHash);
    });

    it('restoresThePersistedPinyin9ProfileIntoTheRustEngineOnAbilityStart', 0, async () => {
      const store = new InputSessionStore();
      const gateway = new T9Gateway();
      const engineCoordinator = new EngineCoordinator(gateway);
      const controller = new InputSessionController(store, new FakeImeInputService(), engineCoordinator);
      const settings: ImeSettings = copyImeSettings(DEFAULT_IME_SETTINGS);
      settings.keyboardProfileId = 'pinyin-9';
      settings.schemeId = 'pinyin-9';

      await controller.handleAbilityCreated(undefined, Promise.resolve(settings));

      expect(gateway.createdCount).assertEqual(1);
      expect(engineCoordinator.getActiveSchemeId()).assertEqual('pinyin-9');
    });

    it('defaultKeyboardModeIsEnglish', 0, () => {
      const store = new InputSessionStore();
      expect(store.getSnapshot().keyboardMode).assertEqual(KeyboardMode.ENGLISH);
    });

    it('keyboardModeTogglesBetweenEnglishAndChinesePlaceholder', 0, () => {
      const store = new InputSessionStore();
      store.toggleKeyboardMode();
      expect(store.getSnapshot().keyboardMode).assertEqual(KeyboardMode.CHINESE_PLACEHOLDER);
      store.toggleKeyboardMode();
      expect(store.getSnapshot().keyboardMode).assertEqual(KeyboardMode.ENGLISH);
    });

    it('qwertyLayoutKeepsNaturalTopToBottomOrder', 0, () => {
      expect(QWERTY_KEY_ROWS[0].map((key) => key.label).join('')).assertEqual('QWERTYUIOP');
      expect(QWERTY_KEY_ROWS[1].map((key) => key.label).join('')).assertEqual('ASDFGHJKL');
      expect(QWERTY_KEY_ROWS[2].map((key) => key.label).join('')).assertEqual('ZXCVBNM');
      expect(QWERTY_KEY_ROWS[3].map((key) => key.id).join(',')).assertEqual('toggle-language,space,delete,enter');
    });

    it('letterInputWithoutSessionReturnsClearError', 0, async () => {
      const store = new InputSessionStore();
      const controller = new InputSessionController(store, new FakeImeInputService(), createFakeEngineCoordinator());
      const result = await controller.insertLetter('a');
      expect(result.success).assertEqual(false);
      expect(result.errorCode).assertEqual(ImeErrorCode.ENGINE_NOT_INITIALIZED);
    });

    it('sessionStateStartsAndStopsCleanly', 0, () => {
      const store = new InputSessionStore();
      store.markSessionStarted();
      expect(store.getSnapshot().sessionActive).assertEqual(true);
      expect(store.getSnapshot().editorConnected).assertEqual(true);
      store.markSessionStopped();
      expect(store.getSnapshot().sessionActive).assertEqual(false);
      expect(store.getSnapshot().editorConnected).assertEqual(false);
      expect(store.getSnapshot().keyboardMode).assertEqual(KeyboardMode.ENGLISH);
    });

    it('keyboardVisibilityUpdates', 0, () => {
      const store = new InputSessionStore();
      store.markKeyboardVisible();
      expect(store.getSnapshot().keyboardVisible).assertEqual(true);
      store.markKeyboardHidden();
      expect(store.getSnapshot().keyboardVisible).assertEqual(false);
    });

    it('keyboardControllerConvertsLetterAndSpaceActionsToInsertRequests', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new FakeImeInputService();
      store.markSessionStarted();
      const sessionController = new InputSessionController(store, imeService, createFakeEngineCoordinator());
      const controller = new KeyboardController(sessionController, new FakeNativeGateway());

      await controller.handleAction({
        type: KeyboardActionType.LETTER,
        letter: 'H'
      });
      await controller.handleAction({
        type: KeyboardActionType.SPACE
      });

      expect(imeService.insertedTexts[0]).assertEqual('h');
      expect(imeService.insertedTexts[1]).assertEqual(' ');
    });

    it('keyboardControllerRoutesDeleteEnterAndHideThroughUnifiedService', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new FakeImeInputService();
      store.markSessionStarted();
      store.markKeyboardVisible();
      const sessionController = new InputSessionController(store, imeService, createFakeEngineCoordinator());
      const controller = new KeyboardController(sessionController, new FakeNativeGateway());

      await controller.handleAction({ type: KeyboardActionType.DELETE });
      await controller.handleAction({ type: KeyboardActionType.DELETE_CURRENT_LINE });
      await controller.handleAction({ type: KeyboardActionType.RESTORE_LAST_DELETION });
      await controller.handleAction({ type: KeyboardActionType.ENTER });
      await controller.handleAction({ type: KeyboardActionType.HIDE_KEYBOARD });

      expect(imeService.deleteCount).assertEqual(1);
      expect(imeService.deleteLineCount).assertEqual(1);
      expect(imeService.restoreDeletionCount).assertEqual(1);
      expect(imeService.enterCount).assertEqual(1);
      expect(imeService.hideCount).assertEqual(1);
      expect(store.getSnapshot().keyboardVisible).assertEqual(false);
    });

    it('keyboardControllerRoutesLiftLayerCursorMovementThroughInputClient', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new FakeImeInputService();
      store.markSessionStarted();
      store.markKeyboardVisible();
      const sessionController = new InputSessionController(store, imeService, createFakeEngineCoordinator());
      const controller = new KeyboardController(sessionController, new FakeNativeGateway());

      await controller.handleAction({ type: KeyboardActionType.MOVE_CURSOR_LEFT });
      await controller.handleAction({ type: KeyboardActionType.MOVE_CURSOR_RIGHT });

      expect(imeService.cursorDirections.length).assertEqual(2);
      expect(imeService.cursorDirections[0]).assertEqual(inputMethodEngine.Direction.CURSOR_LEFT);
      expect(imeService.cursorDirections[1]).assertEqual(inputMethodEngine.Direction.CURSOR_RIGHT);
    });

    it('keyboardControllerSerializesRapidLettersInArrivalOrder', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new OrderedImeInputService();
      store.markSessionStarted();
      const sessionController = new InputSessionController(store, imeService, createFakeEngineCoordinator());
      const controller = new KeyboardController(sessionController, new FakeNativeGateway());
      const firstGate = imeService.gateNextInsert();

      const first = controller.handleAction({ type: KeyboardActionType.LETTER, letter: 'a' });
      const second = controller.handleAction({ type: KeyboardActionType.LETTER, letter: 'b' });
      const third = controller.handleAction({ type: KeyboardActionType.LETTER, letter: 'c' });
      await nextTask();
      expect(imeService.events.join(',')).assertEqual('insert-start:a');

      firstGate.resolve();
      await first;
      await second;
      await third;
      expect(imeService.events.join(',')).assertEqual(
        'insert-start:a,insert-end:a,insert-start:b,insert-end:b,insert-start:c,insert-end:c'
      );
    });

    it('keyboardControllerSerializesInputDeleteAndFollowingInput', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new OrderedImeInputService();
      store.markSessionStarted();
      const sessionController = new InputSessionController(store, imeService, createFakeEngineCoordinator());
      const controller = new KeyboardController(sessionController, new FakeNativeGateway());
      const firstGate = imeService.gateNextInsert();

      const first = controller.handleAction({ type: KeyboardActionType.LETTER, letter: 'a' });
      const deletion = controller.handleAction({ type: KeyboardActionType.DELETE });
      const second = controller.handleAction({ type: KeyboardActionType.LETTER, letter: 'b' });
      await nextTask();
      expect(imeService.events.join(',')).assertEqual('insert-start:a');

      firstGate.resolve();
      await first;
      await deletion;
      await second;
      expect(imeService.events.join(',')).assertEqual(
        'insert-start:a,insert-end:a,delete-start,delete-end,insert-start:b,insert-end:b'
      );
    });

    it('keyboardControllerContinuesAfterUnexpectedActionFailure', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new OrderedImeInputService();
      imeService.failNextInsert = true;
      store.markSessionStarted();
      const sessionController = new InputSessionController(store, imeService, createFakeEngineCoordinator());
      const controller = new KeyboardController(sessionController, new FakeNativeGateway());

      const failed = controller.handleAction({ type: KeyboardActionType.LETTER, letter: 'a' });
      const continued = controller.handleAction({ type: KeyboardActionType.LETTER, letter: 'b' });
      const failedResult = await failed;
      const continuedResult = await continued;

      expect(failedResult.success).assertFalse();
      expect(continuedResult.success).assertTrue();
      expect(imeService.events.join(',')).assertEqual(
        'insert-start:a,insert-failed:a,insert-start:b,insert-end:b'
      );
    });

    it('staleQueuedActionsDoNotRunAgainstANewInputSession', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new OrderedImeInputService();
      store.markSessionStarted();
      const sessionController = new InputSessionController(store, imeService, createFakeEngineCoordinator());
      const controller = new KeyboardController(sessionController, new FakeNativeGateway());
      const firstGate = imeService.gateNextInsert();

      const runningOldAction = controller.handleAction({ type: KeyboardActionType.LETTER, letter: 'a' });
      const queuedOldAction = controller.handleAction({ type: KeyboardActionType.LETTER, letter: 'b' });
      await nextTask();
      store.markSessionStopped();
      store.markSessionStarted();
      const newSessionAction = controller.handleAction({ type: KeyboardActionType.LETTER, letter: 'c' });
      firstGate.resolve();

      const runningResult = await runningOldAction;
      const queuedResult = await queuedOldAction;
      const newResult = await newSessionAction;
      expect(runningResult.success).assertFalse();
      expect(queuedResult.success).assertFalse();
      expect(newResult.success).assertTrue();
      expect(imeService.events.join(',')).assertEqual(
        'insert-start:a,insert-end:a,insert-start:c,insert-end:c'
      );
      expect(store.getSnapshot().lastErrorMessage).assertEqual('success');
    });

    it('candidateCommitModeSwitchAndNewInputShareOneQueueWithoutDeadlock', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new OrderedImeInputService();
      const gateway = new CandidateTransactionGateway();
      const sessionController = new InputSessionController(store, imeService, new EngineCoordinator(gateway));
      const controller = new KeyboardController(sessionController, gateway);
      store.markSessionStarted();
      sessionController.toggleKeyboardMode();
      store.updateComposition(createCandidateComposition());
      const candidateGate = imeService.gateNextInsert();

      const candidate = controller.commitCandidate(0);
      const mode = controller.handleAction({ type: KeyboardActionType.TOGGLE_LANGUAGE });
      const input = controller.handleAction({ type: KeyboardActionType.LETTER, letter: 'x' });
      await nextTask();
      expect(imeService.events.join(',')).assertEqual('insert-start:你');

      candidateGate.resolve();
      const candidateResult = await candidate;
      const modeResult = await mode;
      const inputResult = await input;
      expect(candidateResult.success).assertTrue();
      expect(modeResult.success).assertTrue();
      expect(inputResult.success).assertTrue();
      expect(store.getSnapshot().keyboardMode).assertEqual(KeyboardMode.ENGLISH);
      expect(imeService.events.join(',')).assertEqual(
        'insert-start:你,insert-end:你,insert-start:x,insert-end:x'
      );
    });

    it('asynchronousEnglishModeSwitchAndSynchronousChineseCodeStayOrdered', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new OrderedImeInputService();
      const gateway = new FakeNativeGateway();
      const engineCoordinator = new EngineCoordinator(gateway);
      engineCoordinator.initialize();
      const sessionController = new InputSessionController(store, imeService, engineCoordinator);
      const controller = new KeyboardController(sessionController, gateway);
      store.markSessionStarted();
      const insertGate = imeService.gateNextInsert();

      const english = controller.handleAction({ type: KeyboardActionType.LETTER, letter: 'a' });
      const mode = controller.handleAction({ type: KeyboardActionType.TOGGLE_LANGUAGE });
      const chinese = controller.handleAction({ type: KeyboardActionType.LETTER, letter: 'n' });
      await nextTask();
      expect(imeService.events.join(',')).assertEqual('insert-start:a');
      expect(gateway.processKeys.length).assertEqual(0);

      insertGate.resolve();
      await english;
      await mode;
      await chinese;
      expect(imeService.events.join(',')).assertEqual('insert-start:a,insert-end:a');
      expect(gateway.processKeys.join(',')).assertEqual('n');
      expect(store.getSnapshot().keyboardMode).assertEqual(KeyboardMode.CHINESE);
    });

    it('stage1168RecreatesEngineWithProductionBundleBeforeReleasingOldHandle', 0, () => {
      const gateway = new ReloadableSchemeGateway();
      const engine = new EngineCoordinator(gateway);
      const initialized = engine.initialize('xiaohe', '/files/production.lex', '/files/user.txt', 17);
      expect(initialized.success).assertTrue();
      engine.loadUserModel('/files/user-model.dat');
      engine.setUserLearningEnabled(false);
      engine.setSessionLearningAllowed(false);

      const switched = engine.changeScheme('xiaohe-yinxing', '/files/production.hsyx');

      expect(switched.success).assertTrue();
      expect(engine.getActiveSchemeId()).assertEqual('xiaohe-yinxing');
      expect(gateway.configs.length).assertEqual(2);
      expect(gateway.configs[1].schemeId).assertEqual('xiaohe-yinxing');
      expect(gateway.configs[1].lexiconPath).assertEqual('/files/production.lex');
      expect(gateway.configs[1].userLexiconPath).assertEqual('/files/user.txt');
      expect(gateway.configs[1].candidatePageSize).assertEqual(17);
      expect(gateway.configs[1].codeTableBundlePath).assertEqual('/files/production.hsyx');
      expect(gateway.destroyedHandles.length).assertEqual(1);
      expect(gateway.loadUserModelPath).assertEqual('/files/user-model.dat');
      expect(gateway.userLearningEnabledValues[gateway.userLearningEnabledValues.length - 1]).assertFalse();
      expect(gateway.sessionLearningAllowedValues[gateway.sessionLearningAllowedValues.length - 1]).assertFalse();
    });

    it('recreatesWhenAPhoneticHandleOnlyCarriedTheProductionBundlePathInConfig', 0, () => {
      const gateway = new ReloadableSchemeGateway();
      const engine = new EngineCoordinator(gateway);
      const initialized = engine.initialize(
        'xiaohe',
        '/files/production.lex',
        '/files/user.txt',
        17,
        '/files/production.hsyx'
      );
      expect(initialized.success).assertTrue();

      const switched = engine.changeScheme('xiaohe-yinxing', '/files/production.hsyx');

      expect(switched.success).assertTrue();
      expect(engine.getActiveSchemeId()).assertEqual('xiaohe-yinxing');
      expect(gateway.configs.length).assertEqual(2);
      expect(gateway.configs[1].schemeId).assertEqual('xiaohe-yinxing');
      expect(gateway.destroyedHandles.length).assertEqual(1);
    });

    it('candidatePagesUseSevenByDefaultAndKeepExplicitOverrides', 0, () => {
      const defaultGateway = new ReloadableSchemeGateway();
      const defaultEngine = new EngineCoordinator(defaultGateway);
      expect(defaultEngine.initialize().success).assertTrue();
      expect(defaultGateway.configs[0].candidatePageSize).assertEqual(50);

      const smallGateway = new ReloadableSchemeGateway();
      const smallEngine = new EngineCoordinator(smallGateway);
      expect(smallEngine.initialize('xiaohe', undefined, undefined, 9).success).assertTrue();
      expect(smallGateway.configs[0].candidatePageSize).assertEqual(9);
    });

    it('pinyinStage3CombinationSelectionIsForwardedWithoutArktsDisambiguation', 0, () => {
      const gateway = new FakeNativeGateway();
      const engine = new EngineCoordinator(gateway);
      expect(engine.initialize().success).assertTrue();

      const selected = engine.selectPinyinCombination(2);

      expect(selected.success).assertTrue();
      expect(selected.rawInput).assertEqual('64');
      expect(selected.preeditText).assertEqual('ni');
      expect(engine.getCurrentResult().rawInput).assertEqual('64');
    });

    it('pinyinStage4DedicatedDigitsReachRustWithoutDirectNumberInsertion', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new FakeImeInputService();
      const gateway = new T9Gateway();
      const engine = new EngineCoordinator(gateway);
      expect(engine.initialize('pinyin-9').success).assertTrue();
      store.markSessionStarted();
      const session = new InputSessionController(store, imeService, engine);
      session.toggleKeyboardMode();
      const controller = new KeyboardController(session, gateway);

      for (const digit of '64426'.split('')) {
        const result = await controller.handleAction(createT9PinyinDigitAction(digit));
        expect(result.success).assertTrue();
      }

      expect(gateway.processKeys.join('')).assertEqual('64426');
      expect(imeService.insertedTexts.length).assertEqual(0);
      expect(imeService.previewTexts[imeService.previewTexts.length - 1]).assertEqual('64426');
      expect(store.getSnapshot().currentPinyin).assertEqual("ni'hao");
      expect(store.getSnapshot().candidates[0].text).assertEqual('你好');
    });

    it('pinyinStage4CombinationSelectionBoundaryDeleteAndSpaceStayOnFormalChains', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new FakeImeInputService();
      const gateway = new T9Gateway();
      const engine = new EngineCoordinator(gateway);
      expect(engine.initialize('pinyin-9').success).assertTrue();
      store.markSessionStarted();
      const session = new InputSessionController(store, imeService, engine);
      session.toggleKeyboardMode();
      const controller = new KeyboardController(session, gateway);

      await controller.handleAction(createT9PinyinDigitAction('6'));
      await controller.handleAction(createT9PinyinDigitAction('4'));
      expect(store.getSnapshot().pinyinCombinations.join('|')).assertEqual('ni|mi');
      expect((await controller.selectPinyinCombination(1)).success).assertTrue();
      expect(gateway.selectedCombinationIndexes.join('|')).assertEqual('1');
      expect(store.getSnapshot().currentPinyin).assertEqual('ni');

      expect((await controller.handleAction({ type: KeyboardActionType.INSERT_SEGMENT_BOUNDARY })).success)
        .assertTrue();
      expect(gateway.boundaryCount).assertEqual(1);
      expect((await controller.handleAction({ type: KeyboardActionType.DELETE })).success).assertTrue();
      expect(gateway.backspaceCount).assertEqual(1);
      expect(store.getSnapshot().rawInput).assertEqual('6');

      await controller.handleAction(createT9PinyinDigitAction('4'));
      expect((await controller.handleAction({ type: KeyboardActionType.SPACE })).success).assertTrue();
      expect(imeService.insertedTexts[0]).assertEqual('你');
      expect(store.getSnapshot().rawInput).assertEqual('');
    });

    it('pinyinStage4RejectsNonT9DigitsWithoutCallingRustOrTheEditor', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new FakeImeInputService();
      const gateway = new T9Gateway();
      const engine = new EngineCoordinator(gateway);
      expect(engine.initialize('pinyin-9').success).assertTrue();
      store.markSessionStarted();
      const session = new InputSessionController(store, imeService, engine);
      session.toggleKeyboardMode();

      const rejected = await session.insertT9PinyinDigit('1');
      expect(rejected.success).assertFalse();
      expect(gateway.processKeys.length).assertEqual(0);
      expect(imeService.insertedTexts.length).assertEqual(0);
    });

    it('pinyinStage4KeyboardHideAndShowDoNotRestoreStaleT9State', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new FakeImeInputService();
      const gateway = new T9Gateway();
      const engine = new EngineCoordinator(gateway);
      expect(engine.initialize('pinyin-9').success).assertTrue();
      store.markSessionStarted();
      const session = new InputSessionController(store, imeService, engine);
      session.toggleKeyboardMode();

      await session.insertT9PinyinDigit('6');
      await session.insertT9PinyinDigit('4');
      expect(store.getSnapshot().currentPinyin.length > 0).assertTrue();
      expect(store.getSnapshot().pinyinCombinations.length > 0).assertTrue();

      session.handleKeyboardHide();
      session.handleKeyboardShow();
      const restored = store.getSnapshot();
      expect(restored.rawInput).assertEqual('');
      expect(restored.currentPinyin).assertEqual('');
      expect(restored.pinyinCombinations.length).assertEqual(0);
      expect(restored.candidates.length).assertEqual(0);
      expect(restored.candidatePage).assertEqual(0);
      expect(restored.highlightedIndex).assertEqual(-1);
    });

    it('stage1168RejectedProductionBundleLeavesLiveXiaoheHandleUntouched', 0, () => {
      const gateway = new ReloadableSchemeGateway();
      const engine = new EngineCoordinator(gateway);
      expect(engine.initialize().success).assertTrue();
      gateway.failProductionBundle = true;

      const switched = engine.changeScheme('xiaohe-yinxing', '/files/production.hsyx');

      expect(switched.success).assertFalse();
      expect(engine.getActiveSchemeId()).assertEqual('xiaohe');
      expect(engine.isInitialized()).assertTrue();
      expect(gateway.destroyedHandles.length).assertEqual(0);
      expect(engine.processKey('n').success).assertTrue();
    });

    it('repeatedDeleteEventsStaySerialAndDoNotOvertakeNewInput', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new OrderedImeInputService();
      store.markSessionStarted();
      const sessionController = new InputSessionController(store, imeService, createFakeEngineCoordinator());
      const controller = new KeyboardController(sessionController, new FakeNativeGateway());
      const deleteGate = imeService.gateNextDelete();

      const firstDelete = controller.handleAction({ type: KeyboardActionType.DELETE });
      const repeatedDelete = controller.handleAction({ type: KeyboardActionType.DELETE });
      const input = controller.handleAction({ type: KeyboardActionType.LETTER, letter: 'z' });
      await nextTask();
      expect(imeService.events.join(',')).assertEqual('delete-start');

      deleteGate.resolve();
      await firstDelete;
      await repeatedDelete;
      await input;
      expect(imeService.events.join(',')).assertEqual(
        'delete-start,delete-end,delete-start,delete-end,insert-start:z,insert-end:z'
      );
    });

    it('chineseModeLetterUpdatesStoreWithoutEditorInsert', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new FakeImeInputService();
      const gateway = new FakeNativeGateway();
      const engineCoordinator = new EngineCoordinator(gateway);
      store.markSessionStarted();
      const controller = new InputSessionController(store, imeService, engineCoordinator);
      controller.toggleKeyboardMode();

      const result = await controller.insertLetter('Q');

      expect(result.success).assertEqual(true);
      expect(imeService.insertedTexts.length).assertEqual(0);
      expect(store.getSnapshot().rawInput).assertEqual('q');
      expect(store.getSnapshot().preeditText).assertEqual('q');
      expect(gateway.processKeys[0]).assertEqual('q');
    });

    it('quanpinKeepsRawCodeInTheCandidateBarWhenEditorPreviewIsSupported', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new FakeImeInputService();
      const gateway = new QuanpinGateway();
      const engineCoordinator = new EngineCoordinator(gateway);
      expect(engineCoordinator.initialize('quanpin').success).assertTrue();
      store.markSessionStarted();
      const context = createUnknownEditorContext();
      context.textPreviewSupported = true;
      store.applyEditorContext(context);
      const controller = new InputSessionController(store, imeService, engineCoordinator);

      const result = await controller.insertLetter('n');

      expect(result.success).assertTrue();
      expect(imeService.previewSupportedValues.length).assertEqual(1);
      expect(imeService.previewSupportedValues[0]).assertFalse();
      expect(imeService.insertedTexts.length).assertEqual(0);
      expect(store.getSnapshot().cursorPreeditVisible === true).assertFalse();
    });

    it('quanpinLetterProtocolGuardRollsBackBeforeAnyEditorCommit', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new FakeImeInputService();
      const gateway = new BrokenQuanpinCommitGateway();
      const engineCoordinator = new EngineCoordinator(gateway);
      expect(engineCoordinator.initialize('quanpin').success).assertTrue();
      store.markSessionStarted();
      store.applyEditorContext(createUnknownEditorContext());
      const controller = new InputSessionController(store, imeService, engineCoordinator);

      const result = await controller.insertLetter('g');

      expect(result.success).assertFalse();
      expect(imeService.insertedTexts.length).assertEqual(0);
      expect(imeService.previewTexts.length).assertEqual(0);
      expect(store.getSnapshot().rawInput).assertEqual('');
      expect(gateway.resetCount).assertEqual(1);
      expect(gateway.processKeys.join(',')).assertEqual('g');
    });

    it('quanpinNoCandidateActionsNeverFinishRawAsciiIntoTheEditor', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new FakeImeInputService();
      const gateway = new QuanpinGateway();
      const engineCoordinator = new EngineCoordinator(gateway);
      expect(engineCoordinator.initialize('quanpin').success).assertTrue();
      store.markSessionStarted();
      store.applyEditorContext(createUnknownEditorContext());
      const controller = new InputSessionController(store, imeService, engineCoordinator);

      await controller.insertLetter('g');
      await controller.insertSpace();
      expect(imeService.finishPreviewCount).assertEqual(0);
      expect(imeService.clearPreviewCount).assertEqual(1);
      expect(imeService.insertedTexts.join(',')).assertEqual(' ');

      await controller.insertLetter('j');
      await controller.sendEnter();
      expect(imeService.finishPreviewCount).assertEqual(0);
      expect(imeService.clearPreviewCount).assertEqual(2);
      expect(imeService.enterCount).assertEqual(1);

      await controller.insertLetter('d');
      await controller.insertCharacter('，');
      expect(imeService.finishPreviewCount).assertEqual(0);
      expect(imeService.clearPreviewCount).assertEqual(3);
      expect(imeService.insertedTexts.join(',')).assertEqual(' ,，');
    });

    it('stage1167TopScreenCommitsOnceAndStoresNewSegment', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new FakeImeInputService();
      const gateway = new AutomaticCommitGateway('e');
      const controller = new InputSessionController(store, imeService, new EngineCoordinator(gateway));
      store.markSessionStarted();
      controller.toggleKeyboardMode();

      const result = await controller.insertLetter('e');

      expect(result.success).assertTrue();
      expect(imeService.insertedTexts.length).assertEqual(1);
      expect(imeService.insertedTexts[0]).assertEqual('𠮷😀');
      expect(imeService.previewTexts.length).assertEqual(1);
      expect(imeService.previewTexts[0]).assertEqual('e');
      expect(store.getSnapshot().rawInput).assertEqual('e');
      expect(store.getSnapshot().candidates[0].text).assertEqual('新段');
      expect(gateway.processKeys.join(',')).assertEqual('e');
    });

    it('stage1167ForwardSplitCommitsCandidateOnceAndKeepsRightRemainder', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new FakeImeInputService();
      const gateway = new AutomaticCommitGateway('vv', '正向切分段', '正向切分段');
      const controller = new InputSessionController(store, imeService, new EngineCoordinator(gateway));
      store.markSessionStarted();
      controller.toggleKeyboardMode();

      const result = await controller.insertLetter('v');

      expect(result.success).assertTrue();
      expect(imeService.insertedTexts.length).assertEqual(1);
      expect(imeService.insertedTexts[0]).assertEqual('正向切分段');
      expect(imeService.previewTexts.length).assertEqual(1);
      expect(imeService.previewTexts[0]).assertEqual('vv');
      expect(store.getSnapshot().rawInput).assertEqual('vv');
      expect(store.getSnapshot().candidates[0].text).assertEqual('正向切分段');
      expect(gateway.processKeys.join(',')).assertEqual('v');
    });

    it('stage1167ReverseSplitCommitsLiteralLeftOnceAndKeepsLegalSuffix', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new FakeImeInputService();
      const gateway = new AutomaticCommitGateway('vvv', 'u', '反向合法后段');
      const controller = new InputSessionController(store, imeService, new EngineCoordinator(gateway));
      store.markSessionStarted();
      controller.toggleKeyboardMode();

      const result = await controller.insertLetter('v');

      expect(result.success).assertTrue();
      expect(imeService.insertedTexts.length).assertEqual(1);
      expect(imeService.insertedTexts[0]).assertEqual('u');
      expect(imeService.previewTexts.length).assertEqual(1);
      expect(imeService.previewTexts[0]).assertEqual('vvv');
      expect(store.getSnapshot().rawInput).assertEqual('vvv');
      expect(store.getSnapshot().candidates[0].text).assertEqual('反向合法后段');
      expect(gateway.processKeys.join(',')).assertEqual('v');
    });

    it('stage1167AutoCommitDoesNotCreateAnEmptySecondPreview', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new FakeImeInputService();
      const gateway = new AutomaticCommitGateway('');
      const controller = new InputSessionController(store, imeService, new EngineCoordinator(gateway));
      store.markSessionStarted();
      controller.toggleKeyboardMode();

      const result = await controller.insertLetter('d');

      expect(result.success).assertTrue();
      expect(imeService.insertedTexts.length).assertEqual(1);
      expect(imeService.previewTexts.length).assertEqual(0);
      expect(store.getSnapshot().rawInput).assertEqual('');
    });

    it('preciseStage2AutomaticCommitFailureRestoresOriginalCodeAndCandidates', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new CandidateTransactionImeService([0]);
      const gateway = new StatefulTopScreenGateway();
      const controller = new InputSessionController(store, imeService, new EngineCoordinator(gateway));
      store.markSessionStarted();
      controller.toggleKeyboardMode();

      await controller.insertLetter('a');
      await controller.insertLetter('b');
      await controller.insertLetter('c');
      await controller.insertLetter('d');
      const before = store.getSnapshot();

      const result = await controller.insertLetter('e');

      const restored = store.getSnapshot();

      expect(result.success).assertFalse();
      expect(imeService.insertAttempts).assertEqual(1);
      expect(imeService.insertedTexts.length).assertEqual(0);
      expect(gateway.resetCount).assertEqual(1);
      expect(restored.rawInput).assertEqual('abcd');
      expect(restored.candidates.length).assertEqual(2);
      expect(restored.candidates[0].id).assertEqual(before.candidates[0].id);
      expect(restored.candidates[1].id).assertEqual(before.candidates[1].id);
      expect(gateway.processKeys.join(',')).assertEqual('a,b,c,d,e,a,b,c,d');

      const deleted = await controller.deleteBackward();
      expect(deleted.success).assertTrue();
      expect(store.getSnapshot().rawInput).assertEqual('abc');
    });

    it('preciseStage2PreviewFailureAfterCommitKeepsTheNewTailWithoutReplayingOldCode', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new FakeImeInputService();
      const gateway = new StatefulTopScreenGateway();
      const controller = new InputSessionController(store, imeService, new EngineCoordinator(gateway));
      store.markSessionStarted();
      controller.toggleKeyboardMode();

      await controller.insertLetter('a');
      await controller.insertLetter('b');
      await controller.insertLetter('c');
      await controller.insertLetter('d');
      imeService.failNextPreview = true;

      const fifth = await controller.insertLetter('e');

      expect(fifth.success).assertFalse();
      expect(imeService.insertedTexts.join(',')).assertEqual('𠮷😀');
      expect(gateway.resetCount).assertEqual(0);
      expect(gateway.processKeys.join(',')).assertEqual('a,b,c,d,e');
      expect(store.getSnapshot().rawInput).assertEqual('e');
      expect(store.getSnapshot().candidates[0].text).assertEqual('新段');

      const sixth = await controller.insertLetter('f');

      expect(sixth.success).assertTrue();
      expect(imeService.insertedTexts.join(',')).assertEqual('𠮷😀');
      expect(gateway.processKeys.join(',')).assertEqual('a,b,c,d,e,f');
      expect(store.getSnapshot().rawInput).assertEqual('ef');
    });

    it('preciseStage2RapidFifthAndSixthKeysCommitOnceAndReplayInOrder', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new OrderedImeInputService();
      const gateway = new StatefulTopScreenGateway();
      const sessionController = new InputSessionController(store, imeService, new EngineCoordinator(gateway));
      const controller = new KeyboardController(sessionController, gateway);
      store.markSessionStarted();
      sessionController.toggleKeyboardMode();

      await controller.handleAction({ type: KeyboardActionType.LETTER, letter: 'a' });
      await controller.handleAction({ type: KeyboardActionType.LETTER, letter: 'b' });
      await controller.handleAction({ type: KeyboardActionType.LETTER, letter: 'c' });
      await controller.handleAction({ type: KeyboardActionType.LETTER, letter: 'd' });
      const commitGate = imeService.gateNextInsert();

      const fifth = controller.handleAction({ type: KeyboardActionType.LETTER, letter: 'e' });
      const sixth = controller.handleAction({ type: KeyboardActionType.LETTER, letter: 'f' });
      await nextTask();

      expect(imeService.events.join(',')).assertEqual('insert-start:𠮷😀');
      expect(gateway.processKeys.join(',')).assertEqual('a,b,c,d,e');
      commitGate.resolve();
      const fifthResult = await fifth;
      const sixthResult = await sixth;

      expect(fifthResult.success).assertTrue();
      expect(sixthResult.success).assertTrue();
      expect(imeService.insertedTexts.length).assertEqual(1);
      expect(imeService.insertedTexts[0]).assertEqual('𠮷😀');
      expect(gateway.processKeys.join(',')).assertEqual('a,b,c,d,e,f');
      expect(store.getSnapshot().rawInput).assertEqual('ef');
    });

    it('chineseModeDeletePrefersRustBackspaceWhenComposing', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new FakeImeInputService();
      const gateway = new FakeNativeGateway();
      const engineCoordinator = new EngineCoordinator(gateway);
      store.markSessionStarted();
      const controller = new InputSessionController(store, imeService, engineCoordinator);
      controller.toggleKeyboardMode();
      await controller.insertLetter('q');

      const result = await controller.deleteBackward();

      expect(result.success).assertEqual(true);
      expect(gateway.backspaceCount).assertEqual(1);
      expect(imeService.deleteCount).assertEqual(0);
      expect(store.getSnapshot().rawInput).assertEqual('');
    });

    it('chineseModeDeleteFallsBackToEditorWhenCompositionEmpty', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new FakeImeInputService();
      const gateway = new FakeNativeGateway();
      const engineCoordinator = new EngineCoordinator(gateway);
      store.markSessionStarted();
      const controller = new InputSessionController(store, imeService, engineCoordinator);
      controller.toggleKeyboardMode();

      const result = await controller.deleteBackward();

      expect(result.success).assertEqual(true);
      expect(gateway.backspaceCount).assertEqual(0);
      expect(imeService.deleteCount).assertEqual(1);
    });

    it('stage8PartialCandidateCommitKeepsRemainingComposition', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new FakeImeInputService();
      const gateway = new PartialCommitGateway();
      const engineCoordinator = new EngineCoordinator(gateway);
      store.markSessionStarted();
      const controller = new InputSessionController(store, imeService, engineCoordinator);
      controller.toggleKeyboardMode();
      store.updateComposition(createCandidateComposition('输入'));

      const result = await controller.commitCandidate(0);

      expect(result.success).assertEqual(true);
      expect(imeService.insertedTexts[0]).assertEqual('输入');
      expect(imeService.previewTexts[0]).assertEqual('fa');
      expect(imeService.previewSupportedValues[0]).assertFalse();
      expect(imeService.previewAnchorValues[0]).assertTrue();
      expect(store.getSnapshot().rawInput).assertEqual('fa');
      expect(store.getSnapshot().candidates[0].text).assertEqual('法');
    });

    it('stage8SpaceCommitsSentenceCandidateThroughEngine', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new FakeImeInputService();
      const gateway = new FullSentenceCommitGateway();
      const engineCoordinator = new EngineCoordinator(gateway);
      store.markSessionStarted();
      const controller = new InputSessionController(store, imeService, engineCoordinator);
      controller.toggleKeyboardMode();
      store.updateComposition({
        success: true,
        errorCode: ImeErrorCode.SUCCESS,
        errorMessage: '',
        rawInput: 'uurufa',
        preeditText: "shu'ru'fa",
        parsedSyllables: ['shu', 'ru', 'fa'],
        pendingCode: '',
        parserState: 'complete',
        candidates: [
          {
            id: 'stage8-shurufa',
            text: '输入法',
            reading: 'shu ru fa',
            source: 'stage8'
          }
        ],
        highlightedIndex: 0,
        hasNextPage: false,
        hasPreviousPage: false,
        candidatePage: 0,
        commitText: '',
        action: null,
        compositionFinished: false
      });

      const result = await controller.insertSpace();

      expect(result.success).assertEqual(true);
      expect(imeService.insertedTexts[0]).assertEqual('输入法');
      expect(store.getSnapshot().rawInput).assertEqual('');
    });

    it('candidateTransactionCommitsOnceThenConfirmsNativeAndLearning', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new CandidateTransactionImeService([1]);
      const gateway = new CandidateTransactionGateway();
      const controller = new InputSessionController(store, imeService, new EngineCoordinator(gateway));
      store.markSessionStarted();
      controller.toggleKeyboardMode();
      store.updateComposition(createCandidateComposition());

      const result = await controller.commitCandidate(0);

      expect(result.success).assertTrue();
      expect(imeService.insertAttempts).assertEqual(1);
      expect(imeService.insertedTexts.length).assertEqual(1);
      expect(imeService.insertedTexts[0]).assertEqual('你');
      expect(gateway.selectCount).assertEqual(1);
      expect(gateway.learningCount).assertEqual(1);
      expect(store.getSnapshot().rawInput).assertEqual('');
      expect(store.getSnapshot().candidates.length).assertEqual(0);
    });

    it('candidateTransactionKeepsCompositionWhenInsertReturnsFalse', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new CandidateTransactionImeService([0]);
      const gateway = new CandidateTransactionGateway();
      const controller = new InputSessionController(store, imeService, new EngineCoordinator(gateway));
      store.markSessionStarted();
      controller.toggleKeyboardMode();
      store.updateComposition(createCandidateComposition());

      const result = await controller.commitCandidate(0);
      const state = store.getSnapshot();

      expect(result.success).assertFalse();
      expect(imeService.insertAttempts).assertEqual(1);
      expect(imeService.insertedTexts.length).assertEqual(0);
      expect(gateway.selectCount).assertEqual(0);
      expect(gateway.learningCount).assertEqual(0);
      expect(state.rawInput).assertEqual('ni');
      expect(state.preeditText).assertEqual('ni');
      expect(state.candidates[0].text).assertEqual('你');
    });

    it('candidateTransactionKeepsCompositionWhenInsertThrows', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new CandidateTransactionImeService([-1]);
      const gateway = new CandidateTransactionGateway();
      const controller = new InputSessionController(store, imeService, new EngineCoordinator(gateway));
      store.markSessionStarted();
      controller.toggleKeyboardMode();
      store.updateComposition(createCandidateComposition());

      const result = await controller.commitCandidate(0);
      const state = store.getSnapshot();

      expect(result.success).assertFalse();
      expect(gateway.selectCount).assertEqual(0);
      expect(gateway.learningCount).assertEqual(0);
      expect(state.rawInput).assertEqual('ni');
      expect(state.preeditText).assertEqual('ni');
      expect(state.candidates.length).assertEqual(1);
    });

    it('candidateTransactionCanRetryAfterInsertFailureWithoutDuplicateLearning', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new CandidateTransactionImeService([0, 1]);
      const gateway = new CandidateTransactionGateway();
      const controller = new InputSessionController(store, imeService, new EngineCoordinator(gateway));
      store.markSessionStarted();
      controller.toggleKeyboardMode();
      store.updateComposition(createCandidateComposition());

      const first = await controller.commitCandidate(0);
      const second = await controller.commitCandidate(0);

      expect(first.success).assertFalse();
      expect(second.success).assertTrue();
      expect(imeService.insertAttempts).assertEqual(2);
      expect(imeService.insertedTexts.length).assertEqual(1);
      expect(gateway.selectCount).assertEqual(1);
      expect(gateway.learningCount).assertEqual(1);
      expect(store.getSnapshot().candidates.length).assertEqual(0);
    });

    it('candidateTransactionPrepareFailureDoesNotInsertOrLearn', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new CandidateTransactionImeService([1]);
      const gateway = new CandidateTransactionGateway();
      const controller = new InputSessionController(store, imeService, new EngineCoordinator(gateway));
      store.markSessionStarted();
      controller.toggleKeyboardMode();
      store.updateComposition(createCandidateComposition());

      const result = await controller.commitCandidate(5);

      expect(result.success).assertFalse();
      expect(imeService.insertAttempts).assertEqual(0);
      expect(gateway.selectCount).assertEqual(0);
      expect(gateway.learningCount).assertEqual(0);
      expect(store.getSnapshot().candidates.length).assertEqual(1);
    });

    it('candidateTransactionRejectsAStaleNegativeSourceIndexBeforeEditorOrNativeMutation', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new CandidateTransactionImeService([1]);
      const gateway = new CandidateTransactionGateway();
      const controller = new InputSessionController(store, imeService, new EngineCoordinator(gateway));
      store.markSessionStarted();
      controller.toggleKeyboardMode();
      store.updateComposition(createCandidateComposition());

      const result = await controller.commitCandidate(-1);

      expect(result.success).assertFalse();
      expect(result.errorCode).assertEqual(ImeErrorCode.INVALID_CANDIDATE);
      expect(imeService.insertAttempts).assertEqual(0);
      expect(gateway.selectCount).assertEqual(0);
      expect(store.getSnapshot().rawInput).assertEqual('ni');
    });

    it('guideCandidateAtomicCommitDoesNotTreatSemicolonAsRemainingRawInput', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new AtomicCandidatePreviewImeService();
      const gateway = new CandidateTransactionGateway();
      const controller = new InputSessionController(store, imeService, new EngineCoordinator(gateway));
      store.markSessionStarted();
      controller.toggleKeyboardMode();
      const guide = createCompositionResult(';q', ';q', 'complete');
      guide.candidates = [{
        id: 'guide-quick-symbol-q',
        text: '：“',
        reading: 'q',
        source: 'quick-symbol',
        consumedRawLen: 1
      }];
      guide.highlightedIndex = 0;
      store.updateComposition(guide);

      const result = await controller.commitCandidate(0);

      expect(result.success).assertTrue();
      expect(imeService.committedCandidateTexts.join('|')).assertEqual('：“');
      expect(imeService.predictedRemainingRawInputs.length).assertEqual(1);
      expect(imeService.predictedRemainingRawInputs[0]).assertEqual('');
      expect(imeService.previewTexts.length).assertEqual(0);
      expect(gateway.selectCount).assertEqual(1);
    });

    it('candidateTransactionClearsRetryStateWhenNativeConfirmationFailsAfterInsert', 0, async () => {
      const store = new InputSessionStore();
      const imeService = new CandidateTransactionImeService([1, 1]);
      const gateway = new CandidateTransactionGateway(false);
      const controller = new InputSessionController(store, imeService, new EngineCoordinator(gateway));
      store.markSessionStarted();
      controller.toggleKeyboardMode();
      store.updateComposition(createCandidateComposition());

      const first = await controller.commitCandidate(0);
      const second = await controller.commitCandidate(0);

      expect(first.success).assertFalse();
      expect(second.success).assertFalse();
      expect(imeService.insertAttempts).assertEqual(1);
      expect(imeService.insertedTexts.length).assertEqual(1);
      expect(gateway.selectCount).assertEqual(1);
      expect(gateway.learningCount).assertEqual(0);
      expect(gateway.resetCount).assertEqual(1);
      expect(store.getSnapshot().rawInput).assertEqual('');
      expect(store.getSnapshot().candidates.length).assertEqual(0);
    });

    it('stage9EngineCoordinatorLoadsUserModelThroughGateway', 0, () => {
      const gateway = new FakeNativeGateway();
      const engineCoordinator = new EngineCoordinator(gateway);

      engineCoordinator.initialize('xiaohe', 'lexicon.lex');
      const status = engineCoordinator.loadUserModel('/sandbox/user_model.dat');

      expect(status.loaded).assertTrue();
      expect(gateway.loadUserModelPath).assertEqual('/sandbox/user_model.dat');
    });

    it('stage9SessionLearningPolicyCanDisableLearning', 0, () => {
      const gateway = new FakeNativeGateway();
      const engineCoordinator = new EngineCoordinator(gateway);

      engineCoordinator.initialize('xiaohe', 'lexicon.lex');
      const status = engineCoordinator.setSessionLearningAllowed(false);

      expect(status.sessionLearningAllowed).assertFalse();
      expect(gateway.sessionLearningAllowedValues[0]).assertFalse();
    });

    it('stage9InputStopFlushesUserModelAndDisablesSessionLearning', 0, () => {
      const store = new InputSessionStore();
      const gateway = new FakeNativeGateway();
      const engineCoordinator = new EngineCoordinator(gateway);
      const controller = new InputSessionController(store, new FakeImeInputService(), engineCoordinator);
      controller.toggleKeyboardMode();

      controller.handleInputStop();

      expect(gateway.flushUserModelCount >= 1).assertTrue();
      expect(gateway.sessionLearningAllowedValues[gateway.sessionLearningAllowedValues.length - 1]).assertFalse();
    });

    it('stage9HideKeyboardFlushesUserModel', 0, async () => {
      const store = new InputSessionStore();
      const gateway = new FakeNativeGateway();
      const imeService = new FakeImeInputService();
      const engineCoordinator = new EngineCoordinator(gateway);
      const controller = new InputSessionController(store, imeService, engineCoordinator);
      controller.toggleKeyboardMode();
      store.markSessionStarted();
      store.markKeyboardVisible();

      const result = await controller.hideKeyboard();

      expect(result.success).assertTrue();
      expect(gateway.flushUserModelCount >= 1).assertTrue();
      expect(imeService.hideCount).assertEqual(1);
    });

    it('stage9ClearUserModelRoutesThroughApplicationService', 0, () => {
      const store = new InputSessionStore();
      const gateway = new FakeNativeGateway();
      const engineCoordinator = new EngineCoordinator(gateway);
      const controller = new InputSessionController(store, new FakeImeInputService(), engineCoordinator);
      controller.toggleKeyboardMode();

      controller.clearUserModel();

      expect(gateway.clearUserModelCount).assertEqual(1);
    });
  });
}
