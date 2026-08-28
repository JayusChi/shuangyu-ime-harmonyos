import { describe, expect, it } from '@ohos/hypium';
import { createUnknownEditorContext, ShiftState } from '../main/ets/domain/editor/EditorContext';
import {
  KeyboardActionType,
  KeyboardMode
} from '../main/ets/domain/keyboard/KeyboardAction';
import {
  CandidatePunctuationResolutionType,
  resolveCandidatePunctuation
} from '../main/ets/domain/keyboard/CandidatePunctuationPolicy';
import {
  copyImeSettings,
  DEFAULT_IME_SETTINGS,
  settingsToRaw
} from '../main/ets/domain/settings/ImeSettings';
import { SettingsValidator } from '../main/ets/infrastructure/storage/SettingsValidator';
import { createStage10KeyboardLayout } from '../main/ets/presentation/keyboard/layouts/Stage10KeyboardLayouts';
import { KEYBOARD_STATUS_BAR_LAYOUT } from '../main/ets/presentation/candidate/CandidateBar';
import {
  calculateTotalKeyboardHeight,
  KEYBOARD_LIFT_LAYER_HEIGHT,
  PORTRAIT_METRICS
} from '../main/ets/presentation/keyboard/design/KeyboardMetrics';

export default function keyboardLiftLayerTest() {
  describe('KeyboardLiftLayer', () => {
    it('uses one ϟ12 entry and places comma and period around space', 0, () => {
      const layout = createStage10KeyboardLayout(
        KeyboardMode.CHINESE,
        createUnknownEditorContext(),
        ShiftState.LOWERCASE
      );
      const bottom = layout.rows[layout.rows.length - 1].keys;
      expect(bottom.map((key) => key.id).join(','))
        .assertEqual('number,punctuation-comma,space,punctuation-period,enter');
      expect(bottom[0].label).assertEqual('ϟ12');
      expect(bottom[0].action.type).assertEqual(KeyboardActionType.TOGGLE_NUMBER);
      expect(bottom[0].longPressAction?.type).assertEqual(KeyboardActionType.TOGGLE_SYMBOL);
      expect(bottom[1].action.type).assertEqual(KeyboardActionType.THIRD_CANDIDATE_OR_COMMA);
      expect(bottom[3].action.type).assertEqual(KeyboardActionType.SECOND_CANDIDATE_OR_PERIOD);
    });

    it('keeps auxiliary returns at the lower-left position', 0, () => {
      const context = createUnknownEditorContext();
      const number = createStage10KeyboardLayout(KeyboardMode.NUMBER, context, ShiftState.LOWERCASE);
      const symbol = createStage10KeyboardLayout(KeyboardMode.SYMBOL, context, ShiftState.LOWERCASE);
      expect(number.rows[number.rows.length - 1].keys[0].id).assertEqual('number-return');
      expect(symbol.rows[symbol.rows.length - 1].keys[0].id).assertEqual('symbol-return');
    });

    it('resolves second and third candidate shortcuts with safe punctuation fallback', 0, () => {
      expect(resolveCandidatePunctuation('ni', 3, 1).type)
        .assertEqual(CandidatePunctuationResolutionType.SELECT_CANDIDATE);
      expect(resolveCandidatePunctuation('ni', 3, 1).candidateIndex).assertEqual(1);
      expect(resolveCandidatePunctuation('ni', 3, 2).candidateIndex).assertEqual(2);
      expect(resolveCandidatePunctuation('ni', 1, 2).type)
        .assertEqual(CandidatePunctuationResolutionType.COMMIT_TOP_THEN_PUNCTUATION);
      expect(resolveCandidatePunctuation('', 0, 1).type)
        .assertEqual(CandidatePunctuationResolutionType.INSERT_PUNCTUATION);
    });

    it('persists the lift-layer switch and reserves exactly one layer height', 0, () => {
      const configured = copyImeSettings(DEFAULT_IME_SETTINGS);
      configured.keyboardLiftLayerEnabled = false;
      const restored = new SettingsValidator().validate(settingsToRaw(configured));
      expect(restored.keyboardLiftLayerEnabled).assertFalse();
      expect(
        calculateTotalKeyboardHeight(PORTRAIT_METRICS, false, true) -
          calculateTotalKeyboardHeight(PORTRAIT_METRICS, false, false)
      ).assertEqual(KEYBOARD_LIFT_LAYER_HEIGHT);
    });

    it('keeps the candidate bar language switch hidden when the lift layer is disabled', 0, () => {
      expect(KEYBOARD_STATUS_BAR_LAYOUT.languageSwitchVisible).assertFalse();
    });
  });
}
