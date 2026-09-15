import { enterActionAccessibilityText, enterActionLabel } from '../../../application/EnterActionPolicy';
import { EditorContext, EditorKind, ShiftState } from '../../../domain/editor/EditorContext';
import { ShuangpinKeyboardLayout } from '../../../domain/keyboard/ShuangpinKeyboardLayout';
import {
  createCharacterInputAction,
  createLiteralCharacterInputAction,
  createLiteralPairInputAction,
  createLetterInputAction,
  CANCEL_COMPOSITION_ACTION,
  COPY_ACTION,
  CONVENIENCE_GUIDE_ACTION,
  SECOND_CANDIDATE_OR_PASTE_ACTION,
  CUT_ACTION,
  DELETE_ACTION,
  DELETE_CURRENT_LINE_ACTION,
  ENTER_ACTION,
  EXPAND_CANDIDATES_ACTION,
  KeyboardAction,
  KeyboardMode,
  PASTE_ACTION,
  SELECT_ALL_ACTION,
  SHOW_INPUT_METHOD_PICKER_ACTION,
  SHIFT_ACTION,
  SPACE_ACTION,
  TOGGLE_LANGUAGE_ACTION,
  TOGGLE_CHINESE_CAPS_LOCK_ACTION,
  TOGGLE_NUMBER_ACTION,
  TOGGLE_SYMBOL_ACTION,
  UNIVERSAL_KEY_ACTION,
  SECOND_CANDIDATE_OR_PERIOD_ACTION,
  THIRD_CANDIDATE_OR_COMMA_ACTION,
  REPEAT_LAST_COMMIT_ACTION,
  RESTORE_LAST_DELETION_ACTION,
  UNDO_LAST_COMMIT_ACTION
} from '../../../domain/keyboard/KeyboardAction';
import {
  KeyboardKeyKind,
  KeyboardKeyAlternativeSpec,
  KeyboardKeySpec,
  KeyboardLayoutSpec,
  KeyboardRowKind,
  KeyboardRowSpec
} from '../model/KeyboardLayoutSpec';
import { KEY_WEIGHTS } from '../design/KeyboardMetrics';
import { PINYIN_9_PROFILE_ID } from '../../../domain/keyboard/KeyboardProfile';
import { createPinyin9KeyboardLayout } from './Pinyin9KeyboardLayout';

export const QWERTY_TOP_ROW: string = 'qwertyuiop';
export const QWERTY_MIDDLE_ROW: string = 'asdfghjkl';
export const QWERTY_BOTTOM_ROW: string = 'zxcvbnm';

function key(
  id: string,
  label: string,
  kind: KeyboardKeyKind,
  weight: number,
  action: KeyboardAction,
  accessibilityLabel: string = label,
  previewEnabled: boolean = kind === KeyboardKeyKind.LETTER,
  active: boolean = false
): KeyboardKeySpec {
  return {
    id,
    label,
    kind,
    weight,
    action,
    previewEnabled,
    accessibilityLabel,
    active
  };
}

function letterKey(letter: string, shiftState: ShiftState, chineseMode: boolean): KeyboardKeySpec {
  const label = shiftState === ShiftState.LOWERCASE ? letter.toLowerCase() : letter.toUpperCase();
  const spec = key(
    `letter-${letter}`,
    label,
    KeyboardKeyKind.LETTER,
    KEY_WEIGHTS.LETTER,
    createLetterInputAction(letter),
    `字母 ${label}`
  );
  const upper = upperDeckForLetter(letter, chineseMode);
  if (upper) {
    spec.upperLabel = upper.label;
    spec.longPressAction = upper.action;
    spec.swipeUpAction = upper.action;
    spec.accessibilityLabel = `字母 ${label}，上滑或长按${upper.accessibilityLabel}`;
  }
  return spec;
}

interface UpperDeckSpec {
  label: string;
  action: KeyboardAction;
  accessibilityLabel: string;
}

function upperCharacter(character: string): UpperDeckSpec {
  return {
    label: character,
    action: createLiteralCharacterInputAction(character),
    accessibilityLabel: `输入 ${character}`
  };
}

function smartUpperCharacter(character: string): UpperDeckSpec {
  return {
    label: character,
    action: createCharacterInputAction(character),
    accessibilityLabel: `输入智能标点 ${character}`
  };
}

function upperDeckForLetter(letter: string, chineseMode: boolean): UpperDeckSpec | undefined {
  const topIndex = QWERTY_TOP_ROW.indexOf(letter);
  if (topIndex >= 0) {
    return upperCharacter(topIndex === 9 ? '0' : `${topIndex + 1}`);
  }
  switch (letter) {
    case 'a':
      return { label: '全选', action: SELECT_ALL_ACTION, accessibilityLabel: '全选' };
    case 's':
      return upperCharacter('*');
    case 'd':
      return upperCharacter('/');
    case 'f':
      return upperCharacter(';');
    case 'g':
      return upperCharacter('!');
    case 'h':
      return upperCharacter('-');
    case 'j':
      return upperCharacter('#');
    case 'k':
      return upperCharacter('+');
    case 'l':
      return upperCharacter('@');
    case 'z':
      return { label: '万能', action: UNIVERSAL_KEY_ACTION, accessibilityLabel: '输入万能键' };
    case 'x':
      return { label: '剪切', action: CUT_ACTION, accessibilityLabel: '剪切所选文本' };
    case 'c':
      return { label: '复制', action: COPY_ACTION, accessibilityLabel: '复制所选文本' };
    case 'v':
      return { label: '粘贴', action: PASTE_ACTION, accessibilityLabel: '粘贴' };
    case 'b':
      return upperCharacter('_');
    case 'n':
      return chineseMode ? smartUpperCharacter('、') : upperCharacter('\\');
    case 'm':
      return chineseMode ? smartUpperCharacter('：') : upperCharacter(':');
    default:
      return undefined;
  }
}

function characterKey(character: string, id: string = character): KeyboardKeySpec {
  return key(
    `character-${id}`,
    character,
    KeyboardKeyKind.FUNCTION,
    1,
    createCharacterInputAction(character),
    `输入符号 ${character}`
  );
}

function literalSymbolKey(label: string, character: string, id: string): KeyboardKeySpec {
  return key(
    `symbol-${id}`,
    label,
    KeyboardKeyKind.FUNCTION,
    1,
    createLiteralCharacterInputAction(character),
    `输入符号 ${label}`
  );
}

function literalSymbolPairKey(left: string, right: string, id: string): KeyboardKeySpec {
  const text = `${left}${right}`;
  return key(
    `symbol-${id}`,
    text,
    KeyboardKeyKind.FUNCTION,
    1,
    createLiteralPairInputAction(text, right.length),
    `输入成对符号 ${text}，光标位于中间`
  );
}

function upperCharacterKey(
  character: string,
  upperCharacterValue: string,
  id: string
): KeyboardKeySpec {
  const spec = characterKey(character, id);
  const upperAction = createCharacterInputAction(upperCharacterValue);
  spec.upperLabel = upperCharacterValue;
  spec.longPressAction = upperAction;
  spec.swipeUpAction = upperAction;
  spec.accessibilityLabel = `输入 ${character}，上滑或长按输入 ${upperCharacterValue}`;
  return spec;
}

function segmentedKey(
  id: string,
  labels: string[],
  actions: KeyboardAction[],
  kind: KeyboardKeyKind = KeyboardKeyKind.LETTER,
  weight: number = 1
): KeyboardKeySpec {
  const alternatives: KeyboardKeyAlternativeSpec[] = labels.map((label: string, index: number) => {
    const alternative: KeyboardKeyAlternativeSpec = {
      label,
      action: actions[index],
      accessibilityLabel: kind === KeyboardKeyKind.LETTER ? `字母 ${label}` : `输入符号 ${label}`
    };
    return alternative;
  });
  const spec = key(
    id,
    labels.join(' '),
    kind,
    weight,
    actions[0],
    alternatives.map((item: KeyboardKeyAlternativeSpec) => item.accessibilityLabel).join('、'),
    false
  );
  spec.alternatives = alternatives;
  return spec;
}

function groupedLetterKey(
  id: string,
  letters: string,
  shiftState: ShiftState,
  weight: number
): KeyboardKeySpec {
  const sourceLetters = letters.split('');
  const labels = sourceLetters.map((letter: string): string =>
    shiftState === ShiftState.LOWERCASE ? letter.toLowerCase() : letter.toUpperCase());
  return segmentedKey(
    `group-${id}`,
    labels,
    sourceLetters.map((letter: string) => createLetterInputAction(letter.toLowerCase())),
    KeyboardKeyKind.LETTER,
    weight
  );
}

function letterRow(letters: string, shiftState: ShiftState, chineseMode: boolean): KeyboardKeySpec[] {
  return letters.split('').map((letter: string) => letterKey(letter, shiftState, chineseMode));
}

function enterKey(context: EditorContext, weight: number = 1.35): KeyboardKeySpec {
  const spec = key(
    'enter',
    enterActionLabel(context.enterAction),
    KeyboardKeyKind.ENTER,
    weight,
    ENTER_ACTION,
    enterActionAccessibilityText(context.enterAction)
  );
  spec.swipeUpAction = REPEAT_LAST_COMMIT_ACTION;
  spec.swipeDownAction = RESTORE_LAST_DELETION_ACTION;
  spec.accessibilityLabel = `${spec.accessibilityLabel}，上滑重复上屏，下滑恢复最近删除`;
  return spec;
}

function deleteKey(weight: number = 1.3): KeyboardKeySpec {
  const spec = key('delete', '删除', KeyboardKeyKind.DELETE, weight, DELETE_ACTION,
    '删除前一个字符，上滑撤销上屏，下滑删除当前行');
  spec.swipeUpAction = UNDO_LAST_COMMIT_ACTION;
  spec.swipeDownAction = DELETE_CURRENT_LINE_ACTION;
  return spec;
}

function inputMethodSwitchKey(weight: number = KEY_WEIGHTS.MODE_SWITCH): KeyboardKeySpec {
  const switchKey = key(
    'input-method-switch',
    '',
    KeyboardKeyKind.INPUT_METHOD_SWITCH,
    weight,
    SHOW_INPUT_METHOD_PICKER_ACTION,
    '选择输入法'
  );
  switchKey.longPressAction = SHOW_INPUT_METHOD_PICKER_ACTION;
  return switchKey;
}

function numberDeckKey(weight: number = KEY_WEIGHTS.MODE_SWITCH): KeyboardKeySpec {
  const spec = key(
    'number',
    'ϟ12',
    KeyboardKeyKind.MODE_SWITCH,
    weight,
    TOGGLE_NUMBER_ACTION,
    '点击进入数字键盘，长按进入符号键盘'
  );
  spec.longPressAction = TOGGLE_SYMBOL_ACTION;
  return spec;
}

function commaKey(chineseMode: boolean, weight: number = 0.9): KeyboardKeySpec {
  const spec = key(
    'punctuation-comma',
    chineseMode ? '，' : ',',
    KeyboardKeyKind.FUNCTION,
    weight,
    chineseMode ? THIRD_CANDIDATE_OR_COMMA_ACTION : createCharacterInputAction(','),
    chineseMode ? '有第三候选时选择第三候选，否则输入逗号' : '输入逗号'
  );
  const upperAction = createLiteralCharacterInputAction('=');
  spec.upperLabel = '=';
  spec.longPressAction = upperAction;
  spec.swipeUpAction = upperAction;
  spec.accessibilityLabel = `${spec.accessibilityLabel}，上滑或长按输入 =`;
  return spec;
}

function periodKey(chineseMode: boolean, weight: number = 0.9): KeyboardKeySpec {
  const spec = key(
    'punctuation-period',
    chineseMode ? '。' : '.',
    KeyboardKeyKind.FUNCTION,
    weight,
    chineseMode ? SECOND_CANDIDATE_OR_PERIOD_ACTION : createCharacterInputAction('.'),
    chineseMode ? '有第二候选时选择第二候选，否则输入句号' : '输入句号'
  );
  const upperCharacterValue = chineseMode ? '？' : '?';
  const upperAction = chineseMode
    ? createCharacterInputAction(upperCharacterValue)
    : createLiteralCharacterInputAction(upperCharacterValue);
  spec.upperLabel = upperCharacterValue;
  spec.longPressAction = upperAction;
  spec.swipeUpAction = upperAction;
  spec.accessibilityLabel = `${spec.accessibilityLabel}，上滑或长按输入 ${upperCharacterValue}`;
  return spec;
}

function shiftKey(shiftState: ShiftState, chineseMode: boolean = false): KeyboardKeySpec {
  const label = shiftState === ShiftState.CAPS_LOCK ? '⇧锁' : '⇧';
  const accessibility = chineseMode
    ? '中文左侧功能键'
    : (shiftState === ShiftState.CAPS_LOCK ? '关闭大写锁定' : '切换英文大写');
  return key('shift', label, KeyboardKeyKind.SHIFT, KEY_WEIGHTS.SHIFT, SHIFT_ACTION, accessibility);
}

function chineseShiftKey(chineseCapsLock: boolean): KeyboardKeySpec {
  return key(
    'shift',
    chineseCapsLock ? '⇧锁' : '⇧',
    KeyboardKeyKind.SHIFT,
    KEY_WEIGHTS.SHIFT,
    TOGGLE_CHINESE_CAPS_LOCK_ACTION,
    chineseCapsLock ? '关闭大写直输' : '开启大写直输',
    false,
    chineseCapsLock
  );
}

function escapeKey(): KeyboardKeySpec {
  return key(
    'escape',
    'Esc',
    KeyboardKeyKind.FUNCTION,
    KEY_WEIGHTS.SHIFT,
    CANCEL_COMPOSITION_ACTION,
    '取消当前中文组合'
  );
}

function createStandardLetterRows(shiftState: ShiftState, chineseMode: boolean = false): KeyboardRowSpec[] {
  return [
    { keys: letterRow(QWERTY_TOP_ROW, shiftState, chineseMode), kind: KeyboardRowKind.TOP_LETTERS },
    { keys: letterRow(QWERTY_MIDDLE_ROW, shiftState, chineseMode), kind: KeyboardRowKind.MIDDLE_LETTERS },
    {
      keys: [
        shiftKey(shiftState, chineseMode),
        ...letterRow(QWERTY_BOTTOM_ROW, shiftState, chineseMode),
        deleteKey(KEY_WEIGHTS.DELETE)
      ],
      kind: KeyboardRowKind.BOTTOM_LETTERS
    }
  ];
}

function createChineseLetterRows(
  chineseCapsLock: boolean,
  compositionActive: boolean
): KeyboardRowSpec[] {
  const uppercase = ShiftState.ONE_SHOT_UPPERCASE;
  return [
    { keys: letterRow(QWERTY_TOP_ROW, uppercase, true), kind: KeyboardRowKind.TOP_LETTERS },
    { keys: letterRow(QWERTY_MIDDLE_ROW, uppercase, true), kind: KeyboardRowKind.MIDDLE_LETTERS },
    {
      keys: [
        compositionActive ? escapeKey() : chineseShiftKey(chineseCapsLock),
        ...letterRow(QWERTY_BOTTOM_ROW, uppercase, true),
        deleteKey(KEY_WEIGHTS.DELETE)
      ],
      kind: KeyboardRowKind.BOTTOM_LETTERS
    }
  ];
}

function createTextBottomRow(
  context: EditorContext,
  chineseMode: boolean,
  showInputMethodSwitchKey: boolean = false,
  chineseCapsLock: boolean = false
): KeyboardRowSpec {
  const keys: KeyboardKeySpec[] = [];
  if (context.numberModeAllowed) {
    keys.push(numberDeckKey());
  }
  if (showInputMethodSwitchKey) {
    keys.push(inputMethodSwitchKey());
  }
  const spaceWeight = showInputMethodSwitchKey
    ? KEY_WEIGHTS.SPACE - KEY_WEIGHTS.MODE_SWITCH
    : KEY_WEIGHTS.SPACE;
  const space = key('space', '空格', KeyboardKeyKind.SPACE, spaceWeight, SPACE_ACTION,
    '空格，长按切换中英文，候选不少于三个时上滑展开候选');
  space.upperLabel = chineseMode && !chineseCapsLock ? '中文' : 'EN';
  space.longPressAction = TOGGLE_LANGUAGE_ACTION;
  space.swipeUpAction = EXPAND_CANDIDATES_ACTION;
  keys.push(commaKey(chineseMode));
  keys.push(space);
  keys.push(periodKey(chineseMode));
  keys.push(enterKey(context, KEY_WEIGHTS.ENTER));
  return { keys, kind: KeyboardRowKind.BOTTOM_ACTIONS };
}

function createEighteenKeyTextLayout(
  context: EditorContext,
  chineseMode: boolean,
  shiftState: ShiftState,
  chineseCapsLock: boolean,
  compositionActive: boolean
): KeyboardLayoutSpec {
  const letterShiftState = chineseMode ? ShiftState.ONE_SHOT_UPPERCASE : shiftState;
  const leadingKey = chineseMode
    ? (compositionActive ? escapeKey() : chineseShiftKey(chineseCapsLock))
    : shiftKey(shiftState);
  leadingKey.weight = 1;
  return {
    rows: [
      {
        keys: [
          groupedLetterKey('q', 'Q', letterShiftState, 1),
          groupedLetterKey('we', 'WE', letterShiftState, 1),
          groupedLetterKey('rt', 'RT', letterShiftState, 1),
          groupedLetterKey('y', 'Y', letterShiftState, 1),
          groupedLetterKey('u', 'U', letterShiftState, 1),
          groupedLetterKey('io', 'IO', letterShiftState, 1),
          groupedLetterKey('p', 'P', letterShiftState, 1)
        ],
        kind: KeyboardRowKind.TOP_LETTERS
      },
      {
        keys: [
          groupedLetterKey('a', 'A', letterShiftState, 1),
          groupedLetterKey('sd', 'SD', letterShiftState, 1),
          groupedLetterKey('fg', 'FG', letterShiftState, 1),
          groupedLetterKey('h', 'H', letterShiftState, 1),
          groupedLetterKey('jk', 'JK', letterShiftState, 1),
          groupedLetterKey('l', 'L', letterShiftState, 1)
        ],
        kind: KeyboardRowKind.MIDDLE_LETTERS,
        uniformKeyColumns: 7
      },
      {
        keys: [
          leadingKey,
          groupedLetterKey('z', 'Z', letterShiftState, 1),
          groupedLetterKey('xc', 'XC', letterShiftState, 1),
          groupedLetterKey('v', 'V', letterShiftState, 1),
          groupedLetterKey('bn', 'BN', letterShiftState, 1),
          groupedLetterKey('m', 'M', letterShiftState, 1),
          deleteKey(1)
        ],
        kind: KeyboardRowKind.BOTTOM_LETTERS
      },
      {
        keys: createEighteenKeyBottomKeys(context, chineseMode, chineseCapsLock),
        kind: KeyboardRowKind.BOTTOM_ACTIONS
      }
    ]
  };
}

function createEighteenKeyBottomKeys(
  context: EditorContext,
  chineseMode: boolean,
  chineseCapsLock: boolean
): KeyboardKeySpec[] {
  const space = key('space', '空格', KeyboardKeyKind.SPACE, 3.5, SPACE_ACTION,
    '空格，长按切换中英文，候选不少于三个时上滑展开候选');
  space.upperLabel = chineseMode && !chineseCapsLock ? '中文' : 'EN';
  space.longPressAction = TOGGLE_LANGUAGE_ACTION;
  space.swipeUpAction = EXPAND_CANDIDATES_ACTION;
  return [
    numberDeckKey(1.05),
    commaKey(chineseMode),
    space,
    periodKey(chineseMode),
    enterKey(context, KEY_WEIGHTS.ENTER)
  ];
}

function createChineseLayout(
  context: EditorContext,
  chineseCapsLock: boolean,
  showInputMethodSwitchKey: boolean,
  compositionActive: boolean
): KeyboardLayoutSpec {
  return {
    rows: [
      ...createChineseLetterRows(chineseCapsLock, compositionActive),
      createTextBottomRow(context, true, showInputMethodSwitchKey, chineseCapsLock)
    ]
  };
}

function quickEnglishRow(context: EditorContext): KeyboardKeySpec[] {
  if (context.kind === EditorKind.EMAIL) {
    return [characterKey('@', 'at'), characterKey('.', 'dot'), characterKey('_', 'underscore'), characterKey('-', 'dash')];
  }
  if (context.kind === EditorKind.URL) {
    return [
      characterKey('.', 'dot'),
      characterKey('/', 'slash'),
      characterKey(':', 'colon'),
      characterKey('-', 'dash'),
      characterKey('_', 'underscore')
    ];
  }
  return [];
}

function createEnglishLayout(
  context: EditorContext,
  shiftState: ShiftState,
  showInputMethodSwitchKey: boolean
): KeyboardLayoutSpec {
  const rows: KeyboardRowSpec[] = [
    ...createStandardLetterRows(shiftState)
  ];
  const quickRow = quickEnglishRow(context);
  if (quickRow.length > 0) {
    rows.push({ keys: quickRow, kind: KeyboardRowKind.AUXILIARY });
  }
  rows.push(createTextBottomRow(context, false, showInputMethodSwitchKey));
  return { rows };
}

function createNumberLayout(context: EditorContext, showInputMethodSwitchKey: boolean): KeyboardLayoutSpec {
  if (context.englishModeAllowed || context.chineseModeAllowed) {
    return createReferenceNumberLayout(context, showInputMethodSwitchKey);
  }
  return createRestrictedNumberLayout(context, showInputMethodSwitchKey);
}

function createReferenceNumberLayout(
  context: EditorContext,
  showInputMethodSwitchKey: boolean
): KeyboardLayoutSpec {
  const bottomKeys: KeyboardKeySpec[] = [
    upperCharacterKey('/', ';', 'slash'),
    upperCharacterKey(',', '¥', 'comma'),
    upperCharacterKey('0', '$', 'zero'),
    upperCharacterKey('.', '€', 'decimal')
  ];
  if (showInputMethodSwitchKey) {
    // The lift layer is hidden in this layout; retain its return action here.
    bottomKeys.push(key('number-return', '返回', KeyboardKeyKind.MODE_SWITCH, 1,
      TOGGLE_NUMBER_ACTION, '返回文字键盘'));
    bottomKeys.push(inputMethodSwitchKey());
  }
  bottomKeys.push(enterKey(context, 1));
  return {
    rows: [
      {
        keys: [
          upperCharacterKey('+', '@', 'plus'),
          characterKey('1', 'one'),
          characterKey('2', 'two'),
          characterKey('3', 'three'),
          key('number-paste', '粘贴', KeyboardKeyKind.FUNCTION, 1, SECOND_CANDIDATE_OR_PASTE_ACTION)
        ]
      },
      {
        keys: [
          upperCharacterKey('-', '%', 'minus'),
          characterKey('4', 'four'),
          characterKey('5', 'five'),
          characterKey('6', 'six'),
          key('equals', '=', KeyboardKeyKind.FUNCTION, 1, CONVENIENCE_GUIDE_ACTION)
        ]
      },
      {
        keys: [
          upperCharacterKey('*', '#', 'star'),
          characterKey('7', 'seven'),
          characterKey('8', 'eight'),
          characterKey('9', 'nine'),
          deleteKey(1)
        ]
      },
      {
        keys: bottomKeys,
        kind: KeyboardRowKind.BOTTOM_ACTIONS
      }
    ]
  };
}

function createRestrictedNumberLayout(
  context: EditorContext,
  showInputMethodSwitchKey: boolean
): KeyboardLayoutSpec {
  const fourthRow: KeyboardKeySpec[] = [];
  if (context.numberDecimalAllowed) {
    fourthRow.push(characterKey('.', 'decimal'));
  }
  fourthRow.push(characterKey('0', 'zero'));
  // 数字网格的末行必须沿用与上方数字键相同的等权列。
  fourthRow.push(deleteKey(1));

  const bottomKeys: KeyboardKeySpec[] = [];
  if (showInputMethodSwitchKey) {
    bottomKeys.push(inputMethodSwitchKey());
  }
  if (context.englishModeAllowed || context.chineseModeAllowed) {
    bottomKeys.push(
      key('number-return', '返回', KeyboardKeyKind.MODE_SWITCH, 1.2, TOGGLE_NUMBER_ACTION, '返回文本键盘')
    );
  }
  if (context.symbolModeAllowed) {
    bottomKeys.push(
      key('symbol', '#+=', KeyboardKeyKind.MODE_SWITCH, 1.1, TOGGLE_SYMBOL_ACTION, '切换到符号键盘')
    );
  }
  if (bottomKeys.length === 0) {
    bottomKeys.push(enterKey(context, KEY_WEIGHTS.NUMERIC_ONLY_ENTER));
  } else {
    bottomKeys.push(enterKey(context, KEY_WEIGHTS.PRIMARY_ENTER));
  }

  return {
    rows: [
      { keys: ['1', '2', '3'].map((value: string) => characterKey(value)) },
      { keys: ['4', '5', '6'].map((value: string) => characterKey(value)) },
      { keys: ['7', '8', '9'].map((value: string) => characterKey(value)) },
      { keys: fourthRow },
      { keys: bottomKeys }
    ]
  };
}

function createPhoneLayout(context: EditorContext, showInputMethodSwitchKey: boolean): KeyboardLayoutSpec {
  const bottomKeys: KeyboardKeySpec[] = [];
  if (showInputMethodSwitchKey) {
    bottomKeys.push(inputMethodSwitchKey());
  }
  bottomKeys.push(characterKey('+', 'plus'), deleteKey(), enterKey(context, KEY_WEIGHTS.PRIMARY_ENTER));
  return {
    rows: [
      { keys: ['1', '2', '3'].map((value: string) => characterKey(value)) },
      { keys: ['4', '5', '6'].map((value: string) => characterKey(value)) },
      { keys: ['7', '8', '9'].map((value: string) => characterKey(value)) },
      { keys: [characterKey('*', 'star'), characterKey('0', 'zero'), characterKey('#', 'hash')] },
      { keys: bottomKeys }
    ]
  };
}

function createSymbolLayout(
  showInputMethodSwitchKey: boolean,
  languageMode: KeyboardMode
): KeyboardLayoutSpec {
  const rows: KeyboardKeySpec[][] = languageMode === KeyboardMode.ENGLISH
    ? [
      [
        literalSymbolKey('#', '#', 'en-hash'),
        literalSymbolKey('&', '&', 'en-ampersand'),
        literalSymbolKey('$', '$', 'en-dollar'),
        literalSymbolKey('`', '`', 'en-grave'),
        literalSymbolKey('^', '^', 'en-caret'),
        literalSymbolKey('-', '-', 'en-minus'),
        literalSymbolKey('/', '/', 'en-slash')
      ],
      [
        literalSymbolKey('_', '_', 'en-underscore'),
        literalSymbolKey('%', '%', 'en-percent'),
        literalSymbolKey('<', '<', 'en-less'),
        literalSymbolKey('>', '>', 'en-greater'),
        literalSymbolKey('"', '"', 'en-double-quote'),
        literalSymbolKey("'", "'", 'en-single-quote'),
        literalSymbolKey('|', '|', 'en-pipe')
      ],
      [
        literalSymbolKey('{', '{', 'en-left-brace'),
        literalSymbolKey('}', '}', 'en-right-brace'),
        literalSymbolKey('[', '[', 'en-left-bracket'),
        literalSymbolKey(']', ']', 'en-right-bracket'),
        literalSymbolKey('(', '(', 'en-left-parenthesis'),
        literalSymbolKey(')', ')', 'en-right-parenthesis'),
        literalSymbolKey('\\', '\\', 'en-backslash')
      ],
      [
        literalSymbolKey('¢', '¢', 'en-cent'),
        literalSymbolKey('₿', '₿', 'en-bitcoin'),
        literalSymbolKey('£', '£', 'en-pound'),
        literalSymbolKey('€', '€', 'en-euro'),
        literalSymbolKey('¥', '¥', 'en-yen'),
        literalSymbolKey('~', '~', 'en-tilde')
      ]
    ]
    : [
      [
        literalSymbolKey('＃', '＃', 'zh-hash'),
        literalSymbolKey('＆', '＆', 'zh-ampersand'),
        literalSymbolKey('￥', '￥', 'zh-yen'),
        literalSymbolKey('……', '……', 'zh-ellipsis'),
        literalSymbolKey('——', '——', 'zh-em-dash'),
        literalSymbolKey('·', '·', 'zh-middle-dot'),
        literalSymbolKey('々', '々', 'zh-iteration-mark')
      ],
      [
        literalSymbolKey('＊', '＊', 'zh-star'),
        literalSymbolKey('%', '%', 'zh-percent'),
        literalSymbolKey('＜', '＜', 'zh-less'),
        literalSymbolKey('＞', '＞', 'zh-greater'),
        literalSymbolPairKey('〔', '〕', 'zh-tortoise-shell-pair'),
        literalSymbolPairKey('“', '”', 'zh-double-quote-pair'),
        literalSymbolPairKey('‘', '’', 'zh-single-quote-pair')
      ],
      [
        literalSymbolPairKey('【', '】', 'zh-square-pair'),
        literalSymbolPairKey('｛', '｝', 'zh-brace-pair'),
        literalSymbolPairKey('「', '」', 'zh-corner-pair'),
        literalSymbolPairKey('『', '』', 'zh-white-corner-pair'),
        literalSymbolPairKey('（', '）', 'zh-parenthesis-pair'),
        literalSymbolPairKey('《', '》', 'zh-book-pair'),
        literalSymbolPairKey('〈', '〉', 'zh-single-angle-pair')
      ],
      [
        literalSymbolKey('＝', '＝', 'zh-equals'),
        literalSymbolKey('＋', '＋', 'zh-plus'),
        literalSymbolKey('－', '－', 'zh-minus'),
        literalSymbolKey('×', '×', 'zh-times'),
        literalSymbolKey('÷', '÷', 'zh-divide'),
        literalSymbolKey('～', '～', 'zh-tilde')
      ]
    ];
  const bottomKeys = rows[rows.length - 1];
  if (showInputMethodSwitchKey) {
    bottomKeys.unshift(
      key('symbol-return', '返回', KeyboardKeyKind.MODE_SWITCH, 1,
        TOGGLE_SYMBOL_ACTION, '返回之前的键盘')
    );
    bottomKeys.push(inputMethodSwitchKey());
  }
  const symbolDelete = deleteKey(1);
  if (languageMode === KeyboardMode.CHINESE) {
    symbolDelete.label = '回删';
  }
  bottomKeys.push(symbolDelete);
  return {
    rows: rows.map((keys: KeyboardKeySpec[], index: number): KeyboardRowSpec => ({
      keys,
      kind: index === rows.length - 1 ? KeyboardRowKind.BOTTOM_ACTIONS : undefined
    }))
  };
}

export function createStage10KeyboardLayout(
  mode: KeyboardMode,
  context: EditorContext,
  shiftState: ShiftState,
  rawInput: string = '',
  chineseCapsLock: boolean = false,
  showInputMethodSwitchKey: boolean = false,
  shuangpinLayout: ShuangpinKeyboardLayout = ShuangpinKeyboardLayout.TWENTY_SIX_KEY,
  keyboardProfileId: string = '',
  symbolLanguageMode: KeyboardMode = KeyboardMode.CHINESE
): KeyboardLayoutSpec {
  switch (mode) {
    case KeyboardMode.CHINESE:
      if (keyboardProfileId === PINYIN_9_PROFILE_ID) {
        return createPinyin9KeyboardLayout(context);
      }
      if (shuangpinLayout === ShuangpinKeyboardLayout.EIGHTEEN_KEY) {
        return createEighteenKeyTextLayout(
          context,
          true,
          shiftState,
          chineseCapsLock,
          rawInput.length > 0
        );
      }
      return createChineseLayout(
        context,
        chineseCapsLock,
        showInputMethodSwitchKey,
        rawInput.length > 0
      );
    case KeyboardMode.NUMBER:
      return createNumberLayout(context, showInputMethodSwitchKey);
    case KeyboardMode.PHONE:
      return createPhoneLayout(context, showInputMethodSwitchKey);
    case KeyboardMode.SYMBOL:
      return createSymbolLayout(showInputMethodSwitchKey, symbolLanguageMode);
    default:
      if (shuangpinLayout === ShuangpinKeyboardLayout.EIGHTEEN_KEY) {
        return createEighteenKeyTextLayout(context, false, shiftState, false, false);
      }
      return createEnglishLayout(context, shiftState, showInputMethodSwitchKey);
  }
}
