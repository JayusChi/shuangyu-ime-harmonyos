use std::collections::{BTreeMap, BTreeSet};

use crate::{UserLexiconAction, UserLexiconEntry, UserLexiconSnapshot};

/// Applies exact-code hard rules after soft ranking and before pagination.
pub fn merge_candidates<T, Text, Make>(
    snapshot: &UserLexiconSnapshot,
    code: &str,
    base: Vec<T>,
    text_of: Text,
    make_user_candidate: Make,
) -> Vec<T>
where
    Text: for<'a> Fn(&'a T) -> &'a str,
    Make: Fn(&UserLexiconEntry) -> T,
{
    merge_with_entries(
        snapshot.entries_for_code(code),
        base,
        text_of,
        make_user_candidate,
    )
}

/// Applies exact rules or, when absent, deterministic longer-prefix rules.
pub fn merge_candidates_exact_or_prefix<T, Text, Make>(
    snapshot: &UserLexiconSnapshot,
    code: &str,
    base: Vec<T>,
    text_of: Text,
    make_user_candidate: Make,
) -> Vec<T>
where
    Text: for<'a> Fn(&'a T) -> &'a str,
    Make: Fn(&UserLexiconEntry) -> T,
{
    let exact = snapshot.entries_for_code(code);
    if exact.is_empty() {
        return merge_with_entries(
            snapshot.entries_for_longer_prefix(code),
            base,
            text_of,
            make_user_candidate,
        );
    }

    let exact_output = merge_with_entries(exact, base, &text_of, &make_user_candidate);
    if !exact_output.is_empty() {
        return exact_output;
    }

    // An exact delete-only rule set may hide every exact candidate. In that
    // case longer prefix user entries remain eligible, matching the system
    // query engine's exact-then-prefix fallback semantics.
    merge_with_entries(
        snapshot.entries_for_longer_prefix(code),
        Vec::new(),
        text_of,
        make_user_candidate,
    )
}

/// Applies code-table rules to candidates that retain their complete source code.
///
/// Rule selection keeps the user lexicon's frozen exact-or-prefix semantics, while
/// deletion itself matches the complete `(code, text)` key. Unlike
/// [`merge_candidates_exact_or_prefix`], this function never performs a second
/// prefix fallback after an exact rule set deletes its matches; the code-table
/// backend has already locked the system exact/prefix path before this overlay.
pub fn merge_code_table_candidates<T, Text, Code, Make>(
    snapshot: &UserLexiconSnapshot,
    raw_code: &str,
    base: Vec<T>,
    text_of: Text,
    code_of: Code,
    make_user_candidate: Make,
) -> Vec<T>
where
    Text: for<'a> Fn(&'a T) -> &'a str,
    Code: for<'a> Fn(&'a T) -> &'a str,
    Make: Fn(&UserLexiconEntry) -> T,
{
    let entries = snapshot.entries_exact_or_prefix(raw_code);
    merge_code_table_with_entries(entries, base, text_of, code_of, make_user_candidate)
}

/// Applies exact and strictly longer prefix rules to an already progressive
/// code-table candidate set. All hard rules are resolved before de-duplication
/// and pagination by the caller.
pub fn merge_code_table_progressive_candidates<T, Text, Code, Make>(
    snapshot: &UserLexiconSnapshot,
    raw_code: &str,
    base: Vec<T>,
    text_of: Text,
    code_of: Code,
    make_user_candidate: Make,
) -> Vec<T>
where
    Text: for<'a> Fn(&'a T) -> &'a str,
    Code: for<'a> Fn(&'a T) -> &'a str,
    Make: Fn(&UserLexiconEntry) -> T,
{
    merge_code_table_with_entries(
        snapshot.entries_for_progressive_prefix(raw_code),
        base,
        text_of,
        code_of,
        make_user_candidate,
    )
}

/// Applies longer-code user rules to source-ordered precise-match hints.
///
/// Hint rows deliberately keep the code table's physical order. Delete rules
/// still remove their exact `(code, text)` row, while add/fixed/position rules
/// may contribute a missing user row only after the surviving system rows.
/// They never promote one longer code ahead of another.
pub fn merge_code_table_hint_candidates<T, Text, Code, Make>(
    snapshot: &UserLexiconSnapshot,
    raw_code: &str,
    base: Vec<T>,
    text_of: Text,
    code_of: Code,
    make_user_candidate: Make,
) -> Vec<T>
where
    Text: for<'a> Fn(&'a T) -> &'a str,
    Code: for<'a> Fn(&'a T) -> &'a str,
    Make: Fn(&UserLexiconEntry) -> T,
{
    let entries = snapshot.entries_for_longer_prefix(raw_code);
    let deleted = entries
        .iter()
        .filter(|entry| matches!(entry.action, UserLexiconAction::Delete))
        .map(|entry| (entry.code.as_str(), entry.text.as_str()))
        .collect::<BTreeSet<_>>();
    let mut seen = BTreeSet::new();
    let mut output = Vec::new();

    for candidate in base {
        let key = (code_of(&candidate), text_of(&candidate));
        if deleted.contains(&key) || !seen.insert(text_of(&candidate).to_owned()) {
            continue;
        }
        output.push(candidate);
    }

    for entry in entries {
        if matches!(entry.action, UserLexiconAction::Delete) || !seen.insert(entry.text.clone()) {
            continue;
        }
        output.push(make_user_candidate(entry));
    }
    output
}

/// Applies only complete-code rules. This is the code-table uniqueness primitive:
/// longer user codes must not be counted as exact candidates.
pub fn merge_code_table_exact_candidates<T, Text, Code, Make>(
    snapshot: &UserLexiconSnapshot,
    code: &str,
    base: Vec<T>,
    text_of: Text,
    code_of: Code,
    make_user_candidate: Make,
) -> Vec<T>
where
    Text: for<'a> Fn(&'a T) -> &'a str,
    Code: for<'a> Fn(&'a T) -> &'a str,
    Make: Fn(&UserLexiconEntry) -> T,
{
    merge_code_table_with_entries(
        snapshot.entries_for_code(code),
        base,
        text_of,
        code_of,
        make_user_candidate,
    )
}

fn merge_code_table_with_entries<T, Text, Code, Make>(
    entries: Vec<&UserLexiconEntry>,
    base: Vec<T>,
    text_of: Text,
    code_of: Code,
    make_user_candidate: Make,
) -> Vec<T>
where
    Text: for<'a> Fn(&'a T) -> &'a str,
    Code: for<'a> Fn(&'a T) -> &'a str,
    Make: Fn(&UserLexiconEntry) -> T,
{
    if entries.is_empty() {
        return base;
    }

    let deleted = entries
        .iter()
        .filter(|entry| matches!(entry.action, UserLexiconAction::Delete))
        .map(|entry| (entry.code.as_str(), entry.text.as_str()))
        .collect::<BTreeSet<_>>();
    let promoted_texts = entries
        .iter()
        .filter(|entry| !matches!(entry.action, UserLexiconAction::Delete))
        .map(|entry| entry.text.as_str())
        .collect::<BTreeSet<_>>();

    let mut existing = BTreeMap::new();
    let mut remaining = Vec::new();
    for candidate in base {
        let text = text_of(&candidate).to_owned();
        let code = code_of(&candidate).to_owned();
        if deleted.contains(&(code.as_str(), text.as_str())) {
            continue;
        }
        if promoted_texts.contains(text.as_str()) {
            existing.entry((code, text)).or_insert(candidate);
        } else {
            remaining.push(candidate);
        }
    }

    let fixed_rule_count = entries
        .iter()
        .filter(|entry| matches!(entry.action, UserLexiconAction::Fixed))
        .count();
    let mut fixed = Vec::new();
    let mut added = Vec::new();
    let mut positioned: BTreeMap<u16, Vec<T>> = BTreeMap::new();
    for entry in entries {
        let key = (entry.code.clone(), entry.text.clone());
        match entry.action {
            UserLexiconAction::Delete => {}
            UserLexiconAction::Add => {
                let _ = existing.remove(&key);
                added.push(make_user_candidate(entry));
            }
            UserLexiconAction::Fixed => {
                fixed.push(
                    existing
                        .remove(&key)
                        .unwrap_or_else(|| make_user_candidate(entry)),
                );
            }
            UserLexiconAction::Position(position) => {
                positioned
                    .entry(position.max((fixed_rule_count + 1).min(u16::MAX as usize) as u16))
                    .or_default()
                    .push(
                        existing
                            .remove(&key)
                            .unwrap_or_else(|| make_user_candidate(entry)),
                    );
            }
        }
    }

    let fixed_count = fixed.len();
    // Ordinary user additions are an append-only overlay for an equal code:
    // keep every surviving system candidate ahead of them. Fixed and
    // positioned rules remain hard ordering controls applied around this base.
    fixed.extend(remaining);
    fixed.extend(added);
    let mut output = fixed;
    let mut protected_cursor = fixed_count;
    for (position, candidates) in positioned {
        let requested = usize::from(position.saturating_sub(1));
        let index = requested
            .max(fixed_count)
            .max(protected_cursor)
            .min(output.len());
        let count = candidates.len();
        output.splice(index..index, candidates);
        protected_cursor = index.saturating_add(count);
    }

    let mut seen = BTreeSet::new();
    output
        .into_iter()
        .filter(|candidate| seen.insert(text_of(candidate).to_owned()))
        .collect()
}

fn merge_with_entries<T, Text, Make>(
    entries: Vec<&UserLexiconEntry>,
    base: Vec<T>,
    text_of: Text,
    make_user_candidate: Make,
) -> Vec<T>
where
    Text: for<'a> Fn(&'a T) -> &'a str,
    Make: Fn(&UserLexiconEntry) -> T,
{
    if entries.is_empty() {
        return base;
    }

    let deleted = entries
        .iter()
        .filter(|entry| matches!(entry.action, UserLexiconAction::Delete))
        .map(|entry| entry.text.as_str())
        .collect::<BTreeSet<_>>();
    let promoted = entries
        .iter()
        .filter(|entry| !matches!(entry.action, UserLexiconAction::Delete))
        .map(|entry| entry.text.as_str())
        .collect::<BTreeSet<_>>();

    let mut existing = BTreeMap::new();
    let mut remaining = Vec::new();
    for candidate in base {
        let text = text_of(&candidate).to_owned();
        if deleted.contains(text.as_str()) {
            continue;
        }
        if promoted.contains(text.as_str()) && !existing.contains_key(&text) {
            existing.insert(text, candidate);
        } else if !promoted.contains(text.as_str()) {
            remaining.push(candidate);
        }
    }

    let fixed_rule_count = entries
        .iter()
        .filter(|entry| matches!(entry.action, UserLexiconAction::Fixed))
        .count();
    let mut fixed = Vec::new();
    let mut added = Vec::new();
    let mut positioned: BTreeMap<u16, Vec<T>> = BTreeMap::new();
    for entry in entries {
        let mut take_existing = || existing.remove(&entry.text);
        match entry.action {
            UserLexiconAction::Delete => {}
            UserLexiconAction::Add => {
                // A normal user entry replaces an identical system candidate so
                // its source remains visibly the user overlay.
                let _ = take_existing();
                added.push(make_user_candidate(entry));
            }
            UserLexiconAction::Fixed => {
                fixed.push(take_existing().unwrap_or_else(|| make_user_candidate(entry)));
            }
            UserLexiconAction::Position(position) => {
                positioned
                    .entry(position.max((fixed_rule_count + 1).min(u16::MAX as usize) as u16))
                    .or_default()
                    .push(take_existing().unwrap_or_else(|| make_user_candidate(entry)));
            }
        }
    }

    let fixed_count = fixed.len();
    // Keep ordinary user additions behind all surviving system candidates for
    // the same code. This also applies when an identical system row is replaced
    // by the user-overlay candidate during stable de-duplication.
    fixed.extend(remaining);
    fixed.extend(added);
    let mut output = fixed;
    let mut protected_cursor = fixed_count;
    for (position, candidates) in positioned {
        let requested = usize::from(position.saturating_sub(1));
        let index = requested
            .max(fixed_count)
            .max(protected_cursor)
            .min(output.len());
        let count = candidates.len();
        output.splice(index..index, candidates);
        protected_cursor = index.saturating_add(count);
    }

    // Stable text de-duplication is the last merge stage.
    let mut seen = BTreeSet::new();
    output
        .into_iter()
        .filter(|candidate| seen.insert(text_of(candidate).to_owned()))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::parse_user_lexicon_bytes;

    #[derive(Clone, Debug, Eq, PartialEq)]
    struct Candidate {
        text: String,
        code: String,
        source: &'static str,
    }

    fn candidate(text: &str) -> Candidate {
        Candidate {
            text: text.to_owned(),
            code: "abc".to_owned(),
            source: "system",
        }
    }

    fn apply(rules: &str, base: &[&str]) -> Vec<Candidate> {
        let snapshot = parse_user_lexicon_bytes("fixture.txt", rules.as_bytes())
            .unwrap()
            .into_snapshot();
        merge_candidates(
            &snapshot,
            "abc",
            base.iter().map(|text| candidate(text)).collect(),
            |item| item.text.as_str(),
            |entry| Candidate {
                text: entry.text.clone(),
                code: entry.code.clone(),
                source: "user",
            },
        )
    }

    fn texts(items: &[Candidate]) -> Vec<&str> {
        items.iter().map(|item| item.text.as_str()).collect()
    }

    #[test]
    fn delete_matches_only_code_and_text_and_is_reversible() {
        assert_eq!(
            texts(&apply("乙词\tabc#删\n", &["甲词", "乙词"])),
            vec!["甲词"]
        );
        assert_eq!(
            texts(&apply("乙词\tabc#删\n乙词\tabc\n", &["甲词", "乙词"])),
            vec!["甲词", "乙词"]
        );
    }

    #[test]
    fn fixed_system_and_normal_order_is_hard_and_deduplicated() {
        let output = apply(
            "固定乙\tabc#固\n普通甲\tabc\n已有词\tabc\n",
            &["系统甲", "已有词", "固定乙"],
        );
        assert_eq!(texts(&output), vec!["固定乙", "系统甲", "普通甲", "已有词"]);
        assert_eq!(output[3].source, "user");
    }

    #[test]
    fn code_table_normal_additions_follow_all_surviving_system_candidates() {
        let snapshot =
            parse_user_lexicon_bytes("fixture.txt", "普通甲\tabc\n已有词\tabc\n".as_bytes())
                .unwrap()
                .into_snapshot();
        let output = merge_code_table_candidates(
            &snapshot,
            "abc",
            vec![
                candidate("系统甲"),
                candidate("已有词"),
                candidate("系统乙"),
            ],
            |item| item.text.as_str(),
            |item| item.code.as_str(),
            |entry| Candidate {
                text: entry.text.clone(),
                code: entry.code.clone(),
                source: "user",
            },
        );

        assert_eq!(texts(&output), vec!["系统甲", "系统乙", "普通甲", "已有词"]);
        assert!(output[2..]
            .iter()
            .all(|candidate| candidate.source == "user"));
    }

    #[test]
    fn positions_are_one_based_grouped_and_cannot_cross_fixed_prefix() {
        let output = apply(
            "固定词\tabc#固\n第二甲\tabc#2\n第二乙\tabc#2\n首位请求\tabc#1\n末尾词\tabc#99\n",
            &["系统甲", "系统乙"],
        );
        assert_eq!(
            texts(&output),
            vec![
                "固定词",
                "第二甲",
                "第二乙",
                "首位请求",
                "系统甲",
                "系统乙",
                "末尾词"
            ]
        );
    }

    #[test]
    fn prefix_fallback_is_stable_and_empty_input_does_not_enumerate() {
        let snapshot =
            parse_user_lexicon_bytes("fixture.txt", "第一词\tabca\n第二词\tabcb\n".as_bytes())
                .unwrap()
                .into_snapshot();
        let output = merge_candidates_exact_or_prefix(
            &snapshot,
            "abc",
            Vec::<Candidate>::new(),
            |item| item.text.as_str(),
            |entry| Candidate {
                text: entry.text.clone(),
                code: entry.code.clone(),
                source: "user",
            },
        );
        assert_eq!(texts(&output), vec!["第一词", "第二词"]);
        assert!(snapshot.entries_exact_or_prefix("").is_empty());
    }

    #[test]
    fn exact_delete_allows_longer_prefix_fallback() {
        let snapshot =
            parse_user_lexicon_bytes("fixture.txt", "精确词\tabc#删\n前缀词\tabcd\n".as_bytes())
                .unwrap()
                .into_snapshot();
        let output = merge_candidates_exact_or_prefix(
            &snapshot,
            "abc",
            vec![candidate("精确词")],
            |item| item.text.as_str(),
            |entry| Candidate {
                text: entry.text.clone(),
                code: entry.code.clone(),
                source: "user",
            },
        );
        assert_eq!(texts(&output), vec!["前缀词"]);
    }

    #[test]
    fn code_table_delete_matches_complete_code_and_never_falls_back_again() {
        let snapshot = parse_user_lexicon_bytes(
            "fixture.txt",
            "同名词\tabc#删\n更长用户词\tabcd\n".as_bytes(),
        )
        .unwrap()
        .into_snapshot();
        let base = vec![
            Candidate {
                text: "同名词".to_owned(),
                code: "abc".to_owned(),
                source: "system",
            },
            Candidate {
                text: "同名词".to_owned(),
                code: "abcd".to_owned(),
                source: "system",
            },
            Candidate {
                text: "其他词".to_owned(),
                code: "abc".to_owned(),
                source: "system",
            },
        ];
        let output = merge_code_table_candidates(
            &snapshot,
            "abc",
            base,
            |item| item.text.as_str(),
            |item| item.code.as_str(),
            |entry| Candidate {
                text: entry.text.clone(),
                code: entry.code.clone(),
                source: "user",
            },
        );
        assert_eq!(texts(&output), vec!["同名词", "其他词"]);
        assert_eq!(output[0].code, "abcd");
        assert!(output.iter().all(|item| item.text != "更长用户词"));
    }

    #[test]
    fn code_table_overlay_preserves_fixed_prefix_and_global_positions() {
        let snapshot = parse_user_lexicon_bytes(
            "fixture.txt",
            concat!(
                "固定甲\tabc#固\n",
                "固定乙\tabc#固\n",
                "首位请求\tabc#1\n",
                "第二甲\tabc#2\n",
                "第二乙\tabc#2\n",
                "末尾词\tabc#99\n",
            )
            .as_bytes(),
        )
        .unwrap()
        .into_snapshot();
        let output = merge_code_table_candidates(
            &snapshot,
            "abc",
            vec![candidate("系统甲"), candidate("系统乙")],
            |item| item.text.as_str(),
            |item| item.code.as_str(),
            |entry| Candidate {
                text: entry.text.clone(),
                code: entry.code.clone(),
                source: "user",
            },
        );
        assert_eq!(
            texts(&output),
            vec![
                "固定甲",
                "固定乙",
                "首位请求",
                "第二甲",
                "第二乙",
                "系统甲",
                "系统乙",
                "末尾词",
            ]
        );
    }
}
