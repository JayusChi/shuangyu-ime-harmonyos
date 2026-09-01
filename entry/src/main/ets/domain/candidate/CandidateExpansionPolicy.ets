import { KeyboardDeviceFormFactor } from '../display/KeyboardAuxiliaryAreaPolicy';

export enum CandidatePageDirection {
  PREVIOUS = 'previous',
  NEXT = 'next'
}

export interface CandidateExpansionAvailability {
  sessionActive: boolean;
  keyboardVisible: boolean;
  candidateBarVisible: boolean;
  candidateCount: number;
  hasPreviousPage: boolean;
  hasNextPage: boolean;
  pageLoading: boolean;
  hasError: boolean;
}

export interface CandidateExpansionLayout {
  columnCount: number;
  visibleRowCount: number;
  cellHeight: number;
  panelHeight: number;
}

const PANEL_CHROME_HEIGHT: number = 76;
export const MIN_CANDIDATES_FOR_EXPANSION: number = 3;

export function canExpandCandidates(state: CandidateExpansionAvailability): boolean {
  return state.sessionActive &&
    state.keyboardVisible &&
    state.candidateBarVisible &&
    state.candidateCount >= MIN_CANDIDATES_FOR_EXPANSION &&
    !state.hasError;
}

export function canNavigateCandidatePage(
  state: CandidateExpansionAvailability,
  direction: CandidatePageDirection
): boolean {
  const hasOpenPanelContent = state.sessionActive &&
    state.keyboardVisible &&
    state.candidateBarVisible &&
    state.candidateCount > 0 &&
    !state.hasError;
  if (!hasOpenPanelContent || state.pageLoading) {
    return false;
  }
  return direction === CandidatePageDirection.PREVIOUS
    ? state.hasPreviousPage
    : state.hasNextPage;
}

/**
 * Stage 2 layout contract. Only the current engine page is rendered.
 * Pad exposes 10 x 5 cells so the formal 50-item page fits on one screen.
 */
export function resolveCandidateExpansionLayout(
  formFactor: KeyboardDeviceFormFactor,
  isLandscape: boolean
): CandidateExpansionLayout {
  if (formFactor === KeyboardDeviceFormFactor.TABLET) {
    return {
      columnCount: 10,
      visibleRowCount: 5,
      cellHeight: 44,
      panelHeight: PANEL_CHROME_HEIGHT + (5 * 44)
    };
  }
  if (isLandscape) {
    return {
      columnCount: 8,
      visibleRowCount: 3,
      cellHeight: 42,
      panelHeight: PANEL_CHROME_HEIGHT + (3 * 42)
    };
  }
  return {
    columnCount: 5,
    visibleRowCount: 4,
    cellHeight: 44,
    panelHeight: PANEL_CHROME_HEIGHT + (4 * 44)
  };
}

export function candidateGridColumnsTemplate(columnCount: number): string {
  const columns: string[] = [];
  for (let index = 0; index < Math.max(1, columnCount); index += 1) {
    columns.push('1fr');
  }
  return columns.join(' ');
}
