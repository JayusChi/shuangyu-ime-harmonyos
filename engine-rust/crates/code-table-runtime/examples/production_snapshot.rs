use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;

use code_table_runtime::{CodeTableBundle, CodeTableMatch};

#[derive(Clone)]
struct Record {
    text: String,
    category_id: String,
    source_order: u32,
    candidate_id: String,
}

struct ReferenceIndex {
    records: Vec<Record>,
    exact: BTreeMap<String, Vec<usize>>,
    prefixes: BTreeMap<String, Vec<usize>>,
}

#[derive(Clone)]
struct ReferenceResult {
    match_type: CodeTableMatch,
    before_dedup: usize,
    candidates: Vec<Record>,
}

fn main() {
    let bundle_path = std::env::args_os().nth(1).map(PathBuf::from).unwrap_or_else(|| {
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(
            "../../../dictionaries/generated/xiaohe-yinxing-production/xiaohe-yinxing-production.hsyx",
        )
    });
    let bundle = CodeTableBundle::load_frozen_production_file(&bundle_path)
        .expect("load frozen production bundle");
    bundle
        .validate_scheme_identity("xiaohe-yinxing")
        .expect("formal identity");
    let index = build_index(&bundle);
    let exact_categories = index
        .exact
        .keys()
        .map(|code| (code.clone(), result_categories(&reference(&index, code))))
        .collect::<BTreeMap<_, _>>();
    let prefix_categories = index
        .prefixes
        .keys()
        .filter(|code| !index.exact.contains_key(*code))
        .map(|code| (code.clone(), result_categories(&reference(&index, code))))
        .collect::<BTreeMap<_, _>>();
    println!(
        "META\tbundle_sha256\t0963f9c28b750c375dbe693feaa2b1c9334ecd9c2c58df2e367138b22b82c942"
    );
    println!("HEADER\tcase_id\traw_code\tmatch_type\tbefore_dedup\texpected_total_count\texpected_category_id\texpected_source_order\texpected_candidate_id\texpected_first_candidates\texpected_categories\tselection_reason");

    for length in 1..=4 {
        let code = index
            .exact
            .keys()
            .find(|code| code.len() == length)
            .expect("exact code length");
        print_case(
            &index,
            &format!("exact_{length}"),
            code,
            "smallest sorted exact code",
        );
    }

    let exact_with_longer = index
        .exact
        .keys()
        .find(|code| index.prefixes.contains_key(*code))
        .expect("exact with longer code");
    print_case(
        &index,
        "exact_with_longer",
        exact_with_longer,
        "smallest exact code that is also a longer-code prefix",
    );

    let prefix = index
        .prefixes
        .keys()
        .find(|prefix| {
            !index.exact.contains_key(*prefix) && reference(&index, prefix).candidates.len() >= 2
        })
        .expect("prefix fallback");
    print_case(
        &index,
        "prefix_fallback",
        prefix,
        "smallest non-exact prefix with at least two deduplicated candidates",
    );

    let no_result = first_missing_code(&index);
    print_case(
        &index,
        "no_result",
        &no_result,
        "smallest four-letter code with no exact or prefix record",
    );

    let mut cross_two = None;
    let mut cross_three = None;
    let mut same_category_multi = None;
    for code in index.exact.keys() {
        let result = reference(&index, code);
        let categories = &exact_categories[code];
        if cross_two.is_none() && categories.len() >= 2 {
            cross_two = Some(code.clone());
        }
        if cross_three.is_none() && categories.len() >= 3 {
            cross_three = Some(code.clone());
        }
        if same_category_multi.is_none()
            && result
                .candidates
                .windows(2)
                .any(|pair| pair[0].category_id == pair[1].category_id)
        {
            same_category_multi = Some(code.clone());
        }
    }
    let duplicate = index
        .exact
        .keys()
        .chain(
            index
                .prefixes
                .keys()
                .filter(|code| !index.exact.contains_key(*code)),
        )
        .find(|code| {
            let result = reference(&index, code);
            result.before_dedup > result.candidates.len()
        })
        .cloned();
    print_case(
        &index,
        "cross_two",
        cross_two.as_deref().expect("cross two"),
        "smallest exact code spanning at least two categories",
    );
    if let Some(code) = cross_three.as_deref() {
        print_case(
            &index,
            "cross_three",
            code,
            "smallest exact code spanning at least three categories",
        );
    }
    if let Some(code) = duplicate.as_deref() {
        print_case(
            &index,
            "cross_duplicate",
            code,
            "smallest exact-or-prefix query with cross-record duplicate text",
        );
    } else {
        eprintln!("NO_CASE\tcross_duplicate\tno duplicate text shares an exact-or-prefix result in the frozen bundle");
    }
    print_case(
        &index,
        "same_category_multi",
        same_category_multi.as_deref().expect("same category multi"),
        "smallest exact code with adjacent same-category candidates",
    );

    for category in &bundle.categories {
        if category.id == "quick-symbol" {
            continue;
        }
        let code = index
            .exact
            .keys()
            .find(|code| exact_categories[*code].contains(category.id.as_str()))
            .expect("category representative");
        print_case(
            &index,
            &format!("category_{}", category.id),
            code,
            "smallest exact query exposing this category",
        );
        if let Some(prefix) = index.exact.keys().find_map(|code| {
            (1..code.len()).find_map(|length| {
                let prefix = &code[..length];
                (!index.exact.contains_key(prefix)
                    && prefix_categories
                        .get(prefix)
                        .is_some_and(|categories| categories.contains(category.id.as_str())))
                .then(|| prefix.to_owned())
            })
        }) {
            print_case(
                &index,
                &format!("category_prefix_{}", category.id),
                &prefix,
                "smallest non-exact prefix exposing this category",
            );
        }
    }

    let extension = first_matching(&index, |text| text.chars().any(|ch| ch as u32 > 0xffff));
    if let Some(code) = extension {
        print_case(
            &index,
            "unicode_extension",
            &code,
            "smallest exact query exposing a supplementary-plane scalar",
        );
    }
    let special = first_matching(&index, |text| text.chars().any(is_special));
    if let Some(code) = special {
        print_case(
            &index,
            "special_symbol",
            &code,
            "smallest exact query exposing a non-CJK symbol or ASCII scalar",
        );
    }

    let (max_exact, max_exact_result) = max_result(index.exact.keys(), &index);
    print_case(
        &index,
        "max_exact",
        &max_exact,
        "largest deduplicated exact collision; lexical tie-break",
    );
    eprintln!(
        "MAX_EXACT\t{}\t{}\t{}",
        max_exact,
        max_exact_result.before_dedup,
        max_exact_result.candidates.len()
    );
    let prefix_keys = index
        .prefixes
        .keys()
        .filter(|prefix| !index.exact.contains_key(*prefix));
    let (max_prefix, max_prefix_result) = max_result(prefix_keys, &index);
    print_case(
        &index,
        "max_prefix",
        &max_prefix,
        "largest deduplicated non-exact prefix fallback; lexical tie-break",
    );
    eprintln!(
        "MAX_PREFIX\t{}\t{}\t{}",
        max_prefix,
        max_prefix_result.before_dedup,
        max_prefix_result.candidates.len()
    );
}

fn result_categories(result: &ReferenceResult) -> BTreeSet<String> {
    result
        .candidates
        .iter()
        .map(|candidate| candidate.category_id.clone())
        .collect()
}

fn build_index(bundle: &CodeTableBundle) -> ReferenceIndex {
    let mut records = Vec::new();
    let mut exact = BTreeMap::<String, Vec<usize>>::new();
    let mut prefixes = BTreeMap::<String, Vec<usize>>::new();
    for category in &bundle.categories {
        if category.id == "quick-symbol" {
            continue;
        }
        let mut entries = category.lexicon.entries.iter().collect::<Vec<_>>();
        entries.sort_by_key(|entry| entry.source_order);
        for entry in entries {
            let index = records.len();
            records.push(Record {
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
        records,
        exact,
        prefixes,
    }
}

fn reference(index: &ReferenceIndex, raw_code: &str) -> ReferenceResult {
    let (match_type, indexes) = if let Some(indexes) = index.exact.get(raw_code) {
        (CodeTableMatch::Exact, indexes.as_slice())
    } else {
        (
            CodeTableMatch::Prefix,
            index
                .prefixes
                .get(raw_code)
                .map(Vec::as_slice)
                .unwrap_or(&[]),
        )
    };
    let mut seen = BTreeSet::new();
    let candidates = indexes
        .iter()
        .map(|record| index.records[*record].clone())
        .filter(|record| seen.insert(record.text.clone()))
        .collect();
    ReferenceResult {
        match_type,
        before_dedup: indexes.len(),
        candidates,
    }
}

fn max_result<'a>(
    keys: impl Iterator<Item = &'a String>,
    index: &ReferenceIndex,
) -> (String, ReferenceResult) {
    let mut best: Option<(String, ReferenceResult)> = None;
    for key in keys {
        let result = reference(index, key);
        if best
            .as_ref()
            .map(|(_, value)| result.candidates.len() > value.candidates.len())
            .unwrap_or(true)
        {
            best = Some((key.clone(), result));
        }
    }
    best.expect("non-empty result set")
}

fn print_case(index: &ReferenceIndex, id: &str, code: &str, reason: &str) {
    let result = reference(index, code);
    let first = result.candidates.first();
    let preview = result
        .candidates
        .iter()
        .take(8)
        .map(|candidate| candidate.text.as_str())
        .collect::<Vec<_>>()
        .join("|");
    let categories = result
        .candidates
        .iter()
        .map(|candidate| candidate.category_id.as_str())
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect::<Vec<_>>()
        .join("|");
    println!(
        "CASE\t{id}\t{code}\t{:?}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
        result.match_type,
        result.before_dedup,
        result.candidates.len(),
        first.map(|value| value.category_id.as_str()).unwrap_or(""),
        first
            .map(|value| value.source_order.to_string())
            .unwrap_or_default(),
        first.map(|value| value.candidate_id.as_str()).unwrap_or(""),
        preview,
        categories,
        reason,
    );
}

fn first_matching(index: &ReferenceIndex, predicate: impl Fn(&str) -> bool) -> Option<String> {
    index.exact.keys().find_map(|code| {
        reference(index, code)
            .candidates
            .iter()
            .any(|candidate| predicate(&candidate.text))
            .then(|| code.clone())
    })
}

fn first_missing_code(index: &ReferenceIndex) -> String {
    for a in b'a'..=b'z' {
        for b in b'a'..=b'z' {
            for c in b'a'..=b'z' {
                for d in b'a'..=b'z' {
                    let code = String::from_utf8(vec![a, b, c, d]).expect("ASCII");
                    if !index.exact.contains_key(&code) && !index.prefixes.contains_key(&code) {
                        return code;
                    }
                }
            }
        }
    }
    panic!("missing code not found")
}

fn is_special(ch: char) -> bool {
    let value = ch as u32;
    ch.is_ascii() || !(0x3400..=0x9fff).contains(&value) && !(0x20000..=0x3134f).contains(&value)
}
