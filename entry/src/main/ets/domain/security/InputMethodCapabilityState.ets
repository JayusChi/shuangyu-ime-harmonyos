import { EditorContext, EditorKind } from '../editor/EditorContext';
import { ImeSettings } from '../settings/ImeSettings';
import { CURRENT_CLOUD_AI_CONSENT_VERSION } from '../ai/AiContracts';

export enum InputMethodSecurityMode {
  UNKNOWN = 'unknown',
  BASIC = 'basic',
  FULL = 'full'
}

export enum MicrophonePermissionState {
  UNKNOWN = 'unknown',
  NOT_REQUESTED = 'not_requested',
  GRANTED = 'granted',
  DENIED = 'denied'
}

export enum AssistUnavailableReason {
  NONE = 'none',
  SESSION_INACTIVE = 'session_inactive',
  FEATURE_DISABLED = 'feature_disabled',
  SECURITY_MODE_UNKNOWN = 'security_mode_unknown',
  BASIC_SECURITY_MODE = 'basic_security_mode',
  SENSITIVE_EDITOR = 'sensitive_editor',
  UNSUPPORTED_EDITOR = 'unsupported_editor',
  UNKNOWN_EDITOR = 'unknown_editor',
  PROVIDER_UNAVAILABLE = 'provider_unavailable',
  CLOUD_AI_DISABLED = 'cloud_ai_disabled',
  CONSENT_REQUIRED = 'consent_required'
}

export interface InputMethodCapabilityState {
  securityMode: InputMethodSecurityMode;
  microphonePermission: MicrophonePermissionState;
  localAiProviderAvailable: boolean;
  cloudAiProviderAvailable: boolean;
  speechProviderAvailable: boolean;
  detectedAtMs: number;
}

export interface FeatureAvailability {
  available: boolean;
  reason: AssistUnavailableReason;
  message: string;
}

export interface AssistAvailability {
  ai: FeatureAvailability;
  voice: FeatureAvailability;
}

export function createUnknownInputMethodCapabilityState(): InputMethodCapabilityState {
  return {
    securityMode: InputMethodSecurityMode.UNKNOWN,
    microphonePermission: MicrophonePermissionState.NOT_REQUESTED,
    localAiProviderAvailable: false,
    cloudAiProviderAvailable: false,
    speechProviderAvailable: false,
    detectedAtMs: 0
  };
}

export function copyInputMethodCapabilityState(state: InputMethodCapabilityState): InputMethodCapabilityState {
  return {
    securityMode: state.securityMode,
    microphonePermission: state.microphonePermission,
    localAiProviderAvailable: state.localAiProviderAvailable,
    cloudAiProviderAvailable: state.cloudAiProviderAvailable,
    speechProviderAvailable: state.speechProviderAvailable,
    detectedAtMs: state.detectedAtMs
  };
}

function denied(reason: AssistUnavailableReason, message: string): FeatureAvailability {
  return { available: false, reason, message };
}

function allowed(): FeatureAvailability {
  return { available: true, reason: AssistUnavailableReason.NONE, message: '' };
}

function editorAllowsAssist(editor: EditorContext): FeatureAvailability {
  if (editor.kind === EditorKind.PASSWORD || editor.isPassword) {
    return denied(AssistUnavailableReason.SENSITIVE_EDITOR, '敏感输入框中不可用');
  }
  if (editor.kind === EditorKind.UNKNOWN) {
    return denied(AssistUnavailableReason.UNKNOWN_EDITOR, '无法确认输入框安全性');
  }
  if (editor.kind === EditorKind.NUMBER || editor.kind === EditorKind.PHONE ||
    editor.kind === EditorKind.EMAIL || editor.kind === EditorKind.URL) {
    return denied(AssistUnavailableReason.UNSUPPORTED_EDITOR, '当前输入框类型不支持');
  }
  return allowed();
}

export function resolveAssistAvailability(
  capability: InputMethodCapabilityState,
  editor: EditorContext,
  settings: ImeSettings,
  sessionActive: boolean,
  editorConnected: boolean
): AssistAvailability {
  if (!sessionActive || !editorConnected) {
    const inactive = denied(AssistUnavailableReason.SESSION_INACTIVE, '需要活动输入会话');
    return { ai: inactive, voice: inactive };
  }

  const editorAvailability = editorAllowsAssist(editor);
  if (!editorAvailability.available) {
    return { ai: editorAvailability, voice: editorAvailability };
  }

  let ai = allowed();
  if (!settings.aiEnabled) {
    ai = denied(AssistUnavailableReason.FEATURE_DISABLED, 'AI 辅助尚未开启');
  } else if (capability.securityMode === InputMethodSecurityMode.UNKNOWN) {
    ai = denied(AssistUnavailableReason.SECURITY_MODE_UNKNOWN, '输入法安全模式未知');
  } else if (capability.securityMode !== InputMethodSecurityMode.FULL) {
    ai = denied(AssistUnavailableReason.BASIC_SECURITY_MODE, '云端 AI 需要完整体验模式');
  } else if (!settings.cloudAiEnabled) {
    ai = denied(AssistUnavailableReason.CLOUD_AI_DISABLED, '云端 AI 尚未开启');
  } else if (settings.cloudAiConsentVersion !== CURRENT_CLOUD_AI_CONSENT_VERSION) {
    ai = denied(AssistUnavailableReason.CONSENT_REQUIRED, '需要确认当前版本的云端处理说明');
  } else if (!capability.cloudAiProviderAvailable) {
    ai = denied(AssistUnavailableReason.PROVIDER_UNAVAILABLE, '云端 AI Provider 不可用');
  }

  let voice = allowed();
  if (!settings.voiceInputEnabled) {
    voice = denied(AssistUnavailableReason.FEATURE_DISABLED, '语音输入尚未开启');
  } else if (capability.securityMode === InputMethodSecurityMode.UNKNOWN) {
    voice = denied(AssistUnavailableReason.SECURITY_MODE_UNKNOWN, '输入法安全模式未知');
  } else if (capability.securityMode === InputMethodSecurityMode.BASIC) {
    voice = denied(AssistUnavailableReason.BASIC_SECURITY_MODE, '基础安全模式不允许语音输入');
  } else if (!capability.speechProviderAvailable) {
    voice = denied(AssistUnavailableReason.PROVIDER_UNAVAILABLE, '语音 Provider 不可用');
  }

  return { ai, voice };
}
