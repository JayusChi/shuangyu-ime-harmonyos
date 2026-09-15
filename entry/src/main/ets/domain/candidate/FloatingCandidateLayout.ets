import { CLIPBOARD_REVERSE_PASTE_WIDTH } from '../direct/ClipboardReverseLookup';
import { CandidateExpansionLayout } from './CandidateExpansionPolicy';

export interface FloatingCandidateLayoutInput {
  candidateLabels: string[];
  candidateFontSizeVp: number;
  pageStatus: string;
  measuredTextWidthsVp?: number[];
  expandActionVisible?: boolean;
  clipboardReverseVisible?: boolean;
  hardwareCandidatePaging?: boolean;
  screenWidthVp?: number;
  preeditLabelCount?: number;
}

export const FLOATING_CANDIDATE_SHADOW_INSET_VP: number = 24;
export const FLOATING_CANDIDATE_SHADOW_RADIUS_VP: number = 16;
export const FLOATING_CANDIDATE_SHADOW_OFFSET_Y_VP: number = 6;
export const FLOATING_CANDIDATE_CARD_RADIUS_VP: number = 16;
export const FLOATING_CANDIDATE_MIN_WIDTH_VP: number = 60;
export const FLOATING_CANDIDATE_HORIZONTAL_PADDING_VP: number = 6;
export const FLOATING_CANDIDATE_ITEM_GAP_VP: number = 6;
export const FLOATING_CANDIDATE_ITEM_HORIZONTAL_PADDING_VP: number = 10;
export const FLOATING_CANDIDATE_ITEM_VERTICAL_PADDING_VP: number = 5;
export const FLOATING_CANDIDATE_SELECTED_HORIZONTAL_PADDING_VP: number = 14;
export const FLOATING_CANDIDATE_SELECTED_VERTICAL_PADDING_VP: number = 10;
export const FLOATING_CANDIDATE_SELECTED_BORDER_RADIUS_VP: number = 9;
export const FLOATING_CANDIDATE_ITEM_WIDTH_SAFETY_VP: number = 4;
export const FLOATING_CANDIDATE_PAGER_WIDTH_VP: number = 108;
export const FLOATING_CANDIDATE_EXPAND_WIDTH_VP: number = 48;

/** Physical keyboards page with brackets; touch controls must not consume the candidate row. */
export function shouldShowFloatingCandidatePager(hardware: boolean, pageStatus: string): boolean {
  return !hardware && pageStatus.length > 0;
}

/** Keep five short candidates readable on a phone without changing the preedit padding. */
export function floatingCandidateItemPaddingVp(hardware: boolean, screenWidthVp: number, selected: boolean): number {
  const compact = hardware && screenWidthVp > 0 && screenWidthVp < 600;
  return (selected ? FLOATING_CANDIDATE_SELECTED_HORIZONTAL_PADDING_VP
    : FLOATING_CANDIDATE_ITEM_HORIZONTAL_PADDING_VP) - (compact ? 7 : 0);
}

/** Keep a single-row card tall enough for the font and selected-item padding. */
export function floatingCandidateCardHeightVp(fontSizeVp: number): number {
  return Math.max(56, Math.ceil(fontSizeVp * 1.4) + FLOATING_CANDIDATE_SELECTED_VERTICAL_PADDING_VP * 2 + 12);
}

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
  const outerPaddingAndBorder = FLOATING_CANDIDATE_HORIZONTAL_PADDING_VP * 2 + 2 +
    FLOATING_CANDIDATE_SHADOW_INSET_VP * 2;
  const candidateHorizontalPadding = floatingCandidateItemPaddingVp(
    input.hardwareCandidatePaging === true, input.screenWidthVp ?? 0, false) * 2;
  const selectedItemExtraWidth = Math.max(
    0,
    (FLOATING_CANDIDATE_SELECTED_HORIZONTAL_PADDING_VP -
      FLOATING_CANDIDATE_ITEM_HORIZONTAL_PADDING_VP) * 2
  );
  let width = outerPaddingAndBorder;

  input.candidateLabels.forEach((label: string, index: number): void => {
    if (index > 0) {
      width += FLOATING_CANDIDATE_ITEM_GAP_VP;
    }
    const measured = input.measuredTextWidthsVp?.[index];
    const textWidth = measured !== undefined && Number.isFinite(measured) && measured > 0
      ? measured : estimatedTextWidthVp(label, input.candidateFontSizeVp);
    const padding = index < (input.preeditLabelCount ?? 0)
      ? FLOATING_CANDIDATE_ITEM_HORIZONTAL_PADDING_VP * 2 : candidateHorizontalPadding;
    width += padding + FLOATING_CANDIDATE_ITEM_WIDTH_SAFETY_VP + Math.ceil(textWidth);
  });

  // One candidate is highlighted at a time. Its larger horizontal padding is
  // part of the rendered width and must be reserved before the ArkUI panel is
  // created, otherwise the final candidate can be clipped at the safe edge.
  if (input.candidateLabels.length > 0) {
    width += selectedItemExtraWidth;
  }

  if (shouldShowFloatingCandidatePager(input.hardwareCandidatePaging === true, input.pageStatus)) {
    if (input.candidateLabels.length > 0) {
      width += FLOATING_CANDIDATE_ITEM_GAP_VP;
    }
    width += FLOATING_CANDIDATE_PAGER_WIDTH_VP;
  }

  if (input.clipboardReverseVisible) { width += CLIPBOARD_REVERSE_PASTE_WIDTH + FLOATING_CANDIDATE_ITEM_GAP_VP; }

  if (input.expandActionVisible) {
    width += FLOATING_CANDIDATE_EXPAND_WIDTH_VP + FLOATING_CANDIDATE_ITEM_GAP_VP;
  }

  // Do not clip the estimate to a fixed panel width: the controller already
  // clamps the final physical size to the current screen safe area. Returning
  // the full rendered-content width lets all seven candidates participate in
  // sizing instead of hiding the last item behind a historical 560vp cap.
  return Math.ceil(Math.max(FLOATING_CANDIDATE_MIN_WIDTH_VP, width));
}

/** Reveal keyboard-highlighted candidates when the safe screen width requires scrolling. */
export function floatingCandidateRevealOffset(viewport: number, offset: number, left: number, width: number): number {
  if (viewport <= 0 || !Number.isFinite(left) || !Number.isFinite(width)) { return offset; }
  if (left < offset || width > viewport) { return Math.max(0, left); }
  return left + width > offset + viewport ? Math.max(0, left + width - viewport) : offset;
}

export function floatingCandidateExpandedWidthVp(screenWidthVp: number): number {
  return Math.max(FLOATING_CANDIDATE_MIN_WIDTH_VP, Math.min(560, screenWidthVp - 16));
}

export function resolveFloatingCandidateExpansionLayout(
  screenWidthVp: number, candidateCount: number, fontSizeVp: number
): CandidateExpansionLayout {
  const contentWidth = floatingCandidateExpandedWidthVp(screenWidthVp) - FLOATING_CANDIDATE_SHADOW_INSET_VP * 2 - 16;
  const columnCount = Math.max(1, Math.min(6, Math.floor(contentWidth / Math.max(80, fontSizeVp * 4))));
  const visibleRowCount = Math.max(1, Math.min(5, Math.ceil(candidateCount / columnCount)));
  const cellHeight = Math.max(44, fontSizeVp + 28);
  return { columnCount, visibleRowCount, cellHeight, panelHeight: visibleRowCount * (cellHeight + 4) + 76 };
}
