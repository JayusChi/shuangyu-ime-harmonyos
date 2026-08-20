use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

use shuangpin_parser::{t9_signature, T9PinyinParser};

use crate::eval_json::{parse, serialize, serialize_line, JsonValue};
use crate::eval_sha256;

const AUTHORED_SOURCE: &str = "project-authored:pinyin9-quality-v1";
const DERIVED_SOURCE: &str = "project-derived:quanpin-quality-v1";
const QUANPIN_SOURCE: &str = "project-authored:quanpin-quality-baseline-v1";

#[derive(Clone, Debug)]
struct SourceCase {
    id: String,
    raw_input: String,
    expected_texts: Vec<String>,
    category: String,
    source: String,
    tags: Vec<String>,
}

#[derive(Clone, Debug)]
struct T9Case {
    id: String,
    split: String,
    category: String,
    input_kind: String,
    raw_digits: String,
    canonical_pinyin: String,
    expected_texts: Vec<String>,
    explicit_boundary_positions: Vec<usize>,
    source_id: String,
    source_sample_ids: Vec<String>,
    notes: String,
    layer: String,
}

pub fn create_pinyin9_dataset(
    quanpin_dataset_dir: &Path,
    output_dir: &Path,
) -> Result<String, String> {
    reject_nonempty_directory(output_dir)?;
    verify_quanpin_source_freeze(quanpin_dataset_dir)?;
    let source = load_quanpin_cases(quanpin_dataset_dir)?;
    let clean = source
        .iter()
        .filter(|case| case.tags.iter().any(|tag| tag == "clean"))
        .filter(|case| {
            matches!(
                case.category.as_str(),
                "common_character_word"
                    | "common_phrase_2_4"
                    | "modern_chat"
                    | "long_ambiguous"
                    | "proper_name_domain"
                    | "polyphone_homophone"
            )
        })
        .filter_map(|case| canonicalize_source(case).map(|canonical| (case.clone(), canonical)))
        .collect::<Vec<_>>();
    if clean.len() < 800 {
        return Err(format!(
            "only {} applicable frozen quanpin cases; expected at least 800",
            clean.len()
        ));
    }

    let mut public_by_pair = BTreeMap::<String, T9Case>::new();
    for (case, canonical) in &clean {
        let raw_digits = signature(canonical).expect("validated canonical pinyin");
        let pair = format!("{raw_digits}\0{}", case.expected_texts.join("\u{1f}"));
        if let Some(existing) = public_by_pair.get_mut(&pair) {
            existing.source_sample_ids.push(case.id.clone());
            existing.notes = "Deterministically converted public quanpin regressions with the same T9 signature and expectedTexts were collapsed into one case; every original sample ID remains in sourceSampleIds. This is not new blind data.".to_owned();
        } else {
            public_by_pair.insert(
                pair,
                T9Case {
                    id: format!("p9-public-{}", case.id),
                    split: "public-regression".to_owned(),
                    category: case.category.clone(),
                    input_kind: "clean".to_owned(),
                    raw_digits,
                    canonical_pinyin: canonical.clone(),
                    expected_texts: case.expected_texts.clone(),
                    explicit_boundary_positions: Vec::new(),
                    source_id: case.source.clone(),
                    source_sample_ids: vec![case.id.clone()],
                    notes: "Deterministically converted from the frozen public quanpin regression case; this is not new blind data.".to_owned(),
                    layer: "converted_public_regression".to_owned(),
                },
            );
        }
    }
    let public = public_by_pair.into_values().collect::<Vec<_>>();

    let specialized = build_specialized_cases(&clean)?;
    let mut dev = specialized
        .iter()
        .filter(|case| case.split == "dev")
        .cloned()
        .collect::<Vec<_>>();
    let mut blind = specialized
        .iter()
        .filter(|case| case.split == "blind")
        .cloned()
        .collect::<Vec<_>>();
    dev.sort_by(|left, right| left.id.cmp(&right.id));
    blind.sort_by(|left, right| left.id.cmp(&right.id));

    fs::create_dir_all(output_dir).map_err(|error| error.to_string())?;
    write_cases(&output_dir.join("dev.jsonl"), &dev)?;
    write_cases(&output_dir.join("blind.jsonl"), &blind)?;
    write_cases(&output_dir.join("public-regression.jsonl"), &public)?;
    fs::write(output_dir.join("sources.json"), serialize(&sources_json()))
        .map_err(|error| error.to_string())?;
    fs::write(output_dir.join("DATASET_PROVENANCE.md"), provenance())
        .map_err(|error| error.to_string())?;

    Ok(format!(
        "created {} T9-specialized cases ({} dev, {} blind) and {} deterministic public-regression conversions; no engine candidates were read",
        specialized.len(),
        dev.len(),
        blind.len(),
        public.len()
    ))
}

fn reject_nonempty_directory(path: &Path) -> Result<(), String> {
    if path.exists()
        && fs::read_dir(path)
            .map_err(|error| error.to_string())?
            .next()
            .is_some()
    {
        return Err(format!(
            "dataset directory is not empty: {}; frozen data must never be regenerated in place",
            path.display()
        ));
    }
    Ok(())
}

fn verify_quanpin_source_freeze(dataset_dir: &Path) -> Result<(), String> {
    let manifest_path = dataset_dir
        .parent()
        .ok_or_else(|| "quanpin dataset has no parent".to_owned())?
        .join("freeze-manifest.json");
    let bytes = fs::read(&manifest_path)
        .map_err(|error| format!("{}: {error}", manifest_path.display()))?;
    let manifest = parse(&bytes)?;
    let files = manifest
        .as_object()
        .and_then(|value| value.get("files"))
        .and_then(JsonValue::as_array)
        .ok_or_else(|| "quanpin freeze manifest is missing files".to_owned())?;
    for file in files {
        let object = file
            .as_object()
            .ok_or_else(|| "invalid quanpin manifest file entry".to_owned())?;
        let name = object
            .get("path")
            .and_then(JsonValue::as_str)
            .ok_or_else(|| "quanpin manifest file is missing path".to_owned())?;
        let expected_bytes = object
            .get("bytes")
            .and_then(JsonValue::as_u64)
            .ok_or_else(|| "quanpin manifest file is missing bytes".to_owned())?;
        let expected_hash = object
            .get("sha256")
            .and_then(JsonValue::as_str)
            .ok_or_else(|| "quanpin manifest file is missing SHA-256".to_owned())?;
        let actual = fs::read(dataset_dir.join(name))
            .map_err(|error| format!("frozen quanpin source {name}: {error}"))?;
        if actual.len() as u64 != expected_bytes || eval_sha256::hex(&actual) != expected_hash {
            return Err(format!("FROZEN_QUANPIN_SOURCE_HASH_MISMATCH: {name}"));
        }
    }
    Ok(())
}

fn load_quanpin_cases(dataset_dir: &Path) -> Result<Vec<SourceCase>, String> {
    let mut cases = Vec::new();
    for name in ["dev.jsonl", "blind.jsonl"] {
        let path = dataset_dir.join(name);
        let bytes = fs::read(&path).map_err(|error| format!("{}: {error}", path.display()))?;
        let text =
            std::str::from_utf8(&bytes).map_err(|_| format!("{} is not UTF-8", path.display()))?;
        for (index, line) in text
            .lines()
            .enumerate()
            .filter(|(_, line)| !line.is_empty())
        {
            let value = parse(line.as_bytes())?;
            let object = value
                .as_object()
                .ok_or_else(|| format!("{name}:{} must be an object", index + 1))?;
            let string = |field: &str| -> Result<String, String> {
                object
                    .get(field)
                    .and_then(JsonValue::as_str)
                    .map(str::to_owned)
                    .ok_or_else(|| format!("{name}:{} missing {field}", index + 1))
            };
            let strings = |field: &str| -> Result<Vec<String>, String> {
                object
                    .get(field)
                    .and_then(JsonValue::as_array)
                    .ok_or_else(|| format!("{name}:{} missing {field}", index + 1))?
                    .iter()
                    .map(|item| {
                        item.as_str()
                            .map(str::to_owned)
                            .ok_or_else(|| format!("{name}:{} invalid {field}", index + 1))
                    })
                    .collect()
            };
            cases.push(SourceCase {
                id: string("id")?,
                raw_input: string("rawInput")?,
                expected_texts: strings("expectedTexts")?,
                category: string("category")?,
                source: string("source")?,
                tags: strings("tags")?,
            });
        }
    }
    Ok(cases)
}

fn canonicalize_source(case: &SourceCase) -> Option<String> {
    let segments = segment_pinyin(&case.raw_input)?;
    Some(segments.join("'"))
}

fn segment_pinyin(raw: &str) -> Option<Vec<String>> {
    fn walk(
        raw: &str,
        offset: usize,
        syllables: &[&str],
        memo: &mut BTreeMap<usize, Option<Vec<String>>>,
    ) -> Option<Vec<String>> {
        if offset == raw.len() {
            return Some(Vec::new());
        }
        if let Some(value) = memo.get(&offset) {
            return value.clone();
        }
        let mut best: Option<Vec<String>> = None;
        for syllable in syllables {
            if raw[offset..].starts_with(syllable) {
                if let Some(mut tail) = walk(raw, offset + syllable.len(), syllables, memo) {
                    tail.insert(0, (*syllable).to_owned());
                    if best.as_ref().is_none_or(|current| {
                        tail.len() < current.len()
                            || (tail.len() == current.len() && tail < *current)
                    }) {
                        best = Some(tail);
                    }
                }
            }
        }
        memo.insert(offset, best.clone());
        best
    }

    let mut inventory = pinyin_syllable::all_syllables().collect::<Vec<_>>();
    inventory.sort_by(|left, right| right.len().cmp(&left.len()).then(left.cmp(right)));
    let mut output = Vec::new();
    for part in raw.split('\'') {
        if part.is_empty() {
            return None;
        }
        output.extend(walk(part, 0, &inventory, &mut BTreeMap::new())?);
    }
    Some(output)
}

fn signature(canonical: &str) -> Option<String> {
    let mut result = String::new();
    for syllable in canonical.split('\'') {
        result.push_str(&t9_signature(syllable)?);
    }
    Some(result)
}

#[allow(clippy::vec_init_then_push)]
fn build_specialized_cases(clean: &[(SourceCase, String)]) -> Result<Vec<T9Case>, String> {
    let pools = clean.iter().fold(
        BTreeMap::<String, Vec<(SourceCase, String)>>::new(),
        |mut pools, (case, canonical)| {
            pools
                .entry(case.category.clone())
                .or_default()
                .push((case.clone(), canonical.clone()));
            pools
        },
    );
    let pool = |name: &str| -> Result<&Vec<(SourceCase, String)>, String> {
        pools
            .get(name)
            .ok_or_else(|| format!("missing source pool {name}"))
    };
    let common = pool("common_character_word")?;
    let phrase = pool("common_phrase_2_4")?;
    let chat = pool("modern_chat")?;
    let long = pool("long_ambiguous")?;
    let proper = pool("proper_name_domain")?;
    let poly = pool("polyphone_homophone")?;

    let mut categories = Vec::<(String, Vec<T9Case>)>::new();
    categories.push(("common_character_word".to_owned(), authored_common_cases()?));
    categories.push((
        "common_phrase_2_4".to_owned(),
        derive_clean(phrase, 0, 32, "common_phrase_2_4", "方案", "fang'an")?,
    ));
    categories.push((
        "modern_chat".to_owned(),
        derive_clean(chat, 0, 32, "modern_chat", "呀", "ya")?,
    ));
    categories.push((
        "long_continuous".to_owned(),
        derive_clean(long, 0, 32, "long_continuous", "请确认", "qing'queren")?,
    ));
    categories.push((
        "segmentation_ambiguity".to_owned(),
        derive_clean(long, 32, 32, "segmentation_ambiguity", "以后", "yi'hou")?,
    ));
    categories.push((
        "polyphone_homophone".to_owned(),
        derive_clean(poly, 0, 32, "polyphone_homophone", "读音项", "du'yin'xiang")?,
    ));
    categories.push((
        "high_digit_collision".to_owned(),
        derive_collision(common, 32, "high_digit_collision", "安排", "an'pai")?,
    ));
    categories.push((
        "multiple_pinyin_paths".to_owned(),
        derive_collision(poly, 32, "multiple_pinyin_paths", "情况", "qing'kuang")?,
    ));
    categories.push((
        "abbreviation".to_owned(),
        derive_modified(
            chat,
            32,
            "abbreviation",
            "吗",
            "ma",
            Modification::Abbreviated,
        )?,
    ));
    categories.push((
        "incomplete_tail".to_owned(),
        derive_modified(
            chat,
            64,
            "incomplete_tail",
            "呢",
            "ne",
            Modification::Incomplete,
        )?,
    ));
    categories.push((
        "explicit_boundary".to_owned(),
        derive_modified(
            phrase,
            32,
            "explicit_boundary",
            "结果",
            "jie'guo",
            Modification::Boundary,
        )?,
    ));
    categories.push((
        "missing_digit".to_owned(),
        derive_modified(
            common,
            64,
            "missing_digit",
            "记录",
            "ji'lu",
            Modification::Missing,
        )?,
    ));
    categories.push((
        "extra_digit".to_owned(),
        derive_modified(
            common,
            96,
            "extra_digit",
            "内容",
            "nei'rong",
            Modification::Extra,
        )?,
    ));
    categories.push((
        "adjacent_key".to_owned(),
        derive_modified(
            common,
            128,
            "adjacent_key",
            "消息",
            "xiao'xi",
            Modification::Adjacent,
        )?,
    ));
    categories.push((
        "transposition".to_owned(),
        derive_modified(
            phrase,
            64,
            "transposition",
            "事项",
            "shi'xiang",
            Modification::Transpose,
        )?,
    ));
    categories.push(("fuzzy_dialect".to_owned(), derive_fuzzy(clean, 32)?));

    categories.push((
        "place_name".to_owned(),
        derive_clean(proper, 0, 40, "place_name", "新区", "xin'qu")?,
    ));
    categories.push((
        "person_name".to_owned(),
        derive_clean(proper, 40, 20, "person_name", "老师", "lao'shi")?,
    ));
    categories.push((
        "organization_name".to_owned(),
        derive_clean(
            proper,
            60,
            20,
            "organization_name",
            "办公室",
            "ban'gong'shi",
        )?,
    ));
    categories.push((
        "brand_domain".to_owned(),
        derive_clean(proper, 80, 28, "brand_domain", "平台", "ping'tai")?,
    ));

    let mut result = Vec::new();
    for (category_index, (category, mut cases)) in categories.into_iter().enumerate() {
        let dev_count = cases.len() / 4;
        if dev_count * 4 != cases.len() {
            return Err(format!(
                "category {category} does not permit exact 25/75 split"
            ));
        }
        for (index, case) in cases.iter_mut().enumerate() {
            case.split = if index < dev_count { "dev" } else { "blind" }.to_owned();
            case.id = format!("p9-v1-c{:02}-{:03}", category_index + 1, index + 1);
        }
        result.extend(cases);
    }
    if result.len() < 600 {
        return Err(format!(
            "specialized dataset has only {} cases",
            result.len()
        ));
    }
    Ok(result)
}

fn authored_common_cases() -> Result<Vec<T9Case>, String> {
    const VALUES: &str = "de|的\nle|了\nzai|在\nshi|是\nyou|有\nhe|和\njiu|就\nbu|不\nren|人\ndou|都\nyi|一\nshang|上\nye|也\nhen|很\ndao|到\nshuo|说\nyao|要\nqu|去\nhui|会\nzhe|着\ngei|给\nrang|让\nbei|被\ncong|从\ndui|对\nxiang|向\nyu|与\nji|及\ndeng|等\ngeng|更\nzui|最\nbie|别";
    VALUES
        .lines()
        .enumerate()
        .map(|(index, line)| {
            let (pinyin, text) = line
                .split_once('|')
                .ok_or_else(|| format!("invalid authored T9 common seed {line:?}"))?;
            let canonical = segment_pinyin(pinyin)
                .ok_or_else(|| format!("invalid authored pinyin {pinyin}"))?
                .join("'");
            Ok(base_t9_case(
                "common_character_word",
                "clean",
                signature(&canonical).expect("authored pinyin"),
                canonical,
                vec![text.to_owned()],
                Vec::new(),
                AUTHORED_SOURCE,
                vec![format!("pinyin9-authored-common-{:02}", index + 1)],
                "Hand-authored ordinary Mandarin character/word; independent of engine output.",
            ))
        })
        .collect()
}

fn derive_clean(
    source: &[(SourceCase, String)],
    start: usize,
    count: usize,
    category: &str,
    suffix_text: &str,
    suffix_pinyin: &str,
) -> Result<Vec<T9Case>, String> {
    source
        .iter()
        .skip(start)
        .take(count)
        .map(|base| {
            derived_case(
                base,
                category,
                suffix_text,
                suffix_pinyin,
                Modification::Clean,
            )
        })
        .collect()
}

fn derive_collision(
    source: &[(SourceCase, String)],
    start: usize,
    category: &str,
    suffix_text: &str,
    suffix_pinyin: &str,
) -> Result<Vec<T9Case>, String> {
    let mut result = Vec::new();
    for base in source.iter().cycle().skip(start).take(source.len()) {
        let case = derived_case(
            base,
            category,
            suffix_text,
            suffix_pinyin,
            Modification::Clean,
        )?;
        if published_path_count(&case.raw_digits) > 1 {
            result.push(case);
        }
        if result.len() == 32 {
            return Ok(result);
        }
    }
    Err(format!("not enough collision cases for {category}"))
}

fn derive_modified(
    source: &[(SourceCase, String)],
    start: usize,
    category: &str,
    suffix_text: &str,
    suffix_pinyin: &str,
    modification: Modification,
) -> Result<Vec<T9Case>, String> {
    source
        .iter()
        .cycle()
        .skip(start)
        .take(32)
        .map(|base| derived_case(base, category, suffix_text, suffix_pinyin, modification))
        .collect()
}

fn derive_fuzzy(clean: &[(SourceCase, String)], count: usize) -> Result<Vec<T9Case>, String> {
    let mut result = Vec::new();
    for base in clean {
        let canonical = format!("{}'{}", base.1, "ya");
        let Some(raw_digits) = fuzzy_digits(&canonical) else {
            continue;
        };
        result.push(base_t9_case(
            "fuzzy_dialect",
            "fuzzy_dialect",
            raw_digits,
            canonical,
            vec![format!("{}呀", base.0.expected_texts[0])],
            Vec::new(),
            DERIVED_SOURCE,
            vec![base.0.id.clone()],
            "Synthetic single fuzzy-initial/dialect edit of frozen project-authored pinyin; expected text was not obtained from engine candidates.",
        ));
        if result.len() == count {
            return Ok(result);
        }
    }
    Err(format!("only {} fuzzy-derived cases", result.len()))
}

#[derive(Clone, Copy)]
enum Modification {
    Clean,
    Abbreviated,
    Incomplete,
    Boundary,
    Missing,
    Extra,
    Adjacent,
    Transpose,
}

fn derived_case(
    base: &(SourceCase, String),
    category: &str,
    suffix_text: &str,
    suffix_pinyin: &str,
    modification: Modification,
) -> Result<T9Case, String> {
    let suffix = segment_pinyin(suffix_pinyin)
        .ok_or_else(|| format!("invalid suffix pinyin {suffix_pinyin}"))?
        .join("'");
    let canonical = format!("{}'{suffix}", base.1);
    let canonical_digits = signature(&canonical).expect("validated pinyin");
    let (input_kind, raw_digits, boundaries, note) = match modification {
        Modification::Clean => (
            "clean",
            canonical_digits.clone(),
            Vec::new(),
            "Synthetic composition of frozen project-authored morphemes; no engine output was used.",
        ),
        Modification::Abbreviated => (
            "abbreviated",
            canonical
                .split('\'')
                .filter_map(|syllable| t9_signature(syllable).and_then(|value| value.chars().next()))
                .collect(),
            Vec::new(),
            "Synthetic initial-only T9 shorthand derived before any engine evaluation.",
        ),
        Modification::Incomplete => (
            "incomplete_tail",
            canonical_digits[..canonical_digits.len() - 1].to_owned(),
            Vec::new(),
            "Synthetic unfinished final digit derived before any engine evaluation.",
        ),
        Modification::Boundary => {
            let first = canonical
                .split('\'')
                .next()
                .and_then(t9_signature)
                .ok_or_else(|| "missing first syllable".to_owned())?
                .len();
            (
                "explicit_boundary",
                canonical_digits.clone(),
                vec![first],
                "Clean digits with a declared formal segment-boundary insertion after the first syllable.",
            )
        }
        Modification::Missing => (
            "missing_digit",
            delete_middle(&canonical_digits),
            Vec::new(),
            "Synthetic exactly-one missing-digit edit.",
        ),
        Modification::Extra => (
            "extra_digit",
            insert_middle(&canonical_digits),
            Vec::new(),
            "Synthetic exactly-one extra-digit edit.",
        ),
        Modification::Adjacent => (
            "adjacent_key",
            replace_with_adjacent(&canonical_digits),
            Vec::new(),
            "Synthetic exactly-one adjacent-key substitution on the 3x3 T9 keypad.",
        ),
        Modification::Transpose => (
            "transposition",
            transpose_once(&canonical_digits)
                .ok_or_else(|| format!("cannot transpose {canonical_digits}"))?,
            Vec::new(),
            "Synthetic exactly-one adjacent unequal-digit transposition.",
        ),
    };
    Ok(base_t9_case(
        category,
        input_kind,
        raw_digits,
        canonical,
        vec![format!("{}{suffix_text}", base.0.expected_texts[0])],
        boundaries,
        DERIVED_SOURCE,
        vec![base.0.id.clone()],
        note,
    ))
}

#[allow(clippy::too_many_arguments)]
fn base_t9_case(
    category: &str,
    input_kind: &str,
    raw_digits: String,
    canonical_pinyin: String,
    expected_texts: Vec<String>,
    explicit_boundary_positions: Vec<usize>,
    source_id: &str,
    source_sample_ids: Vec<String>,
    notes: &str,
) -> T9Case {
    T9Case {
        id: String::new(),
        split: String::new(),
        category: category.to_owned(),
        input_kind: input_kind.to_owned(),
        raw_digits,
        canonical_pinyin,
        expected_texts,
        explicit_boundary_positions,
        source_id: source_id.to_owned(),
        source_sample_ids,
        notes: notes.to_owned(),
        layer: "t9_specialized".to_owned(),
    }
}

fn delete_middle(value: &str) -> String {
    let index = value.len() / 2;
    format!("{}{}", &value[..index], &value[index + 1..])
}

fn insert_middle(value: &str) -> String {
    let index = value.len() / 2;
    let inserted = adjacent_digit(value.as_bytes()[index] as char);
    format!("{}{inserted}{}", &value[..index], &value[index..])
}

fn replace_with_adjacent(value: &str) -> String {
    let index = value.len() / 2;
    let replacement = adjacent_digit(value.as_bytes()[index] as char);
    format!("{}{replacement}{}", &value[..index], &value[index + 1..])
}

fn adjacent_digit(value: char) -> char {
    match value {
        '2' => '3',
        '3' => '2',
        '4' => '5',
        '5' => '4',
        '6' => '5',
        '7' => '8',
        '8' => '7',
        '9' => '8',
        _ => unreachable!("validated digit"),
    }
}

fn transpose_once(value: &str) -> Option<String> {
    let bytes = value.as_bytes();
    let index = bytes.windows(2).position(|pair| pair[0] != pair[1])?;
    let mut output = bytes.to_vec();
    output.swap(index, index + 1);
    String::from_utf8(output).ok()
}

fn fuzzy_digits(canonical: &str) -> Option<String> {
    let letters = canonical.replace('\'', "");
    let canonical_digits = signature(canonical)?;
    let fuzzy = if let Some(index) = letters.find("zh") {
        format!("{}{}", &letters[..index + 1], &letters[index + 2..])
    } else if let Some(index) = letters.find("ch") {
        format!("{}{}", &letters[..index + 1], &letters[index + 2..])
    } else if let Some(index) = letters.find("sh") {
        format!("{}{}", &letters[..index + 1], &letters[index + 2..])
    } else if let Some(index) = letters.find('n') {
        format!("{}l{}", &letters[..index], &letters[index + 1..])
    } else if let Some(index) = letters.find('l') {
        format!("{}n{}", &letters[..index], &letters[index + 1..])
    } else {
        return None;
    };
    let fuzzy_digits = t9_signature(&fuzzy)?;
    (edit_distance(&canonical_digits, &fuzzy_digits) == 1).then_some(fuzzy_digits)
}

fn edit_distance(left: &str, right: &str) -> usize {
    let mut row = (0..=right.len()).collect::<Vec<_>>();
    for (left_index, left_byte) in left.bytes().enumerate() {
        let mut previous = row[0];
        row[0] = left_index + 1;
        for (right_index, right_byte) in right.bytes().enumerate() {
            let old = row[right_index + 1];
            row[right_index + 1] = (row[right_index + 1] + 1)
                .min(row[right_index] + 1)
                .min(previous + usize::from(left_byte != right_byte));
            previous = old;
        }
    }
    row[right.len()]
}

fn published_path_count(raw_digits: &str) -> usize {
    let mut parser = T9PinyinParser::new();
    let result = parser.process_str(raw_digits);
    usize::from(!result.current_pinyin.is_empty()) + result.pinyin_combinations.len()
}

fn write_cases(path: &Path, cases: &[T9Case]) -> Result<(), String> {
    let mut bytes = Vec::new();
    for case in cases {
        bytes.extend_from_slice(&serialize_line(&case_json(case)));
    }
    fs::write(path, bytes).map_err(|error| error.to_string())
}

fn case_json(case: &T9Case) -> JsonValue {
    JsonValue::object([
        ("id", JsonValue::string(&case.id)),
        ("split", JsonValue::string(&case.split)),
        ("category", JsonValue::string(&case.category)),
        ("inputKind", JsonValue::string(&case.input_kind)),
        ("rawDigits", JsonValue::string(&case.raw_digits)),
        ("canonicalPinyin", JsonValue::string(&case.canonical_pinyin)),
        (
            "expectedTexts",
            JsonValue::array(case.expected_texts.iter().map(JsonValue::string)),
        ),
        (
            "explicitBoundaryPositions",
            JsonValue::array(
                case.explicit_boundary_positions
                    .iter()
                    .map(|value| JsonValue::number(*value as f64)),
            ),
        ),
        ("sourceId", JsonValue::string(&case.source_id)),
        (
            "sourceSampleIds",
            JsonValue::array(case.source_sample_ids.iter().map(JsonValue::string)),
        ),
        ("notes", JsonValue::string(&case.notes)),
        ("layer", JsonValue::string(&case.layer)),
    ])
}

fn sources_json() -> JsonValue {
    JsonValue::object([
        ("schemaVersion", JsonValue::string("pinyin9-evaluation-sources/1")),
        (
            "sources",
            JsonValue::array([
                JsonValue::object([
                    ("id", JsonValue::string(QUANPIN_SOURCE)),
                    ("name", JsonValue::string("Frozen quanpin quality baseline v1")),
                    ("version", JsonValue::string("quanpin-quality-v1-20260813")),
                    ("license", JsonValue::string("PROJECT-INTERNAL-AUTHORED-DATA")),
                    ("method", JsonValue::string("Exact expectedTexts and source sample IDs retained; rawInput converted deterministically with the standard T9 mapping.")),
                    ("commercialImeData", JsonValue::Bool(false)),
                    ("engineGeneratedExpectedText", JsonValue::Bool(false)),
                ]),
                JsonValue::object([
                    ("id", JsonValue::string(AUTHORED_SOURCE)),
                    ("name", JsonValue::string("Pinyin9 independently authored common-character seeds")),
                    ("version", JsonValue::string("1.0.0")),
                    ("license", JsonValue::string("PROJECT-INTERNAL-AUTHORED-DATA")),
                    ("method", JsonValue::string("Ordinary Mandarin knowledge authored directly in source before evaluation; not copied from an IME.")),
                    ("commercialImeData", JsonValue::Bool(false)),
                    ("engineGeneratedExpectedText", JsonValue::Bool(false)),
                ]),
                JsonValue::object([
                    ("id", JsonValue::string(DERIVED_SOURCE)),
                    ("name", JsonValue::string("Deterministic T9-specific synthetic transformations")),
                    ("version", JsonValue::string("1.0.0")),
                    ("license", JsonValue::string("PROJECT-INTERNAL-AUTHORED-DATA")),
                    ("method", JsonValue::string("Deterministic morpheme composition, abbreviation, incomplete-tail, boundary, single-edit keypad error, and fuzzy-initial transforms of accurately identified frozen project samples.")),
                    ("commercialImeData", JsonValue::Bool(false)),
                    ("engineGeneratedExpectedText", JsonValue::Bool(false)),
                ]),
            ]),
        ),
    ])
}

fn provenance() -> &'static str {
    "# Pinyin-9 evaluation dataset provenance\n\n\
Version: 1.0.0\n\n\
Authoring/freeze preparation date: 2026-08-17 (Asia/Shanghai).\n\n\
The public regression layer is a deterministic conversion of every applicable `clean` sample in the byte-frozen quanpin v1 dataset. When multiple original samples become the same `rawDigits + expectedTexts` pair under T9, they are deterministically collapsed and every original ID is retained in `sourceSampleIds`; this satisfies the duplicate gate without editing the frozen source. It retains the original expected text, category, source ID, and source sample identity. It is explicitly labelled `converted_public_regression` and is not represented as new blind data.\n\n\
The T9-specialized layer contains independently authored common-character seeds plus deterministic synthetic compositions and T9-specific input transforms of accurately identified project-authored quanpin samples. `sourceSampleIds` records the exact upstream case. Error forms are generated before evaluation and are validated as the declared single edit. No expected text was read from current engine candidates.\n\n\
No commercial IME candidate list, commercial corpus, user data, web scrape, or license-unknown text is present. The blind partition is byte-frozen before its sole three-repeat evaluation command; dev failures may be inspected, but blind rows may not be edited after freeze.\n"
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keypad_edits_are_exactly_one_edit() {
        let original = "6442674264";
        assert_eq!(edit_distance(original, &delete_middle(original)), 1);
        assert_eq!(edit_distance(original, &insert_middle(original)), 1);
        assert_eq!(edit_distance(original, &replace_with_adjacent(original)), 1);
        let swapped = transpose_once(original).expect("unequal pair");
        assert_eq!(edit_distance(original, &swapped), 2);
    }

    #[test]
    fn canonical_segmentation_and_signature_are_deterministic() {
        let canonical = segment_pinyin("nihao").expect("segment").join("'");
        assert_eq!(signature(&canonical).as_deref(), Some("64426"));
        assert_eq!(canonical, segment_pinyin("nihao").unwrap().join("'"));
    }

    #[test]
    fn authored_common_shape_is_fixed() {
        let cases = authored_common_cases().expect("authored cases");
        assert_eq!(cases.len(), 32);
        assert!(cases.iter().all(|case| case.input_kind == "clean"));
    }
}
