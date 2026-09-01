import { EnterAction } from '../domain/editor/EditorContext';
import { EditorExtendAction } from '../domain/keyboard/KeyboardAction';
import { ProtocolActionImeService } from './ProtocolActionExecutor';
import { inputMethodEngine } from '@kit.IMEKit';

export interface ImeInputService extends ProtocolActionImeService {
  insertText(text: string): Promise<boolean>;
  setPreviewText(
    text: string,
    previewSupported?: boolean,
    generation?: number,
    anchorAfterCandidateCommit?: boolean,
    serializedContinuation?: boolean
  ): Promise<boolean>;
  /** 当前组合输入码是否实际由编辑器光标处的系统预编辑展示。 */
  isCursorPreviewActive?(): boolean;
  finishPreviewText(generation?: number): Promise<boolean>;
  clearPreviewText(generation?: number): Promise<boolean>;
  isPreviewTextAttached(generation?: number): Promise<boolean>;
  commitCandidatePreviewText?(
    committedText: string,
    remainingRawInput: string,
    generation?: number
  ): Promise<boolean>;
  resetPreviewState(): void;
  deleteBackward(count?: number): Promise<boolean>;
  deleteBackwardIfMatches?(text: string): Promise<boolean>;
  textBeforeCursorMatches?(text: string): Promise<boolean>;
  getCursorIndex?(): Promise<number | undefined>;
  getTextBeforeCursor?(maxUnits: number): Promise<string | undefined>;
  replaceTextBeforeCursorIfMatches?(
    sourceText: string,
    replacementText: string,
    stillOwned?: () => boolean,
    expectedCursorUtf16?: number
  ): Promise<boolean>;
  hasPendingPair?(generation?: number): boolean;
  jumpOutPair?(generation?: number): Promise<boolean>;
  clearPairState?(): void;
  moveToLineEnd?(): Promise<boolean>;
  deleteCurrentLine?(): Promise<boolean>;
  restoreLastDeletion?(): Promise<boolean>;
  clearDeletionRecovery?(): void;
  sendExtendAction?(action: EditorExtendAction): Promise<boolean>;
  moveCursor?(direction: inputMethodEngine.Direction): Promise<void>;
  sendEnter(action?: EnterAction): Promise<boolean>;
  hideKeyboard(): Promise<boolean>;
}
