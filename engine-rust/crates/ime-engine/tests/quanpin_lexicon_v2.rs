use std::fs;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use ime_engine::{EngineConfig, ImeEngine, QuanpinFeatureConfig};

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..")
}

fn lexicon(profile: &str) -> PathBuf {
    repo_root()
        .join("dictionaries/generated/quanpin-v2")
        .join(format!("{profile}.lex"))
}

fn engine(path: &Path) -> ImeEngine {
    ImeEngine::new(EngineConfig {
        scheme_id: "quanpin".to_owned(),
        lexicon_path: Some(path.to_string_lossy().into_owned()),
        code_table_bundle_path: None,
        user_lexicon_path: None,
        code_table_action_fixture_path: None,
        code_table_action_fixture_sha256: None,
        candidate_page_size: 50,
        quanpin_features: QuanpinFeatureConfig::default(),
        quanpin_context_reranking: Default::default(),
    })
    .expect("V2 lexicon must load through the formal ImeEngine constructor")
}

fn texts(path: &Path, raw: &str) -> Vec<String> {
    let mut engine = engine(path);
    for key in raw.chars() {
        let state = engine.process_key(key);
        assert!(
            state.success,
            "formal engine rejected key {key:?} for {raw}"
        );
        assert!(
            state.commit_text.is_empty(),
            "typing caused automatic commit"
        );
    }
    let state = engine.current_state();
    assert_eq!(state.raw_input, raw, "rawInput was lost");
    state
        .candidates
        .into_iter()
        .map(|candidate| candidate.text)
        .collect()
}

fn domain_candidate_loaded(path: &Path, raw: &str, expected: &str) -> bool {
    let mut engine = engine(path);
    for key in raw.chars() {
        let state = engine.process_key(key);
        assert!(state.success);
        assert!(state.commit_text.is_empty());
    }
    engine
        .current_state()
        .candidates
        .into_iter()
        .any(|candidate| {
            candidate.text == expected && candidate.source.contains("project_v2_domain")
        })
}

#[test]
fn default_layer_recalls_colloquial_proper_and_active_hotwords() {
    let path = lexicon("default");
    for (raw, expected) in [
        ("dungehouxu", "蹲个后续"),
        ("hengqinyueao", "横琴粤澳"),
        ("hongmengkongjianjisuan", "鸿蒙空间计算"),
    ] {
        assert!(texts(&path, raw).iter().any(|text| text == expected));
    }
}

#[test]
fn optional_domains_are_off_by_default_and_recalled_when_selected() {
    let cases = [
        ("technology", "jiansuozengqiangshengcheng", "检索增强生成"),
        ("software", "jingtaitiaojian", "竞态条件"),
        ("education", "jiaoxuepingyitihua", "教学评一体化"),
        ("medical", "yingxiangzuxue", "影像组学"),
        ("finance", "fengxianjiaquanzichan", "风险加权资产"),
        ("legal", "gerenxinxibaohu", "个人信息保护"),
    ];
    for (profile, raw, expected) in cases {
        assert!(
            !domain_candidate_loaded(&lexicon("default"), raw, expected),
            "{profile} pack source unexpectedly enabled by default"
        );
        assert!(
            domain_candidate_loaded(&lexicon(profile), raw, expected),
            "{profile} pack did not recall {expected}"
        );
    }
}

#[test]
fn common_exact_top_candidates_are_unchanged() {
    let inherited = repo_root().join("dictionaries/generated/production.lex");
    let v2 = lexicon("default");
    for raw in ["ni", "shi", "zhongguo", "shurufa", "jintian"] {
        let before = texts(&inherited, raw);
        let after = texts(&v2, raw);
        assert_eq!(
            &before[..before.len().min(5)],
            &after[..after.len().min(5)],
            "clean exact candidates changed for {raw}"
        );
    }
}

#[test]
fn complete_candidates_are_deterministic_for_three_fresh_engines() {
    let path = lexicon("all_domains");
    let first = texts(&path, "duoyangxing");
    assert!(!first.is_empty());
    assert_eq!(first, texts(&path, "duoyangxing"));
    assert_eq!(first, texts(&path, "duoyangxing"));
}

#[test]
fn exact_long_phrases_are_not_evicted_by_composed_homophone_paths() {
    let path = lexicon("all_domains");
    for (raw, expected) in [
        ("yuegangaodawanqu", "粤港澳大湾区"),
        ("nizhouqitiaojie", "逆周期调节"),
        ("jiansuozengqiangshengcheng", "检索增强生成"),
    ] {
        let candidates = texts(&path, raw);
        assert_eq!(
            candidates.first().map(String::as_str),
            Some(expected),
            "audited exact phrase was not protected for {raw}"
        );
    }
}

#[test]
fn tampered_file_is_rejected_and_resource_limits_are_bounded() {
    let path = lexicon("all_domains");
    assert!(fs::metadata(&path).unwrap().len() < 5 * 1024 * 1024);
    let load_started = Instant::now();
    let _ = engine(&path);
    assert!(load_started.elapsed() < Duration::from_secs(10));
    let query_started = Instant::now();
    let _ = texts(&path, "jiansuozengqiangshengcheng");
    assert!(query_started.elapsed() < Duration::from_secs(10));

    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let tampered = std::env::temp_dir().join(format!("quanpin-v2-tampered-{nonce}.lex"));
    let mut bytes = fs::read(&path).unwrap();
    let last = bytes.len() - 1;
    bytes[last] ^= 1;
    fs::write(&tampered, bytes).unwrap();
    let result = ImeEngine::new(EngineConfig {
        scheme_id: "quanpin".to_owned(),
        lexicon_path: Some(tampered.to_string_lossy().into_owned()),
        ..EngineConfig::default()
    });
    assert!(result.is_err());
    let _ = fs::remove_file(tampered);
}
