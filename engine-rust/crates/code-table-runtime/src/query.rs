use std::collections::BTreeSet;

use lexicon_core::runtime_index::{entries_for_exact_key, find_prefix_indexes};
use lexicon_core::LexiconEntry;

use crate::bundle::{CodeTableBundle, CodeTableCategory};
use crate::CategorySelectionSnapshot;

const QUICK_SYMBOL_CATEGORY_ID: &str = "quick-symbol";

fn is_normal_query_category(category: &CodeTableCategory) -> bool {
    category.id != QUICK_SYMBOL_CATEGORY_ID
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CodeTableMatch {
    Exact,
    Prefix,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CodeTableQueryStrategy {
    ExactOnly,
    ExactOrPrefixFallback,
    /// Exact-code queries for the production Xiaohe Yinxing scheme.
    ///
    /// This intentionally remains distinct from `ExactOnly`: the named
    /// strategy is part of the scheme contract and lets the historical
    /// progressive behavior remain available for internal comparison and
    /// rollback without inferring behavior from code length or bundle names.
    DeterministicXiaoheYinxing,
    ProgressiveXiaoheYinxing,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CodeTableCandidate {
    pub id: String,
    pub text: String,
    pub code: String,
    pub category_id: String,
    pub source_order: u32,
    pub match_type: CodeTableMatch,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct QuerySnapshot {
    pub raw_code: String,
    pub match_type: Option<CodeTableMatch>,
    pub candidates: Vec<CodeTableCandidate>,
}

pub fn query_exact_or_prefix(
    bundle: &CodeTableBundle,
    enabled_category_ids: &[String],
    raw_code: &str,
    max_candidates: usize,
) -> QuerySnapshot {
    let Ok(selection) = CategorySelectionSnapshot::from_requested(bundle, enabled_category_ids)
    else {
        return QuerySnapshot {
            raw_code: raw_code.to_owned(),
            match_type: None,
            candidates: Vec::new(),
        };
    };
    query_with_strategy_and_snapshot(
        bundle,
        &selection,
        raw_code,
        max_candidates,
        CodeTableQueryStrategy::ExactOrPrefixFallback,
    )
}

pub fn query_exact_or_prefix_with_snapshot(
    bundle: &CodeTableBundle,
    selection: &CategorySelectionSnapshot,
    raw_code: &str,
    max_candidates: usize,
) -> QuerySnapshot {
    query_with_strategy_and_snapshot(
        bundle,
        selection,
        raw_code,
        max_candidates,
        CodeTableQueryStrategy::ExactOrPrefixFallback,
    )
}

pub fn query_with_strategy(
    bundle: &CodeTableBundle,
    enabled_category_ids: &[String],
    raw_code: &str,
    max_candidates: usize,
    strategy: CodeTableQueryStrategy,
) -> QuerySnapshot {
    let Ok(selection) = CategorySelectionSnapshot::from_requested(bundle, enabled_category_ids)
    else {
        return QuerySnapshot {
            raw_code: raw_code.to_owned(),
            match_type: None,
            candidates: Vec::new(),
        };
    };
    query_with_strategy_and_snapshot(bundle, &selection, raw_code, max_candidates, strategy)
}

pub fn query_with_strategy_and_snapshot(
    bundle: &CodeTableBundle,
    selection: &CategorySelectionSnapshot,
    raw_code: &str,
    max_candidates: usize,
    strategy: CodeTableQueryStrategy,
) -> QuerySnapshot {
    if raw_code.is_empty() || max_candidates == 0 {
        return QuerySnapshot {
            raw_code: raw_code.to_owned(),
            match_type: None,
            candidates: Vec::new(),
        };
    }
    let has_exact = bundle.categories.iter().any(|category| {
        is_normal_query_category(category)
            && selection.is_enabled(&category.id)
            && !entries_for_exact_key(&category.lexicon, raw_code, 1).is_empty()
    });
    let progressive = strategy == CodeTableQueryStrategy::ProgressiveXiaoheYinxing
        && (1..=3).contains(&raw_code.len());
    let phases = match strategy {
        CodeTableQueryStrategy::ExactOnly | CodeTableQueryStrategy::DeterministicXiaoheYinxing => {
            (true, false)
        }
        CodeTableQueryStrategy::ExactOrPrefixFallback => (has_exact, !has_exact),
        CodeTableQueryStrategy::ProgressiveXiaoheYinxing => {
            if progressive {
                (true, true)
            } else {
                (true, false)
            }
        }
    };
    let match_type = if has_exact || !phases.1 {
        CodeTableMatch::Exact
    } else {
        CodeTableMatch::Prefix
    };

    let mut seen_text = BTreeSet::new();
    let mut candidates = Vec::new();
    for (enabled, phase_match) in [
        (phases.0, CodeTableMatch::Exact),
        (phases.1, CodeTableMatch::Prefix),
    ] {
        if !enabled {
            continue;
        }
        for category in &bundle.categories {
            if !is_normal_query_category(category) || !selection.is_enabled(&category.id) {
                continue;
            }
            let entries = match phase_match {
                CodeTableMatch::Exact => exact_entries(category, raw_code),
                CodeTableMatch::Prefix => prefix_entries(category, raw_code),
            };
            for entry in entries {
                if phase_match == CodeTableMatch::Prefix && entry.pinyin_key.len() <= raw_code.len()
                {
                    continue;
                }
                if !seen_text.insert(entry.word.as_str()) {
                    continue;
                }
                candidates.push(CodeTableCandidate {
                    id: format!(
                        "ct:{}:{}:{}",
                        bundle.bundle_id, category.id, entry.source_order
                    ),
                    text: entry.word.clone(),
                    code: entry.pinyin_key.clone(),
                    category_id: category.id.clone(),
                    source_order: entry.source_order,
                    match_type: phase_match,
                });
                if candidates.len() == max_candidates {
                    return QuerySnapshot {
                        raw_code: raw_code.to_owned(),
                        match_type: Some(match_type),
                        candidates,
                    };
                }
            }
        }
    }
    QuerySnapshot {
        raw_code: raw_code.to_owned(),
        match_type: Some(match_type),
        candidates,
    }
}

pub(crate) fn exact_system_candidates(
    bundle: &CodeTableBundle,
    selection: &CategorySelectionSnapshot,
    code: &str,
) -> Vec<CodeTableCandidate> {
    collect_candidates(bundle, selection, code, CodeTableMatch::Exact)
}

pub(crate) fn longer_system_codes(
    bundle: &CodeTableBundle,
    selection: &CategorySelectionSnapshot,
    prefix: &str,
) -> BTreeSet<String> {
    if prefix.is_empty() {
        return BTreeSet::new();
    }
    let mut codes = BTreeSet::new();
    for category in &bundle.categories {
        if !is_normal_query_category(category) || !selection.is_enabled(&category.id) {
            continue;
        }
        for index in find_prefix_indexes(&category.lexicon, prefix, usize::MAX) {
            if index.pinyin_key.len() > prefix.len() {
                codes.insert(index.pinyin_key.clone());
            }
        }
    }
    codes
}

pub(crate) fn longer_system_candidates(
    bundle: &CodeTableBundle,
    selection: &CategorySelectionSnapshot,
    prefix: &str,
    max_candidates: usize,
) -> Vec<CodeTableCandidate> {
    if prefix.is_empty() || max_candidates == 0 {
        return Vec::new();
    }
    let mut seen_text = BTreeSet::new();
    let mut candidates = Vec::new();
    for category in &bundle.categories {
        if !is_normal_query_category(category) || !selection.is_enabled(&category.id) {
            continue;
        }
        for entry in prefix_entries(category, prefix) {
            if entry.pinyin_key.len() <= prefix.len() || !seen_text.insert(entry.word.as_str()) {
                continue;
            }
            candidates.push(CodeTableCandidate {
                id: format!(
                    "ct:{}:{}:{}",
                    bundle.bundle_id, category.id, entry.source_order
                ),
                text: entry.word.clone(),
                code: entry.pinyin_key.clone(),
                category_id: category.id.clone(),
                source_order: entry.source_order,
                match_type: CodeTableMatch::Prefix,
            });
            if candidates.len() == max_candidates {
                return candidates;
            }
        }
    }
    candidates
}

/// Queries Xiaohe Yinxing codes containing the backtick universal key.
/// An internal backtick matches one code position; a trailing backtick matches
/// the remaining suffix so `xk` can browse every shape code beginning with xk.
pub(crate) fn wildcard_system_candidates(
    bundle: &CodeTableBundle,
    selection: &CategorySelectionSnapshot,
    pattern: &str,
    max_candidates: usize,
) -> Vec<CodeTableCandidate> {
    if pattern.is_empty() || !pattern.contains('`') || max_candidates == 0 {
        return Vec::new();
    }
    let mut seen_text = BTreeSet::new();
    let mut candidates = Vec::new();
    for category in &bundle.categories {
        if !is_normal_query_category(category) || !selection.is_enabled(&category.id) {
            continue;
        }
        let mut entries = category
            .lexicon
            .entries
            .iter()
            .filter(|entry| wildcard_code_matches(pattern, &entry.pinyin_key))
            .collect::<Vec<_>>();
        entries.sort_by_key(|entry| entry.source_order);
        for entry in entries {
            if !seen_text.insert(entry.word.as_str()) {
                continue;
            }
            candidates.push(CodeTableCandidate {
                id: format!(
                    "ct:{}:{}:{}",
                    bundle.bundle_id, category.id, entry.source_order
                ),
                text: entry.word.clone(),
                code: entry.pinyin_key.clone(),
                category_id: category.id.clone(),
                source_order: entry.source_order,
                match_type: CodeTableMatch::Prefix,
            });
            if candidates.len() == max_candidates {
                return candidates;
            }
        }
    }
    candidates
}

fn wildcard_code_matches(pattern: &str, code: &str) -> bool {
    let pattern_bytes = pattern.as_bytes();
    let code_bytes = code.as_bytes();
    for (pattern_index, byte) in pattern_bytes.iter().copied().enumerate() {
        if byte == b'`' && pattern_index + 1 == pattern_bytes.len() {
            return pattern_index < code_bytes.len();
        }
        if pattern_index >= code_bytes.len() {
            return false;
        }
        if byte != b'`' && byte != code_bytes[pattern_index] {
            return false;
        }
    }
    // A non-trailing pattern remains prefix-searchable while the user enters
    // later known shape positions (for example ``k before ``kp).
    true
}

pub(crate) fn query_isolated_table(
    bundle_id: &str,
    category: &CodeTableCategory,
    raw_code: &str,
) -> QuerySnapshot {
    if raw_code.is_empty() {
        return QuerySnapshot {
            raw_code: raw_code.to_owned(),
            match_type: None,
            candidates: Vec::new(),
        };
    }
    let exact = !entries_for_exact_key(&category.lexicon, raw_code, 1).is_empty();
    let match_type = if exact {
        CodeTableMatch::Exact
    } else {
        CodeTableMatch::Prefix
    };
    let entries = if exact {
        exact_entries(category, raw_code)
    } else {
        prefix_entries(category, raw_code)
    };
    let candidates = entries
        .into_iter()
        .map(|entry| CodeTableCandidate {
            id: format!("ct:{bundle_id}:guide:{}", entry.source_order),
            text: entry.word.clone(),
            code: entry.pinyin_key.clone(),
            category_id: "guide".to_owned(),
            source_order: entry.source_order,
            match_type,
        })
        .collect();
    QuerySnapshot {
        raw_code: raw_code.to_owned(),
        match_type: Some(match_type),
        candidates,
    }
}

fn collect_candidates(
    bundle: &CodeTableBundle,
    selection: &CategorySelectionSnapshot,
    code: &str,
    match_type: CodeTableMatch,
) -> Vec<CodeTableCandidate> {
    let mut seen_text = BTreeSet::new();
    let mut candidates = Vec::new();
    for category in &bundle.categories {
        if !is_normal_query_category(category) || !selection.is_enabled(&category.id) {
            continue;
        }
        let entries = match match_type {
            CodeTableMatch::Exact => exact_entries(category, code),
            CodeTableMatch::Prefix => prefix_entries(category, code),
        };
        for entry in entries {
            if seen_text.insert(entry.word.as_str()) {
                candidates.push(CodeTableCandidate {
                    id: format!(
                        "ct:{}:{}:{}",
                        bundle.bundle_id, category.id, entry.source_order
                    ),
                    text: entry.word.clone(),
                    code: entry.pinyin_key.clone(),
                    category_id: category.id.clone(),
                    source_order: entry.source_order,
                    match_type,
                });
            }
        }
    }
    candidates
}

fn exact_entries<'a>(category: &'a CodeTableCategory, code: &str) -> Vec<&'a LexiconEntry> {
    let mut entries = entries_for_exact_key(&category.lexicon, code, usize::MAX);
    entries.sort_by_key(|entry| entry.source_order);
    entries
}

fn prefix_entries<'a>(category: &'a CodeTableCategory, prefix: &str) -> Vec<&'a LexiconEntry> {
    let mut entries = Vec::new();
    for index in find_prefix_indexes(&category.lexicon, prefix, usize::MAX) {
        let start = index.start as usize;
        let Some(end) = start.checked_add(index.len as usize) else {
            continue;
        };
        let Some(range) = category.lexicon.entries.get(start..end) else {
            continue;
        };
        entries.extend(range);
    }
    entries.sort_by_key(|entry| entry.source_order);
    entries
}
