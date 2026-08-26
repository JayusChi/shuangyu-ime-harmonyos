import { ProxyError, ProxyErrorCode, fixedProxyError } from './errors.mjs';
import { normalizeModelResponse, parseClientRequest } from './validation.mjs';

const JSON_CONTENT_TYPE = 'application/json; charset=utf-8';

export function createAiProxyHandler({
  config,
  tokenVerifier,
  provider,
  rateLimiter,
  replayGuard,
  auditLogger,
  now = () => Date.now()
}) {
  return async function aiProxyHandler(request, response) {
    setSecurityHeaders(response);
    if (request.method === 'GET' && request.url === '/healthz') {
      sendJson(response, 200, { status: 'ok' });
      return;
    }
    if (request.method === 'GET' && request.url === '/readyz') {
      sendJson(response, 200, { status: 'ready' });
      return;
    }
    if (request.method !== 'POST' || request.url !== '/v1/ime/suggestions') {
      sendError(response, new ProxyError(404, ProxyErrorCode.INVALID_REQUEST));
      return;
    }

    const startedAt = now();
    let action = 'unknown';
    let sourceLength = 0;
    let requestBody;
    try {
      // Authenticate before reading user text from the request body.
      const principal = tokenVerifier.verify(request.headers.authorization, startedAt);
      requireJsonContentType(request.headers['content-type']);
      requestBody = await readLimitedRequestBody(request, config.maxRequestBytes);
      const parsed = parseClientRequest(requestBody, config);
      action = parsed.action;
      sourceLength = parsed.text.length;
      rateLimiter.consume(principal.subject, startedAt);
      replayGuard.accept(principal.subject, parsed.requestId, startedAt);
      auditLogger.record({ action, stage: 'accepted', sourceLength, elapsedMs: 0, candidateCount: 0, errorCode: 'none' });

      const controller = new AbortController();
      const abortForClient = () => controller.abort('client_disconnected');
      request.once('aborted', abortForClient);
      response.once('close', () => {
        if (!response.writableEnded) abortForClient();
      });
      const timeout = setTimeout(() => controller.abort('provider_timeout'), config.modelTimeoutMs);
      let providerValue;
      try {
        providerValue = await provider.suggest(parsed, controller.signal);
      } finally {
        clearTimeout(timeout);
        request.off('aborted', abortForClient);
      }
      if (controller.signal.aborted) {
        throw new ProxyError(504, ProxyErrorCode.PROVIDER_TIMEOUT);
      }
      const suggestions = normalizeModelResponse(providerValue, parsed.maxSuggestions);
      auditLogger.record({
        action,
        stage: 'completed',
        sourceLength,
        elapsedMs: now() - startedAt,
        candidateCount: suggestions.length,
        errorCode: 'none'
      });
      sendJson(response, 200, {
        protocolVersion: config.protocolVersion,
        requestId: parsed.requestId,
        providerType: 'cloud',
        providerVersion: config.providerVersion,
        suggestions
      });
    } catch (error) {
      const fixed = fixedProxyError(error);
      auditLogger.record({
        action,
        stage: sourceLength > 0 ? 'provider' : 'rejected',
        sourceLength,
        elapsedMs: now() - startedAt,
        candidateCount: 0,
        errorCode: fixed.code
      });
      if (!response.headersSent && !response.destroyed) {
        sendError(response, fixed);
      }
    } finally {
      // Avoid retaining input text beyond this request scope.
      requestBody = undefined;
    }
  };
}

function requireJsonContentType(contentType) {
  if (typeof contentType !== 'string' || contentType.split(';', 1)[0].trim().toLowerCase() !== 'application/json') {
    throw new ProxyError(415, ProxyErrorCode.INVALID_REQUEST);
  }
}

async function readLimitedRequestBody(request, limit) {
  const announced = Number(request.headers['content-length']);
  if (Number.isFinite(announced) && announced > limit) {
    throw new ProxyError(413, ProxyErrorCode.PAYLOAD_TOO_LARGE);
  }
  const chunks = [];
  let length = 0;
  try {
    for await (const chunk of request) {
      const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
      length += bytes.length;
      if (length > limit) {
        throw new ProxyError(413, ProxyErrorCode.PAYLOAD_TOO_LARGE);
      }
      chunks.push(bytes);
    }
  } catch (error) {
    if (error instanceof ProxyError) throw error;
    throw new ProxyError(400, ProxyErrorCode.INVALID_REQUEST);
  }
  if (length === 0) {
    throw new ProxyError(400, ProxyErrorCode.INVALID_REQUEST);
  }
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks, length));
  } catch {
    throw new ProxyError(400, ProxyErrorCode.INVALID_REQUEST);
  }
}

function setSecurityHeaders(response) {
  response.setHeader('Cache-Control', 'no-store');
  response.setHeader('Content-Security-Policy', "default-src 'none'");
  response.setHeader('Referrer-Policy', 'no-referrer');
  response.setHeader('X-Content-Type-Options', 'nosniff');
  response.setHeader('X-Frame-Options', 'DENY');
}

function sendError(response, error) {
  sendJson(response, error.statusCode, { error: { code: error.code } });
}

function sendJson(response, statusCode, value) {
  const body = JSON.stringify(value);
  response.statusCode = statusCode;
  response.setHeader('Content-Type', JSON_CONTENT_TYPE);
  response.setHeader('Content-Length', Buffer.byteLength(body));
  response.end(body);
}
