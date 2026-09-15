from pathlib import Path
exec((Path(__file__).parent / 'implement-clipboard-reverse.py').read_text(encoding='utf-8').split("replace('engine-rust/crates/code-table-runtime/src/state.rs'")[0])

# The patch tool reported an error after writing these blocks; retain one copy.
for name, start, end in [
    ('engine-rust/crates/code-table-runtime/src/state.rs', '    /// Read-only lookup', '    pub fn new('),
    ('engine-rust/crates/ime-engine/src/formal/composition_state.rs', '    pub fn reverse_lookup', '    pub fn local_associations('),
]:
    def dedup(text):
        first = text.index(start)
        second = text.index(start, first + 1)
        return text[:first] + text[second:]
    edit(name, dedup)
replace('engine-rust/crates/code-table-runtime/src/action.rs', '        "clipboard.reverse" => target.is_empty(),\n        "clipboard.reverse" => target.is_empty(),', '        "clipboard.reverse" => target.is_empty(),')

base = 'entry/src/main/ets/application/InputSessionControllerBase.ets'
replace(base, "import { ShapeLookupService } from './ShapeLookupService';", """import { ShapeLookupService } from './ShapeLookupService';
import { ClipboardReverseLookupService, ClipboardReverseLookupResult } from './ClipboardReverseLookupService';
import { CLIPBOARD_REVERSE_CODE, CLIPBOARD_REVERSE_LABEL } from '../domain/direct/ClipboardReverseLookup';""")
replace(base, '  private shapeLookupGeneration: number = -1;', '''  protected readonly clipboardReverseService: ClipboardReverseLookupService = new ClipboardReverseLookupService();
  protected clipboardReverseResult?: ClipboardReverseLookupResult;
  protected clipboardReverseGeneration: number = -1;
  private clipboardReverseRequest: number = 0;
  private shapeLookupGeneration: number = -1;''')
replace(base, '  protected async refreshShapeLookupCandidate(generation: number): Promise<void> {', '''  async refreshClipboardReverseCandidate(generation: number = this.getInputSessionGeneration()): Promise<void> {
    const request = ++this.clipboardReverseRequest;
    this.clipboardReverseResult = undefined;
    this.clipboardReverseGeneration = -1;
    const state = this.store.getSnapshot();
    if (!this.isInputSessionGenerationCurrent(generation) || state.rawInput !== CLIPBOARD_REVERSE_CODE ||
      state.editorContext.isPassword || !state.editorContext.chineseModeAllowed ||
      state.keyboardMode !== KeyboardMode.CHINESE ||
      !state.candidates.some((candidate: Candidate): boolean =>
        candidate.source === 'functional' && candidate.text === CLIPBOARD_REVERSE_LABEL)) { return; }
    const result = await this.clipboardReverseService.resolve(
      (character: string): string[] => this.engineCoordinator.reverseLookup(character));
    if (request !== this.clipboardReverseRequest || !this.isInputSessionGenerationCurrent(generation) ||
      this.store.getSnapshot().rawInput !== CLIPBOARD_REVERSE_CODE || this.store.getSnapshot().editorContext.isPassword) { return; }
    this.clipboardReverseResult = result;
    this.clipboardReverseGeneration = generation;
    this.store.setFunctionalCandidateDisplay(CLIPBOARD_REVERSE_LABEL, result.text || CLIPBOARD_REVERSE_LABEL);
  }

  protected async refreshShapeLookupCandidate(generation: number): Promise<void> {''')
replace(base, '  beginInputAction(timestampMs: number = Date.now()): SmartPeriodInputAction {', '''  beginInputAction(timestampMs: number = Date.now()): SmartPeriodInputAction {
    this.clipboardReverseRequest += 1;''')
replace('entry/src/main/ets/application/InputSessionCompositionController.ets', '      await this.refreshShapeLookupCandidate(generation);', '      await this.refreshShapeLookupCandidate(generation);\n      await this.refreshClipboardReverseCandidate(generation);')
commit = 'entry/src/main/ets/application/InputSessionCommitController.ets'
edit(commit, lambda text: "import { CLIPBOARD_REVERSE_CODE, CLIPBOARD_REVERSE_LABEL } from '../domain/direct/ClipboardReverseLookup';\n" + text)
replace(commit, '''      if (candidate.source === 'functional') {
        return this.commitFunctionalCandidate(candidateIndex, generation);
      }''', '''      if (candidate.source === 'functional') {
        if (state.rawInput === CLIPBOARD_REVERSE_CODE && candidate.text === CLIPBOARD_REVERSE_LABEL) {
          return await this.commitClipboardReverseCandidate(candidateIndex, generation);
        }
        return await this.commitFunctionalCandidate(candidateIndex, generation);
      }''')
replace(commit, '  private async commitFunctionalCandidate(', '''  private async commitClipboardReverseCandidate(candidateIndex: number, generation: number): Promise<InputOperationResult> {
    if (this.clipboardReverseGeneration !== generation || this.clipboardReverseResult === undefined) {
      await this.refreshClipboardReverseCandidate(generation);
    }
    if (!this.isInputSessionGenerationCurrent(generation)) { return this.staleInputAction('clipboard reverse'); }
    const lookup = this.clipboardReverseResult;
    if (lookup === undefined || !lookup.available) {
      const message = '请点击候选区的粘贴按钮，读取单字后反查';
      this.store.recordError(ImeErrorCode.UNSUPPORTED_OPERATION, message);
      return inputOperationFailed(ImeErrorCode.UNSUPPORTED_OPERATION, message);
    }
    // Display and commit share the same snapshot. Never insert the placeholder,
    // clipboard contents or the triggering code into the editor.
    const inserted = lookup.text.length > 0
      ? await this.imeService.commitPreviewText(lookup.text, generation)
      : await this.imeService.clearPreviewText(generation);
    if (!this.isInputSessionGenerationCurrent(generation)) { return this.staleInputAction('clipboard reverse completion'); }
    if (!inserted) {
      return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR, '反查编码上屏失败，请重试');
    }
    if (lookup.text.length > 0) { this.recordCommittedText(lookup.text); }
    // The clipboard action was fulfilled above; consume its native candidate
    // only after the editor succeeds, without dispatching the action twice.
    try { this.engineCoordinator.selectCandidate(candidateIndex); } finally {
      this.engineCoordinator.reset();
      this.store.clearComposition();
      this.clipboardReverseResult = undefined;
      this.clipboardReverseGeneration = -1;
      this.syncCursorPreeditVisibility('');
    }
    return inputOperationOk();
  }

  private async commitFunctionalCandidate(''')
replace('entry/src/main/ets/application/KeyboardController.ets', '  async commitCandidate(candidateIndex: number): Promise<InputOperationResult> {', '''  refreshClipboardReverseCandidate(): Promise<void> {
    // Read in the security component click turn, before waiting on an input queue.
    return this.sessionController.refreshClipboardReverseCandidate();
  }

  async commitCandidate(candidateIndex: number): Promise<InputOperationResult> {''')
bar = 'entry/src/main/ets/presentation/candidate/CandidateBar.ets'
edit(bar, lambda text: "import { ClipboardReversePasteButton } from './ClipboardReversePasteButton';\nimport { CLIPBOARD_REVERSE_CODE, CLIPBOARD_REVERSE_LABEL } from '../../domain/direct/ClipboardReverseLookup';\n" + text)
edit(bar, lambda text: text.replace('  onCandidateClick?: (candidate: Candidate, index: number) => void;', '  onCandidateClick?: (candidate: Candidate, index: number) => void;\n  onClipboardReversePaste?: () => void;'))
replace(bar, '          ForEach(this.collapsedCandidates(),', '''          if (this.rawInput === CLIPBOARD_REVERSE_CODE && this.candidates.some((candidate: Candidate): boolean =>
            candidate.source === 'functional' && candidate.text === CLIPBOARD_REVERSE_LABEL)) {
            ClipboardReversePasteButton({ onPaste: this.onClipboardReversePaste })
          }
          ForEach(this.collapsedCandidates(),''')
root = 'entry/src/main/ets/presentation/keyboard/KeyboardRootStage3.ets'
replace(root, '        CandidateBar({', '''        CandidateBar({
        onClipboardReversePaste: (): void => { this.controller.refreshClipboardReverseCandidate(); },''')
floating = 'entry/src/main/ets/presentation/candidate/FloatingCandidateRoot.ets'
edit(floating, lambda text: "import { ClipboardReversePasteButton } from './ClipboardReversePasteButton';\nimport { CLIPBOARD_REVERSE_CODE, CLIPBOARD_REVERSE_LABEL } from '../../domain/direct/ClipboardReverseLookup';\n" + text)
replace(floating, "      if (this.pageStatus().length > 0) {", '''      if (this.rawInput === CLIPBOARD_REVERSE_CODE && this.candidates.some((candidate: Candidate): boolean =>
        candidate.source === 'functional' && candidate.text === CLIPBOARD_REVERSE_LABEL)) {
        ClipboardReversePasteButton({
          onPaste: (): void => { this.controller.refreshClipboardReverseCandidate(); }
        })
      }
      if (this.pageStatus().length > 0) {''')
edit('双羽词库分类/双羽词库/5.直通.txt', lambda text: text.rstrip('\n') + '\n$CC(default(dict.rev(clip()), "[复制反查]"), type(dict.rev(clip())))\tofi\n')
print('Implemented clipboard service, candidate integration and direct entry')
