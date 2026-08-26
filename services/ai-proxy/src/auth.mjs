import { createPublicKey, verify as verifySignature } from 'node:crypto';
import { readFileSync, statSync } from 'node:fs';
import { ProxyError, ProxyErrorCode } from './errors.mjs';

const TOKEN_PATTERN = /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/;
const IDENTIFIER_PATTERN = /^[A-Za-z0-9._:@/-]{1,128}$/;

export class FileJwksSource {
  constructor(path) {
    this.path = path;
    this.lastModifiedMs = -1;
    this.keys = new Map();
  }

  get(kid) {
    this.reloadIfChanged();
    return this.keys.get(kid);
  }

  reloadIfChanged() {
    const modifiedMs = statSync(this.path).mtimeMs;
    if (modifiedMs === this.lastModifiedMs) {
      return;
    }
    const parsed = JSON.parse(readFileSync(this.path, { encoding: 'utf8' }));
    if (!parsed || !Array.isArray(parsed.keys) || parsed.keys.length < 1 || parsed.keys.length > 8) {
      throw new Error('jwks_invalid');
    }
    const next = new Map();
    for (const jwk of parsed.keys) {
      if (!jwk || jwk.kty !== 'OKP' || jwk.crv !== 'Ed25519' || jwk.alg !== 'EdDSA' ||
          jwk.use !== 'sig' || typeof jwk.kid !== 'string' || !IDENTIFIER_PATTERN.test(jwk.kid) ||
          typeof jwk.x !== 'string' || jwk.x.length < 40 || jwk.d !== undefined || next.has(jwk.kid)) {
        throw new Error('jwks_invalid');
      }
      next.set(jwk.kid, createPublicKey({ key: jwk, format: 'jwk' }));
    }
    this.keys = next;
    this.lastModifiedMs = modifiedMs;
  }
}

export class EdDsaAccessTokenVerifier {
  constructor({ keySource, issuer, audience, consentVersion, maxTokenLifetimeSeconds, clockSkewSeconds }) {
    this.keySource = keySource;
    this.issuer = issuer;
    this.audience = audience;
    this.consentVersion = consentVersion;
    this.maxTokenLifetimeSeconds = maxTokenLifetimeSeconds;
    this.clockSkewSeconds = clockSkewSeconds;
  }

  verify(authorization, nowMs = Date.now()) {
    try {
      if (typeof authorization !== 'string' || !authorization.startsWith('Bearer ')) {
        throw new Error('auth_invalid');
      }
      const token = authorization.slice('Bearer '.length);
      if (token.length > 4_096 || !TOKEN_PATTERN.test(token)) {
        throw new Error('auth_invalid');
      }
      const [encodedHeader, encodedPayload, encodedSignature] = token.split('.');
      const header = decodeJson(encodedHeader);
      const claims = decodeJson(encodedPayload);
      if (!header || header.alg !== 'EdDSA' || header.typ !== 'at+jwt' ||
          typeof header.kid !== 'string' || !IDENTIFIER_PATTERN.test(header.kid)) {
        throw new Error('auth_invalid');
      }
      const publicKey = this.keySource.get(header.kid);
      if (!publicKey || !verifySignature(
        null,
        Buffer.from(`${encodedHeader}.${encodedPayload}`, 'ascii'),
        publicKey,
        Buffer.from(encodedSignature, 'base64url')
      )) {
        throw new Error('auth_invalid');
      }
      const nowSeconds = Math.floor(nowMs / 1_000);
      if (!claims || claims.iss !== this.issuer || !audienceMatches(claims.aud, this.audience) ||
          !Number.isInteger(claims.iat) || !Number.isInteger(claims.nbf) || !Number.isInteger(claims.exp) ||
          claims.exp <= claims.iat || claims.exp - claims.iat > this.maxTokenLifetimeSeconds ||
          claims.nbf < claims.iat - this.clockSkewSeconds ||
          nowSeconds + this.clockSkewSeconds < claims.nbf || nowSeconds - this.clockSkewSeconds >= claims.exp ||
          typeof claims.sub !== 'string' || !IDENTIFIER_PATTERN.test(claims.sub) ||
          typeof claims.jti !== 'string' || !IDENTIFIER_PATTERN.test(claims.jti) ||
          claims.consentVersion !== this.consentVersion || !scopeContains(claims.scope, 'ai:suggest')) {
        throw new Error('auth_invalid');
      }
      return Object.freeze({ subject: claims.sub, tokenId: claims.jti, expiresAtSeconds: claims.exp });
    } catch {
      throw new ProxyError(401, ProxyErrorCode.UNAUTHORIZED);
    }
  }
}

function decodeJson(encoded) {
  const bytes = Buffer.from(encoded, 'base64url');
  if (bytes.length < 2 || bytes.length > 4_096) {
    throw new Error('auth_invalid');
  }
  return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
}

function audienceMatches(claimAudience, expected) {
  return claimAudience === expected ||
    (Array.isArray(claimAudience) && claimAudience.length <= 4 && claimAudience.includes(expected));
}

function scopeContains(scope, expected) {
  return typeof scope === 'string' && scope.split(' ').filter(Boolean).includes(expected);
}
