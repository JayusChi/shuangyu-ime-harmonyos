use crate::model::{Category, SyntaxStats};

pub fn classify(
    source_root: &str,
    path: &str,
    extension: &str,
    syntax: &SyntaxStats,
) -> (&'static str, &'static str) {
    let leaf = path.rsplit('/').next().unwrap_or(path);
    let role = match leaf {
        "0.0.小鹤.txt" => "core_code_table",
        "1.0.分类.txt" => "category_table",
        "2.1.一简次选.txt" => "one_key_secondary_table",
        "2.2.二简次选.txt" | "导出 - 辅码 - 「二简次选」.txt" => {
            "two_key_secondary_table"
        }
        "2.4.表外字.txt" | "导出 - 主码 - 表外字.txt" => "out_of_table_character",
        "2.5.全码词.txt" | "导出 - 主码 - 全码词.txt" => "full_code_word",
        "2.8.生僻字.txt" => "rare_character",
        "2.9.全码字.txt" | "导出 - 次显 - 「全码字」.txt" => "full_code_character",
        "导出 - 主码 - 次选字词.txt" => "secondary_candidate_table",
        "导出 - 主码 - 用户.txt" => "user_mixed_rule",
        "0.2.拼字.txt" | "导出 - 主码 - 拼字.txt" => "spelling_resource",
        "hans2hant.txt" => "simplified_traditional_resource",
        "2.6.符号.txt" | "导出 - 主码 - Ｏ符.txt" => "symbol_table",
        "2.7.符号组.txt" => "symbol_group",
        "1.2.快符-外接.txt" | "导出 - 主码 - 快符.txt" => "quick_symbol",
        "2.3.直通-安卓.txt" | "导出 - 主码 - 直通.txt" => "direct_input",
        "2.6.符号-安卓.txt" | "2.7.符号组-安卓.txt" => "android_reference",
        "ime.android.ini" => "configuration_reference",
        "导出 - 主码 - 随心.txt" => "user_addition",
        _ => "unknown",
    };
    let content_ok = if extension == "ini" {
        syntax.config_header + syntax.config_item > 0
    } else {
        syntax.ordinary
            + syntax.user_delete
            + syntax.user_pin
            + syntax.user_position
            + syntax.user_mixed
            + syntax.cmd
            + syntax.ddcmd
            > 0
    };
    if role == "unknown" {
        return ("unknown", "no stable path/content rule matched");
    }
    if !content_ok {
        return (
            "unknown",
            "path suggested a role but content did not match expected text/config syntax",
        );
    }
    let evidence = if source_root == "小鹤音形" {
        "numbered delivery name plus matching content syntax"
    } else {
        "export name plus matching content syntax"
    };
    (role, evidence)
}

pub fn decision(
    role: &str,
    has_bom: bool,
    newline: &str,
    security_count: usize,
) -> (&'static str, &'static str) {
    if security_count > 0
        && matches!(
            role,
            "configuration_reference" | "direct_input" | "android_reference"
        )
    {
        return (
            "REJECTED",
            "platform/network/command material is isolated from conversion",
        );
    }
    if security_count > 0 {
        return (
            "TRANSFORM",
            "security-matched records must be isolated before otherwise eligible content is converted",
        );
    }
    match role {
        "core_code_table"
        | "category_table"
        | "one_key_secondary_table"
        | "two_key_secondary_table"
        | "out_of_table_character"
        | "full_code_word"
        | "rare_character"
        | "full_code_character" => {
            if has_bom || newline != "LF" {
                ("TRANSFORM","approved table role requires deterministic BOM/newline/header normalization in 11.6.2C")
            } else {
                ("ACCEPTED", "approved table role and byte format")
            }
        }
        "secondary_candidate_table" | "user_addition" | "user_mixed_rule" | "symbol_table" => (
            "TRANSFORM",
            "eligible content requires explicit merge or record transformation",
        ),
        "spelling_resource"
        | "simplified_traditional_resource"
        | "symbol_group"
        | "quick_symbol" => (
            "DEFERRED",
            "feature is retained but outside the first conversion scope",
        ),
        "direct_input" | "android_reference" | "configuration_reference" => (
            "REJECTED",
            "platform-specific configuration or actions cannot enter HarmonyOS resources",
        ),
        _ => ("REJECTED", "unknown role cannot enter conversion"),
    }
}

pub fn is_first_release_audit_only(source_root: &str, path: &str) -> bool {
    source_root == "码表"
        && matches!(
            path,
            "导出 - 主码 - 次选字词.txt"
                | "导出 - 辅码 - 「二简次选」.txt"
                | "导出 - 主码 - 表外字.txt"
                | "导出 - 主码 - 全码词.txt"
                | "导出 - 次显 - 「全码字」.txt"
        )
}

pub fn categories() -> Vec<Category> {
    vec![
        category(
            "core",
            "核心主表",
            "core_code_table",
            (
                Some("小鹤音形/0.0.小鹤.txt"),
                &[],
                &[],
                &["小鹤音形/0.0.小鹤.txt"],
            ),
            "Only numbered core source enters the first release.",
        ),
        category(
            "category-secondary",
            "分类/次选",
            "category_table",
            (
                Some("小鹤音形/1.0.分类.txt"),
                &[],
                &["码表/导出 - 主码 - 次选字词.txt"],
                &["小鹤音形/1.0.分类.txt"],
            ),
            "The overlapping export remains audit-only and is not merged.",
        ),
        category(
            "one-key-secondary",
            "一简次选",
            "one_key_secondary_table",
            (
                Some("小鹤音形/2.1.一简次选.txt"),
                &[],
                &[],
                &["小鹤音形/2.1.一简次选.txt"],
            ),
            "Unique numbered source enters the first release.",
        ),
        category(
            "two-key-secondary",
            "二简次选",
            "two_key_secondary_table",
            (
                Some("小鹤音形/2.2.二简次选.txt"),
                &[],
                &["码表/导出 - 辅码 - 「二简次选」.txt"],
                &["小鹤音形/2.2.二简次选.txt"],
            ),
            "The alternate export remains audit-only and is not merged.",
        ),
        category(
            "out-of-table-character",
            "表外字",
            "out_of_table_character",
            (
                Some("小鹤音形/2.4.表外字.txt"),
                &[],
                &["码表/导出 - 主码 - 表外字.txt"],
                &["小鹤音形/2.4.表外字.txt"],
            ),
            "The alternate export remains audit-only and is not merged.",
        ),
        category(
            "full-code-word",
            "全码词",
            "full_code_word",
            (
                Some("小鹤音形/2.5.全码词.txt"),
                &[],
                &["码表/导出 - 主码 - 全码词.txt"],
                &["小鹤音形/2.5.全码词.txt"],
            ),
            "The alternate export remains audit-only and is not merged.",
        ),
        category(
            "rare-character",
            "生僻字",
            "rare_character",
            (
                Some("小鹤音形/2.8.生僻字.txt"),
                &[],
                &[],
                &["小鹤音形/2.8.生僻字.txt"],
            ),
            "Unique numbered source enters the first release.",
        ),
        category(
            "full-code-character",
            "全码字",
            "full_code_character",
            (
                Some("小鹤音形/2.9.全码字.txt"),
                &[],
                &["码表/导出 - 次显 - 「全码字」.txt"],
                &["小鹤音形/2.9.全码字.txt"],
            ),
            "The alternate export remains audit-only and is not merged.",
        ),
    ]
}

fn category(
    category_id: &'static str,
    display_name: &'static str,
    role: &'static str,
    sources: (
        Option<&'static str>,
        &'static [&'static str],
        &'static [&'static str],
        &'static [&'static str],
    ),
    notes: &'static str,
) -> Category {
    let (authoritative_source, supplemental_sources, audit_only_sources, merge_order) = sources;
    Category {
        category_id,
        display_name,
        role,
        authoritative_source,
        supplemental_sources,
        audit_only_sources,
        merge_order,
        default_enabled: true,
        first_release_scope: "authoritative_source_only",
        conflict_policy: "audit-only alternatives are excluded; no cross-source merge",
        duplicate_policy: "stable_first_within_authoritative_source_order",
        unsupported_record_policy: "reject_with_source_line",
        confirmation_status: "frozen_by_user_authorization_2026-07-22",
        requires_manual_confirmation: false,
        notes,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn all_categories_have_at_most_one_authority_and_stable_order() {
        let values = categories();
        assert_eq!(values.len(), 8);
        assert!(values
            .iter()
            .all(|c| c.authoritative_source.is_some() && !c.merge_order.is_empty()));
        assert!(values.iter().all(|c| !c.requires_manual_confirmation));
        assert!(values.iter().all(|c| c
            .audit_only_sources
            .iter()
            .all(|source| !c.merge_order.contains(source))));
    }
}
