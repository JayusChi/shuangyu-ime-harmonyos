use std::collections::BTreeSet;

use shuangpin_parser::{ParseStatus, QuanpinParser};

pub const QUANPIN_FEATURE_CONFIG_VERSION: u32 = 1;
pub const MAX_SPELLING_EDIT_DISTANCE: usize = 1;
// Single-edit recovery beyond 24 letters expands hundreds of low-yield paths
// on every key update. Preserve the raw composition and normal candidates for
// longer input while keeping typo recovery available for ordinary phrases.
pub const MAX_CORRECTABLE_RAW_LEN: usize = 24;
pub const MAX_SPELLING_VARIANTS: usize = 512;
pub const MAX_SPELLING_SEARCH_NODES: usize = 1024;
pub const MAX_CORRECTION_QUERY_PATHS: usize = 32;
pub const MAX_CANDIDATES_PER_EXPANSION_PATH: usize = 3;
pub const MAX_FUZZY_QUERY_PATHS: usize = 32;
pub const MAX_FUZZY_CHANGES_PER_PATH: usize = 2;
pub const MAX_COMBINED_QUERY_PATHS: usize = 8;
// Preserve error-kind fairness while preventing as many as sixteen expensive
// sentence decodes from dominating one key update. Extra-letter corrections
// keep four slots because the frozen corpus needs the third/fourth path;
// exact lexicon lookup still runs for every bounded correction path.
pub const MAX_SENTENCE_DECODE_PATHS_BY_SPELLING_KIND: [usize; 4] = [4, 2, 2, 2];
pub const MAX_FUZZY_SENTENCE_DECODE_PATHS: usize = 8;
pub const MAX_COMBINED_SENTENCE_DECODE_PATHS: usize = 4;
pub const MAX_MERGED_CANDIDATES: usize = 256;
pub const QUANPIN_EXPANSION_CACHE_CAPACITY: usize = 32;

#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
pub enum FuzzyOption {
    Nl,
    ZZh,
    CCh,
    SSh,
    InIng,
    EnEng,
    AnAng,
    IanIang,
}

impl FuzzyOption {
    pub const ALL: [Self; 8] = [
        Self::Nl,
        Self::ZZh,
        Self::CCh,
        Self::SSh,
        Self::InIng,
        Self::EnEng,
        Self::AnAng,
        Self::IanIang,
    ];

    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Nl => "n_l",
            Self::ZZh => "z_zh",
            Self::CCh => "c_ch",
            Self::SSh => "s_sh",
            Self::InIng => "in_ing",
            Self::EnEng => "en_eng",
            Self::AnAng => "an_ang",
            Self::IanIang => "ian_iang",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        Self::ALL
            .into_iter()
            .find(|option| option.as_str() == value)
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct QuanpinFeatureConfig {
    pub config_version: u32,
    pub spelling_correction_enabled: bool,
    pub fuzzy_options: BTreeSet<FuzzyOption>,
}

impl Default for QuanpinFeatureConfig {
    fn default() -> Self {
        Self {
            config_version: QUANPIN_FEATURE_CONFIG_VERSION,
            spelling_correction_enabled: false,
            fuzzy_options: BTreeSet::new(),
        }
    }
}

impl QuanpinFeatureConfig {
    pub fn new(
        spelling_correction_enabled: bool,
        fuzzy_options: impl IntoIterator<Item = FuzzyOption>,
    ) -> Self {
        Self {
            spelling_correction_enabled,
            fuzzy_options: fuzzy_options.into_iter().collect(),
            ..Self::default()
        }
    }

    pub fn validate(&self) -> bool {
        self.config_version == QUANPIN_FEATURE_CONFIG_VERSION
    }

    pub fn is_enabled(&self) -> bool {
        self.spelling_correction_enabled || !self.fuzzy_options.is_empty()
    }
}

#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
pub enum SpellingErrorKind {
    ExtraLetter,
    MissingLetter,
    NeighborKey,
    Transposed,
}

impl SpellingErrorKind {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::ExtraLetter => "extra_letter",
            Self::MissingLetter => "missing_letter",
            Self::NeighborKey => "neighbor_key",
            Self::Transposed => "transposed",
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ExpansionKind {
    Fuzzy { changes: usize },
    Spelling(SpellingErrorKind),
    SpellingAndFuzzy(SpellingErrorKind),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ExpansionPath {
    pub raw: String,
    pub syllables: Vec<String>,
    pub kind: ExpansionKind,
    pub source: String,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct QuanpinExpansionStats {
    pub spelling_variants_generated: usize,
    pub spelling_search_nodes: usize,
    pub correction_query_paths: usize,
    pub fuzzy_query_paths: usize,
    pub combined_query_paths: usize,
    pub candidate_expansions: usize,
    pub sentence_decoder_paths: usize,
    pub truncated_by_limit: bool,
    pub input_too_long: bool,
    pub correction_skipped_high_confidence: bool,
    pub correction_deferred_incomplete: bool,
    pub expansion_cache_hit: bool,
}

pub fn expansion_paths(
    raw_input: &str,
    config: &QuanpinFeatureConfig,
) -> (Vec<ExpansionPath>, QuanpinExpansionStats) {
    let mut stats = QuanpinExpansionStats::default();
    let raw = raw_input
        .chars()
        .filter(|character| *character != '\'')
        .collect::<String>();
    if raw.is_empty() || !raw.bytes().all(|byte| byte.is_ascii_lowercase()) {
        return (Vec::new(), stats);
    }

    let mut output = fuzzy_paths(&raw, &config.fuzzy_options, &mut stats);
    if !config.spelling_correction_enabled {
        return (output, stats);
    }
    if raw.len() > MAX_CORRECTABLE_RAW_LEN {
        stats.input_too_long = true;
        return (output, stats);
    }

    let corrected = spelling_paths(&raw, &mut stats);
    output.extend(corrected.iter().cloned());
    if !config.fuzzy_options.is_empty() {
        for path in corrected {
            if stats.combined_query_paths >= MAX_COMBINED_QUERY_PATHS {
                stats.truncated_by_limit = true;
                break;
            }
            for fuzzy in fuzzy_syllable_variants(&path.syllables, &config.fuzzy_options, 1) {
                if stats.combined_query_paths >= MAX_COMBINED_QUERY_PATHS {
                    stats.truncated_by_limit = true;
                    break;
                }
                stats.combined_query_paths += 1;
                output.push(ExpansionPath {
                    raw: fuzzy.concat(),
                    syllables: fuzzy,
                    kind: ExpansionKind::SpellingAndFuzzy(match path.kind {
                        ExpansionKind::Spelling(kind) => kind,
                        _ => unreachable!("spelling path kind"),
                    }),
                    source: format!("quanpin-correction-fuzzy:{}", path.source),
                });
            }
        }
    }
    (output, stats)
}

fn fuzzy_paths(
    raw: &str,
    options: &BTreeSet<FuzzyOption>,
    stats: &mut QuanpinExpansionStats,
) -> Vec<ExpansionPath> {
    if options.is_empty() {
        return Vec::new();
    }
    let combinations = parse_complete_paths(raw);
    let mut output = Vec::new();
    let mut seen = BTreeSet::new();
    for base in combinations {
        for changes in 1..=MAX_FUZZY_CHANGES_PER_PATH {
            for syllables in fuzzy_syllable_variants(&base, options, changes) {
                if !seen.insert(syllables.clone()) {
                    continue;
                }
                if stats.fuzzy_query_paths >= MAX_FUZZY_QUERY_PATHS {
                    stats.truncated_by_limit = true;
                    return output;
                }
                stats.fuzzy_query_paths += 1;
                output.push(ExpansionPath {
                    raw: syllables.concat(),
                    syllables,
                    kind: ExpansionKind::Fuzzy { changes },
                    source: format!("quanpin-fuzzy-{changes}"),
                });
            }
        }
    }
    output
}

fn spelling_paths(raw: &str, stats: &mut QuanpinExpansionStats) -> Vec<ExpansionPath> {
    let chars = raw.chars().collect::<Vec<_>>();
    let mut valid = Vec::new();
    let mut seen_raw = BTreeSet::new();

    for index in 0..chars.len() {
        let mut value = chars.clone();
        value.remove(index);
        if !consider_spelling_variant(
            value.into_iter().collect(),
            SpellingErrorKind::ExtraLetter,
            raw,
            stats,
            &mut seen_raw,
            &mut valid,
        ) {
            break;
        }
    }
    if !spelling_search_limit_reached(stats) {
        for index in 0..chars.len().saturating_sub(1) {
            if chars[index] == chars[index + 1] {
                continue;
            }
            let mut value = chars.clone();
            value.swap(index, index + 1);
            if !consider_spelling_variant(
                value.into_iter().collect(),
                SpellingErrorKind::Transposed,
                raw,
                stats,
                &mut seen_raw,
                &mut valid,
            ) {
                break;
            }
        }
    }
    if !spelling_search_limit_reached(stats) {
        'neighbors: for (index, character) in chars.iter().enumerate() {
            for neighbor in qwerty_neighbors(*character).chars() {
                let mut value = chars.clone();
                value[index] = neighbor;
                if !consider_spelling_variant(
                    value.into_iter().collect(),
                    SpellingErrorKind::NeighborKey,
                    raw,
                    stats,
                    &mut seen_raw,
                    &mut valid,
                ) {
                    break 'neighbors;
                }
            }
        }
    }
    if !spelling_search_limit_reached(stats) {
        'insertions: for index in 0..=chars.len() {
            for inserted in 'a'..='z' {
                let mut value = chars.clone();
                value.insert(index, inserted);
                if !consider_spelling_variant(
                    value.into_iter().collect(),
                    SpellingErrorKind::MissingLetter,
                    raw,
                    stats,
                    &mut seen_raw,
                    &mut valid,
                ) {
                    break 'insertions;
                }
            }
        }
    }
    valid.sort_by(|left, right| {
        let left_kind = match left.kind {
            ExpansionKind::Spelling(kind) => kind,
            _ => unreachable!("spelling path kind"),
        };
        let right_kind = match right.kind {
            ExpansionKind::Spelling(kind) => kind,
            _ => unreachable!("spelling path kind"),
        };
        spelling_path_quality(left)
            .cmp(&spelling_path_quality(right))
            .then_with(|| left_kind.cmp(&right_kind))
            .then_with(|| left.raw.cmp(&right.raw))
    });

    let per_kind_limits = [6usize, 12, 8, MAX_CORRECTION_QUERY_PATHS - 26];
    let mut per_kind = [0usize; 4];
    let mut output = Vec::new();
    for path in valid {
        let kind = match path.kind {
            ExpansionKind::Spelling(kind) => kind,
            _ => unreachable!("spelling path kind"),
        };
        let index = match kind {
            SpellingErrorKind::ExtraLetter => 0,
            SpellingErrorKind::MissingLetter => 1,
            SpellingErrorKind::NeighborKey => 2,
            SpellingErrorKind::Transposed => 3,
        };
        if per_kind[index] >= per_kind_limits[index] {
            continue;
        }
        per_kind[index] += 1;
        output.push(path);
    }
    output.sort_by(|left, right| {
        let left_kind = match left.kind {
            ExpansionKind::Spelling(kind) => kind,
            _ => unreachable!("spelling path kind"),
        };
        let right_kind = match right.kind {
            ExpansionKind::Spelling(kind) => kind,
            _ => unreachable!("spelling path kind"),
        };
        left_kind
            .cmp(&right_kind)
            .then_with(|| spelling_path_quality(left).cmp(&spelling_path_quality(right)))
            .then_with(|| left.raw.cmp(&right.raw))
    });
    stats.correction_query_paths = output.len();
    if stats.spelling_variants_generated >= MAX_SPELLING_VARIANTS {
        stats.truncated_by_limit = true;
    }
    output
}

fn spelling_search_limit_reached(stats: &QuanpinExpansionStats) -> bool {
    stats.spelling_search_nodes >= MAX_SPELLING_SEARCH_NODES
        || stats.spelling_variants_generated >= MAX_SPELLING_VARIANTS
}

fn consider_spelling_variant(
    variant: String,
    kind: SpellingErrorKind,
    raw: &str,
    stats: &mut QuanpinExpansionStats,
    seen_raw: &mut BTreeSet<String>,
    valid: &mut Vec<ExpansionPath>,
) -> bool {
    if spelling_search_limit_reached(stats) {
        stats.truncated_by_limit = true;
        return false;
    }
    stats.spelling_search_nodes += 1;
    if variant == raw || !seen_raw.insert(variant.clone()) {
        return true;
    }
    stats.spelling_variants_generated += 1;
    if let Some(syllables) = parse_complete_paths(&variant).into_iter().next() {
        valid.push(ExpansionPath {
            raw: variant,
            syllables,
            kind: ExpansionKind::Spelling(kind),
            source: format!("quanpin-correction-{}", kind.as_str()),
        });
    }
    true
}

fn spelling_path_quality(path: &ExpansionPath) -> (usize, usize) {
    (
        path.syllables
            .iter()
            .filter(|syllable| syllable.len() == 1)
            .count(),
        path.syllables.len(),
    )
}

fn parse_complete_paths(raw: &str) -> Vec<Vec<String>> {
    let mut parser = QuanpinParser::new();
    let result = parser.process_str(raw);
    if !matches!(
        result.status,
        ParseStatus::Complete | ParseStatus::Ambiguous
    ) || !result.pending_code.is_empty()
    {
        return Vec::new();
    }
    let mut combinations = vec![result.current_pinyin];
    combinations.extend(result.pinyin_combinations);
    let mut unique = BTreeSet::new();
    combinations
        .into_iter()
        .filter_map(|combination| {
            let syllables = combination
                .split('\'')
                .filter(|value| !value.is_empty())
                .map(str::to_owned)
                .collect::<Vec<_>>();
            (!syllables.is_empty() && unique.insert(syllables.clone())).then_some(syllables)
        })
        .take(4)
        .collect()
}

fn fuzzy_syllable_variants(
    base: &[String],
    options: &BTreeSet<FuzzyOption>,
    exact_changes: usize,
) -> Vec<Vec<String>> {
    let mut level = BTreeSet::from([base.to_vec()]);
    for _ in 0..exact_changes {
        let mut next = BTreeSet::new();
        for syllables in level {
            for index in 0..syllables.len() {
                for option in options {
                    if let Some(changed) = apply_fuzzy(&syllables[index], *option) {
                        let mut variant = syllables.clone();
                        variant[index] = changed;
                        if variant != base {
                            next.insert(variant);
                        }
                    }
                }
            }
        }
        level = next;
    }
    level.into_iter().collect()
}

fn apply_fuzzy(syllable: &str, option: FuzzyOption) -> Option<String> {
    let changed = match option {
        FuzzyOption::Nl => swap_initial(syllable, "n", "l"),
        FuzzyOption::ZZh => swap_initial(syllable, "z", "zh"),
        FuzzyOption::CCh => swap_initial(syllable, "c", "ch"),
        FuzzyOption::SSh => swap_initial(syllable, "s", "sh"),
        FuzzyOption::InIng => swap_final(syllable, "in", "ing"),
        FuzzyOption::EnEng => swap_final(syllable, "en", "eng"),
        FuzzyOption::AnAng if syllable.ends_with("ian") || syllable.ends_with("iang") => None,
        FuzzyOption::AnAng => swap_final(syllable, "an", "ang"),
        FuzzyOption::IanIang => swap_final(syllable, "ian", "iang"),
    }?;
    is_legal_syllable(&changed).then_some(changed)
}

fn swap_initial(syllable: &str, short: &str, long: &str) -> Option<String> {
    if let Some(rest) = syllable.strip_prefix(long) {
        Some(format!("{short}{rest}"))
    } else {
        syllable
            .strip_prefix(short)
            .map(|rest| format!("{long}{rest}"))
    }
}

fn swap_final(syllable: &str, short: &str, long: &str) -> Option<String> {
    if let Some(stem) = syllable.strip_suffix(long) {
        Some(format!("{stem}{short}"))
    } else {
        syllable
            .strip_suffix(short)
            .map(|stem| format!("{stem}{long}"))
    }
}

fn is_legal_syllable(value: &str) -> bool {
    pinyin_syllable::all_syllables().any(|syllable| syllable == value)
}

pub fn qwerty_neighbors(key: char) -> &'static str {
    match key {
        'a' => "qwsz",
        'b' => "vghn",
        'c' => "xdfv",
        'd' => "ersfxc",
        'e' => "wsdr",
        'f' => "rtdgcv",
        'g' => "tyfhvb",
        'h' => "yugjbn",
        'i' => "ujko",
        'j' => "uikhmn",
        'k' => "iojlm",
        'l' => "opk",
        'm' => "njk",
        'n' => "bhjm",
        'o' => "iklp",
        'p' => "ol",
        'q' => "wa",
        'r' => "edft",
        's' => "weadzx",
        't' => "rfgy",
        'u' => "yhji",
        'v' => "cfgb",
        'w' => "qase",
        'x' => "zsdc",
        'y' => "tghu",
        'z' => "asx",
        _ => "",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_qwerty_key_has_symmetric_deterministic_neighbors() {
        for key in 'a'..='z' {
            let neighbors = qwerty_neighbors(key);
            assert!(!neighbors.is_empty(), "{key}");
            let mut unique = BTreeSet::new();
            for neighbor in neighbors.chars() {
                assert!(unique.insert(neighbor), "duplicate {key}->{neighbor}");
                assert!(
                    qwerty_neighbors(neighbor).contains(key),
                    "{key}<->{neighbor}"
                );
            }
        }
    }

    #[test]
    fn fuzzy_options_are_independent_and_syllable_scoped() {
        assert_eq!(apply_fuzzy("ni", FuzzyOption::Nl).as_deref(), Some("li"));
        assert_eq!(apply_fuzzy("li", FuzzyOption::Nl).as_deref(), Some("ni"));
        assert_eq!(apply_fuzzy("zi", FuzzyOption::ZZh).as_deref(), Some("zhi"));
        assert_eq!(
            apply_fuzzy("xin", FuzzyOption::InIng).as_deref(),
            Some("xing")
        );
        assert_eq!(
            apply_fuzzy("xian", FuzzyOption::IanIang).as_deref(),
            Some("xiang")
        );
        assert_eq!(apply_fuzzy("xian", FuzzyOption::AnAng), None);
        assert_eq!(apply_fuzzy("abc", FuzzyOption::Nl), None);
    }

    #[test]
    fn spelling_generation_is_bounded() {
        assert_eq!(MAX_SPELLING_EDIT_DISTANCE, 1);
        let config = QuanpinFeatureConfig::new(true, []);
        let (_, stats) = expansion_paths("nhihao", &config);
        assert!(stats.spelling_variants_generated > 0);
        assert!(stats.spelling_variants_generated <= MAX_SPELLING_VARIANTS);
        assert!(stats.spelling_search_nodes <= MAX_SPELLING_SEARCH_NODES);
        assert!(stats.correction_query_paths <= MAX_CORRECTION_QUERY_PATHS);
    }

    #[test]
    fn long_input_disables_only_spelling_expansion() {
        let config = QuanpinFeatureConfig::new(true, []);
        let (_, at_limit) = expansion_paths(&"a".repeat(MAX_CORRECTABLE_RAW_LEN), &config);
        assert!(!at_limit.input_too_long);
        assert!(at_limit.spelling_variants_generated > 0);

        let (paths, stats) = expansion_paths(&"a".repeat(MAX_CORRECTABLE_RAW_LEN + 1), &config);
        assert!(paths.is_empty());
        assert!(stats.input_too_long);
    }

    #[test]
    fn multi_fuzzy_and_combined_expansions_have_independent_hard_caps() {
        let config = QuanpinFeatureConfig::new(true, FuzzyOption::ALL);
        let (fuzzy_paths, fuzzy_stats) = expansion_paths("nananananananan", &config);
        assert!(fuzzy_stats.fuzzy_query_paths <= MAX_FUZZY_QUERY_PATHS);
        assert!(fuzzy_paths.iter().all(|path| match path.kind {
            ExpansionKind::Fuzzy { changes } => changes <= MAX_FUZZY_CHANGES_PER_PATH,
            _ => true,
        }));

        let (_, combined_stats) = expansion_paths("nananananananax", &config);
        assert!(combined_stats.correction_query_paths <= MAX_CORRECTION_QUERY_PATHS);
        assert!(combined_stats.fuzzy_query_paths <= MAX_FUZZY_QUERY_PATHS);
        assert!(combined_stats.combined_query_paths <= MAX_COMBINED_QUERY_PATHS);
    }
}
