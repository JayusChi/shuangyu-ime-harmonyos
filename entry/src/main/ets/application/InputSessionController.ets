import { ImeErrorCode } from '../common/error/ImeError';
import { Logger } from '../common/logging/Logger';
import { EditorExtendAction, KeyboardMode } from '../domain/keyboard/KeyboardAction';
import {
  InputMethodSwitchCapabilities,
  InputMethodSwitchResult,
  InputMethodSwitchResultType
} from '../infrastructure/ime/InputMethodSwitcher';
import { InputOperationResult, inputOperationFailed, inputOperationOk } from './InputOperationResult';
import { InputSessionCompositionController } from './InputSessionCompositionController';

export { ImeInputService } from './ImeInputService';

const TAG = 'InputSessionController';
const LOGGER = new Logger(TAG);

export class InputSessionController extends InputSessionCompositionController {
  /**
   * Compatibility entry point retained for the Stage 2 controller contract.
   * The production keyboard uses the serialized async toggleLanguageMode path.
   */
  toggleKeyboardMode(): InputOperationResult {
    const mode = this.store.toggleKeyboardMode();
    if (mode === KeyboardMode.CHINESE && !this.engineCoordinator.isInitialized()) {
      this.store.updateComposition(this.engineCoordinator.initialize());
    }
    if (mode === KeyboardMode.ENGLISH && this.engineCoordinator.isInitialized()) {
      this.imeService.clearPreviewText(this.getInputSessionGeneration()).catch((): void => {
        LOGGER.warn('compatibility mode switch preview cleanup failed');
      });
      this.store.updateComposition(this.engineCoordinator.reset());
      this.store.clearComposition();
    }
    LOGGER.info(`keyboard mode changed: ${mode}`);
    return inputOperationOk();
  }

  async toggleLanguageMode(
    generation: number = this.getInputSessionGeneration()
  ): Promise<InputOperationResult> {
    const state = this.store.getSnapshot();
    const currentLanguageMode = state.keyboardMode === KeyboardMode.CHINESE ||
      state.keyboardMode === KeyboardMode.ENGLISH
      ? state.keyboardMode
      : state.modeBeforeTransient;
    const target = currentLanguageMode === KeyboardMode.ENGLISH
      ? KeyboardMode.CHINESE
      : KeyboardMode.ENGLISH;
    return this.switchKeyboardMode(target, generation);
  }

  async toggleNumberMode(
    generation: number = this.getInputSessionGeneration()
  ): Promise<InputOperationResult> {
    return this.switchKeyboardMode(KeyboardMode.NUMBER, generation);
  }

  async toggleSymbolMode(
    generation: number = this.getInputSessionGeneration()
  ): Promise<InputOperationResult> {
    return this.switchKeyboardMode(KeyboardMode.SYMBOL, generation);
  }

  pressShift(timestamp: number = Date.now()): InputOperationResult {
    this.store.pressShift(timestamp);
    return inputOperationOk();
  }

  toggleChineseCapsLock(): InputOperationResult {
    const state = this.store.getSnapshot();
    if (!state.sessionActive || state.keyboardMode !== KeyboardMode.CHINESE || state.rawInput.length > 0) {
      this.store.recordError(ImeErrorCode.UNSUPPORTED_OPERATION, 'chinese caps lock requires empty chinese input');
      return inputOperationFailed(
        ImeErrorCode.UNSUPPORTED_OPERATION,
        'chinese caps lock requires empty chinese input'
      );
    }
    return this.store.toggleChineseCapsLock()
      ? inputOperationOk()
      : inputOperationFailed(ImeErrorCode.UNSUPPORTED_OPERATION, 'chinese caps lock is unavailable');
  }

  getInputMethodSwitchCapabilities(): InputMethodSwitchCapabilities {
    return this.inputMethodSwitcher.getCapabilities();
  }

  async switchToNextInputMethod(
    generation: number = this.getInputSessionGeneration()
  ): Promise<InputOperationResult> {
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('switch input method');
    }
    const state = this.store.getSnapshot();
    if (!state.sessionActive || !state.keyboardVisible) {
      return inputOperationFailed(ImeErrorCode.ENGINE_NOT_INITIALIZED, 'input method session is not visible');
    }
    return this.mapInputMethodSwitchResult(await this.inputMethodSwitcher.requestSwitchToNext());
  }

  async showInputMethodPicker(
    generation: number = this.getInputSessionGeneration()
  ): Promise<InputOperationResult> {
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('show input method picker');
    }
    const state = this.store.getSnapshot();
    if (!state.sessionActive || !state.keyboardVisible) {
      return inputOperationFailed(ImeErrorCode.ENGINE_NOT_INITIALIZED, 'input method session is not visible');
    }
    return this.mapInputMethodSwitchResult(await this.inputMethodSwitcher.requestShowSystemPicker());
  }

  async performEditorExtendAction(
    action: EditorExtendAction,
    generation: number = this.getInputSessionGeneration()
  ): Promise<InputOperationResult> {
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('editor extend action');
    }
    const sessionCheck = this.ensureInputSession('editor extend action');
    if (!sessionCheck.success) {
      return sessionCheck;
    }
    const preparation = await this.finishCompositionBeforeUserModeSwitch(generation);
    if (!preparation.success || !this.isInputSessionGenerationCurrent(generation)) {
      return preparation.success
        ? this.staleInputAction('editor extend action preparation')
        : preparation;
    }
    if (!this.imeService.sendExtendAction) {
      this.store.recordError(ImeErrorCode.UNSUPPORTED_OPERATION, 'editor extend action is unavailable');
      return inputOperationFailed(ImeErrorCode.UNSUPPORTED_OPERATION, 'editor extend action is unavailable');
    }
    const sent = await this.imeService.sendExtendAction(action);
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('editor extend action completion');
    }
    if (!sent) {
      this.store.recordError(ImeErrorCode.UNSUPPORTED_OPERATION, 'editor rejected extend action');
      return inputOperationFailed(ImeErrorCode.UNSUPPORTED_OPERATION, 'editor rejected extend action');
    }
    this.store.clearError();
    return inputOperationOk();
  }

  private mapInputMethodSwitchResult(result: InputMethodSwitchResult): InputOperationResult {
    if (result.success) {
      this.store.clearError();
      return inputOperationOk();
    }
    if (result.type === InputMethodSwitchResultType.SESSION_INVALID) {
      return inputOperationFailed(ImeErrorCode.ENGINE_NOT_INITIALIZED, 'input method session changed');
    }
    if (result.type === InputMethodSwitchResultType.UNAVAILABLE) {
      this.store.recordError(ImeErrorCode.UNSUPPORTED_OPERATION, '系统输入法切换不可用');
      return inputOperationFailed(ImeErrorCode.UNSUPPORTED_OPERATION, 'system input method switching unavailable');
    }
    this.store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, '无法打开系统输入法选择器');
    return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'system input method request failed');
  }

  private async switchKeyboardMode(
    target: KeyboardMode,
    generation: number
  ): Promise<InputOperationResult> {
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('keyboard mode switch');
    }
    const preparation = await this.finishCompositionBeforeUserModeSwitch(generation);
    if (!preparation.success) {
      return preparation;
    }
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('keyboard mode switch completion');
    }
    const mode = this.store.switchKeyboardMode(target, true);
    LOGGER.info(`keyboard mode changed: ${mode}`);
    return inputOperationOk();
  }

  private async finishCompositionBeforeUserModeSwitch(generation: number): Promise<InputOperationResult> {
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('finish composition');
    }
    const state = this.store.getSnapshot();
    if (state.keyboardMode !== KeyboardMode.CHINESE || state.rawInput.length <= 0) {
      return inputOperationOk();
    }

    if (state.candidates.length > 0) {
      const commitResult = await this.commitCandidate(0, generation);
      if (!commitResult.success) {
        return commitResult;
      }
    } else {
      const cleared = await this.imeService.clearPreviewText(generation);
      if (!this.isInputSessionGenerationCurrent(generation)) {
        return this.staleInputAction('finish composition preview cleanup');
      }
      if (!cleared) {
        this.store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'composition preview cleanup failed');
        return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'composition preview cleanup failed');
      }
      if (!this.isInputSessionGenerationCurrent(generation)) {
        return this.staleInputAction('finish composition completion');
      }
    }

    if (this.engineCoordinator.isInitialized()) {
      this.store.updateComposition(this.engineCoordinator.reset());
    }
    this.store.clearComposition();
    return inputOperationOk();
  }

}
