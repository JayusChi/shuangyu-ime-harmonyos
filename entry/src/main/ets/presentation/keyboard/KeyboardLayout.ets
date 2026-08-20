import {
  createLetterInputAction,
  DELETE_ACTION,
  ENTER_ACTION,
  KeyboardAction,
  KeyboardActionType,
  SPACE_ACTION,
  TOGGLE_LANGUAGE_ACTION
} from '../../domain/keyboard/KeyboardAction';

export enum KeyboardKeyRole {
  LETTER = 'letter',
  MODE = 'mode',
  SPACE = 'space',
  DELETE = 'delete',
  ENTER = 'enter'
}

export interface KeyboardKeySpec {
  id: string;
  label: string;
  role: KeyboardKeyRole;
  weight: number;
  action: KeyboardAction;
}

function letterKey(letter: string): KeyboardKeySpec {
  return {
    id: `letter-${letter}`,
    label: letter.toUpperCase(),
    role: KeyboardKeyRole.LETTER,
    weight: 1,
    action: createLetterInputAction(letter)
  };
}

function actionKey(id: string, label: string, role: KeyboardKeyRole, weight: number, action: KeyboardAction): KeyboardKeySpec {
  return {
    id,
    label,
    role,
    weight,
    action
  };
}

export const QWERTY_KEY_ROWS: KeyboardKeySpec[][] = [
  'qwertyuiop'.split('').map((letter: string) => letterKey(letter)),
  'asdfghjkl'.split('').map((letter: string) => letterKey(letter)),
  'zxcvbnm'.split('').map((letter: string) => letterKey(letter)),
  [
    actionKey('toggle-language', '英', KeyboardKeyRole.MODE, 1.1, TOGGLE_LANGUAGE_ACTION),
    actionKey('space', '空格', KeyboardKeyRole.SPACE, 4.8, SPACE_ACTION),
    actionKey('delete', '删除', KeyboardKeyRole.DELETE, 1.25, DELETE_ACTION),
    actionKey('enter', '回车', KeyboardKeyRole.ENTER, 1.55, ENTER_ACTION)
  ]
];

export function keyboardActionKey(action: KeyboardAction): string {
  if (action.type === KeyboardActionType.LETTER) {
    return `letter-${action.letter ?? ''}`;
  }

  return action.type;
}
