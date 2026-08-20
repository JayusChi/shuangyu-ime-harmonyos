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
  SECOND_CANDIDATE_OR_PUNCTUATION = 'second_candidate_or_punctuation',
  SECOND_CANDIDATE_OR_COMMA = 'second_candidate_or_comma',
  REPEAT_LAST_COMMIT = 'repeat_last_commit',
  UNDO_LAST_COMMIT = 'undo_last_commit'
}

export interface KeyboardAction {
  type: KeyboardActionType;
  letter?: string;
  digit?: string;
  character?: string;
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

export const REPEAT_LAST_COMMIT_ACTION: KeyboardAction = {
  type: KeyboardActionType.REPEAT_LAST_COMMIT
};

export const UNDO_LAST_COMMIT_ACTION: KeyboardAction = {
  type: KeyboardActionType.UNDO_LAST_COMMIT
};

export function isSingleAsciiLetter(value: string | undefined): boolean {
  if (!value || value.length !== 1) {
    return false;
  }

  return /^[a-zA-Z]$/.test(value);
}
