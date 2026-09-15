from pathlib import Path
exec((Path(__file__).parent / 'implement-clipboard-reverse.py').read_text(encoding='utf-8').split("replace('engine-rust/crates/code-table-runtime/src/state.rs'")[0])
replace('engine-rust/crates/code-table-runtime/src/state.rs', 'if entry.text == text { codes.insert(entry.pinyin_key.clone()); }', 'if entry.word == text { codes.insert(entry.pinyin_key.clone()); }')
replace('scripts/import-shuangyu-customer-lexicon.ps1', '        switch -CaseSensitive ($operation) {', "        switch -CaseSensitive ($operation) {\n            'querycode' { $record.type = 'DIRECT_CONTROL'; $record.action = 'clipboard.reverse'; $record.target = ''; $record.label = '[复制反查]' }")
domain = 'entry/src/main/ets/domain/direct/ClipboardReverseLookup.ets'
edit(domain, lambda text: text + '''
export interface ClipboardReverseLookupResult {
  available: boolean;
  character: string;
  text: string;
}
''')
service = 'entry/src/main/ets/application/ClipboardReverseLookupService.ets'
replace(service, "import { clipboardReverseCharacter }", "import { clipboardReverseCharacter, ClipboardReverseLookupResult }")
replace(service, '''export interface ClipboardReverseLookupResult {
  available: boolean;
  character: string;
  text: string;
}

''', '')
store = 'entry/src/main/ets/state/InputSessionStore.ets'
edit(store, lambda text: "import { ClipboardReverseLookupResult, CLIPBOARD_REVERSE_CODE, CLIPBOARD_REVERSE_LABEL } from '../domain/direct/ClipboardReverseLookup';\n" + text)
replace(store, 'export class InputSessionStore {', '''export class InputSessionStore {
  private clipboardReverseResult?: ClipboardReverseLookupResult;
  private clipboardReverseRevision: number = 0;

  beginClipboardReverseRequest(): number { return ++this.clipboardReverseRevision; }
  getClipboardReverseResult(): ClipboardReverseLookupResult | undefined { return this.clipboardReverseResult; }
  setClipboardReverseResult(request: number, result: ClipboardReverseLookupResult): void {
    if (request !== this.clipboardReverseRevision || this.state.rawInput !== CLIPBOARD_REVERSE_CODE ||
      this.state.editorContext.isPassword) { return; }
    this.clipboardReverseResult = result;
    this.clearErrorInternal();
    this.setFunctionalCandidateDisplay(CLIPBOARD_REVERSE_LABEL, result.text || CLIPBOARD_REVERSE_LABEL);
  }
  private clearClipboardReverseResult(): void {
    this.clipboardReverseRevision += 1;
    this.clipboardReverseResult = undefined;
  }
''')
replace(store, '  advanceSessionGeneration(): number {', '  advanceSessionGeneration(): number {\n    this.clearClipboardReverseResult();')
replace(store, '  updateComposition(result: CompositionResult): void {', '''  updateComposition(result: CompositionResult): void {
    if (this.state.rawInput !== result.rawInput) { this.clearClipboardReverseResult(); }''')
replace(store, '  private clearCompositionInternal(): void {', '  private clearCompositionInternal(): void {\n    this.clearClipboardReverseResult();')
replace(store, '    this.state.candidates = result.candidates;', '''    this.state.candidates = result.candidates;
    if (this.clipboardReverseResult !== undefined && result.rawInput === CLIPBOARD_REVERSE_CODE) {
      this.state.candidates.forEach((candidate: Candidate): void => {
        if (candidate.source === 'functional' && candidate.text === CLIPBOARD_REVERSE_LABEL) {
          candidate.displayText = this.clipboardReverseResult?.text || CLIPBOARD_REVERSE_LABEL;
        }
      });
    }''')
base = 'entry/src/main/ets/application/InputSessionControllerBase.ets'
replace(base, 'ClipboardReverseLookupService, ClipboardReverseLookupResult', 'ClipboardReverseLookupService')
replace(base, '''  protected clipboardReverseResult?: ClipboardReverseLookupResult;
  protected clipboardReverseGeneration: number = -1;
  private clipboardReverseRequest: number = 0;
''', '')
replace(base, '''    const request = ++this.clipboardReverseRequest;
    this.clipboardReverseResult = undefined;
    this.clipboardReverseGeneration = -1;''', '    const request = this.store.beginClipboardReverseRequest();')
replace(base, '    if (request !== this.clipboardReverseRequest || !this.isInputSessionGenerationCurrent(generation) ||', '    if (!this.isInputSessionGenerationCurrent(generation) ||')
replace(base, '''    this.clipboardReverseResult = result;
    this.clipboardReverseGeneration = generation;
    this.store.setFunctionalCandidateDisplay(CLIPBOARD_REVERSE_LABEL, result.text || CLIPBOARD_REVERSE_LABEL);''', '    this.store.setClipboardReverseResult(request, result);')
replace(base, '    this.clipboardReverseRequest += 1;', '    this.store.beginClipboardReverseRequest();')
commit = 'entry/src/main/ets/application/InputSessionCommitController.ets'
replace(commit, '    if (this.clipboardReverseGeneration !== generation || this.clipboardReverseResult === undefined) {', '    if (this.store.getClipboardReverseResult() === undefined) {')
replace(commit, '    const lookup = this.clipboardReverseResult;', '    const lookup = this.store.getClipboardReverseResult();')
replace(commit, "      this.store.recordError(ImeErrorCode.UNSUPPORTED_OPERATION, message);\n      return inputOperationFailed(ImeErrorCode.UNSUPPORTED_OPERATION, message);\n    }\n    // Display", "      return inputOperationFailed(ImeErrorCode.UNSUPPORTED_OPERATION, message);\n    }\n    // Display")
replace(commit, '''      this.clipboardReverseResult = undefined;
      this.clipboardReverseGeneration = -1;
''', '')
print('Refined shared session snapshot and existing legacy ofi import')
