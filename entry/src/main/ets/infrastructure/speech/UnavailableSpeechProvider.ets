import {
  SpeechRecognitionListener,
  SpeechRecognitionProvider
} from './SpeechRecognitionProvider';
import { VoiceErrorCode, VoiceRecognitionRequest } from '../../domain/voice/VoiceContracts';

/** Production-safe placeholder until VOICE-1 is explicitly configured. */
export class UnavailableSpeechProvider implements SpeechRecognitionProvider {
  start(request: VoiceRecognitionRequest, listener: SpeechRecognitionListener): void {
    listener.onError(request.voiceSessionId, VoiceErrorCode.UNAVAILABLE);
  }

  stop(_voiceSessionId: string): void {
  }

  cancel(_voiceSessionId: string): void {
  }
}
