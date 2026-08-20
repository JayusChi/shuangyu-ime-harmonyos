import { inputMethodEngine } from '@kit.IMEKit';
import {
  EditorContext,
  EditorKind,
  EnterAction,
  EDITOR_KIND_EXTRA_CONFIG_KEY,
  EDITOR_KIND_NUMBER_DECIMAL,
  createUnknownEditorContext
} from '../../domain/editor/EditorContext';
import { KeyboardMode } from '../../domain/keyboard/KeyboardAction';

export interface EditorAttributeCatalog {
  patternNull: number;
  patternText: number;
  patternNumber: number;
  patternPhone: number;
  patternEmail: number;
  patternUri: number;
  patternPassword: number;
  patternScreenLockPassword: number;
  patternNumberPassword: number;
  patternNewPassword: number;
  patternNumberDecimal: number;
  enterUnspecified: number;
  enterGo: number;
  enterSearch: number;
  enterSend: number;
  enterNext: number;
  enterDone: number;
  enterNewline: number;
}

export const HARMONY_EDITOR_ATTRIBUTE_CATALOG: EditorAttributeCatalog = {
  patternNull: inputMethodEngine.PATTERN_NULL,
  patternText: inputMethodEngine.PATTERN_TEXT,
  patternNumber: inputMethodEngine.PATTERN_NUMBER,
  patternPhone: inputMethodEngine.PATTERN_PHONE,
  patternEmail: inputMethodEngine.PATTERN_EMAIL,
  patternUri: inputMethodEngine.PATTERN_URI,
  patternPassword: inputMethodEngine.PATTERN_PASSWORD,
  patternScreenLockPassword: inputMethodEngine.PATTERN_PASSWORD_SCREEN_LOCK,
  patternNumberPassword: inputMethodEngine.PATTERN_PASSWORD_NUMBER,
  patternNewPassword: inputMethodEngine.PATTERN_NEW_PASSWORD,
  patternNumberDecimal: inputMethodEngine.PATTERN_NUMBER_DECIMAL,
  enterUnspecified: inputMethodEngine.ENTER_KEY_TYPE_UNSPECIFIED,
  enterGo: inputMethodEngine.ENTER_KEY_TYPE_GO,
  enterSearch: inputMethodEngine.ENTER_KEY_TYPE_SEARCH,
  enterSend: inputMethodEngine.ENTER_KEY_TYPE_SEND,
  enterNext: inputMethodEngine.ENTER_KEY_TYPE_NEXT,
  enterDone: inputMethodEngine.ENTER_KEY_TYPE_DONE,
  enterNewline: inputMethodEngine.ENTER_KEY_TYPE_NEWLINE
};

export class EditorAttributeMapper {
  private readonly catalog: EditorAttributeCatalog;

  constructor(catalog: EditorAttributeCatalog = HARMONY_EDITOR_ATTRIBUTE_CATALOG) {
    this.catalog = catalog;
  }

  map(attribute?: inputMethodEngine.EditorAttribute): EditorContext {
    if (!attribute) {
      return createUnknownEditorContext();
    }

    let configuredEditorKind: string | undefined = undefined;
    const configuredValue = attribute.extraConfig?.customSettings[EDITOR_KIND_EXTRA_CONFIG_KEY];
    if (typeof configuredValue === 'string') {
      configuredEditorKind = configuredValue;
    }
    return this.mapValues(
      attribute.inputPattern,
      attribute.enterKeyType,
      configuredEditorKind,
      attribute.isTextPreviewSupported
    );
  }

  mapValues(
    inputPattern?: number,
    enterKeyType?: number,
    configuredEditorKind?: string,
    textPreviewSupported: boolean = true
  ): EditorContext {
    if (inputPattern === undefined) {
      return createUnknownEditorContext();
    }

    const pattern = inputPattern;
    const enterAction = this.mapEnterAction(enterKeyType);

    if (pattern === this.catalog.patternNumberPassword) {
      return this.createPasswordContext(true, enterAction, textPreviewSupported);
    }
    if (pattern === this.catalog.patternPassword ||
      pattern === this.catalog.patternScreenLockPassword ||
      pattern === this.catalog.patternNewPassword) {
      return this.createPasswordContext(false, enterAction, textPreviewSupported);
    }
    if (pattern === this.catalog.patternNumber || pattern === this.catalog.patternNumberDecimal) {
      const decimalAllowed = pattern === this.catalog.patternNumberDecimal ||
        configuredEditorKind === EDITOR_KIND_NUMBER_DECIMAL;
      return this.createRestrictedContext(
        EditorKind.NUMBER,
        KeyboardMode.NUMBER,
        enterAction,
        decimalAllowed,
        textPreviewSupported
      );
    }
    if (pattern === this.catalog.patternPhone) {
      return this.createRestrictedContext(
        EditorKind.PHONE,
        KeyboardMode.PHONE,
        enterAction,
        false,
        textPreviewSupported
      );
    }
    if (pattern === this.catalog.patternEmail) {
      return this.createEnglishContext(EditorKind.EMAIL, enterAction, textPreviewSupported);
    }
    if (pattern === this.catalog.patternUri) {
      return this.createEnglishContext(EditorKind.URL, enterAction, textPreviewSupported);
    }
    if (pattern === this.catalog.patternText || pattern === this.catalog.patternNull) {
      if (enterKeyType === this.catalog.enterSearch) {
        return this.createTextContext(EditorKind.SEARCH, EnterAction.SEARCH, false, textPreviewSupported);
      }
      if (enterKeyType === this.catalog.enterNewline) {
        return this.createTextContext(EditorKind.MULTILINE, EnterAction.ENTER, true, textPreviewSupported);
      }
      return this.createTextContext(EditorKind.NORMAL_TEXT, enterAction, false, textPreviewSupported);
    }

    const unknown = createUnknownEditorContext();
    unknown.enterAction = enterAction;
    return unknown;
  }

  mapEnterAction(enterKeyType?: number): EnterAction {
    if (enterKeyType === this.catalog.enterSearch) {
      return EnterAction.SEARCH;
    }
    if (enterKeyType === this.catalog.enterDone) {
      return EnterAction.DONE;
    }
    if (enterKeyType === this.catalog.enterNext) {
      return EnterAction.NEXT;
    }
    if (enterKeyType === this.catalog.enterGo) {
      return EnterAction.GO;
    }
    if (enterKeyType === this.catalog.enterSend) {
      return EnterAction.SEND;
    }
    return EnterAction.ENTER;
  }

  private createTextContext(
    kind: EditorKind,
    enterAction: EnterAction,
    isMultiline: boolean,
    textPreviewSupported: boolean
  ): EditorContext {
    return {
      kind,
      preferredKeyboardMode: KeyboardMode.CHINESE,
      enterAction,
      isPassword: false,
      isMultiline,
      learningAllowed: true,
      textPreviewSupported,
      candidateBarVisible: true,
      chineseModeAllowed: true,
      englishModeAllowed: true,
      numberModeAllowed: true,
      phoneModeAllowed: false,
      symbolModeAllowed: true,
      numberDecimalAllowed: false
    };
  }

  private createPasswordContext(
    numberPassword: boolean,
    enterAction: EnterAction,
    textPreviewSupported: boolean
  ): EditorContext {
    return {
      kind: EditorKind.PASSWORD,
      preferredKeyboardMode: numberPassword ? KeyboardMode.NUMBER : KeyboardMode.ENGLISH,
      enterAction,
      isPassword: true,
      isMultiline: false,
      learningAllowed: false,
      textPreviewSupported,
      candidateBarVisible: false,
      chineseModeAllowed: false,
      englishModeAllowed: !numberPassword,
      numberModeAllowed: true,
      phoneModeAllowed: false,
      symbolModeAllowed: !numberPassword,
      numberDecimalAllowed: false
    };
  }

  private createRestrictedContext(
    kind: EditorKind,
    preferredMode: KeyboardMode,
    enterAction: EnterAction,
    decimalAllowed: boolean,
    textPreviewSupported: boolean
  ): EditorContext {
    return {
      kind,
      preferredKeyboardMode: preferredMode,
      enterAction,
      isPassword: false,
      isMultiline: false,
      learningAllowed: true,
      textPreviewSupported,
      candidateBarVisible: false,
      chineseModeAllowed: false,
      englishModeAllowed: false,
      numberModeAllowed: preferredMode === KeyboardMode.NUMBER,
      phoneModeAllowed: preferredMode === KeyboardMode.PHONE,
      symbolModeAllowed: false,
      numberDecimalAllowed: decimalAllowed
    };
  }

  private createEnglishContext(
    kind: EditorKind,
    enterAction: EnterAction,
    textPreviewSupported: boolean
  ): EditorContext {
    return {
      kind,
      preferredKeyboardMode: KeyboardMode.ENGLISH,
      enterAction,
      isPassword: false,
      isMultiline: false,
      learningAllowed: true,
      textPreviewSupported,
      candidateBarVisible: true,
      chineseModeAllowed: false,
      englishModeAllowed: true,
      numberModeAllowed: true,
      phoneModeAllowed: false,
      symbolModeAllowed: true,
      numberDecimalAllowed: false
    };
  }
}
