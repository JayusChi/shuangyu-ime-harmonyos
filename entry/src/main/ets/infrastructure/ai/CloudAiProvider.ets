import {
  AI_ACTIONS,
  AiErrorCode,
  AiProviderKind,
  AiProviderPolicy,
  AiProviderResult,
  AiReplacePolicy,
  AiRequest,
  AiSourceOwnership,
  AiSuggestion,
  MAX_AI_RESPONSE_BYTES,
  MAX_AI_SOURCE_TEXT_LENGTH,
  MAX_AI_SUGGESTIONS,
  MAX_AI_SUGGESTION_TEXT_LENGTH
} from '../../domain/ai/AiContracts';
import { AiProvider } from './AiProvider';
import {
  CloudAiTransport,
  CloudAiTransportRequest,
  CloudAiTransportResponse
} from './CloudAiTransport';

const MAX_LABEL_LENGTH: number = 32;
const MAX_PROVIDER_VERSION_LENGTH: number = 64;

export interface CloudAiProviderConfig {
  endpoint: string;
  approvedProxyHost: string;
  protocolVersion: string;
  maxResponseBytes?: number;
}

interface CloudSuggestionJson {
  suggestionId: string;
  text: string;
  label: string;
  type: string;
}

interface CloudResponseJson {
  protocolVersion: string;
  requestId: string;
  providerType: string;
  providerVersion: string;
  suggestions: CloudSuggestionJson[];
}

export class CloudAiProvider implements AiProvider {
  private readonly config: CloudAiProviderConfig;
  private readonly transport: CloudAiTransport;
  private readonly maxResponseBytes: number;
  private readonly canceledRequestIds: Set<string> = new Set<string>();

  constructor(config: CloudAiProviderConfig, transport: CloudAiTransport) {
    if (!validProxyConfig(config)) {
      throw new Error('invalid_cloud_ai_proxy_config');
    }
    this.config = {
      endpoint: config.endpoint,
      approvedProxyHost: config.approvedProxyHost,
      protocolVersion: config.protocolVersion,
      maxResponseBytes: config.maxResponseBytes
    };
    this.transport = transport;
    this.maxResponseBytes = Math.min(
      MAX_AI_RESPONSE_BYTES,
      Math.max(1024, config.maxResponseBytes ?? MAX_AI_RESPONSE_BYTES)
    );
  }

  async request(request: AiRequest): Promise<AiProviderResult> {
    this.canceledRequestIds.delete(request.requestId);
    if (!validRequest(request)) {
      return this.failure(request.requestId, AiErrorCode.INVALID_REQUEST);
    }
    const transportRequest: CloudAiTransportRequest = {
      requestId: request.requestId,
      endpoint: this.config.endpoint,
      body: JSON.stringify({
        protocolVersion: this.config.protocolVersion,
        requestId: request.requestId,
        action: request.action,
        text: request.sourceText,
        language: request.locale,
        maxSuggestions: request.maxSuggestions
      }),
      timeoutMs: request.deadlineMs,
      maxResponseBytes: this.maxResponseBytes
    };
    let response: CloudAiTransportResponse;
    try {
      response = await this.transport.post(transportRequest);
    } catch (_err) {
      return this.canceledRequestIds.has(request.requestId)
        ? this.failure(request.requestId, AiErrorCode.CANCELED)
        : this.failure(request.requestId, AiErrorCode.NETWORK_ERROR);
    }
    if (this.canceledRequestIds.has(request.requestId)) {
      return this.failure(request.requestId, AiErrorCode.CANCELED);
    }
    if (response.statusCode !== 200) {
      return this.failure(request.requestId, AiErrorCode.HTTP_ERROR);
    }
    if (!Number.isInteger(response.bodyBytes) || response.bodyBytes <= 0 ||
      response.bodyBytes > this.maxResponseBytes || utf8ByteLength(response.body) !== response.bodyBytes) {
      return this.failure(request.requestId,
        response.bodyBytes > this.maxResponseBytes
          ? AiErrorCode.RESPONSE_TOO_LARGE
          : AiErrorCode.INVALID_RESPONSE);
    }
    return this.parseResponse(request, response.body);
  }

  cancel(requestId: string): void {
    this.canceledRequestIds.add(requestId);
    this.transport.cancel(requestId);
  }

  private parseResponse(request: AiRequest, body: string): AiProviderResult {
    let parsed: CloudResponseJson;
    try {
      parsed = JSON.parse(body) as CloudResponseJson;
    } catch (_err) {
      return this.failure(request.requestId, AiErrorCode.INVALID_RESPONSE);
    }
    if (!validResponseEnvelope(parsed, request.requestId, this.config.protocolVersion)) {
      return this.failure(request.requestId, AiErrorCode.PROTOCOL_ERROR);
    }
    if (parsed.suggestions.length === 0) {
      return this.failure(request.requestId, AiErrorCode.EMPTY_RESULT);
    }
    const ids: Set<string> = new Set<string>();
    const suggestions: AiSuggestion[] = [];
    for (let index = 0; index < parsed.suggestions.length; index += 1) {
      const item = parsed.suggestions[index];
      if (!validSuggestion(item) || ids.has(item.suggestionId)) {
        return this.failure(request.requestId, AiErrorCode.PROTOCOL_ERROR);
      }
      ids.add(item.suggestionId);
      suggestions.push({
        suggestionId: item.suggestionId,
        requestId: request.requestId,
        text: item.text,
        label: item.label,
        providerKind: AiProviderKind.CLOUD,
        replacePolicy: AiReplacePolicy.REPLACE_VERIFIED_SOURCE
      });
    }
    return {
      success: true,
      requestId: request.requestId,
      providerKind: AiProviderKind.CLOUD,
      suggestions,
      errorCode: AiErrorCode.NONE
    };
  }

  private failure(requestId: string, errorCode: AiErrorCode): AiProviderResult {
    return {
      success: false,
      requestId,
      providerKind: AiProviderKind.CLOUD,
      suggestions: [],
      errorCode
    };
  }
}

function validProxyConfig(config: CloudAiProviderConfig): boolean {
  if (config.protocolVersion.length <= 0 || config.protocolVersion.length > 32 ||
    config.approvedProxyHost.length <= 0 || config.approvedProxyHost.length > 253) {
    return false;
  }
  const prefix = 'https://';
  if (!config.endpoint.startsWith(prefix) || config.endpoint.indexOf('@') >= 0 ||
    config.endpoint.indexOf('#') >= 0 || config.endpoint.indexOf('?') >= 0) {
    return false;
  }
  const authorityAndPath = config.endpoint.slice(prefix.length);
  const slash = authorityAndPath.indexOf('/');
  if (slash <= 0 || slash === authorityAndPath.length - 1) {
    return false;
  }
  const authority = authorityAndPath.slice(0, slash).toLowerCase();
  const approved = config.approvedProxyHost.toLowerCase();
  if (authority !== approved || approved === 'localhost' || approved.endsWith('.localhost') ||
    approved.endsWith('.test') || approved.endsWith('.invalid') || approved.indexOf(':') >= 0) {
    return false;
  }
  return true;
}

function validRequest(request: AiRequest): boolean {
  return request.requestId.length > 0 && request.requestId.length <= 96 &&
    request.sessionId.length > 0 && request.sessionId.length <= 96 &&
    Number.isInteger(request.sessionGeneration) && request.sessionGeneration >= 0 &&
    AI_ACTIONS.indexOf(request.action) >= 0 &&
    request.sourceText.length > 0 && request.sourceText.length <= MAX_AI_SOURCE_TEXT_LENGTH &&
    request.locale.length > 0 && request.locale.length <= 16 &&
    request.deadlineMs > 0 && request.deadlineMs <= 8000 &&
    request.maxSuggestions > 0 && request.maxSuggestions <= MAX_AI_SUGGESTIONS &&
    request.sourceOwnership === AiSourceOwnership.LAST_IME_COMMIT &&
    request.providerPolicy === AiProviderPolicy.CLOUD_ALLOWED;
}

function validResponseEnvelope(
  parsed: CloudResponseJson,
  requestId: string,
  protocolVersion: string
): boolean {
  return typeof parsed === 'object' && parsed !== null &&
    exactKeys(parsed, ['protocolVersion', 'requestId', 'providerType', 'providerVersion', 'suggestions']) &&
    parsed.protocolVersion === protocolVersion && parsed.requestId === requestId &&
    parsed.providerType === 'cloud' && typeof parsed.providerVersion === 'string' &&
    parsed.providerVersion.length > 0 && parsed.providerVersion.length <= MAX_PROVIDER_VERSION_LENGTH &&
    Array.isArray(parsed.suggestions) && parsed.suggestions.length <= MAX_AI_SUGGESTIONS;
}

function validSuggestion(item: CloudSuggestionJson): boolean {
  return typeof item === 'object' && item !== null &&
    exactKeys(item, ['suggestionId', 'text', 'label', 'type']) && item.type === 'text' &&
    typeof item.suggestionId === 'string' && item.suggestionId.length > 0 && item.suggestionId.length <= 96 &&
    typeof item.text === 'string' && item.text.length > 0 && item.text.length <= MAX_AI_SUGGESTION_TEXT_LENGTH &&
    typeof item.label === 'string' && item.label.length <= MAX_LABEL_LENGTH;
}

function exactKeys(value: Object, expected: string[]): boolean {
  return Object.keys(value).sort().join('|') === expected.slice().sort().join('|');
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
