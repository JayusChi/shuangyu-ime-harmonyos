import { EditorContext } from '../domain/editor/EditorContext';
import { KeyboardMode } from '../domain/keyboard/KeyboardAction';

export class KeyboardModePolicy {
  initialMode(context: EditorContext, lastTextMode: KeyboardMode): KeyboardMode {
    if (context.preferredKeyboardMode === KeyboardMode.CHINESE &&
      this.isAllowed(context, lastTextMode) && this.isTextMode(lastTextMode)) {
      return lastTextMode;
    }
    return this.fallbackMode(context);
  }

  isAllowed(context: EditorContext, mode: KeyboardMode): boolean {
    switch (mode) {
      case KeyboardMode.CHINESE:
        return context.chineseModeAllowed;
      case KeyboardMode.ENGLISH:
        return context.englishModeAllowed;
      case KeyboardMode.NUMBER:
        return context.numberModeAllowed;
      case KeyboardMode.PHONE:
        return context.phoneModeAllowed;
      case KeyboardMode.SYMBOL:
        return context.symbolModeAllowed;
      default:
        return false;
    }
  }

  fallbackMode(context: EditorContext): KeyboardMode {
    if (this.isAllowed(context, context.preferredKeyboardMode)) {
      return context.preferredKeyboardMode;
    }
    if (context.englishModeAllowed) {
      return KeyboardMode.ENGLISH;
    }
    if (context.numberModeAllowed) {
      return KeyboardMode.NUMBER;
    }
    if (context.phoneModeAllowed) {
      return KeyboardMode.PHONE;
    }
    if (context.chineseModeAllowed) {
      return KeyboardMode.CHINESE;
    }
    return KeyboardMode.ENGLISH;
  }

  restoreTransientMode(context: EditorContext, previousMode: KeyboardMode): KeyboardMode {
    if (this.isTextMode(previousMode) && this.isAllowed(context, previousMode)) {
      return previousMode;
    }
    return this.fallbackMode(context);
  }

  shouldShowCandidateBar(context: EditorContext, mode: KeyboardMode): boolean {
    return context.candidateBarVisible && this.isTextMode(mode);
  }

  isTextMode(mode: KeyboardMode): boolean {
    return mode === KeyboardMode.CHINESE || mode === KeyboardMode.ENGLISH;
  }
}
