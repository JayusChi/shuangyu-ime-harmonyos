import {
  VoiceErrorCode,
  VoiceProviderKind,
  VoiceRecognitionRequest,
  VoiceRecognitionResult
} from '../../main/ets/domain/voice/VoiceContracts';
import {
  SpeechRecognitionListener,
  SpeechRecognitionProvider
} from '../../main/ets/infrastructure/speech/SpeechRecognitionProvider';

export enum FakeSpeechScenario {
  SUCCESS = 'success',
  EMPTY = 'empty',
  ERROR = 'error',
  TIMEOUT = 'timeout',
  LATE_AFTER_CANCEL = 'late_after_cancel',
  OUT_OF_ORDER = 'out_of_order'
}

export interface FakeSpeechBehavior {
  scenario: FakeSpeechScenario;
  interimDelayMs: number;
  finalDelayMs: number;
}

const DEFAULT_FAKE_SPEECH_BEHAVIOR: FakeSpeechBehavior = {
  scenario: FakeSpeechScenario.SUCCESS,
  interimDelayMs: 80,
  finalDelayMs: 160
};

export class FakeSpeechProvider implements SpeechRecognitionProvider {
  private behaviorQueue: FakeSpeechBehavior[] = [];
  private defaultBehavior: FakeSpeechBehavior = DEFAULT_FAKE_SPEECH_BEHAVIOR;
  private canceledSessions: Set<string> = new Set<string>();

  setDefaultBehavior(behavior: FakeSpeechBehavior): void {
    this.defaultBehavior = this.copyBehavior(behavior);
  }

  enqueueBehavior(behavior: FakeSpeechBehavior): void {
    this.behaviorQueue.push(this.copyBehavior(behavior));
  }

  start(request: VoiceRecognitionRequest, listener: SpeechRecognitionListener): void {
    const behavior = this.behaviorQueue.shift() ?? this.defaultBehavior;
    this.canceledSessions.delete(request.voiceSessionId);
    if (behavior.scenario === FakeSpeechScenario.TIMEOUT) {
      return;
    }
    if (behavior.scenario === FakeSpeechScenario.ERROR) {
      setTimeout((): void => {
        if (this.shouldEmit(request.voiceSessionId, behavior.scenario)) {
          listener.onError(request.voiceSessionId, VoiceErrorCode.PROVIDER_ERROR);
        }
      }, behavior.interimDelayMs);
      return;
    }
    if (behavior.scenario === FakeSpeechScenario.OUT_OF_ORDER) {
      setTimeout((): void => listener.onResult(this.result(request, '这是最终结果', true)),
        behavior.interimDelayMs);
      setTimeout((): void => listener.onResult(this.result(request, '迟到的中间结果', false)),
        behavior.finalDelayMs);
      return;
    }
    setTimeout((): void => {
      if (this.shouldEmit(request.voiceSessionId, behavior.scenario)) {
        listener.onResult(this.result(request, '这是语音中间结果', false));
      }
    }, behavior.interimDelayMs);
    setTimeout((): void => {
      if (this.shouldEmit(request.voiceSessionId, behavior.scenario)) {
        const text = behavior.scenario === FakeSpeechScenario.EMPTY ? '' : '这是语音最终结果';
        listener.onResult(this.result(request, text, true));
      }
    }, behavior.finalDelayMs);
  }

  stop(_voiceSessionId: string): void {
  }

  cancel(voiceSessionId: string): void {
    this.canceledSessions.add(voiceSessionId);
  }

  private shouldEmit(voiceSessionId: string, scenario: FakeSpeechScenario): boolean {
    return !this.canceledSessions.has(voiceSessionId) || scenario === FakeSpeechScenario.LATE_AFTER_CANCEL;
  }

  private result(
    request: VoiceRecognitionRequest,
    text: string,
    isFinal: boolean
  ): VoiceRecognitionResult {
    return {
      voiceSessionId: request.voiceSessionId,
      sessionGeneration: request.sessionGeneration,
      text,
      isFinal,
      providerKind: VoiceProviderKind.FAKE,
      language: request.language,
      errorCode: VoiceErrorCode.NONE
    };
  }

  private copyBehavior(behavior: FakeSpeechBehavior): FakeSpeechBehavior {
    return {
      scenario: behavior.scenario,
      interimDelayMs: Math.max(0, behavior.interimDelayMs),
      finalDelayMs: Math.max(0, behavior.finalDelayMs)
    };
  }
}
