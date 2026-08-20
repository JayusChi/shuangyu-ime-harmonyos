import { describe, it, expect } from '@ohos/hypium';
import { createUnknownEditorContext, ShiftState } from '../main/ets/domain/editor/EditorContext';
import {
  KeyboardActionType,
  KeyboardMode
} from '../main/ets/domain/keyboard/KeyboardAction';
import { PINYIN_9_PROFILE_ID } from '../main/ets/domain/keyboard/KeyboardProfile';
import { ShuangpinKeyboardLayout } from '../main/ets/domain/keyboard/ShuangpinKeyboardLayout';
import { resolveCompositionPreeditView } from '../main/ets/domain/candidate/CompositionPreeditView';
import { createScreenMetrics } from '../main/ets/domain/display/ScreenMetrics';
import { KeyboardHeightMode } from '../main/ets/domain/settings/ImeSettings';
import { buildPinyinCombinationOptions } from '../main/ets/presentation/candidate/PinyinCombinationBar';
import { createPinyin9KeyboardLayout } from '../main/ets/presentation/keyboard/layouts/Pinyin9KeyboardLayout';
import { createStage10KeyboardLayout } from '../main/ets/presentation/keyboard/layouts/Stage10KeyboardLayouts';
import { KeyboardKeyKind, KeyboardKeySpec } from '../main/ets/presentation/keyboard/model/KeyboardLayoutSpec';
import { panelHeightForMode } from '../main/ets/presentation/keyboard/design/KeyboardMetrics';

export default function pinyin9Stage4Test() {
  describe('Pinyin 9 stage 4 UI contract', () => {
    it('builds the documented four-row grid and shared bottom action row', 0, () => {
      const layout = createPinyin9KeyboardLayout(createUnknownEditorContext());
      expect(layout.rows.length).assertEqual(5);
      expect(layout.rows[0].keys.map((key: KeyboardKeySpec) => key.label).join('|')).assertEqual('1|2|3');
      expect(layout.rows[1].keys.map((key: KeyboardKeySpec) => key.label).join('|')).assertEqual('4|5|6');
      expect(layout.rows[2].keys.map((key: KeyboardKeySpec) => key.label).join('|')).assertEqual('7|8|9');
      expect(layout.rows[3].keys.map((key: KeyboardKeySpec) => key.label).join('|'))
        .assertEqual('符/123|0|删除');
      expect(layout.rows[4].keys[0].label).assertEqual('中');
      expect(layout.rows[4].keys[1].label).assertEqual('空格');
      expect(layout.rows[4].keys[2].action.type).assertEqual(KeyboardActionType.ENTER);
    });

    it('uses dedicated T9 actions and complete primary-secondary labels for 2 through 9', 0, () => {
      const layout = createPinyin9KeyboardLayout(createUnknownEditorContext());
      const digits = layout.rows.slice(0, 3).map((row) => row.keys).reduce(
        (all: KeyboardKeySpec[], row: KeyboardKeySpec[]) => all.concat(row), [] as KeyboardKeySpec[]
      ).filter((key: KeyboardKeySpec) => key.kind === KeyboardKeyKind.T9_DIGIT);
      expect(digits.length).assertEqual(8);
      expect(digits.map((key: KeyboardKeySpec) => key.secondaryLabel ?? '').join('|'))
        .assertEqual('ABC|DEF|GHI|JKL|MNO|PQRS|TUV|WXYZ');
      digits.forEach((key: KeyboardKeySpec): void => {
        expect(key.action.type).assertEqual(KeyboardActionType.T9_PINYIN_DIGIT);
        expect(key.action.digit).assertEqual(key.label);
        expect(key.previewEnabled).assertTrue();
        expect(key.accessibilityLabel.indexOf('字母') > 0).assertTrue();
      });
    });

    it('routes punctuation boundary number entry and delete without entering the T9 digit parser', 0, () => {
      const layout = createPinyin9KeyboardLayout(createUnknownEditorContext());
      expect(layout.rows[0].keys[0].action.type).assertEqual(KeyboardActionType.TOGGLE_SYMBOL);
      expect(layout.rows[3].keys[0].action.type).assertEqual(KeyboardActionType.TOGGLE_NUMBER);
      expect(layout.rows[3].keys[1].action.type).assertEqual(KeyboardActionType.INSERT_SEGMENT_BOUNDARY);
      expect(layout.rows[3].keys[2].action.type).assertEqual(KeyboardActionType.DELETE);
    });

    it('uses QWERTY for English and restores 9-key only for Chinese mode', 0, () => {
      const context = createUnknownEditorContext();
      const chinese = createStage10KeyboardLayout(
        KeyboardMode.CHINESE, context, ShiftState.LOWERCASE, '', false, false,
        ShuangpinKeyboardLayout.TWENTY_SIX_KEY, PINYIN_9_PROFILE_ID
      );
      const english = createStage10KeyboardLayout(
        KeyboardMode.ENGLISH, context, ShiftState.LOWERCASE, '', false, false,
        ShuangpinKeyboardLayout.TWENTY_SIX_KEY, PINYIN_9_PROFILE_ID
      );
      expect(chinese.rows[0].keys[1].id).assertEqual('t9-digit-2');
      expect(english.rows[0].keys[0].id).assertEqual('letter-q');
      expect(english.rows.length).assertEqual(4);
    });

    it('keeps real number mode character actions separate from Chinese T9 digits', 0, () => {
      const number = createStage10KeyboardLayout(
        KeyboardMode.NUMBER,
        createUnknownEditorContext(),
        ShiftState.LOWERCASE,
        '',
        false,
        false,
        ShuangpinKeyboardLayout.TWENTY_SIX_KEY,
        PINYIN_9_PROFILE_ID
      );
      expect(number.rows[0].keys[1].label).assertEqual('2');
      expect(number.rows[0].keys[1].action.type).assertEqual(KeyboardActionType.CHARACTER);
    });

    it('preserves Rust pinyin publication order and marks only current path selected', 0, () => {
      const options = buildPinyinCombinationOptions('ni', ['mi', 'ng']);
      expect(options.map((item) => item.text).join('|')).assertEqual('ni|mi|ng');
      expect(options.map((item) => item.combinationIndex).join('|')).assertEqual('0|1|2');
      expect(options[0].selected).assertTrue();
      expect(options[1].selected).assertFalse();
    });

    it('shows the Rust currentPinyin instead of expanding raw digits in ArkTS', 0, () => {
      const view = resolveCompositionPreeditView({
        rawInput: '64426',
        preeditText: 'ni\'hao',
        displaySegments: ['64', '426'],
        preferredDisplayText: 'ni\'hao'
      });
      expect(view.displayText).assertEqual("ni'hao");
    });

    it('allocates bounded extra height for phone and tablet 9-key layouts', 0, () => {
      const screens = [
        createScreenMetrics({ widthPx: 1080, heightPx: 2340, densityPixels: 3 }, false),
        createScreenMetrics({ widthPx: 2340, heightPx: 1080, densityPixels: 3 }, true),
        createScreenMetrics({ widthPx: 1920, heightPx: 2880, densityPixels: 2 }, false),
        createScreenMetrics({ widthPx: 2880, heightPx: 1920, densityPixels: 2 }, true)
      ];
      screens.forEach((screen): void => {
        const qwertyHeight = panelHeightForMode(KeyboardHeightMode.STANDARD, screen, false);
        const pinyin9Height = panelHeightForMode(KeyboardHeightMode.STANDARD, screen, true);
        expect(pinyin9Height > qwertyHeight).assertTrue();
        expect(pinyin9Height <= screen.heightPx).assertTrue();
      });
    });
  });
}
