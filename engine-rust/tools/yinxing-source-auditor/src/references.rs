use crate::{
    model::{MissingReference, SourceFile},
    sha256,
};
use std::path::{Path, PathBuf};

pub fn scan(repo_root: &Path, files: &[SourceFile]) -> Vec<MissingReference> {
    let mut output = Vec::new();
    for file in files
        .iter()
        .filter(|file| file.file_role == "configuration_reference")
    {
        let path = repo_root.join(&file.source_root).join(
            file.relative_path
                .replace('/', std::path::MAIN_SEPARATOR_STR),
        );
        let Ok(bytes) = std::fs::read(path) else {
            continue;
        };
        let Ok(text) =
            std::str::from_utf8(bytes.strip_prefix(&[0xef, 0xbb, 0xbf]).unwrap_or(&bytes))
        else {
            continue;
        };
        for (index, line) in text.lines().enumerate() {
            for candidate in extract_paths(line) {
                output.push(resolve_reference(
                    repo_root,
                    file,
                    index as u64 + 1,
                    &candidate,
                ));
            }
        }
    }
    output.sort_by(|a, b| {
        (&a.reference_file, a.reference_line, &a.referenced_path).cmp(&(
            &b.reference_file,
            b.reference_line,
            &b.referenced_path,
        ))
    });
    output.dedup_by(|a, b| {
        a.reference_file == b.reference_file
            && a.reference_line == b.reference_line
            && a.referenced_path == b.referenced_path
    });
    output
}

fn extract_paths(line: &str) -> Vec<String> {
    let mut output = Vec::new();
    for token in
        line.split(|c: char| c.is_whitespace() || matches!(c, '"' | '\'' | '=' | ',' | '|' | ';'))
    {
        let clean = token.trim_matches(|c: char| matches!(c, '(' | ')' | '[' | ']' | '{' | '}'));
        let lower = clean.to_ascii_lowercase();
        if lower.ends_with(".txt") || lower.ends_with(".ini") {
            output.push(clean.to_owned());
        }
    }
    output
}

fn resolve_reference(
    repo_root: &Path,
    file: &SourceFile,
    line: u64,
    raw: &str,
) -> MissingReference {
    let absolute = is_absolute_like(raw) || raw.contains("://");
    let separators = raw.contains('\\');
    let safe = if absolute {
        format!("<redacted:{}>", &sha256::hex(raw.as_bytes())[..16])
    } else {
        raw.replace('\\', "/")
    };
    let mut resolved = false;
    let mut resolved_source = None;
    let mut case_mismatch = false;
    if !absolute {
        let normalized = raw.replace('\\', std::path::MAIN_SEPARATOR_STR);
        let direct = repo_root.join(&file.source_root).join(&normalized);
        if direct.is_file() {
            resolved = true;
            resolved_source = Some(format!(
                "{}/{}",
                file.source_root,
                normalized.replace('\\', "/")
            ));
        } else if let Some(name) = Path::new(&normalized).file_name() {
            let root = repo_root.join(&file.source_root);
            if let Some(found) = find_case_insensitive(&root, name.to_string_lossy().as_ref()) {
                resolved = true;
                case_mismatch = found.file_name().is_some_and(|v| v != name);
                resolved_source = Some(format!("{}/{}", file.source_root, relative(&root, &found)));
            }
        }
    }
    let (resolution_decision, reason_code, next_stage_action, blocks_conversion) =
        reference_resolution(&safe, resolved, absolute);
    MissingReference {
        referenced_path: safe,
        reference_file: file.source_id(),
        reference_line: line,
        reference_role: "configuration_file_mapping".into(),
        resolved,
        resolved_source,
        missing_reason: if resolved {
            None
        } else if absolute {
            Some("outside_allowed_roots".into())
        } else {
            Some("referenced_file_not_found".into())
        },
        case_mismatch,
        path_separator_issue: separators,
        outside_allowed_roots: absolute,
        resolution_decision: resolution_decision.into(),
        reason_code: reason_code.into(),
        next_stage_action: next_stage_action.into(),
        blocks_conversion,
    }
}

fn reference_resolution(
    path: &str,
    resolved: bool,
    outside_allowed_roots: bool,
) -> (&'static str, &'static str, &'static str, bool) {
    if resolved {
        return (
            "ACCEPTED",
            "REFERENCE_RESOLVED",
            "retain as non-executable source evidence",
            false,
        );
    }
    if outside_allowed_roots {
        return (
            "REJECTED",
            "REJECT_OUTSIDE_ALLOWED_ROOTS",
            "do not read or convert the external target",
            true,
        );
    }
    let lower = path.to_ascii_lowercase();
    if path.contains('*') {
        return (
            "REJECTED",
            "REJECT_WILDCARD_REFERENCE",
            "do not expand legacy platform globs",
            false,
        );
    }
    if lower.contains("$userpath$") || path.contains("用户") {
        return (
            "REJECTED",
            "REJECT_DYNAMIC_USER_REFERENCE",
            "use the existing project user-lexicon contract instead",
            false,
        );
    }
    if lower.contains("android") || path.contains("安卓") || lower.contains("-win") {
        return (
            "REJECTED",
            "REJECT_PLATFORM_REFERENCE",
            "exclude the missing Android or Windows resource",
            false,
        );
    }
    if lower.starts_with("sys-") {
        return (
            "REJECTED",
            "REJECT_UNSUPPORTED_SYSTEM_REFERENCE",
            "exclude the unavailable legacy system action table",
            false,
        );
    }
    (
        "DEFERRED",
        "DEFER_MISSING_OPTIONAL_RESOURCE",
        "retain the reference for a later customer delivery; do not synthesize data",
        false,
    )
}

fn is_absolute_like(value: &str) -> bool {
    Path::new(value).is_absolute() || {
        let b = value.as_bytes();
        b.len() > 2 && b[0].is_ascii_alphabetic() && b[1] == b':' && (b[2] == b'\\' || b[2] == b'/')
    }
}
fn find_case_insensitive(root: &Path, name: &str) -> Option<PathBuf> {
    let entries = std::fs::read_dir(root).ok()?;
    for entry in entries.flatten() {
        if entry
            .file_name()
            .to_string_lossy()
            .eq_ignore_ascii_case(name)
        {
            return Some(entry.path());
        }
    }
    None
}
fn relative(root: &Path, path: &Path) -> String {
    path.strip_prefix(root)
        .unwrap_or(path)
        .to_string_lossy()
        .replace('\\', "/")
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn extracts_only_file_references() {
        assert_eq!(
            extract_paths("a=foo.txt b=https://x.invalid c=no"),
            vec!["foo.txt"]
        );
    }
    #[test]
    fn redacts_absolute_paths() {
        let f = SourceFile {
            source_root: "小鹤音形".into(),
            relative_path: "a.ini".into(),
            normalized_relative_path: "a.ini".into(),
            file_name: "a.ini".into(),
            extension: "ini".into(),
            byte_size: 0,
            physical_line_count: 0,
            non_empty_line_count: 0,
            detected_encoding: "UTF-8".into(),
            has_utf8_bom: false,
            newline_style: "LF".into(),
            final_newline: true,
            sha256: String::new(),
            file_role: "configuration_reference".into(),
            role_evidence: String::new(),
            security_classification: String::new(),
            decision: String::new(),
            decision_reason: String::new(),
            syntax: Default::default(),
            security_findings: vec![],
            read_error: None,
        };
        let r = resolve_reference(Path::new("."), &f, 1, "C:\\secret\\x.txt");
        assert!(r.referenced_path.starts_with("<redacted:"));
        assert!(r.outside_allowed_roots);
        assert!(r.blocks_conversion);
    }

    #[test]
    fn unresolved_optional_and_platform_references_are_deterministically_disposed() {
        assert_eq!(
            reference_resolution("英文补全.txt", false, false).0,
            "DEFERRED"
        );
        assert_eq!(
            reference_resolution("2.3.用户-安卓.txt", false, false).0,
            "REJECTED"
        );
        assert!(!reference_resolution("2.3.用户-安卓.txt", false, false).3);
    }
}
