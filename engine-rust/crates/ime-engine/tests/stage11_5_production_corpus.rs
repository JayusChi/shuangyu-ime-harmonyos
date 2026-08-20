use std::fs;
use std::path::PathBuf;

use candidate_query::{CandidateQueryEngine, QueryConfig, QueryMode, QueryRequest};
use ime_engine::{EngineConfig, ImeEngine};
use lexicon_core::load_binary_lexicon;

#[test]
fn production_corpus_is_machine_executable_and_queryable() {
    let workspace = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let lexicon_path = workspace.join("../dictionaries/generated/production.lex");
    let lexicon = load_binary_lexicon(&fs::read(&lexicon_path).expect("production lexicon bytes"))
        .expect("production lexicon structure");
    let mut query_engine = CandidateQueryEngine::new(lexicon, QueryConfig::default());
    let mut engine = ImeEngine::new(EngineConfig {
        scheme_id: "xiaohe".to_owned(),
        lexicon_path: Some(lexicon_path.to_string_lossy().into_owned()),
        code_table_bundle_path: None,
        user_lexicon_path: None,
        code_table_action_fixture_path: None,
        code_table_action_fixture_sha256: None,
        candidate_page_size: 9,
        quanpin_features: Default::default(),
        quanpin_context_reranking: Default::default(),
    })
    .expect("production lexicon must load");

    let mut executed = 0_usize;
    for corpus_name in [
        "auto_generated.tsv",
        "human_high_value.tsv",
        "human_idioms.tsv",
    ] {
        let corpus_path = workspace
            .join("tests/fixtures/production_corpus")
            .join(corpus_name);
        let corpus = fs::read_to_string(&corpus_path).expect("production corpus must exist");
        for (line_index, line) in corpus.lines().skip(1).enumerate() {
            let fields = line.split('\t').collect::<Vec<_>>();
            assert_eq!(
                fields.len(),
                9,
                "invalid corpus fields at line {}",
                line_index + 2
            );
            engine.reset();
            let mut result = engine.reset();
            for key in fields[2].chars() {
                result = engine.process_key(key);
            }
            let expected_syllables = fields[3].split(' ').collect::<Vec<_>>();
            let mut expected_cursor = 0_usize;
            for actual in &result.parsed_syllables {
                if expected_cursor < expected_syllables.len()
                    && actual == expected_syllables[expected_cursor]
                {
                    expected_cursor += 1;
                }
            }
            assert_eq!(
                expected_cursor,
                expected_syllables.len(),
                "{} syllables: {:?}",
                fields[0],
                result.parsed_syllables
            );
            let allowed = fields[5]
                .split(',')
                .filter(|value| !value.is_empty())
                .collect::<Vec<_>>();
            let queried = query_engine
                .query(QueryRequest::new("xiaohe", fields[3], QueryMode::Exact, 9))
                .expect("generated reading must be valid");
            if !fields[4].is_empty() {
                assert_eq!(
                    queried
                        .candidates
                        .first()
                        .map(|candidate| candidate.text.as_str()),
                    Some(fields[4]),
                    "{} expected top candidate",
                    fields[0]
                );
            }
            let rank = queried
                .candidates
                .iter()
                .position(|candidate| allowed.contains(&candidate.text.as_str()))
                .map(|position| position + 1);
            let max_rank = fields[7]
                .parse::<usize>()
                .expect("max rank must be numeric");
            assert!(
                rank.is_some_and(|value| value <= max_rank),
                "{} allowed candidate rank: {:?}",
                fields[0],
                rank
            );
            executed += 1;
        }
    }
    let sentence_corpus = fs::read_to_string(
        workspace.join("tests/fixtures/production_corpus/human_short_sentences.tsv"),
    )
    .expect("short sentence corpus must exist");
    for (line_index, line) in sentence_corpus.lines().skip(1).enumerate() {
        let fields = line.split('\t').collect::<Vec<_>>();
        assert_eq!(
            fields.len(),
            9,
            "invalid sentence fields at line {}",
            line_index + 2
        );
        engine.reset();
        let mut result = engine.reset();
        for key in fields[2].chars() {
            result = engine.process_key(key);
        }
        assert_eq!(
            result.parsed_syllables.join(" "),
            fields[3],
            "{} sentence syllables",
            fields[0]
        );
        let rank = result
            .candidates
            .iter()
            .position(|candidate| candidate.text == fields[5])
            .map(|position| position + 1);
        let max_rank = fields[7].parse::<usize>().expect("sentence max rank");
        assert!(
            rank.is_some_and(|value| value <= max_rank),
            "{} sentence rank: {:?}, candidates: {:?}",
            fields[0],
            rank,
            result
                .candidates
                .iter()
                .map(|candidate| candidate.text.as_str())
                .collect::<Vec<_>>()
        );
        executed += 1;
    }

    let safety_corpus =
        fs::read_to_string(workspace.join("tests/fixtures/production_corpus/generated_safety.tsv"))
            .expect("safety corpus must exist");
    for (line_index, line) in safety_corpus.lines().skip(1).enumerate() {
        let fields = line.split('\t').collect::<Vec<_>>();
        assert_eq!(
            fields.len(),
            9,
            "invalid safety fields at line {}",
            line_index + 2
        );
        engine.reset();
        let mut result = engine.reset();
        for key in fields[2].chars() {
            result = engine.process_key(key);
        }
        if fields[1] == "incomplete" {
            assert!(
                result.pending_code.len() <= 1,
                "{} bounded pending input",
                fields[0]
            );
        } else {
            assert!(
                !result.success || result.candidates.is_empty(),
                "{} illegal input returned candidates",
                fields[0]
            );
        }
        executed += 1;
    }
    assert!(
        executed >= 5_100,
        "only {executed} production cases executed"
    );
}
