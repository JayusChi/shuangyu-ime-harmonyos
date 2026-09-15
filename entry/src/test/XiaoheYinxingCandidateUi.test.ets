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
import { toContextualCandidateDisplayItem } from '../main/ets/domain/candidate/CandidateDisplayItem';

function candidate(id: string, text: string, reading: string, source: string = 'core'): Candidate {
  return { id: id, text: text, reading: reading, source: source };
}

export default function xiaoheYinxingCandidateUiTest() {
  describe('xiaohe yinxing precise match stage 3 candidate UI', () => {
    it('convenience candidates keep both formats and use convenience empty guidance', 0, () => {
      for (const mode of [CandidateUiMode.BROWSABLE, CandidateUiMode.PRECISE_MATCH]) {
        const values = [candidate('q0', '2026年5月5日', '=2026.5.5', 'convenience'),
          candidate('q1', '2026-05-05', '=2026.5.5', 'convenience')];
        expect(resolveVisibleCandidates(mode, '=2026.5.5', values).length).assertEqual(2);
        expect(resolveCandidateEmptyFeedback(mode, '=').text).assertEqual('数字、日期、算式或英文');
        expect(resolveCandidateEmptyFeedback(mode, '=1/0').text).assertEqual('请继续输入或检查格式');
      }
    });

    it('routes shuangpin and yinxing by stable scheme ID', 0, () => {
      expect(resolveCandidateUiMode('xiaohe')).assertEqual(CandidateUiMode.BROWSABLE);
      expect(resolveCandidateUiMode('xiaohe-yinxing')).assertEqual(CandidateUiMode.PRECISE_MATCH);
      expect(resolveCandidateUiMode('unknown')).assertEqual(CandidateUiMode.BROWSABLE);
    });

    it('requires three candidates and allows every precise-mode result to expand', 0, () => {
      expect(allowsCandidateBrowsing(CandidateUiMode.BROWSABLE)).assertTrue();
      expect(shouldShowCandidateExpansionAction(CandidateUiMode.BROWSABLE, 50)).assertTrue();
      expect(shouldShowCandidateExpansionAction(CandidateUiMode.BROWSABLE, 2)).assertFalse();
      expect(allowsCandidateBrowsing(CandidateUiMode.PRECISE_MATCH)).assertTrue();
      expect(allowsCandidateBrowsing(CandidateUiMode.PRECISE_MATCH, 'obh')).assertTrue();
      expect(allowsCandidateBrowsing(CandidateUiMode.PRECISE_MATCH, 'ju`')).assertTrue();
      expect(shouldShowCandidateExpansionAction(CandidateUiMode.PRECISE_MATCH, 4, 'obh', 3)).assertTrue();
      expect(shouldShowCandidateExpansionAction(CandidateUiMode.PRECISE_MATCH, 2, 'obh')).assertFalse();
      expect(shouldShowCandidateExpansionAction(CandidateUiMode.PRECISE_MATCH, 2, 'ju`')).assertFalse();
      expect(shouldShowCandidateExpansionAction(CandidateUiMode.PRECISE_MATCH, 3, 'ju`', 2)).assertTrue();
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
        CandidateUiMode.PRECISE_MATCH, 'un', candidates
      ).map((candidate) => candidate.text).join('|')).assertEqual('伤脑筋');
    });

    it('shares continuation hint display text across bar, floating and pad candidate surfaces', 0, () => {
      expect(toContextualCandidateDisplayItem(
        candidate('name', '那么', 'name'),
        0,
        CandidateUiMode.PRECISE_MATCH,
        'nam'
      ).displayText).assertEqual('那么 e');
      expect(toContextualCandidateDisplayItem(
        candidate('unuq', '熟能生巧', 'unuq'),
        0,
        CandidateUiMode.PRECISE_MATCH,
        'un'
      ).displayText).assertEqual('熟能生巧 uq');
      expect(toContextualCandidateDisplayItem(
        candidate('name', '那么', 'name'),
        0,
        CandidateUiMode.BROWSABLE,
        'nam'
      ).displayText).assertEqual('那么');
    });

    it('renders a direct-word label with the remaining code but keeps clean commit text', 0, () => {
      const direct: Candidate = {
        id: 'direct-gwyu',
        text: '给予',
        displayText: '给ʲⁱ̌予',
        reading: 'gwyu',
        source: 'user-lexicon'
      };

      expect(toContextualCandidateDisplayItem(
        direct,
        0,
        CandidateUiMode.PRECISE_MATCH,
        'gwy'
      ).displayText).assertEqual('给ʲⁱ̌予u');
      expect(direct.text).assertEqual('给予');
      expect(resolveCandidateAccessibilityText(
        CandidateUiMode.PRECISE_MATCH,
        'gwy',
        0,
        direct.displayText!,
        direct.reading
      )).assertEqual('精准匹配提示，第 1 个，给ʲⁱ̌予，后续编码 u');
    });

    it('exact candidates remain complete while empty-code hints are fixed to one', 0, () => {
      const mixed: Candidate[] = [
        candidate('exact-1', '精确一', 'un'),
        candidate('exact-2', '精确二', 'un'),
        candidate('hint', '提示', 'unjb')
      ];
      expect(resolveVisibleCandidates(
        CandidateUiMode.PRECISE_MATCH, 'un', mixed
      ).map((item: Candidate): string => item.text).join('|')).assertEqual('精确一|精确二');

      const hints: Candidate[] = [];
      for (let index = 0; index < 12; index += 1) {
        hints.push(candidate(`${index}`, `提示${index}`, `un${index}x`));
      }
      expect(resolveVisibleCandidates(
        CandidateUiMode.PRECISE_MATCH, 'un', hints
      ).length).assertEqual(1);
    });

    it('matches guide candidates after removing the protocol-only semicolon prefix', 0, () => {
      const guideCandidates: Candidate[] = [
        candidate('action:repeat-commit', '重复', 'f', 'functional')
      ];

      const visible = resolveVisibleCandidates(
        CandidateUiMode.PRECISE_MATCH, ';f', guideCandidates
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
        CandidateUiMode.PRECISE_MATCH, ';q', [quickSymbol]
      )[0].id).assertEqual('quick:q');

      const guideDefault = candidate('quick:_', '：', '_', 'quick-symbol');
      expect(resolveVisibleCandidates(
        CandidateUiMode.PRECISE_MATCH, ';', [guideDefault]
      )[0].text).assertEqual('：');
    });

    it('keeps every Rust-filtered universal-key candidate visible', 0, () => {
      const wildcardCandidates: Candidate[] = [
        candidate('universal-1', '坎', 'kjtv'),
        candidate('universal-2', '阔', 'kjmw'),
        candidate('universal-3', '冕', 'kjrl')
      ];

      expect(resolveVisibleCandidates(
        CandidateUiMode.PRECISE_MATCH, 'kj``', wildcardCandidates
      ).map((item: Candidate): string => item.text).join('|')).assertEqual('坎|阔|冕');
      expect(resolveVisibleCandidates(
        CandidateUiMode.PRECISE_MATCH, '``an', wildcardCandidates
      ).length).assertEqual(3);
      expect(resolveCandidateCodeHint(
        CandidateUiMode.PRECISE_MATCH, 'kj``', 'kjtv'
      )).assertEqual('tv');
      expect(toContextualCandidateDisplayItem(
        wildcardCandidates[0], 0, CandidateUiMode.PRECISE_MATCH, 'kj``'
      ).displayText).assertEqual('坎 tv');
      expect(resolveCandidateAccessibilityText(
        CandidateUiMode.PRECISE_MATCH, 'kj``', 0, '坎', 'kjtv'
      )).assertEqual('万能键候选，第 1 个，坎，实际编码 tv');
    });
  });
}
