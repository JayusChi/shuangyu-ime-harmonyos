use std::fs;
use std::path::PathBuf;
use std::sync::OnceLock;

use code_table_fixture_generator::{build_bundle, generate_fixture};
use code_table_runtime::{query_exact_or_prefix, CodeTableBundle};
use engine_protocol::ProtocolAction;
use ime_engine::{EngineConfig, ImeEngine};
use user_lexicon::{parse_user_lexicon_bytes, save_snapshot_atomic};

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

    for (code, expected_label) in [("f", "重复"), ("i", "[撤销]"), ("j", "“”"), ("n", "[End]")]
    {
        engine.reset();
        let state = enter(&mut engine, &format!(";{code}"));
        assert_eq!(state.candidates[0].text, expected_label);
        let selected = engine
            .select_candidate(0)
            .expect("select production action");
        match code {
            "f" => assert_eq!(selected.action, Some(ProtocolAction::RepeatCommit)),
            "i" => assert_eq!(selected.action, Some(ProtocolAction::UndoCommit)),
            "j" => assert!(matches!(
                selected.action,
                Some(ProtocolAction::InsertPair { .. })
            )),
            "n" => assert_eq!(selected.action, Some(ProtocolAction::MoveLineEnd)),
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
    assert_eq!(
        prefix
            .candidates
            .iter()
            .map(|candidate| (candidate.text.as_str(), candidate.reading.as_str()))
            .collect::<Vec<_>>(),
        [("：", "_")]
    );

    let repeated = engine.process_key(';');
    assert_eq!(repeated.commit_text, "：");
    assert!(repeated.raw_input.is_empty());
    assert!(repeated.candidates.is_empty());
}

#[test]
fn production_quick_symbols_and_symbols_follow_category_switches() {
    let mut engine = ImeEngine::new(config("xiaohe-yinxing", Some(formal_bundle()), None, 9))
        .expect("formal engine");

    let quick = enter(&mut engine, ";q");
    assert!(quick
        .candidates
        .iter()
        .any(|candidate| candidate.text == "：“"));
    assert!(texts_for_code(&mut engine, "oi").contains(&"😊".to_owned()));
    assert!(texts_for_code(&mut engine, "obd").contains(&"．".to_owned()));

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
    assert!(!texts_for_code(&mut engine, "obd").contains(&"．".to_owned()));
}

#[test]
fn formal_engine_scopes_embedded_rules_to_full_code_word_and_allows_external_override() {
    let bundle = CodeTableBundle::load_frozen_production_file(formal_bundle())
        .expect("load frozen formal bundle");
    let embedded = bundle.user_rules.as_ref().expect("embedded rules");
    let rule = embedded.entries().first().expect("embedded fixed rule");

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
        .first()
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
    assert_eq!(guide.candidates[0].text, "重复");
    let selected = engine
        .select_candidate(0)
        .expect("select restored production guide action");
    assert_eq!(selected.action, Some(ProtocolAction::RepeatCommit));
}
