export enum KeyboardMode {
  ENGLISH = 'english',
  CHINESE = 'chinese_placeholder',
  CHINESE_PLACEHOLDER = 'chinese_placeholder',
  NUMBER = 'number',
  PHONE = 'phone',
  SYMBOL = 'symbol'
}

export enum KeyboardActionType {
  LETTER = 'letter',
  T9_PINYIN_DIGIT = 't9_pinyin_digit',
  CHARACTER = 'character',
  CONVENIENCE_GUIDE = 'convenience_guide',
  SECOND_CANDIDATE_OR_PASTE = 'second_candidate_or_paste',
  DELETE = 'delete',
  SPACE = 'space',
  ENTER = 'enter',
  SHIFT = 'shift',
  TOGGLE_CHINESE_CAPS_LOCK = 'toggle_chinese_caps_lock',
  INSERT_SEGMENT_BOUNDARY = 'insert_segment_boundary',
  TOGGLE_LANGUAGE = 'toggle_language',
  TOGGLE_NUMBER = 'toggle_number',
  TOGGLE_SYMBOL = 'toggle_symbol',
  SWITCH_INPUT_METHOD = 'switch_input_method',
  SHOW_INPUT_METHOD_PICKER = 'show_input_method_picker',
  HIDE_KEYBOARD = 'hide_keyboard',
  MOVE_CURSOR_LEFT = 'move_cursor_left',
  MOVE_CURSOR_RIGHT = 'move_cursor_right',
  SECOND_CANDIDATE_OR_PUNCTUATION = 'second_candidate_or_punctuation',
  SECOND_CANDIDATE_OR_COMMA = 'second_candidate_or_comma',
  SECOND_CANDIDATE_OR_PERIOD = 'second_candidate_or_period',
  THIRD_CANDIDATE_OR_COMMA = 'third_candidate_or_comma',
  REPEAT_LAST_COMMIT = 'repeat_last_commit',
  UNDO_LAST_COMMIT = 'undo_last_commit',
  DELETE_CURRENT_LINE = 'delete_current_line',
  RESTORE_LAST_DELETION = 'restore_last_deletion',
  SELECT_ALL = 'select_all',
  CUT = 'cut',
  COPY = 'copy',
  PASTE = 'paste',
  CANCEL_COMPOSITION = 'cancel_composition',
  EXPAND_CANDIDATES = 'expand_candidates',
  UNIVERSAL_KEY = 'universal_key'
}

/** Native editor actions exposed by HarmonyOS InputClient.sendExtendAction. */
export enum EditorExtendAction {
  SELECT_ALL = 0,
  CUT = 3,
  COPY = 4,
  PASTE = 5
}

export interface KeyboardAction {
  type: KeyboardActionType;
  letter?: string;
  digit?: string;
  character?: string;
  /** Bypasses punctuation/full-width conversion so an upper-deck key outputs its printed value. */
  literal?: boolean;
  /** UTF-16 units to move left after inserting a literal pair. */
  cursorOffsetUtf16?: number;
}

export function createLetterInputAction(letter: string): KeyboardAction {
  return {
    type: KeyboardActionType.LETTER,
    letter
  };
}

export function createCharacterInputAction(character: string): KeyboardAction {
  return {
    type: KeyboardActionType.CHARACTER,
    character
  };
}

export function createLiteralCharacterInputAction(character: string): KeyboardAction {
  return {
    type: KeyboardActionType.CHARACTER,
    character,
    literal: true
  };
}

export function createLiteralPairInputAction(
  text: string,
  cursorOffsetUtf16: number
): KeyboardAction {
  return {
    type: KeyboardActionType.CHARACTER,
    character: text,
    literal: true,
    cursorOffsetUtf16
  };
}

/**
 * Dedicated 9-key Chinese input action. The digit is forwarded unchanged to
 * the active Rust T9 parser; ArkTS must never expand it into letters.
 */
export function createT9PinyinDigitAction(digit: string): KeyboardAction {
  return {
    type: KeyboardActionType.T9_PINYIN_DIGIT,
    digit
  };
}

export function isT9PinyinDigit(value: string | undefined): boolean {
  return value !== undefined && value.length === 1 && value >= '2' && value <= '9';
}

export const DELETE_ACTION: KeyboardAction = {
  type: KeyboardActionType.DELETE
};

export const SPACE_ACTION: KeyboardAction = {
  type: KeyboardActionType.SPACE
};

export const ENTER_ACTION: KeyboardAction = {
  type: KeyboardActionType.ENTER
};

export const SHIFT_ACTION: KeyboardAction = {
  type: KeyboardActionType.SHIFT
};

export const TOGGLE_CHINESE_CAPS_LOCK_ACTION: KeyboardAction = {
  type: KeyboardActionType.TOGGLE_CHINESE_CAPS_LOCK
};

export const INSERT_SEGMENT_BOUNDARY_ACTION: KeyboardAction = {
  type: KeyboardActionType.INSERT_SEGMENT_BOUNDARY
};

export const TOGGLE_LANGUAGE_ACTION: KeyboardAction = {
  type: KeyboardActionType.TOGGLE_LANGUAGE
};

export const TOGGLE_NUMBER_ACTION: KeyboardAction = {
  type: KeyboardActionType.TOGGLE_NUMBER
};

export const TOGGLE_SYMBOL_ACTION: KeyboardAction = {
  type: KeyboardActionType.TOGGLE_SYMBOL
};

export const HIDE_KEYBOARD_ACTION: KeyboardAction = {
  type: KeyboardActionType.HIDE_KEYBOARD
};

export const MOVE_CURSOR_LEFT_ACTION: KeyboardAction = {
  type: KeyboardActionType.MOVE_CURSOR_LEFT
};

export const MOVE_CURSOR_RIGHT_ACTION: KeyboardAction = {
  type: KeyboardActionType.MOVE_CURSOR_RIGHT
};

export const SWITCH_INPUT_METHOD_ACTION: KeyboardAction = {
  type: KeyboardActionType.SWITCH_INPUT_METHOD
};

export const SHOW_INPUT_METHOD_PICKER_ACTION: KeyboardAction = {
  type: KeyboardActionType.SHOW_INPUT_METHOD_PICKER
};

export const SECOND_CANDIDATE_OR_PUNCTUATION_ACTION: KeyboardAction = {
  type: KeyboardActionType.SECOND_CANDIDATE_OR_PUNCTUATION
};

export const SECOND_CANDIDATE_OR_COMMA_ACTION: KeyboardAction = {
  type: KeyboardActionType.SECOND_CANDIDATE_OR_COMMA
};

export const SECOND_CANDIDATE_OR_PERIOD_ACTION: KeyboardAction = {
  type: KeyboardActionType.SECOND_CANDIDATE_OR_PERIOD
};

export const THIRD_CANDIDATE_OR_COMMA_ACTION: KeyboardAction = {
  type: KeyboardActionType.THIRD_CANDIDATE_OR_COMMA
};

export const REPEAT_LAST_COMMIT_ACTION: KeyboardAction = {
  type: KeyboardActionType.REPEAT_LAST_COMMIT
};

export const UNDO_LAST_COMMIT_ACTION: KeyboardAction = {
  type: KeyboardActionType.UNDO_LAST_COMMIT
};

export const DELETE_CURRENT_LINE_ACTION: KeyboardAction = {
  type: KeyboardActionType.DELETE_CURRENT_LINE
};

export const RESTORE_LAST_DELETION_ACTION: KeyboardAction = {
  type: KeyboardActionType.RESTORE_LAST_DELETION
};

export const SELECT_ALL_ACTION: KeyboardAction = {
  type: KeyboardActionType.SELECT_ALL
};

export const CUT_ACTION: KeyboardAction = {
  type: KeyboardActionType.CUT
};

export const COPY_ACTION: KeyboardAction = {
  type: KeyboardActionType.COPY
};

export const PASTE_ACTION: KeyboardAction = {
  type: KeyboardActionType.PASTE
};

export const CANCEL_COMPOSITION_ACTION: KeyboardAction = {
  type: KeyboardActionType.CANCEL_COMPOSITION
};

export const EXPAND_CANDIDATES_ACTION: KeyboardAction = {
  type: KeyboardActionType.EXPAND_CANDIDATES
};

export const UNIVERSAL_KEY_ACTION: KeyboardAction = {
  type: KeyboardActionType.UNIVERSAL_KEY
};

export function isSingleAsciiLetter(value: string | undefined): boolean {
  if (!value || value.length !== 1) {
    return false;
  }

  return /^[a-zA-Z]$/.test(value);
}

export const CONVENIENCE_GUIDE_ACTION: KeyboardAction = {
  type: KeyboardActionType.CONVENIENCE_GUIDE, character: '='
};
export const SECOND_CANDIDATE_OR_PASTE_ACTION: KeyboardAction = {
  type: KeyboardActionType.SECOND_CANDIDATE_OR_PASTE
};
