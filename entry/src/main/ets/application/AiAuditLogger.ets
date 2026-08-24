import { Logger } from '../common/logging/Logger';
import { AiAction, AiErrorCode, AiProviderKind } from '../domain/ai/AiContracts';

const LOGGER = new Logger('AiAudit');

export class AiAuditLogger {
  record(
    action: AiAction,
    stage: string,
    sourceLength: number,
    elapsedMs: number,
    candidateCount: number,
    errorCode: AiErrorCode,
    providerKind: AiProviderKind = AiProviderKind.CLOUD
  ): void {
    LOGGER.info(
      `action=${action}, stage=${stage}, provider=${providerKind}, ` +
        `lengthBucket=${lengthBucket(sourceLength)}, elapsedBucket=${elapsedBucket(elapsedMs)}, ` +
        `candidateCount=${Math.max(0, candidateCount)}, errorCode=${errorCode}`
    );
  }
}

function lengthBucket(length: number): string {
  if (length <= 16) {
    return '1_16';
  }
  if (length <= 64) {
    return '17_64';
  }
  if (length <= 256) {
    return '65_256';
  }
  return '257_1024';
}

function elapsedBucket(elapsedMs: number): string {
  if (elapsedMs < 500) {
    return 'lt_500';
  }
  if (elapsedMs < 1500) {
    return '500_1499';
  }
  if (elapsedMs < 4000) {
    return '1500_3999';
  }
  return 'ge_4000';
}
