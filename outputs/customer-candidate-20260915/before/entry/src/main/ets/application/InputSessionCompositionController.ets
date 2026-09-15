import { isConvenienceInput } from '../domain/keyboard/ConvenienceInput';
import { inputMethodEngine, InputMethodExtensionContext } from '@kit.IMEKit';
import { ImeErrorCode } from '../common/error/ImeError';
import { Logger } from '../common/logging/Logger';
import {
  EditorContext,
  EnterAction,
  EDITOR_KIND_EXTRA_CONFIG_KEY
} from '../domain/editor/EditorContext';
import { KeyboardMode, isSingleAsciiLetter, isT9PinyinDigit } from '../domain/keyboard/KeyboardAction';
import { normalizeLetterSwipeSymbol } from '../domain/keyboard/LetterSwipeSymbols';
import {
  ImeSettings,
  PINYIN_9_SCHEME_ID,
  PunctuationMode,
  XIAOHE_YINXING_SCHEME_ID
} from '../domain/settings/ImeSettings';
import { EditorAttributeMapper } from '../infrastructure/ime/EditorAttributeMapper';
import { ImeConnectionService } from '../infrastructure/ime/ImeConnectionService';
import {
  getSharedInputSessionStore,
  InputSessionState,
  InputSessionStateListener,
  InputSessionStore
} from '../state/InputSessionStore';
import { EngineCoordinator, getSharedEngineCoordinator } from './EngineCoordinator';
import { inputOperationFailed, inputOperationOk, InputOperationResult } from './InputOperationResult';
import { LexiconResourceInstaller } from '../infrastructure/resource/LexiconResourceInstaller';
import {
  QUANPIN_CONTEXT_MODEL_SHA256,
  QuanpinContextModelResourceInstaller
} from '../infrastructure/resource/QuanpinContextModelResourceInstaller';
import { YinxingBundleInstaller } from '../infrastructure/resource/YinxingBundleInstaller';
import { UserModelPathProvider } from '../infrastructure/storage/UserModelPathProvider';
import { UserLexiconPathProvider } from '../infrastructure/storage/UserLexiconPathProvider';
import { SettingsController, getSharedSettingsController } from './SettingsController';
import { initializeSharedKeySoundBackend } from '../infrastructure/audio/KeySoundService';
import { UserModelCommandRepository } from '../infrastructure/storage/UserModelCommandRepository';
import { UserModelCommandBus } from '../infrastructure/storage/UserModelCommandBus';
import { UserLexiconSyncBus } from '../infrastructure/storage/UserLexiconSyncBus';
import {
  CompositionResult,
  InsertPairAction,
  NativeEngineGatewayContract
} from '../infrastructure/native/NativeEngineTypes';
import { UserLexiconImportManager } from './UserLexiconImportManager';
import { NativeEngineGateway } from '../infrastructure/native/NativeEngineGateway';
import {
  ProtocolActionImeService,
  ProtocolActionHandlers,
  ProtocolActionExecutionStatus,
  ProtocolActionExecutor
} from './ProtocolActionExecutor';
import { SystemTimeProvider } from '../infrastructure/time/TimeProvider';
import { ScreenMetricsPx, withBottomSystemInset } from '../domain/display/ScreenMetrics';
import { getEngineInitializationOverride } from './EngineInitializationOverride';
import {
  getSharedInputMethodSwitcher,
  InputMethodSwitchCapabilities,
  InputMethodSwitcher,
  InputMethodSwitchResult,
  InputMethodSwitchResultType
} from '../infrastructure/ime/InputMethodSwitcher';
import { CommitHistoryManager } from './CommitHistoryManager';
import { UndoCommitManager } from './UndoCommitManager';
import { UserLexiconDocumentEditor } from './UserLexiconController';

import { InputSessionCommitController } from './InputSessionCommitController';
import { SmartPeriodInputAction } from './SmartPeriodController';
import {
  chinesePunctuationForEnglishTarget,
  isSmartPunctuationEnabled,
  smartPunctuationTarget
} from '../domain/keyboard/SmartPunctuation';

const TAG = 'InputSessionController';
const LOGGER = new Logger(TAG);

export class InputSessionCompositionController extends InputSessionCommitController {
  async insertSegmentBoundary(
    generation: number = this.getInputSessionGeneration()
  ): Promise<InputOperationResult> {
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('segment boundary');
    }
    const sessionCheck = this.ensureInputSession('segment boundary');
    if (!sessionCheck.success) {
      return sessionCheck;
    }
    const state = this.store.getSnapshot();
    if (state.keyboardMode !== KeyboardMode.CHINESE || state.rawInput.length === 0) {
      this.store.recordError(ImeErrorCode.INVALID_ARGUMENT, 'segment boundary requires chinese composition');
      return inputOperationFailed(ImeErrorCode.INVALID_ARGUMENT, 'segment boundary requires chinese composition');
    }

    const result = this.engineCoordinator.insertSegmentBoundary();
    if (!result.success) {
      this.store.recordError(result.errorCode, result.errorMessage);
      return inputOperationFailed(result.errorCode, result.errorMessage);
    }
    const previewUpdated = await this.updateCompositionText(
      result.rawInput,
      this.shouldUseCursorPreedit(state),
      generation
    );
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('segment boundary completion');
    }
    if (!previewUpdated) {
      this.store.updateComposition(this.restoreEngineComposition(state));
      this.store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'segment boundary preview update failed');
      return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'segment boundary preview update failed');
    }
    this.store.updateComposition(result);
    return inputOperationOk();
  }

  async insertLetter(
    letter: string | undefined,
    generation: number = this.getInputSessionGeneration(),
    serializedPhysicalContinuation: boolean = false
  ): Promise<InputOperationResult> {
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('letter');
    }

    const input = letter ?? '';
    if (!isSingleAsciiLetter(input)) {
      this.store.recordError(ImeErrorCode.INVALID_ARGUMENT, 'letter input requires one ascii letter');
      return inputOperationFailed(ImeErrorCode.INVALID_ARGUMENT, 'letter input requires one ascii letter');
    }

    let state = this.store.getSnapshot();
    if (isConvenienceInput(state.rawInput)) {
      const quickLetter = state.keyboardMode === KeyboardMode.ENGLISH
        ? this.store.transformEnglishLetter(input) : input;
      const result = await this.insertConvenienceCharacter(quickLetter, generation);
      if (result.success && this.isInputSessionGenerationCurrent(generation)) {
        this.store.markEnglishLetterCommitted();
      }
      return result;
    }
    const normalizedInput = input.toLowerCase();
    if (state.keyboardMode === KeyboardMode.CHINESE &&
      state.editorContext.chineseModeAllowed && !state.editorContext.isPassword) {
      const sessionCheck = this.ensureInputSession('chinese letter');
      if (!sessionCheck.success) {
        return sessionCheck;
      }

      if (state.chineseCapsLock) {
        this.undoCommitManager?.invalidateUndo();
        return this.insertText(normalizedInput.toUpperCase(), 'chinese uppercase letter', generation);
      }

      // The first hardware key in a burst verifies editor ownership. Later
      // keys were already consumed into the same strictly serialized queue,
      // so repeating cursor/text probes only creates a speed-dependent
      // backlog on compatible desktop editors such as Browser Search.
      if (!serializedPhysicalContinuation) {
        await this.resetCompositionDetachedByEditor(state, generation);
      }
      if (!this.isInputSessionGenerationCurrent(generation)) {
        return this.staleInputAction('letter attachment check');
      }
      state = this.store.getSnapshot();

      const activeSchemeId = this.engineCoordinator.getActiveSchemeId();
      // Full-pinyin correction can require several bounded sentence decodes.
      // Await the native worker-backed path so ArkUI can continue receiving
      // touches while the existing input-action queue preserves key order.
      const result = activeSchemeId === 'quanpin'
        ? await this.engineCoordinator.processKeyAsync(normalizedInput)
        : this.engineCoordinator.processKey(normalizedInput);
      if (!result.success) {
        this.store.updateComposition(result);
        return inputOperationFailed(result.errorCode, result.errorMessage);
      }
      if (activeSchemeId === 'quanpin' &&
        (result.commitText.length > 0 || result.compositionFinished)) {
        // A letter is never an explicit confirmation action in full pinyin.
        // Treat any native commit as a protocol violation and rebuild the
        // immutable pre-key composition before touching the host editor.
        this.store.updateComposition(this.restoreEngineComposition(state));
        this.store.recordError(
          ImeErrorCode.SERIALIZATION_ERROR,
          'quanpin letter returned a forbidden commit'
        );
        LOGGER.error(
          `quanpin protocol violation blocked: letter=${normalizedInput}, ` +
            `commitLength=${result.commitText.length}, finished=${result.compositionFinished}`
        );
        return inputOperationFailed(
          ImeErrorCode.SERIALIZATION_ERROR,
          'quanpin letter returned a forbidden commit'
        );
      }
      if (result.action !== null && result.action !== undefined) {
        // Guide actions such as ;i and ;n are produced while the leading
        // semicolon still owns an editor preview range.  Mutating the editor
        // before releasing that range makes getForward()/selectByRange()
        // observe the preview character instead of the committed text and a
        // later preview cleanup can also restore the old caret.  Close the
        // guide preview first, then execute the closed editor action.
        if (state.rawInput.length > 0 &&
          (result.action.type === 'REPEAT_COMMIT' ||
            result.action.type === 'UNDO_COMMIT' ||
            result.action.type === 'MOVE_LINE_END' ||
            result.action.type === 'DIRECT_CONTROL')) {
          const cleared = await this.imeService.clearPreviewText(generation);
          if (!this.isInputSessionGenerationCurrent(generation)) {
            return this.staleInputAction('guide preview clear');
          }
          if (!cleared) {
            this.store.updateComposition(this.restoreEngineComposition(state));
            this.store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'guide preview clear failed');
            return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'guide preview clear failed');
          }
          this.store.clearComposition();
        }
        const executed = await this.protocolActionExecutor.execute(result.action, generation);
        if (executed.committedText.length > 0 && executed.textInserted) {
          this.recordCommittedText(executed.committedText);
        }
        if (executed.status === ProtocolActionExecutionStatus.SESSION_INVALID) {
          return this.staleInputAction('guide action completion');
        }
        if (executed.status !== ProtocolActionExecutionStatus.SUCCESS) {
          // The native guide action is already consumed. If pair text reached
          // the editor but cursor placement failed, keep it exactly once and
          // clear only the stale composition.
          this.store.clearComposition();
          this.store.recordError(
            ImeErrorCode.ENGINE_INTERNAL_ERROR,
            executed.textInserted ? 'guide action completed with cursor fallback' : 'guide action failed'
          );
          return inputOperationFailed(
            ImeErrorCode.ENGINE_INTERNAL_ERROR,
            executed.textInserted ? 'guide action completed with cursor fallback' : 'guide action failed'
          );
        }
        this.store.updateComposition(result);
        return inputOperationOk();
      }
      // A functional guide letter (notably undo) must retain the history it
      // acts on. Ordinary code input and plain-symbol commits still invalidate
      // the previous undo record before applying their own editor mutation.
      this.undoCommitManager?.invalidateUndo();
      let automaticCommitApplied = false;
      if (result.commitText.length > 0) {
        let committed = false;
        try {
          committed = await this.imeService.commitPreviewText(result.commitText, generation);
        } catch (err) {
          committed = false;
        }
        if (!this.isInputSessionGenerationCurrent(generation)) {
          return this.staleInputAction('chinese automatic commit completion');
        }
        if (!committed) {
          // processKey has already advanced the native state (and may have
          // cleared the old four-code segment or replayed a fifth key).  A
          // rejected host commit must roll that speculative transition back;
          // otherwise the user loses the original code and its candidates.
          // Rebuild from the immutable store snapshot captured before this key
          // so the next action observes the same retryable composition.
          this.store.updateComposition(this.restoreEngineComposition(state));
          this.store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'automatic commit failed');
          return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'automatic commit failed');
        }
        automaticCommitApplied = true;
        // Record commit history
        this.commitHistoryManager.addCommit(result.commitText);
        if (this.undoCommitManager) {
          this.undoCommitManager.recordCommit(result.commitText);
        }
        if (result.rawInput.length === 0) {
          this.store.updateComposition(result);
          return inputOperationOk();
        }
      }
      // Keep composing codes in the candidate area, including on hosts that
      // advertise native preview support. Only confirmed candidates reach the editor.
      const useNativeTextPreview = this.shouldUseCursorPreedit(state);

      // Publish the synchronous engine result before waiting for the host
      // editor's asynchronous preview round-trip. Input actions remain
      // serialized, so a later key cannot overtake this write; if HarmonyOS
      // rejects it, the existing rollback path restores both engine and store.
      // This keeps the candidate bar responsive on a slow emulator without
      // weakening editor-range ownership checks.
      this.store.updateComposition(result);
      const previewUpdated = await this.updateCompositionText(
        result.rawInput,
        useNativeTextPreview,
        generation,
        false,
        serializedPhysicalContinuation
      );
      if (!this.isInputSessionGenerationCurrent(generation)) {
        return this.staleInputAction('chinese composition completion');
      }
      if (!previewUpdated) {
        if (!automaticCommitApplied) {
          this.store.updateComposition(this.restoreEngineComposition(state));
        }
        // Once the old four-code segment has reached the editor, replaying
        // the pre-key snapshot would make the next fifth key commit it again.
        // Keep the already-published native tail as the retryable source of
        // truth; a later key/backspace can refresh or edit that composition.
        this.store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'composition text update failed');
        return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'composition text update failed');
      }
      await this.refreshShapeLookupCandidate(generation);
      await this.refreshClipboardReverseCandidate(generation);
      return inputOperationOk();
    }

    this.undoCommitManager?.invalidateUndo();
    const directLetter = this.store.transformEnglishLetter(normalizedInput);
    const result = await this.insertText(directLetter, 'letter', generation);
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('letter completion');
    }
    if (result.success) {
      this.store.markEnglishLetterCommitted();
    }
    return result;
  }

  /**
   * Inserts Xiaohe Yinxing's backtick wildcard into the native composition.
   * It remains an IME code key rather than committed punctuation.
   */
  async insertUniversalKey(
    generation: number = this.getInputSessionGeneration()
  ): Promise<InputOperationResult> {
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('universal key');
    }
    const sessionCheck = this.ensureInputSession('universal key');
    if (!sessionCheck.success) {
      return sessionCheck;
    }
    let state = this.store.getSnapshot();
    if (state.keyboardMode !== KeyboardMode.CHINESE || !state.editorContext.chineseModeAllowed ||
      state.editorContext.isPassword ||
      this.engineCoordinator.getActiveSchemeId() !== XIAOHE_YINXING_SCHEME_ID) {
      this.store.recordError(ImeErrorCode.UNSUPPORTED_OPERATION, '万能键仅在小鹤音形中文模式可用');
      return inputOperationFailed(ImeErrorCode.UNSUPPORTED_OPERATION, 'universal key requires Xiaohe Yinxing');
    }
    this.undoCommitManager?.invalidateUndo();
    await this.resetCompositionDetachedByEditor(state, generation);
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('universal key attachment check');
    }
    state = this.store.getSnapshot();
    const result = this.engineCoordinator.processKey('`');
    if (!result.success || result.commitText.length > 0 || result.compositionFinished ||
      (result.action !== null && result.action !== undefined)) {
      this.store.updateComposition(this.restoreEngineComposition(state));
      const errorCode = result.success ? ImeErrorCode.SERIALIZATION_ERROR : result.errorCode;
      const message = result.success ? 'universal key returned a forbidden commit or action' : result.errorMessage;
      this.store.recordError(errorCode, message);
      return inputOperationFailed(errorCode, message);
    }
    this.store.updateComposition(result);
    const previewUpdated = await this.updateCompositionText(
      result.rawInput,
      this.shouldUseCursorPreedit(state),
      generation
    );
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('universal key completion');
    }
    if (!previewUpdated) {
      this.store.updateComposition(this.restoreEngineComposition(state));
      this.store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'universal key preview update failed');
      return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'universal key preview update failed');
    }
    return inputOperationOk();
  }

  /**
   * Sends a Chinese 9-key digit through the formal ArkTS -> C++ -> Rust input
   * path. This method never inserts the digit into the editor as ordinary text.
   */
  async insertT9PinyinDigit(
    digit: string | undefined,
    generation: number = this.getInputSessionGeneration()
  ): Promise<InputOperationResult> {
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('T9 pinyin digit');
    }

    // Invalidate undo state when user types
    if (this.undoCommitManager) {
      this.undoCommitManager.invalidateUndo();
    }

    if (!isT9PinyinDigit(digit)) {
      this.store.recordError(ImeErrorCode.INVALID_ARGUMENT, 'T9 pinyin input requires one digit from 2 to 9');
      return inputOperationFailed(ImeErrorCode.INVALID_ARGUMENT, 'T9 pinyin input requires one digit from 2 to 9');
    }
    const sessionCheck = this.ensureInputSession('T9 pinyin digit');
    if (!sessionCheck.success) {
      return sessionCheck;
    }

    let state = this.store.getSnapshot();
    if (state.keyboardMode !== KeyboardMode.CHINESE || !state.editorContext.chineseModeAllowed ||
      state.editorContext.isPassword || this.engineCoordinator.getActiveSchemeId() !== PINYIN_9_SCHEME_ID) {
      this.store.recordError(ImeErrorCode.UNSUPPORTED_OPERATION, 'T9 pinyin digit requires the Chinese 9-key profile');
      return inputOperationFailed(
        ImeErrorCode.UNSUPPORTED_OPERATION,
        'T9 pinyin digit requires the Chinese 9-key profile'
      );
    }

    await this.resetCompositionDetachedByEditor(state, generation);
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('T9 pinyin digit attachment check');
    }
    state = this.store.getSnapshot();
    const result = this.engineCoordinator.processKey(digit as string);
    if (!result.success) {
      this.store.recordError(result.errorCode, result.errorMessage);
      return inputOperationFailed(result.errorCode, result.errorMessage);
    }
    if (result.commitText.length > 0 || result.compositionFinished ||
      (result.action !== null && result.action !== undefined)) {
      this.store.updateComposition(this.restoreEngineComposition(state));
      this.store.recordError(ImeErrorCode.SERIALIZATION_ERROR, 'T9 digit returned a forbidden commit or action');
      return inputOperationFailed(ImeErrorCode.SERIALIZATION_ERROR, 'T9 digit returned a forbidden commit or action');
    }

    this.store.updateComposition(result);
    const previewUpdated = await this.updateCompositionText(
      result.rawInput,
      this.shouldUseCursorPreedit(state),
      generation
    );
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('T9 pinyin digit completion');
    }
    if (!previewUpdated) {
      this.store.updateComposition(this.restoreEngineComposition(state));
      this.store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'T9 composition text update failed');
      return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'T9 composition text update failed');
    }
    return inputOperationOk();
  }

  async selectPinyinCombination(
    combinationIndex: number,
    generation: number = this.getInputSessionGeneration()
  ): Promise<InputOperationResult> {
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('pinyin combination');
    }
    const sessionCheck = this.ensureInputSession('pinyin combination');
    if (!sessionCheck.success) {
      return sessionCheck;
    }
    const state = this.store.getSnapshot();
    if (state.keyboardMode !== KeyboardMode.CHINESE || state.rawInput.length === 0 ||
      this.engineCoordinator.getActiveSchemeId() !== PINYIN_9_SCHEME_ID ||
      !Number.isInteger(combinationIndex) || combinationIndex < 0 ||
      combinationIndex > state.pinyinCombinations.length) {
      this.store.recordError(ImeErrorCode.INVALID_ARGUMENT, 'pinyin combination selection is unavailable');
      return inputOperationFailed(ImeErrorCode.INVALID_ARGUMENT, 'pinyin combination selection is unavailable');
    }
    const result = this.engineCoordinator.selectPinyinCombination(combinationIndex);
    if (!result.success) {
      this.store.recordError(result.errorCode, result.errorMessage);
      return inputOperationFailed(result.errorCode, result.errorMessage);
    }
    this.store.updateComposition(result);
    return inputOperationOk();
  }

  /** Runs in the shared input queue; candidate-dependent guide behavior uses live state. */
  async insertConvenienceCharacter(
    character: string,
    generation: number = this.getInputSessionGeneration()
  ): Promise<InputOperationResult> {
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('convenience input');
    }
    const check = this.ensureInputSession('convenience input');
    if (!check.success) { return check; }
    const state = this.store.getSnapshot();
    if (state.editorContext.isPassword ||
      (!state.editorContext.chineseModeAllowed && !state.editorContext.englishModeAllowed)) {
      return this.insertLiteralCharacter(character, generation);
    }
    if (character === '=' && state.candidates.length > 0) {
      return this.insertSpace(generation);
    }
    if (!isConvenienceInput(state.rawInput) && state.rawInput.length > 0) {
      return this.insertCharacter(character, generation);
    }
    if (!this.engineCoordinator.isInitialized()) {
      return inputOperationFailed(ImeErrorCode.ENGINE_NOT_INITIALIZED, 'convenience engine is unavailable');
    }
    const result = this.engineCoordinator.processKey(character);
    if (!result.success) {
      return inputOperationFailed(result.errorCode, result.errorMessage);
    }
    const updated = result.commitText.length > 0
      ? await this.imeService.commitPreviewText(result.commitText, generation)
      : await this.updateCompositionText(result.rawInput, this.shouldUseCursorPreedit(state), generation);
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('convenience input completion');
    }
    if (!updated) {
      this.store.updateComposition(this.restoreEngineComposition(state));
      return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'convenience preview update failed');
    }
    if (result.commitText.length > 0) {
      this.commitHistoryManager.addCommit(result.commitText);
      this.undoCommitManager?.recordCommit(result.commitText);
    }
    this.store.updateComposition(result);
    return inputOperationOk();
  }

  async insertCharacter(
    character: string | undefined,
    generation: number = this.getInputSessionGeneration(),
    inputAction?: SmartPeriodInputAction
  ): Promise<InputOperationResult> {
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('character');
    }
    const input = character ?? '';
    if (input.length !== 1) {
      this.store.recordError(ImeErrorCode.INVALID_ARGUMENT, 'character input requires one character');
      return inputOperationFailed(ImeErrorCode.INVALID_ARGUMENT, 'character input requires one character');
    }
    const state = this.store.getSnapshot();
    if (isConvenienceInput(state.rawInput)) {
      return this.insertConvenienceCharacter(input, generation);
    }
    if (state.keyboardMode === KeyboardMode.CHINESE && state.rawInput.length > 0 &&
      !state.rawInput.startsWith(';')) {
      if (state.candidates.length > 0) {
        const confirmed = await this.commitCandidate(0, generation);
        if (!confirmed.success) {
          return confirmed;
        }
        if (!this.isInputSessionGenerationCurrent(generation)) {
          return this.staleInputAction('punctuation top candidate commit');
        }
      } else {
        const cleared = await this.imeService.clearPreviewText(generation);
        if (!cleared) {
          this.store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'punctuation composition clear failed');
          return inputOperationFailed(
            ImeErrorCode.ENGINE_INTERNAL_ERROR,
            'punctuation composition clear failed'
          );
        }
        if (!this.isInputSessionGenerationCurrent(generation)) {
          return this.staleInputAction('punctuation composition clear');
        }
        this.engineCoordinator.reset();
        this.store.clearComposition();
      }
      return this.insertSmartPunctuationOrText(
        this.normalizeChinesePunctuationInput(input, state),
        'punctuation after explicit composition action',
        generation,
        inputAction
      );
    }
    const chineseEngineReady =
      (state.keyboardMode === KeyboardMode.CHINESE ||
        (state.keyboardMode === KeyboardMode.SYMBOL &&
          state.modeBeforeTransient === KeyboardMode.CHINESE)) &&
      this.engineCoordinator.isInitialized();
    if (input === ';' && chineseEngineReady) {
      const result = this.engineCoordinator.processKey(';');
      if (result.success) {
        if (result.commitText.length > 0) {
          const committed = await this.imeService.commitPreviewText(result.commitText, generation);
          if (!this.isInputSessionGenerationCurrent(generation)) {
            return this.staleInputAction('guide repeat commit completion');
          }
          if (!committed) {
            this.store.updateComposition(this.restoreEngineComposition(state));
            this.store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'guide repeat commit failed');
            return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'guide repeat commit failed');
          }
          this.commitHistoryManager.addCommit(result.commitText);
          if (this.undoCommitManager) {
            this.undoCommitManager.recordCommit(result.commitText);
          }
          this.store.updateComposition(result);
          return inputOperationOk();
        }
        const previewUpdated = await this.updateCompositionText(
          result.rawInput,
          this.shouldUseCursorPreedit(state),
          generation
        );
        if (!this.isInputSessionGenerationCurrent(generation)) {
          return this.staleInputAction('guide prefix completion');
        }
        if (!previewUpdated) {
          this.engineCoordinator.reset();
          this.store.clearComposition();
          return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'guide preview update failed');
        }
        this.store.updateComposition(result);
        return inputOperationOk();
      }
    }
    if (state.keyboardMode === KeyboardMode.CHINESE && state.rawInput.startsWith(';')) {
      await this.imeService.clearPreviewText(generation);
      if (!this.isInputSessionGenerationCurrent(generation)) {
        return this.staleInputAction('guide invalid-key completion');
      }
      this.engineCoordinator.reset();
      this.store.clearComposition();
    }
    return this.insertSmartPunctuationOrText(
      this.normalizeChinesePunctuationInput(input, state),
      'direct character',
      generation,
      inputAction
    );
  }

  /**
   * Inserts literal key text exactly as configured. The text intentionally
   * bypasses Chinese punctuation, full-width and
   * semicolon-guide conversion; an active composition is still confirmed or
   * cleared first, just like an ordinary punctuation action.
   */
  async insertLiteralCharacter(
    character: string | undefined,
    generation: number = this.getInputSessionGeneration()
  ): Promise<InputOperationResult> {
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('literal upper-deck character');
    }
    const input = character ?? '';
    if (input.length <= 0 || normalizeLetterSwipeSymbol(input) !== input) {
      this.store.recordError(ImeErrorCode.INVALID_ARGUMENT, 'literal key text is invalid');
      return inputOperationFailed(ImeErrorCode.INVALID_ARGUMENT, 'literal key text is invalid');
    }
    const sessionCheck = this.ensureInputSession('literal upper-deck character');
    if (!sessionCheck.success) {
      return sessionCheck;
    }

    const state = this.store.getSnapshot();
    if ((state.keyboardMode === KeyboardMode.CHINESE || isConvenienceInput(state.rawInput)) && state.rawInput.length > 0) {
      if (!state.rawInput.startsWith(';') && state.candidates.length > 0) {
        const confirmed = await this.commitCandidate(0, generation);
        if (!confirmed.success) {
          return confirmed;
        }
        if (!this.isInputSessionGenerationCurrent(generation)) {
          return this.staleInputAction('literal upper-deck character candidate commit');
        }
      } else {
        const cleared = await this.imeService.clearPreviewText(generation);
        if (!cleared) {
          this.store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'literal character composition clear failed');
          return inputOperationFailed(
            ImeErrorCode.ENGINE_INTERNAL_ERROR,
            'literal character composition clear failed'
          );
        }
        if (!this.isInputSessionGenerationCurrent(generation)) {
          return this.staleInputAction('literal upper-deck character composition clear');
        }
        this.engineCoordinator.reset();
        this.store.clearComposition();
      }
    }
    this.smartPeriodController.clear();
    return this.insertText(input, 'literal upper-deck character', generation);
  }

  /** Inserts both delimiters atomically and places the editor cursor between them. */
  async insertLiteralPair(
    text: string | undefined,
    cursorOffsetUtf16: number | undefined,
    generation: number = this.getInputSessionGeneration()
  ): Promise<InputOperationResult> {
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('literal symbol pair');
    }
    const input = text ?? '';
    if (input.length <= 1 || normalizeLetterSwipeSymbol(input) !== input ||
      cursorOffsetUtf16 === undefined || !Number.isInteger(cursorOffsetUtf16) ||
      cursorOffsetUtf16 <= 0 || cursorOffsetUtf16 >= input.length) {
      this.store.recordError(ImeErrorCode.INVALID_ARGUMENT, 'literal symbol pair is invalid');
      return inputOperationFailed(ImeErrorCode.INVALID_ARGUMENT, 'literal symbol pair is invalid');
    }
    const sessionCheck = this.ensureInputSession('literal symbol pair');
    if (!sessionCheck.success) {
      return sessionCheck;
    }

    const state = this.store.getSnapshot();
    if (state.rawInput.length > 0) {
      const cleared = await this.imeService.clearPreviewText(generation);
      if (!this.isInputSessionGenerationCurrent(generation)) {
        return this.staleInputAction('literal symbol pair composition clear');
      }
      if (!cleared) {
        this.store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'literal symbol pair composition clear failed');
        return inputOperationFailed(
          ImeErrorCode.ENGINE_INTERNAL_ERROR,
          'literal symbol pair composition clear failed'
        );
      }
      this.engineCoordinator.reset();
      this.store.clearComposition();
    }

    const action: InsertPairAction = {
      type: 'INSERT_PAIR',
      formatId: '',
      text: input,
      cursorOffsetUtf16
    };
    const executed = await this.protocolActionExecutor.execute(action, generation);
    if (executed.committedText.length > 0 && executed.textInserted) {
      this.recordCommittedText(executed.committedText);
    }
    if (executed.status === ProtocolActionExecutionStatus.SESSION_INVALID ||
      !this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('literal symbol pair completion');
    }
    if (executed.status === ProtocolActionExecutionStatus.SUCCESS) {
      this.smartPeriodController.clear();
      this.store.clearError();
      return inputOperationOk();
    }

    const message = executed.textInserted
      ? 'literal symbol pair cursor positioning failed'
      : 'literal symbol pair insertion failed';
    this.store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, message);
    return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR, message);
  }

  /** Appends physical-keyboard punctuation without ending the active composition. */
  async insertPhysicalPunctuation(
    character: string,
    generation: number = this.getInputSessionGeneration(),
    inputAction?: SmartPeriodInputAction
  ): Promise<InputOperationResult> {
    if (character.length !== 1) {
      return inputOperationFailed(ImeErrorCode.INVALID_ARGUMENT, 'physical punctuation requires one character');
    }
    // If there are candidates, commit the first one before inserting punctuation
    const state = this.store.getSnapshot();
    if (state.keyboardMode === KeyboardMode.CHINESE && state.rawInput.length > 0 &&
      !state.rawInput.startsWith(';') && state.candidates.length > 0) {
      const confirmed = await this.commitCandidate(0, generation);
      if (!confirmed.success) {
        return confirmed;
      }
      if (!this.isInputSessionGenerationCurrent(generation)) {
        return this.staleInputAction('punctuation candidate commit');
      }
    }
    return this.insertSmartPunctuationOrText(character, 'physical punctuation suffix', generation, inputAction);
  }

  private normalizeChinesePunctuationInput(text: string, state: InputSessionState): string {
    const settings = this.settingsController.getSettings();
    const chineseMode = state.keyboardMode === KeyboardMode.CHINESE ||
      ((state.keyboardMode === KeyboardMode.SYMBOL || state.keyboardMode === KeyboardMode.NUMBER) &&
        state.modeBeforeTransient === KeyboardMode.CHINESE);
    return chineseMode && settings.punctuationMode === PunctuationMode.CHINESE
      ? chinesePunctuationForEnglishTarget(text)
      : text;
  }

  private async insertSmartPunctuationOrText(
    text: string,
    reason: string,
    generation: number,
    inputAction?: SmartPeriodInputAction
  ): Promise<InputOperationResult> {
    const targetText = smartPunctuationTarget(text);
    if (targetText === undefined) {
      return this.insertText(text, reason, generation);
    }

    const action = inputAction ?? this.beginInputAction();
    const settings = this.settingsController.getSettings();
    if (settings.punctuationMode === PunctuationMode.ENGLISH) {
      this.smartPeriodController.clear();
      return this.insertText(text, reason, generation);
    }
    const timeoutMs = settings.smartPeriodTimeoutMs;
    const enabled = isSmartPunctuationEnabled(settings.smartPunctuationSymbols, targetText);
    const previousSource = enabled
      ? this.smartPeriodController.shouldReplace(action, generation, timeoutMs, targetText)
      : undefined;
    if (targetText === '.' && settings.numericPeriodEnabled && previousSource === '.') {
      const deleted = this.imeService.deleteBackwardIfMatches !== undefined &&
        await this.imeService.deleteBackwardIfMatches(previousSource);
      if (!this.isInputSessionGenerationCurrent(generation)) {
        this.smartPeriodController.clear();
        return this.staleInputAction('numeric smart punctuation verification');
      }
      if (deleted) {
        const replaced = await this.insertText(text, 'numeric smart punctuation replacement', generation);
        this.smartPeriodController.clear();
        if (!replaced.success && this.isInputSessionGenerationCurrent(generation)) {
          await this.imeService.insertText(previousSource);
        }
        return replaced;
      }
    }
    if (targetText === '.' && settings.numericPeriodEnabled && this.imeService.getTextBeforeCursor !== undefined) {
      const before = await this.imeService.getTextBeforeCursor(1);
      if (!this.isInputSessionGenerationCurrent(generation)) {
        this.smartPeriodController.clear();
        return this.staleInputAction('numeric period verification');
      }
      if (before !== undefined && /^[0-9０-９]$/.test(before)) {
        const inserted = await this.insertText('.', reason, generation);
        if (inserted.success && timeoutMs > 0 && enabled) {
          this.smartPeriodController.recordPunctuation(action, generation, '.', targetText);
        } else {
          this.smartPeriodController.clear();
        }
        return inserted;
      }
    }
    if (timeoutMs <= 0 || !enabled) {
      this.smartPeriodController.clear();
      return this.insertText(text, reason, generation);
    }
    if (previousSource !== undefined) {
      let deleted = false;
      try {
        deleted = this.imeService.deleteBackwardIfMatches
          ? await this.imeService.deleteBackwardIfMatches(previousSource)
          : false;
      } catch (_err) {
        deleted = false;
      }
      if (!this.isInputSessionGenerationCurrent(generation)) {
        this.smartPeriodController.clear();
        return this.staleInputAction('smart punctuation verification');
      }
      if (deleted) {
        const replaced = await this.insertText(targetText, 'smart punctuation replacement', generation);
        this.smartPeriodController.clear();
        if (!replaced.success && this.isInputSessionGenerationCurrent(generation)) {
          // The verified Chinese punctuation was removed but the replacement was
          // rejected. Best-effort restoration keeps the editor unchanged.
          await this.imeService.insertText(previousSource);
        }
        return replaced;
      }
    }

    const inserted = await this.insertText(text, reason, generation);
    if (inserted.success && this.isInputSessionGenerationCurrent(generation)) {
      this.smartPeriodController.recordPunctuation(action, generation, text, targetText);
    } else {
      this.smartPeriodController.clear();
    }
    return inserted;
  }

  /** Deletes an editor suffix while preserving raw input and its candidates. */
  async deletePhysicalPunctuationSuffix(
    generation: number = this.getInputSessionGeneration()
  ): Promise<InputOperationResult> {
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('physical punctuation delete');
    }
    const sessionCheck = this.ensureInputSession('physical punctuation delete');
    if (!sessionCheck.success) {
      return sessionCheck;
    }
    const deleted = await this.imeService.deleteBackward(1);
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('physical punctuation delete completion');
    }
    if (deleted) {
      this.store.clearError();
      return inputOperationOk();
    }
    this.store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'physical punctuation delete failed');
    return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'physical punctuation delete failed');
  }

  /**
   * Inserts a symbol string of arbitrary length directly into the editor,
   * clearing any active composition first. Used by the physical keyboard
   * symbol guide so that multi-character symbols like '……' are accepted.
   */
  async insertSymbolText(
    symbol: string,
    generation: number = this.getInputSessionGeneration()
  ): Promise<InputOperationResult> {
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('symbol');
    }
    if (symbol.length === 0) {
      return inputOperationFailed(ImeErrorCode.INVALID_ARGUMENT, 'symbol must not be empty');
    }
    const state = this.store.getSnapshot();
    if (state.rawInput.length > 0) {
      const cleared = await this.imeService.clearPreviewText(generation);
      if (!this.isInputSessionGenerationCurrent(generation)) {
        return this.staleInputAction('symbol composition clear');
      }
      if (!cleared) {
        this.store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'symbol composition clear failed');
        return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'symbol composition clear failed');
      }
      this.engineCoordinator.reset();
      this.store.clearComposition();
    }
    return this.insertText(symbol, 'symbol guide', generation);
  }

  async insertSpace(
    generation: number = this.getInputSessionGeneration(),
    candidateIndex: number = 0
  ): Promise<InputOperationResult> {
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('space');
    }
    const mode = this.store.getSnapshot().keyboardMode;
    if (mode === KeyboardMode.CHINESE || isConvenienceInput(this.store.getSnapshot().rawInput)) {
      const state = this.store.getSnapshot();
      if (state.candidates.length > 0) {
        return this.commitCandidate(candidateIndex, generation);
      }
      if (state.rawInput.length > 0) {
        // No-candidate raw pinyin is cancelled, never finished into editor
        // text. The explicit space itself is inserted below.
        const finished = await this.imeService.clearPreviewText(generation);
        if (!this.isInputSessionGenerationCurrent(generation)) {
          return this.staleInputAction('space preview completion');
        }
        if (!finished) {
          this.store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'space preview finish failed');
          return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'space preview finish failed');
        }
        if (this.engineCoordinator.isInitialized()) {
          this.engineCoordinator.reset();
        }
        this.store.clearComposition();
      }
      LOGGER.info('space in chinese mode cancels no-candidate composition and inserts only the space');
    }
    return this.insertText(' ', 'space', generation);
  }

  async nextCandidatePage(
    generation: number = this.getInputSessionGeneration()
  ): Promise<InputOperationResult> {
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('next candidate page');
    }
    const sessionCheck = this.ensureInputSession('next candidate page');
    if (!sessionCheck.success) {
      return sessionCheck;
    }

    const result = this.engineCoordinator.nextCandidatePage();
    if (result.success) {
      this.store.updateComposition(result);
      return inputOperationOk();
    }
    // A failed page request must not replace the current, still-clickable page.
    this.store.recordError(result.errorCode, result.errorMessage);
    return inputOperationFailed(result.errorCode, result.errorMessage);
  }

  moveCandidateHighlight(delta: number): InputOperationResult {
    const state = this.store.getSnapshot();
    if (!state.sessionActive || !state.editorConnected || (state.keyboardMode !== KeyboardMode.CHINESE && !isConvenienceInput(state.rawInput)) ||
      !state.candidateBarVisible || state.rawInput.length === 0 || state.candidates.length === 0) {
      return inputOperationFailed(ImeErrorCode.UNSUPPORTED_OPERATION, 'candidate selection is unavailable');
    }
    this.store.moveCandidateHighlight(delta);
    return inputOperationOk();
  }

  async cancelComposition(
    generation: number = this.getInputSessionGeneration()
  ): Promise<InputOperationResult> {
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('cancel composition');
    }
    const state = this.store.getSnapshot();
    if (!state.sessionActive || !state.editorConnected || (state.keyboardMode !== KeyboardMode.CHINESE && !isConvenienceInput(state.rawInput)) ||
      state.rawInput.length === 0) {
      return inputOperationFailed(ImeErrorCode.UNSUPPORTED_OPERATION, 'cancel requires chinese composition');
    }
    const cleared = await this.imeService.clearPreviewText(generation);
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('cancel composition completion');
    }
    if (!cleared) {
      this.store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'cancel composition preview cleanup failed');
      return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'cancel composition preview cleanup failed');
    }
    this.imeService.resetPreviewState();
    if (this.engineCoordinator.isInitialized()) {
      this.store.updateComposition(this.engineCoordinator.reset());
    }
    this.store.clearComposition();
    return inputOperationOk();
  }

  async previousCandidatePage(
    generation: number = this.getInputSessionGeneration()
  ): Promise<InputOperationResult> {
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('previous candidate page');
    }
    const sessionCheck = this.ensureInputSession('previous candidate page');
    if (!sessionCheck.success) {
      return sessionCheck;
    }

    const result = this.engineCoordinator.previousCandidatePage();
    if (result.success) {
      this.store.updateComposition(result);
      return inputOperationOk();
    }
    // Keep the current page intact on failure; only surface the operation error.
    this.store.recordError(result.errorCode, result.errorMessage);
    return inputOperationFailed(result.errorCode, result.errorMessage);
  }

  async deleteBackward(
    generation: number = this.getInputSessionGeneration()
  ): Promise<InputOperationResult> {
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('delete');
    }
    const sessionCheck = this.ensureInputSession('delete');
    if (!sessionCheck.success) {
      return sessionCheck;
    }

    const state = this.store.getSnapshot();
    if (state.keyboardMode === KeyboardMode.CHINESE && state.rawInput.length === 0 &&
      this.canJumpOutPair(generation)) {
      return this.jumpOutPair(generation);
    }
    if ((state.keyboardMode === KeyboardMode.CHINESE || isConvenienceInput(state.rawInput)) && state.rawInput.length > 0) {
      const detached = await this.resetCompositionDetachedByEditor(state, generation);
      if (!this.isInputSessionGenerationCurrent(generation)) {
        return this.staleInputAction('delete attachment check');
      }
      if (detached) {
        // The host editor already removed or detached the old composition.
        // Consume this delete as the cancellation of that stale composition;
        // issuing another editor delete could erase unrelated user text.
        this.store.clearError();
        return inputOperationOk();
      }
      const result = this.engineCoordinator.backspace();
      if (!result.success) {
        this.store.updateComposition(result);
        return inputOperationFailed(result.errorCode, result.errorMessage);
      }
      const previewUpdated = await this.updateCompositionText(
        result.rawInput,
        this.shouldUseCursorPreedit(state),
        generation
      );
      if (!this.isInputSessionGenerationCurrent(generation)) {
        return this.staleInputAction('delete composition completion');
      }
      if (!previewUpdated) {
        this.store.updateComposition(this.restoreEngineComposition(state));
        this.store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'delete composition update failed');
        return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'delete composition update failed');
      }
      this.store.updateComposition(result);
      return inputOperationOk();
    }

    const deleted = await this.imeService.deleteBackward(1);
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('delete completion');
    }
    if (deleted) {
      this.store.clearError();
      return inputOperationOk();
    }

    this.store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'delete verification failed');
    return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'delete verification failed');
  }

  async restoreLastDeletion(
    generation: number = this.getInputSessionGeneration()
  ): Promise<InputOperationResult> {
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('restore last deletion');
    }
    const sessionCheck = this.ensureInputSession('restore last deletion');
    if (!sessionCheck.success) {
      return sessionCheck;
    }
    if (this.store.getSnapshot().rawInput.length > 0 || this.imeService.restoreLastDeletion === undefined) {
      return inputOperationFailed(ImeErrorCode.UNSUPPORTED_OPERATION, 'restore last deletion is unavailable');
    }
    const restored = await this.imeService.restoreLastDeletion();
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('restore last deletion completion');
    }
    if (restored) {
      this.store.clearError();
      return inputOperationOk();
    }
    this.store.recordError(ImeErrorCode.UNSUPPORTED_OPERATION, 'restore last deletion failed');
    return inputOperationFailed(ImeErrorCode.UNSUPPORTED_OPERATION, 'restore last deletion failed');
  }

  private async resetCompositionDetachedByEditor(
    state: InputSessionState,
    generation: number
  ): Promise<boolean> {
    if (state.rawInput.length === 0 || state.editorContext.textPreviewSupported) {
      return false;
    }
    const attached = await this.imeService.isPreviewTextAttached(generation);
    if (attached || !this.isInputSessionGenerationCurrent(generation)) {
      return false;
    }

    // Some host editors (including Browser Search) clear their text without
    // emitting discardTypingText. Drop only local ownership and start the next
    // key as a fresh composition; never write the stale range back.
    this.imeService.resetPreviewState();
    if (this.engineCoordinator.isInitialized()) {
      this.store.updateComposition(this.engineCoordinator.reset());
    }
    this.store.clearComposition();
    LOGGER.info('detached compatible composition reset before input');
    return true;
  }

  async sendEnter(
    generation: number = this.getInputSessionGeneration()
  ): Promise<InputOperationResult> {
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('enter');
    }
    const sessionCheck = this.ensureInputSession('enter');
    if (!sessionCheck.success) {
      return sessionCheck;
    }

    const state = this.store.getSnapshot();
    if ((state.keyboardMode === KeyboardMode.CHINESE || isConvenienceInput(state.rawInput)) && state.rawInput.length > 0) {
      // Enter explicitly commits the exact code, including incomplete and
      // functional codes. Candidate selection and host Enter are separate actions.
      return this.commitRawInput(state.rawInput, generation);
    }

    const sent = await this.imeService.sendEnter(state.enterAction);
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('enter completion');
    }
    if (sent) {
      this.store.clearError();
      return inputOperationOk();
    }

    this.store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'enter key function failed');
    return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'enter key function failed');
  }

  private async commitRawInput(rawInput: string, generation: number): Promise<InputOperationResult> {
    let inserted = false;
    try {
      // Replace any native/compatible preedit once, preserving the engine and
      // candidates until the editor accepts the code.
      inserted = await this.imeService.commitPreviewText(rawInput, generation);
    } catch (err) {
      LOGGER.error('enter code commit failed: editor exception');
    }
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('enter code commit completion');
    }
    if (!inserted) {
      this.store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'enter code commit failed');
      return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'enter code commit failed');
    }

    this.recordCommittedText(rawInput);
    this.imeService.resetPreviewState();
    let reset = true;
    try {
      if (this.engineCoordinator.isInitialized()) {
        reset = this.engineCoordinator.reset().success;
      }
    } catch (err) {
      reset = false;
    }
    // The editor already accepted the code. Never leave a retryable copy that
    // could commit it twice, even if native cleanup fails.
    this.store.clearComposition();
    this.syncCursorPreeditVisibility('');
    if (!reset) {
      this.store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'enter code reset failed');
      return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'enter code reset failed');
    }
    this.store.clearError();
    return inputOperationOk();
  }

  async hideKeyboard(
    generation: number = this.getInputSessionGeneration()
  ): Promise<InputOperationResult> {
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('hide keyboard');
    }
    const state = this.store.getSnapshot();
    if (!state.sessionActive) {
      this.store.recordError(ImeErrorCode.ENGINE_NOT_INITIALIZED, 'hide keyboard requires active session');
      return inputOperationFailed(ImeErrorCode.ENGINE_NOT_INITIALIZED, 'hide keyboard requires active session');
    }
    if (!state.keyboardVisible || this.isHideKeyboardInProgress) {
      return inputOperationOk();
    }

    this.isHideKeyboardInProgress = true;
    try {

      if (this.engineCoordinator.isInitialized()) {
        const status = this.engineCoordinator.flushUserModel();
        if (status.lastErrorCode.length > 0) {
          LOGGER.warn(`hide keyboard user model flush failed: ${status.lastErrorCode}`);
        }
      }

      const current = this.store.getSnapshot();
      if (current.rawInput.length > 0) {
        const cleared = await this.imeService.clearPreviewText(generation);
        if (!this.isInputSessionGenerationCurrent(generation)) {
          return this.staleInputAction('hide keyboard preview completion');
        }
        if (!cleared) {
          LOGGER.warn('hide keyboard preview cleanup failed; continuing to hide without fallback text edits');
        }
        if (this.engineCoordinator.isInitialized()) {
          this.engineCoordinator.reset();
        }
        this.store.clearComposition();
      }

      const hidden = await this.imeService.hideKeyboard();
      if (!this.isInputSessionGenerationCurrent(generation)) {
        return this.staleInputAction('hide keyboard completion');
      }
      if (hidden) {
        this.inputMethodSwitcher.setSessionActive(false);
        this.store.markKeyboardHidden();
        return inputOperationOk();
      }

      this.store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'hide keyboard failed');
      return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'hide keyboard failed');
    } finally {
      this.isHideKeyboardInProgress = false;
    }
  }

  private restoreEngineComposition(state: InputSessionState): CompositionResult {
    const rawInput = state.rawInput;
    let restored = this.engineCoordinator.reset();
    const hasEmbeddedBoundary = rawInput.indexOf("'") >= 0;
    for (let index = 0; index < rawInput.length; index += 1) {
      if (!hasEmbeddedBoundary && state.segmentBoundaries.indexOf(index) >= 0) {
        restored = this.engineCoordinator.insertSegmentBoundary();
        if (!restored.success) {
          break;
        }
      }
      restored = !isConvenienceInput(rawInput) && rawInput[index] === "'"
        ? this.engineCoordinator.insertSegmentBoundary()
        : this.engineCoordinator.processKey(rawInput[index]);
      if (!restored.success) {
        break;
      }
    }
    if (restored.success && !hasEmbeddedBoundary && state.segmentBoundaries.indexOf(rawInput.length) >= 0) {
      restored = this.engineCoordinator.insertSegmentBoundary();
    }
    if (restored.success && state.currentPinyin.length > 0 && restored.currentPinyin !== state.currentPinyin) {
      const published = [restored.currentPinyin].concat(restored.pinyinCombinations ?? []);
      const selectedIndex = published.indexOf(state.currentPinyin);
      if (selectedIndex >= 0) {
        restored = this.engineCoordinator.selectPinyinCombination(selectedIndex);
      }
    }
    return restored;
  }
}
