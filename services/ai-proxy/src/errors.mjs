export const ProxyErrorCode = Object.freeze({
  UNAUTHORIZED: 'unauthorized',
  FORBIDDEN: 'forbidden',
  INVALID_REQUEST: 'invalid_request',
  PAYLOAD_TOO_LARGE: 'payload_too_large',
  DUPLICATE_REQUEST: 'duplicate_request',
  RATE_LIMITED: 'rate_limited',
  PROVIDER_UNAVAILABLE: 'provider_unavailable',
  PROVIDER_TIMEOUT: 'provider_timeout',
  PROVIDER_RESPONSE_INVALID: 'provider_response_invalid',
  PROVIDER_RESPONSE_TOO_LARGE: 'provider_response_too_large',
  INTERNAL_ERROR: 'internal_error'
});

export class ProxyError extends Error {
  constructor(statusCode, code) {
    super(code);
    this.name = 'ProxyError';
    this.statusCode = statusCode;
    this.code = code;
  }
}

export function fixedProxyError(error) {
  if (error instanceof ProxyError) {
    return error;
  }
  return new ProxyError(500, ProxyErrorCode.INTERNAL_ERROR);
}
