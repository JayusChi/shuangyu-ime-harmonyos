import { resolveCandidateUiMode, resolveVisibleCandidates } from '../domain/candidate/CandidateUiPolicy';
import { ClipboardReverseLookupResult, CLIPBOARD_REVERSE_CODE, CLIPBOARD_REVERSE_LABEL } from '../domain/direct/ClipboardReverseLookup';
import { isConvenienceInput } from '../domain/keyboard/ConvenienceInput';
import { EnglishShiftController } from '../application/EnglishShiftController';
import { KeyboardModePolicy } from '../application/KeyboardModePolicy';
import { ImeErrorCode, imeErrorMessage } from '../common/error/ImeError';
import {
  copyEditorContext,
  createUnknownEditorContext,
  EditorContext,
  EnterAction,
  ShiftState
} from '../domain/editor/EditorContext';
import { KeyboardMode } from '../domain/keyboard/KeyboardAction';
import { MIN_CANDIDATES_FOR_EXPANSION } from '../domain/candidate/CandidateExpansionPolicy';
import { Candidate, CompositionResult, ParserState } from '../infrastructure/native/NativeEngineTypes';
import {
  copyScreenMetrics,
  SAFE_FALLBACK_SCREEN_METRICS_PX,
  ScreenMetricsPx,
  screenMetricsEqual
} from '../domain/display/ScreenMetrics';
import {
  AiPresentationState,
  AiRequestState,
  AiSuggestion,
  copyAiPresentationState,
  createIdleAiPresentationState
} from '../domain/ai/AiContracts';
import {
  copyVoicePresentationState,
  createIdleVoicePresentationState,
  VoicePresentationState,
  VoiceSessionState
} from '../domain/voice/VoiceContracts';
import {
  copyInputMethodCapabilityState,
  createUnknownInputMethodCapabilityState,
  InputMethodCapabilityState
} from '../domain/security/InputMethodCapabilityState';
import {
  copyLocalAssociationSuggestions,
  LocalAssociationSuggestion
} from '../domain/ai/LocalAssociationContracts';

export interface InputSessionState {
  hardwareCandidatePaging?: boolean;
  sessionActive: boolean;
  keyboardVisible: boolean;
  keyboardMode: KeyboardMode;
  editorConnected: boolean;
  editorContext: EditorContext;
  shiftState: ShiftState;
  chineseCapsLock: boolean;
  enterAction: EnterAction;
  candidateBarVisible: boolean;
  floatingCandidateVisible: boolean;
  floatingCandidateExpanded: boolean;
  /** 非空输入码当前是否由编辑器光标处的系统预编辑负责展示。 */
  cursorPreeditVisible: boolean;
  candidatePanelExpanded: boolean;
  candidatePageLoading: boolean;
  sessionLearningAllowed: boolean;
  capabilityState: InputMethodCapabilityState;
  aiPresentation: AiPresentationState;
  voicePresentation: VoicePresentationState;
  localAssociations: LocalAssociationSuggestion[];
  modeBeforeTransient: KeyboardMode;
  rawInput: string;
  preeditText: string;
  parsedSyllables: string[];
  pendingCode: string;
  displaySegments: string[];
  segmentBoundaries: number[];
  currentPinyin: string;
  pinyinCombinations: string[];
  parserState: ParserState;
  candidates: Candidate[];
  highlightedIndex: number;
  hasNextPage: boolean;
  hasPreviousPage: boolean;
  candidatePage: number;
  lastErrorCode: ImeErrorCode;
  lastErrorMessage: string;
  screenMetrics: ScreenMetricsPx;
}

export type InputSessionStateListener = () => void;

function aiPresentationEqual(left: AiPresentationState, right: AiPresentationState): boolean {
  if (left.state !== right.state || left.requestId !== right.requestId ||
    left.sessionGeneration !== right.sessionGeneration || left.action !== right.action ||
    left.providerKind !== right.providerKind || left.errorCode !== right.errorCode ||
    left.statusMessage !== right.statusMessage || left.suggestions.length !== right.suggestions.length) {
    return false;
  }
  for (let index = 0; index < left.suggestions.length; index += 1) {
    const leftSuggestion: AiSuggestion = left.suggestions[index];
    const rightSuggestion: AiSuggestion = right.suggestions[index];
    if (leftSuggestion.suggestionId !== rightSuggestion.suggestionId ||
      leftSuggestion.requestId !== rightSuggestion.requestId || leftSuggestion.text !== rightSuggestion.text ||
      leftSuggestion.label !== rightSuggestion.label || leftSuggestion.providerKind !== rightSuggestion.providerKind ||
      leftSuggestion.replacePolicy !== rightSuggestion.replacePolicy) {
      return false;
    }
  }
  return true;
}

function voicePresentationEqual(left: VoicePresentationState, right: VoicePresentationState): boolean {
  return left.state === right.state && left.voiceSessionId === right.voiceSessionId &&
    left.sessionGeneration === right.sessionGeneration && left.providerKind === right.providerKind &&
    left.language === right.language && left.interimText === right.interimText &&
    left.finalText === right.finalText && left.errorCode === right.errorCode &&
    left.statusMessage === right.statusMessage;
}

function createInitialState(): InputSessionState {
  const editorContext = createUnknownEditorContext();
  return {
    sessionActive: false,
    keyboardVisible: false,
    keyboardMode: KeyboardMode.ENGLISH,
    editorConnected: false,
    editorContext,
    shiftState: ShiftState.LOWERCASE,
    chineseCapsLock: false,
    enterAction: editorContext.enterAction,
    candidateBarVisible: false,
    floatingCandidateVisible: false,
    floatingCandidateExpanded: false,
    cursorPreeditVisible: false,
    candidatePanelExpanded: false,
    candidatePageLoading: false,
    sessionLearningAllowed: editorContext.learningAllowed,
    capabilityState: createUnknownInputMethodCapabilityState(),
    aiPresentation: createIdleAiPresentationState(),
    voicePresentation: createIdleVoicePresentationState(),
    localAssociations: [],
    modeBeforeTransient: KeyboardMode.CHINESE,
    rawInput: '',
    preeditText: '',
    parsedSyllables: [],
    pendingCode: '',
    displaySegments: [],
    segmentBoundaries: [],
    currentPinyin: '',
    pinyinCombinations: [],
    parserState: 'empty',
    candidates: [],
    highlightedIndex: -1,
    hasNextPage: false,
    hasPreviousPage: false,
    candidatePage: 0,
    lastErrorCode: ImeErrorCode.SUCCESS,
    lastErrorMessage: imeErrorMessage(ImeErrorCode.SUCCESS),
    screenMetrics: copyScreenMetrics(SAFE_FALLBACK_SCREEN_METRICS_PX)
  };
}

export class InputSessionStore {
  private hardwarePageSize: number = 0;
  private hardwareSchemeId: string = '';
  private hardwarePage: number = 0;
  private hardwarePageBase: number = 0;
  private hardwareBatchPageCounts: number[] = [];

  setHardwareCandidatePageSize(pageSize: number, schemeId: string = ''): void {
    const size = Number.isFinite(pageSize) ? Math.max(0, Math.min(9, Math.floor(pageSize))) : 0;
    if (size === this.hardwarePageSize && schemeId === this.hardwareSchemeId) { return; }
    this.hardwareSchemeId = schemeId;
    this.hardwarePageSize = size;
    this.resetHardwarePages();
    this.state.highlightedIndex = this.state.candidates.length > 0 ? 0 : -1;
    this.state.floatingCandidateExpanded = false;
    this.state.candidatePanelExpanded = false;
    this.notify();
  }

  resolveEngineCandidateIndex(index: number): number {
    if (this.hardwarePageSize <= 0) { return index; }
    const candidate = this.hardwareCandidates()[this.hardwarePage * this.hardwarePageSize + index];
    return candidate === undefined ? -1 : this.state.candidates.findIndex((item: Candidate): boolean => item.id === candidate.id);
  }

  /** Visit every numbered slice before crossing a native candidate batch. */
  moveHardwareCandidatePage(next: boolean): boolean {
    if (this.hardwarePageSize <= 0) { return false; }
    const target = this.hardwarePage + (next ? 1 : -1);
    if (target < 0 || target * this.hardwarePageSize >= this.hardwareCandidates().length) { return false; }
    this.hardwarePage = target;
    this.state.highlightedIndex = this.resolveEngineCandidateIndex(0);
    this.clearErrorInternal();
    this.notify();
    return true;
  }

  updateCandidateBatch(result: CompositionResult, previous: boolean): void {
    const oldPage = this.state.candidatePage;
    const oldCount = Math.max(1, Math.ceil(this.hardwareCandidates().length / Math.max(1, this.hardwarePageSize)));
    const oldBase = this.hardwarePageBase;
    const previousCount = this.hardwareBatchPageCounts[result.candidatePage];
    this.updateComposition(result, false);
    if (this.hardwarePageSize > 0 && result.candidatePage !== oldPage) {
      this.hardwareBatchPageCounts[oldPage] = oldCount;
      const count = Math.max(1, Math.ceil(this.hardwareCandidates().length / this.hardwarePageSize));
      this.hardwarePageBase = previous ? Math.max(0, oldBase - (previousCount ?? count)) : oldBase + oldCount;
      this.hardwarePage = previous ? count - 1 : 0;
      this.state.highlightedIndex = result.candidates.length > 0 ? this.resolveEngineCandidateIndex(0) : -1;
    }
    this.notify();
  }

  private hardwareCandidates(): Candidate[] {
    return resolveVisibleCandidates(resolveCandidateUiMode(this.hardwareSchemeId), this.state.rawInput, this.state.candidates);
  }

  private resetHardwarePages(): void {
    this.hardwarePage = 0;
    this.hardwarePageBase = 0;
    this.hardwareBatchPageCounts = [];
  }

  private clipboardReverseResult?: ClipboardReverseLookupResult;
  private clipboardReverseRevision: number = 0;

  beginClipboardReverseRequest(): number { return ++this.clipboardReverseRevision; }
  getClipboardReverseResult(): ClipboardReverseLookupResult | undefined { return this.clipboardReverseResult; }
  setClipboardReverseResult(request: number, result: ClipboardReverseLookupResult): void {
    if (request !== this.clipboardReverseRevision || this.state.rawInput !== CLIPBOARD_REVERSE_CODE ||
      this.state.editorContext.isPassword) { return; }
    this.clipboardReverseResult = result;
    this.clearErrorInternal();
    this.setFunctionalCandidateDisplay(CLIPBOARD_REVERSE_LABEL, result.text || CLIPBOARD_REVERSE_LABEL);
  }
  private clearClipboardReverseResult(): void {
    this.clipboardReverseRevision += 1;
    this.clipboardReverseResult = undefined;
  }

  private state: InputSessionState = createInitialState();
  private sessionGeneration: number = 0;
  private readonly modePolicy: KeyboardModePolicy = new KeyboardModePolicy();
  private readonly shiftController: EnglishShiftController = new EnglishShiftController();
  private lastTextKeyboardMode: KeyboardMode = KeyboardMode.CHINESE;
  private listeners: InputSessionStateListener[] = [];

  getSnapshot(): InputSessionState {
    const start = this.hardwarePageSize > 0 ? this.hardwarePage * this.hardwarePageSize : 0;
    const available = this.hardwarePageSize > 0 ? this.hardwareCandidates() : this.state.candidates;
    const candidates = this.hardwarePageSize > 0 ? available.slice(start, start + this.hardwarePageSize) : available.slice();
    const highlighted = this.state.candidates[this.state.highlightedIndex];
    return {
      hardwareCandidatePaging: this.hardwarePageSize > 0,
      sessionActive: this.state.sessionActive,
      keyboardVisible: this.state.keyboardVisible,
      keyboardMode: this.state.keyboardMode,
      editorConnected: this.state.editorConnected,
      editorContext: copyEditorContext(this.state.editorContext),
      shiftState: this.state.shiftState,
      chineseCapsLock: this.state.chineseCapsLock,
      enterAction: this.state.enterAction,
      candidateBarVisible: this.state.candidateBarVisible,
      floatingCandidateVisible: this.state.floatingCandidateVisible,
      floatingCandidateExpanded: this.state.floatingCandidateExpanded,
      cursorPreeditVisible: this.state.cursorPreeditVisible,
      candidatePanelExpanded: this.state.candidatePanelExpanded,
      candidatePageLoading: this.state.candidatePageLoading,
      sessionLearningAllowed: this.state.sessionLearningAllowed,
      capabilityState: copyInputMethodCapabilityState(this.state.capabilityState),
      aiPresentation: copyAiPresentationState(this.state.aiPresentation),
      voicePresentation: copyVoicePresentationState(this.state.voicePresentation),
      localAssociations: copyLocalAssociationSuggestions(this.state.localAssociations),
      modeBeforeTransient: this.state.modeBeforeTransient,
      rawInput: this.state.rawInput,
      preeditText: this.state.preeditText,
      parsedSyllables: this.state.parsedSyllables.slice(),
      pendingCode: this.state.pendingCode,
      displaySegments: this.state.displaySegments.slice(),
      segmentBoundaries: this.state.segmentBoundaries.slice(),
      currentPinyin: this.state.currentPinyin,
      pinyinCombinations: this.state.pinyinCombinations.slice(),
      parserState: this.state.parserState,
      candidates,
      highlightedIndex: highlighted === undefined ? -1 : candidates.findIndex((item: Candidate): boolean => item.id === highlighted.id),
      hasNextPage: this.state.hasNextPage || (this.hardwarePageSize > 0 && start + candidates.length < available.length),
      hasPreviousPage: this.state.hasPreviousPage || this.hardwarePage > 0,
      candidatePage: this.hardwarePageSize > 0 ? this.hardwarePageBase + this.hardwarePage : this.state.candidatePage,
      lastErrorCode: this.state.lastErrorCode,
      lastErrorMessage: this.state.lastErrorMessage,
      screenMetrics: copyScreenMetrics(this.state.screenMetrics)
    };
  }

  subscribe(listener: InputSessionStateListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unsubscribe(listener: InputSessionStateListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  getSessionGeneration(): number {
    return this.sessionGeneration;
  }

  isAiPresentationIdle(): boolean {
    return this.state.aiPresentation.state === AiRequestState.IDLE;
  }

  isVoicePresentationIdle(): boolean {
    return this.state.voicePresentation.state === VoiceSessionState.IDLE;
  }

  advanceSessionGeneration(): number {
    this.clearClipboardReverseResult();
    this.sessionGeneration += 1;
    return this.sessionGeneration;
  }

  markSessionStarted(): void {
    this.advanceSessionGeneration();
    this.state.sessionActive = true;
    this.state.editorConnected = true;
    this.state.chineseCapsLock = false;
    this.clearAssistInternal();
    this.clearErrorInternal();
    this.notify();
  }

  markSessionStopped(): void {
    this.advanceSessionGeneration();
    this.state.sessionActive = false;
    this.state.keyboardVisible = false;
    this.state.editorConnected = false;
    this.state.keyboardMode = KeyboardMode.ENGLISH;
    this.state.editorContext = createUnknownEditorContext();
    this.state.enterAction = EnterAction.ENTER;
    this.state.candidateBarVisible = false;
    this.state.floatingCandidateVisible = false;
    this.state.cursorPreeditVisible = false;
    this.state.candidatePanelExpanded = false;
    this.state.floatingCandidateExpanded = false;
    this.state.candidatePageLoading = false;
    this.state.sessionLearningAllowed = false;
    this.state.chineseCapsLock = false;
    this.clearAssistInternal();
    this.shiftController.reset();
    this.state.shiftState = this.shiftController.getState();
    this.clearCompositionInternal();
    this.clearErrorInternal();
    this.notify();
  }

  applyEditorContext(context: EditorContext, globalLearningEnabled: boolean = true): KeyboardMode {
    this.state.editorContext = copyEditorContext(context);
    this.state.keyboardMode = this.modePolicy.initialMode(context, this.lastTextKeyboardMode);
    this.state.modeBeforeTransient = this.modePolicy.isTextMode(this.state.keyboardMode)
      ? this.state.keyboardMode
      : KeyboardMode.ENGLISH;
    this.state.enterAction = context.enterAction;
    this.state.sessionLearningAllowed = context.learningAllowed && globalLearningEnabled;
    this.state.chineseCapsLock = false;
    this.shiftController.reset();
    this.clearAssistInternal();
    this.state.shiftState = this.shiftController.getState();
    this.clearCompositionInternal();
    this.refreshCandidateVisibility();
    this.clearErrorInternal();
    this.notify();
    return this.state.keyboardMode;
  }

  markKeyboardVisible(): void {
    this.state.keyboardVisible = true;
    this.clearErrorInternal();
    this.notify();
  }

  markKeyboardHidden(): void {
    this.state.keyboardVisible = false;
    this.state.floatingCandidateVisible = false;
    this.state.candidatePanelExpanded = false;
    this.state.floatingCandidateExpanded = false;
    this.state.candidatePageLoading = false;
    this.state.chineseCapsLock = false;
    this.clearAssistInternal();
    this.notify();
  }

  toggleKeyboardMode(): KeyboardMode {
    let target = KeyboardMode.ENGLISH;
    if (this.state.keyboardMode === KeyboardMode.ENGLISH) {
      target = KeyboardMode.CHINESE;
    } else if (this.state.keyboardMode !== KeyboardMode.CHINESE) {
      target = this.modePolicy.restoreTransientMode(this.state.editorContext, this.state.modeBeforeTransient);
    }
    return this.switchKeyboardMode(target, true);
  }

  toggleNumberMode(): KeyboardMode {
    return this.switchKeyboardMode(KeyboardMode.NUMBER, true);
  }

  toggleSymbolMode(): KeyboardMode {
    return this.switchKeyboardMode(KeyboardMode.SYMBOL, true);
  }

  switchKeyboardMode(target: KeyboardMode, userInitiated: boolean = true): KeyboardMode {
    let resolvedTarget = target;
    if (target === this.state.keyboardMode &&
      (target === KeyboardMode.NUMBER || target === KeyboardMode.SYMBOL)) {
      resolvedTarget = this.modePolicy.restoreTransientMode(this.state.editorContext, this.state.modeBeforeTransient);
    }

    if (!this.modePolicy.isAllowed(this.state.editorContext, resolvedTarget)) {
      resolvedTarget = this.modePolicy.fallbackMode(this.state.editorContext);
    }

    if ((resolvedTarget === KeyboardMode.NUMBER || resolvedTarget === KeyboardMode.SYMBOL) &&
      this.modePolicy.isTextMode(this.state.keyboardMode)) {
      this.state.modeBeforeTransient = this.state.keyboardMode;
    }

    this.state.keyboardMode = resolvedTarget;
    this.state.chineseCapsLock = false;
    if (userInitiated && this.modePolicy.isTextMode(resolvedTarget) &&
      this.state.editorContext.chineseModeAllowed && this.state.editorContext.englishModeAllowed) {
      this.lastTextKeyboardMode = resolvedTarget;
    }
    if (resolvedTarget !== KeyboardMode.CHINESE && !isConvenienceInput(this.state.rawInput)) {
      this.clearCompositionInternal();
    }
    if (resolvedTarget === KeyboardMode.NUMBER || resolvedTarget === KeyboardMode.PHONE) {
      this.shiftController.reset();
      this.state.shiftState = this.shiftController.getState();
    }
    this.refreshCandidateVisibility();
    this.clearErrorInternal();
    this.notify();
    return this.state.keyboardMode;
  }

  pressShift(timestamp: number): ShiftState {
    if (this.state.keyboardMode !== KeyboardMode.ENGLISH) {
      return this.state.shiftState;
    }
    this.state.shiftState = this.shiftController.pressShift(timestamp);
    this.notify();
    return this.state.shiftState;
  }

  toggleChineseCapsLock(): boolean {
    if (this.state.keyboardMode !== KeyboardMode.CHINESE || this.state.rawInput.length > 0) {
      return false;
    }
    this.state.chineseCapsLock = !this.state.chineseCapsLock;
    this.clearErrorInternal();
    this.notify();
    return true;
  }

  resetChineseCapsLock(): void {
    if (!this.state.chineseCapsLock) {
      return;
    }
    this.state.chineseCapsLock = false;
    this.notify();
  }

  transformEnglishLetter(letter: string): string {
    return this.shiftController.transformLetter(letter);
  }

  markEnglishLetterCommitted(): void {
    this.state.shiftState = this.shiftController.letterCommitted();
    this.notify();
  }

  resetShift(): void {
    this.shiftController.reset();
    this.state.shiftState = this.shiftController.getState();
    this.notify();
  }

  updateComposition(result: CompositionResult, notify: boolean = true): void {
    if (result.rawInput !== this.state.rawInput || result.candidatePage === 0) { this.resetHardwarePages(); }
    this.hardwarePage = 0;
    if (this.state.rawInput !== result.rawInput) { this.clearClipboardReverseResult(); }
    this.state.localAssociations = [];
    this.state.candidatePageLoading = false;
    if (!this.isCandidateBarAllowed(result.rawInput)) {
      this.clearCompositionInternal();
      if (result.success) {
        this.clearErrorInternal();
      } else {
        this.recordErrorInternal(result.errorCode, result.errorMessage);
      }
      this.refreshCandidateVisibility();
      this.notify();
      return;
    }
    if (this.state.rawInput !== result.rawInput) { this.state.floatingCandidateExpanded = false; }
    this.state.rawInput = result.rawInput;
    this.state.preeditText = result.preeditText;
    this.state.parsedSyllables = result.parsedSyllables;
    this.state.pendingCode = result.pendingCode;
    this.state.displaySegments = result.displaySegments ?? [];
    this.state.segmentBoundaries = result.segmentBoundaries ?? [];
    this.state.currentPinyin = result.currentPinyin ?? '';
    this.state.pinyinCombinations = result.pinyinCombinations ?? [];
    if (result.rawInput.length > 0) {
      this.state.chineseCapsLock = false;
    }
    this.state.parserState = result.parserState;
    this.state.candidates = result.candidates;
    if (this.clipboardReverseResult !== undefined && result.rawInput === CLIPBOARD_REVERSE_CODE) {
      this.state.candidates.forEach((candidate: Candidate): void => {
        if (candidate.source === 'functional' && candidate.text === CLIPBOARD_REVERSE_LABEL) {
          candidate.displayText = this.clipboardReverseResult?.text || CLIPBOARD_REVERSE_LABEL;
        }
      });
    }
    this.state.highlightedIndex = result.highlightedIndex;
    this.state.hasNextPage = result.hasNextPage;
    this.state.hasPreviousPage = result.hasPreviousPage;
    this.state.candidatePage = result.candidatePage;
    if (result.rawInput.length === 0) {
      this.state.cursorPreeditVisible = false;
    }
    if (result.success) {
      this.clearErrorInternal();
    } else {
      this.recordErrorInternal(result.errorCode, result.errorMessage);
    }
    // The three-candidate rule gates opening only. Once open, a short final
    // page must remain visible so the user can navigate back or collapse it.
    if (this.state.candidates.length === 0 || !result.success) {
      this.state.candidatePanelExpanded = false;
    this.state.floatingCandidateExpanded = false;
    }
    this.refreshCandidateVisibility();
    if (notify) { this.notify(); }
  }

  setFunctionalCandidateDisplay(label: string, displayText: string): void {
    this.state.candidates.forEach((candidate: Candidate): void => {
      if (candidate.source === 'functional' && candidate.text === label) { candidate.displayText = displayText; }
    });
    this.notify();
  }

  clearComposition(): void {
    this.clearCompositionInternal();
    this.refreshCandidateVisibility();
    this.notify();
  }

  setFloatingCandidateExpanded(expanded: boolean): boolean {
    const resolved = expanded && this.hardwarePageSize === 0 && this.state.sessionActive && this.state.candidates.length > 0 &&
      this.state.lastErrorCode === ImeErrorCode.SUCCESS;
    if (resolved !== this.state.floatingCandidateExpanded) {
      this.state.floatingCandidateExpanded = resolved;
      this.notify();
    }
    return resolved;
  }

  setFloatingCandidateVisible(visible: boolean): void {
    if (this.state.floatingCandidateVisible === visible) {
      return;
    }
    this.state.floatingCandidateVisible = visible;
    this.notify();
  }

  setCursorPreeditVisible(visible: boolean): void {
    const resolved = visible && this.state.rawInput.length > 0;
    if (this.state.cursorPreeditVisible === resolved) {
      return;
    }
    this.state.cursorPreeditVisible = resolved;
    this.notify();
  }

  setCandidatePanelExpanded(expanded: boolean): boolean {
    const canExpand = this.hardwarePageSize === 0 && this.state.sessionActive &&
      this.state.keyboardVisible &&
      this.state.candidateBarVisible &&
      this.state.candidates.length >= MIN_CANDIDATES_FOR_EXPANSION &&
      this.state.lastErrorCode === ImeErrorCode.SUCCESS;
    const resolved = expanded && canExpand;
    if (this.state.candidatePanelExpanded === resolved) {
      return resolved;
    }
    this.state.candidatePanelExpanded = resolved;
    if (!resolved) {
      this.state.candidatePageLoading = false;
    }
    this.notify();
    return resolved;
  }

  setCandidatePageLoading(loading: boolean): void {
    const resolved = loading && this.state.candidatePanelExpanded;
    if (this.state.candidatePageLoading === resolved) {
      return;
    }
    this.state.candidatePageLoading = resolved;
    this.notify();
  }

  moveCandidateHighlight(delta: number): number {
    if (!Number.isInteger(delta) || delta === 0 || this.state.candidates.length === 0) {
      return this.state.highlightedIndex;
    }
    if (this.hardwarePageSize > 0) {
      const page = this.getSnapshot();
      const selected = Math.max(0, Math.min(page.candidates.length - 1, Math.max(0, page.highlightedIndex) + delta));
      this.state.highlightedIndex = this.resolveEngineCandidateIndex(selected);
      this.notify();
      return selected;
    }
    const current = this.state.highlightedIndex >= 0 &&
      this.state.highlightedIndex < this.state.candidates.length
      ? this.state.highlightedIndex
      : 0;
    const resolved = Math.max(0, Math.min(this.state.candidates.length - 1, current + delta));
    if (resolved !== this.state.highlightedIndex) {
      this.state.highlightedIndex = resolved;
      this.notify();
    }
    return resolved;
  }

  updateLearningAllowed(allowed: boolean): void {
    if (this.state.sessionLearningAllowed === allowed) {
      return;
    }
    this.state.sessionLearningAllowed = allowed;
    this.notify();
  }

  setInputMethodCapabilityState(capabilityState: InputMethodCapabilityState): void {
    this.state.capabilityState = copyInputMethodCapabilityState(capabilityState);
    this.notify();
  }

  updateAiPresentation(presentation: AiPresentationState): void {
    if (aiPresentationEqual(this.state.aiPresentation, presentation)) {
      return;
    }
    this.state.aiPresentation = copyAiPresentationState(presentation);
    this.notify();
  }

  updateVoicePresentation(presentation: VoicePresentationState): void {
    if (voicePresentationEqual(this.state.voicePresentation, presentation)) {
      return;
    }
    this.state.voicePresentation = copyVoicePresentationState(presentation);
    this.notify();
  }

  clearAssistPresentation(): void {
    this.clearAssistInternal();
    this.notify();
  }

  updateLocalAssociations(suggestions: LocalAssociationSuggestion[]): void {
    this.state.localAssociations = copyLocalAssociationSuggestions(suggestions);
    this.notify();
  }

  clearLocalAssociations(): void {
    if (this.state.localAssociations.length === 0) {
      return;
    }
    this.state.localAssociations = [];
    this.notify();
  }

  recordError(code: ImeErrorCode, message?: string): void {
    this.recordErrorInternal(code, message);
    this.refreshCandidateVisibility();
    this.notify();
  }

  clearError(): void {
    this.clearErrorInternal();
    this.refreshCandidateVisibility();
    this.notify();
  }

  resetAll(): void {
    this.advanceSessionGeneration();
    this.state = createInitialState();
    this.lastTextKeyboardMode = KeyboardMode.CHINESE;
    this.shiftController.reset();
    this.notify();
  }

  setScreenMetrics(screenMetrics: ScreenMetricsPx): void {
    if (screenMetricsEqual(this.state.screenMetrics, screenMetrics)) {
      return;
    }
    this.state.screenMetrics = copyScreenMetrics(screenMetrics);
    this.notify();
  }

  private refreshCandidateVisibility(): void {
    const allowed = this.isCandidateBarAllowed();
    if (!allowed) {
      this.clearCompositionInternal();
    }
    // Text keyboards reserve the candidate row even when it has no content,
    // so the panel does not jump after the first composition update.
    this.state.candidateBarVisible = allowed;
  }

  private isCandidateBarAllowed(rawInput: string = this.state.rawInput): boolean {
    if (isConvenienceInput(rawInput)) {
      return !this.state.editorContext.isPassword &&
        (this.state.editorContext.chineseModeAllowed || this.state.editorContext.englishModeAllowed);
    }
    return this.modePolicy.shouldShowCandidateBar(
      this.state.editorContext,
      this.state.keyboardMode
    );
  }

  private clearCompositionInternal(): void {
    this.resetHardwarePages();
    this.clearClipboardReverseResult();
    this.state.rawInput = '';
    this.state.preeditText = '';
    this.state.parsedSyllables = [];
    this.state.pendingCode = '';
    this.state.displaySegments = [];
    this.state.segmentBoundaries = [];
    this.state.currentPinyin = '';
    this.state.pinyinCombinations = [];
    this.state.parserState = 'empty';
    this.state.candidates = [];
    this.state.highlightedIndex = -1;
    this.state.hasNextPage = false;
    this.state.hasPreviousPage = false;
    this.state.candidatePage = 0;
    this.state.floatingCandidateVisible = false;
    this.state.cursorPreeditVisible = false;
    this.state.candidatePanelExpanded = false;
    this.state.floatingCandidateExpanded = false;
    this.state.candidatePageLoading = false;
    this.state.localAssociations = [];
  }

  private clearAssistInternal(): void {
    this.state.aiPresentation = createIdleAiPresentationState();
    this.state.voicePresentation = createIdleVoicePresentationState();
    this.state.localAssociations = [];
  }

  private recordErrorInternal(code: ImeErrorCode, message?: string): void {
    this.state.lastErrorCode = code;
    this.state.lastErrorMessage = message ?? imeErrorMessage(code);
    this.state.candidatePanelExpanded = false;
    this.state.floatingCandidateExpanded = false;
    this.state.candidatePageLoading = false;
  }

  private clearErrorInternal(): void {
    this.state.lastErrorCode = ImeErrorCode.SUCCESS;
    this.state.lastErrorMessage = imeErrorMessage(ImeErrorCode.SUCCESS);
  }

  private notify(): void {
    this.listeners.slice().forEach((listener: InputSessionStateListener) => listener());
  }
}

const SHARED_INPUT_SESSION_STORE = new InputSessionStore();

export function getSharedInputSessionStore(): InputSessionStore {
  return SHARED_INPUT_SESSION_STORE;
}
