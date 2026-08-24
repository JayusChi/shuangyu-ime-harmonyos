import { EnterAction } from '../domain/editor/EditorContext';
import { EditorExtendAction } from '../domain/keyboard/KeyboardAction';
import { ProtocolActionImeService } from './ProtocolActionExecutor';

export interface ImeInputService extends ProtocolActionImeService {
  insertText(text: string): Promise<boolean>;
  setPreviewText(
    text: string,
    previewSupported?: boolean,
    generation?: number,
    anchorAfterCandidateCommit?: boolean,
    serializedContinuation?: boolean
  ): Promise<boolean>;
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
  sendExtendAction?(action: EditorExtendAction): Promise<boolean>;
  sendEnter(action?: EnterAction): Promise<boolean>;
  hideKeyboard(): Promise<boolean>;
}
