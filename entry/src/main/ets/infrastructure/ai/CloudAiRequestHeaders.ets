export interface CloudAiRequestHeaders {
  authorization?: string;
  clientAttestation?: string;
}

export interface CloudAiRequestHeaderProvider {
  getHeaders(requestId: string): Promise<CloudAiRequestHeaders>;
}
