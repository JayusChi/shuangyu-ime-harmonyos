import { KeyboardMode } from '../keyboard/KeyboardAction';

export const EDITOR_KIND_EXTRA_CONFIG_KEY: string = 'com.corrosion.shuangyuime.editorKind';
export const EDITOR_KIND_NUMBER_DECIMAL: string = 'number_decimal';

export enum EditorKind {
  NORMAL_TEXT = 'normal_text',
  PASSWORD = 'password',
  NUMBER = 'number',
  PHONE = 'phone',
  EMAIL = 'email',
  URL = 'url',
  SEARCH = 'search',
  MULTILINE = 'multiline',
  UNKNOWN = 'unknown'
}

export enum ShiftState {
  LOWERCASE = 'lowercase',
  ONE_SHOT_UPPERCASE = 'one_shot_uppercase',
  CAPS_LOCK = 'caps_lock'
}

export enum EnterAction {
  ENTER = 'enter',
  SEARCH = 'search',
  DONE = 'done',
  NEXT = 'next',
  GO = 'go',
  SEND = 'send'
}

export interface EditorContext {
  kind: EditorKind;
  preferredKeyboardMode: KeyboardMode;
  enterAction: EnterAction;
  isPassword: boolean;
  isMultiline: boolean;
  learningAllowed: boolean;
  textPreviewSupported: boolean;
  candidateBarVisible: boolean;
  chineseModeAllowed: boolean;
  englishModeAllowed: boolean;
  numberModeAllowed: boolean;
  phoneModeAllowed: boolean;
  symbolModeAllowed: boolean;
  numberDecimalAllowed: boolean;
}

export function copyEditorContext(context: EditorContext): EditorContext {
  return {
    kind: context.kind,
    preferredKeyboardMode: context.preferredKeyboardMode,
    enterAction: context.enterAction,
    isPassword: context.isPassword,
    isMultiline: context.isMultiline,
    learningAllowed: context.learningAllowed,
    textPreviewSupported: context.textPreviewSupported,
    candidateBarVisible: context.candidateBarVisible,
    chineseModeAllowed: context.chineseModeAllowed,
    englishModeAllowed: context.englishModeAllowed,
    numberModeAllowed: context.numberModeAllowed,
    phoneModeAllowed: context.phoneModeAllowed,
    symbolModeAllowed: context.symbolModeAllowed,
    numberDecimalAllowed: context.numberDecimalAllowed
  };
}

export function createUnknownEditorContext(): EditorContext {
  return {
    kind: EditorKind.UNKNOWN,
    preferredKeyboardMode: KeyboardMode.CHINESE,
    enterAction: EnterAction.ENTER,
    isPassword: false,
    isMultiline: false,
    learningAllowed: true,
    textPreviewSupported: false,
    candidateBarVisible: true,
    chineseModeAllowed: true,
    englishModeAllowed: true,
    numberModeAllowed: true,
    phoneModeAllowed: false,
    symbolModeAllowed: true,
    numberDecimalAllowed: false
  };
}
