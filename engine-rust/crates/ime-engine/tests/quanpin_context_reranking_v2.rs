use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use context_reranker::{
    sha256_hex, NgramBuildInput, WordNgramModel, MAX_BIGRAM_QUERIES, MAX_CANDIDATE_POOL,
    MAX_CONTEXT_WORDS, MAX_MODEL_FILE_BYTES, MAX_MODEL_LOAD_MICROS, MAX_MODEL_MEMORY_BYTES,
    MAX_RERANK_MICROS, MAX_TRIGRAM_QUERIES, MODEL_VERSION, QUERY_CACHE_CAPACITY,
};
use engine_protocol::CompositionResult;
use ime_engine::{
    EngineConfig, ImeEngine, QuanpinContextRerankingConfig,
    QUANPIN_CONTEXT_RERANKING_CONFIG_VERSION,
};
use lexicon_core::{build_binary_lexicon, LexiconEntry};

const LEXICON_VERSION: u32 = 42;

fn entry(text: &str, reading: &str, frequency: u64) -> LexiconEntry {
    LexiconEntry::new(
        text.to_owned(),
        reading.to_owned(),
        reading.split_whitespace().map(str::to_owned).collect(),
        frequency,
        vec!["context-reranking-contract-test".to_owned()],
    )
}

fn unique_path(extension: &str) -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("clock")
        .as_nanos();
    std::env::temp_dir().join(format!(
        "quanpin-context-v2-{}-{nanos}.{extension}",
        std::process::id()
    ))
}

fn test_lexicon() -> PathBuf {
    let entries = vec![
        entry("昨天", "zuo tian", 200_000),
        entry("前天", "qian tian", 190_000),
        entry("今天", "jin tian", 200_000),
        entry("津贴", "jin tian", 100_000),
        // The pre-rerank base score intentionally prefers 天启 by one bucket.
        entry("天气", "tian qi", 100_000),
        entry("天启", "tian qi", 101_000),
        entry("天齐", "tian qi", 99_000),
        entry("预报", "yu bao", 100_000),
        entry("预包", "yu bao", 101_000),
    ];
    let path = unique_path("lex");
    fs::write(
        &path,
        build_binary_lexicon(&entries, LEXICON_VERSION, 1).expect("build lexicon"),
    )
    .expect("write lexicon");
    path
}

fn model_bytes(lexicon_version: u32) -> Vec<u8> {
    WordNgramModel::build_bytes(
        lexicon_version,
        &NgramBuildInput {
            bigrams: vec![
                ("今天".to_owned(), "天气".to_owned(), 1_000_000),
                ("天气".to_owned(), "预报".to_owned(), 500_000),
            ],
            trigrams: vec![(
                "昨天".to_owned(),
                "今天".to_owned(),
                "天气".to_owned(),
                1_000_000,
            )],
        },
    )
    .expect("build model")
}

fn model_file(bytes: &[u8]) -> (PathBuf, String) {
    let path = unique_path("qng");
    fs::write(&path, bytes).expect("write model");
    (path, sha256_hex(bytes))
}

fn engine_with_config(config: QuanpinContextRerankingConfig, page_size: usize) -> ImeEngine {
    ImeEngine::new(EngineConfig {
        scheme_id: "quanpin".to_owned(),
        lexicon_path: Some(test_lexicon().to_string_lossy().into_owned()),
        candidate_page_size: page_size,
        quanpin_context_reranking: config,
        ..EngineConfig::default()
    })
    .expect("context reranking engine")
}

fn enabled_engine(page_size: usize) -> ImeEngine {
    let bytes = model_bytes(LEXICON_VERSION);
    let (path, hash) = model_file(&bytes);
    engine_with_config(
        QuanpinContextRerankingConfig::new(
            true,
            Some(path.to_string_lossy().into_owned()),
            Some(hash),
        ),
        page_size,
    )
}

fn type_text(engine: &mut ImeEngine, raw: &str) -> CompositionResult {
    let mut result = engine.current_state();
    for key in raw.chars() {
        result = engine.process_key(key);
        assert!(result.success, "key {key} failed for {raw}");
    }
    result
}

fn texts(result: &CompositionResult) -> Vec<String> {
    result
        .candidates
        .iter()
        .map(|candidate| candidate.text.clone())
        .collect()
}

fn rank(result: &CompositionResult, expected: &str) -> usize {
    result
        .candidates
        .iter()
        .position(|candidate| candidate.text == expected)
        .expect("candidate recalled")
}

fn select_text(engine: &mut ImeEngine, raw: &str, expected: &str) {
    let result = type_text(engine, raw);
    let index = rank(&result, expected);
    let selected = engine.select_candidate(index).expect("select context word");
    assert_eq!(selected.commit_text, expected);
    assert!(selected.composition_finished);
}

#[test]
fn word_bigram_lifts_only_an_already_recalled_complete_candidate() {
    let mut base = engine_with_config(QuanpinContextRerankingConfig::default(), 20);
    let mut reranked = enabled_engine(20);
    let base_result = type_text(&mut base, "jintiantianqi");
    let reranked_result = type_text(&mut reranked, "jintiantianqi");

    assert!(rank(&base_result, "今天天气") > 0);
    assert_eq!(rank(&reranked_result, "今天天气"), 0);
    assert_eq!(
        texts(&base_result)
            .into_iter()
            .collect::<std::collections::BTreeSet<_>>(),
        texts(&reranked_result)
            .into_iter()
            .collect::<std::collections::BTreeSet<_>>()
    );
    assert_eq!(reranked_result.raw_input, "jintiantianqi");
    assert!(reranked_result.commit_text.is_empty());
    assert!(reranked_result
        .candidates
        .iter()
        .all(|candidate| candidate.consumed_raw_len <= 14));
    let stats = reranked.last_quanpin_reranking_stats();
    assert!(stats.bigram_hits > 0);
    assert!(stats.candidates_with_ngram_hit > 0);
}

#[test]
fn existing_fixed_user_rule_stays_a_barrier_after_context_scoring() {
    let bytes = model_bytes(LEXICON_VERSION);
    let (model_path, hash) = model_file(&bytes);
    let user_path = unique_path("txt");
    fs::write(&user_path, "天启\tqptianqi#固\n").expect("write fixed user rule");
    let mut engine = ImeEngine::new(EngineConfig {
        scheme_id: "quanpin".to_owned(),
        lexicon_path: Some(test_lexicon().to_string_lossy().into_owned()),
        user_lexicon_path: Some(user_path.to_string_lossy().into_owned()),
        candidate_page_size: 20,
        quanpin_context_reranking: QuanpinContextRerankingConfig::new(
            true,
            Some(model_path.to_string_lossy().into_owned()),
            Some(hash),
        ),
        ..EngineConfig::default()
    })
    .expect("fixed rule engine");
    select_text(&mut engine, "jintian", "今天");
    let result = type_text(&mut engine, "tianqi");
    assert_eq!(result.candidates[0].text, "天启");
    assert_eq!(
        result.candidates[0].source,
        "context-reranking-contract-test"
    );
    assert!(rank(&result, "天气") > 0);
}

#[test]
fn trigram_hit_and_bigram_backoff_are_observable_and_bounded() {
    let mut trigram = enabled_engine(20);
    select_text(&mut trigram, "zuotian", "昨天");
    select_text(&mut trigram, "jintian", "今天");
    let hit = type_text(&mut trigram, "tianqi");
    assert_eq!(rank(&hit, "天气"), 0);
    let hit_stats = trigram.last_quanpin_reranking_stats();
    assert!(hit_stats.trigram_hits > 0);
    assert!(hit_stats.trigram_backoffs > 0);

    let mut backoff = enabled_engine(20);
    select_text(&mut backoff, "qiantian", "前天");
    select_text(&mut backoff, "jintian", "今天");
    let backed_off = type_text(&mut backoff, "tianqi");
    assert_eq!(rank(&backed_off, "天气"), 0);
    let stats = backoff.last_quanpin_reranking_stats();
    assert!(stats.trigram_queries > 0);
    assert!(stats.trigram_backoffs > 0);
    assert!(stats.bigram_hits > 0);
    assert!(stats.candidate_pool_size <= MAX_CANDIDATE_POOL);
    assert!(stats.bigram_queries <= MAX_BIGRAM_QUERIES);
    assert!(stats.trigram_queries <= MAX_TRIGRAM_QUERIES);
    assert!(stats.model_file_bytes <= MAX_MODEL_FILE_BYTES);
    assert!(stats.model_memory_bytes <= MAX_MODEL_MEMORY_BYTES);
    assert!(stats.rerank_micros <= MAX_RERANK_MICROS);
    assert_eq!(stats.query_cache_capacity, QUERY_CACHE_CAPACITY);
    assert_eq!(MAX_CONTEXT_WORDS, 2);
}

#[test]
fn partial_selection_clears_context_and_preserves_the_unconsumed_raw_tail() {
    let mut engine = enabled_engine(20);
    select_text(&mut engine, "jintian", "今天");
    let composed = type_text(&mut engine, "tianqiyubao");
    let partial_index = composed
        .candidates
        .iter()
        .position(|candidate| {
            candidate.text == "天气"
                && candidate.consumed_raw_len < composed.raw_input.chars().count() as u32
        })
        .expect("partial 天气 candidate");
    let selected = engine
        .select_candidate(partial_index)
        .expect("select partial candidate");
    assert_eq!(selected.commit_text, "天气");
    assert_eq!(selected.raw_input, "yubao");
    assert!(!selected.composition_finished);
    assert!(rank(&selected, "预报") > 0);
}

#[test]
fn no_hit_and_every_model_load_failure_keep_the_base_order() {
    let mut base = engine_with_config(QuanpinContextRerankingConfig::default(), 20);
    let base_order = texts(&type_text(&mut base, "tianqi"));

    let missing = QuanpinContextRerankingConfig::new(
        true,
        Some(unique_path("missing").to_string_lossy().into_owned()),
        Some("0".repeat(64)),
    );
    let mut cases = vec![(missing, "io_error")];

    let good = model_bytes(LEXICON_VERSION);
    let (good_path, _) = model_file(&good);
    cases.push((
        QuanpinContextRerankingConfig::new(
            true,
            Some(good_path.to_string_lossy().into_owned()),
            Some("0".repeat(64)),
        ),
        "hash_mismatch",
    ));

    let (wrong_lexicon_path, wrong_lexicon_hash) = model_file(&model_bytes(LEXICON_VERSION + 1));
    cases.push((
        QuanpinContextRerankingConfig::new(
            true,
            Some(wrong_lexicon_path.to_string_lossy().into_owned()),
            Some(wrong_lexicon_hash),
        ),
        "lexicon_version_mismatch",
    ));

    let mut wrong_version = good.clone();
    wrong_version[10..12].copy_from_slice(&(MODEL_VERSION + 1).to_le_bytes());
    let (wrong_version_path, wrong_version_hash) = model_file(&wrong_version);
    cases.push((
        QuanpinContextRerankingConfig::new(
            true,
            Some(wrong_version_path.to_string_lossy().into_owned()),
            Some(wrong_version_hash),
        ),
        "unsupported_version",
    ));

    let mut corrupt = good;
    corrupt[0] = b'X';
    let (corrupt_path, corrupt_hash) = model_file(&corrupt);
    cases.push((
        QuanpinContextRerankingConfig::new(
            true,
            Some(corrupt_path.to_string_lossy().into_owned()),
            Some(corrupt_hash),
        ),
        "invalid_header",
    ));

    for (config, expected_error) in cases {
        let mut engine = engine_with_config(config, 20);
        let status = engine.quanpin_context_reranking_status();
        assert!(!status.enabled);
        assert_eq!(status.last_error_code, expected_error);
        assert_eq!(texts(&type_text(&mut engine, "tianqi")), base_order);
    }

    let mut no_hit = enabled_engine(20);
    assert_eq!(texts(&type_text(&mut no_hit, "yubao")), {
        let mut baseline = engine_with_config(QuanpinContextRerankingConfig::default(), 20);
        texts(&type_text(&mut baseline, "yubao"))
    });
}

#[test]
fn reset_backspace_scheme_switch_and_privacy_gate_clear_short_context() {
    fn assert_cleared(mut engine: ImeEngine, clear: impl FnOnce(&mut ImeEngine)) {
        select_text(&mut engine, "jintian", "今天");
        clear(&mut engine);
        let result = type_text(&mut engine, "tianqi");
        assert!(rank(&result, "天气") > 0);
    }

    assert_cleared(enabled_engine(20), |engine| {
        engine.reset();
    });
    assert_cleared(enabled_engine(20), |engine| {
        engine.backspace();
    });
    assert_cleared(enabled_engine(20), |engine| {
        engine.change_scheme("xiaohe").expect("xiaohe");
        engine.change_scheme("quanpin").expect("quanpin");
    });
    assert_cleared(enabled_engine(20), |engine| {
        engine.set_session_learning_allowed(false);
        engine.set_session_learning_allowed(true);
    });
}

#[test]
fn three_round_full_candidate_order_ids_and_paging_are_deterministic() {
    fn snapshot(engine: &mut ImeEngine) -> Vec<(String, String, u32)> {
        engine.reset();
        let mut state = type_text(engine, "tianqi");
        let raw = state.raw_input.clone();
        let mut output = Vec::new();
        loop {
            for candidate in &state.candidates {
                assert_eq!(state.raw_input, raw);
                assert!(!candidate.id.is_empty());
                output.push((
                    candidate.id.clone(),
                    candidate.text.clone(),
                    candidate.consumed_raw_len,
                ));
            }
            if !state.has_next_page {
                break;
            }
            state = engine.next_candidate_page().expect("next page");
        }
        output
    }

    let mut engine = enabled_engine(2);
    let first = snapshot(&mut engine);
    assert!(first.len() >= 3);
    assert_eq!(snapshot(&mut engine), first);
    assert_eq!(snapshot(&mut engine), first);
    let status = engine.quanpin_context_reranking_status();
    assert!(status.enabled);
    assert_eq!(status.model_version, MODEL_VERSION);
    assert!(status.model_load_micros <= MAX_MODEL_LOAD_MICROS);
}

#[test]
fn wrong_reranking_config_version_is_rejected_before_any_model_io() {
    let config = QuanpinContextRerankingConfig {
        config_version: QUANPIN_CONTEXT_RERANKING_CONFIG_VERSION + 1,
        ..QuanpinContextRerankingConfig::default()
    };
    let error = ImeEngine::new(EngineConfig {
        scheme_id: "quanpin".to_owned(),
        quanpin_context_reranking: config,
        ..EngineConfig::default()
    })
    .expect_err("invalid version");
    assert_eq!(error.to_string(), "invalid engine config");
}
