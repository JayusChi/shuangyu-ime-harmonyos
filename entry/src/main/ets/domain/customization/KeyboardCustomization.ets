export const BUILTIN_KEYBOARD_STRUCTURE_ID: string = 'builtin.default';
export const BUILTIN_KEYBOARD_SKIN_ID: string = 'builtin.follow-system';
export const KEYBOARD_CUSTOMIZATION_SCHEMA_VERSION: number = 1;

const IDENTIFIER_PATTERN: RegExp = /^[a-z0-9][a-z0-9._-]{0,63}$/;
const COLOR_PATTERN: RegExp = /^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/;
const ASSET_PATTERN: RegExp = /^assets\/[a-zA-Z0-9][a-zA-Z0-9._-]{0,95}\.(png|jpg|jpeg|webp)$/;
const LETTER_IDS: string[] = 'abcdefghijklmnopqrstuvwxyz'.split('').map((letter: string): string =>
  `letter-${letter}`);
const REQUIRED_STRUCTURE_KEYS: string[] = LETTER_IDS.concat(['left-action', 'delete', 'space', 'enter']);
const ALLOWED_STRUCTURE_KEYS: string[] = REQUIRED_STRUCTURE_KEYS.concat([
  'symbol', 'number', 'punctuation-comma-period', 'punctuation-comma', 'punctuation-period',
  'input-method-switch'
]);

export interface KeyboardStructureKeyDefinition {
  id: string;
  weight?: number;
  label?: string;
}

export interface KeyboardStructureRowDefinition {
  kind?: string;
  keys: KeyboardStructureKeyDefinition[];
}

export interface KeyboardStructureDefinition {
  schemaVersion: number;
  id: string;
  name: string;
  rows: KeyboardStructureRowDefinition[];
}

export interface KeyboardSkinColors {
  panelBackground?: string;
  candidateBackground?: string;
  letterKeyBackground?: string;
  functionKeyBackground?: string;
  spaceKeyBackground?: string;
  primaryFunctionBackground?: string;
  modeKeyBackgroundEnglish?: string;
  modeKeyBackgroundChinese?: string;
  letterKeyPressedBackground?: string;
  functionKeyPressedBackground?: string;
  primaryFunctionPressedBackground?: string;
  letterKeyText?: string;
  functionKeyText?: string;
  primaryFunctionText?: string;
  modeKeyTextEnglish?: string;
  modeKeyTextChinese?: string;
  errorText?: string;
  previewBackground?: string;
  previewText?: string;
  previewShadow?: string;
  candidateText?: string;
  candidateReading?: string;
  candidateDivider?: string;
  keyBorder?: string;
}

export interface KeyboardSkinImages {
  panelBackground?: string;
  letterKey?: string;
  functionKey?: string;
  spaceKey?: string;
  enterKey?: string;
}

export interface KeyboardSkinDefinition {
  schemaVersion: number;
  id: string;
  name: string;
  colors: KeyboardSkinColors;
  images: KeyboardSkinImages;
}

export interface KeyboardCustomizationOption {
  id: string;
  name: string;
  builtIn: boolean;
}

export interface KeyboardCustomizationParseResult<T> {
  success: boolean;
  message: string;
  value?: T;
}

function failure<T>(message: string): KeyboardCustomizationParseResult<T> {
  return { success: false, message };
}

function success<T>(value: T): KeyboardCustomizationParseResult<T> {
  return { success: true, message: '', value };
}

function validPackageIdentity(record: Record<string, Object>): string {
  const schemaVersion = record['schemaVersion'];
  const id = record['id'];
  const name = record['name'];
  if (schemaVersion !== KEYBOARD_CUSTOMIZATION_SCHEMA_VERSION) {
    return '模板版本不受支持';
  }
  if (typeof id !== 'string' || !IDENTIFIER_PATTERN.test(id) || id.startsWith('builtin.')) {
    return '模板 ID 必须由小写字母、数字、点、横线或下划线组成';
  }
  if (typeof name !== 'string' || name.trim().length <= 0 || name.trim().length > 64) {
    return '模板名称长度必须为 1～64 个字符';
  }
  return '';
}

function parseRowKind(value: Object | undefined): string | undefined {
  if (value === undefined) {
    return undefined;
  }
  if (value === 'top_letters' || value === 'middle_letters' || value === 'bottom_letters' ||
    value === 'auxiliary' || value === 'bottom_actions') {
    return value as string;
  }
  return undefined;
}

export function parseKeyboardStructureJson(content: string): KeyboardCustomizationParseResult<KeyboardStructureDefinition> {
  let record: Record<string, Object>;
  try {
    record = JSON.parse(content) as Record<string, Object>;
  } catch (_err) {
    return failure('layout.json 不是有效的 JSON');
  }
  if (record === null || typeof record !== 'object' || Array.isArray(record)) {
    return failure('layout.json 根节点必须是对象');
  }
  const identityError = validPackageIdentity(record);
  if (identityError.length > 0) {
    return failure(identityError);
  }
  const rawRows = record['rows'];
  if (!Array.isArray(rawRows) || rawRows.length < 3 || rawRows.length > 6) {
    return failure('键盘结构必须包含 3～6 行');
  }

  const seenIds: string[] = [];
  const rows: KeyboardStructureRowDefinition[] = [];
  for (const rawRow of rawRows as Object[]) {
    if (rawRow === null || typeof rawRow !== 'object' || Array.isArray(rawRow)) {
      return failure('键盘行必须是对象');
    }
    const rowRecord = rawRow as Record<string, Object>;
    const rawKeys = rowRecord['keys'];
    if (!Array.isArray(rawKeys) || rawKeys.length <= 0 || rawKeys.length > 12) {
      return failure('每行必须包含 1～12 个按键');
    }
    const kind = parseRowKind(rowRecord['kind']);
    if (rowRecord['kind'] !== undefined && kind === undefined) {
      return failure('存在不支持的行类型');
    }
    const keys: KeyboardStructureKeyDefinition[] = [];
    for (const rawKey of rawKeys as Object[]) {
      if (rawKey === null || typeof rawKey !== 'object' || Array.isArray(rawKey)) {
        return failure('按键配置必须是对象');
      }
      const keyRecord = rawKey as Record<string, Object>;
      const id = keyRecord['id'];
      if (typeof id !== 'string' || id.length <= 0 || id.length > 64 || seenIds.indexOf(id) >= 0) {
        return failure('按键 ID 为空、重复或过长');
      }
      if (ALLOWED_STRUCTURE_KEYS.indexOf(id) < 0) {
        return failure(`按键 ${id} 不受支持`);
      }
      const weightValue = keyRecord['weight'];
      if (weightValue !== undefined &&
        (typeof weightValue !== 'number' || !Number.isFinite(weightValue) || weightValue < 0.4 || weightValue > 8)) {
        return failure(`按键 ${id} 的 weight 必须在 0.4～8 之间`);
      }
      const labelValue = keyRecord['label'];
      if (labelValue !== undefined &&
        (typeof labelValue !== 'string' || labelValue.length <= 0 || labelValue.length > 8)) {
        return failure(`按键 ${id} 的 label 长度必须为 1～8 个字符`);
      }
      seenIds.push(id);
      const key: KeyboardStructureKeyDefinition = { id };
      if (typeof weightValue === 'number') {
        key.weight = weightValue;
      }
      if (typeof labelValue === 'string') {
        key.label = labelValue;
      }
      keys.push(key);
    }
    const row: KeyboardStructureRowDefinition = { keys };
    if (kind !== undefined) {
      row.kind = kind;
    }
    rows.push(row);
  }

  const missing = REQUIRED_STRUCTURE_KEYS.filter((id: string): boolean => seenIds.indexOf(id) < 0);
  if (missing.length > 0) {
    return failure(`键盘结构缺少必要按键：${missing.join(', ')}`);
  }
  const definition: KeyboardStructureDefinition = {
    schemaVersion: KEYBOARD_CUSTOMIZATION_SCHEMA_VERSION,
    id: record['id'] as string,
    name: (record['name'] as string).trim(),
    rows
  };
  return success(definition);
}

function optionalColor(record: Record<string, Object>, key: string): KeyboardCustomizationParseResult<string | undefined> {
  const value = record[key];
  if (value === undefined) {
    return success<string | undefined>(undefined);
  }
  if (typeof value !== 'string' || !COLOR_PATTERN.test(value)) {
    return failure(`${key} 必须是 #RRGGBB 或 #RRGGBBAA 颜色`);
  }
  return success<string | undefined>(value);
}

function optionalAsset(record: Record<string, Object>, key: string): KeyboardCustomizationParseResult<string | undefined> {
  const value = record[key];
  if (value === undefined) {
    return success<string | undefined>(undefined);
  }
  if (typeof value !== 'string' || !ASSET_PATTERN.test(value)) {
    return failure(`${key} 必须引用 assets 目录内的 PNG、JPG 或 WebP 图片`);
  }
  return success<string | undefined>(value);
}

function assignColor(
  target: KeyboardSkinColors,
  source: Record<string, Object>,
  key: string
): KeyboardCustomizationParseResult<boolean> {
  const result = optionalColor(source, key);
  if (!result.success) {
    return failure(result.message);
  }
  const value = result.value;
  if (value !== undefined) {
    (target as Record<string, Object>)[key] = value;
    return success(true);
  }
  return success(false);
}

function assignAsset(
  target: KeyboardSkinImages,
  source: Record<string, Object>,
  key: string
): KeyboardCustomizationParseResult<boolean> {
  const result = optionalAsset(source, key);
  if (!result.success) {
    return failure(result.message);
  }
  const value = result.value;
  if (value !== undefined) {
    (target as Record<string, Object>)[key] = value;
    return success(true);
  }
  return success(false);
}

export function parseKeyboardSkinJson(content: string): KeyboardCustomizationParseResult<KeyboardSkinDefinition> {
  let record: Record<string, Object>;
  try {
    record = JSON.parse(content) as Record<string, Object>;
  } catch (_err) {
    return failure('skin.json 不是有效的 JSON');
  }
  if (record === null || typeof record !== 'object' || Array.isArray(record)) {
    return failure('skin.json 根节点必须是对象');
  }
  const identityError = validPackageIdentity(record);
  if (identityError.length > 0) {
    return failure(identityError);
  }
  const rawColors = record['colors'];
  const rawImages = record['images'];
  if (rawColors !== undefined &&
    (rawColors === null || typeof rawColors !== 'object' || Array.isArray(rawColors))) {
    return failure('colors 必须是对象');
  }
  if (rawImages !== undefined &&
    (rawImages === null || typeof rawImages !== 'object' || Array.isArray(rawImages))) {
    return failure('images 必须是对象');
  }
  const colorRecord = (rawColors ?? {}) as Record<string, Object>;
  const imageRecord = (rawImages ?? {}) as Record<string, Object>;
  const colors: KeyboardSkinColors = {};
  const images: KeyboardSkinImages = {};
  const colorKeys: string[] = [
    'panelBackground', 'candidateBackground', 'letterKeyBackground', 'functionKeyBackground',
    'spaceKeyBackground', 'primaryFunctionBackground', 'modeKeyBackgroundEnglish',
    'modeKeyBackgroundChinese', 'letterKeyPressedBackground', 'functionKeyPressedBackground',
    'primaryFunctionPressedBackground', 'letterKeyText', 'functionKeyText', 'primaryFunctionText',
    'modeKeyTextEnglish', 'modeKeyTextChinese', 'errorText', 'previewBackground', 'previewText',
    'previewShadow', 'candidateText', 'candidateReading', 'candidateDivider', 'keyBorder'
  ];
  const imageKeys: string[] = ['panelBackground', 'letterKey', 'functionKey', 'spaceKey', 'enterKey'];
  let customizationCount = 0;
  for (const key of colorKeys) {
    const result = assignColor(colors, colorRecord, key);
    if (!result.success) {
      return failure(result.message);
    }
    if (result.value === true) {
      customizationCount += 1;
    }
  }
  for (const key of imageKeys) {
    const result = assignAsset(images, imageRecord, key);
    if (!result.success) {
      return failure(result.message);
    }
    if (result.value === true) {
      customizationCount += 1;
    }
  }
  if (customizationCount <= 0) {
    return failure('皮肤至少需要配置一种颜色或图片');
  }
  const definition: KeyboardSkinDefinition = {
    schemaVersion: KEYBOARD_CUSTOMIZATION_SCHEMA_VERSION,
    id: record['id'] as string,
    name: (record['name'] as string).trim(),
    colors,
    images
  };
  return success(definition);
}

export enum KeyboardCustomizationShortcut {
  NONE = 'none',
  CYCLE_SKIN = 'cycle-skin',
  CYCLE_STRUCTURE = 'cycle-structure'
}

/** Pure chord resolver used by the touch keyboard and unit tests. */
export function resolveKeyboardCustomizationShortcut(pressedKeyIds: string[]): KeyboardCustomizationShortcut {
  const hasSpace = pressedKeyIds.indexOf('space') >= 0;
  if (hasSpace && pressedKeyIds.indexOf('number') >= 0) {
    return KeyboardCustomizationShortcut.CYCLE_SKIN;
  }
  if (hasSpace && (pressedKeyIds.indexOf('punctuation-period') >= 0 ||
    pressedKeyIds.indexOf('symbol') >= 0)) {
    return KeyboardCustomizationShortcut.CYCLE_STRUCTURE;
  }
  return KeyboardCustomizationShortcut.NONE;
}
