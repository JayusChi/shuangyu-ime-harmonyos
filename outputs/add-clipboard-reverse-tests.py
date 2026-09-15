from pathlib import Path
exec((Path(__file__).parent / 'implement-clipboard-reverse.py').read_text(encoding='utf-8').split("replace('engine-rust/crates/code-table-runtime/src/state.rs'")[0])
replace('scripts/import-shuangyu-customer-lexicon.ps1', '    [switch]$UpdateProject\n', '    [switch]$UpdateProject,\n    [switch]$DirectActionsOnly\n')
replace('scripts/import-shuangyu-customer-lexicon.ps1', 'foreach ($entry in $cleanedFiles.GetEnumerator()) {\n    Write-Utf8Lf', "foreach ($entry in $cleanedFiles.GetEnumerator()) {\n    if ($DirectActionsOnly -and $entry.Key -ne '5.直通.txt') { continue }\n    Write-Utf8Lf")
replace('scripts/import-shuangyu-customer-lexicon.ps1', '    foreach ($entry in $formalFiles.GetEnumerator()) {\n        Write-Utf8Lf', '    foreach ($entry in $formalFiles.GetEnumerator()) {\n        if ($DirectActionsOnly) { continue }\n        Write-Utf8Lf')
edit('engine-rust/crates/code-table-runtime/tests/runtime.rs', lambda text: text + '''
#[test]
fn clipboard_reverse_lookup_keeps_composition_and_includes_hidden_full_codes() {
    let mut machine = state_from_specs(&[
        TableSpec { id: "core", order: 10, enabled: true, guide: false,
            entries: vec![("你", "n"), ("你", "ni"), ("你好", "nihk"), ("𠮷", "abcd")] },
        TableSpec { id: "full-code-character", order: 20, enabled: false, guide: false,
            entries: vec![("你", "nirx"), ("你", "ni")] },
    ], 1, 1);
    input(&mut machine, "n");
    let before = machine.query_cache().cloned();
    assert_eq!(machine.reverse_lookup("你"), ["nirx", "ni", "n"]);
    assert_eq!(machine.reverse_lookup("𠮷"), ["abcd"]);
    for text in ["", "你好", "n", "😀", " 你", "你\\n", "龘"] {
        assert!(machine.reverse_lookup(text).is_empty(), "{text}");
    }
    assert_eq!(machine.raw_code(), "n");
    assert_eq!(machine.query_cache(), before.as_ref());
    machine.set_user_lexicon_snapshot(snapshot("你\\tni#删\\n你\\tniru\\n"));
    assert_eq!(machine.reverse_lookup("你"), ["niru", "nirx", "n"]);
}
''')
edit('engine-rust/crates/ime-engine/tests/xiaohe_yinxing_production.rs', lambda text: text + '''
#[test]
fn clipboard_reverse_ofi_is_a_functional_candidate_and_lookup_does_not_commit() {
    let mut engine = ImeEngine::new(config("xiaohe-yinxing", Some(formal_bundle()), None, 5)).unwrap();
    let result = enter(&mut engine, "ofi");
    let index = result.candidates.iter().position(|candidate| candidate.text == "[复制反查]").unwrap();
    assert_eq!(result.candidates[index].source, "functional");
    assert!(result.commit_text.is_empty());
    assert!(result.action.is_none());
    let codes = engine.reverse_lookup("你");
    assert!(codes.iter().any(|code| code == "nirx"), "{codes:?}");
    assert_eq!(engine.current_state().raw_input, "ofi");
    let selected = engine.select_candidate(index).unwrap();
    assert!(selected.commit_text.is_empty());
    assert_eq!(selected.action, Some(ProtocolAction::DirectControl {
        action: "clipboard.reverse".to_owned(), target: String::new(),
    }));
    let phonetic = ImeEngine::new(config("xiaohe", Some(formal_bundle()), None, 5)).unwrap();
    assert!(phonetic.reverse_lookup("你").is_empty());
}
''')
replace('engine-rust/crates/ime-ffi/src/ffi/tests.rs', '    #[test]\n    fn local_association_ffi_is_bounded_json_and_defaults_empty()', '''    #[test]
    fn clipboard_reverse_ffi_handles_invalid_utf8_size_and_handle() {
        let mut handle = create_default_engine();
        let mut out = ImeBuffer::empty();
        unsafe {
            assert_eq!(ime_engine_reverse_lookup(handle, "你".as_ptr(), 3, &mut out), 0);
            assert_eq!(take_buffer(out), "[]");
            out = ImeBuffer::empty();
            assert_eq!(ime_engine_reverse_lookup(handle, b"hello".as_ptr(), 5, &mut out), ImeErrorCode::InvalidArgument.as_i32());
            assert_ne!(ime_engine_reverse_lookup(handle, [0xff].as_ptr(), 1, &mut out), 0);
            assert_eq!(ime_engine_reverse_lookup(ptr::null_mut(), "你".as_ptr(), 3, &mut out), ImeErrorCode::InvalidHandle.as_i32());
        }
        assert_eq!(ffi_destroy(&mut handle), 0);
    }

    #[test]
    fn local_association_ffi_is_bounded_json_and_defaults_empty()''')
print('Added runtime, engine and FFI regressions')
