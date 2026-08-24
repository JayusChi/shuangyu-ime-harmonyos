import {
  AiAction,
  AiErrorCode,
  AiProviderKind,
  AiProviderResult,
  AiReplacePolicy,
  AiRequest,
  AiSuggestion,
  MAX_AI_SUGGESTION_TEXT_LENGTH
} from '../../main/ets/domain/ai/AiContracts';
import { AiProvider } from '../../main/ets/infrastructure/ai/AiProvider';

export enum FakeAiScenario {
  SUCCESS = 'success',
  EMPTY = 'empty',
  ERROR = 'error',
  TIMEOUT = 'timeout',
  LATE_SUCCESS = 'late_success'
}

export interface FakeAiBehavior {
  scenario: FakeAiScenario;
  delayMs: number;
}

interface PendingAiRequest {
  scenario: FakeAiScenario;
  resolve: (result: AiProviderResult) => void;
}

const DEFAULT_FAKE_AI_BEHAVIOR: FakeAiBehavior = {
  scenario: FakeAiScenario.SUCCESS,
  delayMs: 80
};

export class FakeAiProvider implements AiProvider {
  private behaviorQueue: FakeAiBehavior[] = [];
  private defaultBehavior: FakeAiBehavior = DEFAULT_FAKE_AI_BEHAVIOR;
  private canceledRequestIds: Set<string> = new Set<string>();
  private pendingRequests: Map<string, PendingAiRequest> = new Map<string, PendingAiRequest>();

  setDefaultBehavior(behavior: FakeAiBehavior): void {
    this.defaultBehavior = { scenario: behavior.scenario, delayMs: Math.max(0, behavior.delayMs) };
  }

  enqueueBehavior(behavior: FakeAiBehavior): void {
    this.behaviorQueue.push({ scenario: behavior.scenario, delayMs: Math.max(0, behavior.delayMs) });
  }

  request(request: AiRequest): Promise<AiProviderResult> {
    const behavior = this.behaviorQueue.shift() ?? this.defaultBehavior;
    this.canceledRequestIds.delete(request.requestId);
    return new Promise<AiProviderResult>((resolve: (result: AiProviderResult) => void): void => {
      this.pendingRequests.set(request.requestId, { scenario: behavior.scenario, resolve });
      if (behavior.scenario === FakeAiScenario.TIMEOUT) {
        return;
      }
      setTimeout((): void => {
        this.pendingRequests.delete(request.requestId);
        if (this.canceledRequestIds.has(request.requestId) &&
          behavior.scenario !== FakeAiScenario.LATE_SUCCESS) {
          resolve(this.errorResult(request.requestId, AiErrorCode.CANCELED));
          return;
        }
        if (behavior.scenario === FakeAiScenario.ERROR) {
          resolve(this.errorResult(request.requestId, AiErrorCode.PROVIDER_ERROR));
          return;
        }
        if (behavior.scenario === FakeAiScenario.EMPTY) {
          resolve({
            success: true,
            requestId: request.requestId,
            providerKind: AiProviderKind.CLOUD,
            suggestions: [],
            errorCode: AiErrorCode.NONE
          });
          return;
        }
        resolve({
          success: true,
          requestId: request.requestId,
          providerKind: AiProviderKind.CLOUD,
          suggestions: this.buildSuggestions(request),
          errorCode: AiErrorCode.NONE
        });
      }, behavior.delayMs);
    });
  }

  cancel(requestId: string): void {
    this.canceledRequestIds.add(requestId);
    const pending = this.pendingRequests.get(requestId);
    if (pending && pending.scenario === FakeAiScenario.TIMEOUT) {
      this.pendingRequests.delete(requestId);
      pending.resolve(this.errorResult(requestId, AiErrorCode.CANCELED));
    }
  }

  private errorResult(requestId: string, errorCode: AiErrorCode): AiProviderResult {
    return {
      success: false,
      requestId,
      providerKind: AiProviderKind.CLOUD,
      suggestions: [],
      errorCode
    };
  }

  private buildSuggestions(request: AiRequest): AiSuggestion[] {
    const variants = this.variantsForAction(request.action, request.sourceText);
    return variants.map((text: string, index: number): AiSuggestion => ({
      suggestionId: `${request.requestId}-s${index + 1}`,
      requestId: request.requestId,
      text: text.slice(0, MAX_AI_SUGGESTION_TEXT_LENGTH),
      label: this.labelForAction(request.action, index),
      providerKind: AiProviderKind.CLOUD,
      replacePolicy: AiReplacePolicy.REPLACE_VERIFIED_SOURCE
    }));
  }

  private variantsForAction(action: AiAction, sourceText: string): string[] {
    if (action === AiAction.CONCISE) {
      const concise = sourceText.length > 12 ? `${sourceText.slice(0, 12)}…` : sourceText;
      return [concise, `简要说：${concise}`, `概括为：${concise}`];
    }
    if (action === AiAction.POLITE) {
      return [`您好，${sourceText}`, `${sourceText}，谢谢。`, `麻烦您${sourceText}`];
    }
    if (action === AiAction.FORMAL) {
      return [`现就此说明：${sourceText}`, `正式表述：${sourceText}`, `经确认，${sourceText}`];
    }
    if (action === AiAction.TRANSLATE) {
      return [`[Translation] ${sourceText}`, `[EN] ${sourceText}`, `[ZH/EN] ${sourceText}`];
    }
    return [`${sourceText}（续写一）`, `${sourceText}（续写二）`, `${sourceText}（续写三）`];
  }

  private labelForAction(action: AiAction, index: number): string {
    return `${action}-${index + 1}`;
  }
}
