import {
  VoiceErrorCode,
  VoiceRecognitionRequest,
  VoiceRecognitionResult
} from '../../domain/voice/VoiceContracts';

export interface SpeechRecognitionListener {
  onResult(result: VoiceRecognitionResult): void;
  onError(voiceSessionId: string, errorCode: VoiceErrorCode): void;
}

export interface SpeechRecognitionProvider {
  start(request: VoiceRecognitionRequest, listener: SpeechRecognitionListener): void;
  stop(voiceSessionId: string): void;
  cancel(voiceSessionId: string): void;
}
