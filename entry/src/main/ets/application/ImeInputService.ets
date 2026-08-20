import { EnterAction } from '../domain/editor/EditorContext';
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
  moveToLineEnd?(): Promise<boolean>;
  sendEnter(action?: EnterAction): Promise<boolean>;
  hideKeyboard(): Promise<boolean>;
}

