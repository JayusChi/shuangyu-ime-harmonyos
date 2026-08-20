import { enterActionAccessibilityText, enterActionLabel } from '../../../application/EnterActionPolicy';
import { EditorContext } from '../../../domain/editor/EditorContext';
import {
  createT9PinyinDigitAction,
  DELETE_ACTION,
  ENTER_ACTION,
  INSERT_SEGMENT_BOUNDARY_ACTION,
  KeyboardAction,
  SPACE_ACTION,
  TOGGLE_LANGUAGE_ACTION,
  TOGGLE_NUMBER_ACTION,
  TOGGLE_SYMBOL_ACTION
} from '../../../domain/keyboard/KeyboardAction';
import {
  KeyboardKeyKind,
  KeyboardKeySpec,
  KeyboardLayoutSpec,
  KeyboardRowKind
} from '../model/KeyboardLayoutSpec';
import { KEY_WEIGHTS } from '../design/KeyboardMetrics';

function key(
  id: string,
  label: string,
  kind: KeyboardKeyKind,
  weight: number,
  action: KeyboardAction,
  accessibilityLabel: string,
  secondaryLabel?: string,
  previewEnabled: boolean = false
): KeyboardKeySpec {
  return {
    id,
    label,
    secondaryLabel,
    previewLabel: secondaryLabel ? `${label} ${secondaryLabel}` : label,
    kind,
    weight,
    action,
    previewEnabled,
    accessibilityLabel
  };
}

function t9DigitKey(digit: string, letters: string, chineseNumber: string): KeyboardKeySpec {
  return key(
    `t9-digit-${digit}`,
    digit,
    KeyboardKeyKind.T9_DIGIT,
    1,
    createT9PinyinDigitAction(digit),
    `数字${chineseNumber}，字母 ${letters.split('').join(' ')}`,
    letters,
    true
  );
}

function enterKey(context: EditorContext): KeyboardKeySpec {
  return key(
    'enter',
    enterActionLabel(context.enterAction),
    KeyboardKeyKind.ENTER,
    KEY_WEIGHTS.ENTER,
    ENTER_ACTION,
    enterActionAccessibilityText(context.enterAction)
  );
}

/**
 * Traditional Chinese 3x4 keypad plus the shared language/space/editor-action
 * row. Only 2-9 produce T9 actions; real digits remain in the number layout.
 */
export function createPinyin9KeyboardLayout(context: EditorContext): KeyboardLayoutSpec {
  const space = key('space', '空格', KeyboardKeyKind.SPACE, 4.6, SPACE_ACTION,
    '空格，上滑或长按切换中英文', '中/英');
  space.longPressAction = TOGGLE_LANGUAGE_ACTION;
  space.swipeUpAction = TOGGLE_LANGUAGE_ACTION;
  return {
    rows: [
      {
        keys: [
          key('t9-punctuation', '1', KeyboardKeyKind.FUNCTION, 1, TOGGLE_SYMBOL_ACTION,
            '数字一，常用标点', '标点'),
          t9DigitKey('2', 'ABC', '二'),
          t9DigitKey('3', 'DEF', '三')
        ]
      },
      {
        keys: [
          t9DigitKey('4', 'GHI', '四'),
          t9DigitKey('5', 'JKL', '五'),
          t9DigitKey('6', 'MNO', '六')
        ]
      },
      {
        keys: [
          t9DigitKey('7', 'PQRS', '七'),
          t9DigitKey('8', 'TUV', '八'),
          t9DigitKey('9', 'WXYZ', '九')
        ]
      },
      {
        keys: [
          key('t9-number', '符/123', KeyboardKeyKind.MODE_SWITCH, 1, TOGGLE_NUMBER_ACTION,
            '符号和数字'),
          key('t9-boundary', '0', KeyboardKeyKind.FUNCTION, 1, INSERT_SEGMENT_BOUNDARY_ACTION,
            '分词', '分词'),
          key('delete', '删除', KeyboardKeyKind.DELETE, 1, DELETE_ACTION, '删除')
        ]
      },
      {
        keys: [
          space,
          enterKey(context)
        ],
        kind: KeyboardRowKind.BOTTOM_ACTIONS
      }
    ]
  };
}
