use std::collections::BTreeMap;

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct SyntaxStats {
    pub ordinary: u64,
    pub user_delete: u64,
    pub user_pin: u64,
    pub user_position: u64,
    pub user_mixed: u64,
    pub cmd: u64,
    pub ddcmd: u64,
    pub config_header: u64,
    pub config_item: u64,
    pub comment: u64,
    pub empty: u64,
    pub unrecognized: u64,
    pub first: BTreeMap<String, Occurrence>,
    pub records: Vec<Record>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Occurrence {
    pub line: u64,
    pub sample_sha256: String,
}

#[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd)]
pub struct Record {
    pub text: String,
    pub code: String,
    pub syntax: String,
    pub line: u64,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SecurityFinding {
    pub finding_type: String,
    pub line: u64,
    pub summary_sha256: String,
    pub reason_code: String,
    pub blocking_credential: bool,
}

#[derive(Clone, Debug)]
pub struct SourceFile {
    pub source_root: String,
    pub relative_path: String,
    pub normalized_relative_path: String,
    pub file_name: String,
    pub extension: String,
    pub byte_size: u64,
    pub physical_line_count: u64,
    pub non_empty_line_count: u64,
    pub detected_encoding: String,
    pub has_utf8_bom: bool,
    pub newline_style: String,
    pub final_newline: bool,
    pub sha256: String,
    pub file_role: String,
    pub role_evidence: String,
    pub security_classification: String,
    pub decision: String,
    pub decision_reason: String,
    pub syntax: SyntaxStats,
    pub security_findings: Vec<SecurityFinding>,
    pub read_error: Option<String>,
}

impl SourceFile {
    pub fn source_id(&self) -> String {
        format!("{}/{}", self.source_root, self.relative_path)
    }
}

#[derive(Clone, Debug)]
pub struct Comparison {
    pub comparison_id: String,
    pub left_source: String,
    pub right_source: String,
    pub comparison_type: String,
    pub byte_identical: bool,
    pub normalized_text_identical: bool,
    pub record_set_identical: bool,
    pub record_order_identical: bool,
    pub semantic_role_identical: bool,
    pub overlap_count: u64,
    pub left_only_count: u64,
    pub right_only_count: u64,
    pub order_difference: bool,
    pub syntax_difference: bool,
    pub same_text_different_code: u64,
    pub same_code_different_text: u64,
    pub recommended_resolution: String,
    pub requires_manual_confirmation: bool,
}

#[derive(Clone, Debug)]
pub struct MissingReference {
    pub referenced_path: String,
    pub reference_file: String,
    pub reference_line: u64,
    pub reference_role: String,
    pub resolved: bool,
    pub resolved_source: Option<String>,
    pub missing_reason: Option<String>,
    pub case_mismatch: bool,
    pub path_separator_issue: bool,
    pub outside_allowed_roots: bool,
    pub resolution_decision: String,
    pub reason_code: String,
    pub next_stage_action: String,
    pub blocks_conversion: bool,
}

#[derive(Clone, Debug)]
pub struct Category {
    pub category_id: &'static str,
    pub display_name: &'static str,
    pub role: &'static str,
    pub authoritative_source: Option<&'static str>,
    pub supplemental_sources: &'static [&'static str],
    pub audit_only_sources: &'static [&'static str],
    pub merge_order: &'static [&'static str],
    pub default_enabled: bool,
    pub first_release_scope: &'static str,
    pub conflict_policy: &'static str,
    pub duplicate_policy: &'static str,
    pub unsupported_record_policy: &'static str,
    pub confirmation_status: &'static str,
    pub requires_manual_confirmation: bool,
    pub notes: &'static str,
}

#[derive(Clone, Debug)]
pub struct AuditResult {
    pub files: Vec<SourceFile>,
    pub comparisons: Vec<Comparison>,
    pub references: Vec<MissingReference>,
    pub categories: Vec<Category>,
    pub path_conflicts: Vec<String>,
    pub blocking_reasons: Vec<String>,
}
