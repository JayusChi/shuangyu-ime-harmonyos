use std::collections::{BTreeMap, BTreeSet};

use crate::model::{UserLexiconAction, UserLexiconEntry, UserLexiconStats};

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct UserLexiconSnapshot {
    entries: Vec<UserLexiconEntry>,
    by_code: BTreeMap<String, Vec<usize>>,
    stats: UserLexiconStats,
}

impl UserLexiconSnapshot {
    pub fn empty() -> Self {
        Self::default()
    }

    /// Builds a deterministic snapshot. The last `(code, text)` rule wins.
    pub fn from_entries(entries: Vec<UserLexiconEntry>, accepted_rows: usize) -> Self {
        let mut effective = BTreeMap::new();
        for entry in entries {
            effective.insert((entry.code.clone(), entry.text.clone()), entry);
        }
        let mut entries = effective.into_values().collect::<Vec<_>>();
        entries.sort_by(|left, right| {
            left.source_order
                .cmp(&right.source_order)
                .then_with(|| left.code.cmp(&right.code))
                .then_with(|| left.text.cmp(&right.text))
        });
        let mut by_code: BTreeMap<String, Vec<usize>> = BTreeMap::new();
        let mut stats = UserLexiconStats {
            accepted: accepted_rows,
            effective: entries.len(),
            ..UserLexiconStats::default()
        };
        for (index, entry) in entries.iter().enumerate() {
            by_code.entry(entry.code.clone()).or_default().push(index);
            match entry.action {
                UserLexiconAction::Add
                | UserLexiconAction::Direct
                | UserLexiconAction::OpenUrl
                | UserLexiconAction::OpenDirectory => stats.added += 1,
                UserLexiconAction::Delete => stats.deleted += 1,
                UserLexiconAction::Fixed => stats.fixed += 1,
                UserLexiconAction::Position(_) => stats.positioned += 1,
            }
        }
        Self {
            entries,
            by_code,
            stats,
        }
    }

    pub fn entries(&self) -> &[UserLexiconEntry] {
        &self.entries
    }

    pub const fn stats(&self) -> UserLexiconStats {
        self.stats
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    /// Retains external rules plus bundle-owned rules whose source category is
    /// enabled. This keeps built-in direct words and fixed rules atomic with
    /// their actual category instead of assigning every rule to one category.
    pub fn for_enabled_categories(&self, enabled_category_ids: &[String]) -> Self {
        let enabled = enabled_category_ids.iter().collect::<BTreeSet<_>>();
        let entries = self
            .entries
            .iter()
            .filter(|entry| {
                entry
                    .category_id
                    .as_ref()
                    .is_none_or(|category_id| enabled.contains(category_id))
            })
            .cloned()
            .collect::<Vec<_>>();
        let accepted = entries.len();
        Self::from_entries(entries, accepted)
    }

    pub fn entries_for_code(&self, code: &str) -> Vec<&UserLexiconEntry> {
        self.by_code
            .get(code)
            .into_iter()
            .flatten()
            .map(|index| &self.entries[*index])
            .collect()
    }

    /// Exact code rules when present, otherwise longer prefix codes in source order.
    pub fn entries_exact_or_prefix(&self, code: &str) -> Vec<&UserLexiconEntry> {
        let exact = self.entries_for_code(code);
        if !exact.is_empty() || code.is_empty() {
            return exact;
        }
        self.entries_for_longer_prefix(code)
    }

    /// Exact and strictly longer prefix-code rules in stable source order.
    /// Empty input never enumerates the entire user lexicon.
    pub fn entries_for_progressive_prefix(&self, code: &str) -> Vec<&UserLexiconEntry> {
        if code.is_empty() {
            return Vec::new();
        }
        self.entries
            .iter()
            .filter(|entry| entry.code.starts_with(code))
            .collect()
    }

    /// Longer prefix-code rules in stable source order. Empty input never
    /// enumerates the entire user lexicon.
    pub fn entries_for_longer_prefix(&self, code: &str) -> Vec<&UserLexiconEntry> {
        if code.is_empty() {
            return Vec::new();
        }
        self.entries
            .iter()
            .filter(|entry| entry.code.starts_with(code) && entry.code.len() > code.len())
            .collect()
    }

    pub fn deletes(&self, code: &str, text: &str) -> bool {
        self.entries_for_code(code)
            .into_iter()
            .any(|entry| entry.text == text && matches!(entry.action, UserLexiconAction::Delete))
    }

    pub fn normalized_bytes(&self) -> Vec<u8> {
        let mut output = String::new();
        for entry in &self.entries {
            output.push_str(&entry.text);
            if matches!(entry.action, UserLexiconAction::Direct) && entry.category_id.is_none() {
                if let Some(display_text) = &entry.display_text {
                    output.push(',');
                    output.push_str(display_text);
                }
            }
            output.push('\t');
            output.push_str(&entry.code);
            match entry.action {
                UserLexiconAction::Add => {}
                UserLexiconAction::Direct => output.push_str("#直"),
                UserLexiconAction::OpenUrl => output.push_str("#网页"),
                UserLexiconAction::OpenDirectory => output.push_str("#目录"),
                UserLexiconAction::Delete => output.push_str("#删"),
                UserLexiconAction::Fixed => output.push_str("#固"),
                UserLexiconAction::Position(position) => {
                    output.push('#');
                    output.push_str(&position.to_string());
                }
            }
            if let Some(category_id) = &entry.category_id {
                output.push('\t');
                output.push_str(entry.display_text.as_deref().unwrap_or(""));
                output.push('\t');
                output.push_str(category_id);
            } else if entry.action.external_action().is_some() {
                output.push('\t');
                output.push_str(entry.display_text.as_deref().unwrap_or(""));
            }
            output.push('\n');
        }
        output.into_bytes()
    }

    /// Stable revision used by product CRUD and batch compare-and-swap saves.
    pub fn revision(&self) -> String {
        let mut hash = 0xcbf2_9ce4_8422_2325_u64;
        for byte in self.normalized_bytes() {
            hash ^= u64::from(byte);
            hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
        }
        format!("{hash:016x}")
    }
}

/// Deterministically layers two already parsed immutable snapshots.
///
/// Entries from `base` keep their stable order before entries from `overlay`.
/// When both layers contain the same complete `(code, text)` key, the overlay
/// entry is later and therefore wins through the existing snapshot contract.
pub fn merge_user_lexicon_snapshots(
    base: &UserLexiconSnapshot,
    overlay: &UserLexiconSnapshot,
) -> UserLexiconSnapshot {
    let accepted = base.entries.len().saturating_add(overlay.entries.len());
    let mut entries = Vec::with_capacity(accepted);
    for entry in base.entries.iter().chain(&overlay.entries) {
        let mut entry = entry.clone();
        entry.source_order = u32::try_from(entries.len())
            .expect("two in-memory user lexicon snapshots exceed u32 source order");
        entries.push(entry);
    }
    UserLexiconSnapshot::from_entries(entries, accepted)
}

#[cfg(test)]
mod tests {
    use crate::{
        merge_user_lexicon_snapshots, parse_user_lexicon_bytes, UserLexiconAction,
        UserLexiconSnapshot,
    };

    fn snapshot(value: &str) -> UserLexiconSnapshot {
        parse_user_lexicon_bytes("fixture.txt", value.as_bytes())
            .unwrap()
            .into_snapshot()
    }

    #[test]
    fn later_rule_wins_and_keeps_later_source_order() {
        let snapshot = parse_user_lexicon_bytes(
            "fixture.txt",
            "测试词\tabc#删\n其他词\tabc\n测试词\tabc#固\n".as_bytes(),
        )
        .unwrap()
        .into_snapshot();
        let entry = snapshot
            .entries()
            .iter()
            .find(|entry| entry.text == "测试词")
            .unwrap();
        assert_eq!(entry.action, UserLexiconAction::Fixed);
        assert_eq!(entry.source_order, 2);
        assert_eq!(snapshot.stats().accepted, 3);
        assert_eq!(snapshot.stats().effective, 2);
    }

    #[test]
    fn normalized_snapshot_is_stable_and_has_no_bom() {
        let snapshot = parse_user_lexicon_bytes(
            "fixture.txt",
            "\u{feff}甲词\tabc#删\r\n乙词\tabc#2\r\n".as_bytes(),
        )
        .unwrap()
        .into_snapshot();
        assert_eq!(
            snapshot.normalized_bytes(),
            "甲词\tabc#删\n乙词\tabc#2\n".as_bytes()
        );
        assert_eq!(snapshot.revision(), snapshot.revision());
        assert_ne!(snapshot.revision(), UserLexiconSnapshot::empty().revision());
    }

    #[test]
    fn direct_snapshot_round_trips_commit_and_candidate_text() {
        let snapshot = snapshot("给予,给ʲⁱ̌予\tgwyu#直\n直通词\tztci#直\n");
        assert_eq!(
            snapshot.normalized_bytes(),
            "给予,给ʲⁱ̌予\tgwyu#直\n直通词\tztci#直\n".as_bytes()
        );
        assert_eq!(snapshot.stats().added, 2);
    }

    #[test]
    fn layered_empty_and_single_layer_snapshots_preserve_values() {
        let empty = UserLexiconSnapshot::empty();
        let built_in = snapshot("内置甲\tabc#固\n内置乙\tdef#固\n");
        let external = snapshot("外部甲\tghi#删\n");

        assert_eq!(merge_user_lexicon_snapshots(&empty, &empty), empty);
        assert_eq!(
            merge_user_lexicon_snapshots(&built_in, &empty).normalized_bytes(),
            built_in.normalized_bytes()
        );
        assert_eq!(
            merge_user_lexicon_snapshots(&empty, &external).normalized_bytes(),
            external.normalized_bytes()
        );
    }

    #[test]
    fn layered_different_keys_keep_base_then_overlay_order() {
        let built_in = snapshot("内置甲\tabc#固\n内置乙\tdef#固\n");
        let external = snapshot("外部甲\tghi\n外部乙\tjkl#2\n");
        let merged = merge_user_lexicon_snapshots(&built_in, &external);

        assert_eq!(
            merged
                .entries()
                .iter()
                .map(|entry| entry.text.as_str())
                .collect::<Vec<_>>(),
            ["内置甲", "内置乙", "外部甲", "外部乙"]
        );
        assert_eq!(
            merged
                .entries()
                .iter()
                .map(|entry| entry.source_order)
                .collect::<Vec<_>>(),
            [0, 1, 2, 3]
        );
    }

    #[test]
    fn overlay_replaces_same_key_for_every_supported_action() {
        for (marker, expected) in [
            ("#删", UserLexiconAction::Delete),
            ("", UserLexiconAction::Add),
            ("#直", UserLexiconAction::Direct),
            ("#7", UserLexiconAction::Position(7)),
            ("#固", UserLexiconAction::Fixed),
        ] {
            let built_in = snapshot("同键词\tabc#固\n保留词\tdef#固\n");
            let external = snapshot(&format!("同键词\tabc{marker}\n"));
            let merged = merge_user_lexicon_snapshots(&built_in, &external);
            let replaced = merged
                .entries()
                .iter()
                .find(|entry| entry.code == "abc" && entry.text == "同键词")
                .unwrap();
            assert_eq!(replaced.action, expected, "marker={marker}");
            assert_eq!(replaced.source_order, 2, "marker={marker}");
            assert_eq!(merged.entries().len(), 2, "marker={marker}");
        }
    }

    #[test]
    fn overlay_internal_later_rule_wins_before_layering() {
        let built_in = snapshot("同键词\tabc#固\n");
        let external = snapshot("同键词\tabc#删\n同键词\tabc#3\n");
        let merged = merge_user_lexicon_snapshots(&built_in, &external);

        assert_eq!(merged.entries().len(), 1);
        assert_eq!(merged.entries()[0].action, UserLexiconAction::Position(3));
        assert_eq!(merged.entries()[0].source_order, 1);
    }

    #[test]
    fn layering_is_repeatable_does_not_mutate_inputs_and_rebuilds_stats() {
        let built_in = snapshot("同键词\tabc#固\n内置保留\tdef#固\n");
        let external = snapshot("同键词\tabc#删\n外部固顶\tghi#固\n外部位置\tjkl#2\n");
        let built_in_before = built_in.clone();
        let external_before = external.clone();
        let first = merge_user_lexicon_snapshots(&built_in, &external);

        for _ in 0..32 {
            assert_eq!(merge_user_lexicon_snapshots(&built_in, &external), first);
        }
        assert_eq!(built_in, built_in_before);
        assert_eq!(external, external_before);
        assert_eq!(first.stats().accepted, 5);
        assert_eq!(first.stats().effective, 4);
        assert_eq!(first.stats().added, 0);
        assert_eq!(first.stats().deleted, 1);
        assert_eq!(first.stats().fixed, 2);
        assert_eq!(first.stats().positioned, 1);
        assert_eq!(
            first.stats().effective,
            first.stats().added
                + first.stats().deleted
                + first.stats().fixed
                + first.stats().positioned
        );
    }

    #[test]
    fn category_filter_keeps_external_rules_and_only_enabled_embedded_rules() {
        let embedded = crate::parse_embedded_user_lexicon_bytes(
            "embedded.txt",
            "核心直通\tabcd\t核心提示\tcore\n扩展直通\tefgh\t扩展提示\tfull-code-word\n".as_bytes(),
        )
        .unwrap()
        .into_snapshot();
        let external = snapshot("用户词\tuvwx\n");
        let merged = merge_user_lexicon_snapshots(&embedded, &external);
        let filtered = merged.for_enabled_categories(&["core".to_owned()]);

        assert_eq!(
            filtered
                .entries()
                .iter()
                .map(|entry| entry.text.as_str())
                .collect::<Vec<_>>(),
            ["核心直通", "用户词"]
        );
        assert_eq!(
            filtered.entries()[0].display_text.as_deref(),
            Some("核心提示")
        );
    }
}
