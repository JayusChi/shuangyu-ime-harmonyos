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
  keyboardHeightScale,
  KEYBOARD_HEIGHT_MODE_OPTIONS,
  KeyboardHeightMode,
  copyImeSettings,
  DEFAULT_IME_SETTINGS,
  settingsToRaw
} from '../main/ets/domain/settings/ImeSettings';
import { SettingsValidator } from '../main/ets/infrastructure/storage/SettingsValidator';
import { createStage10KeyboardLayout } from '../main/ets/presentation/keyboard/layouts/Stage10KeyboardLayouts';
import { ShuangpinKeyboardLayout } from '../main/ets/domain/keyboard/ShuangpinKeyboardLayout';
import { KEYBOARD_STATUS_BAR_LAYOUT } from '../main/ets/presentation/candidate/CandidateBar';
import {
  calculateTotalKeyboardHeight,
  PORTRAIT_METRICS
} from '../main/ets/presentation/keyboard/design/KeyboardMetrics';
import { keyboardRowRenderIdentity } from '../main/ets/presentation/keyboard/model/KeyboardLayoutSpec';

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

    it('uses the lift menu for navigation and matches both reference symbol decks', 0, () => {
      const context = createUnknownEditorContext();
      const number = createStage10KeyboardLayout(KeyboardMode.NUMBER, context, ShiftState.LOWERCASE);
      const chineseSymbols = createStage10KeyboardLayout(
        KeyboardMode.SYMBOL, context, ShiftState.LOWERCASE, '', false, false,
        ShuangpinKeyboardLayout.TWENTY_SIX_KEY, '', KeyboardMode.CHINESE
      );
      const englishSymbols = createStage10KeyboardLayout(
        KeyboardMode.SYMBOL, context, ShiftState.LOWERCASE, '', false, false,
        ShuangpinKeyboardLayout.TWENTY_SIX_KEY, '', KeyboardMode.ENGLISH
      );
      expect(number.rows[number.rows.length - 1].keys.map((key) => key.id).join(','))
        .assertEqual('number-return,character-comma,character-zero,character-decimal,enter');
      expect(chineseSymbols.rows.map((row) => row.keys.map((key) => key.label).join('')).join('|'))
        .assertEqual('#&¥……——·↗|*%<>〈〉“”‘’|【】{}「」『』（）《》〈〉|=+-×÷~删除');
      expect(englishSymbols.rows.map((row) => row.keys.map((key) => key.label).join('')).join('|'))
        .assertEqual('#&$`^-↗|_%<>"\'||{}[]()\\|¢₿£€¥~删除');
      chineseSymbols.rows.forEach((row) => row.keys.forEach((key) => {
        if (key.id !== 'delete') {
          expect(key.action.literal === true).assertTrue();
        }
      }));
      englishSymbols.rows.forEach((row) => row.keys.forEach((key) => {
        if (key.id !== 'delete') {
          expect(key.action.literal === true).assertTrue();
        }
      }));
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
      ).assertEqual(PORTRAIT_METRICS.letterKeyHeight);
    });

    it('offers exact persisted keyboard height ratios from 0.8 to 1.2', 0, () => {
      const modes = KEYBOARD_HEIGHT_MODE_OPTIONS;
      expect(modes.map((mode: KeyboardHeightMode): number => keyboardHeightScale(mode)).join(','))
        .assertEqual('0.8,0.9,1,1.1,1.2');
      modes.forEach((mode: KeyboardHeightMode): void => {
        const configured = copyImeSettings(DEFAULT_IME_SETTINGS);
        configured.keyboardHeightMode = mode;
        expect(new SettingsValidator().validate(settingsToRaw(configured)).keyboardHeightMode)
          .assertEqual(mode);
      });
    });

    it('keeps the candidate bar language switch hidden when the lift layer is disabled', 0, () => {
      expect(KEYBOARD_STATUS_BAR_LAYOUT.languageSwitchVisible).assertFalse();
    });

    it('rebuilds only the Chinese bottom row when Shift swaps with Esc', 0, () => {
      const empty = keyboardRowRenderIdentity({
        editorKind: 'text',
        keyboardMode: KeyboardMode.CHINESE,
        symbolLanguageMode: KeyboardMode.CHINESE,
        shiftState: ShiftState.LOWERCASE,
        rawInput: '',
        chineseCapsLock: false,
        shuangpinLayout: 'twenty_six_key',
        keyboardProfileId: 'xiaohe-26',
        keyboardStructureId: 'builtin-standard',
        numberDecimalAllowed: false,
        enterAction: 'enter'
      }, 1);
      const oPrefix = keyboardRowRenderIdentity({
        editorKind: 'text',
        keyboardMode: KeyboardMode.CHINESE,
        symbolLanguageMode: KeyboardMode.CHINESE,
        shiftState: ShiftState.LOWERCASE,
        rawInput: 'o',
        chineseCapsLock: false,
        shuangpinLayout: 'twenty_six_key',
        keyboardProfileId: 'xiaohe-26',
        keyboardStructureId: 'builtin-standard',
        numberDecimalAllowed: false,
        enterAction: 'enter'
      }, 1);
      const okPrefix = keyboardRowRenderIdentity({
        editorKind: 'text',
        keyboardMode: KeyboardMode.CHINESE,
        symbolLanguageMode: KeyboardMode.CHINESE,
        shiftState: ShiftState.LOWERCASE,
        rawInput: 'ok',
        chineseCapsLock: false,
        shuangpinLayout: 'twenty_six_key',
        keyboardProfileId: 'xiaohe-26',
        keyboardStructureId: 'builtin-standard',
        numberDecimalAllowed: false,
        enterAction: 'enter'
      }, 1);
      expect(oPrefix).assertEqual(empty);
      expect(okPrefix).assertEqual(empty);

      const emptyBottom = keyboardRowRenderIdentity({
        editorKind: 'text', keyboardMode: KeyboardMode.CHINESE,
        symbolLanguageMode: KeyboardMode.CHINESE,
        shiftState: ShiftState.LOWERCASE, rawInput: '', chineseCapsLock: false,
        shuangpinLayout: 'twenty_six_key', keyboardProfileId: 'xiaohe-26',
        keyboardStructureId: 'builtin-standard', numberDecimalAllowed: false, enterAction: 'enter'
      }, 2);
      const oBottom = keyboardRowRenderIdentity({
        editorKind: 'text', keyboardMode: KeyboardMode.CHINESE,
        symbolLanguageMode: KeyboardMode.CHINESE,
        shiftState: ShiftState.LOWERCASE, rawInput: 'o', chineseCapsLock: false,
        shuangpinLayout: 'twenty_six_key', keyboardProfileId: 'xiaohe-26',
        keyboardStructureId: 'builtin-standard', numberDecimalAllowed: false, enterAction: 'enter'
      }, 2);
      const okBottom = keyboardRowRenderIdentity({
        editorKind: 'text', keyboardMode: KeyboardMode.CHINESE,
        symbolLanguageMode: KeyboardMode.CHINESE,
        shiftState: ShiftState.LOWERCASE, rawInput: 'ok', chineseCapsLock: false,
        shuangpinLayout: 'twenty_six_key', keyboardProfileId: 'xiaohe-26',
        keyboardStructureId: 'builtin-standard', numberDecimalAllowed: false, enterAction: 'enter'
      }, 2);
      expect(emptyBottom === oBottom).assertFalse();
      expect(oBottom).assertEqual(okBottom);
    });

    it('rebuilds symbol rows when the transient menu switches language decks', 0, () => {
      const chineseRow = keyboardRowRenderIdentity({
        editorKind: 'text', keyboardMode: KeyboardMode.SYMBOL,
        symbolLanguageMode: KeyboardMode.CHINESE,
        shiftState: ShiftState.LOWERCASE, rawInput: '', chineseCapsLock: false,
        shuangpinLayout: 'twenty_six_key', keyboardProfileId: 'xiaohe-26',
        keyboardStructureId: 'builtin-standard', numberDecimalAllowed: false, enterAction: 'enter'
      }, 0);
      const englishRow = keyboardRowRenderIdentity({
        editorKind: 'text', keyboardMode: KeyboardMode.SYMBOL,
        symbolLanguageMode: KeyboardMode.ENGLISH,
        shiftState: ShiftState.LOWERCASE, rawInput: '', chineseCapsLock: false,
        shuangpinLayout: 'twenty_six_key', keyboardProfileId: 'xiaohe-26',
        keyboardStructureId: 'builtin-standard', numberDecimalAllowed: false, enterAction: 'enter'
      }, 0);

      expect(chineseRow === englishRow).assertFalse();
    });
  });
}
