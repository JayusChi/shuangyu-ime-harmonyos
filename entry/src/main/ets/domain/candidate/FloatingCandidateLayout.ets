export interface FloatingCandidateLayoutInput {
  candidateLabels: string[];
  candidateFontSizeVp: number;
  pageStatus: string;
}

export const FLOATING_CANDIDATE_MIN_WIDTH_VP: number = 60;
export const FLOATING_CANDIDATE_HORIZONTAL_PADDING_VP: number = 6;
export const FLOATING_CANDIDATE_ITEM_GAP_VP: number = 6;
export const FLOATING_CANDIDATE_ITEM_HORIZONTAL_PADDING_VP: number = 10;

function estimatedTextWidthVp(text: string, fontSizeVp: number): number {
  let width = 0;
  for (let index = 0; index < text.length; index += 1) {
    const code = text.charCodeAt(index);
    if (code === 0x20) {
      width += fontSizeVp * 0.16;
    } else if (code >= 0x30 && code <= 0x39) {
      width += fontSizeVp * 0.48;
    } else if ((code >= 0x41 && code <= 0x5a) || (code >= 0x61 && code <= 0x7a)) {
      width += fontSizeVp * 0.58;
    } else if (code <= 0x7f) {
      width += fontSizeVp * 0.22;
    } else {
      // CJK glyphs occupy the full em. Shrinking them along with the narrow
      // numeric prefix keeps short pages compact but under-sizes long Chinese
      // candidates, which can clip item seven even when the screen has room.
      width += fontSizeVp;
    }
  }
  return width;
}

/**
 * Mirrors FloatingCandidateRoot spacing closely enough to size the system panel
 * before ArkUI content exists. Only rendered candidates participate: the raw
 * composition is already visible in the host editor and must not reserve space.
 */
export function estimateFloatingCandidateWidthVp(input: FloatingCandidateLayoutInput): number {
  const outerPaddingAndBorder = FLOATING_CANDIDATE_HORIZONTAL_PADDING_VP * 2 + 2;
  const candidateHorizontalPadding = FLOATING_CANDIDATE_ITEM_HORIZONTAL_PADDING_VP * 2;
  let width = outerPaddingAndBorder;

  input.candidateLabels.forEach((label: string, index: number): void => {
    if (index > 0) {
      width += FLOATING_CANDIDATE_ITEM_GAP_VP;
    }
    width += candidateHorizontalPadding + estimatedTextWidthVp(label, input.candidateFontSizeVp);
  });

  if (input.pageStatus.length > 0) {
    if (input.candidateLabels.length > 0) {
      width += FLOATING_CANDIDATE_ITEM_GAP_VP;
    }
    width += estimatedTextWidthVp(input.pageStatus, 12);
  }

  // Do not clip the estimate to a fixed panel width: the controller already
  // clamps the final physical size to the current screen safe area. Returning
  // the full rendered-content width lets all seven candidates participate in
  // sizing instead of hiding the last item behind a historical 560vp cap.
  return Math.max(FLOATING_CANDIDATE_MIN_WIDTH_VP, width);
}
