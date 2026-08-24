export interface CloudAiTransportRequest {
  requestId: string;
  endpoint: string;
  body: string;
  timeoutMs: number;
  maxResponseBytes: number;
}

export interface CloudAiTransportResponse {
  statusCode: number;
  body: string;
  bodyBytes: number;
}

/**
 * Transport owns short-lived authentication material. CloudAiProvider never
 * accepts or persists a model-vendor key and only supplies the approved proxy URL.
 */
export interface CloudAiTransport {
  post(request: CloudAiTransportRequest): Promise<CloudAiTransportResponse>;
  cancel(requestId: string): void;
}
