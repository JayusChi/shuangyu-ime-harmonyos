use engine_protocol::CompositionResult;
use ime_engine::{EngineConfig, ImeEngine};
use lexicon_core::{build_binary_lexicon, LexiconEntry};
use std::{
    fs,
    path::PathBuf,
    sync::atomic::{AtomicUsize, Ordering},
};

static NEXT: AtomicUsize = AtomicUsize::new(0);

fn path(label: &str) -> PathBuf {
    let dir =
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../target/xiaohe-fixed-word-tests");
    fs::create_dir_all(&dir).unwrap();
    dir.join(format!(
        "{label}-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ))
}

fn config(lexicon_path: PathBuf, user_path: PathBuf) -> EngineConfig {
    EngineConfig {
        scheme_id: "xiaohe".to_owned(),
        lexicon_path: Some(lexicon_path.to_string_lossy().into()),
        user_lexicon_path: Some(user_path.to_string_lossy().into()),
        candidate_page_size: 16,
        ..EngineConfig::default()
    }
}

fn fixture(rules: &str) -> (ImeEngine, PathBuf, EngineConfig) {
    let entries = [
        ("我", "wo", 900_000),
        ("用", "yong", 500_000),
        ("是", "shi", 1_000_000),
        ("普", "pu", 500_000),
        ("品", "pin", 100_000),
        ("商品", "shang pin", 1_000_000),
        ("我用商品", "wo yong shang pin", 1_000_000),
        ("很好", "hen hao", 80_000),
        ("的", "de", 1_000_000),
        ("输入法", "shu ru fa", 60_000),
        ("弄", "nong", 600_000),
        ("怒", "nu", 200_000),
        ("拼", "pin", 300_000),
        ("很", "hen", 160_000),
        ("有", "you", 1_000_000),
        ("很有", "hen you", 7_205),
        ("希望", "xi wang", 50_277),
        ("游戏王", "you xi wang", 4),
    ]
    .into_iter()
    .map(|(word, reading, frequency)| {
        LexiconEntry::new(
            word.to_owned(),
            reading.to_owned(),
            reading.split_whitespace().map(str::to_owned).collect(),
            frequency,
            vec!["test".to_owned()],
        )
    })
    .collect::<Vec<_>>();
    let lexicon_path = path("system.lex");
    let user_path = path("user.txt");
    fs::write(
        &lexicon_path,
        build_binary_lexicon(&entries, 24, 1).unwrap(),
    )
    .unwrap();
    fs::write(&user_path, rules).unwrap();
    let cfg = config(lexicon_path, user_path.clone());
    (ImeEngine::new(cfg.clone()).unwrap(), user_path, cfg)
}

fn enter(engine: &mut ImeEngine, raw: &str) -> CompositionResult {
    engine.reset();
    let mut state = engine.current_state();
    for key in raw.chars() {
        state = if key == '\'' {
            engine.insert_segment_boundary().unwrap()
        } else {
            engine.process_key(key)
        };
        assert!(state.success, "{raw}: {state:?}");
    }
    state
}

#[test]
fn common_words_beat_a_rare_long_entry_without_a_sentence_dictionary_patch() {
    let (mut engine, _, _) = fixture("");
    let state = enter(&mut engine, "hfyzxiwh");
    assert_eq!(state.candidates[0].text, "很有希望");
    assert_eq!(engine.select_candidate(0).unwrap().commit_text, "很有希望");
}

#[test]
fn fixed_pair_is_atomic_at_sentence_start_middle_end_and_repeated_positions() {
    let (mut engine, _, _) = fixture("双拼\tup#固\n");
    for (raw, text) in [
        ("up", "双拼"),
        ("uphfhc", "双拼很好"),
        ("woysup", "我用双拼"),
        ("woysupuurufa", "我用双拼输入法"),
        ("upup", "双拼双拼"),
        ("wo'ys'up'uu'ru'fa", "我用双拼输入法"),
    ] {
        let state = enter(&mut engine, raw);
        assert_eq!(state.candidates[0].text, text, "{raw}: {state:?}");
        assert!(
            state.candidates.iter().all(|c| !c.text.contains("商品")),
            "{state:?}"
        );
        let consumed = raw.chars().filter(|c| *c != '\'').count();
        assert_eq!(state.candidates[0].consumed_raw_len as usize, consumed);
        let selected = engine.select_candidate(0).unwrap();
        assert_eq!(selected.commit_text, text);
        assert!(selected.raw_input.is_empty());
    }
}

#[test]
fn partial_selection_and_backspace_preserve_pair_boundaries() {
    let (mut engine, _, _) = fixture("双拼\tup#固\n");
    let original = enter(&mut engine, "upde");
    let index = original
        .candidates
        .iter()
        .position(|c| c.text == "双拼")
        .unwrap();
    assert_eq!(original.candidates[index].consumed_raw_len, 2);
    let selected = engine.select_candidate(index).unwrap();
    assert_eq!(selected.commit_text, "双拼");
    assert_eq!(selected.raw_input, "de");
    assert_eq!(selected.candidates[0].text, "的");
    enter(&mut engine, "upde");
    assert_eq!(engine.backspace().raw_input, "upd");
    assert_eq!(engine.backspace().candidates[0].text, "双拼");
    let odd = engine.backspace();
    assert_eq!(odd.raw_input, "u");
    assert!(odd.candidates.iter().all(|c| c.text != "双拼"));
    assert_eq!(engine.process_key('p').candidates[0].text, "双拼");
}

#[test]
fn valid_syllables_cross_pair_occurrences_and_other_schemes_are_not_overridden() {
    let (mut engine, _, _) = fixture("双拼\tup#固\n固定\tns#固\n");
    for raw in ["nupb", "nu'pb", "wons"] {
        let state = enter(&mut engine, raw);
        assert!(
            state
                .candidates
                .iter()
                .all(|c| !c.text.contains("双拼") && !c.text.contains("固定")),
            "{raw}: {state:?}"
        );
    }
    engine.change_scheme("quanpin").unwrap();
    let state = enter(&mut engine, "woshangpin");
    assert!(state.candidates.iter().all(|c| !c.text.contains("双拼")));
}

#[test]
fn changing_removing_and_reloading_a_rule_affects_the_current_sentence_and_survives_recreation() {
    let (mut engine, user_path, cfg) = fixture("双拼\tup#固\n");
    assert_eq!(enter(&mut engine, "woysup").candidates[0].text, "我用双拼");
    fs::write(&user_path, "声拼\tup#固\n").unwrap();
    assert_eq!(
        engine.reload_user_lexicon().unwrap().candidates[0].text,
        "我用声拼"
    );
    let mut reopened = ImeEngine::new(cfg).unwrap();
    assert_eq!(
        enter(&mut reopened, "woysup").candidates[0].text,
        "我用声拼"
    );
    fs::write(&user_path, "").unwrap();
    let state = engine.reload_user_lexicon().unwrap();
    assert!(state.candidates.iter().all(|c| !c.text.contains("声拼")));
    assert_eq!(state.candidates[0].text, "我用商品");
}

#[test]
fn only_fixed_two_character_rules_participate_and_conflicts_use_source_order() {
    let (mut engine, _, _) = fixture("双拼\tup\n声拼\tup#2\n很长的词\tup#固\n");
    assert_eq!(enter(&mut engine, "woysup").candidates[0].text, "我用商品");
    let (mut engine, _, _) = fixture("双拼\tup#固\n声拼\tup#固\n");
    assert_eq!(enter(&mut engine, "woysup").candidates[0].text, "我用双拼");
}

#[test]
fn packaged_lexicon_resolves_customer_example_and_fixed_sentence() {
    let production = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../../dictionaries/generated/production.lex");
    let user_path = path("production-user.txt");
    fs::write(&user_path, "双拼\tup#固\n怎么\tzm#固\n").unwrap();
    let mut engine = ImeEngine::new(config(production, user_path)).unwrap();
    for (raw, text) in [
        ("hfyzxiwh", "很有希望"),
        ("hf'yz'xi'wh", "很有希望"),
        ("woysup", "我用双拼"),
        ("uphfhc", "双拼很好"),
        ("nizmbuxk", "你怎么不行"),
        ("ni'zm'bu'xk", "你怎么不行"),
    ] {
        let state = enter(&mut engine, raw);
        assert_eq!(state.candidates[0].text, text, "{raw}: {state:?}");
        assert_eq!(
            state.candidates[0].consumed_raw_len,
            raw.chars().filter(|key| key.is_ascii_alphabetic()).count() as u32
        );
        let selected = engine.select_candidate(0).unwrap();
        assert_eq!(selected.commit_text, text);
        assert!(selected.raw_input.is_empty());
        assert!(selected.composition_finished);
    }
}
