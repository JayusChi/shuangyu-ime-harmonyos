import {
  CloudAiRequestHeaderProvider,
  CloudAiRequestHeaders
} from './CloudAiRequestHeaders';

const MAX_ACCESS_TOKEN_LENGTH: number = 4096;
const MAX_ACCESS_TOKEN_LIFETIME_SECONDS: number = 300;
const MIN_REMAINING_LIFETIME_SECONDS: number = 15;

/** A token returned by the product identity service. It is kept in memory only. */
export interface CloudAiAccessToken {
  value: string;
  issuedAtEpochSeconds: number;
  expiresAtEpochSeconds: number;
  consentVersion: number;
}

/**
 * Product-owned identity boundary. Its production implementation must exchange
 * an authenticated app session/device assertion for a short-lived ai:suggest
 * token; it must never return a model-vendor credential.
 */
export interface CloudAiTokenBroker {
  requestAccessToken(requestId: string, consentVersion: number): Promise<CloudAiAccessToken>;
}

export class ShortLivedCloudAiHeaderProvider implements CloudAiRequestHeaderProvider {
  private readonly broker: CloudAiTokenBroker;
  private readonly consentVersion: number;
  private readonly nowEpochSeconds: () => number;
  private cachedToken?: CloudAiAccessToken;
  private pendingToken?: Promise<CloudAiAccessToken>;
  private generation: number = 0;

  constructor(
    broker: CloudAiTokenBroker,
    consentVersion: number,
    nowEpochSeconds: () => number = (): number => Math.floor(Date.now() / 1000)
  ) {
    if (!Number.isInteger(consentVersion) || consentVersion <= 0) {
      throw new Error('invalid_cloud_ai_consent_version');
    }
    this.broker = broker;
    this.consentVersion = consentVersion;
    this.nowEpochSeconds = nowEpochSeconds;
  }

  async getHeaders(requestId: string): Promise<CloudAiRequestHeaders> {
    const requestGeneration = this.generation;
    const now = this.nowEpochSeconds();
    if (validToken(this.cachedToken, this.consentVersion, now)) {
      return { authorization: `Bearer ${this.cachedToken?.value}` };
    }
    let pending = this.pendingToken;
    if (pending === undefined) {
      pending = this.broker.requestAccessToken(requestId, this.consentVersion);
      this.pendingToken = pending;
    }
    try {
      const token = await pending;
      const verifiedAt = this.nowEpochSeconds();
      if (this.generation !== requestGeneration) {
        throw new Error('cloud_ai_access_token_canceled');
      }
      if (!validToken(token, this.consentVersion, verifiedAt)) {
        throw new Error('invalid_cloud_ai_access_token');
      }
      this.cachedToken = copyToken(token);
      return { authorization: `Bearer ${token.value}` };
    } finally {
      if (this.pendingToken === pending) {
        this.pendingToken = undefined;
      }
    }
  }

  clear(): void {
    this.generation += 1;
    this.cachedToken = undefined;
    this.pendingToken = undefined;
  }
}

function validToken(
  token: CloudAiAccessToken | undefined,
  expectedConsentVersion: number,
  nowEpochSeconds: number
): boolean {
  if (token === undefined || token.consentVersion !== expectedConsentVersion ||
    !Number.isInteger(token.issuedAtEpochSeconds) || !Number.isInteger(token.expiresAtEpochSeconds) ||
    token.issuedAtEpochSeconds > nowEpochSeconds ||
    token.expiresAtEpochSeconds - token.issuedAtEpochSeconds > MAX_ACCESS_TOKEN_LIFETIME_SECONDS ||
    token.expiresAtEpochSeconds - nowEpochSeconds < MIN_REMAINING_LIFETIME_SECONDS ||
    token.value.length < 16 || token.value.length > MAX_ACCESS_TOKEN_LENGTH) {
    return false;
  }
  return /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(token.value);
}

function copyToken(token: CloudAiAccessToken): CloudAiAccessToken {
  return {
    value: token.value,
    issuedAtEpochSeconds: token.issuedAtEpochSeconds,
    expiresAtEpochSeconds: token.expiresAtEpochSeconds,
    consentVersion: token.consentVersion
  };
}
