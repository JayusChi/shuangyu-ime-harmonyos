import { isConvenienceInput } from './ConvenienceInput';
import { KeyboardMode } from './KeyboardAction';
import { chinesePunctuationForEnglishTarget } from './SmartPunctuation';

export enum PhysicalKeyCommandType {
  NONE = 'none',
  CONVENIENCE = 'convenience',
  LETTER = 'letter',
  UNIVERSAL = 'universal',
  DELETE = 'delete',
  SPACE = 'space',
  ENTER = 'enter',
  TAB = 'tab',
  SEGMENT_BOUNDARY = 'segment_boundary',
  CANDIDATE = 'candidate',
  SECOND_CANDIDATE = 'second_candidate',
  THIRD_CANDIDATE = 'third_candidate',
  CANCEL = 'cancel',
  JUMP_OUT_PAIR = 'jump_out_pair',
  SELECT_PREVIOUS = 'select_previous',
  SELECT_NEXT = 'select_next',
  PREVIOUS_PAGE = 'previous_page',
  NEXT_PAGE = 'next_page',
  PUNCTUATION = 'punctuation',
  SYMBOL_GUIDE = 'symbol_guide'
}

export interface PhysicalKeySnapshot {
  isDown: boolean;
  unicodeChar: number;
  keyCode: number;
  ctrlKey: boolean;
  altKey: boolean;
  logoKey: boolean;
  shiftKey?: boolean;
}

export interface PhysicalKeySessionSnapshot {
  sessionActive: boolean;
  editorConnected: boolean;
  /** Editor policy, independent from whether the candidate UI is currently painted. */
  chineseInputAllowed?: boolean;
  candidateBarVisible: boolean;
  keyboardMode: KeyboardMode;
  universalKeyEnabled?: boolean;
  rawInput: string;
  candidateCount: number;
  /** True while an earlier consumed hardware key is still queued. */
  compositionPending?: boolean;
  conveniencePendingRaw?: string;
  /** True while a verified pair insertion can still jump over its right delimiter. */
  pairJumpAvailable?: boolean;
  /** English key whose previous Chinese punctuation can still be replaced. */
  smartPunctuationContinuation?: string;
}

export interface PhysicalKeyCommand {
  type: PhysicalKeyCommandType;
  letter?: string;
  character?: string;
  candidateIndex?: number;
}

const KEYCODE_SPACE = 2050;
const KEYCODE_TAB = 2049;
const KEYCODE_ENTER = 2054;
const KEYCODE_DELETE = 2055;
const KEYCODE_NUMPAD_ENTER = 2119;
const KEYCODE_NUMPAD_0 = 2103;
const KEYCODE_NUMPAD_9 = 2112;
const KEYCODE_DPAD_UP = 2012;
const KEYCODE_DPAD_DOWN = 2013;
const KEYCODE_DPAD_LEFT = 2014;
const KEYCODE_DPAD_RIGHT = 2015;
const KEYCODE_PAGE_UP = 2068;
const KEYCODE_PAGE_DOWN = 2069;
const KEYCODE_ESCAPE = 2070;
const KEYCODE_LEFT_BRACKET = 2059;
const KEYCODE_RIGHT_BRACKET = 2060;
const KEYCODE_A = 2017;
const KEYCODE_Z = 2042;
const KEYCODE_0 = 2000;
const KEYCODE_9 = 2009;
export const KEYCODE_SHIFT_LEFT = 2047;
export const KEYCODE_SHIFT_RIGHT = 2048;

const NO_COMMAND: PhysicalKeyCommand = { type: PhysicalKeyCommandType.NONE };

/** Resolves an unmodified hardware letter without depending on session state. */
export function resolveUnmodifiedPhysicalLetter(key: PhysicalKeySnapshot): string | undefined {
  if (key.ctrlKey || key.altKey || key.logoKey) {
    return undefined;
  }
  if (key.unicodeChar > 0) {
    const character = String.fromCharCode(key.unicodeChar);
    return /^[a-zA-Z]$/.test(character) ? character : undefined;
  }
  if (key.keyCode < KEYCODE_A || key.keyCode > KEYCODE_Z) {
    return undefined;
  }
  const lowerCase = String.fromCharCode(97 + key.keyCode - KEYCODE_A);
  return key.shiftKey === true ? lowerCase.toUpperCase() : lowerCase;
}

function punctuationFromKeyCode(keyCode: number): string {
  switch (keyCode) {
    case 2010: return '*';
    case 2066: return '+';
    case 2113: return '/';
    case 2114: return '*';
    case 2115: return '-';
    case 2116: return '+';
    case 2117: return '.';
    case 2120: return '=';
    case 2043:
      return ',';
    case 2044:
      return '.';
    case 2056:
      return '`';
    case 2057:
      return '-';
    case 2058:
      return '=';
    case KEYCODE_LEFT_BRACKET:
      return '[';
    case KEYCODE_RIGHT_BRACKET:
      return ']';
    case 2061:
      return '\\';
    case 2062:
      return ';';
    case 2063:
      return "'";
    case 2064:
      return '/';
    case 2065:
      return '@';
    default:
      return '';
  }
}

function isPrintablePunctuation(character: string): boolean {
  if (character.length !== 1 || character.charCodeAt(0) < 32) {
    return false;
  }
  return !/^[a-zA-Z0-9\s]$/.test(character);
}

function normalizeChinesePunctuation(character: string): string {
  return chinesePunctuationForEnglishTarget(character);
}

/** Pure routing contract for hardware keys while a Chinese IME session owns composition. */
export function resolvePhysicalKeyCommand(
  key: PhysicalKeySnapshot,
  session: PhysicalKeySessionSnapshot
): PhysicalKeyCommand {
  if (!key.isDown || key.ctrlKey || key.altKey || key.logoKey ||
    !session.sessionActive || !session.editorConnected ||
    (session.keyboardMode !== KeyboardMode.CHINESE && !isConvenienceInput(session.rawInput) &&
      !isConvenienceInput(session.conveniencePendingRaw ?? '')) || session.chineseInputAllowed === false) {
    return NO_COMMAND;
  }

  let character = key.unicodeChar > 0 ? String.fromCharCode(key.unicodeChar) : '';
  // Some hardware drivers and UI injection tools report unicodeChar=0 while
  // still providing a standard KeyCode. Preserve the same routing contract.
  if (character.length === 0 && key.keyCode >= KEYCODE_A && key.keyCode <= KEYCODE_Z) {
    character = String.fromCharCode(97 + key.keyCode - KEYCODE_A);
    if (key.shiftKey === true) { character = character.toUpperCase(); }
  } else if (character.length === 0 && key.keyCode >= KEYCODE_0 && key.keyCode <= KEYCODE_9) {
    character = String.fromCharCode(48 + key.keyCode - KEYCODE_0);
  } else if (character.length === 0 && key.keyCode >= KEYCODE_NUMPAD_0 && key.keyCode <= KEYCODE_NUMPAD_9) {
    character = String.fromCharCode(48 + key.keyCode - KEYCODE_NUMPAD_0);
  } else if (character.length === 0) {
    character = punctuationFromKeyCode(key.keyCode);
    if (key.keyCode === 2056 && key.shiftKey === true) { character = '~'; }
  }

  const convenienceRaw = session.conveniencePendingRaw ?? session.rawInput;
  const convenienceActive = isConvenienceInput(convenienceRaw);
  if (character === '`' && key.shiftKey !== true && session.universalKeyEnabled === true &&
    !convenienceActive && session.keyboardMode === KeyboardMode.CHINESE) {
    return { type: PhysicalKeyCommandType.UNIVERSAL };
  }
  if (convenienceActive) {
    if (key.unicodeChar === 0 && key.shiftKey === true) {
      if (key.keyCode === 2058) { character = '+'; }
      if (key.keyCode === 2008) { character = '*'; }
      if (key.keyCode === 2057) { character = '_'; }
    }
    // Digits edit the expression/date instead of selecting candidate slots.
    if (character.length === 1 && /^[a-zA-Z0-9='.+*/_@-]$/.test(character)) {
      return { type: PhysicalKeyCommandType.CONVENIENCE, character };
    }
    if (character === ';') {
      return { type: PhysicalKeyCommandType.SECOND_CANDIDATE, candidateIndex: 1 };
    }
  } else if (character === "'" && key.shiftKey !== true &&
    convenienceRaw.length === 0 && (session.compositionPending !== true || session.conveniencePendingRaw !== undefined)) {
    return { type: PhysicalKeyCommandType.CONVENIENCE, character };
  }

  // Input ownership must follow the editor policy, never the transient
  // visibility of a candidate window. Floating candidate UI can be recreated
  // or hidden for a frame on desktop without changing which IME owns the key.
  if (key.keyCode === KEYCODE_DELETE || character === String.fromCharCode(8)) {
    return { type: PhysicalKeyCommandType.DELETE };
  }

  // Letters always belong to an active Chinese hardware-input session.
  if (/^[a-zA-Z]$/.test(character)) {
    return { type: PhysicalKeyCommandType.LETTER, letter: character.toLowerCase() };
  }

  const hasComposition = convenienceRaw.length > 0 ||
    (session.compositionPending === true && session.conveniencePendingRaw === undefined);
  // The first punctuation may have committed the candidate and emptied the
  // composition before the second DOWN event. Continue only the same selected
  // intelligsymbol key so the replacement remains atomic in the IME.
  if (!hasComposition && session.smartPunctuationContinuation !== undefined &&
    character === session.smartPunctuationContinuation) {
    return {
      type: PhysicalKeyCommandType.PUNCTUATION,
      character: normalizeChinesePunctuation(character)
    };
  }

  // Semicolon is the physical second-candidate key. When no second candidate
  // exists it arms the one-shot symbol guide instead of inserting punctuation.
  // With exactly one candidate it commits the first and arms the guide.
  if (character === ';') {
    if (session.rawInput.startsWith(';')) {
      return { type: PhysicalKeyCommandType.SYMBOL_GUIDE };
    }
    if (session.candidateCount >= 2) {
      return { type: PhysicalKeyCommandType.SECOND_CANDIDATE, candidateIndex: 1 };
    }
    if (session.candidateCount === 1) {
      return { type: PhysicalKeyCommandType.CANDIDATE, candidateIndex: 0 };
    }
    return { type: PhysicalKeyCommandType.SYMBOL_GUIDE };
  }

  const isTab = key.keyCode === KEYCODE_TAB || character === String.fromCharCode(9);
  if (isTab) {
    if (hasComposition) {
      return { type: PhysicalKeyCommandType.TAB };
    }
    return session.pairJumpAvailable === true
      ? { type: PhysicalKeyCommandType.JUMP_OUT_PAIR }
      : NO_COMMAND;
  }
  const isEnter = key.keyCode === KEYCODE_ENTER || key.keyCode === KEYCODE_NUMPAD_ENTER ||
    character === String.fromCharCode(10) || character === String.fromCharCode(13);
  if (!hasComposition && isEnter && session.pairJumpAvailable === true) {
    return { type: PhysicalKeyCommandType.JUMP_OUT_PAIR };
  }
  if (!hasComposition) {
    return NO_COMMAND;
  }

  // Match desktop Chinese IMEs: while composing, the unmodified bracket
  // keys page the candidate window instead of leaking punctuation into the
  // editor. unicodeChar=0 drivers are covered by punctuationFromKeyCode().
  if (character === '[') {
    return { type: PhysicalKeyCommandType.PREVIOUS_PAGE };
  }
  if (character === ']') {
    return { type: PhysicalKeyCommandType.NEXT_PAGE };
  }

  // Apostrophe is the physical third-candidate key. With fewer than three
  // candidates it retains its pinyin syllable-boundary behavior.
  if (character === "'") {
    if (session.candidateCount >= 3) {
      return { type: PhysicalKeyCommandType.THIRD_CANDIDATE, candidateIndex: 2 };
    }
    return { type: PhysicalKeyCommandType.SEGMENT_BOUNDARY };
  }

  // Physical punctuation is appended after the editor preview without ending
  // the active composition. A dedicated suffix tracker makes Backspace remove
  // these characters before it edits the raw input and candidate state.
  if (isPrintablePunctuation(character)) {
    return {
      type: PhysicalKeyCommandType.PUNCTUATION,
      character: normalizeChinesePunctuation(character)
    };
  }

  if (character >= '1' && character <= '9') {
    const index = Number(character) - 1;
    // Consume the whole documented selector range while composing. If the
    // requested slot is absent the serialized commit reports that fact without
    // leaking a literal digit into the host editor.
    return { type: PhysicalKeyCommandType.CANDIDATE, candidateIndex: index };
  }
  if (key.keyCode === KEYCODE_DELETE || character === String.fromCharCode(8)) {
    return { type: PhysicalKeyCommandType.DELETE };
  }
  if (key.keyCode === KEYCODE_SPACE || character === ' ') {
    return { type: PhysicalKeyCommandType.SPACE };
  }
  if (isEnter) {
    return { type: PhysicalKeyCommandType.ENTER };
  }
  if (key.keyCode === KEYCODE_ESCAPE || character === String.fromCharCode(27)) {
    return { type: PhysicalKeyCommandType.CANCEL };
  }
  if (key.keyCode === KEYCODE_DPAD_LEFT || key.keyCode === KEYCODE_DPAD_UP) {
    return { type: PhysicalKeyCommandType.SELECT_PREVIOUS };
  }
  if (key.keyCode === KEYCODE_DPAD_RIGHT || key.keyCode === KEYCODE_DPAD_DOWN) {
    return { type: PhysicalKeyCommandType.SELECT_NEXT };
  }
  if (key.keyCode === KEYCODE_PAGE_UP) {
    return { type: PhysicalKeyCommandType.PREVIOUS_PAGE };
  }
  if (key.keyCode === KEYCODE_PAGE_DOWN) {
    return { type: PhysicalKeyCommandType.NEXT_PAGE };
  }
  return NO_COMMAND;
}

/** Keeps a consumed DOWN/UP pair from being split between the IME and host. */
export class PhysicalKeyConsumptionTracker {
  private consumedKeyCodes: number[] = [];

  recordConsumedDown(keyCode: number): void {
    if (this.consumedKeyCodes.indexOf(keyCode) < 0) {
      this.consumedKeyCodes.push(keyCode);
    }
  }

  consumeRelease(keyCode: number): boolean {
    const index = this.consumedKeyCodes.indexOf(keyCode);
    if (index < 0) {
      return false;
    }
    this.consumedKeyCodes.splice(index, 1);
    return true;
  }

  reset(): void {
    this.consumedKeyCodes = [];
  }
}

/** True for the two platform physical Shift keys. */
export function isPhysicalShiftKey(keyCode: number): boolean {
  return keyCode === KEYCODE_SHIFT_LEFT || keyCode === KEYCODE_SHIFT_RIGHT;
}

/**
 * Recognizes a standalone Shift press without stealing Shift combinations.
 * DOWN is always returned to the host; a matching UP toggles the IME only when
 * no other key participated while Shift was held.
 */
export class PhysicalShiftLanguageToggleTracker {
  private pressedShiftKeyCodes: number[] = [];
  private standaloneCandidate: boolean = false;

  observe(key: PhysicalKeySnapshot): boolean {
    if (!isPhysicalShiftKey(key.keyCode)) {
      if (key.isDown && this.pressedShiftKeyCodes.length > 0) {
        this.standaloneCandidate = false;
      }
      return false;
    }

    const pressedIndex = this.pressedShiftKeyCodes.indexOf(key.keyCode);
    if (key.isDown) {
      if (pressedIndex >= 0) {
        return false;
      }
      if (this.pressedShiftKeyCodes.length === 0) {
        this.standaloneCandidate = !key.ctrlKey && !key.altKey && !key.logoKey;
      } else {
        // Two Shift keys form a modifier chord, not a standalone tap.
        this.standaloneCandidate = false;
      }
      this.pressedShiftKeyCodes.push(key.keyCode);
      return false;
    }

    if (pressedIndex < 0) {
      return false;
    }
    this.pressedShiftKeyCodes.splice(pressedIndex, 1);
    if (this.pressedShiftKeyCodes.length > 0) {
      return false;
    }
    const shouldToggle = this.standaloneCandidate && !key.ctrlKey && !key.altKey && !key.logoKey;
    this.standaloneCandidate = false;
    return shouldToggle;
  }

  reset(): void {
    this.pressedShiftKeyCodes = [];
    this.standaloneCandidate = false;
  }
}

/**
 * Claims plain letter DOWN/UP pairs while the IME runtime is still starting.
 * Other keys keep their normal host routing until the active editor policy is
 * available, so cold start never swallows shortcuts, digits or controls.
 */
export class PhysicalKeyStartupDeferral {
  private readonly consumption = new PhysicalKeyConsumptionTracker();

  shouldDefer(key: PhysicalKeySnapshot): boolean {
    if (!key.isDown) {
      return this.consumption.consumeRelease(key.keyCode);
    }
    if (resolveUnmodifiedPhysicalLetter(key) === undefined) {
      return false;
    }
    this.consumption.recordConsumedDown(key.keyCode);
    return true;
  }

  reset(): void {
    this.consumption.reset();
  }
}

/** Tracks punctuation appended after an active editor preview. */
export class PhysicalEditorSuffixTracker {
  private punctuationCount: number = 0;

  recordPunctuation(): void {
    this.punctuationCount += 1;
  }

  consumePunctuationDelete(): boolean {
    if (this.punctuationCount <= 0) {
      return false;
    }
    this.punctuationCount -= 1;
    return true;
  }

  reset(): void {
    this.punctuationCount = 0;
  }
}
