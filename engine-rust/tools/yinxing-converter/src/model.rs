use std::collections::BTreeMap;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CategorySpec {
    pub category_id: String,
    pub display_name: String,
    pub role: String,
    pub order: u32,
    pub source_path: String,
    pub source_file_id: String,
    pub source_size: u64,
    pub source_sha256: String,
    pub source_decision: String,
    pub default_enabled: bool,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CommandFinding {
    pub source_file: String,
    pub physical_line: u64,
    pub finding_type: String,
    pub summary_sha256: String,
    pub decision: String,
    pub reason_code: String,
}

#[derive(Clone, Debug)]
pub struct ValidatedContract {
    pub categories: Vec<CategorySpec>,
    pub command_findings: BTreeMap<(String, u64), CommandFinding>,
    pub source_manifest_bytes: Vec<u8>,
    pub conversion_contract_bytes: Vec<u8>,
    pub command_policy_sha256: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SystemRecord {
    pub text: String,
    pub code: String,
    pub source_file_id: String,
    pub source_file: String,
    pub source_sha256: String,
    pub category_id: String,
    pub physical_line: u64,
    pub source_order: u32,
    pub line_digest: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum UserAction {
    Add,
    Delete,
    Fixed,
    Position(u16),
}

impl UserAction {
    pub const fn name(&self) -> &'static str {
        match self {
            Self::Add => "add",
            Self::Delete => "delete",
            Self::Fixed => "fixed",
            Self::Position(_) => "position",
        }
    }

    pub fn marker(&self) -> String {
        match self {
            Self::Add => String::new(),
            Self::Delete => "#删".to_owned(),
            Self::Fixed => "#固".to_owned(),
            Self::Position(value) => format!("#{value}"),
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct UserRuleRecord {
    pub text: String,
    pub display_text: Option<String>,
    pub code: String,
    pub action: UserAction,
    pub source_file_id: String,
    pub source_file: String,
    pub source_sha256: String,
    pub category_id: String,
    pub physical_line: u64,
    pub source_order: u32,
    pub line_digest: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ActionDisposition {
    Deferred,
    Rejected,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ActionRecord {
    pub source_file_id: String,
    pub physical_line: u64,
    pub syntax: String,
    pub disposition: ActionDisposition,
    pub reason_code: String,
    pub line_digest: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RejectedRecord {
    pub source_file_id: String,
    pub physical_line: u64,
    pub reason_code: String,
    pub safe_summary: String,
    pub line_digest: String,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct CategoryStatistics {
    pub input_bytes: u64,
    pub physical_lines: u64,
    pub empty: u64,
    pub comments: u64,
    pub configuration_headers: u64,
    pub ordinary: u64,
    pub accepted_system: u64,
    pub user_add: u64,
    pub user_delete: u64,
    pub user_fixed: u64,
    pub user_position: u64,
    pub mixed_rule: u64,
    pub cmd: u64,
    pub ddcmd: u64,
    pub normalized: u64,
    pub rejected: u64,
    pub deferred: u64,
    pub duplicates: u64,
    pub conflicts: u64,
    pub max_code_length: u64,
    pub max_word_length: u64,
    pub cjk_extension_records: u64,
    pub emoji_or_special_records: u64,
}

impl CategoryStatistics {
    pub fn user_rule_count(&self) -> u64 {
        self.user_add + self.user_delete + self.user_fixed + self.user_position
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CategoryBuild {
    pub spec: CategorySpec,
    pub system_records: Vec<SystemRecord>,
    pub user_rules: Vec<UserRuleRecord>,
    pub actions: Vec<ActionRecord>,
    pub rejected: Vec<RejectedRecord>,
    pub stats: CategoryStatistics,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct BuildStatistics {
    pub input_file_count: u64,
    pub input_bytes: u64,
    pub physical_lines: u64,
    pub empty: u64,
    pub comments: u64,
    pub configuration_headers: u64,
    pub ordinary: u64,
    pub user_add: u64,
    pub user_delete: u64,
    pub user_fixed: u64,
    pub user_position: u64,
    pub mixed_rule: u64,
    pub cmd: u64,
    pub ddcmd: u64,
    pub accepted: u64,
    pub transformed: u64,
    pub rejected: u64,
    pub deferred: u64,
    pub duplicates: u64,
    pub conflicts: u64,
    pub cjk_extension_records: u64,
    pub emoji_or_special_records: u64,
}

impl BuildStatistics {
    pub fn add_category(&mut self, value: &CategoryStatistics) {
        self.input_file_count += 1;
        self.input_bytes += value.input_bytes;
        self.physical_lines += value.physical_lines;
        self.empty += value.empty;
        self.comments += value.comments;
        self.configuration_headers += value.configuration_headers;
        self.ordinary += value.ordinary;
        self.user_add += value.user_add;
        self.user_delete += value.user_delete;
        self.user_fixed += value.user_fixed;
        self.user_position += value.user_position;
        self.mixed_rule += value.mixed_rule;
        self.cmd += value.cmd;
        self.ddcmd += value.ddcmd;
        self.accepted += value.accepted_system + value.user_rule_count();
        self.transformed += value.normalized + value.user_rule_count();
        self.rejected += value.rejected;
        self.deferred += value.deferred;
        self.duplicates += value.duplicates;
        self.conflicts += value.conflicts;
        self.cjk_extension_records += value.cjk_extension_records;
        self.emoji_or_special_records += value.emoji_or_special_records;
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct OutputFile {
    pub path: String,
    pub bytes: Vec<u8>,
    pub sha256: String,
    pub kind: String,
    pub order: u32,
}

impl OutputFile {
    pub fn new(
        path: impl Into<String>,
        bytes: Vec<u8>,
        kind: impl Into<String>,
        order: u32,
    ) -> Self {
        let sha256 = crate::sha256::hex(&bytes);
        Self {
            path: path.into(),
            bytes,
            sha256,
            kind: kind.into(),
            order,
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BuildResult {
    pub bundle_sha256: String,
    pub bundle_bytes: usize,
    pub bundle_content_sha256: String,
    pub output_files: Vec<(String, usize, String)>,
    pub statistics: BuildStatistics,
}
