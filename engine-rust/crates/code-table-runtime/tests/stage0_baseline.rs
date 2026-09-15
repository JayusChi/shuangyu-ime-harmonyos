use std::path::PathBuf;
use std::sync::Arc;

use code_table_runtime::{CodeTableBundle, CodeTableStateMachine, PRODUCTION_SCHEME_ID};

const FORMAL_BASELINE: &str = include_str!(
    "../../../../dictionaries/audit/xiaohe-yinxing/baseline/formal_bundle_baseline.json"
);
const MANIFEST_SNAPSHOT: &str = include_str!(
    "../../../../dictionaries/audit/xiaohe-yinxing/baseline/formal_bundle_manifest_snapshot.json"
);
const CANDIDATE_BASELINE: &str = include_str!(
    "../../../../dictionaries/audit/xiaohe-yinxing/baseline/candidate_behavior_baseline.json"
);
const SHUANGPIN_BASELINE: &str = include_str!(
    "../../../../dictionaries/audit/xiaohe-yinxing/baseline/xiaohe_isolation_baseline.json"
);
type ExpectedCandidate<'a> = (&'a str, &'a str, &'a str, u32, &'a str);
type ExpectedCase<'a> = (&'a str, &'a [ExpectedCandidate<'a>]);

fn bundle_path() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(
        "../../../dictionaries/generated/xiaohe-yinxing-production/xiaohe-yinxing-production.hsyx",
    )
}

#[test]
fn stage0_machine_baselines_are_committed_path_clean_and_tied_to_frozen_bundle() {
    for baseline in [
        FORMAL_BASELINE,
        MANIFEST_SNAPSHOT,
        CANDIDATE_BASELINE,
        SHUANGPIN_BASELINE,
    ] {
        assert!(baseline.ends_with('\n'));
        assert!(!baseline.contains("C:\\"));
        assert!(!baseline.contains("/Users/"));
        assert!(!baseline.contains("\"generated_at\""));
        assert!(!baseline.contains("\"timestamp\""));
    }
    for expected in [
        "\"bundle_byte_size\"",
        "56104310",
        "\"bundle_sha256\"",
        "7c936b7e451fffba4463306d03188addb772efc38b414a6d593ea2d618f48bf0",
        "\"ordinary_record_count\"",
        "162694",
        "\"embedded_fixed_rule_count\"",
        "\"core_required\"",
        "\"archive_allowlist_complete\"",
        "\"unexpected_archive_files\"",
        "\"contains_sensitive_configuration\"",
    ] {
        assert!(FORMAL_BASELINE.contains(expected), "{expected}");
    }
    assert!(MANIFEST_SNAPSHOT.contains("\"category_count\""));
    assert!(CANDIDATE_BASELINE.contains("xiaohe-yinxing-stage0-candidates/1"));
    assert!(SHUANGPIN_BASELINE.contains("xiaohe-stage0-isolation/1"));
    assert!(SHUANGPIN_BASELINE.contains("\"xiaohe_result_restored\": true"));

    assert_eq!(
        std::fs::metadata(bundle_path())
            .expect("formal bundle")
            .len(),
        56_104_310
    );
    let bundle = CodeTableBundle::load_frozen_production_file(bundle_path())
        .expect("strict frozen loader verifies format, allowlist, hashes, and content");
    bundle
        .validate_scheme_identity(PRODUCTION_SCHEME_ID)
        .expect("formal scheme");
}

#[test]
fn stage0_required_default_candidate_profiles_remain_exact_and_ordered() {
    let bundle = Arc::new(
        CodeTableBundle::load_frozen_production_file(bundle_path()).expect("formal bundle"),
    );
    let rules = Arc::new(bundle.user_rules.clone().expect("embedded rules"));
    let cases: [ExpectedCase<'_>; 10] = [
        (
            "aa",
            &[("阿", "aa", "core", 5, "ct:xiaohe-yinxing-production:core:5")],
        ),
        (
            "ai",
            &[("爱", "ai", "core", 4, "ct:xiaohe-yinxing-production:core:4")],
        ),
        (
            "an",
            &[
                (
                    "按时",
                    "anui",
                    "user-lexicon",
                    10,
                    "user-lexicon-0e678f52bf07c8b8",
                ),
                (
                    "按到",
                    "andc",
                    "user-lexicon",
                    33,
                    "user-lexicon-e8eb21db1b7e774d",
                ),
                ("安", "an", "core", 2, "ct:xiaohe-yinxing-production:core:2"),
            ],
        ),
        (
            "ni",
            &[(
                "你",
                "ni",
                "core",
                34_898,
                "ct:xiaohe-yinxing-production:core:34898",
            )],
        ),
        (
            "hc",
            &[(
                "好",
                "hc",
                "core",
                15_962,
                "ct:xiaohe-yinxing-production:core:15962",
            )],
        ),
        (
            "ui",
            &[
                (
                    "时间",
                    "uijm",
                    "user-lexicon",
                    16,
                    "user-lexicon-82fb3de0a4e7340b",
                ),
                (
                    "试试",
                    "uiui",
                    "user-lexicon",
                    18,
                    "user-lexicon-8e108f684f027787",
                ),
                (
                    "事",
                    "ui",
                    "core",
                    48_103,
                    "ct:xiaohe-yinxing-production:core:48103",
                ),
            ],
        ),
        (
            "vi",
            &[
                (
                    "知道",
                    "vidc",
                    "user-lexicon",
                    3,
                    "user-lexicon-e61a289af9b75d6f",
                ),
                (
                    "只能",
                    "ving",
                    "user-lexicon",
                    4,
                    "user-lexicon-ea6ff1d051418793",
                ),
                (
                    "只是",
                    "viui",
                    "user-lexicon",
                    9,
                    "user-lexicon-da195c3ad7218efb",
                ),
                (
                    "只会",
                    "vihv",
                    "user-lexicon",
                    29,
                    "user-lexicon-49b58bbe2cc171be",
                ),
                (
                    "只",
                    "vi",
                    "core",
                    51_835,
                    "ct:xiaohe-yinxing-production:core:51835",
                ),
                (
                    "支持",
                    "vi",
                    "category-secondary",
                    292,
                    "ct:xiaohe-yinxing-production:category-secondary:292",
                ),
            ],
        ),
        (
            "wo",
            &[(
                "我",
                "wo",
                "core",
                55_332,
                "ct:xiaohe-yinxing-production:core:55332",
            )],
        ),
        (
            "xm",
            &[
                (
                    "现金",
                    "xmjb",
                    "user-lexicon",
                    25,
                    "user-lexicon-b54819968e7f1570",
                ),
                (
                    "先",
                    "xm",
                    "core",
                    57_527,
                    "ct:xiaohe-yinxing-production:core:57527",
                ),
                (
                    "下面",
                    "xm",
                    "category-secondary",
                    306,
                    "ct:xiaohe-yinxing-production:category-secondary:306",
                ),
            ],
        ),
        (
            "xq",
            &[
                (
                    "修正",
                    "xqvg",
                    "user-lexicon",
                    1,
                    "user-lexicon-5731f97642e9301a",
                ),
                (
                    "修",
                    "xq",
                    "core",
                    57_555,
                    "ct:xiaohe-yinxing-production:core:57555",
                ),
            ],
        ),
    ];

    for (code, expected) in cases {
        let mut state = CodeTableStateMachine::new_with_user_lexicon(
            Arc::clone(&bundle),
            9,
            usize::MAX,
            Arc::clone(&rules),
        )
        .expect("state");
        for key in code.chars() {
            let outcome = state.process_key(key).expect("key");
            assert!(outcome.commit_text.is_none(), "{code}");
        }
        assert_eq!(
            state
                .all_candidates()
                .iter()
                .map(|candidate| (
                    candidate.text.as_str(),
                    candidate.code.as_str(),
                    candidate.category_id.as_str(),
                    candidate.source_order,
                    candidate.id.as_str(),
                ))
                .collect::<Vec<_>>(),
            expected,
            "{code}"
        );
        assert_eq!(state.current_candidates(), state.all_candidates(), "{code}");
        assert!(!state.has_next_page(), "{code}");
    }
}
