export enum ComputerCandidateRoute {
  CANDIDATE_PANEL = 'ROUTE_A_CANDIDATE_PANEL',
  STATUS_BAR_PANEL = 'ROUTE_B_STATUS_BAR_PANEL',
  FIXED_CANDIDATE_STRIP = 'ROUTE_C_FIXED_CANDIDATE_STRIP',
  UNDECIDED = 'UNDECIDED'
}

export interface ComputerPanelLifecycleResult {
  created: boolean;
  contentSet: boolean;
  resized: boolean;
  moved: boolean;
  shown: boolean;
  hidden: boolean;
  reshown: boolean;
  clicked: boolean;
  focusRetained: boolean;
  destroyed: boolean;
}

/**
 * Stage 1 freezes a route only after the complete lifecycle has been observed.
 * A successful `createPanel` call alone is deliberately insufficient.
 */
export function panelLifecyclePassed(result: ComputerPanelLifecycleResult): boolean {
  return result.created && result.contentSet && result.resized && result.moved && result.shown &&
    result.hidden && result.reshown && result.clicked && result.focusRetained && result.destroyed;
}

export function resolveComputerCandidateRoute(
  candidate: ComputerPanelLifecycleResult,
  statusBar: ComputerPanelLifecycleResult
): ComputerCandidateRoute {
  if (panelLifecyclePassed(candidate)) {
    return ComputerCandidateRoute.CANDIDATE_PANEL;
  }
  if (panelLifecyclePassed(statusBar)) {
    return ComputerCandidateRoute.STATUS_BAR_PANEL;
  }
  if (candidate.destroyed && statusBar.destroyed) {
    return ComputerCandidateRoute.FIXED_CANDIDATE_STRIP;
  }
  return ComputerCandidateRoute.UNDECIDED;
}

export function isComputerCapabilityProbeTarget(deviceType: string): boolean {
  return deviceType.trim().toLowerCase() === '2in1';
}
