use std::fs;
use std::path::PathBuf;
use std::sync::OnceLock;

use code_table_fixture_generator::{build_bundle, generate_fixture};
use code_table_runtime::{query_exact_or_prefix, CodeTableBundle};
use engine_protocol::ProtocolAction;
use ime_engine::{EngineConfig, ImeEngine};
use user_lexicon::{parse_user_lexicon_bytes, save_snapshot_atomic, UserLexiconAction};

const ALL_CATEGORY_IDS: [&str; 12] = [
    "core",
    "category-secondary",
    "quick-symbol",
    "one-key-secondary",
    "two-key-secondary",
    "out-of-table-character",
    "full-code-word",
    "symbol",
    "symbol-group",
    "rare-character",
    "full-code-character",
    "ok-spelling",
];

#[test]
fn display_feedback_direct_commands_keep_customer_order_and_do_not_commit_labels() {
    let mut engine =
        ImeEngine::new(config("xiaohe-yinxing", Some(formal_bundle()), None, 9)).unwrap();
    type DirectCommandCase<'a> = (&'a str, &'a str, &'a [(&'a str, &'a str)]);
    let commands: &[DirectCommandCase<'_>] = &[
        (
            "ohx",
            "settings.candidate-position",
            &[("[固定]", "bar"), ("[浮动]", "floating")],
        ),
        (
            "ojg",
            "settings.keyboard-height",
            &[
                ("[键高1.0]", "default"),
                ("[+0.05]", "increase"),
                ("[-0.05]", "decrease"),
            ],
        ),
        (
            "ojz",
            "settings.keyboard-font",
            &[
                ("[键字12号]", "default"),
                ("[+2]", "increase"),
                ("[-1]", "decrease"),
            ],
        ),
        (
            "ohz",
            "settings.candidate-font",
            &[
                ("[候字15号]", "default"),
                ("[+2]", "increase"),
                ("[-1]", "decrease"),
            ],
        ),
        (
            "ofz",
            "settings.floating-font",
            &[
                ("[浮字17号]", "default"),
                ("[+2]", "increase"),
                ("[-1]", "decrease"),
            ],
        ),
        (
            "ofa",
            "settings.keyboard-profile",
            &[
                ("[音形]", "xiaohe-yinxing-26"),
                ("[双拼]", "xiaohe-26"),
                ("[全拼]", "quanpin-26"),
            ],
        ),
        (
            "ovd",
            "settings.haptic",
            &[("[震动_开]", "enabled"), ("[关]", "disabled")],
        ),
        (
            "oyx",
            "settings.key-sound",
            &[("[音效_开]", "enabled"), ("[关]", "disabled")],
        ),
    ];
    for &(code, action, options) in commands {
        for (index, &(label, target)) in options.iter().enumerate() {
            engine.reset();
            let state = enter(&mut engine, code);
            assert!(state.commit_text.is_empty(), "{code}");
            assert_eq!(state.candidates[index].text, label, "{code}/{index}");
            assert_eq!(state.candidates[index].source, "functional");
            let selected = engine.select_candidate(index).unwrap();
            assert!(selected.commit_text.is_empty(), "{code}/{index}");
            assert_eq!(
                selected.action,
                Some(ProtocolAction::DirectControl {
                    action: action.to_owned(),
                    target: target.to_owned(),
                })
            );
            assert!(engine.current_state().raw_input.is_empty());
        }
    }
}

#[test]
fn oix_returns_a_shape_lookup_action_only_after_selection() {
    let mut engine = ImeEngine::new(config("xiaohe-yinxing", Some(formal_bundle()), None, 9)).unwrap();
    let state = enter(&mut engine, "oix");
    assert!(state.commit_text.is_empty());
    assert!(state.action.is_none());
    assert!(!state.candidates.is_empty());
    assert_eq!(state.candidates[0].text, "「查」：{last_0}");
    assert_eq!(state.candidates[0].source, "functional");
    let selected = engine.select_candidate(0).unwrap();
    assert!(selected.commit_text.is_empty());
    assert_eq!(selected.action, Some(ProtocolAction::DirectControl {
        action: "url.open".to_owned(), target: "flypy-shape".to_owned(),
    }));
    assert!(engine.current_state().raw_input.is_empty());
}

#[test]
fn ofa_is_available_in_both_phonetic_schemes_with_paging() {
    for scheme in ["xiaohe", "quanpin"] {
        for page_size in [1, 2, 5, 9] {
            for (selection, target) in ["xiaohe-yinxing-26", "xiaohe-26", "quanpin-26"]
                .iter()
                .enumerate()
            {
                let mut engine = ImeEngine::new(config(scheme, None, None, page_size)).unwrap();
                let first = enter(&mut engine, "ofa");
                assert_eq!(first.candidates[0].text, "[音形]");
                assert_eq!(first.candidates.len(), page_size.min(3));
                assert_eq!(engine.current_state(), first);
                assert!(engine.select_candidate(first.candidates.len()).is_err());
                for _ in 0..selection / page_size {
                    engine.next_candidate_page().unwrap();
                }
                let selected = engine.select_candidate(selection % page_size).unwrap();
                assert!(selected.commit_text.is_empty());
                assert_eq!(
                    selected.action,
                    Some(ProtocolAction::DirectControl {
                        action: "settings.keyboard-profile".to_owned(),
                        target: (*target).to_owned()
                    })
                );
                assert!(engine.current_state().raw_input.is_empty());
                enter(&mut engine, "ofa");
                let shorter = engine.backspace();
                assert_eq!(shorter.raw_input, "of");
                assert!(shorter
                    .candidates
                    .iter()
                    .all(|candidate| candidate.source != "functional"));
                engine.reset();
                let normal = enter(&mut engine, "ni");
                assert!(!normal.candidates.is_empty());
                assert!(normal
                    .candidates
                    .iter()
                    .all(|candidate| candidate.source != "functional"));
            }
        }
    }
}

#[test]
fn reverse_split_customer_sentences_use_the_formal_dictionary() {
    let mut engine =
        ImeEngine::new(config("xiaohe-yinxing", Some(formal_bundle()), None, 5)).unwrap();
    engine
        .configure_code_table_commit_policy(4, 4, true)
        .unwrap();
    for (code, expected) in [
        ("alyghfry", "按理应该很容易"),
        ("gmycxnta", "干嘛要笑她"),
        ("xtupjdma", "学双拼简单吗"),
        ("nivtsmne", "你折腾什么呢"),
    ] {
        engine.reset();
        let mut text = String::new();
        for key in code.chars() {
            let result = engine.process_key(key);
            assert!(result.success);
            text.push_str(&result.commit_text);
        }
        if !engine.current_state().raw_input.is_empty() {
            text.push_str(&engine.select_candidate(0).unwrap().commit_text);
        }
        assert_eq!(text, expected, "{code}");
        assert!(engine.current_state().raw_input.is_empty());
    }
}

#[test]
fn reverse_split_formal_candidates_and_oit_preserve_protocol_semantics() {
    let mut engine =
        ImeEngine::new(config("xiaohe-yinxing", Some(formal_bundle()), None, 5)).unwrap();
    enable_all_categories(&mut engine);
    engine
        .configure_code_table_commit_policy(4, 4, true)
        .unwrap();
    let result = enter(&mut engine, "hfkn");
    assert!(result.commit_text.is_empty());
    assert_eq!(result.candidates[0].text, "很可能");
    assert_eq!(result.candidates[1].text, "很困难");
    assert_eq!(result.candidates[1].display_text, "困难");
    assert_eq!(result.candidates[1].reading, "hfkn");
    assert_eq!(result.candidates[1].consumed_raw_len, 4);
    assert_eq!(result.display_segments, ["hf", "kn"]);
    assert_eq!(result.preedit_text, "hfkn");
    assert_eq!(engine.select_candidate(1).unwrap().commit_text, "很困难");
    enter(&mut engine, "hfkn");
    let next = engine.process_key('n');
    assert_eq!(next.commit_text, "很可能");
    assert_eq!(next.raw_input, "n");
    engine.reset();
    let modes = enter(&mut engine, "oit");
    assert_eq!(
        modes
            .candidates
            .iter()
            .take(2)
            .map(|row| row.text.as_str())
            .collect::<Vec<_>>(),
        ["[传统]", "[切分]"]
    );
    // Existing same-code symbols remain available after the two mode actions.
    assert!(modes.candidates.iter().skip(2).any(|row| row.text == "🤭"));
    let selected = engine.select_candidate(0).unwrap();
    assert!(selected.commit_text.is_empty());
    assert_eq!(
        selected.action,
        Some(ProtocolAction::DirectControl {
            action: "settings.split-mode".to_owned(),
            target: "traditional".to_owned(),
        })
    );
}

#[test]
fn reverse_split_formal_three_code_dead_end_starts_two_plus_one() {
    let mut engine =
        ImeEngine::new(config("xiaohe-yinxing", Some(formal_bundle()), None, 5)).unwrap();
    enable_all_categories(&mut engine);
    engine
        .configure_code_table_commit_policy(4, 4, true)
        .unwrap();

    let result = enter(&mut engine, "jda");
    assert!(result.commit_text.is_empty());
    assert_eq!(result.raw_input, "jda");
    assert_eq!(result.display_segments, ["jd", "a"]);
    assert_eq!(result.candidates[0].text, "简单啊");
    assert_eq!(result.candidates[0].display_text, "简单啊");
    assert_eq!(result.candidates[1].text, "简单安装");
    assert_eq!(result.candidates[1].display_text, "安装");
    assert_eq!(result.candidates[1].reading, "jda");
    assert_eq!(result.candidates[1].consumed_raw_len, 3);

    let selected = engine.select_candidate(1).unwrap();
    assert_eq!(selected.commit_text, "简单安装");
    assert!(selected.raw_input.is_empty());
}

#[test]
fn reverse_split_formal_page_sizes_preserve_ambiguity_and_fifth_key() {
    for page_size in [1, 2, 5, 9] {
        let mut engine = ImeEngine::new(config(
            "xiaohe-yinxing",
            Some(formal_bundle()),
            None,
            page_size,
        ))
        .unwrap();
        enable_all_categories(&mut engine);
        engine
            .configure_code_table_commit_policy(4, 4, true)
            .unwrap();
        let state = enter(&mut engine, "hfkn");
        assert!(state.commit_text.is_empty(), "page size {page_size}");
        assert_eq!(state.raw_input, "hfkn");
        assert_eq!(state.candidates.len(), page_size.min(2));
        if page_size == 1 {
            assert!(state.has_next_page);
            let second = engine.next_candidate_page().unwrap();
            assert_eq!(second.candidates[0].display_text, "困难");
            assert_eq!(engine.select_candidate(0).unwrap().commit_text, "很困难");
            enter(&mut engine, "hfkn");
            engine.next_candidate_page().unwrap();
        }
        let next = engine.process_key('n');
        assert_eq!(next.commit_text, "很可能");
        assert_eq!(next.raw_input, "n");
    }
}

#[test]
fn reverse_split_formal_category_switch_changes_unique_commit() {
    let mut engine =
        ImeEngine::new(config("xiaohe-yinxing", Some(formal_bundle()), None, 5)).unwrap();
    engine
        .configure_code_table_commit_policy(4, 4, true)
        .unwrap();
    engine
        .set_code_table_categories(vec!["core".to_owned()])
        .unwrap();
    let unique = enter(&mut engine, "hfkn");
    assert_eq!(unique.commit_text, "很可能");
    assert!(unique.raw_input.is_empty());
    engine
        // The customer table stores 困难/kn in 分类, not 二简次选.
        .set_code_table_categories(vec!["core".to_owned(), "category-secondary".to_owned()])
        .unwrap();
    let ambiguous = enter(&mut engine, "hfkn");
    assert!(ambiguous.commit_text.is_empty());
    assert_eq!(ambiguous.candidates[1].display_text, "困难");
    assert_eq!(engine.select_candidate(1).unwrap().commit_text, "很困难");
}

#[test]
fn reverse_split_formal_symbol_halves_and_missing_category_fallback() {
    let mut engine =
        ImeEngine::new(config("xiaohe-yinxing", Some(formal_bundle()), None, 5)).unwrap();
    engine
        .configure_code_table_commit_policy(4, 4, true)
        .unwrap();
    engine
        .set_code_table_categories(vec!["core".to_owned(), "symbol".to_owned()])
        .unwrap();
    for (code, expected) in [("hfoi", "很😊"), ("oihf", "😊很")] {
        let state = enter(&mut engine, code);
        assert_eq!(state.commit_text, expected, "{code}");
        assert!(state.raw_input.is_empty());
    }
    engine
        .set_code_table_categories(vec!["core".to_owned()])
        .unwrap();
    for clear_length in [4, 12] {
        engine
            .configure_code_table_commit_policy(4, clear_length, true)
            .unwrap();
        let state = enter(&mut engine, "hfoi");
        assert!(state.commit_text.is_empty());
        assert!(state.candidates.is_empty());
        assert_eq!(state.raw_input, if clear_length == 4 { "" } else { "hfoi" });
        engine.reset();
    }
}

fn workspace() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..")
}

fn formal_bundle() -> PathBuf {
    workspace()
        .join("dictionaries/generated/xiaohe-yinxing-production/xiaohe-yinxing-production.hsyx")
}

fn xiaohe_lexicon() -> PathBuf {
    workspace().join("dictionaries/generated/production.lex")
}

fn fixture_bundle() -> &'static PathBuf {
    static PATH: OnceLock<PathBuf> = OnceLock::new();
    PATH.get_or_init(|| {
        let root = std::env::temp_dir().join(format!(
            "stage11-6-3-formal-pairing-fixture-{}",
            std::process::id()
        ));
        let report = generate_fixture(&root).expect("fixture source");
        let build = build_bundle(&report.manifest_path).expect("fixture bundle");
        let path = root.join("fixture.bundle");
        fs::write(&path, build.bytes).expect("write fixture");
        path
    })
}

fn config(
    scheme_id: &str,
    bundle: Option<PathBuf>,
    user: Option<PathBuf>,
    page_size: usize,
) -> EngineConfig {
    EngineConfig {
        scheme_id: scheme_id.to_owned(),
        lexicon_path: Some(xiaohe_lexicon().to_string_lossy().into_owned()),
        code_table_bundle_path: bundle.map(|path| path.to_string_lossy().into_owned()),
        user_lexicon_path: user.map(|path| path.to_string_lossy().into_owned()),
        code_table_action_fixture_path: None,
        code_table_action_fixture_sha256: None,
        candidate_page_size: page_size,
        quanpin_features: Default::default(),
        quanpin_context_reranking: Default::default(),
    }
}

fn enter(engine: &mut ImeEngine, code: &str) -> engine_protocol::CompositionResult {
    let mut result = engine.current_state();
    for key in code.chars() {
        result = engine.process_key(key);
        assert!(result.success, "{}", result.error_message);
    }
    result
}

fn enable_all_categories(engine: &mut ImeEngine) {
    engine
        .set_code_table_categories(ALL_CATEGORY_IDS.map(str::to_owned).to_vec())
        .expect("enable all formal categories");
}

fn texts_for_code(engine: &mut ImeEngine, code: &str) -> Vec<String> {
    engine.reset();
    let mut result = enter(engine, code);
    if !result.commit_text.is_empty() {
        return vec![result.commit_text];
    }
    let mut texts = result
        .candidates
        .iter()
        .map(|candidate| candidate.text.clone())
        .collect::<Vec<_>>();
    while result.has_next_page {
        result = engine.next_candidate_page().expect("next formal page");
        texts.extend(
            result
                .candidates
                .iter()
                .map(|candidate| candidate.text.clone()),
        );
    }
    texts
}

fn temporary_user_file(name: &str) -> PathBuf {
    std::env::temp_dir().join(format!(
        "stage11-6-4-formal-{name}-{}-{:?}.txt",
        std::process::id(),
        std::thread::current().id()
    ))
}

#[test]
fn production_guide_exposes_repeat_pair_undo_and_line_end_actions() {
    let mut engine = ImeEngine::new(config("xiaohe-yinxing", Some(formal_bundle()), None, 9))
        .expect("formal engine");

    for code in ["f", "i", "j", "n"] {
        engine.reset();
        let state = enter(&mut engine, &format!(";{code}"));
        assert!(state.raw_input.is_empty(), "guide code {code}");
        assert!(state.candidates.is_empty(), "guide code {code}");
        match code {
            "f" => assert_eq!(state.action, Some(ProtocolAction::RepeatCommit)),
            "i" => assert_eq!(state.action, Some(ProtocolAction::UndoCommit)),
            "j" => assert!(matches!(
                state.action,
                Some(ProtocolAction::InsertPair { .. })
            )),
            "n" => assert_eq!(state.action, Some(ProtocolAction::MoveLineEnd)),
            _ => unreachable!(),
        }
    }
}

#[test]
fn production_guide_prefix_candidate_and_double_semicolon_follow_the_table() {
    let mut engine = ImeEngine::new(config("xiaohe-yinxing", Some(formal_bundle()), None, 9))
        .expect("formal engine");

    let prefix = engine.process_key(';');
    assert_eq!(prefix.raw_input, ";");
    assert_eq!(prefix.candidates[0].text, "：");

    let repeated = engine.process_key(';');
    assert_eq!(repeated.commit_text, "；");
    assert!(repeated.raw_input.is_empty());
    assert!(repeated.candidates.is_empty());
}

#[test]
fn production_quick_symbols_and_symbols_follow_category_switches() {
    let mut engine = ImeEngine::new(config("xiaohe-yinxing", Some(formal_bundle()), None, 9))
        .expect("formal engine");

    let quick = enter(&mut engine, ";q");
    assert_eq!(quick.commit_text, "：“");
    assert!(quick.raw_input.is_empty());
    assert!(quick.candidates.is_empty());
    assert!(texts_for_code(&mut engine, "oi").contains(&"😊".to_owned()));
    assert!(texts_for_code(&mut engine, "ofbd").contains(&"．".to_owned()));

    engine
        .set_code_table_categories(vec![
            "core".to_owned(),
            "category-secondary".to_owned(),
            "one-key-secondary".to_owned(),
            "two-key-secondary".to_owned(),
            "out-of-table-character".to_owned(),
            "full-code-word".to_owned(),
            "rare-character".to_owned(),
            "full-code-character".to_owned(),
        ])
        .expect("disable quick symbols and symbols");

    engine.reset();
    let quick_disabled = enter(&mut engine, ";q");
    assert!(quick_disabled.candidates.is_empty());
    assert!(!texts_for_code(&mut engine, "oi").contains(&"😊".to_owned()));
    assert!(!texts_for_code(&mut engine, "ofbd").contains(&"．".to_owned()));
}

#[test]
fn production_component_candidates_cover_ob_and_ox_source_rows_in_order() {
    let mut engine = ImeEngine::new(config("xiaohe-yinxing", Some(formal_bundle()), None, 9))
        .expect("formal engine");

    assert_eq!(texts_for_code(&mut engine, "oba"), ["一", "鱼"]);
    assert_eq!(texts_for_code(&mut engine, "obn"), ["乀", "⺧", "牜"]);

    engine.reset();
    let oba = enter(&mut engine, "oba");
    assert_eq!(oba.candidates[0].text, "一");
    assert_eq!(oba.candidates[0].display_text, "横_一");
    assert_eq!(oba.candidates[1].text, "鱼");
    engine.reset();
    let obn = enter(&mut engine, "obn");
    assert_eq!(obn.candidates[0].text, "乀");
    assert_eq!(obn.candidates[0].display_text, "捺_乀");

    let expected_counts = [
        ("oba", 2),
        ("obb", 6),
        ("obc", 2),
        ("obd", 5),
        ("obe", 5),
        ("obf", 5),
        ("obg", 5),
        ("obh", 4),
        ("obi", 3),
        ("obj", 3),
        ("obk", 5),
        ("obl", 4),
        ("obm", 1),
        ("obn", 3),
        ("obo", 3),
        ("obp", 3),
        ("obq", 4),
        ("obr", 1),
        ("obs", 4),
        ("obt", 1),
        ("obu", 5),
        ("obv", 3),
        ("obw", 4),
        ("obx", 5),
        ("oby", 5),
        ("obz", 3),
        ("oxa", 1),
        ("oxb", 13),
        ("oxc", 4),
        ("oxd", 9),
        ("oxe", 4),
        ("oxf", 9),
        ("oxg", 12),
        ("oxh", 5),
        ("oxi", 14),
        ("oxj", 16),
        ("oxk", 3),
        ("oxl", 11),
        ("oxm", 12),
        ("oxn", 8),
        ("oxp", 3),
        ("oxq", 8),
        ("oxr", 5),
        ("oxs", 3),
        ("oxt", 4),
        ("oxu", 23),
        ("oxv", 13),
        ("oxw", 16),
        ("oxx", 9),
        ("oxy", 29),
        ("oxz", 3),
    ];
    for (code, expected_count) in expected_counts {
        assert_eq!(
            texts_for_code(&mut engine, code).len(),
            expected_count,
            "candidate count for {code}",
        );
    }
}

#[test]
fn production_o_prefix_accepts_each_key_once_and_keeps_direct_actions_reachable() {
    let mut engine = ImeEngine::new(config("xiaohe-yinxing", Some(formal_bundle()), None, 9))
        .expect("formal engine");

    let o = engine.process_key('o');
    assert!(o.success);
    assert_eq!(o.raw_input, "o");
    assert!(o.candidates.iter().any(|candidate| candidate.text == "哦"));
    assert!(o
        .candidates
        .iter()
        .all(|candidate| candidate.reading == "o"));

    let ok = engine.process_key('k');
    assert!(ok.success);
    assert_eq!(ok.raw_input, "ok");
    assert!(ok.candidates.iter().any(|candidate| candidate.text == "👌"));
    assert!(ok
        .candidates
        .iter()
        .all(|candidate| candidate.reading == "ok"));

    engine.reset();
    for (key, expected_raw) in [('o', "o"), ('c', "oc"), ('d', "ocd")] {
        let result = engine.process_key(key);
        assert!(result.success);
        assert_eq!(result.raw_input, expected_raw);
    }
    let selected = engine
        .select_candidate(0)
        .expect("select o-prefixed settings action");
    assert!(matches!(
        selected.action,
        Some(ProtocolAction::DirectControl { ref action, ref target })
            if action == "app.open" && target == "settings"
    ));
}

#[test]
fn formal_engine_scopes_embedded_rules_to_their_owning_category_and_allows_external_override() {
    let bundle = CodeTableBundle::load_frozen_production_file(formal_bundle())
        .expect("load frozen formal bundle");
    let embedded = bundle.user_rules.as_ref().expect("embedded rules");
    let rule = embedded
        .entries()
        .iter()
        .find(|entry| entry.category_id.as_deref() == Some("full-code-word"))
        .expect("embedded full-code-word fixed rule");

    let mut built_in_only =
        ImeEngine::new(config("xiaohe-yinxing", Some(formal_bundle()), None, 3))
            .expect("formal engine with embedded rules");
    let default_texts = texts_for_code(&mut built_in_only, &rule.code);
    assert!(
        !default_texts.contains(&rule.text),
        "full-code-word is disabled by default, so its fixed rows must not leak"
    );
    enable_all_categories(&mut built_in_only);
    let built_in_texts = texts_for_code(&mut built_in_only, &rule.code);
    assert_eq!(built_in_texts.first(), Some(&rule.text));
    built_in_only
        .set_code_table_categories(bundle.default_enabled_category_ids())
        .expect("restore default categories");
    assert!(!texts_for_code(&mut built_in_only, &rule.code).contains(&rule.text));

    let external_path = std::env::temp_dir().join(format!(
        "stage11-6-4-formal-external-delete-{}.txt",
        std::process::id()
    ));
    fs::write(&external_path, format!("{}\t{}#删\n", rule.text, rule.code))
        .expect("external delete rule");
    let mut with_external = ImeEngine::new(config(
        "xiaohe-yinxing",
        Some(formal_bundle()),
        Some(external_path),
        3,
    ))
    .expect("formal engine with external override");
    enable_all_categories(&mut with_external);
    let external_texts = texts_for_code(&mut with_external, &rule.code);
    assert!(!external_texts.contains(&rule.text));
}

#[test]
fn direct_entry_exposes_a_distinct_prefix_hint_and_commits_clean_text() {
    let bundle = CodeTableBundle::load_frozen_production_file(formal_bundle())
        .expect("load frozen formal bundle");
    let direct_rule = bundle
        .user_rules
        .as_ref()
        .expect("embedded rules")
        .entries()
        .iter()
        .find(|entry| entry.text == "给予" && entry.code == "gwyu")
        .expect("embedded direct entry");
    assert!(matches!(direct_rule.action, UserLexiconAction::Direct));

    let mut engine = ImeEngine::new(config("xiaohe-yinxing", Some(formal_bundle()), None, 9))
        .expect("formal engine");

    let prefix = enter(&mut engine, "gwy");
    assert_eq!(prefix.candidates.len(), 1);
    let direct = &prefix.candidates[0];
    assert_eq!(direct.text, "给予");
    assert_eq!(direct.display_text, "给ʲⁱ̌予");
    assert_eq!(direct.reading, "gwyu");

    let selected = engine.select_candidate(0).expect("select direct candidate");
    assert_eq!(selected.commit_text, "给予");

    engine.reset();
    let complete = enter(&mut engine, "gwyu");
    assert_eq!(complete.commit_text, "给予");
    assert!(complete.candidates.is_empty());

    let delete_path = temporary_user_file("delete-embedded-direct");
    fs::write(&delete_path, "给予\tgwyu#删\n").expect("external direct deletion");
    let mut deleted = ImeEngine::new(config(
        "xiaohe-yinxing",
        Some(formal_bundle()),
        Some(delete_path),
        9,
    ))
    .expect("formal engine with direct deletion");
    let deleted_prefix = enter(&mut deleted, "gwy");
    assert!(!deleted_prefix
        .candidates
        .iter()
        .any(|candidate| candidate.text == "给予"));
    deleted.reset();
    let deleted_complete = enter(&mut deleted, "gwyu");
    assert_ne!(deleted_complete.commit_text, "给予");
    assert!(!deleted_complete
        .candidates
        .iter()
        .any(|candidate| candidate.text == "给予"));
}

#[test]
fn external_actions_layer_after_embedded_rules_with_fixed_protection() {
    let bundle = CodeTableBundle::load_frozen_production_file(formal_bundle())
        .expect("load frozen formal bundle");
    let embedded = bundle.user_rules.as_ref().expect("embedded rules");
    let rules_with_room = embedded
        .entries()
        .iter()
        .take(3)
        .cloned()
        .collect::<Vec<_>>();
    assert_eq!(rules_with_room.len(), 3, "formal data needs three rules");
    let deleted = &rules_with_room[0];
    let added = &rules_with_room[1];
    let protected = &rules_with_room[2];
    let enabled = ALL_CATEGORY_IDS.map(str::to_owned).to_vec();
    let positioned = embedded
        .entries()
        .iter()
        .find(|rule| {
            !rules_with_room
                .iter()
                .any(|selected| selected.code == rule.code)
                && query_exact_or_prefix(&bundle, &enabled, &rule.code, usize::MAX)
                    .candidates
                    .len()
                    >= 2
        })
        .expect("formal embedded rule with at least two system candidates");

    let path = temporary_user_file("actions");
    fs::write(
        &path,
        format!(
            concat!(
                "{}\t{}#删\n",
                "{}\t{}\n",
                "外部固顶\t{}#固\n",
                "外部同位甲\t{}#1\n",
                "外部同位乙\t{}#1\n",
                "{}\t{}#2\n",
            ),
            deleted.text,
            deleted.code,
            added.text,
            added.code,
            protected.code,
            protected.code,
            protected.code,
            positioned.text,
            positioned.code,
        ),
    )
    .expect("external action rules");
    let mut engine = ImeEngine::new(config(
        "xiaohe-yinxing",
        Some(formal_bundle()),
        Some(path),
        2,
    ))
    .expect("formal engine with layered actions");
    enable_all_categories(&mut engine);

    assert!(!texts_for_code(&mut engine, &deleted.code).contains(&deleted.text));

    engine.reset();
    let mut added_result = enter(&mut engine, &added.code);
    let mut added_candidates = added_result
        .candidates
        .iter()
        .map(|candidate| (candidate.text.clone(), candidate.source.clone()))
        .collect::<Vec<_>>();
    while added_result.has_next_page {
        added_result = engine.next_candidate_page().expect("next added page");
        added_candidates.extend(
            added_result
                .candidates
                .iter()
                .map(|candidate| (candidate.text.clone(), candidate.source.clone())),
        );
    }
    assert_eq!(added_candidates.last().unwrap().0, added.text);
    assert_eq!(added_candidates.last().unwrap().1, "user-lexicon");

    let protected_texts = texts_for_code(&mut engine, &protected.code);
    assert_eq!(
        &protected_texts[..4],
        [
            protected.text.as_str(),
            "外部固顶",
            "外部同位甲",
            "外部同位乙",
        ]
    );

    let positioned_texts = texts_for_code(&mut engine, &positioned.code);
    assert_eq!(positioned_texts.get(1), Some(&positioned.text));
}

#[test]
fn external_delete_is_complete_key_exact_and_never_falls_back_to_prefixes() {
    let bundle = CodeTableBundle::load_frozen_production_file(formal_bundle())
        .expect("load frozen formal bundle");
    let enabled = bundle.default_enabled_category_ids();
    let embedded = bundle.user_rules.as_ref().expect("embedded rules");

    let mut by_text = std::collections::BTreeMap::<&str, Vec<&str>>::new();
    for category in &bundle.categories {
        for entry in &category.lexicon.entries {
            let codes = by_text.entry(entry.word.as_str()).or_default();
            if !codes.contains(&entry.pinyin_key.as_str()) {
                codes.push(entry.pinyin_key.as_str());
            }
        }
    }
    let (same_text, codes) = by_text
        .iter()
        .find(|(_, codes)| codes.len() >= 2)
        .expect("same text with different complete codes");
    let path = temporary_user_file("complete-key-delete");
    fs::write(&path, format!("{same_text}\t{}#删\n", codes[0])).expect("external delete");
    let mut engine = ImeEngine::new(config(
        "xiaohe-yinxing",
        Some(formal_bundle()),
        Some(path),
        3,
    ))
    .expect("formal engine with exact delete");
    assert!(texts_for_code(&mut engine, codes[1]).contains(&same_text.to_string()));

    let exact_only = bundle
        .categories
        .iter()
        .flat_map(|category| category.lexicon.entries.iter())
        .find(|entry| {
            embedded
                .entries_exact_or_prefix(&entry.pinyin_key)
                .is_empty()
                && query_exact_or_prefix(&bundle, &enabled, &entry.pinyin_key, usize::MAX)
                    .candidates
                    .len()
                    == 1
                && bundle.categories.iter().any(|category| {
                    category.lexicon.entries.iter().any(|longer| {
                        longer.pinyin_key.starts_with(&entry.pinyin_key)
                            && longer.pinyin_key.len() > entry.pinyin_key.len()
                    })
                })
        })
        .expect("single exact candidate with a longer system prefix");
    let delete_path = temporary_user_file("no-second-fallback");
    fs::write(
        &delete_path,
        format!("{}\t{}#删\n", exact_only.word, exact_only.pinyin_key),
    )
    .expect("exact delete without fallback");
    let mut deleted = ImeEngine::new(config(
        "xiaohe-yinxing",
        Some(formal_bundle()),
        Some(delete_path),
        3,
    ))
    .expect("formal engine for no-fallback delete");
    let after_delete = enter(&mut deleted, &exact_only.pinyin_key);
    assert!(after_delete.commit_text.is_empty());
    assert!(after_delete.candidates.is_empty());
}

#[test]
fn formal_precise_queries_return_only_exact_short_codes_stably() {
    let bundle = CodeTableBundle::load_frozen_production_file(formal_bundle())
        .expect("load frozen formal bundle");
    let enabled = bundle.default_enabled_category_ids();
    let cases = ["aa", "ai", "an", "ni", "hc", "ui", "vi", "wo", "xm", "xq"];
    let mut engine = ImeEngine::new(config("xiaohe-yinxing", Some(formal_bundle()), None, 9))
        .expect("formal precise engine");

    for code in cases {
        engine.reset();
        let first = enter(&mut engine, code);
        assert!(first.commit_text.is_empty(), "{code}");
        assert!(first
            .candidates
            .iter()
            .all(|candidate| candidate.reading == code));
        let all = texts_for_code(&mut engine, code);
        assert!(
            !all.is_empty(),
            "{code}: expected an exact short-code entry"
        );
        let mut seen = std::collections::BTreeSet::new();
        assert!(
            all.iter().all(|text| seen.insert(text)),
            "{code}: duplicate text"
        );

        let system_exact = query_exact_or_prefix(&bundle, &enabled, code, usize::MAX)
            .candidates
            .into_iter()
            .map(|candidate| candidate.text)
            .collect::<Vec<_>>();
        assert!(system_exact.iter().all(|text| all.contains(text)));

        let repeated = texts_for_code(&mut engine, code);
        assert_eq!(repeated, all, "{code}: repeated query changed");
    }
}

#[test]
fn formal_un_returns_only_the_first_source_ordered_prefix_hint() {
    let mut engine = ImeEngine::new(config("xiaohe-yinxing", Some(formal_bundle()), None, 50))
        .expect("formal precise hint engine");
    let result = enter(&mut engine, "un");

    assert!(result.commit_text.is_empty());
    assert_eq!(result.candidates.len(), 1);
    assert!(!result.has_next_page);
    assert!(result.candidates.iter().all(|candidate| {
        candidate.reading.starts_with("un") && candidate.reading.len() > "un".len()
    }));
    assert_eq!(
        result
            .candidates
            .iter()
            .map(|candidate| (candidate.text.as_str(), candidate.reading.as_str()))
            .collect::<Vec<_>>(),
        [("熟能生巧", "unuq")]
    );

    engine.reset();
    assert_eq!(enter(&mut engine, "un").candidates, result.candidates);
}

#[test]
fn formal_precise_backspace_and_page_size_are_stable() {
    let mut page_nine =
        ImeEngine::new(config("xiaohe-yinxing", Some(formal_bundle()), None, 9)).unwrap();
    let ni = texts_for_code(&mut page_nine, "ni");
    let nia = texts_for_code(&mut page_nine, "nia");
    assert_eq!(ni, ["你"]);
    assert_eq!(nia, ["鲵"]);

    page_nine.reset();
    enter(&mut page_nine, "nia");
    let after_backspace = page_nine.backspace();
    assert_eq!(after_backspace.raw_input, "ni");
    assert_eq!(
        after_backspace
            .candidates
            .iter()
            .map(|candidate| candidate.text.as_str())
            .collect::<Vec<_>>(),
        ni.iter().take(9).map(String::as_str).collect::<Vec<_>>()
    );

    let mut page_three =
        ImeEngine::new(config("xiaohe-yinxing", Some(formal_bundle()), None, 3)).unwrap();
    assert_eq!(texts_for_code(&mut page_three, "ni"), ni);
    assert_eq!(texts_for_code(&mut page_nine, "ni"), ni);
}

#[test]
fn precise_short_codes_ignore_large_pages_and_double_pinyin_snapshot_stays_stable() {
    let mut shape_b =
        ImeEngine::new(config("xiaohe-yinxing", Some(formal_bundle()), None, 50)).unwrap();
    let shape_b_result = enter(&mut shape_b, "b");
    assert_eq!(
        shape_b_result
            .candidates
            .iter()
            .map(|candidate| (candidate.text.as_str(), candidate.reading.as_str()))
            .collect::<Vec<_>>(),
        [("不", "b"), ("比较", "b")]
    );
    assert!(!shape_b_result.has_next_page);

    let mut shape_page_nine =
        ImeEngine::new(config("xiaohe-yinxing", Some(formal_bundle()), None, 9)).unwrap();
    let shape_baseline = texts_for_code(&mut shape_page_nine, "h");
    assert_eq!(shape_baseline, ["和", "忽略"]);

    let mut shape_page_fifty =
        ImeEngine::new(config("xiaohe-yinxing", Some(formal_bundle()), None, 50)).unwrap();
    let shape_first = enter(&mut shape_page_fifty, "h");
    assert_eq!(shape_first.candidates.len(), 2);
    assert!(!shape_first.has_next_page);
    let selected_shape = shape_page_fifty.select_candidate(1).unwrap();
    assert_eq!(selected_shape.commit_text, "忽略");
    assert_eq!(texts_for_code(&mut shape_page_fifty, "h"), shape_baseline);

    let mut double_page_nine = ImeEngine::new(config("xiaohe", None, None, 9)).unwrap();
    let double_baseline = texts_for_code(&mut double_page_nine, "h");
    assert_eq!(double_baseline.len(), 500);
    for common in ["和", "好", "还", "会", "很", "后", "或"] {
        assert!(
            double_baseline.iter().take(20).any(|text| text == common),
            "{common} should be in the globally ranked first 20"
        );
    }

    let mut double_page_fifty = ImeEngine::new(config("xiaohe", None, None, 50)).unwrap();
    let double_first = enter(&mut double_page_fifty, "h");
    assert_eq!(double_first.candidates.len(), 50);
    assert!(double_first.has_next_page);
    let double_second = double_page_fifty.next_candidate_page().unwrap();
    assert_eq!(double_second.candidate_page, 1);
    assert_eq!(double_second.candidates.len(), 50);
    assert_eq!(double_second.candidates[0].text, double_baseline[50]);
    assert!(double_second.has_next_page);
    let double_third = double_page_fifty.next_candidate_page().unwrap();
    assert_eq!(double_third.candidate_page, 2);
    assert_eq!(double_third.candidates.len(), 50);
    assert_eq!(double_third.candidates[0].text, double_baseline[100]);
    assert!(double_third.has_next_page);
    assert_eq!(texts_for_code(&mut double_page_fifty, "h"), double_baseline);
}

#[test]
fn oversized_page_keeps_precise_results_small_and_double_pinyin_bounded() {
    let mut shape = ImeEngine::new(config(
        "xiaohe-yinxing",
        Some(formal_bundle()),
        None,
        usize::MAX,
    ))
    .unwrap();
    assert_eq!(enter(&mut shape, "h").candidates.len(), 2);

    let mut double = ImeEngine::new(config("xiaohe", None, None, usize::MAX)).unwrap();
    let double_result = enter(&mut double, "h");
    assert_eq!(double_result.candidates.len(), 500);
    assert!(!double_result.has_next_page);
}

#[test]
fn external_recovery_failure_never_removes_embedded_layer() {
    let bundle = CodeTableBundle::load_frozen_production_file(formal_bundle())
        .expect("load frozen formal bundle");
    let rule = bundle
        .user_rules
        .as_ref()
        .expect("embedded rules")
        .entries()
        .iter()
        .find(|entry| entry.category_id.as_deref() == Some("full-code-word"))
        .expect("embedded fixed rule")
        .clone();

    for (name, prepare) in [("missing", None), ("empty", Some(Vec::<u8>::new()))] {
        let path = temporary_user_file(name);
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(path.with_file_name(format!(
            "{}.bak",
            path.file_name().unwrap().to_string_lossy()
        )));
        if let Some(bytes) = prepare {
            fs::write(&path, bytes).expect("prepare empty external file");
        }
        let mut engine = ImeEngine::new(config(
            "xiaohe-yinxing",
            Some(formal_bundle()),
            Some(path),
            3,
        ))
        .expect("formal engine without effective external layer");
        enable_all_categories(&mut engine);
        assert_eq!(
            texts_for_code(&mut engine, &rule.code).first(),
            Some(&rule.text)
        );
    }

    let path = temporary_user_file("recovery");
    let external = parse_user_lexicon_bytes(
        "external.txt",
        format!("外部恢复固顶\t{}#固\n", rule.code).as_bytes(),
    )
    .expect("valid external recovery rule")
    .into_snapshot();
    save_snapshot_atomic(&path, &external).expect("save external primary and backup");
    fs::write(&path, b"broken").expect("corrupt external primary");
    let mut recovered = ImeEngine::new(config(
        "xiaohe-yinxing",
        Some(formal_bundle()),
        Some(path.clone()),
        3,
    ))
    .expect("formal engine recovers external backup");
    enable_all_categories(&mut recovered);
    assert_eq!(
        &texts_for_code(&mut recovered, &rule.code)[..2],
        [rule.text.as_str(), "外部恢复固顶"]
    );

    fs::write(
        path.with_file_name(format!(
            "{}.bak",
            path.file_name().unwrap().to_string_lossy()
        )),
        b"broken",
    )
    .expect("corrupt external backup");
    let mut degraded = ImeEngine::new(config(
        "xiaohe-yinxing",
        Some(formal_bundle()),
        Some(path),
        3,
    ))
    .expect("formal engine degrades to embedded rules");
    enable_all_categories(&mut degraded);
    let degraded_texts = texts_for_code(&mut degraded, &rule.code);
    assert_eq!(degraded_texts.first(), Some(&rule.text));
    assert!(!degraded_texts.iter().any(|text| text == "外部恢复固顶"));
}

#[test]
fn formal_engine_queries_pages_resets_selects_and_preserves_system_behavior() {
    let mut engine = ImeEngine::new(config("xiaohe-yinxing", Some(formal_bundle()), None, 2))
        .expect("formal engine");
    enable_all_categories(&mut engine);
    assert_eq!(engine.scheme_id(), "xiaohe-yinxing");
    assert!(engine.has_lexicon());

    let isolated = enter(&mut engine, "aaba");
    assert_eq!(isolated.commit_text, "阿爸");
    assert!(isolated.candidates.is_empty());
    assert!(isolated.raw_input.is_empty());

    engine.reset();
    enter(&mut engine, "jumk");
    let first = engine.current_state();
    assert_eq!(first.raw_input, "jumk");
    assert_eq!(
        first
            .candidates
            .iter()
            .map(|item| item.text.as_str())
            .collect::<Vec<_>>(),
        ["驹", "枸"]
    );
    assert!(first.has_next_page);
    let second = engine.next_candidate_page().expect("page two");
    assert_eq!(second.candidate_page, 1);
    assert_eq!(
        second
            .candidates
            .iter()
            .map(|item| item.text.as_str())
            .collect::<Vec<_>>(),
        ["椐", "桔"]
    );
    assert!(second.has_previous_page);
    let first_again = engine.previous_candidate_page().expect("page one");
    assert_eq!(first_again.candidates, first.candidates);

    engine.set_user_learning_enabled(true);
    engine.set_session_learning_allowed(true);
    let committed = engine.select_candidate(0).expect("select formal candidate");
    assert_eq!(committed.commit_text, "驹");
    assert!(committed.composition_finished);
    assert!(engine.current_state().raw_input.is_empty());
    enter(&mut engine, "jumk");
    assert_eq!(engine.current_state().candidates, first.candidates);

    let after_backspace = engine.backspace();
    assert_eq!(after_backspace.raw_input, "jum");
    assert_ne!(after_backspace.candidates, first.candidates);
    let reset = engine.reset();
    assert!(reset.raw_input.is_empty());
    assert!(reset.candidates.is_empty());
}

#[test]
fn four_code_uniqueness_is_decided_after_user_rules_and_commits_once() {
    let mut multiple =
        ImeEngine::new(config("xiaohe-yinxing", Some(formal_bundle()), None, 9)).unwrap();
    enable_all_categories(&mut multiple);
    let multiple_result = enter(&mut multiple, "bmlu");
    assert!(multiple_result.commit_text.is_empty());
    assert_eq!(
        multiple_result
            .candidates
            .iter()
            .map(|candidate| candidate.text.as_str())
            .collect::<Vec<_>>(),
        ["辫", "辨", "辩"]
    );
    assert!(multiple_result
        .candidates
        .iter()
        .all(|candidate| candidate.reading == "bmlu"));

    let rules = temporary_user_file("filtered-unique");
    fs::write(&rules, "辫\tbmlu#删\n辨\tbmlu#删\n").expect("delete two exact duplicates");
    let mut unique = ImeEngine::new(config(
        "xiaohe-yinxing",
        Some(formal_bundle()),
        Some(rules),
        9,
    ))
    .unwrap();
    enable_all_categories(&mut unique);
    let committed = enter(&mut unique, "bmlu");
    assert_eq!(committed.commit_text, "辩");
    assert!(committed.raw_input.is_empty());
    assert!(committed.candidates.is_empty());

    let next = unique.process_key('a');
    assert!(next.commit_text.is_empty());
    assert_eq!(next.raw_input, "a");
}

#[test]
fn customer_empty_code_examples_never_commit_a_shorter_prefix_before_four_codes() {
    let mut engine = ImeEngine::new(config("xiaohe-yinxing", Some(formal_bundle()), None, 9))
        .expect("formal engine");

    let niu = enter(&mut engine, "niu");
    assert!(niu.commit_text.is_empty());
    assert_eq!(niu.raw_input, "niu");
    let niuo = engine.process_key('o');
    assert!(niuo.commit_text.is_empty());
    assert!(niuo.raw_input.is_empty());
    assert!(niuo.candidates.is_empty());

    let lad = enter(&mut engine, "lad");
    assert!(lad.commit_text.is_empty());
    assert_eq!(lad.raw_input, "lad");
    let ladj = engine.process_key('j');
    assert!(ladj.commit_text.is_empty());
    assert!(ladj.raw_input.is_empty());
    assert!(ladj.candidates.is_empty());

    let jda = enter(&mut engine, "jda");
    assert!(jda.commit_text.is_empty());
    assert_eq!(jda.raw_input, "jda");
    assert!(jda.candidates.is_empty());
    assert!(!jda.composition_finished);
}

#[test]
fn formal_and_fixture_bundle_identities_cannot_be_cross_paired() {
    let formal_as_fixture =
        ImeEngine::new(config("code-table-fixture", Some(formal_bundle()), None, 9))
            .expect_err("formal bundle must not satisfy fixture scheme");
    assert!(formal_as_fixture.to_string().contains("metadata_mismatch"));

    let fixture_as_formal = ImeEngine::new(config(
        "xiaohe-yinxing",
        Some(fixture_bundle().clone()),
        None,
        9,
    ))
    .expect_err("fixture bundle must not satisfy formal scheme");
    assert!(fixture_as_formal.to_string().contains("metadata_mismatch"));
}

#[test]
fn xiaohe_ignores_irrelevant_formal_path_and_explicitly_recovers_after_formal_failure() {
    let corrupt_path = std::env::temp_dir().join(format!(
        "stage11-6-3-corrupt-formal-{}.hsyx",
        std::process::id()
    ));
    let mut corrupt = fs::read(formal_bundle()).expect("formal bytes");
    corrupt[0] = b'X';
    fs::write(&corrupt_path, corrupt).expect("corrupt formal file");

    let formal_error = ImeEngine::new(config(
        "xiaohe-yinxing",
        Some(corrupt_path.clone()),
        None,
        9,
    ))
    .expect_err("corrupt formal bundle must fail");
    assert!(formal_error.to_string().contains("invalid_magic"));

    for irrelevant in [
        corrupt_path,
        workspace().join("definitely-missing-formal.hsyx"),
    ] {
        let mut xiaohe = ImeEngine::new(config("xiaohe", Some(irrelevant), None, 9))
            .expect("explicit xiaohe fallback ignores formal path");
        enter(&mut xiaohe, "nihc");
        assert_eq!(xiaohe.current_state().candidates[0].text, "你好");
        xiaohe.reset();
        enter(&mut xiaohe, "uurufa");
        assert_eq!(xiaohe.current_state().candidates[0].text, "输入法");
    }
}

#[test]
fn switching_between_formal_and_xiaohe_resets_backend_state() {
    let mut engine = ImeEngine::new(config("xiaohe-yinxing", Some(formal_bundle()), None, 9))
        .expect("formal engine");
    enable_all_categories(&mut engine);
    enter(&mut engine, "bcbn");
    assert_eq!(engine.current_state().candidates.len(), 3);

    let xiaohe = engine.change_scheme("xiaohe").expect("switch to xiaohe");
    assert!(xiaohe.raw_input.is_empty());
    enter(&mut engine, "nihc");
    assert_eq!(engine.current_state().candidates[0].text, "你好");

    let formal = engine
        .change_scheme("xiaohe-yinxing")
        .expect("switch back to formal");
    assert!(formal.raw_input.is_empty());
    let committed = enter(&mut engine, "aavi");
    assert_eq!(committed.commit_text, "AA制");
    assert!(committed.raw_input.is_empty());

    let guide = enter(&mut engine, ";f");
    assert!(guide.raw_input.is_empty());
    assert!(guide.candidates.is_empty());
    assert_eq!(guide.action, Some(ProtocolAction::RepeatCommit));
}

#[test]
fn user_external_shortcuts_confirm_at_four_codes_or_by_selection_without_text() {
    let path = temporary_user_file("external-shortcuts");
    fs::write(&path, "https://example.com/Help?q=a,b#Part\tzzweb#网页\t帮助网页\nfile://docs/storage/Users/currentUser/Documents\tzzda#目录\t工作目录\n").unwrap();
    let mut engine = ImeEngine::new(config(
        "xiaohe-yinxing",
        Some(formal_bundle()),
        Some(path),
        9,
    ))
    .unwrap();
    engine
        .configure_code_table_commit_policy(4, 4, true)
        .unwrap();
    for (code, label, action, target) in [
        (
            "zzweb",
            "帮助网页",
            "url.open",
            "https://example.com/Help?q=a,b#Part",
        ),
        (
            "zzda",
            "工作目录",
            "directory.open",
            "file://docs/storage/Users/currentUser/Documents",
        ),
    ] {
        engine.reset();
        let state = enter(&mut engine, code);
        assert!(state.commit_text.is_empty());
        let selected = if code.len() == 4 {
            assert!(state.raw_input.is_empty());
            assert!(state.candidates.is_empty());
            state
        } else {
            assert!(state.action.is_none());
            let index = state.candidates.iter().position(|candidate| candidate.text == target).unwrap();
            assert_eq!(state.candidates[index].display_text, label);
            assert_eq!(state.candidates[index].source, "functional");
            engine.select_candidate(index).unwrap()
        };
        assert!(selected.commit_text.is_empty());
        assert_eq!(
            selected.action,
            Some(ProtocolAction::DirectControl {
                action: action.to_owned(),
                target: target.to_owned()
            })
        );
        engine.reset();
        enter(&mut engine, code);
        let continued = engine.process_key('z');
        assert!(continued.commit_text.is_empty());
        assert!(continued.action.is_none());
    }
}

#[test]
fn convenience_input_bypasses_production_auto_commit_and_preserves_normal_codes() {
    let mut engine =
        ImeEngine::new(config("xiaohe-yinxing", Some(formal_bundle()), None, 9)).unwrap();
    for c in "=1234.5".chars() {
        let state = engine.process_key(c);
        assert!(state.success);
        assert!(state.commit_text.is_empty());
    }
    assert_eq!(
        engine.current_state().candidates[0].text,
        "壹仟贰佰叁拾肆元伍角整"
    );
    assert_eq!(
        engine.select_candidate(0).unwrap().commit_text,
        "壹仟贰佰叁拾肆元伍角整"
    );
    for c in "'2026.5.5".chars() {
        engine.process_key(c);
    }
    assert_eq!(
        engine.select_candidate(1).unwrap().commit_text,
        "2026-05-05"
    );
    for c in "ofa".chars() {
        engine.process_key(c);
    }
    assert_eq!(engine.current_state().candidates.len(), 3);
    engine.reset();
    engine.process_key('=');
    engine.change_scheme("xiaohe").unwrap();
    assert!(engine.current_state().raw_input.is_empty());
}

#[test]
fn xhgw_executes_on_the_unique_fourth_key_and_does_not_reexecute_afterward() {
    let mut engine = ImeEngine::new(config("xiaohe-yinxing", Some(formal_bundle()), None, 9)).unwrap();
    for key in "xhg".chars() {
        let prefix = engine.process_key(key);
        assert!(prefix.action.is_none());
        assert!(prefix.commit_text.is_empty());
    }
    let fourth = engine.process_key('w');
    assert!(fourth.success);
    assert!(fourth.raw_input.is_empty());
    assert!(fourth.candidates.is_empty());
    assert!(fourth.commit_text.is_empty());
    assert_eq!(fourth.action, Some(ProtocolAction::DirectControl {
        action: "url.open".to_owned(), target: "flypy-home".to_owned()
    }));
    assert!(engine.current_state().action.is_none());
    assert!(engine.process_key('n').action.is_none());
}

#[test]
fn clipboard_reverse_ofi_is_a_functional_candidate_and_lookup_does_not_commit() {
    let mut engine =
        ImeEngine::new(config("xiaohe-yinxing", Some(formal_bundle()), None, 5)).unwrap();
    let result = enter(&mut engine, "ofi");
    let index = result
        .candidates
        .iter()
        .position(|candidate| candidate.text == "[复制反查]")
        .unwrap();
    assert_eq!(result.candidates[index].source, "functional");
    assert!(result.commit_text.is_empty());
    assert!(result.action.is_none());
    let codes = engine.reverse_lookup("你");
    assert!(codes.iter().any(|code| code == "nirx"), "{codes:?}");
    assert_eq!(engine.current_state().raw_input, "ofi");
    let selected = engine.select_candidate(index).unwrap();
    assert!(selected.commit_text.is_empty());
    assert_eq!(
        selected.action,
        Some(ProtocolAction::DirectControl {
            action: "clipboard.reverse".to_owned(),
            target: String::new(),
        })
    );
    let phonetic = ImeEngine::new(config("xiaohe", Some(formal_bundle()), None, 5)).unwrap();
    assert!(phonetic.reverse_lookup("你").is_empty());
}

