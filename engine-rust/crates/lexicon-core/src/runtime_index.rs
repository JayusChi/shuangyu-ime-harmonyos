use crate::{BinaryLexicon, PinyinIndex};

/// Finds the exact pinyin-key index record using the sorted runtime index.
pub fn find_exact_index<'a>(lexicon: &'a BinaryLexicon, key: &str) -> Option<&'a PinyinIndex> {
    lexicon
        .index
        .binary_search_by(|record| record.pinyin_key.as_str().cmp(key))
        .ok()
        .and_then(|index| lexicon.index.get(index))
}

/// Returns the highest-frequency entries for an exact pinyin-key range,
/// capped by `limit`.
///
/// This keeps runtime users on top of the verified `BinaryLexicon` model rather
/// than parsing binary bytes or exposing unchecked index arithmetic. Binary
/// entries are stored in deterministic text order, so taking the first rows
/// before ranking would discard common homophones merely because of their
/// Unicode order.
pub fn entries_for_exact_key<'a>(
    lexicon: &'a BinaryLexicon,
    key: &str,
    limit: usize,
) -> Vec<&'a crate::LexiconEntry> {
    if limit == 0 {
        return Vec::new();
    }
    let Some(index) = find_exact_index(lexicon, key) else {
        return Vec::new();
    };
    let start = index.start as usize;
    let end = start
        .saturating_add(index.len as usize)
        .min(lexicon.entries.len());
    let mut entries = lexicon.entries[start..end].iter().collect::<Vec<_>>();
    entries.sort_by(|left, right| {
        right
            .frequency
            .cmp(&left.frequency)
            .then_with(|| left.word.cmp(&right.word))
            .then_with(|| left.source_key().cmp(&right.source_key()))
    });
    entries.truncate(limit);
    entries
}

/// Finds pinyin-key index records whose key starts with `prefix`.
///
/// The returned vector is capped by `limit`; empty prefixes return no records
/// so callers cannot accidentally enumerate the whole lexicon.
pub fn find_prefix_indexes<'a>(
    lexicon: &'a BinaryLexicon,
    prefix: &str,
    limit: usize,
) -> Vec<&'a PinyinIndex> {
    if prefix.is_empty() || limit == 0 {
        return Vec::new();
    }

    let mut cursor = lower_bound(&lexicon.index, prefix);
    let mut matches = Vec::new();
    while cursor < lexicon.index.len() && matches.len() < limit {
        let record = &lexicon.index[cursor];
        if !record.pinyin_key.starts_with(prefix) {
            break;
        }
        matches.push(record);
        cursor += 1;
    }
    matches
}

fn lower_bound(index: &[PinyinIndex], key: &str) -> usize {
    let mut left = 0;
    let mut right = index.len();
    while left < right {
        let mid = left + (right - left) / 2;
        if index[mid].pinyin_key.as_str() < key {
            left = mid + 1;
        } else {
            right = mid;
        }
    }
    left
}

#[cfg(test)]
mod tests {
    use crate::{build_binary_lexicon, load_binary_lexicon, LexiconEntry};

    use super::*;

    fn sample_lexicon() -> BinaryLexicon {
        let entries = vec![
            LexiconEntry::new(
                "你".to_owned(),
                "ni".to_owned(),
                vec!["ni".to_owned()],
                100,
                vec!["test".to_owned()],
            ),
            LexiconEntry::new(
                "你好".to_owned(),
                "ni hao".to_owned(),
                vec!["ni".to_owned(), "hao".to_owned()],
                90,
                vec!["test".to_owned()],
            ),
            LexiconEntry::new(
                "输入".to_owned(),
                "shu ru".to_owned(),
                vec!["shu".to_owned(), "ru".to_owned()],
                80,
                vec!["test".to_owned()],
            ),
        ];
        let bytes = build_binary_lexicon(&entries, 1, 1).unwrap();
        load_binary_lexicon(&bytes).unwrap()
    }

    #[test]
    fn finds_exact_index_range() {
        let lexicon = sample_lexicon();
        let index = find_exact_index(&lexicon, "ni hao").unwrap();

        assert_eq!(index.start, 1);
        assert_eq!(index.len, 1);
        assert_eq!(lexicon.entries[index.start as usize].word, "你好");
    }

    #[test]
    fn finds_bounded_prefix_ranges() {
        let lexicon = sample_lexicon();
        let indexes = find_prefix_indexes(&lexicon, "ni", 1);

        assert_eq!(indexes.len(), 1);
        assert_eq!(indexes[0].pinyin_key, "ni");

        let indexes = find_prefix_indexes(&lexicon, "ni", 8);
        assert_eq!(
            indexes
                .iter()
                .map(|record| record.pinyin_key.as_str())
                .collect::<Vec<_>>(),
            vec!["ni", "ni hao"]
        );
    }

    #[test]
    fn empty_prefix_never_returns_whole_lexicon() {
        let lexicon = sample_lexicon();

        assert!(find_prefix_indexes(&lexicon, "", 99).is_empty());
    }

    #[test]
    fn exact_range_cap_keeps_common_homophones_instead_of_text_order() {
        let entries = vec![
            LexiconEntry::new(
                "妹".to_owned(),
                "mei".to_owned(),
                vec!["mei".to_owned()],
                2_508,
                vec!["test".to_owned()],
            ),
            LexiconEntry::new(
                "没".to_owned(),
                "mei".to_owned(),
                vec!["mei".to_owned()],
                295_036,
                vec!["test".to_owned()],
            ),
            LexiconEntry::new(
                "美".to_owned(),
                "mei".to_owned(),
                vec!["mei".to_owned()],
                17_651,
                vec!["test".to_owned()],
            ),
        ];
        let bytes = build_binary_lexicon(&entries, 1, 1).unwrap();
        let lexicon = load_binary_lexicon(&bytes).unwrap();

        let top = entries_for_exact_key(&lexicon, "mei", 2)
            .into_iter()
            .map(|entry| entry.word.as_str())
            .collect::<Vec<_>>();

        assert_eq!(top, vec!["没", "美"]);
    }
}
