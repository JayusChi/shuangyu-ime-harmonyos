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
        "56183822",
        "\"bundle_sha256\"",
        "0963f9c28b750c375dbe693feaa2b1c9334ecd9c2c58df2e367138b22b82c942",
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
        56_183_822
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
                    9,
                    "user-lexicon-0e678f52bf07c8b8",
                ),
                (
                    "按到",
                    "andc",
                    "user-lexicon",
                    32,
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
                34_897,
                "ct:xiaohe-yinxing-production:core:34897",
            )],
        ),
        (
            "hc",
            &[(
                "好",
                "hc",
                "core",
                15_961,
                "ct:xiaohe-yinxing-production:core:15961",
            )],
        ),
        (
            "ui",
            &[
                (
                    "时间",
                    "uijm",
                    "user-lexicon",
                    15,
                    "user-lexicon-82fb3de0a4e7340b",
                ),
                (
                    "试试",
                    "uiui",
                    "user-lexicon",
                    17,
                    "user-lexicon-8e108f684f027787",
                ),
                (
                    "事",
                    "ui",
                    "core",
                    48_102,
                    "ct:xiaohe-yinxing-production:core:48102",
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
                    2,
                    "user-lexicon-e61a289af9b75d6f",
                ),
                (
                    "只能",
                    "ving",
                    "user-lexicon",
                    3,
                    "user-lexicon-ea6ff1d051418793",
                ),
                (
                    "只是",
                    "viui",
                    "user-lexicon",
                    8,
                    "user-lexicon-da195c3ad7218efb",
                ),
                (
                    "只会",
                    "vihv",
                    "user-lexicon",
                    28,
                    "user-lexicon-49b58bbe2cc171be",
                ),
                (
                    "只",
                    "vi",
                    "core",
                    51_834,
                    "ct:xiaohe-yinxing-production:core:51834",
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
                55_331,
                "ct:xiaohe-yinxing-production:core:55331",
            )],
        ),
        (
            "xm",
            &[
                (
                    "现金",
                    "xmjb",
                    "user-lexicon",
                    24,
                    "user-lexicon-b54819968e7f1570",
                ),
                (
                    "先",
                    "xm",
                    "core",
                    57_526,
                    "ct:xiaohe-yinxing-production:core:57526",
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
                    0,
                    "user-lexicon-5731f97642e9301a",
                ),
                (
                    "修",
                    "xq",
                    "core",
                    57_554,
                    "ct:xiaohe-yinxing-production:core:57554",
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
