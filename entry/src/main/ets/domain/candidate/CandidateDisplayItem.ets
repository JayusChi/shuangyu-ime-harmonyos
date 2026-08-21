import { Candidate } from '../../infrastructure/native/NativeEngineTypes';
import { CandidateUiMode, resolveCandidateCodeHint } from './CandidateUiPolicy';

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

/** Keeps candidate text and precise-match continuation hints identical on every form factor. */
export function toContextualCandidateDisplayItem(
  candidate: Candidate,
  index: number,
  mode: CandidateUiMode,
  rawInput: string
): CandidateDisplayItem {
  return toCandidateDisplayItem(
    candidate,
    index,
    resolveCandidateCodeHint(mode, rawInput, candidate.reading)
  );
}
