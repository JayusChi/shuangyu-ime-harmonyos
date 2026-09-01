import { enterActionAccessibilityText, enterActionLabel } from '../../../application/EnterActionPolicy';
import { EditorContext } from '../../../domain/editor/EditorContext';
import {
  createT9PinyinDigitAction,
  DELETE_ACTION,
  DELETE_CURRENT_LINE_ACTION,
  ENTER_ACTION,
  EXPAND_CANDIDATES_ACTION,
  INSERT_SEGMENT_BOUNDARY_ACTION,
  KeyboardAction,
  SPACE_ACTION,
  TOGGLE_LANGUAGE_ACTION,
  TOGGLE_NUMBER_ACTION,
  TOGGLE_SYMBOL_ACTION,
  REPEAT_LAST_COMMIT_ACTION,
  RESTORE_LAST_DELETION_ACTION,
  UNDO_LAST_COMMIT_ACTION,
  SECOND_CANDIDATE_OR_PERIOD_ACTION,
  THIRD_CANDIDATE_OR_COMMA_ACTION
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
  const spec = key(
    'enter',
    enterActionLabel(context.enterAction),
    KeyboardKeyKind.ENTER,
    KEY_WEIGHTS.ENTER,
    ENTER_ACTION,
    enterActionAccessibilityText(context.enterAction)
  );
  spec.swipeUpAction = REPEAT_LAST_COMMIT_ACTION;
  spec.swipeDownAction = RESTORE_LAST_DELETION_ACTION;
  spec.accessibilityLabel = `${spec.accessibilityLabel}，上滑重复上屏，下滑恢复最近删除`;
  return spec;
}

/**
 * Traditional Chinese 3x4 keypad plus the shared language/space/editor-action
 * row. Only 2-9 produce T9 actions; real digits remain in the number layout.
 */
export function createPinyin9KeyboardLayout(context: EditorContext): KeyboardLayoutSpec {
  const space = key('space', '空格', KeyboardKeyKind.SPACE, 4.6, SPACE_ACTION,
    '空格，长按切换中英文，候选不少于三个时上滑展开候选');
  space.upperLabel = '中文';
  space.longPressAction = TOGGLE_LANGUAGE_ACTION;
  space.swipeUpAction = EXPAND_CANDIDATES_ACTION;
  const numberKey = key('t9-number', 'ϟ12', KeyboardKeyKind.MODE_SWITCH, 1, TOGGLE_NUMBER_ACTION,
    '点击进入数字键盘，长按进入符号键盘');
  numberKey.longPressAction = TOGGLE_SYMBOL_ACTION;
  return {
    rows: [
      {
        keys: [
          key('t9-punctuation', '1', KeyboardKeyKind.FUNCTION, 1, THIRD_CANDIDATE_OR_COMMA_ACTION,
            '常用标点或第三候选', '标点'),
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
          numberKey,
          key('t9-boundary', '0', KeyboardKeyKind.FUNCTION, 1, INSERT_SEGMENT_BOUNDARY_ACTION,
            '分词', '分词'),
          deleteKey()
        ]
      },
      {
        keys: [
          key('punctuation-comma', '，', KeyboardKeyKind.FUNCTION, 0.9,
            THIRD_CANDIDATE_OR_COMMA_ACTION, '有第三候选时选择第三候选，否则输入逗号'),
          space,
          key('punctuation-period', '。', KeyboardKeyKind.FUNCTION, 0.9,
            SECOND_CANDIDATE_OR_PERIOD_ACTION, '有第二候选时选择第二候选，否则输入句号'),
          enterKey(context)
        ],
        kind: KeyboardRowKind.BOTTOM_ACTIONS
      }
    ]
  };
}

function deleteKey(): KeyboardKeySpec {
  const spec = key('delete', '删除', KeyboardKeyKind.DELETE, 1, DELETE_ACTION,
    '删除前一个字符，上滑撤销上屏，下滑删除当前行');
  spec.swipeUpAction = UNDO_LAST_COMMIT_ACTION;
  spec.swipeDownAction = DELETE_CURRENT_LINE_ACTION;
  return spec;
}
