/** Stable product-level keyboard profiles. A profile is the only legal way to
 * combine input semantics, the touch layout, and the Rust engine scheme. */
export enum KeyboardInputScheme {
  XIAOHE_SHUANGPIN = 'xiaohe-shuangpin',
  XIAOHE_YINXING = 'xiaohe-yinxing',
  QUANPIN = 'quanpin',
  T9_PINYIN = 't9-pinyin'
}

export enum KeyboardLayoutKind {
  EIGHTEEN_KEY = 'eighteen-key',
  QWERTY_26_KEY = 'qwerty-26-key',
  T9_9_KEY = 't9-9-key'
}

export enum KeyboardCapability {
  LETTER_INPUT = 'letter-input',
  SEGMENT_BOUNDARY = 'segment-boundary',
  PINYIN_ALTERNATIVES = 'pinyin-alternatives',
  CODE_TABLE = 'code-table'
}

export interface KeyboardProfile {
  profileId: string;
  displayName: string;
  inputScheme: KeyboardInputScheme;
  layoutKind: KeyboardLayoutKind;
  engineSchemeId: string;
  supportedCapabilities: KeyboardCapability[];
  enabled: boolean;
}

export const XIAOHE_18_PROFILE_ID: string = 'xiaohe-18';
export const XIAOHE_26_PROFILE_ID: string = 'xiaohe-26';
export const QUANPIN_26_PROFILE_ID: string = 'quanpin-26';
export const PINYIN_9_PROFILE_ID: string = 'pinyin-9';
export const XIAOHE_YINXING_26_PROFILE_ID: string = 'xiaohe-yinxing-26';
export const DEFAULT_KEYBOARD_PROFILE_ID: string = XIAOHE_26_PROFILE_ID;

const LEGACY_XIAOHE_17_PROFILE_ID: string = 'xiaohe-17';
const LEGACY_XIAOHE_YINXING_17_PROFILE_ID: string = 'xiaohe-yinxing-17';

const SHUANGPIN_CAPABILITIES: KeyboardCapability[] = [
  KeyboardCapability.LETTER_INPUT,
  KeyboardCapability.SEGMENT_BOUNDARY
];
const YINXING_CAPABILITIES: KeyboardCapability[] = [
  KeyboardCapability.LETTER_INPUT,
  KeyboardCapability.CODE_TABLE
];

/** Product keyboard profiles. Each enabled entry has a complete engine and UI. */
export const KEYBOARD_PROFILES: KeyboardProfile[] = [
  {
    profileId: XIAOHE_18_PROFILE_ID,
    displayName: '18 键双拼',
    inputScheme: KeyboardInputScheme.XIAOHE_SHUANGPIN,
    layoutKind: KeyboardLayoutKind.EIGHTEEN_KEY,
    engineSchemeId: 'xiaohe',
    supportedCapabilities: SHUANGPIN_CAPABILITIES.slice(),
    enabled: true
  },
  {
    profileId: XIAOHE_26_PROFILE_ID,
    displayName: '26 键双拼',
    inputScheme: KeyboardInputScheme.XIAOHE_SHUANGPIN,
    layoutKind: KeyboardLayoutKind.QWERTY_26_KEY,
    engineSchemeId: 'xiaohe',
    supportedCapabilities: SHUANGPIN_CAPABILITIES.slice(),
    enabled: true
  },
  {
    profileId: QUANPIN_26_PROFILE_ID,
    displayName: '26 键全拼',
    inputScheme: KeyboardInputScheme.QUANPIN,
    layoutKind: KeyboardLayoutKind.QWERTY_26_KEY,
    engineSchemeId: 'quanpin',
    supportedCapabilities: [KeyboardCapability.LETTER_INPUT, KeyboardCapability.SEGMENT_BOUNDARY],
    enabled: true
  },
  {
    profileId: PINYIN_9_PROFILE_ID,
    displayName: '9 键拼音',
    inputScheme: KeyboardInputScheme.T9_PINYIN,
    layoutKind: KeyboardLayoutKind.T9_9_KEY,
    engineSchemeId: 'pinyin-9',
    supportedCapabilities: [KeyboardCapability.SEGMENT_BOUNDARY, KeyboardCapability.PINYIN_ALTERNATIVES],
    enabled: true
  },
  {
    profileId: XIAOHE_YINXING_26_PROFILE_ID,
    displayName: '26 键小鹤音形',
    inputScheme: KeyboardInputScheme.XIAOHE_YINXING,
    layoutKind: KeyboardLayoutKind.QWERTY_26_KEY,
    engineSchemeId: 'xiaohe-yinxing',
    supportedCapabilities: YINXING_CAPABILITIES.slice(),
    enabled: true
  }
];

export function findKeyboardProfile(profileId: string | undefined): KeyboardProfile | undefined {
  return KEYBOARD_PROFILES.find((profile: KeyboardProfile): boolean => profile.profileId === profileId);
}

export function isEnabledKeyboardProfile(profileId: string | undefined): boolean {
  return findKeyboardProfile(profileId)?.enabled === true;
}

export function enabledKeyboardProfiles(): KeyboardProfile[] {
  return KEYBOARD_PROFILES.filter((profile: KeyboardProfile): boolean => profile.enabled);
}

export function normalizeKeyboardProfileId(profileId: string | undefined): string {
  if (profileId === LEGACY_XIAOHE_17_PROFILE_ID) {
    return XIAOHE_18_PROFILE_ID;
  }
  if (profileId === LEGACY_XIAOHE_YINXING_17_PROFILE_ID) {
    return XIAOHE_YINXING_26_PROFILE_ID;
  }
  return isEnabledKeyboardProfile(profileId) ? profileId as string : DEFAULT_KEYBOARD_PROFILE_ID;
}

export function keyboardProfileForLegacy(
  schemeId: string | undefined,
  legacyLayout: string | undefined
): string {
  if (schemeId === 'xiaohe-yinxing') {
    return XIAOHE_YINXING_26_PROFILE_ID;
  }
  if (schemeId === 'quanpin') {
    return QUANPIN_26_PROFILE_ID;
  }
  if (schemeId === 'pinyin-9') {
    return PINYIN_9_PROFILE_ID;
  }
  if (schemeId === undefined || schemeId.length === 0 || schemeId === 'xiaohe') {
    const isCompactPinyin = legacyLayout === 'seventeen_key' || legacyLayout === 'seventeen-key' ||
      legacyLayout === 'eighteen_key' || legacyLayout === KeyboardLayoutKind.EIGHTEEN_KEY;
    return isCompactPinyin ? XIAOHE_18_PROFILE_ID : XIAOHE_26_PROFILE_ID;
  }
  return DEFAULT_KEYBOARD_PROFILE_ID;
}

export function keyboardProfileForEngineScheme(
  schemeId: string,
  layoutKind: KeyboardLayoutKind
): string | undefined {
  const match = KEYBOARD_PROFILES.find((profile: KeyboardProfile): boolean =>
    profile.enabled && profile.engineSchemeId === schemeId && profile.layoutKind === layoutKind);
  return match?.profileId;
}

export function keyboardProfileLayoutKind(profileId: string | undefined): KeyboardLayoutKind {
  return findKeyboardProfile(normalizeKeyboardProfileId(profileId))?.layoutKind ?? KeyboardLayoutKind.QWERTY_26_KEY;
}

export function keyboardProfileEngineSchemeId(profileId: string | undefined): string {
  return findKeyboardProfile(normalizeKeyboardProfileId(profileId))?.engineSchemeId ?? 'xiaohe';
}
