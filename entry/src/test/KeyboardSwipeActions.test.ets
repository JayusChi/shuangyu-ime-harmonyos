import { describe, expect, it } from '@ohos/hypium';
import { createUnknownEditorContext, ShiftState } from '../main/ets/domain/editor/EditorContext';
import {
  KeyboardActionType,
  KeyboardMode
} from '../main/ets/domain/keyboard/KeyboardAction';
import {
  DEFAULT_LETTER_SWIPE_SYMBOLS,
  EMPTY_LETTER_SWIPE_SYMBOLS,
  LETTER_SWIPE_KEYS,
  normalizeLetterSwipeSymbols,
  parseLetterSwipeSymbols,
  RECOMMENDED_LETTER_SWIPE_SYMBOLS,
  resolveLetterSwipeSymbol,
  updateLetterSwipeSymbol
} from '../main/ets/domain/keyboard/LetterSwipeSymbols';
import { createStage10KeyboardLayout } from '../main/ets/presentation/keyboard/layouts/Stage10KeyboardLayouts';
import { PINYIN_9_PROFILE_ID } from '../main/ets/domain/keyboard/KeyboardProfile';
import { ShuangpinKeyboardLayout } from '../main/ets/domain/keyboard/ShuangpinKeyboardLayout';
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
import { SettingsMigration } from '../main/ets/infrastructure/storage/SettingsMigration';

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

    it('shows the active language above space and reserves swipe-up for candidate expansion', 0, () => {
      const context = createUnknownEditorContext();
      const chinese = createStage10KeyboardLayout(KeyboardMode.CHINESE, context, ShiftState.LOWERCASE);
      const english = createStage10KeyboardLayout(KeyboardMode.ENGLISH, context, ShiftState.LOWERCASE);
      const pinyin9 = createStage10KeyboardLayout(
        KeyboardMode.CHINESE,
        context,
        ShiftState.LOWERCASE,
        '',
        false,
        false,
        ShuangpinKeyboardLayout.TWENTY_SIX_KEY,
        PINYIN_9_PROFILE_ID
      );

      expect(findKey(chinese.rows, 'space')?.upperLabel).assertEqual('中文');
      expect(findKey(english.rows, 'space')?.upperLabel).assertEqual('EN');
      expect(findKey(pinyin9.rows, 'space')?.upperLabel).assertEqual('中文');
      expect(findKey(chinese.rows, 'space')?.longPressAction?.type)
        .assertEqual(KeyboardActionType.TOGGLE_LANGUAGE);
      expect(findKey(chinese.rows, 'space')?.swipeUpAction?.type)
        .assertEqual(KeyboardActionType.EXPAND_CANDIDATES);
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

    it('ships the reference down-swipe symbols as an editable default preset', 0, () => {
      expect(DEFAULT_LETTER_SWIPE_SYMBOLS).assertEqual(RECOMMENDED_LETTER_SWIPE_SYMBOLS);
      expect(resolveLetterSwipeSymbol(DEFAULT_LETTER_SWIPE_SYMBOLS, 'q')).assertEqual('[');
      expect(resolveLetterSwipeSymbol(DEFAULT_LETTER_SWIPE_SYMBOLS, 'a')).assertEqual('_');
      expect(resolveLetterSwipeSymbol(DEFAULT_LETTER_SWIPE_SYMBOLS, 'f')).assertEqual('《');
      expect(resolveLetterSwipeSymbol(DEFAULT_LETTER_SWIPE_SYMBOLS, 'b')).assertEqual('🍀');
      expect(resolveLetterSwipeSymbol(DEFAULT_LETTER_SWIPE_SYMBOLS, 'n')).assertEqual('乚');
      expect(resolveLetterSwipeSymbol(DEFAULT_LETTER_SWIPE_SYMBOLS, 'm')).assertEqual('→');
      expect(resolveLetterSwipeSymbol(DEFAULT_LETTER_SWIPE_SYMBOLS, 'z')).assertEqual('');
    });

    it('upgrades only the legacy empty default and preserves customized swipe maps', 0, () => {
      const migration = new SettingsMigration();
      const upgraded = migration.migrate({
        schemaVersion: '14',
        chineseLetterSwipeSymbols: EMPTY_LETTER_SWIPE_SYMBOLS,
        englishLetterSwipeSymbols: EMPTY_LETTER_SWIPE_SYMBOLS
      });
      expect(resolveLetterSwipeSymbol(upgraded.chineseLetterSwipeSymbols, 'q')).assertEqual('[');
      expect(resolveLetterSwipeSymbol(upgraded.englishLetterSwipeSymbols, 'm')).assertEqual('→');

      const customized = updateLetterSwipeSymbol(EMPTY_LETTER_SWIPE_SYMBOLS, 'q', '【');
      const preserved = migration.migrate({
        schemaVersion: '14',
        chineseLetterSwipeSymbols: customized,
        englishLetterSwipeSymbols: customized
      });
      expect(resolveLetterSwipeSymbol(preserved.chineseLetterSwipeSymbols, 'q')).assertEqual('【');
      expect(resolveLetterSwipeSymbol(preserved.chineseLetterSwipeSymbols, 'w')).assertEqual('');
    });

    it('uses language-specific upper-deck symbols on letters and punctuation keys', 0, () => {
      const context = createUnknownEditorContext();
      const chinese = createStage10KeyboardLayout(KeyboardMode.CHINESE, context, ShiftState.LOWERCASE);
      const english = createStage10KeyboardLayout(KeyboardMode.ENGLISH, context, ShiftState.LOWERCASE);

      expect(findKey(chinese.rows, 'letter-b')?.upperLabel).assertEqual('_');
      expect(findKey(chinese.rows, 'letter-n')?.upperLabel).assertEqual('`');
      expect(findKey(chinese.rows, 'letter-m')?.upperLabel).assertEqual('：');
      expect(findKey(chinese.rows, 'punctuation-comma')?.upperLabel).assertEqual('=');
      expect(findKey(chinese.rows, 'punctuation-period')?.upperLabel).assertEqual('？');
      expect(findKey(chinese.rows, 'letter-m')?.swipeUpAction?.character).assertEqual('：');
      expect(findKey(chinese.rows, 'punctuation-period')?.swipeUpAction?.literal === true).assertTrue();

      expect(findKey(english.rows, 'letter-b')?.upperLabel).assertEqual('_');
      expect(findKey(english.rows, 'letter-n')?.upperLabel).assertEqual('\\');
      expect(findKey(english.rows, 'letter-m')?.upperLabel).assertEqual(':');
      expect(findKey(english.rows, 'punctuation-comma')?.upperLabel).assertEqual('=');
      expect(findKey(english.rows, 'punctuation-period')?.upperLabel).assertEqual('?');
      expect(findKey(english.rows, 'letter-n')?.swipeUpAction?.character).assertEqual('\\');
      expect(findKey(english.rows, 'letter-n')?.swipeUpAction?.literal === true).assertTrue();
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
