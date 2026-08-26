use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::PathBuf;

use std::sync::Arc;

use code_table_runtime::{
    query_exact_or_prefix, CategoryKind, CategorySelectionSnapshot, CodeTableBundle,
    CodeTableMatch, CodeTableStateMachine,
};
use user_lexicon::UserLexiconAction;

const ARCHIVE_SHA256: &str = "0963f9c28b750c375dbe693feaa2b1c9334ecd9c2c58df2e367138b22b82c942";
const SNAPSHOT: &str = include_str!("data/xiaohe_yinxing_stage11_6_3.tsv");
const CATEGORY_PROFILE: [(&str, usize); 12] = [
    ("core", 68_568),
    ("category-secondary", 1_690),
    ("quick-symbol", 16),
    ("one-key-secondary", 26),
    ("two-key-secondary", 66),
    ("out-of-table-character", 362),
    ("full-code-word", 464),
    ("symbol", 623),
    ("symbol-group", 707),
    ("rare-character", 498),
    ("full-code-character", 1_654),
    ("ok-spelling", 88_020),
];
const DEFAULT_CATEGORY_IDS: [&str; 8] = [
    "core",
    "category-secondary",
    "quick-symbol",
    "one-key-secondary",
    "out-of-table-character",
    "symbol",
    "symbol-group",
    "ok-spelling",
];

#[derive(Clone)]
struct ReferenceCandidate {
    text: String,
    category_id: String,
    source_order: u32,
    candidate_id: String,
}

struct ReferenceIndex {
    candidates: Vec<ReferenceCandidate>,
    exact: BTreeMap<String, Vec<usize>>,
    prefixes: BTreeMap<String, Vec<usize>>,
}

fn bundle_path() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(
        "../../../dictionaries/generated/xiaohe-yinxing-production/xiaohe-yinxing-production.hsyx",
    )
}

#[test]
fn unchanged_production_file_reuses_one_immutable_index() {
    let first = CodeTableBundle::load_frozen_production_file_shared(bundle_path())
        .expect("first shared load");
    let second = CodeTableBundle::load_frozen_production_file_shared(bundle_path())
        .expect("second shared load");
    assert!(Arc::ptr_eq(&first, &second));
}

#[test]
fn frozen_formal_bundle_matches_identity_profile_and_reference_snapshot() {
    let path = bundle_path();
    assert_eq!(
        fs::metadata(&path).expect("bundle metadata").len(),
        56_183_822
    );
    let bundle =
        CodeTableBundle::load_frozen_production_file(&path).expect("load frozen production bundle");
    bundle
        .validate_scheme_identity("xiaohe-yinxing")
        .expect("formal scheme identity");
    assert_eq!(bundle.bundle_id, "xiaohe-yinxing-production");
    assert!(bundle.guide.is_none());
    let metadata = bundle
        .production_metadata
        .as_ref()
        .expect("production metadata");
    assert_eq!(metadata.scheme_id, "xiaohe-yinxing");
    assert_eq!(metadata.data_version, "source-receipt-1");
    assert_eq!(metadata.converter_version, "yinxing-converter/1.0.0");
    assert_eq!(metadata.archive_file_count, 17);
    assert_eq!(
        bundle
            .user_rules
            .as_ref()
            .expect("fixed rules")
            .stats()
            .fixed,
        36
    );
    assert_eq!(
        bundle
            .categories
            .iter()
            .map(|category| (category.id.as_str(), category.lexicon.entries.len()))
            .collect::<Vec<_>>(),
        CATEGORY_PROFILE
    );
    assert_eq!(
        bundle
            .categories
            .iter()
            .map(|category| category.lexicon.entries.len())
            .sum::<usize>(),
        162_694
    );
    for category in &bundle.categories {
        assert_eq!(
            category.default_enabled,
            DEFAULT_CATEGORY_IDS.contains(&category.id.as_str())
        );
        let mut source_orders = category
            .lexicon
            .entries
            .iter()
            .map(|entry| entry.source_order)
            .collect::<Vec<_>>();
        source_orders.sort_unstable();
        assert!(source_orders
            .iter()
            .enumerate()
            .all(|(index, source_order)| *source_order as usize == index));
    }
    let category_contract = CategorySelectionSnapshot::defaults(&bundle).unwrap();
    assert_eq!(
        category_contract.enabled_category_ids(),
        DEFAULT_CATEGORY_IDS
    );
    assert_eq!(
        category_contract
            .definitions()
            .iter()
            .map(|definition| (
                definition.id.as_str(),
                definition.kind,
                definition.order,
                definition.default_enabled,
                definition.required,
                definition.user_toggleable,
                definition.entry_count,
            ))
            .collect::<Vec<_>>(),
        vec![
            ("core", CategoryKind::Primary, 0, true, true, false, 68_568),
            (
                "category-secondary",
                CategoryKind::PrimaryEquivalent,
                1,
                true,
                false,
                true,
                1_690,
            ),
            (
                "quick-symbol",
                CategoryKind::Extension,
                2,
                true,
                false,
                true,
                16,
            ),
            (
                "one-key-secondary",
                CategoryKind::PrimaryEquivalent,
                3,
                true,
                false,
                true,
                26,
            ),
            (
                "two-key-secondary",
                CategoryKind::PrimaryEquivalent,
                4,
                false,
                false,
                true,
                66,
            ),
            (
                "out-of-table-character",
                CategoryKind::Extension,
                5,
                true,
                false,
                true,
                362,
            ),
            (
                "full-code-word",
                CategoryKind::Extension,
                6,
                false,
                false,
                true,
                464,
            ),
            ("symbol", CategoryKind::Extension, 7, true, false, true, 623,),
            (
                "symbol-group",
                CategoryKind::Extension,
                8,
                true,
                false,
                true,
                707,
            ),
            (
                "rare-character",
                CategoryKind::Extension,
                9,
                false,
                false,
                true,
                498,
            ),
            (
                "full-code-character",
                CategoryKind::Extension,
                10,
                false,
                false,
                true,
                1_654,
            ),
            (
                "ok-spelling",
                CategoryKind::Extension,
                11,
                true,
                false,
                true,
                88_020,
            ),
        ]
    );

    let reference = build_reference(&bundle);
    let enabled = CATEGORY_PROFILE
        .iter()
        .map(|(id, _)| (*id).to_owned())
        .collect::<Vec<_>>();
    let mut case_count = 0;
    for line in SNAPSHOT.lines().filter(|line| line.starts_with("CASE\t")) {
        case_count += 1;
        let fields = line.split('\t').collect::<Vec<_>>();
        assert_eq!(fields.len(), 12, "snapshot row: {line}");
        let case_id = fields[1];
        let code = fields[2];
        let expected_match = fields[3];
        let expected_before = fields[4].parse::<usize>().expect("before_dedup");
        let expected_total = fields[5].parse::<usize>().expect("total");
        let expected_preview = split_pipe(fields[9]);
        let expected_categories = split_pipe(fields[10]);

        let (reference_match, indexes) = reference_result(&reference, code);
        assert_eq!(format!("{reference_match:?}"), expected_match, "{case_id}");
        assert_eq!(indexes.len(), expected_before, "{case_id}");
        let reference_candidates = deduplicate(&reference, indexes);
        assert_eq!(reference_candidates.len(), expected_total, "{case_id}");

        let actual = query_exact_or_prefix(&bundle, &enabled, code, usize::MAX);
        assert_eq!(actual.match_type, Some(reference_match), "{case_id}");
        assert_eq!(actual.candidates.len(), expected_total, "{case_id}");
        assert_eq!(
            actual
                .candidates
                .iter()
                .map(|candidate| (
                    candidate.text.as_str(),
                    candidate.category_id.as_str(),
                    candidate.source_order,
                    candidate.id.as_str(),
                ))
                .collect::<Vec<_>>(),
            reference_candidates
                .iter()
                .map(|candidate| (
                    candidate.text.as_str(),
                    candidate.category_id.as_str(),
                    candidate.source_order,
                    candidate.candidate_id.as_str(),
                ))
                .collect::<Vec<_>>(),
            "{case_id}: runtime differs from independent index"
        );
        assert_eq!(
            actual
                .candidates
                .iter()
                .take(expected_preview.len())
                .map(|candidate| candidate.text.as_str())
                .collect::<Vec<_>>(),
            expected_preview,
            "{case_id}: preview"
        );
        let actual_categories = actual
            .candidates
            .iter()
            .map(|candidate| candidate.category_id.as_str())
            .collect::<BTreeSet<_>>()
            .into_iter()
            .collect::<Vec<_>>();
        assert_eq!(
            actual_categories, expected_categories,
            "{case_id}: categories"
        );
        if let Some(first) = actual.candidates.first() {
            assert_eq!(first.category_id, fields[6], "{case_id}");
            assert_eq!(first.source_order.to_string(), fields[7], "{case_id}");
            assert_eq!(first.id, fields[8], "{case_id}");
        } else {
            assert!(
                fields[6..=10].iter().all(|field| field.is_empty()),
                "{case_id}"
            );
        }
    }
    assert_eq!(case_count, 35);
    assert!(SNAPSHOT.contains(&format!("META\tbundle_sha256\t{ARCHIVE_SHA256}")));
}

fn build_reference(bundle: &CodeTableBundle) -> ReferenceIndex {
    let mut candidates = Vec::new();
    let mut exact = BTreeMap::<String, Vec<usize>>::new();
    let mut prefixes = BTreeMap::<String, Vec<usize>>::new();
    for category in &bundle.categories {
        if category.id == "quick-symbol" {
            continue;
        }
        let mut entries = category.lexicon.entries.iter().collect::<Vec<_>>();
        entries.sort_by_key(|entry| entry.source_order);
        for entry in entries {
            let index = candidates.len();
            candidates.push(ReferenceCandidate {
                text: entry.word.clone(),
                category_id: category.id.clone(),
                source_order: entry.source_order,
                candidate_id: format!(
                    "ct:{}:{}:{}",
                    bundle.bundle_id, category.id, entry.source_order
                ),
            });
            exact
                .entry(entry.pinyin_key.clone())
                .or_default()
                .push(index);
            for length in 1..entry.pinyin_key.len() {
                prefixes
                    .entry(entry.pinyin_key[..length].to_owned())
                    .or_default()
                    .push(index);
            }
        }
    }
    ReferenceIndex {
        candidates,
        exact,
        prefixes,
    }
}

fn reference_result<'a>(index: &'a ReferenceIndex, code: &str) -> (CodeTableMatch, &'a [usize]) {
    if let Some(indexes) = index.exact.get(code) {
        (CodeTableMatch::Exact, indexes)
    } else {
        (
            CodeTableMatch::Prefix,
            index.prefixes.get(code).map(Vec::as_slice).unwrap_or(&[]),
        )
    }
}

fn deduplicate<'a>(index: &'a ReferenceIndex, indexes: &[usize]) -> Vec<&'a ReferenceCandidate> {
    let mut seen = BTreeSet::new();
    indexes
        .iter()
        .map(|position| &index.candidates[*position])
        .filter(|candidate| seen.insert(candidate.text.as_str()))
        .collect()
}

fn split_pipe(value: &str) -> Vec<&str> {
    if value.is_empty() {
        Vec::new()
    } else {
        value.split('|').collect()
    }
}

#[test]
fn frozen_rule_profile_is_separate_complete_and_deterministic() {
    let bundle = CodeTableBundle::load_frozen_production_file(bundle_path())
        .expect("load frozen production bundle");
    let rules = bundle.user_rules.as_ref().expect("embedded rules");
    let stats = rules.stats();
    assert_eq!(stats.accepted, 36);
    assert_eq!(stats.effective, 36);
    assert_eq!(stats.added, 0);
    assert_eq!(stats.deleted, 0);
    assert_eq!(stats.fixed, 36);
    assert_eq!(stats.positioned, 0);
    assert!(rules
        .entries()
        .iter()
        .all(|entry| matches!(entry.action, UserLexiconAction::Fixed)));
    assert!(rules
        .entries()
        .iter()
        .enumerate()
        .all(|(index, entry)| entry.source_order as usize == index));
    assert_eq!(
        rules
            .entries()
            .iter()
            .map(|entry| (entry.code.as_str(), entry.text.as_str()))
            .collect::<BTreeSet<_>>()
            .len(),
        36
    );
    let groups =
        rules
            .entries()
            .iter()
            .fold(BTreeMap::<&str, usize>::new(), |mut groups, entry| {
                *groups.entry(entry.code.as_str()).or_default() += 1;
                groups
            });
    assert_eq!(groups.len(), 36);
    assert_eq!(groups.values().copied().max(), Some(1));
    assert_eq!(
        bundle
            .categories
            .iter()
            .map(|category| category.lexicon.entries.len())
            .sum::<usize>(),
        162_694
    );
}

#[test]
fn every_embedded_fixed_rule_applies_before_paging_without_mutating_system_queries() {
    let bundle = Arc::new(
        CodeTableBundle::load_frozen_production_file(bundle_path())
            .expect("load frozen production bundle"),
    );
    let enabled = bundle.default_enabled_category_ids();
    let rules = bundle.user_rules.clone().expect("embedded rules");
    let mut state = CodeTableStateMachine::new_with_user_lexicon(
        Arc::clone(&bundle),
        2,
        usize::MAX,
        Arc::new(rules.clone()),
    )
    .expect("formal state with embedded rules");

    for rule in rules.entries() {
        let pure_before = query_exact_or_prefix(&bundle, &enabled, &rule.code, usize::MAX);
        state.reset();
        for key in rule.code.chars() {
            state.process_key(key).expect("formal rule code");
        }
        assert_eq!(
            state
                .all_candidates()
                .first()
                .map(|candidate| candidate.text.as_str()),
            Some(rule.text.as_str()),
            "embedded fixed source_order={}",
            rule.source_order
        );

        let fixed_before = pure_before
            .candidates
            .iter()
            .find(|candidate| candidate.code == rule.code && candidate.text == rule.text);
        let fixed_after = state
            .all_candidates()
            .iter()
            .find(|candidate| candidate.code == rule.code && candidate.text == rule.text)
            .expect("fixed candidate after overlay");
        if let Some(fixed_before) = fixed_before {
            assert_eq!(fixed_after.id, fixed_before.id);
            assert_eq!(fixed_after.category_id, fixed_before.category_id);
            assert_eq!(fixed_after.source_order, fixed_before.source_order);
            assert_eq!(fixed_after.code, fixed_before.code);
        } else {
            assert_eq!(fixed_after.category_id, "user-lexicon");
            assert_eq!(fixed_after.code, rule.code);
        }

        let expected_all = state.all_candidates().to_vec();
        let mut paged = state.current_candidates().to_vec();
        while state.has_next_page() {
            state.next_page().expect("next embedded-rule page");
            paged.extend_from_slice(state.current_candidates());
        }
        assert_eq!(paged, expected_all);
        assert_eq!(
            query_exact_or_prefix(&bundle, &enabled, &rule.code, usize::MAX),
            pure_before,
            "raw system query changed after overlay"
        );
    }

    let unhit = bundle
        .categories
        .iter()
        .flat_map(|category| category.lexicon.entries.iter())
        .map(|entry| entry.pinyin_key.as_str())
        .find(|code| rules.entries_exact_or_prefix(code).is_empty())
        .expect("system code not matched by embedded rules")
        .to_owned();
    let pure = query_exact_or_prefix(&bundle, &enabled, &unhit, usize::MAX);
    state.reset();
    for key in unhit.chars() {
        state.process_key(key).expect("unhit formal code");
    }
    assert_eq!(state.all_candidates(), pure.candidates);
}
