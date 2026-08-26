import { Logger } from '../common/logging/Logger';
import {
  AiAction,
  AiErrorCode,
  AiPresentationState,
  AiProviderKind,
  AiProviderResult,
  AiProviderPolicy,
  AiReplacePolicy,
  AiRequest,
  AiRequestState,
  AiSourceOwnership,
  AiSuggestion,
  AI_CLIENT_TIMEOUT_MS,
  createIdleAiPresentationState,
  MAX_AI_SOURCE_TEXT_LENGTH,
  MAX_AI_SUGGESTIONS,
  MAX_AI_SUGGESTION_TEXT_LENGTH
} from '../domain/ai/AiContracts';
import { ImeSettings } from '../domain/settings/ImeSettings';
import { resolveAssistAvailability } from '../domain/security/InputMethodCapabilityState';
import { AiProvider } from '../infrastructure/ai/AiProvider';
import { InputSessionStore } from '../state/InputSessionStore';
import { VerifiedTextReplacer } from './VerifiedTextReplacer';
import { AiAuditLogger } from './AiAuditLogger';

const LOGGER = new Logger('AiAssistController');

export class AiAssistController {
  private readonly store: InputSessionStore;
  private readonly settingsProvider: () => ImeSettings;
  private readonly provider: AiProvider;
  private readonly replacer: VerifiedTextReplacer;
  private readonly lastCommitProvider: () => string | null;
  private readonly sourceVerifier: (sourceText: string) => Promise<boolean>;
  private readonly sourceCursorProvider?: () => Promise<number | undefined>;
  private readonly replacementRecorder: (originalText: string, replacementText: string) => void;
  private readonly auditLogger: AiAuditLogger;
  private activeRequest?: AiRequest;
  private activeSourceCursorUtf16?: number;
  private activeRequestStartedAtMs: number = 0;
  private requestSequence: number = 0;
  private operationSequence: number = 0;
  private timeoutId?: number;
  private readonly requestTimeoutMs: number;

  constructor(
    store: InputSessionStore,
    settingsProvider: () => ImeSettings,
    provider: AiProvider,
    replacer: VerifiedTextReplacer,
    lastCommitProvider: () => string | null,
    replacementRecorder: (originalText: string, replacementText: string) => void,
    requestTimeoutMs: number = AI_CLIENT_TIMEOUT_MS,
    sourceVerifier: (sourceText: string) => Promise<boolean> = (_sourceText: string): Promise<boolean> =>
      Promise.resolve(true),
    sourceCursorProvider?: () => Promise<number | undefined>,
    auditLogger: AiAuditLogger = new AiAuditLogger()
  ) {
    this.store = store;
    this.settingsProvider = settingsProvider;
    this.provider = provider;
    this.replacer = replacer;
    this.lastCommitProvider = lastCommitProvider;
    this.sourceVerifier = sourceVerifier;
    this.sourceCursorProvider = sourceCursorProvider;
    this.replacementRecorder = replacementRecorder;
    this.auditLogger = auditLogger;
    this.requestTimeoutMs = Math.max(1, requestTimeoutMs);
  }

  async showActions(): Promise<void> {
    this.cancelActive(false);
    const operation = this.operationSequence;
    const generation = this.store.getSessionGeneration();
    const action = AiAction.POLITE;
    const unavailable = this.unavailablePresentation(action);
    if (unavailable !== undefined) {
      this.store.updateAiPresentation(unavailable);
      return;
    }
    const sourceText = this.lastCommitProvider();
    const sourceVerified = sourceText !== null && sourceText.length > 0 &&
      sourceText.length <= MAX_AI_SOURCE_TEXT_LENGTH && await this.sourceVerifier(sourceText);
    const sourceCursor = sourceVerified && this.sourceCursorProvider !== undefined
      ? await this.sourceCursorProvider() : undefined;
    const cursorVerified = this.sourceCursorProvider === undefined ||
      (sourceText !== null && sourceCursor !== undefined && Number.isInteger(sourceCursor) &&
        sourceCursor >= sourceText.length);
    if (operation !== this.operationSequence || generation !== this.store.getSessionGeneration()) {
      return;
    }
    if (!sourceText || !sourceVerified || !cursorVerified) {
      this.store.updateAiPresentation(this.noOwnedSourcePresentation(action));
      return;
    }
    this.store.updateAiPresentation({
      state: AiRequestState.ACTIONS,
      requestId: '',
      sessionGeneration: generation,
      suggestions: [],
      errorCode: AiErrorCode.NONE,
      statusMessage: '选择 AI 动作（云端处理）'
    });
  }

  async request(action: AiAction): Promise<void> {
    this.cancelActive(false);
    const operation = this.operationSequence;
    const generation = this.store.getSessionGeneration();
    const unavailable = this.unavailablePresentation(action);
    if (unavailable !== undefined) {
      this.store.updateAiPresentation(unavailable);
      return;
    }

    const sourceText = this.lastCommitProvider();
    const sourceVerified = sourceText !== null && sourceText.length > 0 &&
      sourceText.length <= MAX_AI_SOURCE_TEXT_LENGTH && await this.sourceVerifier(sourceText);
    const sourceCursor = sourceVerified && this.sourceCursorProvider !== undefined
      ? await this.sourceCursorProvider() : undefined;
    const cursorVerified = this.sourceCursorProvider === undefined ||
      (sourceText !== null && sourceCursor !== undefined && Number.isInteger(sourceCursor) &&
        sourceCursor >= sourceText.length);
    if (operation !== this.operationSequence || generation !== this.store.getSessionGeneration()) {
      return;
    }
    if (!sourceText || !sourceVerified || !cursorVerified) {
      this.store.updateAiPresentation(this.noOwnedSourcePresentation(action));
      return;
    }

    this.requestSequence += 1;
    const requestId = this.createRequestId(generation);
    const request: AiRequest = {
      requestId,
      sessionId: `ime-${generation}`,
      sessionGeneration: generation,
      action,
      sourceText,
      sourceOwnership: AiSourceOwnership.LAST_IME_COMMIT,
      locale: 'zh-CN',
      providerPolicy: AiProviderPolicy.CLOUD_ALLOWED,
      deadlineMs: Math.min(AI_CLIENT_TIMEOUT_MS, this.requestTimeoutMs),
      maxSuggestions: MAX_AI_SUGGESTIONS
    };
    this.activeRequest = request;
    this.activeSourceCursorUtf16 = sourceCursor;
    this.activeRequestStartedAtMs = Date.now();
    this.store.updateAiPresentation({
      state: AiRequestState.LOADING,
      requestId,
      sessionGeneration: generation,
      action,
      suggestions: [],
      errorCode: AiErrorCode.NONE,
      providerKind: AiProviderKind.CLOUD,
      statusMessage: '正在通过自有服务处理'
    });
    this.auditLogger.record(action, 'request', sourceText.length, 0, 0, AiErrorCode.NONE);
    this.timeoutId = setTimeout((): void => this.handleTimeout(requestId), request.deadlineMs);
    try {
      const result = await this.provider.request(request);
      await this.handleResult(request, result);
    } catch (_err) {
      this.handleProviderFailure(requestId);
    }
  }

  async acceptSuggestion(suggestionId: string): Promise<boolean> {
    const request = this.activeRequest;
    const presentation = this.store.getSnapshot().aiPresentation;
    if (!request || presentation.state !== AiRequestState.READY ||
      request.requestId !== presentation.requestId ||
      request.sessionGeneration !== this.store.getSessionGeneration()) {
      return false;
    }
    if (this.unavailablePresentation(request.action) !== undefined ||
      !(await this.sourceStillOwned(request.sourceText))) {
      this.cancelActive(false);
      return false;
    }
    const suggestion = presentation.suggestions.find(
      (item: AiSuggestion): boolean => item.suggestionId === suggestionId
    );
    if (!suggestion) {
      return false;
    }
    this.store.updateAiPresentation({
      state: AiRequestState.APPLYING,
      requestId: request.requestId,
      sessionGeneration: request.sessionGeneration,
      action: request.action,
      providerKind: suggestion.providerKind,
      suggestions: presentation.suggestions,
      errorCode: AiErrorCode.NONE,
      statusMessage: '正在核验并替换'
    });
    const result = await this.replacer.replace({
      sessionGeneration: request.sessionGeneration,
      sourceText: request.sourceText,
      replacementText: suggestion.text,
      sourceOwnership: request.sourceOwnership,
      stillOwned: (): boolean => this.activeRequest?.requestId === request.requestId,
      expectedCursorUtf16: this.activeSourceCursorUtf16
    });
    if (!result.success || request.requestId !== this.activeRequest?.requestId) {
      if (request.requestId === this.activeRequest?.requestId) {
        this.store.updateAiPresentation({
          state: AiRequestState.ERROR,
          requestId: request.requestId,
          sessionGeneration: request.sessionGeneration,
          action: request.action,
          providerKind: suggestion.providerKind,
          suggestions: [],
          errorCode: AiErrorCode.REPLACE_FAILED,
          statusMessage: '原文已变化，未执行替换'
        });
      }
      return false;
    }
    this.replacementRecorder(request.sourceText, suggestion.text);
    this.activeRequest = undefined;
    this.activeSourceCursorUtf16 = undefined;
    this.clearTimeout();
    this.store.updateAiPresentation({
      state: AiRequestState.APPLIED,
      requestId: request.requestId,
      sessionGeneration: request.sessionGeneration,
      action: request.action,
      providerKind: suggestion.providerKind,
      suggestions: [],
      errorCode: AiErrorCode.NONE,
      statusMessage: '已安全替换，可撤销'
    });
    LOGGER.info(`AI suggestion applied: replacementLength=${suggestion.text.length}`);
    this.auditLogger.record(
      request.action,
      'applied',
      request.sourceText.length,
      Date.now() - this.activeRequestStartedAtMs,
      presentation.suggestions.length,
      AiErrorCode.NONE,
      suggestion.providerKind
    );
    return true;
  }

  cancel(showCanceled: boolean = true): void {
    this.cancelActive(showCanceled);
  }

  invalidateForInput(): void {
    this.cancelActive(false);
  }

  private async handleResult(request: AiRequest, result: AiProviderResult): Promise<void> {
    if (!this.isActive(request.requestId, request.sessionGeneration)) {
      return;
    }
    if (this.unavailablePresentation(request.action) !== undefined ||
      !(await this.sourceStillOwned(request.sourceText)) ||
      !this.isActive(request.requestId, request.sessionGeneration)) {
      this.cancelActive(false);
      return;
    }
    this.clearTimeout();
    if (!result.success) {
      if (result.errorCode === AiErrorCode.CANCELED) {
        return;
      }
      this.activeRequest = undefined;
      this.activeSourceCursorUtf16 = undefined;
      this.store.updateAiPresentation(this.errorPresentation(
        request,
        result.errorCode,
        this.statusForError(result.errorCode)
      ));
      this.auditLogger.record(
        request.action,
        'result',
        request.sourceText.length,
        Date.now() - this.activeRequestStartedAtMs,
        0,
        result.errorCode
      );
      return;
    }
    const providerAllowed = request.providerPolicy === AiProviderPolicy.CLOUD_ALLOWED &&
      result.providerKind === AiProviderKind.CLOUD;
    if (result.errorCode !== AiErrorCode.NONE || result.requestId !== request.requestId ||
      !providerAllowed ||
      !this.validSuggestions(result.suggestions, request.requestId, result.providerKind)) {
      this.activeRequest = undefined;
      this.activeSourceCursorUtf16 = undefined;
      this.store.updateAiPresentation(this.errorPresentation(
        request,
        result.suggestions.length === 0 ? AiErrorCode.EMPTY_RESULT : AiErrorCode.PROTOCOL_ERROR,
        result.suggestions.length === 0 ? 'AI 未返回建议' : 'AI 协议校验失败'
      ));
      return;
    }
    this.store.updateAiPresentation({
      state: AiRequestState.READY,
      requestId: request.requestId,
      sessionGeneration: request.sessionGeneration,
      action: request.action,
      providerKind: result.providerKind,
      suggestions: result.suggestions.slice(0, MAX_AI_SUGGESTIONS),
      errorCode: AiErrorCode.NONE,
      statusMessage: 'AI 候选'
    });
    this.auditLogger.record(
      request.action,
      'ready',
      request.sourceText.length,
      Date.now() - this.activeRequestStartedAtMs,
      result.suggestions.length,
      AiErrorCode.NONE
    );
  }

  private handleTimeout(requestId: string): void {
    const request = this.activeRequest;
    if (!request || request.requestId !== requestId) {
      return;
    }
    if (!this.isActive(request.requestId, request.sessionGeneration)) {
      this.provider.cancel(requestId);
      this.activeRequest = undefined;
      this.activeSourceCursorUtf16 = undefined;
      this.clearTimeout();
      return;
    }
    this.provider.cancel(requestId);
    this.activeRequest = undefined;
    this.activeSourceCursorUtf16 = undefined;
    this.clearTimeout();
    this.store.updateAiPresentation(this.errorPresentation(request, AiErrorCode.TIMEOUT, 'AI 请求已超时'));
    this.auditLogger.record(
      request.action,
      'timeout',
      request.sourceText.length,
      Date.now() - this.activeRequestStartedAtMs,
      0,
      AiErrorCode.TIMEOUT
    );
  }

  private handleProviderFailure(requestId: string): void {
    const request = this.activeRequest;
    if (!request || request.requestId !== requestId) {
      return;
    }
    if (!this.isActive(request.requestId, request.sessionGeneration)) {
      this.activeRequest = undefined;
      this.activeSourceCursorUtf16 = undefined;
      this.clearTimeout();
      return;
    }
    this.activeRequest = undefined;
    this.activeSourceCursorUtf16 = undefined;
    this.clearTimeout();
    this.store.updateAiPresentation(this.errorPresentation(
      request,
      AiErrorCode.PROVIDER_ERROR,
      'AI Provider 调用失败'
    ));
  }

  private cancelActive(showCanceled: boolean): void {
    this.operationSequence += 1;
    const request = this.activeRequest;
    if (request === undefined && this.activeSourceCursorUtf16 === undefined &&
      this.timeoutId === undefined && this.store.isAiPresentationIdle()) {
      return;
    }
    if (request) {
      this.provider.cancel(request.requestId);
    }
    this.activeRequest = undefined;
    this.activeSourceCursorUtf16 = undefined;
    this.clearTimeout();
    if (showCanceled && request) {
      this.store.updateAiPresentation({
        state: AiRequestState.CANCELED,
        requestId: request.requestId,
        sessionGeneration: request.sessionGeneration,
        action: request.action,
        suggestions: [],
        errorCode: AiErrorCode.CANCELED,
        statusMessage: 'AI 请求已取消'
      });
    } else {
      this.store.updateAiPresentation(createIdleAiPresentationState());
    }
  }

  private isActive(requestId: string, generation: number): boolean {
    return this.activeRequest?.requestId === requestId &&
      generation === this.store.getSessionGeneration();
  }

  private async sourceStillOwned(sourceText: string): Promise<boolean> {
    if (!(await this.sourceVerifier(sourceText))) {
      return false;
    }
    if (this.sourceCursorProvider === undefined) {
      return true;
    }
    const cursor = await this.sourceCursorProvider();
    return cursor !== undefined && cursor === this.activeSourceCursorUtf16;
  }

  private validSuggestions(
    suggestions: AiSuggestion[],
    requestId: string,
    providerKind: AiProviderKind
  ): boolean {
    if (suggestions.length <= 0 || suggestions.length > MAX_AI_SUGGESTIONS) {
      return false;
    }
    const ids: Set<string> = new Set<string>();
    return suggestions.every((suggestion: AiSuggestion): boolean => {
      if (suggestion.requestId !== requestId || suggestion.suggestionId.length <= 0 ||
        ids.has(suggestion.suggestionId) || suggestion.text.length <= 0 ||
        suggestion.text.length > MAX_AI_SUGGESTION_TEXT_LENGTH || suggestion.label.length > 32 ||
        suggestion.providerKind !== providerKind ||
        suggestion.replacePolicy !== AiReplacePolicy.REPLACE_VERIFIED_SOURCE) {
        return false;
      }
      ids.add(suggestion.suggestionId);
      return true;
    });
  }

  private errorPresentation(
    request: AiRequest,
    errorCode: AiErrorCode,
    statusMessage: string
  ): AiPresentationState {
    return {
      state: AiRequestState.ERROR,
      requestId: request.requestId,
      sessionGeneration: request.sessionGeneration,
      action: request.action,
      suggestions: [],
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

  private unavailablePresentation(action: AiAction): AiPresentationState | undefined {
    const snapshot = this.store.getSnapshot();
    const availability = resolveAssistAvailability(
      snapshot.capabilityState,
      snapshot.editorContext,
      this.settingsProvider(),
      snapshot.sessionActive,
      snapshot.editorConnected
    ).ai;
    if (availability.available) {
      return undefined;
    }
    return {
      state: AiRequestState.UNAVAILABLE,
      requestId: '',
      sessionGeneration: this.store.getSessionGeneration(),
      action,
      suggestions: [],
      errorCode: AiErrorCode.UNAVAILABLE,
      statusMessage: availability.message
    };
  }

  private noOwnedSourcePresentation(action: AiAction): AiPresentationState {
    return {
      state: AiRequestState.UNAVAILABLE,
      requestId: '',
      sessionGeneration: this.store.getSessionGeneration(),
      action,
      suggestions: [],
      errorCode: AiErrorCode.NO_OWNED_SOURCE,
      statusMessage: '没有仍由本输入法拥有的最近上屏文本'
    };
  }

  private statusForError(errorCode: AiErrorCode): string {
    if (errorCode === AiErrorCode.NETWORK_ERROR) {
      return '网络不可用';
    }
    if (errorCode === AiErrorCode.TIMEOUT) {
      return 'AI 请求已超时';
    }
    if (errorCode === AiErrorCode.EMPTY_RESULT) {
      return 'AI 未返回建议';
    }
    return 'AI 服务暂不可用';
  }

  private createRequestId(generation: number): string {
    const random = Math.floor(Math.random() * 0x100000000).toString(36);
    return `ai-${generation}-${Date.now().toString(36)}-${this.requestSequence.toString(36)}-${random}`;
  }
}
