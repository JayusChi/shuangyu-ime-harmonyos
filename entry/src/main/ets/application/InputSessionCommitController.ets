import { SHAPE_LOOKUP_TARGET } from '../domain/direct/ShapeLookup';
import { CLIPBOARD_REVERSE_CODE, CLIPBOARD_REVERSE_LABEL } from '../domain/direct/ClipboardReverseLookup';
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
import { ImeSettings, PINYIN_9_SCHEME_ID, XIAOHE_YINXING_SCHEME_ID } from '../domain/settings/ImeSettings';
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
import { CompositionResult, NativeEngineGatewayContract } from '../infrastructure/native/NativeEngineTypes';
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

import { InputSessionControllerBase } from './InputSessionControllerBase';

const TAG = 'InputSessionController';
const LOGGER = new Logger(TAG);

function remainingRawInputAfterCandidate(rawInput: string, consumedRawLen: number | undefined): string {
  if (consumedRawLen === undefined || consumedRawLen <= 0) {
    return '';
  }
  let lettersSeen = 0;
  let remainingStart = rawInput.length;
  for (let index = 0; index < rawInput.length; index += 1) {
    const character = rawInput.charAt(index);
    if (character !== "'" && character !== ';') {
      if (lettersSeen === consumedRawLen) {
        remainingStart = index;
        break;
      }
      lettersSeen += 1;
    }
  }
  let remaining = rawInput.slice(remainingStart);
  while (remaining.startsWith("'")) {
    remaining = remaining.slice(1);
  }
  return remaining;
}

export class InputSessionCommitController extends InputSessionControllerBase {
  async commitCandidate(
    candidateIndex: number,
    generation: number = this.getInputSessionGeneration()
  ): Promise<InputOperationResult> {
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('candidate commit');
    }
    const sessionCheck = this.ensureInputSession('candidate commit');
    if (!sessionCheck.success) {
      return sessionCheck;
    }
    if (!Number.isInteger(candidateIndex) || candidateIndex < 0) {
      this.store.recordError(ImeErrorCode.INVALID_CANDIDATE, 'candidate index is invalid');
      return inputOperationFailed(ImeErrorCode.INVALID_CANDIDATE, 'candidate index is invalid');
    }

    const state = this.store.getSnapshot();
    if (state.editorContext.isPassword || (state.keyboardMode !== KeyboardMode.CHINESE && !isConvenienceInput(state.rawInput)) ||
      !state.candidateBarVisible) {
      this.store.recordError(ImeErrorCode.UNSUPPORTED_OPERATION, 'candidate commit is disabled for this editor');
      return inputOperationFailed(ImeErrorCode.UNSUPPORTED_OPERATION, 'candidate commit is disabled for this editor');
    }

    if (this.isCandidateCommitInProgress) {
      LOGGER.warn(`candidate commit rejected: stage=prepare, index=${candidateIndex}, reason=in-progress`);
      this.store.recordError(ImeErrorCode.UNSUPPORTED_OPERATION, 'candidate commit is already in progress');
      return inputOperationFailed(ImeErrorCode.UNSUPPORTED_OPERATION, 'candidate commit is already in progress');
    }

    const candidate = state.candidates[candidateIndex];
    if (!candidate || candidate.text.length <= 0) {
      LOGGER.warn(`candidate commit failed: stage=prepare, index=${candidateIndex}, reason=unavailable`);
      this.store.recordError(ImeErrorCode.INVALID_CANDIDATE, 'candidate is unavailable');
      return inputOperationFailed(ImeErrorCode.INVALID_CANDIDATE, 'candidate is unavailable');
    }

    this.isCandidateCommitInProgress = true;
    try {
      LOGGER.info(`candidate commit started: stage=prepare, index=${candidateIndex}`);
      if (candidate.source === 'functional') {
        if (state.rawInput === CLIPBOARD_REVERSE_CODE && candidate.text === CLIPBOARD_REVERSE_LABEL) {
          return await this.commitClipboardReverseCandidate(candidateIndex, generation);
        }
        return await this.commitFunctionalCandidate(candidateIndex, generation);
      }
      const predictedRemainingRaw = remainingRawInputAfterCandidate(
        state.rawInput,
        candidate.consumedRawLen
      );
      const supportsAtomicPartialCommit = this.imeService.commitCandidatePreviewText !== undefined;
      let inserted = false;
      try {
        if (this.imeService.commitCandidatePreviewText !== undefined) {
          inserted = await this.imeService.commitCandidatePreviewText(
            candidate.text,
            predictedRemainingRaw,
            generation
          );
        } else {
          inserted = await this.imeService.commitPreviewText(candidate.text, generation);
        }
      } catch (err) {
        if (!this.isInputSessionGenerationCurrent(generation)) {
          return this.staleInputAction('candidate commit completion');
        }
        LOGGER.error(`candidate commit failed: stage=insert, index=${candidateIndex}, reason=exception`);
        this.store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'candidate commit insert failed');
        return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'candidate commit insert failed');
      }

      if (!this.isInputSessionGenerationCurrent(generation)) {
        return this.staleInputAction('candidate commit completion');
      }

      if (!inserted) {
        LOGGER.warn(`candidate commit failed: stage=insert, index=${candidateIndex}, reason=rejected`);
        this.store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'candidate commit insert failed');
        return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'candidate commit insert failed');
      }
      this.syncCursorPreeditVisibility(predictedRemainingRaw);

      // Native selection consumes composition and records learning, so it is the
      // confirmation phase and must only run after the editor accepts the text.
      LOGGER.info(`candidate commit continuing: stage=nativeCommit, index=${candidateIndex}`);
      let result: CompositionResult;
      try {
        result = this.engineCoordinator.selectCandidate(this.store.resolveEngineCandidateIndex(candidateIndex));
      } catch (err) {
        return this.handleCandidateConfirmationFailure(
          candidateIndex,
          ImeErrorCode.NATIVE_BRIDGE_ERROR,
          'native candidate confirmation threw an exception'
        );
      }
      if (!result.success) {
        return this.handleCandidateConfirmationFailure(
          candidateIndex,
          result.errorCode,
          result.errorMessage
        );
      }

      if (supportsAtomicPartialCommit && result.rawInput !== predictedRemainingRaw) {
        // The native consumedRawLen contract and post-selection state should
        // agree. Reconcile defensively without re-inserting the committed
        // Chinese prefix if a future engine version returns a different tail.
        const reconciled = await this.updateCompositionText(
          result.rawInput,
          this.shouldUseCursorPreedit(state),
          generation
        );
        if (!this.isInputSessionGenerationCurrent(generation)) {
          return this.staleInputAction('candidate remaining reconciliation');
        }
        if (!reconciled) {
          this.clearCompositionAfterInsertedText(candidateIndex);
          this.store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'remaining text reconciliation failed');
          return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'remaining text reconciliation failed');
        }
      } else if (!supportsAtomicPartialCommit && result.rawInput.length > 0) {
        // A legacy service without the atomic partial-commit method keeps the
        // remaining code in the candidate-bar composition path. It must not
        // reinsert that raw tail into the editor beside the committed prefix.
        const remainingPreviewUpdated = await this.updateCompositionText(
          result.rawInput,
          this.shouldUseCursorPreedit(state),
          generation,
          true
        );
        if (!this.isInputSessionGenerationCurrent(generation)) {
          return this.staleInputAction('candidate remaining preview completion');
        }
        if (!remainingPreviewUpdated) {
          this.clearCompositionAfterInsertedText(candidateIndex);
          this.store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'remaining text preview update failed');
          return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'remaining text preview update failed');
        }
      }

      try {
        this.store.updateComposition(result);
      } catch (err) {
        LOGGER.error(`candidate commit failed: stage=storeSync, index=${candidateIndex}, reason=exception`);
        this.clearCompositionAfterInsertedText(candidateIndex);
        this.store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'candidate commit store sync failed');
        return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'candidate commit store sync failed');
      }

      // Record commit history
      this.commitHistoryManager.addCommit(candidate.text);
      if (this.undoCommitManager) {
        this.undoCommitManager.recordCommit(candidate.text);
      }
      if (result.rawInput.length === 0) {
        this.publishLocalAssociations();
      }

      LOGGER.info(`candidate commit completed: stage=completed, index=${candidateIndex}`);
      return inputOperationOk();
    } finally {
      this.isCandidateCommitInProgress = false;
    }
  }

  private async commitClipboardReverseCandidate(candidateIndex: number, generation: number): Promise<InputOperationResult> {
    if (this.store.getClipboardReverseResult() === undefined) {
      await this.refreshClipboardReverseCandidate(generation);
    }
    if (!this.isInputSessionGenerationCurrent(generation)) { return this.staleInputAction('clipboard reverse'); }
    const lookup = this.store.getClipboardReverseResult();
    if (lookup === undefined || !lookup.available) {
      const message = '请点击候选区的粘贴按钮，读取单字后反查';
      return inputOperationFailed(ImeErrorCode.UNSUPPORTED_OPERATION, message);
    }
    // Display and commit share the same snapshot. Never insert the placeholder,
    // clipboard contents or the triggering code into the editor.
    const inserted = lookup.text.length > 0
      ? await this.imeService.commitPreviewText(lookup.text, generation)
      : await this.imeService.clearPreviewText(generation);
    if (!this.isInputSessionGenerationCurrent(generation)) { return this.staleInputAction('clipboard reverse completion'); }
    if (!inserted) {
      return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR, '反查编码上屏失败，请重试');
    }
    if (lookup.text.length > 0) { this.recordCommittedText(lookup.text); }
    // The clipboard action was fulfilled above; consume its native candidate
    // only after the editor succeeds, without dispatching the action twice.
    try { this.engineCoordinator.selectCandidate(this.store.resolveEngineCandidateIndex(candidateIndex)); } finally {
      this.engineCoordinator.reset();
      this.store.clearComposition();
      this.syncCursorPreeditVisibility('');
    }
    return inputOperationOk();
  }

  private async commitFunctionalCandidate(
    candidateIndex: number,
    generation: number
  ): Promise<InputOperationResult> {
    let result: CompositionResult;
    try {
      result = this.engineCoordinator.selectCandidate(this.store.resolveEngineCandidateIndex(candidateIndex));
    } catch (err) {
      this.store.recordError(ImeErrorCode.NATIVE_BRIDGE_ERROR, 'functional candidate confirmation failed');
      return inputOperationFailed(ImeErrorCode.NATIVE_BRIDGE_ERROR, 'functional candidate confirmation failed');
    }
    if (!result.success || (result.commitText.length > 0 && result.action !== null &&
      result.action !== undefined)) {
      const code = result.success ? ImeErrorCode.SERIALIZATION_ERROR : result.errorCode;
      this.store.recordError(code, 'functional candidate was rejected');
      return inputOperationFailed(code, 'functional candidate was rejected');
    }

    let inserted = false;
    let actionSucceeded = false;
    if (result.commitText.length > 0) {
      inserted = await this.imeService.commitPreviewText(result.commitText, generation);
      actionSucceeded = inserted;
      if (inserted) {
        this.recordCommittedText(result.commitText);
        this.publishLocalAssociations();
      }
    } else if (result.action !== null && result.action !== undefined) {
      // Navigation/settings actions must not strand embedded codes in the editor.
      // Text-producing actions replace the preview through their own commit path.
      const actionClearsPreview = result.action.type === 'DIRECT_CONTROL' &&
        (result.action.formatId === 'editor.delete-line' ||
          (result.action.formatId === 'url.open' && result.action.text === SHAPE_LOOKUP_TARGET));
      if (!actionClearsPreview && result.action.type !== 'DATE_TIME_TEXT' && result.action.type !== 'INSERT_PAIR' &&
        this.imeService.isCursorPreviewActive?.() === true) {
        const cleared = await this.imeService.clearPreviewText(generation);
        if (!this.isInputSessionGenerationCurrent(generation)) { return this.staleInputAction('functional preview clear'); }
        if (!cleared) {
          return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'functional preview clear failed');
        }
        this.store.setCursorPreeditVisible(false);
      }
      const executed = await this.protocolActionExecutor.execute(result.action, generation);
      inserted = executed.textInserted;
      actionSucceeded = executed.status === ProtocolActionExecutionStatus.SUCCESS;
      if (executed.committedText.length > 0 && executed.textInserted) {
        this.recordCommittedText(executed.committedText);
      }
      if (executed.status === ProtocolActionExecutionStatus.SESSION_INVALID) {
        return this.staleInputAction('functional action completion');
      }
    }

    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('functional candidate completion');
    }
    if (!actionSucceeded) {
      // Native already consumed this candidate. Never replay it automatically;
      // if pair insertion succeeded but cursor placement failed, preserve the
      // inserted text and only clear stale composition state.
      this.store.clearComposition();
      this.store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR,
        inserted ? 'action completed with cursor fallback' : 'functional action failed');
      return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR,
        inserted ? 'action completed with cursor fallback' : 'functional action failed');
    }
    this.store.updateComposition(result);
    return inputOperationOk();
  }

  private handleCandidateConfirmationFailure(
    candidateIndex: number,
    errorCode: ImeErrorCode,
    errorMessage: string
  ): InputOperationResult {
    const resolvedCode = errorCode === ImeErrorCode.SUCCESS ? ImeErrorCode.ENGINE_INTERNAL_ERROR : errorCode;
    LOGGER.error(`candidate commit failed: stage=nativeCommit, index=${candidateIndex}, code=${resolvedCode}`);
    // The editor already contains the text. Clear the stale composition instead
    // of restoring a retryable state that could insert the same text twice.
    this.clearCompositionAfterInsertedText(candidateIndex);
    const message = errorMessage.length > 0 ? errorMessage : 'native candidate confirmation failed';
    this.store.recordError(resolvedCode, message);
    return inputOperationFailed(resolvedCode, message);
  }

  private clearCompositionAfterInsertedText(candidateIndex: number): void {
    LOGGER.warn(`candidate commit recovery: stage=rollback, index=${candidateIndex}, action=clear-stale-composition`);
    try {
      this.engineCoordinator.reset();
    } catch (err) {
      LOGGER.error(`candidate commit recovery failed: stage=rollback, index=${candidateIndex}, target=native`);
    }
    this.store.clearComposition();
  }

}
