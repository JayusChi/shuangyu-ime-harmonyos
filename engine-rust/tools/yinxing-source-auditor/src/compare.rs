use crate::{
    model::{Comparison, Record, SourceFile},
    sha256,
};
use std::collections::{BTreeMap, BTreeSet};

pub fn compare(files: &[SourceFile]) -> Vec<Comparison> {
    let mut pairs = BTreeSet::<(usize, usize)>::new();
    for left in 0..files.len() {
        for right in left + 1..files.len() {
            if files[left].source_root == files[right].source_root {
                continue;
            }
            if files[left].file_role == files[right].file_role
                || logical_category_pair(&files[left].file_role, &files[right].file_role)
                || files[left].sha256 == files[right].sha256
                || files[left]
                    .file_name
                    .eq_ignore_ascii_case(&files[right].file_name)
            {
                pairs.insert((left, right));
            }
        }
    }
    let mut output = pairs
        .into_iter()
        .map(|(left, right)| compare_pair(&files[left], &files[right]))
        .collect::<Vec<_>>();
    output.sort_by(|a, b| a.comparison_id.cmp(&b.comparison_id));
    output
}

fn logical_category_pair(left: &str, right: &str) -> bool {
    matches!(
        (left, right),
        ("category_table", "secondary_candidate_table")
            | ("secondary_candidate_table", "category_table")
    )
}

fn compare_pair(left: &SourceFile, right: &SourceFile) -> Comparison {
    let left_records = normalized_records(&left.syntax.records);
    let right_records = normalized_records(&right.syntax.records);
    let left_set: BTreeSet<_> = left_records.iter().cloned().collect();
    let right_set: BTreeSet<_> = right_records.iter().cloned().collect();
    let overlap = left_set.intersection(&right_set).count() as u64;
    let left_only = left_set.difference(&right_set).count() as u64;
    let right_only = right_set.difference(&left_set).count() as u64;
    let record_set_identical = left_set == right_set;
    let record_order_identical = left_records == right_records;
    let normalized_text_identical = normalized_text_digest(left) == normalized_text_digest(right);
    let comparison_type = if left.sha256 == right.sha256 {
        "byte_identical"
    } else if normalized_text_identical {
        "normalized_text_identical"
    } else if record_set_identical && !record_order_identical {
        "same_records_different_order"
    } else if left_only == 0 && overlap > 0 {
        "left_subset"
    } else if right_only == 0 && overlap > 0 {
        "right_subset"
    } else if overlap > 0 {
        "partial_overlap"
    } else {
        "different"
    };
    let mut left_by_text = BTreeMap::<&str, BTreeSet<&str>>::new();
    let mut right_by_text = BTreeMap::<&str, BTreeSet<&str>>::new();
    let mut left_by_code = BTreeMap::<&str, BTreeSet<&str>>::new();
    let mut right_by_code = BTreeMap::<&str, BTreeSet<&str>>::new();
    index_records(&left.syntax.records, &mut left_by_text, &mut left_by_code);
    index_records(
        &right.syntax.records,
        &mut right_by_text,
        &mut right_by_code,
    );
    let same_text_different_code = conflicts(&left_by_text, &right_by_text);
    let same_code_different_text = conflicts(&left_by_code, &right_by_code);
    let syntax_difference = syntax_signature(left) != syntax_signature(right);
    let id_seed = format!("{}\0{}", left.source_id(), right.source_id());
    Comparison {
        comparison_id: format!("cmp-{}", &sha256::hex(id_seed.as_bytes())[..16]),
        left_source: left.source_id(),
        right_source: right.source_id(),
        comparison_type: comparison_type.into(),
        byte_identical: left.sha256 == right.sha256,
        normalized_text_identical,
        record_set_identical,
        record_order_identical,
        semantic_role_identical: left.file_role == right.file_role,
        overlap_count: overlap,
        left_only_count: left_only,
        right_only_count: right_only,
        order_difference: record_set_identical && !record_order_identical,
        syntax_difference,
        same_text_different_code,
        same_code_different_text,
        recommended_resolution: "use the numbered 小鹤音形 source only for frozen first-release categories; keep 码表 exports audit-only; keep deferred or rejected feature pairs isolated".into(),
        requires_manual_confirmation: false,
    }
}

fn normalized_records(records: &[Record]) -> Vec<(String, String, String)> {
    records
        .iter()
        .map(|r| (r.text.trim().into(), r.code.trim().into(), r.syntax.clone()))
        .collect()
}
fn normalized_text_digest(file: &SourceFile) -> String {
    let mut value = String::new();
    for r in &file.syntax.records {
        value.push_str(r.text.trim());
        value.push('\t');
        value.push_str(r.code.trim());
        value.push('\n');
    }
    sha256::hex(value.as_bytes())
}
fn index_records<'a>(
    records: &'a [Record],
    by_text: &mut BTreeMap<&'a str, BTreeSet<&'a str>>,
    by_code: &mut BTreeMap<&'a str, BTreeSet<&'a str>>,
) {
    for r in records {
        by_text.entry(&r.text).or_default().insert(&r.code);
        by_code.entry(&r.code).or_default().insert(&r.text);
    }
}
fn conflicts(left: &BTreeMap<&str, BTreeSet<&str>>, right: &BTreeMap<&str, BTreeSet<&str>>) -> u64 {
    left.iter()
        .filter(|(key, values)| right.get(*key).is_some_and(|other| other != *values))
        .count() as u64
}
fn syntax_signature(file: &SourceFile) -> [u64; 10] {
    let s = &file.syntax;
    [
        s.ordinary,
        s.user_delete,
        s.user_pin,
        s.direct_add,
        s.user_position,
        s.user_mixed,
        s.cmd,
        s.ddcmd,
        s.config_item,
        s.unrecognized,
    ]
}

#[cfg(test)]
mod tests {
    use super::*;
    fn file(root: &str, name: &str, records: Vec<Record>) -> SourceFile {
        SourceFile {
            source_root: root.into(),
            relative_path: name.into(),
            normalized_relative_path: name.into(),
            file_name: name.into(),
            extension: "txt".into(),
            byte_size: 0,
            physical_line_count: 0,
            non_empty_line_count: 0,
            detected_encoding: "UTF-8".into(),
            has_utf8_bom: false,
            newline_style: "LF".into(),
            final_newline: true,
            sha256: name.into(),
            file_role: "core_code_table".into(),
            role_evidence: "test".into(),
            security_classification: "clean".into(),
            decision: "ACCEPTED".into(),
            decision_reason: "test".into(),
            syntax: crate::model::SyntaxStats {
                records,
                ..Default::default()
            },
            security_findings: vec![],
            read_error: None,
        }
    }
    fn rec(text: &str, code: &str, line: u64) -> Record {
        Record {
            text: text.into(),
            code: code.into(),
            syntax: "ordinary".into(),
            line,
        }
    }
    #[test]
    fn compares_order_subset_and_conflicts() {
        let a = file("码表", "a", vec![rec("甲", "aa", 1), rec("乙", "bb", 2)]);
        let b = file(
            "小鹤音形",
            "b",
            vec![rec("乙", "bb", 1), rec("甲", "cc", 2)],
        );
        let c = compare(&[a, b]);
        assert_eq!(c[0].overlap_count, 1);
        assert_eq!(c[0].same_text_different_code, 1);
        assert!(!c[0].requires_manual_confirmation);
    }
}
