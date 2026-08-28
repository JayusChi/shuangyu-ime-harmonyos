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
  const hasDirectDisplayText = candidate.displayText !== undefined && candidate.displayText.length > 0;
  const candidateText = hasDirectDisplayText ? candidate.displayText! : candidate.text;
  // Direct-word labels flow into the remaining code (`给ʲⁱ̌予u`). Ordinary
  // precise hints retain the established separating space.
  const suffix = codeHint.length > 0 ? `${hasDirectDisplayText ? '' : ' '}${codeHint}` : '';
  return {
    displayText: `${candidateText}${suffix}`,
    accessibilityText: `第 ${index + 1} 个候选，${candidateText}${suffix}`
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
