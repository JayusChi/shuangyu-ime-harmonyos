export const MAX_AI_SOURCE_TEXT_LENGTH: number = 1024;
export const MAX_AI_SUGGESTION_TEXT_LENGTH: number = 512;
export const MAX_AI_SUGGESTIONS: number = 3;
export const MAX_AI_RESPONSE_BYTES: number = 64 * 1024;
export const AI_CLIENT_TIMEOUT_MS: number = 8000;
export const CURRENT_CLOUD_AI_CONSENT_VERSION: number = 1;

export enum AiAction {
  CONTINUE = 'continue',
  CONCISE = 'concise',
  POLITE = 'polite',
  FORMAL = 'formal',
  TRANSLATE = 'translate'
}

export enum AiProviderKind {
  FAKE = 'fake',
  LOCAL = 'local',
  CLOUD = 'cloud'
}

export enum AiProviderPolicy {
  LOCAL_ONLY = 'local_only',
  CLOUD_ALLOWED = 'cloud_allowed'
}

export enum AiSourceOwnership {
  CURRENT_COMPOSITION = 'current_composition',
  LAST_IME_COMMIT = 'last_ime_commit',
  EXPLICIT_SELECTION = 'explicit_selection'
}

export enum AiReplacePolicy {
  REPLACE_VERIFIED_SOURCE = 'replace_verified_source',
  INSERT_ONLY = 'insert_only'
}

export enum AiRequestState {
  IDLE = 'idle',
  ACTIONS = 'actions',
  LOADING = 'loading',
  READY = 'ready',
  APPLYING = 'applying',
  APPLIED = 'applied',
  CANCELED = 'canceled',
  UNAVAILABLE = 'unavailable',
  ERROR = 'error'
}

export enum AiErrorCode {
  NONE = 'none',
  FEATURE_DISABLED = 'feature_disabled',
  UNAVAILABLE = 'unavailable',
  NO_OWNED_SOURCE = 'no_owned_source',
  INVALID_REQUEST = 'invalid_request',
  TIMEOUT = 'timeout',
  CANCELED = 'canceled',
  EMPTY_RESULT = 'empty_result',
  NETWORK_ERROR = 'network_error',
  HTTP_ERROR = 'http_error',
  RESPONSE_TOO_LARGE = 'response_too_large',
  INVALID_RESPONSE = 'invalid_response',
  PROVIDER_ERROR = 'provider_error',
  PROTOCOL_ERROR = 'protocol_error',
  STALE_RESULT = 'stale_result',
  REPLACE_FAILED = 'replace_failed'
}

export interface AiRequest {
  requestId: string;
  sessionId: string;
  sessionGeneration: number;
  action: AiAction;
  sourceText: string;
  sourceOwnership: AiSourceOwnership;
  locale: string;
  providerPolicy: AiProviderPolicy;
  deadlineMs: number;
  maxSuggestions: number;
}

export interface AiSuggestion {
  suggestionId: string;
  requestId: string;
  text: string;
  label: string;
  providerKind: AiProviderKind;
  replacePolicy: AiReplacePolicy;
}

export interface AiProviderResult {
  success: boolean;
  requestId: string;
  providerKind: AiProviderKind;
  suggestions: AiSuggestion[];
  errorCode: AiErrorCode;
}

export interface AiPresentationState {
  state: AiRequestState;
  requestId: string;
  sessionGeneration: number;
  action?: AiAction;
  providerKind?: AiProviderKind;
  suggestions: AiSuggestion[];
  errorCode: AiErrorCode;
  statusMessage: string;
}

export const AI_ACTIONS: AiAction[] = [
  AiAction.CONTINUE,
  AiAction.CONCISE,
  AiAction.POLITE,
  AiAction.FORMAL,
  AiAction.TRANSLATE
];

export function aiActionLabel(action: AiAction): string {
  if (action === AiAction.CONTINUE) {
    return '续写';
  }
  if (action === AiAction.CONCISE) {
    return '精简';
  }
  if (action === AiAction.POLITE) {
    return '礼貌';
  }
  if (action === AiAction.FORMAL) {
    return '正式';
  }
  return '翻译';
}

export function createIdleAiPresentationState(): AiPresentationState {
  return {
    state: AiRequestState.IDLE,
    requestId: '',
    sessionGeneration: 0,
    suggestions: [],
    errorCode: AiErrorCode.NONE,
    statusMessage: ''
  };
}

export function copyAiSuggestion(suggestion: AiSuggestion): AiSuggestion {
  return {
    suggestionId: suggestion.suggestionId,
    requestId: suggestion.requestId,
    text: suggestion.text,
    label: suggestion.label,
    providerKind: suggestion.providerKind,
    replacePolicy: suggestion.replacePolicy
  };
}

export function copyAiPresentationState(state: AiPresentationState): AiPresentationState {
  return {
    state: state.state,
    requestId: state.requestId,
    sessionGeneration: state.sessionGeneration,
    action: state.action,
    providerKind: state.providerKind,
    suggestions: state.suggestions.map((item: AiSuggestion): AiSuggestion => copyAiSuggestion(item)),
    errorCode: state.errorCode,
    statusMessage: state.statusMessage
  };
}
