import { inputMethodEngine } from '@kit.IMEKit';
import { Logger } from '../../common/logging/Logger';
import { CompositionTextManager } from './ImePreviewService';

const TAG = 'Stage0ImeConnection';
const LOGGER = new Logger(TAG);

export class ImeConnectionLifecycle {
  protected static keyboardController?: inputMethodEngine.KeyboardController;
  protected static inputClient?: inputMethodEngine.InputClient;
  private static keyboardDelegate?: inputMethodEngine.KeyboardDelegate;
  private static editorAttributeCallback?: (attribute: inputMethodEngine.EditorAttribute) => void;
  protected static compositionTextManager: CompositionTextManager = new CompositionTextManager();

  static bindSession(
    keyboardController: inputMethodEngine.KeyboardController,
    inputClient: inputMethodEngine.InputClient
  ): void {
    ImeConnectionLifecycle.keyboardController = keyboardController;
    ImeConnectionLifecycle.inputClient = inputClient;
    ImeConnectionLifecycle.compositionTextManager = new CompositionTextManager();
    LOGGER.info('IME session bound');
  }

  static clearSession(): void {
    ImeConnectionLifecycle.keyboardController = undefined;
    ImeConnectionLifecycle.inputClient = undefined;
    ImeConnectionLifecycle.compositionTextManager = new CompositionTextManager();
    LOGGER.info('IME session cleared');
  }

  static hasActiveSession(): boolean {
    return !!ImeConnectionLifecycle.keyboardController && !!ImeConnectionLifecycle.inputClient;
  }

  static getEditorAttributeSync(): inputMethodEngine.EditorAttribute | undefined {
    if (!ImeConnectionLifecycle.inputClient) {
      return undefined;
    }
    try {
      return ImeConnectionLifecycle.inputClient.getEditorAttributeSync();
    } catch (err) {
      LOGGER.warn('getEditorAttributeSync failed; using safe unknown editor context');
      return undefined;
    }
  }

  static observeEditorAttributes(
    callback: (attribute: inputMethodEngine.EditorAttribute) => void
  ): void {
    ImeConnectionLifecycle.stopObservingEditorAttributes();
    try {
      const delegate = inputMethodEngine.getKeyboardDelegate();
      delegate.on('editorAttributeChanged', callback);
      ImeConnectionLifecycle.keyboardDelegate = delegate;
      ImeConnectionLifecycle.editorAttributeCallback = callback;
      LOGGER.info('editor attribute observer registered');
    } catch (err) {
      LOGGER.warn('editor attribute observer unavailable');
    }
  }

  static stopObservingEditorAttributes(): void {
    const delegate = ImeConnectionLifecycle.keyboardDelegate;
    const callback = ImeConnectionLifecycle.editorAttributeCallback;
    if (delegate && callback) {
      try {
        delegate.off('editorAttributeChanged', callback);
      } catch (err) {
        LOGGER.warn('editor attribute observer cleanup failed');
      }
    }
    ImeConnectionLifecycle.keyboardDelegate = undefined;
    ImeConnectionLifecycle.editorAttributeCallback = undefined;
  }

  protected static resetCompositionTextManager(): void {
    ImeConnectionLifecycle.compositionTextManager = new CompositionTextManager();
  }
}
