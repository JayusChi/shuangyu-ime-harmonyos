export const MAX_VOICE_RESULT_TEXT_LENGTH: number = 2048;

export enum VoiceProviderKind {
  FAKE = 'fake',
  PLATFORM = 'platform',
  LOCAL = 'local',
  CLOUD = 'cloud'
}

export enum VoiceSessionState {
  IDLE = 'idle',
  PREPARING = 'preparing',
  LISTENING = 'listening',
  FINALIZING = 'finalizing',
  RESULT_READY = 'result_ready',
  COMMITTING = 'committing',
  COMMITTED = 'committed',
  CANCELING = 'canceling',
  CANCELED = 'canceled',
  UNAVAILABLE = 'unavailable',
  ERROR = 'error'
}

export enum VoiceErrorCode {
  NONE = 'none',
  FEATURE_DISABLED = 'feature_disabled',
  UNAVAILABLE = 'unavailable',
  PERMISSION_REQUIRED = 'permission_required',
  SECURITY_MODE_RESTRICTED = 'security_mode_restricted',
  START_FAILED = 'start_failed',
  NO_RESULT = 'no_result',
  TIMEOUT = 'timeout',
  CANCELED = 'canceled',
  PROVIDER_ERROR = 'provider_error',
  PROTOCOL_ERROR = 'protocol_error',
  STALE_RESULT = 'stale_result',
  COMMIT_FAILED = 'commit_failed'
}

export interface VoiceRecognitionRequest {
  voiceSessionId: string;
  sessionGeneration: number;
  language: string;
  maxDurationMs: number;
}

export interface VoiceRecognitionResult {
  voiceSessionId: string;
  sessionGeneration: number;
  text: string;
  isFinal: boolean;
  providerKind: VoiceProviderKind;
  language: string;
  errorCode: VoiceErrorCode;
}

export interface VoicePresentationState {
  state: VoiceSessionState;
  voiceSessionId: string;
  sessionGeneration: number;
  providerKind?: VoiceProviderKind;
  language: string;
  interimText: string;
  finalText: string;
  errorCode: VoiceErrorCode;
  statusMessage: string;
}

export function createIdleVoicePresentationState(): VoicePresentationState {
  return {
    state: VoiceSessionState.IDLE,
    voiceSessionId: '',
    sessionGeneration: 0,
    language: 'zh-CN',
    interimText: '',
    finalText: '',
    errorCode: VoiceErrorCode.NONE,
    statusMessage: ''
  };
}

export function copyVoicePresentationState(state: VoicePresentationState): VoicePresentationState {
  return {
    state: state.state,
    voiceSessionId: state.voiceSessionId,
    sessionGeneration: state.sessionGeneration,
    providerKind: state.providerKind,
    language: state.language,
    interimText: state.interimText,
    finalText: state.finalText,
    errorCode: state.errorCode,
    statusMessage: state.statusMessage
  };
}
