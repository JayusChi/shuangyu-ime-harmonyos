import { enterActionAccessibilityText, enterActionLabel } from '../../../application/EnterActionPolicy';
import { EditorContext, EditorKind, ShiftState } from '../../../domain/editor/EditorContext';
import { ShuangpinKeyboardLayout } from '../../../domain/keyboard/ShuangpinKeyboardLayout';
import {
  createCharacterInputAction,
  createLetterInputAction,
  DELETE_ACTION,
  ENTER_ACTION,
  KeyboardAction,
  KeyboardMode,
  SHOW_INPUT_METHOD_PICKER_ACTION,
  SHIFT_ACTION,
  SPACE_ACTION,
  TOGGLE_LANGUAGE_ACTION,
  TOGGLE_CHINESE_CAPS_LOCK_ACTION,
  TOGGLE_NUMBER_ACTION,
  TOGGLE_SYMBOL_ACTION,
  SWITCH_INPUT_METHOD_ACTION,
  SECOND_CANDIDATE_OR_PUNCTUATION_ACTION,
  SECOND_CANDIDATE_OR_COMMA_ACTION
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

function letterKey(letter: string, shiftState: ShiftState): KeyboardKeySpec {
  const label = shiftState === ShiftState.LOWERCASE ? letter.toLowerCase() : letter.toUpperCase();
  return key(
    `letter-${letter}`,
    label,
    KeyboardKeyKind.LETTER,
    KEY_WEIGHTS.LETTER,
    createLetterInputAction(letter),
    `字母 ${label}`
  );
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

function groupedLetterKey(id: string, letters: string): KeyboardKeySpec {
  const labels = letters.split('');
  return segmentedKey(
    `group-${id}`,
    labels,
    labels.map((letter: string) => createLetterInputAction(letter.toLowerCase()))
  );
}

function letterRow(letters: string, shiftState: ShiftState): KeyboardKeySpec[] {
  return letters.split('').map((letter: string) => letterKey(letter, shiftState));
}

function enterKey(context: EditorContext, weight: number = 1.35): KeyboardKeySpec {
  return key(
    'enter',
    enterActionLabel(context.enterAction),
    KeyboardKeyKind.ENTER,
    weight,
    ENTER_ACTION,
    enterActionAccessibilityText(context.enterAction)
  );
}

function deleteKey(weight: number = 1.3): KeyboardKeySpec {
  return key('delete', '删除', KeyboardKeyKind.DELETE, weight, DELETE_ACTION, '删除前一个字符');
}

function inputMethodSwitchKey(weight: number = KEY_WEIGHTS.MODE_SWITCH): KeyboardKeySpec {
  const switchKey = key(
    'input-method-switch',
    '',
    KeyboardKeyKind.INPUT_METHOD_SWITCH,
    weight,
    SWITCH_INPUT_METHOD_ACTION,
    '切换输入法'
  );
  switchKey.longPressAction = SHOW_INPUT_METHOD_PICKER_ACTION;
  return switchKey;
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

function createStandardLetterRows(shiftState: ShiftState, chineseMode: boolean = false): KeyboardRowSpec[] {
  return [
    { keys: letterRow(QWERTY_TOP_ROW, shiftState), kind: KeyboardRowKind.TOP_LETTERS },
    { keys: letterRow(QWERTY_MIDDLE_ROW, shiftState), kind: KeyboardRowKind.MIDDLE_LETTERS },
    {
      keys: [
        shiftKey(shiftState, chineseMode),
        ...letterRow(QWERTY_BOTTOM_ROW, shiftState),
        deleteKey(KEY_WEIGHTS.DELETE)
      ],
      kind: KeyboardRowKind.BOTTOM_LETTERS
    }
  ];
}

function createChineseLetterRows(chineseCapsLock: boolean): KeyboardRowSpec[] {
  const uppercase = ShiftState.ONE_SHOT_UPPERCASE;
  return [
    { keys: letterRow(QWERTY_TOP_ROW, uppercase), kind: KeyboardRowKind.TOP_LETTERS },
    { keys: letterRow(QWERTY_MIDDLE_ROW, uppercase), kind: KeyboardRowKind.MIDDLE_LETTERS },
    {
      keys: [
        chineseShiftKey(chineseCapsLock),
        ...letterRow(QWERTY_BOTTOM_ROW, uppercase),
        deleteKey(KEY_WEIGHTS.DELETE)
      ],
      kind: KeyboardRowKind.BOTTOM_LETTERS
    }
  ];
}

function createTextBottomRow(
  context: EditorContext,
  chineseMode: boolean,
  showInputMethodSwitchKey: boolean = false
): KeyboardRowSpec {
  if (chineseMode) {
    // 26键中文底行与17键对齐：符/123、中/英、空格、标点(次选)、动作键
    const punctuation = segmentedKey(
      'punctuation-comma-period',
      ['，', '。'],
      [SECOND_CANDIDATE_OR_COMMA_ACTION, createCharacterInputAction('。')],
      KeyboardKeyKind.FUNCTION,
      1.25
    );
    const keys: KeyboardKeySpec[] = [];
    keys.push(key('number', '符/123', KeyboardKeyKind.MODE_SWITCH, 1.2,
      TOGGLE_NUMBER_ACTION, '切换到数字和符号键盘'));
    if (showInputMethodSwitchKey) {
      keys.push(inputMethodSwitchKey());
    }
    keys.push(key('language', '中', KeyboardKeyKind.MODE_SWITCH, 1.05,
      TOGGLE_LANGUAGE_ACTION, '切换到英文键盘'));
    const spaceWeight = showInputMethodSwitchKey
      ? 3.5 - KEY_WEIGHTS.MODE_SWITCH
      : 3.5;
    keys.push(key('space', '空格', KeyboardKeyKind.SPACE, spaceWeight, SPACE_ACTION, '空格'));
    keys.push(punctuation);
    keys.push(enterKey(context, KEY_WEIGHTS.ENTER));
    return { keys, kind: KeyboardRowKind.BOTTOM_ACTIONS };
  }
  // English mode bottom row unchanged
  const keys: KeyboardKeySpec[] = [];
  if (context.numberModeAllowed) {
    keys.push(key('number', '123', KeyboardKeyKind.MODE_SWITCH, KEY_WEIGHTS.MODE_SWITCH,
      TOGGLE_NUMBER_ACTION, '切换到数字键盘'));
  }
  if (showInputMethodSwitchKey) {
    keys.push(inputMethodSwitchKey());
  }
  if (context.chineseModeAllowed) {
    const languageKey = key('language', '中', KeyboardKeyKind.MODE_SWITCH,
      KEY_WEIGHTS.MODE_SWITCH, TOGGLE_LANGUAGE_ACTION, '切换到中文键盘');
    keys.push(languageKey);
  }
  const spaceWeight = showInputMethodSwitchKey
    ? KEY_WEIGHTS.SPACE - KEY_WEIGHTS.MODE_SWITCH
    : KEY_WEIGHTS.SPACE;
  keys.push(key('space', '空格', KeyboardKeyKind.SPACE, spaceWeight, SPACE_ACTION, '空格'));
  if (context.symbolModeAllowed) {
    keys.push(key('symbol', '#+=', KeyboardKeyKind.MODE_SWITCH, KEY_WEIGHTS.MODE_SWITCH,
      TOGGLE_SYMBOL_ACTION, '切换到符号键盘'));
  }
  keys.push(enterKey(context, KEY_WEIGHTS.ENTER));
  return { keys, kind: KeyboardRowKind.BOTTOM_ACTIONS };
}

function createSeventeenKeyTextLayout(context: EditorContext, chineseMode: boolean): KeyboardLayoutSpec {
  const punctuation = segmentedKey(
    'punctuation-comma-period',
    chineseMode ? ['，', '。'] : [',', '.'],
    chineseMode
      ? [SECOND_CANDIDATE_OR_COMMA_ACTION, createCharacterInputAction('。')]
      : [createCharacterInputAction(','), createCharacterInputAction('.')],
    KeyboardKeyKind.FUNCTION,
    1.25
  );
  return {
    rows: [
      {
        keys: [
          groupedLetterKey('hp', 'HP'),
          groupedLetterKey('sh', 'SH'),
          groupedLetterKey('zh', 'ZH'),
          groupedLetterKey('b', 'B'),
          groupedLetterKey('oxv', 'OXV'),
          groupedLetterKey('ms', 'MS')
        ]
      },
      {
        keys: [
          groupedLetterKey('l', 'L'),
          groupedLetterKey('d', 'D'),
          groupedLetterKey('y', 'Y'),
          groupedLetterKey('wz', 'WZ'),
          groupedLetterKey('jk', 'JK'),
          groupedLetterKey('nr', 'NR')
        ]
      },
      {
        keys: [
          groupedLetterKey('ch', 'CH'),
          groupedLetterKey('q', 'Q'),
          groupedLetterKey('g', 'G'),
          groupedLetterKey('cf', 'CF'),
          groupedLetterKey('t', 'T'),
          deleteKey(1)
        ]
      },
      {
        keys: [
          key('number', '符/123', KeyboardKeyKind.MODE_SWITCH, 1.2,
            TOGGLE_NUMBER_ACTION, '切换到数字和符号键盘'),
          key('language', chineseMode ? '中' : '英', KeyboardKeyKind.MODE_SWITCH, 1.05,
            TOGGLE_LANGUAGE_ACTION, chineseMode ? '切换到英文键盘' : '切换到中文键盘'),
          key('space', '空格', KeyboardKeyKind.SPACE, 3.5, SPACE_ACTION, '空格'),
          punctuation,
          enterKey(context, KEY_WEIGHTS.ENTER)
        ],
        kind: KeyboardRowKind.BOTTOM_ACTIONS
      }
    ]
  };
}

function createChineseLayout(
  context: EditorContext,
  chineseCapsLock: boolean,
  showInputMethodSwitchKey: boolean
): KeyboardLayoutSpec {
  return {
    rows: [
      ...createChineseLetterRows(chineseCapsLock),
      createTextBottomRow(context, true, showInputMethodSwitchKey)
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

function createSymbolLayout(context: EditorContext, showInputMethodSwitchKey: boolean): KeyboardLayoutSpec {
  const bottomKeys: KeyboardKeySpec[] = [];
  if (showInputMethodSwitchKey) {
    bottomKeys.push(inputMethodSwitchKey());
  }
  bottomKeys.push(
    key('symbol-return', '返回', KeyboardKeyKind.MODE_SWITCH, 1.2, TOGGLE_SYMBOL_ACTION, '返回之前的键盘'),
    key('space', '空格', KeyboardKeyKind.SPACE, KEY_WEIGHTS.SYMBOL_SPACE, SPACE_ACTION, '空格'),
    deleteKey(),
    enterKey(context, KEY_WEIGHTS.SYMBOL_ENTER)
  );
  return {
    rows: [
      { keys: ['!', '@', '#', '$', '%', '^', '&', '*'].map((value: string) => characterKey(value)) },
      { keys: ['(', ')', '-', '_', '=', '+', '[', ']'].map((value: string) => characterKey(value)) },
      { keys: ['.', ',', '?', '/', ':', ';', "'", '"'].map((value: string) => characterKey(value)) },
      { keys: bottomKeys }
    ]
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
  keyboardProfileId: string = ''
): KeyboardLayoutSpec {
  switch (mode) {
    case KeyboardMode.CHINESE:
      if (keyboardProfileId === PINYIN_9_PROFILE_ID) {
        return createPinyin9KeyboardLayout(context);
      }
      if (shuangpinLayout === ShuangpinKeyboardLayout.SEVENTEEN_KEY) {
        return createSeventeenKeyTextLayout(context, true);
      }
      return createChineseLayout(context, chineseCapsLock, showInputMethodSwitchKey);
    case KeyboardMode.NUMBER:
      return createNumberLayout(context, showInputMethodSwitchKey);
    case KeyboardMode.PHONE:
      return createPhoneLayout(context, showInputMethodSwitchKey);
    case KeyboardMode.SYMBOL:
      return createSymbolLayout(context, showInputMethodSwitchKey);
    default:
      if (shuangpinLayout === ShuangpinKeyboardLayout.SEVENTEEN_KEY) {
        return createSeventeenKeyTextLayout(context, false);
      }
      return createEnglishLayout(context, shiftState, showInputMethodSwitchKey);
  }
}
