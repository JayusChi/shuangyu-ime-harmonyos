import { http } from '@kit.NetworkKit';
import {
  CloudAiTransport,
  CloudAiTransportRequest,
  CloudAiTransportResponse
} from './CloudAiTransport';

export interface CloudAiRequestHeaders {
  authorization?: string;
  clientAttestation?: string;
}

export interface CloudAiRequestHeaderProvider {
  getHeaders(requestId: string): Promise<CloudAiRequestHeaders>;
}

/**
 * Thin HTTPS adapter. It is deliberately not wired into the default runtime
 * until Release has an approved endpoint, auth contract, consent copy, and
 * INTERNET permission profile.
 */
export class HarmonyHttpAiTransport implements CloudAiTransport {
  private readonly headerProvider: CloudAiRequestHeaderProvider;
  private readonly requests: Map<string, http.HttpRequest> = new Map<string, http.HttpRequest>();

  constructor(headerProvider: CloudAiRequestHeaderProvider) {
    this.headerProvider = headerProvider;
  }

  async post(request: CloudAiTransportRequest): Promise<CloudAiTransportResponse> {
    const task = http.createHttp();
    this.requests.set(request.requestId, task);
    try {
      const headers = await this.headerProvider.getHeaders(request.requestId);
      const authorization = headers.authorization ?? '';
      const attestation = headers.clientAttestation ?? '';
      const header: Object = authorization.length > 0
        ? (attestation.length > 0
          ? {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': authorization,
            'X-Client-Attestation': attestation
          }
          : {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': authorization
          })
        : {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        };
      const response = await task.request(request.endpoint, {
        method: http.RequestMethod.POST,
        header,
        extraData: request.body,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false,
        connectTimeout: request.timeoutMs,
        readTimeout: request.timeoutMs,
        maxLimit: request.maxResponseBytes,
        maxRedirects: 0
      });
      if (typeof response.result !== 'string') {
        throw new Error('cloud_ai_non_text_response');
      }
      const body = response.result as string;
      return {
        statusCode: Number(response.responseCode),
        body,
        bodyBytes: utf8ByteLength(body)
      };
    } finally {
      this.requests.delete(request.requestId);
      task.destroy();
    }
  }

  cancel(requestId: string): void {
    const request = this.requests.get(requestId);
    this.requests.delete(requestId);
    request?.destroy();
  }
}

function utf8ByteLength(value: string): number {
  let bytes = 0;
  for (let index = 0; index < value.length; index += 1) {
    const code = value.charCodeAt(index);
    if (code <= 0x7f) {
      bytes += 1;
    } else if (code <= 0x7ff) {
      bytes += 2;
    } else if (code >= 0xd800 && code <= 0xdbff && index + 1 < value.length &&
      value.charCodeAt(index + 1) >= 0xdc00 && value.charCodeAt(index + 1) <= 0xdfff) {
      bytes += 4;
      index += 1;
    } else {
      bytes += 3;
    }
  }
  return bytes;
}
