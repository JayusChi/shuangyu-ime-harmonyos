use crate::json::{self, JsonValue};
use crate::model::{BuildStatistics, CategoryBuild, RejectedRecord};

pub fn statistics_json(categories: &[CategoryBuild], totals: &BuildStatistics) -> Vec<u8> {
    let category_values = categories.iter().map(|category| {
        JsonValue::object([
            ("category_id", JsonValue::string(&category.spec.category_id)),
            ("order", JsonValue::Number(u64::from(category.spec.order))),
            ("input_bytes", JsonValue::Number(category.stats.input_bytes)),
            (
                "physical_lines",
                JsonValue::Number(category.stats.physical_lines),
            ),
            (
                "ordinary_records",
                JsonValue::Number(category.stats.ordinary),
            ),
            (
                "accepted_system_records",
                JsonValue::Number(category.stats.accepted_system),
            ),
            ("user_additions", JsonValue::Number(category.stats.user_add)),
            (
                "user_direct_entries",
                JsonValue::Number(category.stats.user_direct),
            ),
            (
                "user_deletions",
                JsonValue::Number(category.stats.user_delete),
            ),
            ("user_fixed", JsonValue::Number(category.stats.user_fixed)),
            (
                "user_positions",
                JsonValue::Number(category.stats.user_position),
            ),
            ("mixed_rules", JsonValue::Number(category.stats.mixed_rule)),
            ("commands", JsonValue::Number(category.stats.cmd)),
            ("ddcommands", JsonValue::Number(category.stats.ddcmd)),
            ("empty_lines", JsonValue::Number(category.stats.empty)),
            ("comments", JsonValue::Number(category.stats.comments)),
            (
                "configuration_headers",
                JsonValue::Number(category.stats.configuration_headers),
            ),
            (
                "normalized_records",
                JsonValue::Number(category.stats.normalized),
            ),
            (
                "deferred_records",
                JsonValue::Number(category.stats.deferred),
            ),
            (
                "rejected_records",
                JsonValue::Number(category.stats.rejected),
            ),
            (
                "duplicate_records",
                JsonValue::Number(category.stats.duplicates),
            ),
            (
                "conflict_records",
                JsonValue::Number(category.stats.conflicts),
            ),
            (
                "max_code_length",
                JsonValue::Number(category.stats.max_code_length),
            ),
            (
                "max_word_length",
                JsonValue::Number(category.stats.max_word_length),
            ),
            (
                "cjk_extension_records",
                JsonValue::Number(category.stats.cjk_extension_records),
            ),
            (
                "emoji_or_special_records",
                JsonValue::Number(category.stats.emoji_or_special_records),
            ),
        ])
    });
    let rejected = categories
        .iter()
        .flat_map(|category| category.rejected.iter())
        .map(rejected_json);
    json::serialize(&JsonValue::object([
        ("report_version", JsonValue::string("1.1.0")),
        (
            "statistics_scope",
            JsonValue::string("one deterministic production build"),
        ),
        (
            "input_file_count",
            JsonValue::Number(totals.input_file_count),
        ),
        ("input_bytes", JsonValue::Number(totals.input_bytes)),
        ("physical_lines", JsonValue::Number(totals.physical_lines)),
        ("empty_lines", JsonValue::Number(totals.empty)),
        ("comments", JsonValue::Number(totals.comments)),
        (
            "configuration_headers",
            JsonValue::Number(totals.configuration_headers),
        ),
        ("ordinary_records", JsonValue::Number(totals.ordinary)),
        ("user_additions", JsonValue::Number(totals.user_add)),
        ("user_direct_entries", JsonValue::Number(totals.user_direct)),
        ("user_deletions", JsonValue::Number(totals.user_delete)),
        ("user_fixed", JsonValue::Number(totals.user_fixed)),
        ("user_positions", JsonValue::Number(totals.user_position)),
        ("mixed_rules", JsonValue::Number(totals.mixed_rule)),
        ("commands", JsonValue::Number(totals.cmd)),
        ("ddcommands", JsonValue::Number(totals.ddcmd)),
        ("accepted_records", JsonValue::Number(totals.accepted)),
        ("transformed_records", JsonValue::Number(totals.transformed)),
        ("deferred_records", JsonValue::Number(totals.deferred)),
        ("rejected_records", JsonValue::Number(totals.rejected)),
        ("duplicate_records", JsonValue::Number(totals.duplicates)),
        ("conflict_records", JsonValue::Number(totals.conflicts)),
        (
            "cjk_extension_records",
            JsonValue::Number(totals.cjk_extension_records),
        ),
        (
            "emoji_or_special_records",
            JsonValue::Number(totals.emoji_or_special_records),
        ),
        ("categories", JsonValue::array(category_values)),
        ("rejections", JsonValue::array(rejected)),
    ]))
}

fn rejected_json(value: &RejectedRecord) -> JsonValue {
    JsonValue::object([
        ("source_file_id", JsonValue::string(&value.source_file_id)),
        ("physical_line", JsonValue::Number(value.physical_line)),
        ("reason_code", JsonValue::string(&value.reason_code)),
        ("safe_summary", JsonValue::string(&value.safe_summary)),
        ("line_digest", JsonValue::string(&value.line_digest)),
    ])
}

pub fn human_report(
    bundle_sha256: &str,
    bundle_bytes: usize,
    content_sha256: &str,
    totals: &BuildStatistics,
    outputs: &[(String, usize, String)],
) -> Vec<u8> {
    let mut text = String::new();
    text.push_str("# 小鹤音形生产 bundle 构建报告\n\n");
    text.push_str("- 构建时间策略：omitted\n");
    text.push_str(&format!("- 总 bundle：{bundle_bytes} bytes\n"));
    text.push_str(&format!("- 总 bundle SHA-256：`{bundle_sha256}`\n"));
    text.push_str(&format!("- 内容 SHA-256：`{content_sha256}`\n"));
    text.push_str(&format!("- 输入文件：{}\n", totals.input_file_count));
    text.push_str(&format!("- 普通记录：{}\n", totals.ordinary));
    text.push_str(&format!(
        "- 用户新增/直通/删除/固顶/位置：{}/{}/{}/{}/{}\n",
        totals.user_add,
        totals.user_direct,
        totals.user_delete,
        totals.user_fixed,
        totals.user_position
    ));
    text.push_str(&format!(
        "- 接受/转换/延期/拒绝：{}/{}/{}/{}\n",
        totals.accepted, totals.transformed, totals.deferred, totals.rejected
    ));
    text.push_str(&format!(
        "- 重复/冲突：{}/{}\n\n",
        totals.duplicates, totals.conflicts
    ));
    text.push_str("## 输出文件\n\n");
    text.push_str("| 路径 | 字节 | SHA-256 |\n| --- | ---: | --- |\n");
    for (path, bytes, hash) in outputs {
        text.push_str(&format!("| `{path}` | {bytes} | `{hash}` |\n"));
    }
    text.into_bytes()
}
