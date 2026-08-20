mod audit;
mod compare;
mod emit;
mod encoding;
mod json;
mod model;
mod references;
mod roles;
mod security;
mod sha256;
mod syntax;

use std::path::Path;

pub use audit::normalize_path;
pub use model::AuditResult;

pub struct AuditSummary {
    pub file_count: usize,
    pub manifest_sha256: String,
    pub contract_sha256: String,
    pub blocking_reasons: Vec<String>,
}

pub fn audit_and_write(
    repo_root: &Path,
    output: &Path,
    reports: &Path,
) -> Result<AuditSummary, String> {
    let result = audit::run(repo_root);
    let emitted = emit::write_all(&result, output, reports)?;
    Ok(AuditSummary {
        file_count: result.files.len(),
        manifest_sha256: emitted.manifest_sha256,
        contract_sha256: emitted.contract_sha256,
        blocking_reasons: result.blocking_reasons,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        fs,
        path::PathBuf,
        time::{SystemTime, UNIX_EPOCH},
    };

    fn temp(name: &str) -> PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!(
            "yinxing-audit-{name}-{}-{nonce}",
            std::process::id()
        ))
    }
    fn fixture(root: &Path) {
        fs::create_dir_all(root.join("码表/嵌套")).unwrap();
        fs::create_dir_all(root.join("小鹤音形")).unwrap();
        fs::write(
            root.join("码表/嵌套/导出 - 主码 - 表外字.txt"),
            "甲\taaaa\r\n",
        )
        .unwrap();
        fs::write(
            root.join("小鹤音形/0.0.小鹤.txt"),
            b"\xef\xbb\xbf\xe4\xb9\x99\tbbbb\n",
        )
        .unwrap();
        fs::write(
            root.join("小鹤音形/ime.android.ini"),
            "[files]\ncore=0.0.小鹤.txt\nmissing=missing.txt\npassword=fake-test-value\n",
        )
        .unwrap();
    }
    #[test]
    fn repeated_outputs_are_byte_identical_and_inputs_unchanged() {
        let root = temp("determinism");
        fixture(&root);
        let before = fs::read(root.join("小鹤音形/0.0.小鹤.txt")).unwrap();
        let out1 = root.join("out1");
        let out2 = root.join("out2");
        let rep1 = root.join("rep1");
        let rep2 = root.join("rep2");
        let a = audit_and_write(&root, &out1, &rep1).unwrap();
        let b = audit_and_write(&root, &out2, &rep2).unwrap();
        assert!(a.blocking_reasons.is_empty());
        assert_eq!(a.manifest_sha256, b.manifest_sha256);
        assert_eq!(a.contract_sha256, b.contract_sha256);
        for name in [
            "source_manifest.json",
            "conversion_contract.json",
            "category_mapping.json",
            "command_policy.json",
            "missing_references.json",
            "decisions.json",
            "comparisons.json",
            "sanitized_configuration.json",
        ] {
            assert_eq!(
                fs::read(out1.join(name)).unwrap(),
                fs::read(out2.join(name)).unwrap()
            );
        }
        let sanitized = fs::read_to_string(out1.join("sanitized_configuration.json")).unwrap();
        assert!(sanitized.contains("\"credential_containment_complete\": true"));
        assert!(!sanitized.contains("fake-test-value"));
        assert_eq!(
            before,
            fs::read(root.join("小鹤音形/0.0.小鹤.txt")).unwrap()
        );
        fs::remove_dir_all(root).unwrap();
    }
}
