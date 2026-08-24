import { AiProviderKind } from './AiContracts';

export const MAX_LOCAL_ASSOCIATIONS: number = 3;
export const MAX_LOCAL_ASSOCIATION_TEXT_LENGTH: number = 48;

export interface LocalAssociationSuggestion {
  associationId: string;
  text: string;
  providerKind: AiProviderKind;
  sessionGeneration: number;
}

export function copyLocalAssociationSuggestion(
  suggestion: LocalAssociationSuggestion
): LocalAssociationSuggestion {
  return {
    associationId: suggestion.associationId,
    text: suggestion.text,
    providerKind: suggestion.providerKind,
    sessionGeneration: suggestion.sessionGeneration
  };
}

export function copyLocalAssociationSuggestions(
  suggestions: LocalAssociationSuggestion[]
): LocalAssociationSuggestion[] {
  return suggestions.map((item: LocalAssociationSuggestion): LocalAssociationSuggestion =>
    copyLocalAssociationSuggestion(item));
}

export function normalizeLocalAssociations(
  texts: string[],
  sessionGeneration: number
): LocalAssociationSuggestion[] {
  const seen: Set<string> = new Set<string>();
  const suggestions: LocalAssociationSuggestion[] = [];
  for (let index = 0; index < texts.length && suggestions.length < MAX_LOCAL_ASSOCIATIONS; index += 1) {
    const text = texts[index];
    if (text.length <= 0 || text.length > MAX_LOCAL_ASSOCIATION_TEXT_LENGTH || seen.has(text)) {
      continue;
    }
    seen.add(text);
    suggestions.push({
      associationId: `local-${sessionGeneration}-${suggestions.length + 1}`,
      text,
      providerKind: AiProviderKind.LOCAL,
      sessionGeneration
    });
  }
  return suggestions;
}
