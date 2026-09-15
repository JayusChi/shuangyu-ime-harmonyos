import { isConvenienceInput } from '../domain/keyboard/ConvenienceInput';
import { ImeErrorCode } from '../common/error/ImeError';
import { Logger } from '../common/logging/Logger';
import { EditorExtendAction, KeyboardAction, KeyboardActionType } from '../domain/keyboard/KeyboardAction';
import { NativeEngineGateway } from '../infrastructure/native/NativeEngineGateway';
import { NativeEngineGatewayContract } from '../infrastructure/native/NativeEngineTypes';
import { InputSessionState, InputSessionStateListener } from '../state/InputSessionStore';
import { InputOperationResult, inputOperationFailed, inputOperationOk } from './InputOperationResult';
import { InputSessionController } from './InputSessionController';
import { FeedbackController } from './FeedbackController';
import { getSharedInputActionExecutor, SerialActionExecutor } from './SerialActionExecutor';
import { InputMethodSwitchCapabilities } from '../infrastructure/ime/InputMethodSwitcher';
import {
  canNavigateCandidatePage,
  CandidateExpansionAvailability,
  CandidatePageDirection
} from '../domain/candidate/CandidateExpansionPolicy';
import { SmartPeriodInputAction } from './SmartPeriodController';
import { inputMethodEngine } from '@kit.IMEKit';
import { AiAction } from '../domain/ai/AiContracts';
import { AssistAvailability } from '../domain/security/InputMethodCapabilityState';
import {
  CandidatePunctuationResolutionType,
  resolveCandidatePunctuation
} from '../domain/keyboard/CandidatePunctuationPolicy';

const TAG = 'KeyboardController';
const LOGGER = new Logger(TAG);

export class KeyboardController {
  private readonly sessionController: InputSessionController;
  private readonly nativeGateway: NativeEngineGatewayContract;
  private readonly feedbackController: FeedbackController;
  private readonly actionExecutor: SerialActionExecutor;
  private actionSequence: number = 0;
  private candidatePageNavigationInProgress: boolean = false;

  constructor(
    sessionController: InputSessionController = new InputSessionController(),
    nativeGateway: NativeEngineGatewayContract = new NativeEngineGateway(),
    feedbackController: FeedbackController = new FeedbackController(),
    actionExecutor: SerialActionExecutor = getSharedInputActionExecutor()
  ) {
    this.sessionController = sessionController;
    this.nativeGateway = nativeGateway;
    this.feedbackController = feedbackController;
    this.actionExecutor = actionExecutor;
  }

  getState(): InputSessionState {
    return this.sessionController.getState();
  }

  subscribe(listener: InputSessionStateListener): void {
    this.sessionController.subscribe(listener);
  }

  unsubscribe(listener: InputSessionStateListener): void {
    this.sessionController.unsubscribe(listener);
  }

  getEngineVersion(): string {
    return this.nativeGateway.getEngineVersion();
  }

  getInputMethodSwitchCapabilities(): InputMethodSwitchCapabilities {
    return this.sessionController.getInputMethodSwitchCapabilities();
  }

  getAssistAvailability(): AssistAvailability {
    return this.sessionController.getAssistAvailability();
  }

  requestAiSuggestions(action: AiAction = AiAction.POLITE): Promise<void> {
    return this.sessionController.requestAiSuggestions(action);
  }

  showAiActions(): Promise<void> {
    return this.sessionController.showAiActions();
  }

  acceptAiSuggestion(suggestionId: string): Promise<boolean> {
    return this.sessionController.acceptAiSuggestion(suggestionId);
  }

  acceptLocalAssociation(associationId: string): Promise<boolean> {
    return this.sessionController.acceptLocalAssociation(associationId);
  }

  cancelAiRequest(): void {
    this.sessionController.cancelAiRequest();
  }

  startVoiceInput(): boolean {
    return this.sessionController.startVoiceInput();
  }

  stopVoiceInput(): void {
    this.sessionController.stopVoiceInput();
  }

  confirmVoiceResult(): Promise<boolean> {
    return this.sessionController.confirmVoiceResult();
  }

  retryVoiceInput(): boolean {
    return this.sessionController.retryVoiceInput();
  }

  cancelVoiceInput(): void {
    this.sessionController.cancelVoiceInput();
  }

  /** Invalidates a pending double-press sequence for a key handled by the host. */
  noteExternalInputAction(timestampMs: number = Date.now()): void {
    this.sessionController.beginInputAction(timestampMs);
  }

  refreshClipboardReverseCandidate(): Promise<void> {
    // Read in the security component click turn, before waiting on an input queue.
    return this.sessionController.refreshClipboardReverseCandidate();
  }

  async commitCandidate(candidateIndex: number): Promise<InputOperationResult> {
    return this.enqueueInputOperation('candidate', async (generation: number): Promise<InputOperationResult> => {
      const result = await this.sessionController.commitCandidate(candidateIndex, generation);
      if (result.success && this.sessionController.isInputSessionGenerationCurrent(generation)) {
        this.feedbackController.accepted();
      }
      return result;
    });
  }

  async selectPinyinCombination(combinationIndex: number): Promise<InputOperationResult> {
    return this.enqueueInputOperation('pinyin_combination',
      async (generation: number): Promise<InputOperationResult> => {
        const result = await this.sessionController.selectPinyinCombination(combinationIndex, generation);
        if (result.success && this.sessionController.isInputSessionGenerationCurrent(generation)) {
          this.feedbackController.accepted();
        }
        return result;
      });
  }

  async nextCandidatePage(): Promise<InputOperationResult> {
    return this.navigateCandidatePage(CandidatePageDirection.NEXT);
  }

  async previousCandidatePage(): Promise<InputOperationResult> {
    return this.navigateCandidatePage(CandidatePageDirection.PREVIOUS);
  }

  async commitHighlightedCandidate(): Promise<InputOperationResult> {
    return this.enqueueInputOperation('hardware_candidate', async (generation: number): Promise<InputOperationResult> => {
      const state = this.sessionController.getState();
      const index = state.highlightedIndex >= 0 && state.highlightedIndex < state.candidates.length
        ? state.highlightedIndex
        : 0;
      return this.sessionController.commitCandidate(index, generation);
    });
  }

  async handlePhysicalSpace(): Promise<InputOperationResult> {
    return this.enqueueInputOperation('hardware_space', async (generation: number): Promise<InputOperationResult> => {
      const state = this.sessionController.getState();
      const index = state.highlightedIndex >= 0 && state.highlightedIndex < state.candidates.length
        ? state.highlightedIndex
        : 0;
      return this.sessionController.insertSpace(generation, index);
    });
  }

  /**
   * Handles a hardware letter with the ordering guarantee already provided by
   * the shared executor. A continuation that arrived while an older hardware
   * action was pending can reuse that verified editor ownership and avoid
   * several blocking editor queries per key.
   */
  async handlePhysicalLetter(
    letter: string | undefined,
    serializedContinuation: boolean = false
  ): Promise<InputOperationResult> {
    return this.enqueueInputOperation('hardware_letter', async (generation: number): Promise<InputOperationResult> => {
      const result = await this.sessionController.insertLetter(letter, generation, serializedContinuation);
      if (result.success && this.sessionController.isInputSessionGenerationCurrent(generation)) {
        this.feedbackController.accepted();
      }
      return result;
    });
  }

  /** Restores a cold-start letter when the eventual editor policy is passthrough. */
  async insertDeferredPhysicalCharacter(character: string): Promise<InputOperationResult> {
    return this.enqueueInputOperation('deferred_hardware_character',
      async (generation: number): Promise<InputOperationResult> => {
        const result = await this.sessionController.insertCharacter(character, generation);
        if (result.success && this.sessionController.isInputSessionGenerationCurrent(generation)) {
          this.feedbackController.accepted();
        }
        return result;
      });
  }

  async handlePhysicalEnter(): Promise<InputOperationResult> {
    return this.enqueueInputOperation('hardware_enter', async (generation: number): Promise<InputOperationResult> => {
      const state = this.sessionController.getState();
      if (state.rawInput.length === 0 && this.sessionController.canJumpOutPair(generation)) {
        return this.sessionController.jumpOutPair(generation);
      }
      return this.sessionController.sendEnter(generation);
    });
  }

  /** Serializes a standalone physical-Shift language toggle with nearby hardware input. */
  async togglePhysicalLanguageMode(): Promise<InputOperationResult> {
    return this.enqueueInputOperation('hardware_shift_language_toggle', async (
      generation: number
    ): Promise<InputOperationResult> => {
      return this.sessionController.toggleLanguageMode(generation);
    });
  }

  async jumpOutPhysicalPair(): Promise<InputOperationResult> {
    return this.enqueueInputOperation('hardware_pair_jump', async (generation: number): Promise<InputOperationResult> => {
      return this.sessionController.jumpOutPair(generation);
    });
  }

  async cancelPhysicalComposition(): Promise<InputOperationResult> {
    return this.enqueueInputOperation('hardware_cancel', async (generation: number): Promise<InputOperationResult> => {
      return this.sessionController.cancelComposition(generation);
    });
  }

  async handlePhysicalTab(): Promise<InputOperationResult> {
    return this.enqueueInputOperation('hardware_tab', async (generation: number): Promise<InputOperationResult> => {
      // A preceding queued symbol commit may have created a pair since key DOWN.
      if (this.sessionController.getState().rawInput.length === 0 &&
        this.sessionController.canJumpOutPair(generation)) {
        return this.sessionController.jumpOutPair(generation);
      }
      return this.sessionController.cancelComposition(generation);
    });
  }

  async insertSymbol(symbol: string): Promise<InputOperationResult> {
    return this.enqueueInputOperation('symbol_guide', async (generation: number): Promise<InputOperationResult> => {
      return this.sessionController.insertSymbolText(symbol, generation);
    });
  }

  /** Routes a hardware semicolon through the code-table guide state machine. */
  async handlePhysicalGuideSemicolon(): Promise<InputOperationResult> {
    return this.enqueueInputOperation('hardware_guide_semicolon', async (generation: number): Promise<InputOperationResult> => {
      return this.sessionController.insertCharacter(';', generation);
    });
  }

  /**
   * Resolves Xiaohe Yinxing's physical semicolon against the live composition
   * after older hardware keys have drained from the serial queue. This avoids
   * routing a rapidly typed semicolon from a stale pre-candidate snapshot.
   */
  async handlePhysicalCodeTableSemicolon(): Promise<InputOperationResult> {
    return this.enqueueInputOperation('hardware_code_table_semicolon', async (
      generation: number
    ): Promise<InputOperationResult> => {
      const state = this.sessionController.getState();
      if (state.rawInput.startsWith(';')) {
        return this.sessionController.insertCharacter(';', generation);
      }
      if (state.candidates.length >= 2) {
        return this.sessionController.commitCandidate(1, generation);
      }
      if (state.candidates.length === 1) {
        const committed = await this.sessionController.commitCandidate(0, generation);
        if (!committed.success || !this.sessionController.isInputSessionGenerationCurrent(generation)) {
          return committed;
        }
        return this.sessionController.insertCharacter(';', generation);
      }
      if (state.rawInput.length > 0) {
        const cancelled = await this.sessionController.cancelComposition(generation);
        if (!cancelled.success || !this.sessionController.isInputSessionGenerationCurrent(generation)) {
          return cancelled;
        }
      }
      return this.sessionController.insertCharacter(';', generation);
    });
  }

  async insertPhysicalPunctuation(character: string): Promise<InputOperationResult> {
    return this.enqueueInputOperation('hardware_punctuation', async (
      generation: number,
      inputAction: SmartPeriodInputAction
    ): Promise<InputOperationResult> => {
      return this.sessionController.insertPhysicalPunctuation(character, generation, inputAction);
    });
  }

  async deletePhysicalPunctuationSuffix(): Promise<InputOperationResult> {
    return this.enqueueInputOperation('hardware_punctuation_delete',
      async (generation: number): Promise<InputOperationResult> => {
        return this.sessionController.deletePhysicalPunctuationSuffix(generation);
      });
  }

  async selectPreviousHardwareCandidate(): Promise<InputOperationResult> {
    return this.moveHardwareCandidateSelection(-1);
  }

  async selectNextHardwareCandidate(): Promise<InputOperationResult> {
    return this.moveHardwareCandidateSelection(1);
  }

  async previousHardwareCandidatePage(): Promise<InputOperationResult> {
    return this.navigateStandaloneCandidatePage(CandidatePageDirection.PREVIOUS, 'hardware');
  }

  async nextHardwareCandidatePage(): Promise<InputOperationResult> {
    return this.navigateStandaloneCandidatePage(CandidatePageDirection.NEXT, 'hardware');
  }

  async previousFloatingCandidatePage(): Promise<InputOperationResult> {
    return this.navigateStandaloneCandidatePage(CandidatePageDirection.PREVIOUS, 'floating');
  }

  async nextFloatingCandidatePage(): Promise<InputOperationResult> {
    return this.navigateStandaloneCandidatePage(CandidatePageDirection.NEXT, 'floating');
  }

  setFloatingCandidateExpanded(expanded: boolean): boolean {
    return this.sessionController.setFloatingCandidateExpanded(expanded);
  }

  setCandidatePanelExpanded(expanded: boolean): boolean {
    const startedAt = Date.now();
    const resolved = this.sessionController.setCandidatePanelExpanded(expanded);
    const state = this.sessionController.getState();
    LOGGER.info(
      `candidate panel state changed: expanded=${resolved}, page=${state.candidatePage}, ` +
        `currentPageNodes=${resolved ? state.candidates.length : 0}, elapsedMs=${Date.now() - startedAt}`
    );
    return resolved;
  }

  private async navigateCandidatePage(direction: CandidatePageDirection): Promise<InputOperationResult> {
    const state = this.sessionController.getState();
    const availability: CandidateExpansionAvailability = {
      sessionActive: state.sessionActive,
      keyboardVisible: state.keyboardVisible,
      candidateBarVisible: state.candidateBarVisible,
      candidateCount: state.candidates.length,
      hasPreviousPage: state.hasPreviousPage,
      hasNextPage: state.hasNextPage,
      pageLoading: state.candidatePageLoading || this.candidatePageNavigationInProgress,
      hasError: state.lastErrorCode !== ImeErrorCode.SUCCESS
    };
    if (!state.candidatePanelExpanded || !canNavigateCandidatePage(availability, direction)) {
      return inputOperationFailed(ImeErrorCode.UNSUPPORTED_OPERATION, 'candidate page navigation is unavailable');
    }

    this.candidatePageNavigationInProgress = true;
    this.sessionController.setCandidatePageLoading(true);
    try {
      const label = direction === CandidatePageDirection.NEXT
        ? 'candidate_page_next'
        : 'candidate_page_previous';
      return await this.enqueueInputOperation(
        label,
        async (generation: number): Promise<InputOperationResult> => {
          return direction === CandidatePageDirection.NEXT
            ? this.sessionController.nextCandidatePage(generation)
            : this.sessionController.previousCandidatePage(generation);
        }
      );
    } finally {
      this.candidatePageNavigationInProgress = false;
      this.sessionController.setCandidatePageLoading(false);
    }
  }

  private async moveHardwareCandidateSelection(delta: number): Promise<InputOperationResult> {
    return this.enqueueInputOperation('hardware_candidate_selection',
      async (_generation: number): Promise<InputOperationResult> => {
        return this.sessionController.moveCandidateHighlight(delta);
      });
  }

  private async navigateStandaloneCandidatePage(
    direction: CandidatePageDirection,
    source: string
  ): Promise<InputOperationResult> {
    const label = direction === CandidatePageDirection.NEXT
      ? `${source}_candidate_page_next`
      : `${source}_candidate_page_previous`;
    return this.enqueueInputOperation(label, async (generation: number): Promise<InputOperationResult> => {
      const state = this.sessionController.getState();
      const available = state.sessionActive && state.editorConnected && state.candidateBarVisible &&
        state.rawInput.length > 0 && state.candidates.length > 0 &&
        (direction === CandidatePageDirection.NEXT ? state.hasNextPage : state.hasPreviousPage);
      if (!available) {
        return inputOperationFailed(ImeErrorCode.UNSUPPORTED_OPERATION, 'standalone candidate page is unavailable');
      }
      return direction === CandidatePageDirection.NEXT
        ? this.sessionController.nextCandidatePage(generation)
        : this.sessionController.previousCandidatePage(generation);
    });
  }

  async handleAction(action: KeyboardAction): Promise<InputOperationResult> {
    return this.enqueueInputOperation(action.type, async (
      generation: number,
      inputAction: SmartPeriodInputAction
    ): Promise<InputOperationResult> => {
      const result = await this.executeActionInternal(action, generation, inputAction);
      if (result.success && this.sessionController.isInputSessionGenerationCurrent(generation)) {
        this.feedbackController.accepted(action.type === KeyboardActionType.DELETE ||
          action.type === KeyboardActionType.DELETE_CURRENT_LINE);
      }
      return result;
    });
  }

  private async executeActionInternal(
    action: KeyboardAction,
    generation: number,
    inputAction: SmartPeriodInputAction
  ): Promise<InputOperationResult> {
    let result: InputOperationResult;
    switch (action.type) {
      case KeyboardActionType.LETTER:
        result = await this.sessionController.insertLetter(action.letter, generation);
        break;
      case KeyboardActionType.T9_PINYIN_DIGIT:
        result = await this.sessionController.insertT9PinyinDigit(action.digit, generation);
        break;
      case KeyboardActionType.CONVENIENCE_GUIDE:
        result = await this.sessionController.insertConvenienceCharacter(action.character ?? '=', generation);
        break;
      case KeyboardActionType.SECOND_CANDIDATE_OR_PASTE:
        if (this.sessionController.getState().candidates.length > 0) {
          result = await this.sessionController.commitCandidate(
            this.sessionController.getState().candidates.length > 1 ? 1 : 0, generation);
        } else {
          result = await this.sessionController.performEditorExtendAction(EditorExtendAction.PASTE, generation);
        }
        break;
      case KeyboardActionType.CHARACTER:
        if (isConvenienceInput(this.sessionController.getState().rawInput) && (action.character ?? '').length === 1) {
          result = await this.sessionController.insertConvenienceCharacter(action.character ?? '', generation);
        } else if (action.literal === true && action.cursorOffsetUtf16 !== undefined) {
          result = await this.sessionController.insertLiteralPair(
            action.character,
            action.cursorOffsetUtf16,
            generation
          );
        } else {
          result = action.literal === true
            ? await this.sessionController.insertLiteralCharacter(action.character, generation)
            : await this.sessionController.insertCharacter(action.character, generation, inputAction);
        }
        break;
      case KeyboardActionType.DELETE:
        result = await this.sessionController.deleteBackward(generation);
        break;
      case KeyboardActionType.SPACE:
        result = await this.sessionController.insertSpace(generation);
        break;
      case KeyboardActionType.ENTER:
        result = await this.sessionController.sendEnter(generation);
        break;
      case KeyboardActionType.SHIFT:
        result = this.sessionController.pressShift();
        break;
      case KeyboardActionType.TOGGLE_CHINESE_CAPS_LOCK:
        result = this.sessionController.toggleChineseCapsLock();
        break;
      case KeyboardActionType.INSERT_SEGMENT_BOUNDARY:
        result = await this.sessionController.insertSegmentBoundary(generation);
        break;
      case KeyboardActionType.TOGGLE_LANGUAGE:
        result = await this.sessionController.toggleLanguageMode(generation);
        break;
      case KeyboardActionType.TOGGLE_NUMBER:
        result = await this.sessionController.toggleNumberMode(generation);
        break;
      case KeyboardActionType.TOGGLE_SYMBOL:
        result = await this.sessionController.toggleSymbolMode(generation);
        break;
      case KeyboardActionType.SWITCH_INPUT_METHOD:
        result = await this.sessionController.switchToNextInputMethod(generation);
        break;
      case KeyboardActionType.SHOW_INPUT_METHOD_PICKER:
        result = await this.sessionController.showInputMethodPicker(generation);
        break;
      case KeyboardActionType.HIDE_KEYBOARD:
        return this.sessionController.hideKeyboard(generation);
      case KeyboardActionType.MOVE_CURSOR_LEFT:
      case KeyboardActionType.MOVE_CURSOR_RIGHT:
        // Read candidates inside the input queue so a preceding letter is included.
        // Both lift-layer arrows act like Space while candidates are available.
        result = this.sessionController.getState().candidates.length > 0
          ? await this.sessionController.insertSpace(generation)
          : await this.sessionController.moveEditorCursor(
            action.type === KeyboardActionType.MOVE_CURSOR_LEFT
              ? inputMethodEngine.Direction.CURSOR_LEFT
              : inputMethodEngine.Direction.CURSOR_RIGHT,
            generation
          );
        break;
      case KeyboardActionType.SECOND_CANDIDATE_OR_PUNCTUATION: {
        const state = this.sessionController.getState();
        if (state.rawInput.length > 0 && !state.rawInput.startsWith(';') && state.candidates.length >= 2) {
          // 有第二候选时，选择第二候选
          result = await this.sessionController.commitCandidate(1, generation);
        } else if (state.rawInput.length > 0 && !state.rawInput.startsWith(';') && state.candidates.length === 1) {
          // 候选唯一时，顶候选上屏，然后分号自身进入引导状态
          const confirmed = await this.sessionController.commitCandidate(0, generation);
          if (!confirmed.success || !this.sessionController.isInputSessionGenerationCurrent(generation)) {
            result = confirmed;
          } else {
            result = await this.sessionController.insertCharacter(';', generation);
          }
        } else {
          // 没有候选或已在引导状态时，直接处理分号字符（进入或继续引导状态）
          result = await this.sessionController.insertCharacter(';', generation);
        }
        break;
      }
      case KeyboardActionType.SECOND_CANDIDATE_OR_COMMA: {
        const state = this.sessionController.getState();
        if (state.rawInput.length > 0 && !state.rawInput.startsWith(';') && state.candidates.length >= 2) {
          // 有第二候选时，选择第二候选
          result = await this.sessionController.commitCandidate(1, generation);
        } else {
          // 没有第二候选时，输入逗号
          result = await this.sessionController.insertCharacter('，', generation);
        }
        break;
      }
      case KeyboardActionType.SECOND_CANDIDATE_OR_PERIOD:
        result = await this.handleCandidatePunctuation(1, '。', generation, inputAction);
        break;
      case KeyboardActionType.THIRD_CANDIDATE_OR_COMMA:
        result = await this.handleCandidatePunctuation(2, '，', generation, inputAction);
        break;
      case KeyboardActionType.REPEAT_LAST_COMMIT:
      case KeyboardActionType.UNDO_LAST_COMMIT: {
        const prepared = await this.commitCandidateBeforeHistoryAction(generation);
        if (!prepared.success) {
          return prepared;
        }
        if (!this.sessionController.isInputSessionGenerationCurrent(generation)) {
          return inputOperationFailed(ImeErrorCode.ENGINE_NOT_INITIALIZED,
            'input session changed before repeat or undo');
        }
        const repeat = action.type === KeyboardActionType.REPEAT_LAST_COMMIT;
        const succeeded = repeat ? await this.sessionController.repeatLastCommit(generation) :
          await this.sessionController.undoLastCommit(generation);
        result = succeeded
          ? inputOperationOk()
          : inputOperationFailed(ImeErrorCode.UNSUPPORTED_OPERATION,
            repeat ? 'repeat last commit failed' : 'undo last commit failed');
        break;
      }
      case KeyboardActionType.DELETE_CURRENT_LINE:
        result = await this.sessionController.deleteCurrentLine(generation, true);
        break;
      case KeyboardActionType.RESTORE_LAST_DELETION:
        result = await this.sessionController.restoreLastDeletion(generation);
        break;
      case KeyboardActionType.SELECT_ALL:
        result = await this.sessionController.performEditorExtendAction(EditorExtendAction.SELECT_ALL, generation);
        break;
      case KeyboardActionType.CUT:
        result = await this.sessionController.performEditorExtendAction(EditorExtendAction.CUT, generation);
        break;
      case KeyboardActionType.COPY:
        result = await this.sessionController.performEditorExtendAction(EditorExtendAction.COPY, generation);
        break;
      case KeyboardActionType.PASTE:
        result = await this.sessionController.performEditorExtendAction(EditorExtendAction.PASTE, generation);
        break;
      case KeyboardActionType.CANCEL_COMPOSITION:
        result = await this.sessionController.cancelComposition(generation);
        break;
      case KeyboardActionType.UNIVERSAL_KEY:
        result = await this.sessionController.insertUniversalKey(generation);
        break;
      default:
        LOGGER.warn('unsupported keyboard action');
        this.sessionController.recordError(ImeErrorCode.UNSUPPORTED_OPERATION, 'unsupported keyboard action');
        return inputOperationFailed(ImeErrorCode.UNSUPPORTED_OPERATION, 'unsupported keyboard action');
    }
    return result;
  }

  private async commitCandidateBeforeHistoryAction(generation: number): Promise<InputOperationResult> {
    const state = this.sessionController.getState();
    if (state.rawInput.length === 0) {
      return inputOperationOk();
    }
    const index = state.highlightedIndex >= 0 && state.highlightedIndex < state.candidates.length
      ? state.highlightedIndex : 0;
    const candidate = state.candidates[index];
    if (!candidate || candidate.text.length === 0 || candidate.source === 'functional') {
      // An unfinished code or a command candidate must not act on older text.
      return inputOperationFailed(ImeErrorCode.INVALID_CANDIDATE,
        'repeat or undo requires a text candidate');
    }
    const committed = await this.sessionController.commitCandidate(index, generation);
    if (!this.sessionController.isInputSessionGenerationCurrent(generation)) {
      return inputOperationFailed(ImeErrorCode.ENGINE_NOT_INITIALIZED,
        'input session changed after candidate commit');
    }
    return committed;
  }

  private async handleCandidatePunctuation(
    candidateIndex: number,
    punctuation: string,
    generation: number,
    inputAction: SmartPeriodInputAction
  ): Promise<InputOperationResult> {
    const state = this.sessionController.getState();
    const resolution = resolveCandidatePunctuation(
      state.rawInput,
      state.candidates.length,
      candidateIndex
    );
    if (resolution.type === CandidatePunctuationResolutionType.SELECT_CANDIDATE) {
      return this.sessionController.commitCandidate(resolution.candidateIndex, generation);
    }
    if (resolution.type === CandidatePunctuationResolutionType.COMMIT_TOP_THEN_PUNCTUATION) {
      const committed = await this.sessionController.commitCandidate(0, generation);
      if (!committed.success || !this.sessionController.isInputSessionGenerationCurrent(generation)) {
        return committed;
      }
    }
    return this.sessionController.insertCharacter(punctuation, generation, inputAction);
  }

  private enqueueInputOperation(
    label: string,
    task: (generation: number, inputAction: SmartPeriodInputAction) => Promise<InputOperationResult>
  ): Promise<InputOperationResult> {
    const generation = this.sessionController.getInputSessionGeneration();
    const inputAction = this.sessionController.beginInputAction();
    this.actionSequence += 1;
    const sequence = this.actionSequence;
    LOGGER.debug(`input action queued: type=${label}, generation=${generation}, sequence=${sequence}`);

    return this.actionExecutor.enqueue(async (): Promise<InputOperationResult> => {
      if (!this.sessionController.isInputSessionGenerationCurrent(generation)) {
        LOGGER.info(
          `stale input action skipped: type=${label}, generation=${generation}, sequence=${sequence}`
        );
        return inputOperationFailed(ImeErrorCode.ENGINE_NOT_INITIALIZED, 'stale input action skipped');
      }

      LOGGER.debug(`input action started: type=${label}, generation=${generation}, sequence=${sequence}`);
      try {
        const result = await task(generation, inputAction);
        if (!this.sessionController.isInputSessionGenerationCurrent(generation)) {
          LOGGER.info(
            `stale input action completed without state update: type=${label}, ` +
              `generation=${generation}, sequence=${sequence}`
          );
          return inputOperationFailed(ImeErrorCode.ENGINE_NOT_INITIALIZED, 'input session changed during action');
        }
        LOGGER.debug(
          `input action completed: type=${label}, generation=${generation}, ` +
            `sequence=${sequence}, success=${result.success}`
        );
        return result;
      } catch (err) {
        LOGGER.error(
          `input action failed: type=${label}, generation=${generation}, ` +
            `sequence=${sequence}, error=${JSON.stringify(err)}`
        );
        if (this.sessionController.isInputSessionGenerationCurrent(generation)) {
          this.sessionController.handleInputControllerRecovery();
          this.sessionController.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, `${label} input action failed`);
        }
        return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR, `${label} input action failed`);
      }
    });
  }

  dispose(): void {
    this.sessionController.setCandidatePanelExpanded(false);
    this.feedbackController.dispose();
  }
}
