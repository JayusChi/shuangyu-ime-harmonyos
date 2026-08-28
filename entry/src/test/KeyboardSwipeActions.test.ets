import { describe, expect, it } from '@ohos/hypium';
import { createUnknownEditorContext, ShiftState } from '../main/ets/domain/editor/EditorContext';
import {
  KeyboardActionType,
  KeyboardMode
} from '../main/ets/domain/keyboard/KeyboardAction';
import {
  LETTER_SWIPE_KEYS,
  normalizeLetterSwipeSymbols,
  parseLetterSwipeSymbols,
  resolveLetterSwipeSymbol,
  updateLetterSwipeSymbol
} from '../main/ets/domain/keyboard/LetterSwipeSymbols';
import { createStage10KeyboardLayout } from '../main/ets/presentation/keyboard/layouts/Stage10KeyboardLayouts';
import {
  KeyboardKeySpec,
  KeyboardRowSpec
} from '../main/ets/presentation/keyboard/model/KeyboardLayoutSpec';
import { applyLetterSwipeSymbols } from '../main/ets/presentation/keyboard/customization/LetterSwipeSymbolResolver';
import {
  copyImeSettings,
  DEFAULT_IME_SETTINGS,
  settingsToRaw
} from '../main/ets/domain/settings/ImeSettings';
import { SettingsValidator } from '../main/ets/infrastructure/storage/SettingsValidator';

function findKey(rows: KeyboardRowSpec[], id: string): KeyboardKeySpec | undefined {
  let result: KeyboardKeySpec | undefined = undefined;
  rows.forEach((row: KeyboardRowSpec): void => {
    const found = row.keys.find((key: KeyboardKeySpec): boolean => key.id === id);
    if (found !== undefined) {
      result = found;
    }
  });
  return result;
}

export default function keyboardSwipeActionsTest() {
  describe('KeyboardSwipeActions', () => {
    it('binds delete and enter vertical gestures to their editor actions', 0, () => {
      const layout = createStage10KeyboardLayout(
        KeyboardMode.ENGLISH,
        createUnknownEditorContext(),
        ShiftState.LOWERCASE
      );
      const deleteKey = findKey(layout.rows, 'delete');
      const enterKey = findKey(layout.rows, 'enter');
      expect(deleteKey?.swipeUpAction?.type).assertEqual(KeyboardActionType.UNDO_LAST_COMMIT);
      expect(deleteKey?.swipeDownAction?.type).assertEqual(KeyboardActionType.DELETE_CURRENT_LINE);
      expect(enterKey?.swipeUpAction?.type).assertEqual(KeyboardActionType.REPEAT_LAST_COMMIT);
      expect(enterKey?.swipeDownAction?.type).assertEqual(KeyboardActionType.RESTORE_LAST_DELETION);
    });

    it('keeps Chinese and English letter bindings separate and off the key face', 0, () => {
      const chinese = updateLetterSwipeSymbol(undefined, 'q', '【');
      const english = updateLetterSwipeSymbol(undefined, 'q', '@');
      expect(resolveLetterSwipeSymbol(chinese, 'q')).assertEqual('【');
      expect(resolveLetterSwipeSymbol(english, 'q')).assertEqual('@');
      expect(parseLetterSwipeSymbols(normalizeLetterSwipeSymbols('bad')).length)
        .assertEqual(LETTER_SWIPE_KEYS.length);

      const layout = applyLetterSwipeSymbols(
        createStage10KeyboardLayout(
          KeyboardMode.CHINESE,
          createUnknownEditorContext(),
          ShiftState.LOWERCASE
        ),
        KeyboardMode.CHINESE,
        chinese,
        english
      );
      const q = findKey(layout.rows, 'letter-q');
      expect(q?.label.toLowerCase()).assertEqual('q');
      expect(q?.swipeDownAction?.character).assertEqual('【');
      expect(q?.swipeDownAction?.literal === true).assertTrue();
    });

    it('round trips both language maps through the settings schema', 0, () => {
      const configured = copyImeSettings(DEFAULT_IME_SETTINGS);
      configured.chineseLetterSwipeSymbols = updateLetterSwipeSymbol(undefined, 'a', '。');
      configured.englishLetterSwipeSymbols = updateLetterSwipeSymbol(undefined, 'a', '&');
      const restored = new SettingsValidator().validate(settingsToRaw(configured));
      expect(resolveLetterSwipeSymbol(restored.chineseLetterSwipeSymbols, 'a')).assertEqual('。');
      expect(resolveLetterSwipeSymbol(restored.englishLetterSwipeSymbols, 'a')).assertEqual('&');
    });
  });
}
