import { describe, expect, it } from '@ohos/hypium';
import {
  allowsCandidateBrowsing,
  CandidateUiMode,
  isPreciseMatchHintCandidate,
  resolveCandidateCodeHint,
  resolveCandidateAccessibilityText,
  resolveCandidateEmptyFeedback,
  resolveCandidateUiMode,
  resolveVisibleCandidates,
  shouldShowCandidateExpansionAction
} from '../main/ets/domain/candidate/CandidateUiPolicy';
import { Candidate } from '../main/ets/infrastructure/native/NativeEngineTypes';

function candidate(id: string, text: string, reading: string, source: string = 'core'): Candidate {
  return { id: id, text: text, reading: reading, source: source };
}

export default function xiaoheYinxingCandidateUiTest() {
  describe('xiaohe yinxing precise match stage 3 candidate UI', () => {
    it('routes shuangpin and yinxing by stable scheme ID', 0, () => {
      expect(resolveCandidateUiMode('xiaohe')).assertEqual(CandidateUiMode.BROWSABLE);
      expect(resolveCandidateUiMode('xiaohe-yinxing')).assertEqual(CandidateUiMode.PRECISE_MATCH);
      expect(resolveCandidateUiMode('unknown')).assertEqual(CandidateUiMode.BROWSABLE);
    });

    it('keeps shuangpin expansion and hides it for precise match candidates', 0, () => {
      expect(allowsCandidateBrowsing(CandidateUiMode.BROWSABLE)).assertTrue();
      expect(shouldShowCandidateExpansionAction(CandidateUiMode.BROWSABLE, 50)).assertTrue();
      expect(shouldShowCandidateExpansionAction(CandidateUiMode.BROWSABLE, 0)).assertFalse();
      expect(allowsCandidateBrowsing(CandidateUiMode.PRECISE_MATCH)).assertFalse();
      expect(shouldShowCandidateExpansionAction(CandidateUiMode.PRECISE_MATCH, 3)).assertFalse();
    });

    it('describes recoverable empty precise states without creating candidates', 0, () => {
      const partial = resolveCandidateEmptyFeedback(CandidateUiMode.PRECISE_MATCH, 'bml');
      expect(partial.visible).assertTrue();
      expect(partial.text).assertEqual('继续输入形码');
      expect(partial.accessibilityText.indexOf('3 码') >= 0).assertTrue();

      const full = resolveCandidateEmptyFeedback(CandidateUiMode.PRECISE_MATCH, 'zzzz');
      expect(full.visible).assertTrue();
      expect(full.text).assertEqual('无匹配全码');
      expect(full.accessibilityText).assertEqual('当前完整码没有匹配候选，可退格修改');

      expect(resolveCandidateEmptyFeedback(CandidateUiMode.BROWSABLE, 'h').visible).assertFalse();
      expect(resolveCandidateEmptyFeedback(CandidateUiMode.PRECISE_MATCH, '').visible).assertFalse();
    });

    it('announces exact short codes and full-code duplicates distinctly', 0, () => {
      expect(resolveCandidateAccessibilityText(
        CandidateUiMode.PRECISE_MATCH, 'ni', 0, '你', 'ni'
      )).assertEqual('精确简码候选，第 1 个，你');
      expect(resolveCandidateAccessibilityText(
        CandidateUiMode.PRECISE_MATCH, 'bmbm', 1, '辩', 'bmbm'
      )).assertEqual('完整码候选，第 2 个，辩');
      expect(resolveCandidateAccessibilityText(
        CandidateUiMode.BROWSABLE, 'h', 0, '和', 'he'
      )).assertEqual('第 1 个候选，和');
    });

    it('renders source-ordered prefix hints with only the remaining code', 0, () => {
      const candidates: Candidate[] = [
        candidate('1', '伤脑筋', 'unjb'),
        candidate('2', '施耐庵', 'unan'),
        candidate('3', '史努比', 'unbi')
      ];
      expect(isPreciseMatchHintCandidate(
        CandidateUiMode.PRECISE_MATCH, 'un', candidates[0]
      )).assertTrue();
      expect(resolveCandidateCodeHint(
        CandidateUiMode.PRECISE_MATCH, 'un', 'unjb'
      )).assertEqual('jb');
      expect(resolveCandidateAccessibilityText(
        CandidateUiMode.PRECISE_MATCH, 'un', 0, '伤脑筋', 'unjb'
      )).assertEqual('精准匹配提示，第 1 个，伤脑筋，后续编码 jb');
      expect(resolveVisibleCandidates(
        CandidateUiMode.PRECISE_MATCH, 'un', candidates, 2
      ).map((candidate) => candidate.text).join('|')).assertEqual('伤脑筋|施耐庵');
    });

    it('exact candidates lock the branch and hint count clamps to one through nine', 0, () => {
      const mixed: Candidate[] = [
        candidate('exact', '精确', 'un'),
        candidate('hint', '提示', 'unjb')
      ];
      expect(resolveVisibleCandidates(
        CandidateUiMode.PRECISE_MATCH, 'un', mixed, 9
      ).length).assertEqual(1);
      expect(resolveVisibleCandidates(
        CandidateUiMode.PRECISE_MATCH, 'un', mixed, 9
      )[0].text).assertEqual('精确');

      const hints: Candidate[] = [];
      for (let index = 0; index < 12; index += 1) {
        hints.push(candidate(`${index}`, `提示${index}`, `un${index}x`));
      }
      expect(resolveVisibleCandidates(
        CandidateUiMode.PRECISE_MATCH, 'un', hints, 99
      ).length).assertEqual(9);
      expect(resolveVisibleCandidates(
        CandidateUiMode.PRECISE_MATCH, 'un', hints, 0
      ).length).assertEqual(1);
    });

    it('matches guide candidates after removing the protocol-only semicolon prefix', 0, () => {
      const guideCandidates: Candidate[] = [
        candidate('action:repeat-commit', '重复', 'f', 'functional')
      ];

      const visible = resolveVisibleCandidates(
        CandidateUiMode.PRECISE_MATCH, ';f', guideCandidates, 9
      );

      expect(visible.length).assertEqual(1);
      expect(visible[0].text).assertEqual('重复');
      expect(resolveCandidateAccessibilityText(
        CandidateUiMode.PRECISE_MATCH, ';f', 0, '重复', 'f'
      )).assertEqual('引导候选，第 1 个，重复');
      expect(resolveCandidateEmptyFeedback(CandidateUiMode.PRECISE_MATCH, ';z').text)
        .assertEqual('无匹配引导项');

      const quickSymbol = candidate('quick:q', '：“', 'q', 'quick-symbol');
      expect(resolveVisibleCandidates(
        CandidateUiMode.PRECISE_MATCH, ';q', [quickSymbol], 9
      )[0].id).assertEqual('quick:q');
    });
  });
}
