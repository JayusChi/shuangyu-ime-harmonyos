use crate::{
    compare, encoding,
    model::{AuditResult, SourceFile},
    references, roles, security, sha256, syntax,
};
use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};

pub const SOURCE_ROOTS: [&str; 2] = ["码表", "小鹤音形"];

pub fn run(repo_root: &Path) -> AuditResult {
    let mut files = Vec::new();
    let mut path_conflicts = Vec::new();
    for source_root in SOURCE_ROOTS {
        let root = repo_root.join(source_root);
        if !root.is_dir() {
            files.push(error_file(
                source_root,
                "",
                format!("SOURCE_ROOT_MISSING:{source_root}"),
            ));
            continue;
        }
        let mut paths = Vec::new();
        collect_files(&root, &root, &mut paths, &mut path_conflicts);
        paths.sort_by(|a, b| {
            relative_path(&root, a)
                .as_bytes()
                .cmp(relative_path(&root, b).as_bytes())
        });
        let mut normalized = BTreeMap::<String, String>::new();
        for path in paths {
            let relative = relative_path(&root, &path);
            let norm = normalize_path(&relative);
            let key = norm.to_lowercase();
            if let Some(previous) = normalized.insert(key, relative.clone()) {
                path_conflicts.push(format!(
                    "PATH_NORMALIZATION_CONFLICT:{source_root}/{previous}:{source_root}/{relative}"
                ));
            }
            files.push(scan_file(source_root, &relative, &norm, &path));
        }
    }
    files.sort_by(|a, b| {
        (a.source_root.as_bytes(), a.relative_path.as_bytes())
            .cmp(&(b.source_root.as_bytes(), b.relative_path.as_bytes()))
    });
    path_conflicts.sort();
    path_conflicts.dedup();
    let comparisons = compare::compare(&files);
    let references = references::scan(repo_root, &files);
    let categories = roles::categories();
    let mut blocking_reasons = Vec::new();
    if files.iter().any(|file| file.read_error.is_some()) {
        blocking_reasons.push("BLOCK_UNREADABLE_SOURCE".into());
    }
    if files.iter().any(|file| {
        file.security_findings
            .iter()
            .any(|finding| finding.blocking_credential)
            && file.decision != "REJECTED"
    }) {
        blocking_reasons.push("BLOCK_EMBEDDED_CREDENTIAL".into());
    }
    if references
        .iter()
        .any(|reference| reference.blocks_conversion)
    {
        blocking_reasons.push("BLOCK_OUTSIDE_ROOT_REFERENCE".into());
    }
    if categories
        .iter()
        .any(|category| category.requires_manual_confirmation)
    {
        blocking_reasons.push("BLOCK_CATEGORY_AUTHORITY_CONFIRMATION".into());
    }
    if !path_conflicts.is_empty() {
        blocking_reasons.push("BLOCK_PATH_COLLISION".into());
    }
    blocking_reasons.sort();
    blocking_reasons.dedup();
    AuditResult {
        files,
        comparisons,
        references,
        categories,
        path_conflicts,
        blocking_reasons,
    }
}

fn collect_files(root: &Path, current: &Path, output: &mut Vec<PathBuf>, errors: &mut Vec<String>) {
    let entries = match fs::read_dir(current) {
        Ok(v) => v,
        Err(_) => {
            errors.push(format!(
                "READ_DIRECTORY_FAILED:{}",
                relative_path(root, current)
            ));
            return;
        }
    };
    let mut entries = entries.flatten().collect::<Vec<_>>();
    entries.sort_by_key(|e| e.file_name());
    for entry in entries {
        let path = entry.path();
        match entry.file_type() {
            Ok(kind) if kind.is_dir() => collect_files(root, &path, output, errors),
            Ok(kind) if kind.is_file() => output.push(path),
            Ok(kind) if kind.is_symlink() => {
                errors.push(format!("SYMLINK_REJECTED:{}", relative_path(root, &path)))
            }
            Ok(_) => {}
            Err(_) => errors.push(format!("FILE_TYPE_FAILED:{}", relative_path(root, &path))),
        }
    }
}

fn scan_file(source_root: &str, relative: &str, normalized: &str, path: &Path) -> SourceFile {
    let bytes = match fs::read(path) {
        Ok(v) => v,
        Err(_) => return error_file(source_root, relative, "FILE_READ_FAILED".into()),
    };
    let profile = encoding::profile(&bytes);
    let syntax = profile
        .text
        .as_deref()
        .map(syntax::scan)
        .unwrap_or_default();
    let security_findings = profile
        .text
        .as_deref()
        .map(security::scan)
        .unwrap_or_default();
    let extension = Path::new(relative)
        .extension()
        .and_then(|v| v.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    let (role, evidence) = roles::classify(source_root, relative, &extension, &syntax);
    let has_credential = security_findings
        .iter()
        .any(|finding| finding.blocking_credential);
    let (decision, reason) = if roles::is_first_release_audit_only(source_root, relative) {
        (
            "DEFERRED",
            "alternate export retained as audit-only evidence and excluded from first-release conversion",
        )
    } else if has_credential {
        (
            "REJECTED",
            "credential-like assigned value requires isolation and manual cleanup",
        )
    } else {
        roles::decision(
            role,
            profile.bom,
            profile.newline_style,
            security_findings.len(),
        )
    };
    SourceFile {
        source_root: source_root.into(),
        relative_path: relative.into(),
        normalized_relative_path: normalized.into(),
        file_name: Path::new(relative)
            .file_name()
            .and_then(|v| v.to_str())
            .unwrap_or(relative)
            .into(),
        extension,
        byte_size: bytes.len() as u64,
        physical_line_count: profile.physical_lines,
        non_empty_line_count: profile.non_empty_lines,
        detected_encoding: profile.encoding.into(),
        has_utf8_bom: profile.bom,
        newline_style: profile.newline_style.into(),
        final_newline: profile.final_newline,
        sha256: sha256::hex(&bytes),
        file_role: role.into(),
        role_evidence: evidence.into(),
        security_classification: if has_credential && decision == "REJECTED" {
            "credential_quarantined"
        } else if has_credential {
            "credential_blocking"
        } else if security_findings.is_empty() {
            "clean"
        } else {
            "findings_isolated"
        }
        .into(),
        decision: decision.into(),
        decision_reason: reason.into(),
        syntax,
        security_findings,
        read_error: None,
    }
}

fn error_file(root: &str, relative: &str, error: String) -> SourceFile {
    SourceFile {
        source_root: root.into(),
        relative_path: relative.into(),
        normalized_relative_path: normalize_path(relative),
        file_name: relative.into(),
        extension: String::new(),
        byte_size: 0,
        physical_line_count: 0,
        non_empty_line_count: 0,
        detected_encoding: "unreadable".into(),
        has_utf8_bom: false,
        newline_style: "Binary / Not applicable".into(),
        final_newline: false,
        sha256: String::new(),
        file_role: "unknown".into(),
        role_evidence: "read failed".into(),
        security_classification: "not_scanned".into(),
        decision: "REJECTED".into(),
        decision_reason: error.clone(),
        syntax: Default::default(),
        security_findings: vec![],
        read_error: Some(error),
    }
}

pub fn normalize_path(path: &str) -> String {
    let mapped = path
        .replace('\\', "/")
        .chars()
        .map(|ch| match ch {
            '\u{3000}' => ' ',
            value @ '\u{ff01}'..='\u{ff5e}' => {
                char::from_u32(value as u32 - 0xfee0).unwrap_or(value)
            }
            value => value,
        })
        .collect::<String>();
    let mut parts = Vec::new();
    for part in mapped.split('/') {
        match part {
            "" | "." => {}
            ".." => {
                parts.pop();
            }
            value => parts.push(value),
        }
    }
    parts.join("/")
}
fn relative_path(root: &Path, path: &Path) -> String {
    path.strip_prefix(root)
        .unwrap_or(path)
        .to_string_lossy()
        .replace('\\', "/")
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn normalizes_separators_dots_and_fullwidth_ascii() {
        assert_eq!(normalize_path("a\\.\\b\\..\\Ｏ.txt"), "a/O.txt");
    }
    #[test]
    fn missing_repo_produces_reportable_errors() {
        let result = run(Path::new("definitely-missing-audit-root"));
        assert_eq!(result.files.len(), 2);
        assert!(result
            .blocking_reasons
            .contains(&"BLOCK_UNREADABLE_SOURCE".into()));
    }
}
