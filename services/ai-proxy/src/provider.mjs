import { readFileSync } from 'node:fs';
import { ProxyError, ProxyErrorCode } from './errors.mjs';

export class HttpJsonModelProvider {
  constructor({ endpoint, authTokenFile, maxResponseBytes, fetchImpl = fetch }) {
    this.endpoint = endpoint;
    this.authTokenFile = authTokenFile;
    this.maxResponseBytes = maxResponseBytes;
    this.fetchImpl = fetchImpl;
  }

  async suggest(request, signal) {
    let token;
    try {
      token = readSecret(this.authTokenFile);
    } catch {
      throw new ProxyError(503, ProxyErrorCode.PROVIDER_UNAVAILABLE);
    }
    let response;
    try {
      response = await this.fetchImpl(this.endpoint, {
        method: 'POST',
        headers: {
          'Accept': 'application/json',
          'Authorization': `Bearer ${token}`,
          'Cache-Control': 'no-store',
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          action: request.action,
          text: request.text,
          language: request.language,
          maxSuggestions: request.maxSuggestions
        }),
        redirect: 'error',
        signal
      });
    } catch (error) {
      if (signal.aborted) {
        throw new ProxyError(504, ProxyErrorCode.PROVIDER_TIMEOUT);
      }
      throw new ProxyError(503, ProxyErrorCode.PROVIDER_UNAVAILABLE);
    }
    if (response.status !== 200 || !response.headers.get('content-type')?.toLowerCase().startsWith('application/json')) {
      throw new ProxyError(503, ProxyErrorCode.PROVIDER_UNAVAILABLE);
    }
    let body;
    try {
      body = await readLimitedBody(response.body, this.maxResponseBytes);
    } catch (error) {
      if (error instanceof ProxyError) throw error;
      throw new ProxyError(503, ProxyErrorCode.PROVIDER_UNAVAILABLE);
    }
    try {
      return JSON.parse(body);
    } catch {
      throw new ProxyError(502, ProxyErrorCode.PROVIDER_RESPONSE_INVALID);
    }
  }
}

async function readLimitedBody(stream, limit) {
  if (!stream) {
    throw new ProxyError(502, ProxyErrorCode.PROVIDER_RESPONSE_INVALID);
  }
  const reader = stream.getReader();
  const chunks = [];
  let length = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    length += value.byteLength;
    if (length > limit) {
      await reader.cancel();
      throw new ProxyError(502, ProxyErrorCode.PROVIDER_RESPONSE_TOO_LARGE);
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch {
    throw new ProxyError(502, ProxyErrorCode.PROVIDER_RESPONSE_INVALID);
  }
}

function readSecret(path) {
  const value = readFileSync(path, { encoding: 'utf8' }).trim();
  if (value.length < 16 || value.length > 8_192 || /[\r\n\0]/.test(value)) {
    throw new Error('secret_invalid');
  }
  return value;
}
