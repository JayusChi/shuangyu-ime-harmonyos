export enum CandidatePunctuationResolutionType {
  SELECT_CANDIDATE = 'select_candidate',
  COMMIT_TOP_THEN_PUNCTUATION = 'commit_top_then_punctuation',
  INSERT_PUNCTUATION = 'insert_punctuation'
}

export interface CandidatePunctuationResolution {
  type: CandidatePunctuationResolutionType;
  candidateIndex: number;
}

/**
 * Resolves the phone-keyboard punctuation shortcuts without touching editor
 * state. A semicolon-led symbol guide remains authoritative and is never
 * interpreted as a normal candidate list.
 */
export function resolveCandidatePunctuation(
  rawInput: string,
  candidateCount: number,
  requestedCandidateIndex: number
): CandidatePunctuationResolution {
  const eligibleComposition = rawInput.length > 0 && !rawInput.startsWith(';');
  if (eligibleComposition && candidateCount > requestedCandidateIndex) {
    return {
      type: CandidatePunctuationResolutionType.SELECT_CANDIDATE,
      candidateIndex: requestedCandidateIndex
    };
  }
  if (eligibleComposition && candidateCount > 0) {
    return {
      type: CandidatePunctuationResolutionType.COMMIT_TOP_THEN_PUNCTUATION,
      candidateIndex: 0
    };
  }
  return {
    type: CandidatePunctuationResolutionType.INSERT_PUNCTUATION,
    candidateIndex: -1
  };
}
