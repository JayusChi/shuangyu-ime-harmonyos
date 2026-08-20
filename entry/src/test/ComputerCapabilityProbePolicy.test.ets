import { describe, expect, it } from '@ohos/hypium';
import {
  ComputerCandidateRoute,
  ComputerPanelLifecycleResult,
  isComputerCapabilityProbeTarget,
  panelLifecyclePassed,
  resolveComputerCandidateRoute
} from '../main/ets/domain/display/ComputerCapabilityProbePolicy';

function result(passed: boolean): ComputerPanelLifecycleResult {
  return {
    created: passed,
    contentSet: passed,
    resized: passed,
    moved: passed,
    shown: passed,
    hidden: passed,
    reshown: passed,
    clicked: passed,
    focusRetained: passed,
    destroyed: true
  };
}

export default function computerCapabilityProbePolicyTest() {
  describe('computer stage 1 capability probe policy', () => {
    it('activates the isolated probe only on 2in1', 0, () => {
      expect(isComputerCapabilityProbeTarget('2in1')).assertTrue();
      expect(isComputerCapabilityProbeTarget(' 2IN1 ')).assertTrue();
      expect(isComputerCapabilityProbeTarget('tablet')).assertFalse();
      expect(isComputerCapabilityProbeTarget('phone')).assertFalse();
    });

    it('requires click focus and destroy evidence for a passing lifecycle', 0, () => {
      const incomplete = result(true);
      incomplete.focusRetained = false;
      expect(panelLifecyclePassed(incomplete)).assertFalse();
      expect(panelLifecyclePassed(result(true))).assertTrue();
    });

    it('prefers route A and falls back through routes B and C', 0, () => {
      expect(resolveComputerCandidateRoute(result(true), result(true)))
        .assertEqual(ComputerCandidateRoute.CANDIDATE_PANEL);
      expect(resolveComputerCandidateRoute(result(false), result(true)))
        .assertEqual(ComputerCandidateRoute.STATUS_BAR_PANEL);
      expect(resolveComputerCandidateRoute(result(false), result(false)))
        .assertEqual(ComputerCandidateRoute.FIXED_CANDIDATE_STRIP);
    });

    it('does not freeze a route before both failed probes are cleaned up', 0, () => {
      const candidate = result(false);
      const statusBar = result(false);
      statusBar.destroyed = false;
      expect(resolveComputerCandidateRoute(candidate, statusBar)).assertEqual(ComputerCandidateRoute.UNDECIDED);
    });
  });
}
