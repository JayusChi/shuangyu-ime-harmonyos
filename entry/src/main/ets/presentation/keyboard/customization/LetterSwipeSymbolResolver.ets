import {
  parseLetterSwipeSymbols,
  LETTER_SWIPE_KEYS
} from '../../../domain/keyboard/LetterSwipeSymbols';
import {
  createLiteralCharacterInputAction,
  KeyboardMode
} from '../../../domain/keyboard/KeyboardAction';
import {
  KeyboardKeySpec,
  KeyboardLayoutSpec,
  KeyboardRowSpec
} from '../model/KeyboardLayoutSpec';

/** Adds invisible, settings-defined downward actions to 26-key letter keys. */
export function applyLetterSwipeSymbols(
  layout: KeyboardLayoutSpec,
  mode: KeyboardMode,
  chineseSymbols: string,
  englishSymbols: string
): KeyboardLayoutSpec {
  if (mode !== KeyboardMode.CHINESE && mode !== KeyboardMode.ENGLISH) {
    return layout;
  }
  const symbols = parseLetterSwipeSymbols(
    mode === KeyboardMode.CHINESE ? chineseSymbols : englishSymbols
  );
  layout.rows.forEach((row: KeyboardRowSpec): void => {
    row.keys.forEach((spec: KeyboardKeySpec): void => {
      const letter = spec.id.startsWith('letter-') ? spec.id.slice('letter-'.length) : '';
      const index = LETTER_SWIPE_KEYS.indexOf(letter);
      if (index < 0 || symbols[index].length === 0) {
        return;
      }
      spec.swipeDownAction = createLiteralCharacterInputAction(symbols[index]);
      spec.accessibilityLabel = `${spec.accessibilityLabel}，下滑输入自定义符号`;
    });
  });
  return layout;
}
