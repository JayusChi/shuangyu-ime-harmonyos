import {
  AiErrorCode,
  AiProviderKind,
  AiProviderResult,
  AiRequest
} from '../../domain/ai/AiContracts';
import { AiProvider } from './AiProvider';

/** Production-safe default used until an approved proxy configuration is injected. */
export class UnavailableAiProvider implements AiProvider {
  request(request: AiRequest): Promise<AiProviderResult> {
    const result: AiProviderResult = {
      success: false,
      requestId: request.requestId,
      providerKind: AiProviderKind.CLOUD,
      suggestions: [],
      errorCode: AiErrorCode.UNAVAILABLE
    };
    return Promise.resolve(result);
  }

  cancel(_requestId: string): void {
  }
}
