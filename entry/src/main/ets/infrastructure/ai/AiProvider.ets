import { AiProviderResult, AiRequest } from '../../domain/ai/AiContracts';

export interface AiProvider {
  request(request: AiRequest): Promise<AiProviderResult>;
  cancel(requestId: string): void;
}
