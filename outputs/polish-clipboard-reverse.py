from pathlib import Path
import subprocess
exec((Path(__file__).parent / 'implement-clipboard-reverse.py').read_text(encoding='utf-8').split("replace('engine-rust/crates/code-table-runtime/src/state.rs'")[0])
name = 'scripts/import-shuangyu-customer-lexicon.ps1'
edit(name, lambda text: text.replace("-not $operation.Contains('$cmd') -and -not $operation.Contains('$ddcmd'))", "-not $operation.Contains('$cmd') -and -not $operation.Contains('$ddcmd') -and\n                    -not $operation.ToLowerInvariant().Contains('$cc('))").replace("-not $syntax.Contains('$cmd') -and -not $syntax.Contains('$ddcmd'))", "-not $syntax.Contains('$cmd') -and -not $syntax.Contains('$ddcmd') -and\n                    -not $syntax.ToLowerInvariant().Contains('$cc('))"))
name = 'engine-rust/crates/code-table-runtime/src/action.rs'
replace(name, '        || value.to_ascii_lowercase().contains("$cmd")', '        || value.to_ascii_lowercase().contains("$cmd")\n        || value.to_ascii_lowercase().contains("$cc(")')
replace(name, '        || lower.contains("$ddcmd")', '        || lower.contains("$ddcmd")\n        || lower.contains("$cc(")')
replace(name, '        let cases = [\n            r#"{"formatVersion":1,"fixtureOnly":false', '''        let cases = [
            r#"{"formatVersion":1,"fixtureOnly":false,"source":"5.直通.txt","sourceRecordCount":1,"rejectedRecordCount":0,"records":[{"id":"x","scope":"DIRECT","code":"ofi","label":"x","type":"STATIC_TEXT","text":"$CC(clip(),type(clip()))"}]}"#.as_bytes(),
            r#"{"formatVersion":1,"fixtureOnly":false''')
edit('entry/src/main/ets/domain/direct/ClipboardReverseLookup.ets', lambda text: text + '\nexport const CLIPBOARD_REVERSE_PASTE_WIDTH: number = 88;\n')
name = 'entry/src/main/ets/presentation/candidate/ClipboardReversePasteButton.ets'
edit(name, lambda text: "import { CLIPBOARD_REVERSE_PASTE_WIDTH } from '../../domain/direct/ClipboardReverseLookup';\n\n" + text)
replace(name, '    PasteButton()\n      .fontSize(14)', '    PasteButton()\n      .width(CLIPBOARD_REVERSE_PASTE_WIDTH)\n      .height(36)\n      .fontSize(14)')
name = 'entry/src/main/ets/domain/candidate/FloatingCandidateLayout.ets'
edit(name, lambda text: "import { CLIPBOARD_REVERSE_PASTE_WIDTH } from '../direct/ClipboardReverseLookup';\n" + text)
replace(name, '  expandActionVisible?: boolean;', '  expandActionVisible?: boolean;\n  clipboardReverseVisible?: boolean;')
replace(name, '  if (input.expandActionVisible) {', '  if (input.clipboardReverseVisible) { width += CLIPBOARD_REVERSE_PASTE_WIDTH + FLOATING_CANDIDATE_ITEM_GAP_VP; }\n\n  if (input.expandActionVisible) {')
name = 'entry/src/main/ets/application/FloatingCandidateWindowController.ets'
edit(name, lambda text: "import { CLIPBOARD_REVERSE_CODE, CLIPBOARD_REVERSE_LABEL } from '../domain/direct/ClipboardReverseLookup';\n" + text)
replace(name, '    const baseWidth = estimateFloatingCandidateWidthVp({', '''    const baseWidth = estimateFloatingCandidateWidthVp({
      clipboardReverseVisible: state.rawInput === CLIPBOARD_REVERSE_CODE && state.candidates.some((candidate: Candidate): boolean =>
        candidate.source === 'functional' && candidate.text === CLIPBOARD_REVERSE_LABEL),''')
name = 'entry/src/main/ets/presentation/candidate/FloatingCandidateRoot.ets'
replace(name, '    const width = estimateFloatingCandidateWidthVp({', '''    const width = estimateFloatingCandidateWidthVp({
      clipboardReverseVisible: this.rawInput === CLIPBOARD_REVERSE_CODE && this.candidates.some((candidate: Candidate): boolean =>
        candidate.source === 'functional' && candidate.text === CLIPBOARD_REVERSE_LABEL),''')
name = 'scripts/README.md'
edit(name, lambda text: text + '''
## 复制反查直通

`pwsh -File scripts/test-clipboard-reverse-import.ps1` 验证客户 `$CC` 和旧 `querycode` 格式的转换。
`import-shuangyu-customer-lexicon.ps1 -UpdateProject -DirectActionsOnly` 仅更新直通清理稿、动作表和报告，跳过字词资源写入。
行为与设备验收见 [复制反查说明](../docs/features/direct-control/CLIPBOARD_REVERSE_LOOKUP.md)。
''')

# Format only the new Rust blocks, preserving pre-existing unrelated edits.
def format_region(name, begin, end, wrapper=''):
    def formatted(text):
        first = text.index(begin)
        last = text.index(end, first) if end else len(text)
        block = text[first:last].rstrip() + '\n'
        source = wrapper + ' {\n' + block + '}\n' if wrapper else block
        result = subprocess.run(['rustfmt', '--edition', '2021', '--emit', 'stdout'], input=source, encoding='utf-8', capture_output=True, check=True).stdout
        if wrapper: result = result[result.index('\n') + 1:result.rindex('}')]
        return text[:first] + result.rstrip() + '\n\n' + text[last:]
    edit(name, formatted)
format_region('engine-rust/crates/code-table-runtime/src/state.rs', '    /// Read-only lookup', '    pub fn new(', 'impl Example')
format_region('engine-rust/crates/ime-engine/src/formal/composition_state.rs', '    pub fn reverse_lookup', '    pub fn local_associations', 'impl Example')
format_region('engine-rust/crates/ime-ffi/src/ffi/exports.rs', '#[no_mangle]\n/// # Safety\n/// `text_utf8`', '#[no_mangle]\npub extern "C" fn ime_engine_get_code_table_category_config')
format_region('engine-rust/crates/code-table-runtime/tests/runtime.rs', '#[test]\nfn clipboard_reverse_lookup_', '')
format_region('engine-rust/crates/ime-engine/tests/xiaohe_yinxing_production.rs', '#[test]\nfn clipboard_reverse_ofi_', '')
format_region('engine-rust/crates/ime-ffi/src/ffi/tests.rs', '    #[test]\n    fn clipboard_reverse_ffi_', '    #[test]\n    fn local_association_ffi_', 'mod tests')
print('Polished import validation, paste button sizing and Rust formatting')
