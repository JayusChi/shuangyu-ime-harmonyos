use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;
use std::sync::Arc;

use code_table_runtime::{
    query_exact_or_prefix, CodeTableBundle, CodeTableMatch, CodeTableStateMachine,
};

fn bundle_path() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(
        "../../../dictionaries/generated/xiaohe-yinxing-production/xiaohe-yinxing-production.hsyx",
    )
}

fn load_bundle() -> CodeTableBundle {
    CodeTableBundle::load_file(bundle_path()).expect("formal production bundle must load")
}

fn all_codes(bundle: &CodeTableBundle) -> BTreeSet<String> {
    bundle
        .categories
        .iter()
        .flat_map(|category| category.lexicon.entries.iter())
        .map(|entry| entry.pinyin_key.clone())
        .collect()
}

#[test]
fn formal_bundle_queries_are_stable_across_code_lengths_and_categories() {
    let bundle = load_bundle();
    assert_eq!(bundle.bundle_id, "xiaohe-yinxing-production");
    assert_eq!(bundle.categories.len(), 11);
    assert!(bundle.guide.is_none());
    assert!(bundle.production_metadata.is_some());
    assert_eq!(
        bundle
            .user_rules
            .as_ref()
            .expect("user rules")
            .stats()
            .fixed,
        36
    );

    let defaults = bundle.default_enabled_category_ids();
    assert_eq!(
        defaults,
        [
            "core",
            "category-secondary",
            "quick-symbol",
            "one-key-secondary",
            "out-of-table-character",
            "symbol",
            "symbol-group",
        ]
    );
    let enabled = bundle
        .categories
        .iter()
        .map(|category| category.id.clone())
        .collect::<Vec<_>>();
    let category_rank = enabled
        .iter()
        .enumerate()
        .map(|(index, id)| (id.as_str(), index))
        .collect::<BTreeMap<_, _>>();

    for code in ["a", "an", "anf", "anbm"] {
        let first = query_exact_or_prefix(&bundle, &enabled, code, usize::MAX);
        let second = query_exact_or_prefix(&bundle, &enabled, code, usize::MAX);
        assert_eq!(first, second, "query must be deterministic for {code}");
        assert_eq!(first.match_type, Some(CodeTableMatch::Exact));
        assert!(!first.candidates.is_empty(), "missing exact query {code}");
        assert!(first
            .candidates
            .iter()
            .all(|candidate| candidate.code == code));
        let mut seen = BTreeSet::new();
        assert!(first
            .candidates
            .iter()
            .all(|candidate| seen.insert(candidate.text.as_str())));
        for pair in first.candidates.windows(2) {
            let left = category_rank[pair[0].category_id.as_str()];
            let right = category_rank[pair[1].category_id.as_str()];
            assert!(left <= right);
            if left == right {
                assert!(pair[0].source_order < pair[1].source_order);
            }
        }
    }

    let empty = query_exact_or_prefix(&bundle, &enabled, "", usize::MAX);
    assert!(empty.candidates.is_empty());
    assert_eq!(empty.match_type, None);

    let codes = all_codes(&bundle);
    let missing = ('a'..='z')
        .flat_map(|a| ('a'..='z').map(move |b| format!("{a}{b}{a}{b}")))
        .find(|code| !codes.iter().any(|known| known.starts_with(code)))
        .expect("a no-match code");
    let no_match = query_exact_or_prefix(&bundle, &enabled, &missing, usize::MAX);
    assert_eq!(no_match.match_type, Some(CodeTableMatch::Prefix));
    assert!(no_match.candidates.is_empty());

    let prefix = codes
        .iter()
        .filter(|code| code.len() > 1)
        .flat_map(|code| (1..code.len()).map(move |length| &code[..length]))
        .find(|prefix| !codes.contains(*prefix))
        .expect("prefix without exact record");
    let prefix_result = query_exact_or_prefix(&bundle, &enabled, prefix, usize::MAX);
    assert_eq!(prefix_result.match_type, Some(CodeTableMatch::Prefix));
    assert!(!prefix_result.candidates.is_empty());
    assert!(prefix_result
        .candidates
        .iter()
        .all(|candidate| candidate.code.starts_with(prefix)));
}

#[test]
fn formal_bundle_supports_paging_user_overlay_and_tamper_detection() {
    let bundle = load_bundle();
    let mut counts = BTreeMap::<String, usize>::new();
    for category in &bundle.categories {
        for entry in &category.lexicon.entries {
            *counts.entry(entry.pinyin_key.clone()).or_default() += 1;
        }
    }
    let collision_code = counts
        .into_iter()
        .max_by_key(|(_, count)| *count)
        .filter(|(_, count)| *count > 2)
        .map(|(code, _)| code)
        .expect("large collision code");

    let bundle = Arc::new(bundle);
    let mut state = CodeTableStateMachine::new(Arc::clone(&bundle), 2, usize::MAX).unwrap();
    for key in collision_code.chars() {
        state.process_key(key).unwrap();
    }
    assert_eq!(state.current_candidates().len(), 2);
    assert!(state.has_next_page());
    let first_page = state.current_candidates().to_vec();
    state.next_page().unwrap();
    assert!(state.has_previous_page());
    assert_ne!(state.current_candidates(), first_page);
    state.previous_page().unwrap();
    assert_eq!(state.current_candidates(), first_page);

    let user_rules = bundle.user_rules.clone().expect("user rules");
    let fixed = user_rules
        .entries()
        .first()
        .expect("fixed user rule")
        .clone();
    let mut overlay = CodeTableStateMachine::new_with_user_lexicon(
        Arc::clone(&bundle),
        9,
        usize::MAX,
        Arc::new(user_rules),
    )
    .unwrap();
    for key in fixed.code.chars() {
        overlay.process_key(key).unwrap();
    }
    assert_eq!(
        overlay
            .all_candidates()
            .first()
            .map(|item| item.text.as_str()),
        Some(fixed.text.as_str())
    );

    let mut bytes = std::fs::read(bundle_path()).unwrap();
    let last = bytes.len() - 1;
    bytes[last] ^= 1;
    let error = CodeTableBundle::load_bytes(&bytes).expect_err("tamper must fail");
    assert!(error.to_string().contains("checksum"));
}
