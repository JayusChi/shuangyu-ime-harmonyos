import { readFileSync } from 'node:fs';
import { isAbsolute } from 'node:path';

const PROTOCOL_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$/;
const POLICY_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._:/-]{2,127}$/;

export function loadProductionConfig(env = process.env) {
  const mode = required(env, 'AI_PROXY_MODE');
  if (mode !== 'production') {
    throw new Error('config_invalid');
  }
  const publicOrigin = parseHttpsOrigin(required(env, 'AI_PROXY_PUBLIC_ORIGIN'));
  const protocolVersion = matchRequired(env, 'AI_PROXY_PROTOCOL_VERSION', PROTOCOL_PATTERN);
  const consentVersion = integerRequired(env, 'AI_PROXY_CONSENT_VERSION', 1, 1_000_000);
  const issuer = parseHttpsOrigin(required(env, 'AI_PROXY_TOKEN_ISSUER'));
  const audience = matchRequired(env, 'AI_PROXY_TOKEN_AUDIENCE', POLICY_PATTERN);
  const jwksPath = absolutePathRequired(env, 'AI_PROXY_JWKS_PATH');
  const retentionPolicyId = matchRequired(env, 'AI_PROXY_RETENTION_POLICY_ID', POLICY_PATTERN);
  const noTrainPolicyId = matchRequired(env, 'AI_PROXY_NO_TRAIN_POLICY_ID', POLICY_PATTERN);
  const privacyNoticeId = matchRequired(env, 'AI_PROXY_PRIVACY_NOTICE_ID', POLICY_PATTERN);
  const rateLimitPerMinute = integerRequired(env, 'AI_PROXY_RATE_LIMIT_PER_MINUTE', 1, 600);
  const modelGatewayUrl = parseHttpsEndpoint(required(env, 'AI_MODEL_GATEWAY_URL'));
  const modelAuthTokenFile = absolutePathRequired(env, 'AI_MODEL_AUTH_TOKEN_FILE');
  const modelTimeoutMs = integerRequired(env, 'AI_MODEL_TIMEOUT_MS', 500, 6_500);
  const port = integerOptional(env, 'PORT', 8080, 1, 65_535);
  const host = env.HOST?.trim() || '0.0.0.0';
  const externalTlsTerminated = env.AI_PROXY_EXTERNAL_TLS_TERMINATED === 'true';
  const tlsCertPath = env.AI_PROXY_TLS_CERT_PATH?.trim() || '';
  const tlsKeyPath = env.AI_PROXY_TLS_KEY_PATH?.trim() || '';
  if (!externalTlsTerminated && (tlsCertPath.length === 0 || tlsKeyPath.length === 0)) {
    throw new Error('config_invalid');
  }
  if ((tlsCertPath.length === 0) !== (tlsKeyPath.length === 0)) {
    throw new Error('config_invalid');
  }
  if (!externalTlsTerminated && (!isAbsolute(tlsCertPath) || !isAbsolute(tlsKeyPath))) {
    throw new Error('config_invalid');
  }
  return Object.freeze({
    mode,
    publicOrigin,
    protocolVersion,
    providerVersion: 'ai-proxy-reference-1',
    consentVersion,
    issuer,
    audience,
    jwksPath,
    maxTokenLifetimeSeconds: integerOptional(env, 'AI_PROXY_MAX_TOKEN_LIFETIME_SECONDS', 300, 30, 300),
    clockSkewSeconds: integerOptional(env, 'AI_PROXY_TOKEN_CLOCK_SKEW_SECONDS', 15, 0, 30),
    retentionPolicyId,
    noTrainPolicyId,
    privacyNoticeId,
    rateLimitPerMinute,
    replayWindowMs: integerOptional(env, 'AI_PROXY_REPLAY_WINDOW_MS', 600_000, 60_000, 900_000),
    maxRequestBytes: 8 * 1024,
    maxProviderResponseBytes: 64 * 1024,
    modelGatewayUrl,
    modelAuthTokenFile,
    modelTimeoutMs,
    host,
    port,
    externalTlsTerminated,
    tlsCertPath,
    tlsKeyPath
  });
}

export function loadMountedSecret(path) {
  const value = readFileSync(path, { encoding: 'utf8' }).trim();
  if (value.length < 16 || value.length > 8_192 || /[\r\n\0]/.test(value)) {
    throw new Error('secret_invalid');
  }
  return value;
}

function required(env, name) {
  const value = env[name]?.trim() || '';
  if (value.length === 0 || value.startsWith('REPLACE_')) {
    throw new Error('config_invalid');
  }
  return value;
}

function matchRequired(env, name, pattern) {
  const value = required(env, name);
  if (!pattern.test(value)) {
    throw new Error('config_invalid');
  }
  return value;
}

function absolutePathRequired(env, name) {
  const value = required(env, name);
  if (!isAbsolute(value)) {
    throw new Error('config_invalid');
  }
  return value;
}

function integerRequired(env, name, minimum, maximum) {
  return parseInteger(required(env, name), minimum, maximum);
}

function integerOptional(env, name, fallback, minimum, maximum) {
  const value = env[name]?.trim();
  return value ? parseInteger(value, minimum, maximum) : fallback;
}

function parseInteger(value, minimum, maximum) {
  if (!/^[0-9]+$/.test(value)) {
    throw new Error('config_invalid');
  }
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < minimum || parsed > maximum) {
    throw new Error('config_invalid');
  }
  return parsed;
}

function parseHttpsOrigin(value) {
  const url = new URL(value);
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash ||
      (url.port && url.port !== '443') || url.pathname !== '/') {
    throw new Error('config_invalid');
  }
  rejectReservedHost(url.hostname);
  return url.origin;
}

function parseHttpsEndpoint(value) {
  const url = new URL(value);
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash ||
      (url.port && url.port !== '443') || url.pathname === '/') {
    throw new Error('config_invalid');
  }
  rejectReservedHost(url.hostname);
  return url.toString();
}

function rejectReservedHost(hostname) {
  const host = hostname.toLowerCase();
  if (host === 'localhost' || host.endsWith('.localhost') || host.endsWith('.test') ||
      host.endsWith('.invalid') || host.endsWith('.example') || host === 'example.com' ||
      host.endsWith('.example.com') || host === 'example.org' || host.endsWith('.example.org') ||
      host === 'example.net' || host.endsWith('.example.net') || host === '127.0.0.1' || host === '::1') {
    throw new Error('config_invalid');
  }
}
