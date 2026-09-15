use std::{fs, path::PathBuf};

use ime_engine::{EngineConfig, ImeEngine};
use lexicon_core::load_binary_lexicon;
use sentence_decoder::{DecodeLimits, SentenceDecoder, XiaoheSentenceQuery};
use shuangpin_parser::ShuangpinParser;

fn main() {
    let mut args = std::env::args().skip(1);
    let raw = args.next().unwrap_or_else(|| "hfyzxiwh".to_owned());
    let user_lexicon_path = args.next();
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../..")
        .join("dictionaries/generated/production.lex");
    let mut engine = ImeEngine::new(EngineConfig {
        scheme_id: "xiaohe".to_owned(),
        lexicon_path: Some(path.to_string_lossy().into_owned()),
        code_table_bundle_path: None,
        user_lexicon_path,
        code_table_action_fixture_path: None,
        code_table_action_fixture_sha256: None,
        candidate_page_size: 16,
        quanpin_features: Default::default(),
        quanpin_context_reranking: Default::default(),
    })
    .expect("engine");
    for key in raw.chars() {
        let state = if key == '\'' {
            engine.insert_segment_boundary().expect("boundary")
        } else {
            engine.process_key(key)
        };
        println!(
            "{}: {:?}",
            state.raw_input,
            state.candidates.iter().map(|c| &c.text).collect::<Vec<_>>()
        );
    }
    let parsed = ShuangpinParser::xiaohe().unwrap().process_str(&raw);
    println!("parse: {parsed:?}");
    if parsed.syllables.iter().all(|s| s.raw_code.len() == 2) {
        let lexicon = load_binary_lexicon(&fs::read(path).unwrap()).unwrap();
        for reading in ["hen you", "you xi wang", "xi wang", "hen", "you"] {
            for e in lexicon
                .entries
                .iter()
                .filter(|e| e.pinyin_key == reading)
                .take(16)
            {
                println!("lexicon: {} {} {}", e.word, e.pinyin_key, e.frequency);
            }
        }
        let decoder = SentenceDecoder::new(
            lexicon,
            DecodeLimits {
                beam_width: 128,
                max_output_paths: 128,
                max_output_candidates: 128,
                ..DecodeLimits::default()
            },
        )
        .unwrap();
        let syllables = parsed
            .syllables
            .iter()
            .map(|s| s.syllable.clone())
            .collect::<Vec<_>>();
        for c in decoder
            .decode_xiaohe_with_user_scores(
                XiaoheSentenceQuery {
                    raw_input: &raw,
                    syllables: &syllables,
                    initials: &vec![false; syllables.len()],
                    raw_lengths: &vec![2; syllables.len()],
                    fixed_words: &[],
                },
                |_| 0,
            )
            .unwrap()
            .candidates
            .iter()
            .take(32)
        {
            println!(
                "score={} text={} words={:?} path={}",
                c.score, c.text, c.words, c.path_key
            );
        }
    }
}
