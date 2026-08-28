import {
  BUILTIN_KEYBOARD_SKIN_ID,
  BUILTIN_KEYBOARD_STRUCTURE_ID,
  KeyboardCustomizationOption,
  KeyboardSkinDefinition,
  KeyboardStructureDefinition,
  KeyboardStructureKeyDefinition,
  KeyboardStructureRowDefinition
} from './KeyboardCustomization';

export const WIDE_SPACE_STRUCTURE_ID: string = 'builtin.wide-space';
export const CENTER_SPACE_STRUCTURE_ID: string = 'builtin.center-space';
export const SOFT_BLUE_SKIN_ID: string = 'builtin.soft-blue';
export const SAKURA_SKIN_ID: string = 'builtin.sakura';
export const INK_PURPLE_SKIN_ID: string = 'builtin.ink-purple';

function key(id: string, weight?: number, label?: string): KeyboardStructureKeyDefinition {
  const definition: KeyboardStructureKeyDefinition = { id };
  if (weight !== undefined) {
    definition.weight = weight;
  }
  if (label !== undefined) {
    definition.label = label;
  }
  return definition;
}

function row(kind: string, ids: string[]): KeyboardStructureRowDefinition {
  return {
    kind,
    keys: ids.map((id: string): KeyboardStructureKeyDefinition => key(id))
  };
}

function letterRows(): KeyboardStructureRowDefinition[] {
  return [
    row('top_letters', [
      'letter-q', 'letter-w', 'letter-e', 'letter-r', 'letter-t',
      'letter-y', 'letter-u', 'letter-i', 'letter-o', 'letter-p'
    ]),
    row('middle_letters', [
      'letter-a', 'letter-s', 'letter-d', 'letter-f', 'letter-g',
      'letter-h', 'letter-j', 'letter-k', 'letter-l'
    ]),
    {
      kind: 'bottom_letters',
      keys: [
        key('left-action', 1.35), key('letter-z'), key('letter-x'), key('letter-c'),
        key('letter-v'), key('letter-b'), key('letter-n'), key('letter-m'), key('delete', 1.35)
      ]
    }
  ];
}

function wideSpaceStructure(): KeyboardStructureDefinition {
  const rows = letterRows();
  rows.push({
    kind: 'bottom_actions',
    keys: [
      key('number', 1), key('punctuation-comma', 0.85), key('space', 5.2, '空格'),
      key('punctuation-period', 0.85), key('enter', 1.6)
    ]
  });
  return {
    schemaVersion: 1,
    id: WIDE_SPACE_STRUCTURE_ID,
    name: '宽空格布局',
    rows
  };
}

function centerSpaceStructure(): KeyboardStructureDefinition {
  const rows = letterRows();
  rows.push({
    kind: 'bottom_actions',
    keys: [
      key('number', 1), key('punctuation-comma', 0.95), key('space', 4.8, '空格'),
      key('punctuation-period', 0.95), key('enter', 1.55)
    ]
  });
  return {
    schemaVersion: 1,
    id: CENTER_SPACE_STRUCTURE_ID,
    name: '居中空格布局',
    rows
  };
}

const SOFT_BLUE_SKIN: KeyboardSkinDefinition = {
  schemaVersion: 1,
  id: SOFT_BLUE_SKIN_ID,
  name: '柔和蓝',
  colors: {
    panelBackground: '#D8E4F4',
    candidateBackground: '#EDF4FC',
    letterKeyBackground: '#F8FBFF',
    functionKeyBackground: '#C7D8EE',
    spaceKeyBackground: '#F8FBFF',
    primaryFunctionBackground: '#6F9FD8',
    letterKeyPressedBackground: '#B7CDE8',
    functionKeyPressedBackground: '#AFC7E4',
    primaryFunctionPressedBackground: '#507FB8',
    letterKeyText: '#18324F',
    functionKeyText: '#18324F',
    primaryFunctionText: '#FFFFFF',
    candidateText: '#18324F',
    candidateReading: '#607D9E',
    candidateDivider: '#B7CAE0',
    keyBorder: '#B7CAE0'
  },
  images: {}
};

const SAKURA_SKIN: KeyboardSkinDefinition = {
  schemaVersion: 1,
  id: SAKURA_SKIN_ID,
  name: '樱花粉',
  colors: {
    panelBackground: '#F7E4EA',
    candidateBackground: '#FFF4F7',
    letterKeyBackground: '#FFFAFC',
    functionKeyBackground: '#F1CAD6',
    spaceKeyBackground: '#FFF8FB',
    primaryFunctionBackground: '#D77C9A',
    letterKeyPressedBackground: '#EEC5D2',
    functionKeyPressedBackground: '#DFADC0',
    primaryFunctionPressedBackground: '#B85C7A',
    letterKeyText: '#542536',
    functionKeyText: '#542536',
    primaryFunctionText: '#FFFFFF',
    candidateText: '#542536',
    candidateReading: '#936174',
    candidateDivider: '#E3B7C5',
    keyBorder: '#E3B7C5'
  },
  images: {}
};

const INK_PURPLE_SKIN: KeyboardSkinDefinition = {
  schemaVersion: 1,
  id: INK_PURPLE_SKIN_ID,
  name: '墨紫夜色',
  colors: {
    panelBackground: '#191724',
    candidateBackground: '#211E2E',
    letterKeyBackground: '#302C42',
    functionKeyBackground: '#45405B',
    spaceKeyBackground: '#302C42',
    primaryFunctionBackground: '#8B6FC7',
    letterKeyPressedBackground: '#514A6B',
    functionKeyPressedBackground: '#5E567A',
    primaryFunctionPressedBackground: '#7054AD',
    letterKeyText: '#F6F1FF',
    functionKeyText: '#EEE7FA',
    primaryFunctionText: '#FFFFFF',
    candidateText: '#F6F1FF',
    candidateReading: '#BEB2D6',
    candidateDivider: '#4B4561',
    keyBorder: '#4B4561'
  },
  images: {}
};

export function bundledKeyboardStructureOptions(): KeyboardCustomizationOption[] {
  return [
    { id: BUILTIN_KEYBOARD_STRUCTURE_ID, name: '默认键盘结构', builtIn: true },
    { id: WIDE_SPACE_STRUCTURE_ID, name: '宽空格布局', builtIn: true },
    { id: CENTER_SPACE_STRUCTURE_ID, name: '居中空格布局', builtIn: true }
  ];
}

export function bundledKeyboardSkinOptions(): KeyboardCustomizationOption[] {
  return [
    { id: BUILTIN_KEYBOARD_SKIN_ID, name: '默认皮肤（跟随系统）', builtIn: true },
    { id: SOFT_BLUE_SKIN_ID, name: '柔和蓝', builtIn: true },
    { id: SAKURA_SKIN_ID, name: '樱花粉', builtIn: true },
    { id: INK_PURPLE_SKIN_ID, name: '墨紫夜色', builtIn: true }
  ];
}

export function loadBundledKeyboardStructure(id: string): KeyboardStructureDefinition | undefined {
  if (id === WIDE_SPACE_STRUCTURE_ID) {
    return wideSpaceStructure();
  }
  if (id === CENTER_SPACE_STRUCTURE_ID) {
    return centerSpaceStructure();
  }
  return undefined;
}

export function loadBundledKeyboardSkin(id: string): KeyboardSkinDefinition | undefined {
  if (id === SOFT_BLUE_SKIN_ID) {
    return SOFT_BLUE_SKIN;
  }
  if (id === SAKURA_SKIN_ID) {
    return SAKURA_SKIN;
  }
  if (id === INK_PURPLE_SKIN_ID) {
    return INK_PURPLE_SKIN;
  }
  return undefined;
}
