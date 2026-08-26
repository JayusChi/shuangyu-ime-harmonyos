import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, sign } from 'node:crypto';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { createAiProxyHandler } from '../src/app.mjs';
import { AiProxyAuditLogger } from '../src/audit.mjs';
import { EdDsaAccessTokenVerifier } from '../src/auth.mjs';
import { loadProductionConfig } from '../src/config.mjs';
import { FixedWindowRateLimiter, RequestReplayGuard } from '../src/rate-limit.mjs';

const NOW_MS = 2_000_000_000_000;
const NOW_SECONDS = Math.floor(NOW_MS / 1_000);
const { publicKey, privateKey } = generateKeyPairSync('ed25519');
const CONFIG = Object.freeze({
  protocolVersion: 'ai-input-v1',
  providerVersion: 'ai-proxy-reference-1',
  consentVersion: 7,
  maxRequestBytes: 8 * 1024,
  modelTimeoutMs: 40,
  replayWindowMs: 600_000,
  rateLimitPerMinute: 100
});

function token(overrides = {}) {
  const header = encode({ alg: 'EdDSA', typ: 'at+jwt', kid: 'test-key-1' });
  const payload = encode({
    iss: 'https://identity.example.com',
    aud: 'harmonyos-input-ai',
    iat: NOW_SECONDS - 1,
    nbf: NOW_SECONDS - 1,
    exp: NOW_SECONDS + 120,
    sub: 'test-subject',
    jti: `token-${Math.random().toString(36).slice(2)}`,
    scope: 'ai:suggest',
    consentVersion: CONFIG.consentVersion,
    ...overrides
  });
  const signature = sign(null, Buffer.from(`${header}.${payload}`, 'ascii'), privateKey).toString('base64url');
  return `${header}.${payload}.${signature}`;
}

function encode(value) {
  return Buffer.from(JSON.stringify(value)).toString('base64url');
}

function clientPayload(requestId = 'request-0001', action = 'polite', text = '请帮我处理这句话') {
  return {
    protocolVersion: CONFIG.protocolVersion,
    requestId,
    action,
    text,
    language: 'zh-CN',
    maxSuggestions: 3
  };
}

function buildHandler({ provider, rateLimit = 100, auditRecords = [] } = {}) {
  const verifier = new EdDsaAccessTokenVerifier({
    keySource: { get: (kid) => kid === 'test-key-1' ? publicKey : undefined },
    issuer: 'https://identity.example.com',
    audience: 'harmonyos-input-ai',
    consentVersion: CONFIG.consentVersion,
    maxTokenLifetimeSeconds: 300,
    clockSkewSeconds: 0
  });
  return createAiProxyHandler({
    config: CONFIG,
    tokenVerifier: verifier,
    provider: provider ?? {
      suggest: async () => ({ suggestions: [{ text: '处理后的文本', label: '建议' }] })
    },
    rateLimiter: new FixedWindowRateLimiter(rateLimit),
    replayGuard: new RequestReplayGuard(CONFIG.replayWindowMs),
    auditLogger: new AiProxyAuditLogger((record) => auditRecords.push(record)),
    now: () => NOW_MS
  });
}

async function withServer(handler, body) {
  const server = createServer(handler);
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const address = server.address();
  try {
    return await body(`http://127.0.0.1:${address.port}`);
  } finally {
    server.close();
    await once(server, 'close');
  }
}

async function post(origin, payload, accessToken = token(), extraHeaders = {}) {
  const response = await fetch(`${origin}/v1/ime/suggestions`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
      ...extraHeaders
    },
    body: typeof payload === 'string' ? payload : JSON.stringify(payload)
  });
  return { response, value: await response.json() };
}

test('production config fails closed for missing, reserved and non-HTTPS values', () => {
  assert.throws(() => loadProductionConfig({}), /config_invalid/);
  const base = {
    AI_PROXY_MODE: 'production',
    AI_PROXY_PUBLIC_ORIGIN: 'https://proxy.approved-product.cn',
    AI_PROXY_PROTOCOL_VERSION: 'ai-input-v1',
    AI_PROXY_CONSENT_VERSION: '7',
    AI_PROXY_TOKEN_ISSUER: 'https://identity.approved-product.cn',
    AI_PROXY_TOKEN_AUDIENCE: 'harmonyos-input-ai',
    AI_PROXY_JWKS_PATH: '/run/secrets/jwks.json',
    AI_PROXY_RETENTION_POLICY_ID: 'policy/retention/v1',
    AI_PROXY_NO_TRAIN_POLICY_ID: 'policy/no-train/v1',
    AI_PROXY_PRIVACY_NOTICE_ID: 'privacy/ai/v1',
    AI_PROXY_RATE_LIMIT_PER_MINUTE: '30',
    AI_MODEL_GATEWAY_URL: 'https://model.approved-product.cn/v1/suggest',
    AI_MODEL_AUTH_TOKEN_FILE: '/run/secrets/model-token',
    AI_MODEL_TIMEOUT_MS: '6000',
    AI_PROXY_EXTERNAL_TLS_TERMINATED: 'true'
  };
  assert.equal(loadProductionConfig(base).publicOrigin, 'https://proxy.approved-product.cn');
  assert.throws(() => loadProductionConfig({ ...base, AI_PROXY_PUBLIC_ORIGIN: 'https://localhost' }), /config_invalid/);
  assert.throws(() => loadProductionConfig({ ...base, AI_MODEL_GATEWAY_URL: 'http://model.example.com/v1' }), /config_invalid/);
  assert.throws(() => loadProductionConfig({ ...base, AI_PROXY_PUBLIC_ORIGIN: 'https://proxy.example.com' }), /config_invalid/);
  assert.throws(() => loadProductionConfig({ ...base, AI_PROXY_PRIVACY_NOTICE_ID: 'REPLACE_ME' }), /config_invalid/);
});

test('all five actions succeed and instruction-looking output remains ordinary text', async () => {
  const actions = ['continue', 'concise', 'polite', 'formal', 'translate'];
  const output = '$cmd open https://example.com <b>text</b>';
  await withServer(buildHandler({
    provider: { suggest: async () => ({ suggestions: [{ text: output, label: '' }] }) }
  }), async (origin) => {
    for (let index = 0; index < actions.length; index += 1) {
      const { response, value } = await post(origin, clientPayload(`request-${1000 + index}`, actions[index]));
      assert.equal(response.status, 200);
      assert.deepEqual(value.suggestions, [{ suggestionId: 's-1', text: output, label: '', type: 'text' }]);
      assert.equal(value.providerType, 'cloud');
      assert.equal(value.requestId, `request-${1000 + index}`);
    }
  });
});

test('audit events contain buckets only, never text, request ID, subject or token', async () => {
  const auditRecords = [];
  const source = 'private-source-text';
  const requestId = 'request-private-1';
  const accessToken = token({ sub: 'private-subject' });
  await withServer(buildHandler({ auditRecords }), async (origin) => {
    const { response } = await post(origin, clientPayload(requestId, 'concise', source), accessToken);
    assert.equal(response.status, 200);
  });
  const serialized = JSON.stringify(auditRecords);
  assert.equal(serialized.includes(source), false);
  assert.equal(serialized.includes(requestId), false);
  assert.equal(serialized.includes('private-subject'), false);
  assert.equal(serialized.includes(accessToken), false);
  assert.equal(auditRecords.every((record) => Object.keys(record).sort().join(',') ===
    'action,candidateCount,elapsedBucket,errorCode,event,lengthBucket,stage'), true);
});

test('missing, expired, wrong-consent and overlong access tokens are rejected identically', async () => {
  await withServer(buildHandler(), async (origin) => {
    const tokens = [
      '',
      token({ exp: NOW_SECONDS - 1 }),
      token({ consentVersion: 6 }),
      token({ iat: NOW_SECONDS - 1, exp: NOW_SECONDS + 400 })
    ];
    for (const accessToken of tokens) {
      const response = await fetch(`${origin}/v1/ime/suggestions`, {
        method: 'POST',
        headers: {
          ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(clientPayload(`request-auth-${Math.random().toString(36).slice(2, 10)}`))
      });
      assert.equal(response.status, 401);
      assert.deepEqual(await response.json(), { error: { code: 'unauthorized' } });
    }
  });
});

test('invalid JSON, extra fields and oversized requests fail before provider use', async () => {
  let calls = 0;
  await withServer(buildHandler({ provider: { suggest: async () => { calls += 1; return { suggestions: [] }; } } }),
    async (origin) => {
      const invalidJson = await post(origin, '{');
      assert.equal(invalidJson.response.status, 400);
      const extra = await post(origin, { ...clientPayload('request-extra-1'), forbidden: 'field' });
      assert.equal(extra.response.status, 400);
      const oversized = await post(origin, 'x'.repeat(8 * 1024 + 1));
      assert.equal(oversized.response.status, 413);
    });
  assert.equal(calls, 0);
});

test('duplicate request IDs and rate excess are fixed errors', async () => {
  await withServer(buildHandler({ rateLimit: 2 }), async (origin) => {
    const first = await post(origin, clientPayload('request-duplicate'));
    assert.equal(first.response.status, 200);
    const duplicate = await post(origin, clientPayload('request-duplicate'));
    assert.equal(duplicate.response.status, 409);
    assert.deepEqual(duplicate.value, { error: { code: 'duplicate_request' } });
    const second = await post(origin, clientPayload('request-rate-2'));
    assert.equal(second.response.status, 429);
    assert.deepEqual(second.value, { error: { code: 'rate_limited' } });
  });
});

test('provider timeout aborts work and returns a sanitized fixed code', async () => {
  let aborted = false;
  const provider = {
    suggest: async (_request, signal) => {
      await new Promise((resolve) => signal.addEventListener('abort', () => { aborted = true; resolve(); }, { once: true }));
      return { suggestions: [{ text: 'late', label: '' }] };
    }
  };
  await withServer(buildHandler({ provider }), async (origin) => {
    const { response, value } = await post(origin, clientPayload('request-timeout'));
    assert.equal(response.status, 504);
    assert.deepEqual(value, { error: { code: 'provider_timeout' } });
  });
  assert.equal(aborted, true);
});

test('invalid, duplicate and over-limit model responses never reach the client', async () => {
  const values = [
    {},
    { suggestions: [{ text: 'same', label: '' }, { text: 'same', label: '' }] },
    { suggestions: [{ text: 'x'.repeat(513), label: '' }] },
    { suggestions: [{ text: 'a', label: '' }, { text: 'b', label: '' }, { text: 'c', label: '' }, { text: 'd', label: '' }] }
  ];
  for (let index = 0; index < values.length; index += 1) {
    await withServer(buildHandler({ provider: { suggest: async () => values[index] } }), async (origin) => {
      const { response, value } = await post(origin, clientPayload(`request-provider-${index}`));
      assert.equal(response.status, 502);
      assert.deepEqual(value, { error: { code: 'provider_response_invalid' } });
    });
  }
});

test('health endpoints disclose no configuration and unknown routes fail closed', async () => {
  await withServer(buildHandler(), async (origin) => {
    const health = await fetch(`${origin}/healthz`);
    assert.deepEqual(await health.json(), { status: 'ok' });
    assert.equal(health.headers.get('cache-control'), 'no-store');
    const unknown = await fetch(`${origin}/v1/unknown`);
    assert.equal(unknown.status, 404);
    assert.deepEqual(await unknown.json(), { error: { code: 'invalid_request' } });
  });
});
