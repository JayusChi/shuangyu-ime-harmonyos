import { ProxyError, ProxyErrorCode } from './errors.mjs';

export const AI_ACTIONS = Object.freeze(['continue', 'concise', 'polite', 'formal', 'translate']);
const REQUEST_KEYS = Object.freeze([
  'action', 'language', 'maxSuggestions', 'protocolVersion', 'requestId', 'text'
]);
const MODEL_RESPONSE_KEYS = Object.freeze(['suggestions']);
const MODEL_SUGGESTION_KEYS = Object.freeze(['label', 'text']);
const REQUEST_ID_PATTERN = /^[A-Za-z0-9._:-]{8,96}$/;
const LANGUAGE_PATTERN = /^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$/;

export function parseClientRequest(body, config) {
  let parsed;
  try {
    parsed = JSON.parse(body);
  } catch {
    throw new ProxyError(400, ProxyErrorCode.INVALID_REQUEST);
  }
  if (!plainObject(parsed) || !exactKeys(parsed, REQUEST_KEYS) ||
      parsed.protocolVersion !== config.protocolVersion ||
      typeof parsed.requestId !== 'string' || !REQUEST_ID_PATTERN.test(parsed.requestId) ||
      !AI_ACTIONS.includes(parsed.action) ||
      typeof parsed.text !== 'string' || parsed.text.length < 1 || parsed.text.length > 1_024 ||
      !validUnicode(parsed.text) ||
      typeof parsed.language !== 'string' || parsed.language.length > 16 ||
      !LANGUAGE_PATTERN.test(parsed.language) ||
      !Number.isInteger(parsed.maxSuggestions) || parsed.maxSuggestions < 1 || parsed.maxSuggestions > 3) {
    throw new ProxyError(400, ProxyErrorCode.INVALID_REQUEST);
  }
  return Object.freeze({
    protocolVersion: parsed.protocolVersion,
    requestId: parsed.requestId,
    action: parsed.action,
    text: parsed.text,
    language: parsed.language,
    maxSuggestions: parsed.maxSuggestions
  });
}

export function normalizeModelResponse(value, maxSuggestions) {
  if (!plainObject(value) || !exactKeys(value, MODEL_RESPONSE_KEYS) ||
      !Array.isArray(value.suggestions) || value.suggestions.length < 1 ||
      value.suggestions.length > 3 || value.suggestions.length > maxSuggestions) {
    throw new ProxyError(502, ProxyErrorCode.PROVIDER_RESPONSE_INVALID);
  }
  const texts = new Set();
  return value.suggestions.map((item, index) => {
    if (!plainObject(item) || !exactKeys(item, MODEL_SUGGESTION_KEYS) ||
        typeof item.text !== 'string' || item.text.length < 1 || item.text.length > 512 ||
        !validUnicode(item.text) || texts.has(item.text) ||
        typeof item.label !== 'string' || item.label.length > 32 || !validUnicode(item.label)) {
      throw new ProxyError(502, ProxyErrorCode.PROVIDER_RESPONSE_INVALID);
    }
    texts.add(item.text);
    return Object.freeze({
      suggestionId: `s-${index + 1}`,
      text: item.text,
      label: item.label,
      type: 'text'
    });
  });
}

export function exactKeys(value, expected) {
  return Object.keys(value).sort().join('|') === [...expected].sort().join('|');
}

function plainObject(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value) &&
    Object.getPrototypeOf(value) === Object.prototype;
}

function validUnicode(value) {
  if (value.includes('\0')) {
    return false;
  }
  for (let index = 0; index < value.length; index += 1) {
    const code = value.charCodeAt(index);
    if (code >= 0xd800 && code <= 0xdbff) {
      if (index + 1 >= value.length) {
        return false;
      }
      const next = value.charCodeAt(index + 1);
      if (next < 0xdc00 || next > 0xdfff) {
        return false;
      }
      index += 1;
    } else if (code >= 0xdc00 && code <= 0xdfff) {
      return false;
    }
  }
  return true;
}
