import { Candidate } from '../../infrastructure/native/NativeEngineTypes';

/** Stage 4.2 render contract: normal candidate cells never expose reading. */
export interface CandidateDisplayItem {
  displayText: string;
  accessibilityText: string;
}

export function toCandidateDisplayItem(
  candidate: Candidate,
  index: number,
  codeHint: string = ''
): CandidateDisplayItem {
  const suffix = codeHint.length > 0 ? ` ${codeHint}` : '';
  return {
    displayText: `${candidate.text}${suffix}`,
    accessibilityText: `第 ${index + 1} 个候选，${candidate.text}${suffix}`
  };
}
