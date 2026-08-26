const ACTIONS = new Set(['continue', 'concise', 'polite', 'formal', 'translate', 'unknown']);

export class AiProxyAuditLogger {
  constructor(write = (record) => console.info(JSON.stringify(record))) {
    this.write = write;
  }

  record({ action, stage, sourceLength, elapsedMs, candidateCount, errorCode }) {
    this.write(Object.freeze({
      event: 'ai_proxy',
      action: ACTIONS.has(action) ? action : 'unknown',
      stage: fixedStage(stage),
      lengthBucket: lengthBucket(sourceLength),
      elapsedBucket: elapsedBucket(elapsedMs),
      candidateCount: Math.max(0, Math.min(3, Number(candidateCount) || 0)),
      errorCode: typeof errorCode === 'string' && /^[a-z_]{2,40}$/.test(errorCode)
        ? errorCode : 'internal_error'
    }));
  }
}

function fixedStage(stage) {
  return ['accepted', 'completed', 'rejected', 'provider'].includes(stage) ? stage : 'rejected';
}

function lengthBucket(length) {
  if (length <= 0) return '0';
  if (length <= 16) return '1_16';
  if (length <= 64) return '17_64';
  if (length <= 256) return '65_256';
  return '257_1024';
}

function elapsedBucket(elapsedMs) {
  if (elapsedMs < 500) return 'lt_500';
  if (elapsedMs < 1_500) return '500_1499';
  if (elapsedMs < 4_000) return '1500_3999';
  return 'ge_4000';
}
