#[cfg(test)]
mod tests {
    use super::*;
    use engine_protocol::ProtocolParserState;
    use std::ffi::CString;
    use std::fs;
    use std::path::PathBuf;
    use std::sync::OnceLock;
    use std::time::{SystemTime, UNIX_EPOCH};

    use code_table_fixture_generator::{build_bundle, generate_fixture};
    use code_table_runtime::CodeTableBundle;
    use lexicon_core::{build_binary_lexicon, LexiconEntry};

    fn ffi_create(
        config_utf8: *const u8,
        config_len: usize,
        out_handle: *mut *mut ImeEngineOpaque,
    ) -> i32 {
        // SAFETY: tests pass pointers to local storage or explicit nulls to verify FFI behavior.
        unsafe { ime_engine_create(config_utf8, config_len, out_handle) }
    }

    fn ffi_destroy(handle: *mut *mut ImeEngineOpaque) -> i32 {
        // SAFETY: tests pass handles returned by ime_engine_create or explicit nulls.
        unsafe { ime_engine_destroy(handle) }
    }

    fn ffi_free_buffer(buffer: *mut ImeBuffer) -> i32 {
        // SAFETY: tests pass buffers returned by this crate or explicit nulls.
        unsafe { ime_engine_free_buffer(buffer) }
    }

    fn take_buffer(mut buffer: ImeBuffer) -> String {
        assert!(!buffer.data.is_null());
        assert!(buffer.len > 0);
        // SAFETY: test buffers are produced by this crate and contain buffer.len readable bytes.
        let value = unsafe { slice::from_raw_parts(buffer.data, buffer.len) };
        let value = str::from_utf8(value)
            .expect("buffer should be utf8")
            .to_owned();
        assert_eq!(ffi_free_buffer(&mut buffer), ImeErrorCode::Success.as_i32());
        assert!(buffer.data.is_null());
        assert_eq!(buffer.len, 0);
        value
    }

    fn create_default_engine() -> *mut ImeEngineOpaque {
        let mut handle = ptr::null_mut();
        let code = ffi_create(ptr::null(), 0, &mut handle);
        assert_eq!(code, ImeErrorCode::Success.as_i32());
        assert!(!handle.is_null());
        handle
    }

    fn create_test_lexicon() -> PathBuf {
        let entries = vec![
            LexiconEntry::new(
                "你".to_owned(),
                "ni".to_owned(),
                vec!["ni".to_owned()],
                100_000,
                vec!["stage7".to_owned()],
            ),
            LexiconEntry::new(
                "你好".to_owned(),
                "ni hao".to_owned(),
                vec!["ni".to_owned(), "hao".to_owned()],
                72_000,
                vec!["stage7".to_owned()],
            ),
        ];
        let bytes = build_binary_lexicon(&entries, 7, 1).unwrap();
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!("stage7-ime-ffi-{nanos}.lex"));
        fs::write(&path, bytes).unwrap();
        path
    }

    fn code_table_bundle_path() -> &'static PathBuf {
        static PATH: OnceLock<PathBuf> = OnceLock::new();
        PATH.get_or_init(|| {
            let root = std::env::temp_dir().join(format!(
                "stage11-6-3-ime-ffi-fixture-{}",
                std::process::id()
            ));
            let _ = fs::remove_dir_all(&root);
            let report = generate_fixture(&root).unwrap();
            let bundle = build_bundle(&report.manifest_path).unwrap();
            let path = root.join("code-table-fixture-synthetic.bundle");
            fs::write(&path, bundle.bytes).unwrap();
            path
        })
    }

    fn formal_bundle_path() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(
            "../../../dictionaries/generated/xiaohe-yinxing-production/xiaohe-yinxing-production.hsyx",
        )
    }

    fn create_engine_with_lexicon(page_size: usize) -> *mut ImeEngineOpaque {
        let path = create_test_lexicon();
        let config = format!(
            "{{\"interfaceVersion\":7,\"schemeId\":\"xiaohe\",\"lexiconPath\":\"{}\",\"candidatePageSize\":{}}}",
            path.to_string_lossy().replace('\\', "\\\\"),
            page_size
        );
        let mut handle = ptr::null_mut();
        let code = ffi_create(config.as_ptr(), config.len(), &mut handle);
        assert_eq!(code, ImeErrorCode::Success.as_i32());
        assert!(!handle.is_null());
        handle
    }

    fn create_stage8_lexicon() -> PathBuf {
        let entries = vec![
            stage8_entry("法", "fa", 80_000),
            stage8_entry("输入", "shu ru", 82_000),
            stage8_entry("输入法", "shu ru fa", 90_000),
        ];
        let bytes = build_binary_lexicon(&entries, 8, 1).unwrap();
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!("stage8-ime-ffi-{nanos}.lex"));
        fs::write(&path, bytes).unwrap();
        path
    }

    fn create_engine_with_stage8_lexicon(page_size: usize) -> *mut ImeEngineOpaque {
        let path = create_stage8_lexicon();
        let config = format!(
            "{{\"interfaceVersion\":7,\"schemeId\":\"xiaohe\",\"lexiconPath\":\"{}\",\"candidatePageSize\":{}}}",
            path.to_string_lossy().replace('\\', "\\\\"),
            page_size
        );
        let mut handle = ptr::null_mut();
        let code = ffi_create(config.as_ptr(), config.len(), &mut handle);
        assert_eq!(code, ImeErrorCode::Success.as_i32());
        assert!(!handle.is_null());
        handle
    }

    fn temp_user_model_path(name: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!("stage9-ime-ffi-{name}-{nanos}.dat"))
    }

    fn stage8_entry(word: &str, pinyin: &str, frequency: u64) -> LexiconEntry {
        LexiconEntry::new(
            word.to_owned(),
            pinyin.to_owned(),
            pinyin.split(' ').map(str::to_owned).collect(),
            frequency,
            vec!["stage8".to_owned()],
        )
    }

    #[test]
    fn get_abi_and_version_success() {
        assert_eq!(ime_engine_get_abi_version(), ABI_VERSION_DIRECT_ACTIONS);
        let mut out = ImeBuffer::empty();
        let code = ime_engine_get_version(&mut out);
        assert_eq!(code, ImeErrorCode::Success.as_i32());
        assert_eq!(take_buffer(out), ENGINE_VERSION_DIRECT_ACTIONS);
    }

    #[test]
    fn local_association_ffi_is_bounded_json_and_defaults_empty() {
        let mut handle = create_default_engine();
        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_get_local_associations(handle, &mut out),
            ImeErrorCode::Success.as_i32()
        );
        assert_eq!(take_buffer(out), "[]");
        assert_eq!(ffi_destroy(&mut handle), ImeErrorCode::Success.as_i32());
    }

    #[test]
    fn quanpin_letter_contract_has_no_fixed_length_gate_cross_ffi() {
        let config = br#"{"interfaceVersion":7,"schemeId":"quanpin"}"#;
        let mut handle = ptr::null_mut();
        assert_eq!(
            ffi_create(config.as_ptr(), config.len(), &mut handle),
            ImeErrorCode::Success.as_i32()
        );
        for length in 1..=320 {
            let mut out = ImeBuffer::empty();
            assert_eq!(
                ime_engine_process_key(handle, b"v".as_ptr(), 1, &mut out),
                ImeErrorCode::Success.as_i32()
            );
            let json = take_buffer(out);
            assert!(json.contains("\"commitText\":\"\""), "letter {length}");
            assert!(
                json.contains("\"compositionFinished\":false"),
                "letter {length}"
            );
            if [64, 65, 128, 255, 256, 320].contains(&length) {
                assert!(json.contains(&format!("\"rawInput\":\"{}\"", "v".repeat(length))));
            }
        }

        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_backspace(handle, &mut out),
            ImeErrorCode::Success.as_i32()
        );
        let restored = take_buffer(out);
        assert!(restored.contains("\"commitText\":\"\""));
        assert!(restored.contains("\"compositionFinished\":false"));
        assert!(restored.contains(&format!("\"rawInput\":\"{}\"", "v".repeat(319))));
        assert_eq!(ffi_destroy(&mut handle), ImeErrorCode::Success.as_i32());
    }

    #[test]
    fn creates_and_destroys_engine() {
        let mut handle = ptr::null_mut();
        let config = br#"{"interfaceVersion":7,"schemeId":"xiaohe"}"#;
        let code = ffi_create(config.as_ptr(), config.len(), &mut handle);
        assert_eq!(code, ImeErrorCode::Success.as_i32());
        assert!(!handle.is_null());

        assert_eq!(ffi_destroy(&mut handle), ImeErrorCode::Success.as_i32());
        assert!(handle.is_null());
        assert_eq!(ffi_destroy(&mut handle), ImeErrorCode::Success.as_i32());

        let quanpin = br#"{"interfaceVersion":7,"schemeId":"quanpin"}"#;
        assert_eq!(
            ffi_create(quanpin.as_ptr(), quanpin.len(), &mut handle),
            ImeErrorCode::Success.as_i32()
        );
        assert!(!handle.is_null());
        assert_eq!(ffi_destroy(&mut handle), ImeErrorCode::Success.as_i32());
    }

    #[test]
    fn create_rejects_invalid_config_and_scheme() {
        let mut handle = ptr::null_mut();
        let invalid = b"not-json";
        assert_eq!(
            ffi_create(invalid.as_ptr(), invalid.len(), &mut handle),
            ImeErrorCode::InvalidConfig.as_i32()
        );
        assert!(handle.is_null());

        let old_interface = br#"{"interfaceVersion":2,"schemeId":"xiaohe"}"#;
        assert_eq!(
            ffi_create(old_interface.as_ptr(), old_interface.len(), &mut handle),
            ImeErrorCode::AbiVersionMismatch.as_i32()
        );
        assert!(handle.is_null());

        let previous_interface = br#"{"interfaceVersion":6,"schemeId":"xiaohe"}"#;
        assert_eq!(
            ffi_create(
                previous_interface.as_ptr(),
                previous_interface.len(),
                &mut handle
            ),
            ImeErrorCode::AbiVersionMismatch.as_i32()
        );
        assert!(handle.is_null());

        let invalid_scheme = br#"{"schemeId":"missing"}"#;
        assert_eq!(
            ffi_create(invalid_scheme.as_ptr(), invalid_scheme.len(), &mut handle),
            ImeErrorCode::InvalidScheme.as_i32()
        );
        assert!(handle.is_null());

        let invalid_page_size = br#"{"schemeId":"xiaohe","candidatePageSize":0}"#;
        assert_eq!(
            ffi_create(
                invalid_page_size.as_ptr(),
                invalid_page_size.len(),
                &mut handle
            ),
            ImeErrorCode::InvalidConfig.as_i32()
        );
        assert!(handle.is_null());

        let missing_lexicon = br#"{"schemeId":"xiaohe","lexiconPath":"missing-stage7.lex"}"#;
        assert_eq!(
            ffi_create(missing_lexicon.as_ptr(), missing_lexicon.len(), &mut handle),
            ImeErrorCode::LexiconNotFound.as_i32()
        );
        assert!(handle.is_null());
    }

    #[test]
    fn missing_page_size_uses_production_default() {
        let config = parse_engine_config(r#"{"interfaceVersion":7,"schemeId":"xiaohe"}"#).unwrap();
        assert_eq!(config.candidate_page_size, 50);
    }

    #[test]
    fn quanpin_features_default_off_and_parse_all_supported_options() {
        let defaults =
            parse_engine_config(r#"{"interfaceVersion":10,"schemeId":"quanpin"}"#).unwrap();
        assert!(!defaults.quanpin_features.spelling_correction_enabled);
        assert!(defaults.quanpin_features.fuzzy_options.is_empty());

        let configured = parse_engine_config(
            r#"{"interfaceVersion":10,"schemeId":"quanpin","quanpinConfigVersion":1,"spellingCorrectionEnabled":true,"fuzzyOptions":["n_l","z_zh","c_ch","s_sh","in_ing","en_eng","an_ang","ian_iang"]}"#,
        )
        .unwrap();
        assert!(configured.quanpin_features.spelling_correction_enabled);
        assert_eq!(configured.quanpin_features.fuzzy_options.len(), 8);
    }

    #[test]
    fn quanpin_features_reject_unknown_options_and_versions() {
        assert!(parse_engine_config(
            r#"{"interfaceVersion":10,"schemeId":"quanpin","fuzzyOptions":["unknown"]}"#
        )
        .is_err());
        assert!(parse_engine_config(
            r#"{"interfaceVersion":10,"schemeId":"quanpin","quanpinConfigVersion":2}"#
        )
        .is_err());
    }

    #[test]
    fn quanpin_context_reranking_config_crosses_ffi_parser_and_defaults_off() {
        let defaults =
            parse_engine_config(r#"{"interfaceVersion":10,"schemeId":"quanpin"}"#).unwrap();
        assert!(!defaults.quanpin_context_reranking.enabled);
        assert_eq!(defaults.quanpin_context_reranking.model_path, None);
        assert_eq!(defaults.quanpin_context_reranking.model_sha256, None);

        let configured = parse_engine_config(
            r#"{"interfaceVersion":10,"schemeId":"quanpin","quanpinContextRerankingConfigVersion":2,"quanpinContextRerankingEnabled":true,"quanpinContextModelPath":"data/context.qng","quanpinContextModelSha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}"#,
        )
        .unwrap();
        assert!(configured.quanpin_context_reranking.enabled);
        assert_eq!(
            configured.quanpin_context_reranking.model_path.as_deref(),
            Some("data/context.qng")
        );
        assert_eq!(
            configured.quanpin_context_reranking.model_sha256.as_deref(),
            Some("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        );
    }

    #[test]
    fn quanpin_context_reranking_rejects_wrong_config_version() {
        assert!(parse_engine_config(
            r#"{"interfaceVersion":10,"schemeId":"quanpin","quanpinContextRerankingConfigVersion":3}"#
        )
        .is_err());
    }

    #[test]
    fn optional_user_lexicon_path_is_backward_compatible() {
        let config = parse_engine_config(
            r#"{"schemeId":"xiaohe","userLexiconPath":"data/user_lexicon.txt"}"#,
        )
        .unwrap();
        assert_eq!(
            config.user_lexicon_path.as_deref(),
            Some("data/user_lexicon.txt")
        );
        assert_eq!(parse_engine_config("{}").unwrap().user_lexicon_path, None);
    }

    #[test]
    fn code_table_fixture_crosses_the_existing_ffi_without_abi_change() {
        let path = code_table_bundle_path()
            .to_string_lossy()
            .replace('\\', "\\\\");
        let config = format!(
            "{{\"interfaceVersion\":7,\"schemeId\":\"code-table-fixture\",\"codeTableBundlePath\":\"{path}\",\"candidatePageSize\":5}}"
        );
        let mut handle = ptr::null_mut();
        assert_eq!(
            ffi_create(config.as_ptr(), config.len(), &mut handle),
            ImeErrorCode::Success.as_i32()
        );
        let mut out = ImeBuffer::empty();
        for key in [b'a', b'b'] {
            assert_eq!(
                ime_engine_process_key(handle, &key, 1, &mut out),
                ImeErrorCode::Success.as_i32()
            );
            let json = take_buffer(out);
            assert!(json.contains("\"rawInput\":"));
            out = ImeBuffer::empty();
        }
        assert_eq!(ffi_destroy(&mut handle), ImeErrorCode::Success.as_i32());
    }

    #[test]
    fn code_table_universal_key_crosses_the_existing_ffi() {
        let path = code_table_bundle_path()
            .to_string_lossy()
            .replace('\\', "\\\\");
        let config = format!(
            "{{\"interfaceVersion\":7,\"schemeId\":\"code-table-fixture\",\"codeTableBundlePath\":\"{path}\",\"candidatePageSize\":5}}"
        );
        let mut handle = ptr::null_mut();
        assert_eq!(
            ffi_create(config.as_ptr(), config.len(), &mut handle),
            ImeErrorCode::Success.as_i32()
        );
        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_process_key(handle, b"`".as_ptr(), 1, &mut out),
            ImeErrorCode::Success.as_i32()
        );
        let json = take_buffer(out);
        assert!(json.contains("\"success\":true"), "{json}");
        assert!(json.contains("\"rawInput\":\"`\""), "{json}");
        assert_eq!(ffi_destroy(&mut handle), ImeErrorCode::Success.as_i32());
    }

    #[test]
    fn stage1167_top_screen_serializes_commit_and_new_segment_without_abi_change() {
        let bundle = code_table_bundle_path();
        let user_path = std::env::temp_dir().join(format!(
            "stage11-6-7-ime-ffi-user-{}.txt",
            std::process::id()
        ));
        fs::write(&user_path, "用户首选\tzzzz#固\n").unwrap();
        let config = format!(
            "{{\"interfaceVersion\":7,\"schemeId\":\"code-table-fixture\",\"codeTableBundlePath\":\"{}\",\"userLexiconPath\":\"{}\",\"candidatePageSize\":5}}",
            bundle.to_string_lossy().replace('\\', "\\\\"),
            user_path.to_string_lossy().replace('\\', "\\\\")
        );
        let mut handle = ptr::null_mut();
        assert_eq!(
            ffi_create(config.as_ptr(), config.len(), &mut handle),
            ImeErrorCode::Success.as_i32()
        );
        let mut out = ImeBuffer::empty();
        for key in [b'z', b'z', b'z', b'z'] {
            assert_eq!(
                ime_engine_process_key(handle, &key, 1, &mut out),
                ImeErrorCode::Success.as_i32()
            );
            let _ = take_buffer(out);
            out = ImeBuffer::empty();
        }
        let key = b'a';
        assert_eq!(
            ime_engine_process_key(handle, &key, 1, &mut out),
            ImeErrorCode::Success.as_i32()
        );
        let json = take_buffer(out);
        assert!(json.contains("\"commitText\":\"用户首选\""), "{json}");
        assert!(json.contains("\"rawInput\":\"a\""));
        assert!(json.contains("\"action\":null"));
        assert!(json.contains("\"compositionFinished\":false"));
        assert_eq!(ffi_destroy(&mut handle), ImeErrorCode::Success.as_i32());
        let _ = fs::remove_file(user_path);
    }

    #[test]
    fn stage1167_empty_code_splits_serialize_one_commit_and_one_remaining_segment() {
        let bundle = code_table_bundle_path();
        let forward_user_path = std::env::temp_dir().join(format!(
            "stage11-6-7-ime-ffi-forward-split-{}.txt",
            std::process::id()
        ));
        fs::write(&forward_user_path, "正向切分段\tvv\n").unwrap();
        let forward_config = format!(
            "{{\"interfaceVersion\":7,\"schemeId\":\"code-table-fixture\",\"codeTableBundlePath\":\"{}\",\"userLexiconPath\":\"{}\",\"candidatePageSize\":5}}",
            bundle.to_string_lossy().replace('\\', "\\\\"),
            forward_user_path.to_string_lossy().replace('\\', "\\\\")
        );
        let mut forward_handle = ptr::null_mut();
        assert_eq!(
            ffi_create(
                forward_config.as_ptr(),
                forward_config.len(),
                &mut forward_handle
            ),
            ImeErrorCode::Success.as_i32()
        );
        let mut out = ImeBuffer::empty();
        let mut forward_json = String::new();
        let mut forward_steps = Vec::new();
        for key in [b'v', b'v', b'v', b'v'] {
            assert_eq!(
                ime_engine_process_key(forward_handle, &key, 1, &mut out),
                ImeErrorCode::Success.as_i32()
            );
            forward_json = take_buffer(out);
            forward_steps.push(forward_json.clone());
            out = ImeBuffer::empty();
        }
        assert!(
            forward_json.contains("\"commitText\":\"正向切分段\""),
            "{forward_steps:?}"
        );
        assert!(forward_json.contains("\"rawInput\":\"vv\""));
        assert!(forward_json.contains("\"action\":null"));
        assert!(forward_json.contains("\"compositionFinished\":false"));
        assert_eq!(
            ffi_destroy(&mut forward_handle),
            ImeErrorCode::Success.as_i32()
        );

        let reverse_user_path = std::env::temp_dir().join(format!(
            "stage11-6-7-ime-ffi-reverse-split-{}.txt",
            std::process::id()
        ));
        fs::write(&reverse_user_path, "反向合法后段\tvvv\n").unwrap();
        let reverse_config = format!(
            "{{\"interfaceVersion\":7,\"schemeId\":\"code-table-fixture\",\"codeTableBundlePath\":\"{}\",\"userLexiconPath\":\"{}\",\"candidatePageSize\":5}}",
            bundle.to_string_lossy().replace('\\', "\\\\"),
            reverse_user_path.to_string_lossy().replace('\\', "\\\\")
        );
        let mut reverse_handle = ptr::null_mut();
        assert_eq!(
            ffi_create(
                reverse_config.as_ptr(),
                reverse_config.len(),
                &mut reverse_handle
            ),
            ImeErrorCode::Success.as_i32()
        );
        let mut reverse_json = String::new();
        for key in [b'u', b'v', b'v', b'v'] {
            assert_eq!(
                ime_engine_process_key(reverse_handle, &key, 1, &mut out),
                ImeErrorCode::Success.as_i32()
            );
            reverse_json = take_buffer(out);
            out = ImeBuffer::empty();
        }
        assert!(
            reverse_json.contains("\"commitText\":\"u\""),
            "{reverse_json}"
        );
        assert!(reverse_json.contains("\"rawInput\":\"vvv\""));
        assert!(reverse_json.contains("\"action\":null"));
        assert!(reverse_json.contains("\"compositionFinished\":false"));
        assert_eq!(
            ffi_destroy(&mut reverse_handle),
            ImeErrorCode::Success.as_i32()
        );
        let _ = fs::remove_file(forward_user_path);
        let _ = fs::remove_file(reverse_user_path);
    }

    #[test]
    fn stage1166_single_action_crosses_ffi_and_old_interface_is_rejected() {
        let bundle = code_table_bundle_path();
        let action_path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../tests/fixtures/code-table/stage11_6_6_actions.json");
        let config = format!(
            "{{\"interfaceVersion\":7,\"schemeId\":\"code-table-fixture\",\"codeTableBundlePath\":\"{}\",\"codeTableActionFixturePath\":\"{}\",\"codeTableActionFixtureSha256\":\"05a7653e44fe72c45b1b5b0dc1dc245baaafbc1f4becd5c2ec6c657687c59b63\",\"candidatePageSize\":5}}",
            bundle.to_string_lossy().replace('\\', "\\\\"),
            action_path.to_string_lossy().replace('\\', "\\\\")
        );
        let mut handle = ptr::null_mut();
        assert_eq!(
            ffi_create(config.as_ptr(), config.len(), &mut handle),
            ImeErrorCode::Success.as_i32()
        );
        let mut out = ImeBuffer::empty();
        for key in [b';', b'd', b'i'] {
            assert_eq!(
                ime_engine_process_key(handle, &key, 1, &mut out),
                ImeErrorCode::Success.as_i32()
            );
            let _ = take_buffer(out);
        }
        assert_eq!(
            ime_engine_select_candidate(handle, 0, &mut out),
            ImeErrorCode::Success.as_i32()
        );
        let json = take_buffer(out);
        assert!(json.contains("\"commitText\":\"\""));
        assert!(json.contains("\"action\":{\"type\":\"DATE_TIME_TEXT\""));
        assert!(json.contains("\"formatId\":\"DATE_ISO\""));
        assert_eq!(ffi_destroy(&mut handle), ImeErrorCode::Success.as_i32());

        let old = br#"{"interfaceVersion":3,"schemeId":"xiaohe"}"#;
        assert_eq!(
            ffi_create(old.as_ptr(), old.len(), &mut handle),
            ImeErrorCode::AbiVersionMismatch.as_i32()
        );
    }

    #[test]
    fn formal_bundle_crosses_ffi_with_strict_identity_and_explicit_fallback() {
        let formal = formal_bundle_path().to_string_lossy().replace('\\', "\\\\");
        let config = format!(
            "{{\"interfaceVersion\":7,\"schemeId\":\"xiaohe-yinxing\",\"codeTableBundlePath\":\"{formal}\",\"candidatePageSize\":5}}"
        );
        let mut handle = ptr::null_mut();
        assert_eq!(
            ffi_create(config.as_ptr(), config.len(), &mut handle),
            ImeErrorCode::Success.as_i32()
        );
        let mut latest = String::new();
        for key in b"aaba" {
            let mut out = ImeBuffer::empty();
            assert_eq!(
                ime_engine_process_key(handle, key, 1, &mut out),
                ImeErrorCode::Success.as_i32()
            );
            latest = take_buffer(out);
        }
        assert!(latest.contains("\"rawInput\":\"\""));
        assert!(latest.contains("\"commitText\":\"阿爸\""));
        assert!(latest.contains("\"compositionFinished\":true"));
        assert_eq!(ffi_destroy(&mut handle), ImeErrorCode::Success.as_i32());

        let fixture = code_table_bundle_path()
            .to_string_lossy()
            .replace('\\', "\\\\");
        let wrong_pair = format!(
            "{{\"interfaceVersion\":7,\"schemeId\":\"xiaohe-yinxing\",\"codeTableBundlePath\":\"{fixture}\"}}"
        );
        assert_eq!(
            ffi_create(wrong_pair.as_ptr(), wrong_pair.len(), &mut handle),
            ImeErrorCode::LexiconLoadFailed.as_i32()
        );
        assert!(handle.is_null());

        let missing_formal = br#"{"interfaceVersion":7,"schemeId":"xiaohe-yinxing","codeTableBundlePath":"missing-formal.hsyx"}"#;
        assert_eq!(
            ffi_create(missing_formal.as_ptr(), missing_formal.len(), &mut handle),
            ImeErrorCode::LexiconNotFound.as_i32()
        );
        assert!(handle.is_null());

        let explicit_xiaohe = br#"{"interfaceVersion":7,"schemeId":"xiaohe","codeTableBundlePath":"missing-formal.hsyx"}"#;
        assert_eq!(
            ffi_create(explicit_xiaohe.as_ptr(), explicit_xiaohe.len(), &mut handle),
            ImeErrorCode::Success.as_i32()
        );
        assert_eq!(ffi_destroy(&mut handle), ImeErrorCode::Success.as_i32());
        assert_eq!(ime_engine_get_abi_version(), ABI_VERSION_DIRECT_ACTIONS);
    }

    #[test]
    fn production_direct_actions_cross_ffi_as_closed_protocol_actions() {
        let formal = formal_bundle_path().to_string_lossy().replace('\\', "\\\\");
        let config = format!(
            "{{\"interfaceVersion\":10,\"schemeId\":\"xiaohe-yinxing\",\"codeTableBundlePath\":\"{formal}\",\"candidatePageSize\":5}}"
        );
        let mut handle = ptr::null_mut();
        assert_eq!(
            ffi_create(config.as_ptr(), config.len(), &mut handle),
            ImeErrorCode::Success.as_i32()
        );

        for (code, expected_action) in [
            (b'f', "REPEAT_COMMIT"),
            (b'i', "UNDO_COMMIT"),
            (b'j', "INSERT_PAIR"),
            (b'n', "MOVE_LINE_END"),
        ] {
            let mut out = ImeBuffer::empty();
            for key in [b';', code] {
                assert_eq!(
                    ime_engine_process_key(handle, &key, 1, &mut out),
                    ImeErrorCode::Success.as_i32()
                );
                let _ = take_buffer(out);
                out = ImeBuffer::empty();
            }
            assert_eq!(
                ime_engine_select_candidate(handle, 0, &mut out),
                ImeErrorCode::Success.as_i32()
            );
            let json = take_buffer(out);
            assert!(
                json.contains(&format!("\"type\":\"{expected_action}\"")),
                "unexpected action for ;{}: {json}",
                code as char
            );
        }

        let mut out = ImeBuffer::empty();
        for key in b"oba" {
            assert_eq!(
                ime_engine_process_key(handle, key, 1, &mut out),
                ImeErrorCode::Success.as_i32()
            );
            let _ = take_buffer(out);
            out = ImeBuffer::empty();
        }
        assert_eq!(
            ime_engine_select_candidate(handle, 0, &mut out),
            ImeErrorCode::Success.as_i32()
        );
        let display_commit = take_buffer(out);
        assert!(display_commit.contains("\"commitText\":\"一\""));

        out = ImeBuffer::empty();
        for key in b"ojj" {
            assert_eq!(
                ime_engine_process_key(handle, key, 1, &mut out),
                ImeErrorCode::Success.as_i32()
            );
            let _ = take_buffer(out);
            out = ImeBuffer::empty();
        }
        assert_eq!(
            ime_engine_select_candidate(handle, 0, &mut out),
            ImeErrorCode::Success.as_i32()
        );
        let category_action = take_buffer(out);
        assert!(category_action.contains("\"type\":\"DIRECT_CONTROL\""));
        assert!(category_action.contains("\"formatId\":\"category.preset\""));
        assert!(category_action.contains("\"text\":\"experienced\""));

        assert_eq!(ffi_destroy(&mut handle), ImeErrorCode::Success.as_i32());
    }

    #[test]
    fn formal_precise_ffi_keeps_exact_short_codes_small_for_large_pages() {
        let formal = formal_bundle_path().to_string_lossy().replace('\\', "\\\\");
        for page_size in [50usize, 9] {
            let config = format!(
                "{{\"interfaceVersion\":7,\"schemeId\":\"xiaohe-yinxing\",\"codeTableBundlePath\":\"{formal}\",\"candidatePageSize\":{page_size}}}"
            );
            let mut handle = ptr::null_mut();
            assert_eq!(
                ffi_create(config.as_ptr(), config.len(), &mut handle),
                ImeErrorCode::Success.as_i32()
            );
            let mut out = ImeBuffer::empty();
            assert_eq!(
                ime_engine_process_key(handle, b"h".as_ptr(), 1, &mut out),
                ImeErrorCode::Success.as_i32()
            );
            let json = take_buffer(out);
            assert_eq!(json.matches("\"id\":").count(), 2);
            assert!(json.contains("\"hasNextPage\":false"));
            assert_eq!(ffi_destroy(&mut handle), ImeErrorCode::Success.as_i32());
        }
    }

    #[test]
    fn formal_embedded_and_external_layers_cross_ffi_v4() {
        let formal_path = formal_bundle_path();
        let bundle = CodeTableBundle::load_frozen_production_file(&formal_path).unwrap();
        let rule = bundle
            .user_rules
            .as_ref()
            .expect("embedded rules")
            .entries()
            .first()
            .expect("embedded rule");
        let formal = formal_path.to_string_lossy().replace('\\', "\\\\");

        let mut handle = ptr::null_mut();
        let built_in_config = format!(
            "{{\"interfaceVersion\":7,\"schemeId\":\"xiaohe-yinxing\",\"codeTableBundlePath\":\"{formal}\",\"candidatePageSize\":5}}"
        );
        assert_eq!(
            ffi_create(built_in_config.as_ptr(), built_in_config.len(), &mut handle),
            ImeErrorCode::Success.as_i32()
        );
        let enabled_categories = br#"["core","full-code-word"]"#;
        let mut category_out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_set_code_table_categories(
                handle,
                enabled_categories.as_ptr(),
                enabled_categories.len(),
                &mut category_out,
            ),
            ImeErrorCode::Success.as_i32()
        );
        let _ = take_buffer(category_out);
        let mut built_in_json = String::new();
        for key in rule.code.as_bytes() {
            let mut out = ImeBuffer::empty();
            assert_eq!(
                ime_engine_process_key(handle, key, 1, &mut out),
                ImeErrorCode::Success.as_i32()
            );
            built_in_json = take_buffer(out);
        }
        assert!(built_in_json.contains(&format!("\"text\":\"{}\"", rule.text)));
        assert_eq!(ffi_destroy(&mut handle), ImeErrorCode::Success.as_i32());

        let user_path = std::env::temp_dir().join(format!(
            "stage11-6-4-formal-ime-ffi-delete-{}.txt",
            std::process::id()
        ));
        fs::write(&user_path, format!("{}\t{}#删\n", rule.text, rule.code)).unwrap();
        let user = user_path.to_string_lossy().replace('\\', "\\\\");
        let external_config = format!(
            "{{\"interfaceVersion\":7,\"schemeId\":\"xiaohe-yinxing\",\"codeTableBundlePath\":\"{formal}\",\"userLexiconPath\":\"{user}\",\"candidatePageSize\":5}}"
        );
        assert_eq!(
            ffi_create(external_config.as_ptr(), external_config.len(), &mut handle),
            ImeErrorCode::Success.as_i32()
        );
        let mut category_out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_set_code_table_categories(
                handle,
                enabled_categories.as_ptr(),
                enabled_categories.len(),
                &mut category_out,
            ),
            ImeErrorCode::Success.as_i32()
        );
        let _ = take_buffer(category_out);
        let mut external_json = String::new();
        for key in rule.code.as_bytes() {
            let mut out = ImeBuffer::empty();
            assert_eq!(
                ime_engine_process_key(handle, key, 1, &mut out),
                ImeErrorCode::Success.as_i32()
            );
            external_json = take_buffer(out);
        }
        assert!(!external_json.contains(&format!("\"text\":\"{}\"", rule.text)));
        assert_eq!(ime_engine_get_abi_version(), ABI_VERSION_DIRECT_ACTIONS);
        assert_eq!(ffi_destroy(&mut handle), ImeErrorCode::Success.as_i32());
    }

    #[test]
    fn code_table_user_overlay_crosses_v4_result_json() {
        let bundle = code_table_bundle_path()
            .to_string_lossy()
            .replace('\\', "\\\\");
        let user_path = std::env::temp_dir().join(format!(
            "stage11-6-4-ime-ffi-user-{}.txt",
            std::process::id()
        ));
        fs::write(&user_path, "固顶词\tab#固\n位置词\tab#2\n").unwrap();
        let user = user_path.to_string_lossy().replace('\\', "\\\\");
        let config = format!(
            "{{\"interfaceVersion\":7,\"schemeId\":\"code-table-fixture\",\"codeTableBundlePath\":\"{bundle}\",\"userLexiconPath\":\"{user}\",\"candidatePageSize\":5}}"
        );
        let mut handle = ptr::null_mut();
        assert_eq!(
            ffi_create(config.as_ptr(), config.len(), &mut handle),
            ImeErrorCode::Success.as_i32()
        );
        let mut out = ImeBuffer::empty();
        for key in [b'a', b'b'] {
            assert_eq!(
                ime_engine_process_key(handle, &key, 1, &mut out),
                ImeErrorCode::Success.as_i32()
            );
            if key == b'a' {
                let _ = take_buffer(out);
                out = ImeBuffer::empty();
            }
        }
        let json = take_buffer(out);
        let fixed = json.find("\"text\":\"固顶词\"").unwrap();
        let positioned = json.find("\"text\":\"位置词\"").unwrap();
        assert!(fixed < positioned);
        assert!(json.contains("\"source\":\"user-lexicon\""));
        assert_eq!(ime_engine_get_abi_version(), ABI_VERSION_DIRECT_ACTIONS);
        assert_eq!(ffi_destroy(&mut handle), ImeErrorCode::Success.as_i32());
    }

    #[test]
    fn null_outputs_and_handles_are_safe() {
        assert_eq!(
            ime_engine_get_version(ptr::null_mut()),
            ImeErrorCode::BufferAllocationFailed.as_i32()
        );
        assert_eq!(
            ffi_create(ptr::null(), 0, ptr::null_mut()),
            ImeErrorCode::InvalidArgument.as_i32()
        );

        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_process_key(ptr::null_mut(), b"n".as_ptr(), 1, &mut out),
            ImeErrorCode::InvalidHandle.as_i32()
        );
        assert!(out.data.is_null());
        assert_eq!(out.len, 0);
    }

    #[test]
    fn process_key_validates_utf8_and_key_shape() {
        let mut handle = create_engine_with_lexicon(5);
        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_process_key(handle, [0xff].as_ptr(), 1, &mut out),
            ImeErrorCode::InvalidUtf8.as_i32()
        );
        assert_eq!(
            ime_engine_process_key(handle, [0xff, 0xff].as_ptr(), 2, &mut out),
            ImeErrorCode::InvalidUtf8.as_i32()
        );
        assert_eq!(
            ime_engine_process_key(handle, b"".as_ptr(), 0, &mut out),
            ImeErrorCode::InvalidArgument.as_i32()
        );
        assert_eq!(
            ime_engine_process_key(handle, b"ab".as_ptr(), 2, &mut out),
            ImeErrorCode::InvalidArgument.as_i32()
        );
        assert_eq!(
            ime_engine_process_key(handle, b"1".as_ptr(), 1, &mut out),
            ImeErrorCode::InvalidArgument.as_i32()
        );
        assert_eq!(
            ime_engine_process_key(handle, b"!".as_ptr(), 1, &mut out),
            ImeErrorCode::InvalidArgument.as_i32()
        );
        assert_eq!(ffi_destroy(&mut handle), ImeErrorCode::Success.as_i32());
    }

    #[test]
    fn process_backspace_reset_and_change_scheme_return_json() {
        let mut handle = create_engine_with_lexicon(5);
        let mut out = ImeBuffer::empty();

        assert_eq!(
            ime_engine_process_key(handle, b"n".as_ptr(), 1, &mut out),
            ImeErrorCode::Success.as_i32()
        );
        let first = take_buffer(out);
        assert!(first.contains("\"parserState\":\"incomplete\""));
        assert!(first.contains("\"pendingCode\":\"n\""));

        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_process_key(handle, b"i".as_ptr(), 1, &mut out),
            ImeErrorCode::Success.as_i32()
        );
        let second = take_buffer(out);
        assert!(second.contains("\"parserState\":\"complete\""));
        assert!(second.contains("\"parsedSyllables\":[\"ni\"]"));
        assert!(second.contains("\"text\":\"你\""));

        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_backspace(handle, &mut out),
            ImeErrorCode::Success.as_i32()
        );
        assert!(take_buffer(out).contains("\"rawInput\":\"n\""));

        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_reset(handle, &mut out),
            ImeErrorCode::Success.as_i32()
        );
        assert!(take_buffer(out).contains("\"parserState\":\"empty\""));

        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_change_scheme(handle, b"xiaohe".as_ptr(), 6, &mut out),
            ImeErrorCode::Success.as_i32()
        );
        assert!(take_buffer(out).contains("\"success\":true"));

        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_change_scheme(handle, b"missing".as_ptr(), 7, &mut out),
            ImeErrorCode::InvalidScheme.as_i32()
        );
        assert!(out.data.is_null());
        assert_eq!(ffi_destroy(&mut handle), ImeErrorCode::Success.as_i32());
    }

    #[test]
    fn segment_boundary_crosses_ffi_and_rejects_invalid_repetition() {
        let mut handle = create_engine_with_lexicon(5);
        let mut out = ImeBuffer::empty();
        for key in [b'n', b'i'] {
            assert_eq!(
                ime_engine_process_key(handle, &key, 1, &mut out),
                ImeErrorCode::Success.as_i32()
            );
            let _ = take_buffer(out);
            out = ImeBuffer::empty();
        }

        assert_eq!(
            ime_engine_insert_segment_boundary(handle, &mut out),
            ImeErrorCode::Success.as_i32()
        );
        let segmented = take_buffer(out);
        assert!(segmented.contains("\"rawInput\":\"ni'\""));
        assert!(segmented.contains("\"segmentBoundaries\":[2]"));
        assert!(!segmented.contains("\"commitText\":\"'\""));

        let mut invalid_out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_insert_segment_boundary(handle, &mut invalid_out),
            ImeErrorCode::InvalidArgument.as_i32()
        );
        assert!(invalid_out.data.is_null());
        assert_eq!(invalid_out.len, 0);
        assert_eq!(ffi_destroy(&mut handle), ImeErrorCode::Success.as_i32());
    }

    #[test]
    fn semantic_invalid_code_is_not_native_failure() {
        let mut handle = create_engine_with_lexicon(5);
        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_process_key(handle, b"q".as_ptr(), 1, &mut out),
            ImeErrorCode::Success.as_i32()
        );
        let _ = take_buffer(out);

        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_process_key(handle, b"g".as_ptr(), 1, &mut out),
            ImeErrorCode::Success.as_i32()
        );
        let json = take_buffer(out);
        assert!(json.contains("\"success\":true"));
        assert!(json.contains("\"parserState\":\"invalid\""));
        assert_eq!(ffi_destroy(&mut handle), ImeErrorCode::Success.as_i32());
    }

    #[test]
    fn select_candidate_and_pages_return_json() {
        let mut handle = create_engine_with_lexicon(1);
        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_process_key(handle, b"n".as_ptr(), 1, &mut out),
            ImeErrorCode::Success.as_i32()
        );
        let json = take_buffer(out);
        assert!(json.contains("\"hasNextPage\":true"));

        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_next_candidate_page(handle, &mut out),
            ImeErrorCode::Success.as_i32()
        );
        let json = take_buffer(out);
        assert!(json.contains("\"candidatePage\":1"));
        assert!(json.contains("\"hasPreviousPage\":true"));

        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_previous_candidate_page(handle, &mut out),
            ImeErrorCode::Success.as_i32()
        );
        assert!(take_buffer(out).contains("\"candidatePage\":0"));

        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_select_candidate(handle, 0, &mut out),
            ImeErrorCode::Success.as_i32()
        );
        let json = take_buffer(out);
        assert!(json.contains("\"commitText\":\"你\""));
        assert!(json.contains("\"compositionFinished\":true"));
        assert_eq!(ffi_destroy(&mut handle), ImeErrorCode::Success.as_i32());
    }

    #[test]
    fn invalid_page_and_candidate_index_return_errors() {
        let mut handle = create_engine_with_lexicon(5);
        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_next_candidate_page(handle, &mut out),
            ImeErrorCode::InvalidPage.as_i32()
        );
        assert!(out.data.is_null());

        assert_eq!(
            ime_engine_process_key(handle, b"n".as_ptr(), 1, &mut out),
            ImeErrorCode::Success.as_i32()
        );
        let _ = take_buffer(out);
        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_select_candidate(handle, 99, &mut out),
            ImeErrorCode::InvalidCandidate.as_i32()
        );
        assert!(out.data.is_null());
        assert_eq!(ffi_destroy(&mut handle), ImeErrorCode::Success.as_i32());
    }

    #[test]
    fn stage8_sentence_candidates_and_partial_commit_cross_ffi() {
        let mut handle = create_engine_with_stage8_lexicon(5);
        let mut latest = String::new();
        for key in ["u", "u", "r", "u", "f", "a"] {
            let mut out = ImeBuffer::empty();
            assert_eq!(
                ime_engine_process_key(handle, key.as_ptr(), key.len(), &mut out),
                ImeErrorCode::Success.as_i32()
            );
            latest = take_buffer(out);
        }

        assert!(latest.contains("\"text\":\"输入法\""));
        assert!(latest.contains("\"text\":\"输入\""));

        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_select_candidate(handle, 1, &mut out),
            ImeErrorCode::Success.as_i32()
        );
        let json = take_buffer(out);
        assert!(json.contains("\"commitText\":\"输入\""));
        assert!(json.contains("\"rawInput\":\"fa\""));
        assert!(json.contains("\"compositionFinished\":false"));
        assert!(json.contains("\"text\":\"法\""));
        assert_eq!(ffi_destroy(&mut handle), ImeErrorCode::Success.as_i32());
    }

    #[test]
    fn stage9_user_model_status_and_policy_cross_ffi() {
        let mut handle = create_engine_with_lexicon(5);
        let path = temp_user_model_path("status");
        let path_text = path.to_string_lossy();
        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_set_user_model_path(handle, path_text.as_ptr(), path_text.len(), &mut out),
            ImeErrorCode::Success.as_i32()
        );
        assert!(take_buffer(out).contains("\"recordCount\":0"));

        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_load_user_model(handle, &mut out),
            ImeErrorCode::Success.as_i32()
        );
        assert!(take_buffer(out).contains("\"loaded\":true"));

        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_set_user_learning_enabled(handle, false, &mut out),
            ImeErrorCode::Success.as_i32()
        );
        assert!(take_buffer(out).contains("\"enabled\":false"));

        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_set_session_learning_allowed(handle, false, &mut out),
            ImeErrorCode::Success.as_i32()
        );
        assert!(take_buffer(out).contains("\"sessionLearningAllowed\":false"));

        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_flush_user_model(handle, &mut out),
            ImeErrorCode::Success.as_i32()
        );
        assert!(take_buffer(out).contains("\"dirty\":false"));

        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_clear_user_model(handle, &mut out),
            ImeErrorCode::Success.as_i32()
        );
        assert!(take_buffer(out).contains("\"recordCount\":0"));
        assert_eq!(ffi_destroy(&mut handle), ImeErrorCode::Success.as_i32());
    }

    #[test]
    fn stage9_user_model_ffi_validates_handles_and_paths() {
        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_load_user_model(ptr::null_mut(), &mut out),
            ImeErrorCode::InvalidHandle.as_i32()
        );
        assert!(out.data.is_null());

        let mut handle = create_default_engine();
        assert_eq!(
            ime_engine_set_user_model_path(handle, ptr::null(), 4, &mut out),
            ImeErrorCode::InvalidArgument.as_i32()
        );
        assert!(out.data.is_null());
        assert_eq!(
            ime_engine_set_user_model_path(handle, b"".as_ptr(), 0, &mut out),
            ImeErrorCode::InvalidArgument.as_i32()
        );
        assert_eq!(ffi_destroy(&mut handle), ImeErrorCode::Success.as_i32());
    }

    #[test]
    fn stage1165_category_ffi_reads_updates_normalizes_and_rejects_atomically() {
        let formal = formal_bundle_path();
        let config = format!(
            "{{\"interfaceVersion\":7,\"schemeId\":\"xiaohe-yinxing\",\"codeTableBundlePath\":\"{}\",\"candidatePageSize\":5}}",
            formal.to_string_lossy().replace('\\', "\\\\")
        );
        let mut handle = ptr::null_mut();
        assert_eq!(
            ffi_create(config.as_ptr(), config.len(), &mut handle),
            ImeErrorCode::Success.as_i32()
        );

        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_get_code_table_category_config(handle, &mut out),
            ImeErrorCode::Success.as_i32()
        );
        let defaults = take_buffer(out);
        assert!(defaults.contains("\"schemaVersion\":1"));
        assert!(defaults.contains("\"displayName\":\"首选\""));
        assert!(defaults.contains("\"kind\":\"PRIMARY\""));
        assert!(defaults.contains("\"enabledCategoryIds\":[\"core\",\"category-secondary\""));

        let input = br#"["full-code-word","core","full-code-word"]"#;
        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_set_code_table_categories(handle, input.as_ptr(), input.len(), &mut out),
            ImeErrorCode::Success.as_i32()
        );
        let changed = take_buffer(out);
        assert!(changed.contains("\"commitText\":\"\""));
        assert!(changed.contains("\"candidatePage\":0"));

        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_get_code_table_category_config(handle, &mut out),
            ImeErrorCode::Success.as_i32()
        );
        assert!(take_buffer(out).contains("\"enabledCategoryIds\":[\"core\",\"full-code-word\"]"));

        let unknown = br#"["unknown"]"#;
        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_set_code_table_categories(handle, unknown.as_ptr(), unknown.len(), &mut out),
            ImeErrorCode::Success.as_i32()
        );
        let rejected = take_buffer(out);
        assert!(rejected.contains("\"success\":false"));
        assert!(rejected.contains("\"errorCode\":1001"));

        let mut xiaohe = create_default_engine();
        assert_eq!(
            ime_engine_get_code_table_category_config(xiaohe, &mut out),
            ImeErrorCode::UnsupportedOperation.as_i32()
        );
        assert_eq!(ffi_destroy(&mut xiaohe), ImeErrorCode::Success.as_i32());
        assert_eq!(ffi_destroy(&mut handle), ImeErrorCode::Success.as_i32());
    }

    #[test]
    fn buffer_free_is_idempotent_after_clearing() {
        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_get_version(&mut out),
            ImeErrorCode::Success.as_i32()
        );
        assert!(!out.data.is_null());
        assert_eq!(ffi_free_buffer(&mut out), ImeErrorCode::Success.as_i32());
        assert!(out.data.is_null());
        assert_eq!(out.len, 0);
        assert_eq!(ffi_free_buffer(&mut out), ImeErrorCode::Success.as_i32());
        assert_eq!(
            ffi_free_buffer(ptr::null_mut()),
            ImeErrorCode::Success.as_i32()
        );
    }

    #[test]
    fn fixed_candidate_regression_interface_still_works() {
        let input = CString::new("test").unwrap();
        let mut out = ImeBuffer::empty();
        let code = ime_engine_get_test_candidates(input.as_ptr(), &mut out);
        assert_eq!(code, ImeErrorCode::Success.as_i32());
        let json = take_buffer(out);
        assert!(json.contains("\"rawInput\":\"test\""));
        assert!(json.contains("\"text\":\"测试\""));
        assert!(json.contains("\"engineVersion\":\"0.0.1-stage0\""));
    }

    #[test]
    fn panic_is_captured_without_crossing_ffi() {
        let mut out = ImeBuffer::empty();
        let code = ime_engine_stage5_test_panic(&mut out);
        assert_eq!(code, ImeErrorCode::EngineInternalError.as_i32());
        assert!(out.data.is_null());
        assert_eq!(out.len, 0);
    }

    #[test]
    fn user_lexicon_management_and_runtime_reload_cross_ffi() {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!("stage12-ime-ffi-user-{nanos}.txt"));
        let path_text = path.to_string_lossy().to_string();

        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_user_lexicon_load(path_text.as_ptr(), path_text.len(), &mut out),
            ImeErrorCode::Success.as_i32()
        );
        let initial = take_buffer(out);
        assert!(initial.contains("\"success\":true"));
        let initial_revision = extract_json_string(&initial, "revision").unwrap().unwrap();

        let first = "直通词\tzzzz#固\n";
        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_user_lexicon_save(
                path_text.as_ptr(),
                path_text.len(),
                initial_revision.as_ptr(),
                initial_revision.len(),
                first.as_ptr(),
                first.len(),
                &mut out,
            ),
            ImeErrorCode::Success.as_i32()
        );
        let saved = take_buffer(out);
        assert!(saved.contains("\"action\":\"FIXED\""));
        let saved_revision = extract_json_string(&saved, "revision").unwrap().unwrap();

        let bundle = code_table_bundle_path()
            .to_string_lossy()
            .replace('\\', "\\\\");
        let escaped_user = path_text.replace('\\', "\\\\");
        let config = format!(
            "{{\"interfaceVersion\":7,\"schemeId\":\"code-table-fixture\",\"codeTableBundlePath\":\"{bundle}\",\"userLexiconPath\":\"{escaped_user}\"}}"
        );
        let mut handle = ptr::null_mut();
        assert_eq!(
            ffi_create(config.as_ptr(), config.len(), &mut handle),
            ImeErrorCode::Success.as_i32()
        );

        let second = "热载词\tzzzz#1\n";
        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_user_lexicon_save(
                path_text.as_ptr(),
                path_text.len(),
                saved_revision.as_ptr(),
                saved_revision.len(),
                second.as_ptr(),
                second.len(),
                &mut out,
            ),
            ImeErrorCode::Success.as_i32()
        );
        let re_saved = take_buffer(out);
        assert!(re_saved.contains("\"action\":\"POSITION\""));

        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_reload_user_lexicon(handle, &mut out),
            ImeErrorCode::Success.as_i32()
        );
        let reloaded = take_buffer(out);
        assert!(reloaded.contains("\"success\":true"));
        for key in [b'z', b'z', b'z', b'z'] {
            let mut out = ImeBuffer::empty();
            assert_eq!(
                ime_engine_process_key(handle, &key, 1, &mut out),
                ImeErrorCode::Success.as_i32()
            );
            let json = take_buffer(out);
            if key == b'z' && json.contains("\"rawInput\":\"zzzz\"") {
                assert!(json.contains("\"text\":\"热载词\""));
                assert!(!json.contains("\"text\":\"直通词\""));
            }
        }

        let stale = "冲突词\taaaa\n";
        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_user_lexicon_save(
                path_text.as_ptr(),
                path_text.len(),
                initial_revision.as_ptr(),
                initial_revision.len(),
                stale.as_ptr(),
                stale.len(),
                &mut out,
            ),
            ImeErrorCode::Success.as_i32()
        );
        assert!(take_buffer(out).contains("\"errorCode\":\"revision_conflict\""));

        assert_eq!(ffi_destroy(&mut handle), ImeErrorCode::Success.as_i32());
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(path.with_extension("txt.bak"));
    }

    #[test]
    fn pinyin9_digits_and_combination_selection_cross_the_c_abi() {
        let path = create_test_lexicon();
        let config = format!(
            "{{\"interfaceVersion\":7,\"schemeId\":\"pinyin-9\",\"lexiconPath\":\"{}\",\"candidatePageSize\":20}}",
            path.to_string_lossy().replace('\\', "\\\\")
        );
        let mut handle = ptr::null_mut();
        assert_eq!(
            ffi_create(config.as_ptr(), config.len(), &mut handle),
            ImeErrorCode::Success.as_i32()
        );

        let mut last = String::new();
        for digit in b"64426" {
            let mut out = ImeBuffer::empty();
            assert_eq!(
                ime_engine_process_key(handle, digit, 1, &mut out),
                ImeErrorCode::Success.as_i32()
            );
            last = take_buffer(out);
        }
        assert!(last.contains("\"rawInput\":\"64426\""));
        assert!(last.contains("ni'hao"));
        assert!(last.contains("\"text\":\"你好\""));

        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_reset(handle, &mut out),
            ImeErrorCode::Success.as_i32()
        );
        let _ = take_buffer(out);
        for digit in b"64" {
            let mut out = ImeBuffer::empty();
            assert_eq!(
                ime_engine_process_key(handle, digit, 1, &mut out),
                ImeErrorCode::Success.as_i32()
            );
            last = take_buffer(out);
        }
        assert!(last.contains("\"rawInput\":\"64\""));
        assert!(last.contains("\"currentPinyin\":\"ni\""));
        assert!(last.contains("\"text\":\"你\""));

        let mut out = ImeBuffer::empty();
        assert_eq!(
            ime_engine_select_pinyin_combination(handle, 0, &mut out),
            ImeErrorCode::Success.as_i32()
        );
        let selected = take_buffer(out);
        assert!(selected.contains("\"currentPinyin\":\"ni\""));
        assert!(selected.contains("\"text\":\"你\""));

        assert_eq!(ffi_destroy(&mut handle), ImeErrorCode::Success.as_i32());
        let _ = fs::remove_file(path);
    }

    #[test]
    fn stress_create_destroy_and_repeated_operations() {
        for _ in 0..1000 {
            let mut handle = create_default_engine();
            assert_eq!(ffi_destroy(&mut handle), ImeErrorCode::Success.as_i32());
            assert!(handle.is_null());
        }

        let mut handle = create_engine_with_lexicon(5);
        for index in 0..10_000 {
            let key = if index % 2 == 0 { b"n" } else { b"i" };
            let mut out = ImeBuffer::empty();
            assert_eq!(
                ime_engine_process_key(handle, key.as_ptr(), 1, &mut out),
                ImeErrorCode::Success.as_i32()
            );
            let _ = take_buffer(out);
            if index % 4 == 3 {
                let mut out = ImeBuffer::empty();
                assert_eq!(
                    ime_engine_backspace(handle, &mut out),
                    ImeErrorCode::Success.as_i32()
                );
                let _ = take_buffer(out);
            }
        }
        for _ in 0..1000 {
            let mut out = ImeBuffer::empty();
            assert_eq!(
                ime_engine_reset(handle, &mut out),
                ImeErrorCode::Success.as_i32()
            );
            let json = take_buffer(out);
            assert!(json.contains(ProtocolParserState::Empty.as_str()));
        }
        for _ in 0..128 {
            let mut out = ImeBuffer::empty();
            assert_eq!(
                ime_engine_change_scheme(handle, b"xiaohe".as_ptr(), 6, &mut out),
                ImeErrorCode::Success.as_i32()
            );
            let _ = take_buffer(out);

            let mut out = ImeBuffer::empty();
            assert_eq!(
                ime_engine_change_scheme(handle, b"missing".as_ptr(), 7, &mut out),
                ImeErrorCode::InvalidScheme.as_i32()
            );
            assert!(out.data.is_null());
        }
        assert_eq!(ffi_destroy(&mut handle), ImeErrorCode::Success.as_i32());
    }
}
