import { describe, expect, it } from '@ohos/hypium';
import {
  InputPresentationMode,
  InputPresentationPreference,
  resolveInputPresentationMode
} from '../main/ets/domain/display/InputPresentationMode';
import {
  estimateFloatingCandidateWidthVp,
  resolveFloatingCandidateExpansionLayout, floatingCandidateExpandedWidthVp,
  floatingCandidateRevealOffset,
  floatingCandidateItemPaddingVp,
  shouldShowFloatingCandidatePager,
  floatingCandidateCardHeightVp,
  FLOATING_CANDIDATE_SHADOW_RADIUS_VP,
  FLOATING_CANDIDATE_SHADOW_OFFSET_Y_VP,
  FLOATING_CANDIDATE_SHADOW_INSET_VP,
  FLOATING_CANDIDATE_ITEM_GAP_VP,
  FLOATING_CANDIDATE_ITEM_HORIZONTAL_PADDING_VP,
  FLOATING_CANDIDATE_ITEM_VERTICAL_PADDING_VP,
  FLOATING_CANDIDATE_ITEM_WIDTH_SAFETY_VP,
  FLOATING_CANDIDATE_MIN_WIDTH_VP,
  FLOATING_CANDIDATE_PAGER_WIDTH_VP,
  FLOATING_CANDIDATE_SELECTED_HORIZONTAL_PADDING_VP,
  FLOATING_CANDIDATE_SELECTED_VERTICAL_PADDING_VP
} from '../main/ets/domain/candidate/FloatingCandidateLayout';
import {
  copyImeSettings,
  EffectiveTheme,
  DEFAULT_IME_SETTINGS,
  settingsToRaw
} from '../main/ets/domain/settings/ImeSettings';
import { SettingsValidator } from '../main/ets/infrastructure/storage/SettingsValidator';
import { KeyboardThemeResolver } from '../main/ets/presentation/keyboard/design/KeyboardThemeResolver';

export default function computerStage5Test() {
  describe('computer remediation stage 5 product mode and compact candidate layout', () => {
    it('fits five hardware candidates and preedit inside the phone safe width', 0, () => {
      const labels = ['ui', '1. 是', '2. 时', '3. 事', '4. 使', '5. 市'];
      const hardware = estimateFloatingCandidateWidthVp({ candidateLabels: labels,
        candidateFontSizeVp: 17, pageStatus: '第 1 页', hardwareCandidatePaging: true,
        screenWidthVp: 377, preeditLabelCount: 1 });
      expect(hardware <= 377 - 16).assertTrue();
      const touch = estimateFloatingCandidateWidthVp({ candidateLabels: labels,
        candidateFontSizeVp: 17, pageStatus: '第 1 页', screenWidthVp: 377, preeditLabelCount: 1 });
      expect(touch - hardware).assertEqual(108 + 6 + 5 * 14);
      const nextPage = estimateFloatingCandidateWidthVp({ candidateLabels: labels,
        candidateFontSizeVp: 17, pageStatus: '第 100 页', hardwareCandidatePaging: true,
        screenWidthVp: 377, preeditLabelCount: 1 });
      expect(nextPage).assertEqual(hardware);
    });

    it('keeps touch paging and desktop spacing while compacting phone hardware candidates', 0, () => {
      expect(shouldShowFloatingCandidatePager(true, '第 2 页')).assertFalse();
      expect(shouldShowFloatingCandidatePager(false, '第 2 页')).assertTrue();
      expect(shouldShowFloatingCandidatePager(false, '')).assertFalse();
      expect(floatingCandidateItemPaddingVp(true, 377, false)).assertEqual(3);
      expect(floatingCandidateItemPaddingVp(true, 377, true)).assertEqual(7);
      expect(floatingCandidateItemPaddingVp(false, 377, false)).assertEqual(10);
      expect(floatingCandidateItemPaddingVp(true, 1642, true)).assertEqual(14);
    });

    it('reserves room for a soft shadow and large single-line candidate text', 0, () => {
      expect(FLOATING_CANDIDATE_SHADOW_INSET_VP >=
        FLOATING_CANDIDATE_SHADOW_RADIUS_VP + FLOATING_CANDIDATE_SHADOW_OFFSET_Y_VP).assertTrue();
      for (let font = 12; font <= 32; font += 1) {
        expect(floatingCandidateCardHeightVp(font) >=
          Math.ceil(font * 1.4) + 2 * FLOATING_CANDIDATE_SELECTED_VERTICAL_PADDING_VP + 12).assertTrue();
      }
    });

    it('uses white and dark floating cards without modifying the fixed keyboard palettes', 0, () => {
      const resolver = new KeyboardThemeResolver();
      const fixedLight = resolver.resolve(EffectiveTheme.LIGHT).candidateBackground;
      const fixedDark = resolver.resolve(EffectiveTheme.DARK).candidateBackground;
      const light = resolver.resolveFloatingCandidates(EffectiveTheme.LIGHT);
      const dark = resolver.resolveFloatingCandidates(EffectiveTheme.DARK);
      expect(light.candidateBackground).assertEqual('#FFFFFF');
      expect(light.functionKeyBackground === light.candidateBackground).assertFalse();
      expect(dark.useDarkMedia).assertTrue();
      expect(dark.candidateText === light.candidateText).assertFalse();
      expect(resolver.resolve(EffectiveTheme.LIGHT).candidateBackground).assertEqual(fixedLight);
      expect(resolver.resolve(EffectiveTheme.DARK).candidateBackground).assertEqual(fixedDark);
    });

    it('reserves the expand button and adapts expanded columns to a narrow screen', 0, () => {
      const collapsed = estimateFloatingCandidateWidthVp({ candidateLabels: ['1. 看'], candidateFontSizeVp: 17, pageStatus: '' });
      const expandable = estimateFloatingCandidateWidthVp({ candidateLabels: ['1. 看'], candidateFontSizeVp: 17, pageStatus: '', expandActionVisible: true });
      expect(expandable - collapsed).assertEqual(54);
      const phone = resolveFloatingCandidateExpansionLayout(320, 50, 17);
      const pad = resolveFloatingCandidateExpansionLayout(1000, 50, 17);
      expect(phone.columnCount < pad.columnCount).assertTrue();
      expect(phone.visibleRowCount).assertEqual(5);
      expect(floatingCandidateExpandedWidthVp(320)).assertEqual(304);
      expect(floatingCandidateExpandedWidthVp(1000)).assertEqual(560);
    });

    it('AUTO follows the 2in1 and Tablet alphabetic-keyboard product rule', 0, () => {
      expect(resolveInputPresentationMode(InputPresentationPreference.AUTO, '2in1', false))
        .assertEqual(InputPresentationMode.HARDWARE);
      expect(resolveInputPresentationMode(InputPresentationPreference.AUTO, 'tablet', false))
        .assertEqual(InputPresentationMode.TOUCH);
      expect(resolveInputPresentationMode(InputPresentationPreference.AUTO, 'tablet', true))
        .assertEqual(InputPresentationMode.HARDWARE);
      expect(resolveInputPresentationMode(InputPresentationPreference.AUTO, 'phone', true))
        .assertEqual(InputPresentationMode.HARDWARE);
      expect(resolveInputPresentationMode(InputPresentationPreference.AUTO, 'phone', false))
        .assertEqual(InputPresentationMode.TOUCH);
    });

    it('explicit presentation preferences override the AUTO device rule', 0, () => {
      expect(resolveInputPresentationMode(InputPresentationPreference.TOUCH, '2in1', true))
        .assertEqual(InputPresentationMode.TOUCH);
      expect(resolveInputPresentationMode(InputPresentationPreference.HARDWARE, 'phone', false))
        .assertEqual(InputPresentationMode.HARDWARE);
    });

    it('persists and validates the three input-presentation preferences', 0, () => {
      const settings = copyImeSettings(DEFAULT_IME_SETTINGS);
      settings.inputPresentationPreference = InputPresentationPreference.TOUCH;
      expect(settingsToRaw(settings).inputPresentationPreference)
        .assertEqual(InputPresentationPreference.TOUCH);
      const validator = new SettingsValidator();
      expect(validator.validate({ inputPresentationPreference: InputPresentationPreference.HARDWARE })
        .inputPresentationPreference).assertEqual(InputPresentationPreference.HARDWARE);
      expect(validator.validate({ inputPresentationPreference: 'invalid' }).inputPresentationPreference)
        .assertEqual(InputPresentationPreference.AUTO);
      settings.inputPresentationPreference = InputPresentationPreference.AUTO;
      const restored = validator.validate(settingsToRaw(settings));
      expect(restored.inputPresentationPreference).assertEqual(InputPresentationPreference.AUTO);
      expect(resolveInputPresentationMode(restored.inputPresentationPreference, 'phone', true))
        .assertEqual(InputPresentationMode.HARDWARE);
      expect(resolveInputPresentationMode(restored.inputPresentationPreference, 'phone', false))
        .assertEqual(InputPresentationMode.TOUCH);
    });

    it('candidate window grows with rendered candidate count and not raw composition', 0, () => {
      expect(FLOATING_CANDIDATE_ITEM_WIDTH_SAFETY_VP).assertEqual(4);
      const one = estimateFloatingCandidateWidthVp({
        candidateLabels: ['1. 是'],
        candidateFontSizeVp: 14,
        pageStatus: ''
      });
      const two = estimateFloatingCandidateWidthVp({
        candidateLabels: ['1. 是', '2. 所有'],
        candidateFontSizeVp: 14,
        pageStatus: ''
      });
      expect(one >= FLOATING_CANDIDATE_MIN_WIDTH_VP).assertTrue();
      expect(two > one).assertTrue();
      expect(two < 280).assertTrue();
    });

    it('gives the highlighted floating candidate a larger background target', 0, () => {
      expect(FLOATING_CANDIDATE_SELECTED_HORIZONTAL_PADDING_VP >
        FLOATING_CANDIDATE_ITEM_HORIZONTAL_PADDING_VP).assertTrue();
      expect(FLOATING_CANDIDATE_SELECTED_VERTICAL_PADDING_VP >
        FLOATING_CANDIDATE_ITEM_VERTICAL_PADDING_VP).assertTrue();
    });

    it('reserves a visible pager beside a multipage floating candidate row', 0, () => {
      const onePage = estimateFloatingCandidateWidthVp({
        candidateLabels: ['1. 是', '2. 所有'],
        candidateFontSizeVp: 14,
        pageStatus: ''
      });
      const multiplePages = estimateFloatingCandidateWidthVp({
        candidateLabels: ['1. 是', '2. 所有'],
        candidateFontSizeVp: 14,
        pageStatus: '第 1 页'
      });
      expect(multiplePages - onePage)
        .assertEqual(FLOATING_CANDIDATE_ITEM_GAP_VP + FLOATING_CANDIDATE_PAGER_WIDTH_VP);
    });

    it('candidate window includes the full rendered width for long candidate pages', 0, () => {
      const width = estimateFloatingCandidateWidthVp({
        candidateLabels: [
          '1. 这是一个非常长的候选词',
          '2. 这是另一个非常长的候选词',
          '3. 这是第三个非常长的候选词'
        ],
        candidateFontSizeVp: 17,
        pageStatus: '第 12 页'
      });
      expect(width > 560).assertTrue();
    });

    it('does not reserve oversized side gutters for seven short candidates', 0, () => {
      const width = estimateFloatingCandidateWidthVp({
        candidateLabels: ['1. 今天', '2. 尽头', '3. 津贴', '4. 紧贴', '5. 劲头', '6. 金条', '7. 进退'],
        candidateFontSizeVp: 14,
        pageStatus: ''
      });
      expect(width > 400).assertTrue();
      expect(width - FLOATING_CANDIDATE_SHADOW_INSET_VP * 2 < 520).assertTrue();
    });

    it('uses measured font widths without rounding down the final candidate or shadow', 0, () => {
      const measured = estimateFloatingCandidateWidthVp({
        candidateLabels: ['1. WWW', '2. 查'], candidateFontSizeVp: 17, pageStatus: '',
        measuredTextWidthsVp: [95.3, 41.8]
      });
      const expected = 2 * FLOATING_CANDIDATE_SHADOW_INSET_VP + 14 + 96 + 42 +
        2 * (FLOATING_CANDIDATE_ITEM_HORIZONTAL_PADDING_VP * 2 + FLOATING_CANDIDATE_ITEM_WIDTH_SAFETY_VP) +
        FLOATING_CANDIDATE_ITEM_GAP_VP + 8;
      expect(measured).assertEqual(expected);
      const fallback = estimateFloatingCandidateWidthVp({
        candidateLabels: ['1. 查'], candidateFontSizeVp: 17, pageStatus: '', measuredTextWidthsVp: [Number.NaN]
      });
      expect(Number.isFinite(fallback)).assertTrue();
    });

    it('reveals the rightmost highlighted candidate and brings the first one back into view', 0, () => {
      expect(floatingCandidateRevealOffset(300, 0, 340, 92)).assertEqual(132);
      expect(floatingCandidateRevealOffset(300, 132, 0, 92)).assertEqual(0);
      expect(floatingCandidateRevealOffset(300, 0, 90, 92)).assertEqual(0);
      expect(floatingCandidateRevealOffset(300, 0, 90, 500)).assertEqual(90);
    });

    it('keeps all seven longer Chinese candidates inside the adaptive window', 0, () => {
      const width = estimateFloatingCandidateWidthVp({
        candidateLabels: [
          '1. 今天是个',
          '2. 今天是各',
          '3. 今天是格',
          '4. 今天是歌',
          '5. 今天是哥',
          '6. 今天是割',
          '7. 今天是给'
        ],
        candidateFontSizeVp: 14,
        pageStatus: ''
      });
      expect(width > 640).assertTrue();
    });
  });
}
