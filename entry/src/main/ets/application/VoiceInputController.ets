import { Logger } from '../common/logging/Logger';
import { ImeSettings } from '../domain/settings/ImeSettings';
import { resolveAssistAvailability } from '../domain/security/InputMethodCapabilityState';
import {
  createIdleVoicePresentationState,
  MAX_VOICE_RESULT_TEXT_LENGTH,
  VoiceErrorCode,
  VoicePresentationState,
  VoiceRecognitionRequest,
  VoiceRecognitionResult,
  VoiceSessionState
} from '../domain/voice/VoiceContracts';
import {
  SpeechRecognitionListener,
  SpeechRecognitionProvider
} from '../infrastructure/speech/SpeechRecognitionProvider';
import { InputSessionStore } from '../state/InputSessionStore';
import { ImeInputService } from './ImeInputService';

const LOGGER = new Logger('VoiceInputController');

class VoiceControllerListener implements SpeechRecognitionListener {
  private readonly resultHandler: (result: VoiceRecognitionResult) => void;
  private readonly errorHandler: (voiceSessionId: string, errorCode: VoiceErrorCode) => void;

  constructor(
    resultHandler: (result: VoiceRecognitionResult) => void,
    errorHandler: (voiceSessionId: string, errorCode: VoiceErrorCode) => void
  ) {
    this.resultHandler = resultHandler;
    this.errorHandler = errorHandler;
  }

  onResult(result: VoiceRecognitionResult): void {
    this.resultHandler(result);
  }

  onError(voiceSessionId: string, errorCode: VoiceErrorCode): void {
    this.errorHandler(voiceSessionId, errorCode);
  }
}

export class VoiceInputController {
  private readonly store: InputSessionStore;
  private readonly settingsProvider: () => ImeSettings;
  private readonly provider: SpeechRecognitionProvider;
  private readonly imeService: ImeInputService;
  private readonly commitRecorder: (text: string) => void;
  private activeRequest?: VoiceRecognitionRequest;
  private sessionSequence: number = 0;
  private timeoutId?: number;
  private readonly maxDurationMs: number;

  constructor(
    store: InputSessionStore,
    settingsProvider: () => ImeSettings,
    provider: SpeechRecognitionProvider,
    imeService: ImeInputService,
    commitRecorder: (text: string) => void,
    maxDurationMs: number = 20000
  ) {
    this.store = store;
    this.settingsProvider = settingsProvider;
    this.provider = provider;
    this.imeService = imeService;
    this.commitRecorder = commitRecorder;
    this.maxDurationMs = Math.max(1, maxDurationMs);
  }

  start(): boolean {
    this.cancelActive(false);
    const snapshot = this.store.getSnapshot();
    const settings = this.settingsProvider();
    const availability = resolveAssistAvailability(
      snapshot.capabilityState,
      snapshot.editorContext,
      settings,
      snapshot.sessionActive,
      snapshot.editorConnected
    ).voice;
    if (!availability.available) {
      this.store.updateVoicePresentation({
        state: VoiceSessionState.UNAVAILABLE,
        voiceSessionId: '',
        sessionGeneration: this.store.getSessionGeneration(),
        language: settings.voiceLanguage,
        interimText: '',
        finalText: '',
        errorCode: VoiceErrorCode.UNAVAILABLE,
        statusMessage: availability.message
      });
      return false;
    }

    const generation = this.store.getSessionGeneration();
    this.sessionSequence += 1;
    const request: VoiceRecognitionRequest = {
      voiceSessionId: `voice-${generation}-${this.sessionSequence}`,
      sessionGeneration: generation,
      language: settings.voiceLanguage,
      maxDurationMs: this.maxDurationMs
    };
    this.activeRequest = request;
    this.store.updateVoicePresentation({
      state: VoiceSessionState.PREPARING,
      voiceSessionId: request.voiceSessionId,
      sessionGeneration: generation,
      language: request.language,
      interimText: '',
      finalText: '',
      errorCode: VoiceErrorCode.NONE,
      statusMessage: 'AI-0 语音流程验证中'
    });
    const listener = new VoiceControllerListener(
      (result: VoiceRecognitionResult): void => this.handleResult(result),
      (voiceSessionId: string, errorCode: VoiceErrorCode): void =>
        this.handleProviderError(voiceSessionId, errorCode)
    );
    this.timeoutId = setTimeout((): void => this.handleTimeout(request.voiceSessionId), request.maxDurationMs);
    try {
      this.provider.start(request, listener);
      if (this.isActive(request.voiceSessionId, request.sessionGeneration) &&
        this.store.getSnapshot().voicePresentation.state === VoiceSessionState.PREPARING) {
        const preparing = this.store.getSnapshot().voicePresentation;
        this.store.updateVoicePresentation({
          state: VoiceSessionState.LISTENING,
          voiceSessionId: request.voiceSessionId,
          sessionGeneration: request.sessionGeneration,
          providerKind: preparing.providerKind,
          language: request.language,
          interimText: preparing.interimText,
          finalText: '',
          errorCode: VoiceErrorCode.NONE,
          statusMessage: '正在聆听，识别结果需确认后上屏'
        });
      }
      return true;
    } catch (_err) {
      this.handleProviderError(request.voiceSessionId, VoiceErrorCode.START_FAILED);
      return false;
    }
  }

  stop(): void {
    const request = this.activeRequest;
    if (!request || request.sessionGeneration !== this.store.getSessionGeneration()) {
      return;
    }
    const current = this.store.getSnapshot().voicePresentation;
    if (current.state !== VoiceSessionState.LISTENING) {
      return;
    }
    this.store.updateVoicePresentation({
      state: VoiceSessionState.FINALIZING,
      voiceSessionId: request.voiceSessionId,
      sessionGeneration: request.sessionGeneration,
      providerKind: current.providerKind,
      language: request.language,
      interimText: current.interimText,
      finalText: '',
      errorCode: VoiceErrorCode.NONE,
      statusMessage: '正在生成最终结果'
    });
    this.provider.stop(request.voiceSessionId);
  }

  async confirm(): Promise<boolean> {
    const request = this.activeRequest;
    const current = this.store.getSnapshot().voicePresentation;
    if (!request || current.state !== VoiceSessionState.RESULT_READY ||
      current.finalText.length <= 0 || request.voiceSessionId !== current.voiceSessionId ||
      request.sessionGeneration !== this.store.getSessionGeneration()) {
      return false;
    }
    this.store.updateVoicePresentation({
      state: VoiceSessionState.COMMITTING,
      voiceSessionId: request.voiceSessionId,
      sessionGeneration: request.sessionGeneration,
      providerKind: current.providerKind,
      language: request.language,
      interimText: '',
      finalText: current.finalText,
      errorCode: VoiceErrorCode.NONE,
      statusMessage: '正在上屏'
    });
    const inserted = await this.imeService.insertText(current.finalText);
    if (!this.isActive(request.voiceSessionId, request.sessionGeneration)) {
      return false;
    }
    if (!inserted) {
      this.store.updateVoicePresentation(this.errorPresentation(
        request,
        VoiceErrorCode.COMMIT_FAILED,
        '上屏失败，结果已保留',
        current.finalText
      ));
      return false;
    }
    this.commitRecorder(current.finalText);
    this.activeRequest = undefined;
    this.clearTimeout();
    this.store.updateVoicePresentation({
      state: VoiceSessionState.COMMITTED,
      voiceSessionId: request.voiceSessionId,
      sessionGeneration: request.sessionGeneration,
      providerKind: current.providerKind,
      language: request.language,
      interimText: '',
      finalText: '',
      errorCode: VoiceErrorCode.NONE,
      statusMessage: '语音结果已上屏，可撤销'
    });
    LOGGER.info(`voice result committed: length=${current.finalText.length}`);
    return true;
  }

  retry(): boolean {
    this.cancelActive(false);
    return this.start();
  }

  cancel(showCanceled: boolean = true): void {
    this.cancelActive(showCanceled);
  }

  invalidateForInput(): void {
    this.cancelActive(false);
  }

  private handleResult(result: VoiceRecognitionResult): void {
    const request = this.activeRequest;
    if (!request || result.voiceSessionId !== request.voiceSessionId ||
      result.sessionGeneration !== request.sessionGeneration ||
      !this.isActive(request.voiceSessionId, request.sessionGeneration)) {
      return;
    }
    if (result.errorCode !== VoiceErrorCode.NONE || result.text.length > MAX_VOICE_RESULT_TEXT_LENGTH ||
      result.language !== request.language) {
      this.handleProviderError(request.voiceSessionId, VoiceErrorCode.PROTOCOL_ERROR);
      return;
    }
    const current = this.store.getSnapshot().voicePresentation;
    if (current.state === VoiceSessionState.RESULT_READY ||
      current.state === VoiceSessionState.COMMITTING || current.state === VoiceSessionState.COMMITTED) {
      return;
    }
    if (!result.isFinal) {
      this.store.updateVoicePresentation({
        state: VoiceSessionState.LISTENING,
        voiceSessionId: request.voiceSessionId,
        sessionGeneration: request.sessionGeneration,
        providerKind: result.providerKind,
        language: result.language,
        interimText: result.text,
        finalText: '',
        errorCode: VoiceErrorCode.NONE,
        statusMessage: '正在识别'
      });
      return;
    }
    this.clearTimeout();
    if (result.text.length <= 0) {
      this.store.updateVoicePresentation(this.errorPresentation(
        request,
        VoiceErrorCode.NO_RESULT,
        '未识别到语音内容'
      ));
      this.activeRequest = undefined;
      return;
    }
    this.store.updateVoicePresentation({
      state: VoiceSessionState.RESULT_READY,
      voiceSessionId: request.voiceSessionId,
      sessionGeneration: request.sessionGeneration,
      providerKind: result.providerKind,
      language: result.language,
      interimText: '',
      finalText: result.text,
      errorCode: VoiceErrorCode.NONE,
      statusMessage: '语音结果待确认'
    });
  }

  private handleProviderError(voiceSessionId: string, errorCode: VoiceErrorCode): void {
    const request = this.activeRequest;
    if (!request || request.voiceSessionId !== voiceSessionId) {
      return;
    }
    if (!this.isActive(request.voiceSessionId, request.sessionGeneration)) {
      this.activeRequest = undefined;
      this.clearTimeout();
      return;
    }
    const current = this.store.getSnapshot().voicePresentation;
    if (current.state === VoiceSessionState.RESULT_READY ||
      current.state === VoiceSessionState.COMMITTING || current.state === VoiceSessionState.COMMITTED) {
      return;
    }
    const resolvedError = errorCode === VoiceErrorCode.NONE
      ? VoiceErrorCode.PROTOCOL_ERROR
      : errorCode;
    this.activeRequest = undefined;
    this.clearTimeout();
    this.store.updateVoicePresentation(this.errorPresentation(request, resolvedError, '语音 Provider 调用失败'));
  }

  private handleTimeout(voiceSessionId: string): void {
    const request = this.activeRequest;
    if (!request || request.voiceSessionId !== voiceSessionId) {
      return;
    }
    if (!this.isActive(request.voiceSessionId, request.sessionGeneration)) {
      this.provider.cancel(voiceSessionId);
      this.activeRequest = undefined;
      this.clearTimeout();
      return;
    }
    this.provider.cancel(voiceSessionId);
    this.activeRequest = undefined;
    this.clearTimeout();
    this.store.updateVoicePresentation(this.errorPresentation(request, VoiceErrorCode.TIMEOUT, '语音会话已超时'));
  }

  private cancelActive(showCanceled: boolean): void {
    const request = this.activeRequest;
    if (request) {
      this.provider.cancel(request.voiceSessionId);
    }
    this.activeRequest = undefined;
    this.clearTimeout();
    if (showCanceled && request) {
      this.store.updateVoicePresentation({
        state: VoiceSessionState.CANCELED,
        voiceSessionId: request.voiceSessionId,
        sessionGeneration: request.sessionGeneration,
        language: request.language,
        interimText: '',
        finalText: '',
        errorCode: VoiceErrorCode.CANCELED,
        statusMessage: '语音会话已取消'
      });
    } else {
      this.store.updateVoicePresentation(createIdleVoicePresentationState());
    }
  }

  private isActive(voiceSessionId: string, generation: number): boolean {
    return this.activeRequest?.voiceSessionId === voiceSessionId &&
      generation === this.store.getSessionGeneration();
  }

  private errorPresentation(
    request: VoiceRecognitionRequest,
    errorCode: VoiceErrorCode,
    statusMessage: string,
    finalText: string = ''
  ): VoicePresentationState {
    return {
      state: VoiceSessionState.ERROR,
      voiceSessionId: request.voiceSessionId,
      sessionGeneration: request.sessionGeneration,
      language: request.language,
      interimText: '',
      finalText,
      errorCode,
      statusMessage
    };
  }

  private clearTimeout(): void {
    if (this.timeoutId !== undefined) {
      clearTimeout(this.timeoutId);
      this.timeoutId = undefined;
    }
  }
}
