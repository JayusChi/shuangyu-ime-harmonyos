import {
  AiSourceOwnership,
  MAX_AI_SOURCE_TEXT_LENGTH,
  MAX_AI_SUGGESTION_TEXT_LENGTH
} from '../domain/ai/AiContracts';
import { ImeInputService } from './ImeInputService';

export enum VerifiedReplaceErrorCode {
  NONE = 'none',
  INVALID_ARGUMENT = 'invalid_argument',
  UNSUPPORTED_OWNERSHIP = 'unsupported_ownership',
  STALE_SESSION = 'stale_session',
  SOURCE_MISMATCH = 'source_mismatch'
}

export interface VerifiedReplaceRequest {
  sessionGeneration: number;
  sourceText: string;
  replacementText: string;
  sourceOwnership: AiSourceOwnership;
  stillOwned?: () => boolean;
  expectedCursorUtf16?: number;
}

export interface VerifiedReplaceResult {
  success: boolean;
  errorCode: VerifiedReplaceErrorCode;
}

export class VerifiedTextReplacer {
  private readonly service: ImeInputService;
  private readonly generationIsCurrent: (generation: number) => boolean;

  constructor(
    service: ImeInputService,
    generationIsCurrent: (generation: number) => boolean
  ) {
    this.service = service;
    this.generationIsCurrent = generationIsCurrent;
  }

  async replace(request: VerifiedReplaceRequest): Promise<VerifiedReplaceResult> {
    if (request.sourceText.length <= 0 || request.sourceText.length > MAX_AI_SOURCE_TEXT_LENGTH ||
      request.replacementText.length <= 0 || request.replacementText.length > MAX_AI_SUGGESTION_TEXT_LENGTH) {
      return { success: false, errorCode: VerifiedReplaceErrorCode.INVALID_ARGUMENT };
    }
    if (request.sourceOwnership !== AiSourceOwnership.LAST_IME_COMMIT &&
      request.sourceOwnership !== AiSourceOwnership.CURRENT_COMPOSITION) {
      return { success: false, errorCode: VerifiedReplaceErrorCode.UNSUPPORTED_OWNERSHIP };
    }
    if (!this.generationIsCurrent(request.sessionGeneration) || request.stillOwned?.() === false) {
      return { success: false, errorCode: VerifiedReplaceErrorCode.STALE_SESSION };
    }
    if (request.expectedCursorUtf16 !== undefined &&
      (!Number.isInteger(request.expectedCursorUtf16) || request.expectedCursorUtf16 < request.sourceText.length)) {
      return { success: false, errorCode: VerifiedReplaceErrorCode.INVALID_ARGUMENT };
    }
    if (!this.service.replaceTextBeforeCursorIfMatches) {
      return { success: false, errorCode: VerifiedReplaceErrorCode.SOURCE_MISMATCH };
    }
    const replaced = await this.service.replaceTextBeforeCursorIfMatches(
      request.sourceText,
      request.replacementText,
      (): boolean => this.generationIsCurrent(request.sessionGeneration) && request.stillOwned?.() !== false,
      request.expectedCursorUtf16
    );
    if (!this.generationIsCurrent(request.sessionGeneration) || request.stillOwned?.() === false) {
      return { success: false, errorCode: VerifiedReplaceErrorCode.STALE_SESSION };
    }
    return replaced
      ? { success: true, errorCode: VerifiedReplaceErrorCode.NONE }
      : { success: false, errorCode: VerifiedReplaceErrorCode.SOURCE_MISMATCH };
  }
}
