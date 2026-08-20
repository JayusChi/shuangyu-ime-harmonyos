import { describe, expect, it } from '@ohos/hypium';
import {
  InputPresentationMode,
  InputPresentationPreference,
  resolveInputPresentationMode
} from '../main/ets/domain/display/InputPresentationMode';
import {
  estimateFloatingCandidateWidthVp,
  FLOATING_CANDIDATE_MIN_WIDTH_VP
} from '../main/ets/domain/candidate/FloatingCandidateLayout';
import {
  copyImeSettings,
  DEFAULT_IME_SETTINGS,
  settingsToRaw
} from '../main/ets/domain/settings/ImeSettings';
import { SettingsValidator } from '../main/ets/infrastructure/storage/SettingsValidator';

export default function computerStage5Test() {
  describe('computer remediation stage 5 product mode and compact candidate layout', () => {
    it('AUTO follows the 2in1 and Tablet alphabetic-keyboard product rule', 0, () => {
      expect(resolveInputPresentationMode(InputPresentationPreference.AUTO, '2in1', false))
        .assertEqual(InputPresentationMode.HARDWARE);
      expect(resolveInputPresentationMode(InputPresentationPreference.AUTO, 'tablet', false))
        .assertEqual(InputPresentationMode.TOUCH);
      expect(resolveInputPresentationMode(InputPresentationPreference.AUTO, 'tablet', true))
        .assertEqual(InputPresentationMode.HARDWARE);
      expect(resolveInputPresentationMode(InputPresentationPreference.AUTO, 'phone', true))
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
    });

    it('candidate window grows with rendered candidate count and not raw composition', 0, () => {
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
      expect(width < 500).assertTrue();
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
