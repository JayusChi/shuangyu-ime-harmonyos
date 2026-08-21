import {
  createLetterInputAction,
  DELETE_ACTION,
  ENTER_ACTION,
  KeyboardAction,
  SPACE_ACTION,
  TOGGLE_LANGUAGE_ACTION
} from '../../../domain/keyboard/KeyboardAction';

/**
 * 按键种类
 */
export enum KeyboardKeyKind {
  LETTER = 'letter',
  T9_DIGIT = 't9_digit',
  FUNCTION = 'function',
  DELETE = 'delete',
  SPACE = 'space',
  ENTER = 'enter',
  SHIFT = 'shift',
  MODE_SWITCH = 'mode_switch',
  INPUT_METHOD_SWITCH = 'input_method_switch'
}

/**
 * 按键规格
 */
export interface KeyboardKeySpec {
  id: string;
  label: string;
  /** Small upper-deck hint shown above the primary key label. */
  upperLabel?: string;
  secondaryLabel?: string;
  previewLabel?: string;
  kind: KeyboardKeyKind;
  weight: number;
  action: KeyboardAction;
  longPressAction?: KeyboardAction;
  swipeUpAction?: KeyboardAction;
  previewEnabled: boolean;
  accessibilityLabel: string;
  active?: boolean;
  alternatives?: KeyboardKeyAlternativeSpec[];
}

/**
 * 一个组合键帽内可直接点选的子项。18 键分组布局在同一键帽内为每个
 * 字母提供独立点击目标，保证 26 个字母均可直接输入。
 */
export interface KeyboardKeyAlternativeSpec {
  label: string;
  action: KeyboardAction;
  accessibilityLabel: string;
}

/**
 * 行在标准全键盘中的结构用途。正式运行布局用它应用统一的行缩进，
 * 旧版兼容布局可以省略并继续按普通行渲染。
 */
export enum KeyboardRowKind {
  TOP_LETTERS = 'top_letters',
  MIDDLE_LETTERS = 'middle_letters',
  BOTTOM_LETTERS = 'bottom_letters',
  AUXILIARY = 'auxiliary',
  BOTTOM_ACTIONS = 'bottom_actions'
}

/**
 * 键盘行规格
 */
export interface KeyboardRowSpec {
  keys: KeyboardKeySpec[];
  kind?: KeyboardRowKind;
}

/**
 * 键盘布局规格
 */
export interface KeyboardLayoutSpec {
  rows: KeyboardRowSpec[];
}

/**
 * 创建字母按键
 */
function letterKey(letter: string): KeyboardKeySpec {
  return {
    id: `letter-${letter}`,
    label: letter.toUpperCase(),
    kind: KeyboardKeyKind.LETTER,
    weight: 1,
    action: createLetterInputAction(letter),
    previewEnabled: true,
    accessibilityLabel: `字母 ${letter}`
  };
}

/**
 * 创建功能按键
 */
function functionKey(
  id: string,
  label: string,
  kind: KeyboardKeyKind,
  weight: number,
  action: KeyboardAction
): KeyboardKeySpec {
  return {
    id,
    label,
    kind,
    weight,
    action,
    previewEnabled: false,
    accessibilityLabel: label
  };
}

/**
 * QWERTY布局定义
 */
export const QWERTY_LAYOUT: KeyboardLayoutSpec = {
  rows: [
    // Q行
    {
      keys: 'qwertyuiop'.split('').map(letter => letterKey(letter))
    },
    // A行
    {
      keys: 'asdfghjkl'.split('').map(letter => letterKey(letter))
    },
    // Z行
    {
      keys: [
        ...('zxcvbnm'.split('').map(letter => letterKey(letter))),
        functionKey('delete', '删除', KeyboardKeyKind.DELETE, 1.25, DELETE_ACTION)
      ]
    },
    // 功能键行
    {
      keys: [
        functionKey('mode-switch', '英', KeyboardKeyKind.MODE_SWITCH, 1.1, TOGGLE_LANGUAGE_ACTION),
        functionKey('space', '空格', KeyboardKeyKind.SPACE, 4.8, SPACE_ACTION),
        functionKey('enter', '回车', KeyboardKeyKind.ENTER, 1.55, ENTER_ACTION)
      ]
    }
  ]
};

/**
 * 兼容性：导出旧版接口供阶段2代码使用
 * @deprecated 使用 QWERTY_LAYOUT 和 KeyboardKeySpec
 */
export enum KeyboardKeyRole {
  LETTER = 'letter',
  MODE = 'mode',
  SPACE = 'space',
  DELETE = 'delete',
  ENTER = 'enter'
}

/**
 * 兼容性：旧版按键规格
 * @deprecated 使用 KeyboardKeySpec
 */
export interface LegacyKeyboardKeySpec {
  id: string;
  label: string;
  role: KeyboardKeyRole;
  weight: number;
  action: KeyboardAction;
}

/**
 * 将新版KeyboardKeySpec转换为旧版格式
 */
function convertToLegacy(spec: KeyboardKeySpec): LegacyKeyboardKeySpec {
  let role: KeyboardKeyRole;
  switch (spec.kind) {
    case KeyboardKeyKind.LETTER:
      role = KeyboardKeyRole.LETTER;
      break;
    case KeyboardKeyKind.MODE_SWITCH:
      role = KeyboardKeyRole.MODE;
      break;
    case KeyboardKeyKind.SPACE:
      role = KeyboardKeyRole.SPACE;
      break;
    case KeyboardKeyKind.DELETE:
      role = KeyboardKeyRole.DELETE;
      break;
    case KeyboardKeyKind.ENTER:
      role = KeyboardKeyRole.ENTER;
      break;
    default:
      role = KeyboardKeyRole.LETTER;
  }

  return {
    id: spec.id,
    label: spec.label,
    role: role,
    weight: spec.weight,
    action: spec.action
  };
}

/**
 * 兼容性：导出旧版QWERTY_KEY_ROWS
 * @deprecated 使用 QWERTY_LAYOUT
 */
export const QWERTY_KEY_ROWS: LegacyKeyboardKeySpec[][] = QWERTY_LAYOUT.rows.map(
  row => row.keys.map(key => convertToLegacy(key))
);
