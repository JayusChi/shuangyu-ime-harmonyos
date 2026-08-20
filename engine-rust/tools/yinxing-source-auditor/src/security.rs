use crate::{model::SecurityFinding, sha256};

const KEYWORDS: [(&str, &str, &str); 8] = [
    ("password", "credential", "REJECT_EMBEDDED_CREDENTIAL"),
    ("passwd", "credential", "REJECT_EMBEDDED_CREDENTIAL"),
    ("token", "credential", "REJECT_EMBEDDED_CREDENTIAL"),
    ("secret", "credential", "REJECT_EMBEDDED_CREDENTIAL"),
    ("api_key", "credential", "REJECT_EMBEDDED_CREDENTIAL"),
    ("authorization", "credential", "REJECT_EMBEDDED_CREDENTIAL"),
    ("cookie", "credential", "REJECT_EMBEDDED_CREDENTIAL"),
    ("webdav", "webdav", "REJECT_NETWORK_ACTION"),
];

pub fn scan(text: &str) -> Vec<SecurityFinding> {
    let mut output = Vec::new();
    for (index, raw) in text.lines().enumerate() {
        let lower = raw.to_ascii_lowercase();
        let line = index as u64 + 1;
        let mut types = Vec::<(&str, &str, bool)>::new();
        if lower.contains("http://") || lower.contains("https://") {
            types.push(("url", "REJECT_NETWORK_ACTION", false));
        }
        if lower.contains("ftp://") {
            types.push(("ftp", "REJECT_NETWORK_ACTION", false));
        }
        if lower.contains("intent://") || lower.contains("android.intent") {
            types.push(("android_intent", "REJECT_UNSUPPORTED_COMMAND", false));
        }
        if lower.contains("keycode_") || lower.contains("android keycode") || lower.contains("vk_")
        {
            types.push((
                "platform_specific_keycode",
                "REJECT_PLATFORM_SPECIFIC_KEYCODE",
                false,
            ));
        }
        if lower.contains(".exe") || lower.contains("cmd.exe") || lower.contains("powershell") {
            types.push(("external_process", "REJECT_EXTERNAL_PROCESS", false));
        }
        if lower.contains("cmd /c") || lower.contains("sh -c") || lower.contains("bash -c") {
            types.push(("shell_command", "REJECT_EXTERNAL_PROCESS", false));
        }
        if lower.contains("/sdcard/") || lower.contains("/storage/emulated/") {
            types.push(("android_storage_path", "REJECT_UNSAFE_PATH_ACCESS", false));
        }
        if has_windows_absolute_path(raw) {
            types.push(("windows_absolute_path", "REJECT_UNSAFE_PATH_ACCESS", false));
        }
        if lower.contains("-----begin ")
            && (lower.contains("private key") || lower.contains("certificate"))
        {
            types.push((
                "private_key_or_certificate",
                "REJECT_EMBEDDED_CREDENTIAL",
                true,
            ));
        }
        if looks_like_email(raw) {
            types.push(("email", "REJECT_EMBEDDED_ACCOUNT", false));
        }
        if looks_like_ip(raw) {
            types.push(("ip_address", "REJECT_NETWORK_ACTION", false));
        }
        for (needle, kind, reason) in KEYWORDS {
            if lower.contains(needle) {
                let blocking = kind == "credential" && has_assigned_value(&lower, needle);
                types.push((kind, reason, blocking));
            }
        }
        types.sort_unstable();
        types.dedup();
        for (kind, reason, blocking) in types {
            output.push(SecurityFinding {
                finding_type: kind.into(),
                line,
                summary_sha256: sha256::hex(raw.as_bytes()),
                reason_code: reason.into(),
                blocking_credential: blocking,
            });
        }
    }
    output.sort_by(|a, b| {
        (a.line, &a.finding_type, &a.summary_sha256).cmp(&(
            b.line,
            &b.finding_type,
            &b.summary_sha256,
        ))
    });
    output
}

fn has_assigned_value(line: &str, needle: &str) -> bool {
    let Some(offset) = line.find(needle) else {
        return false;
    };
    let tail = &line[offset + needle.len()..];
    let tail = tail.trim_start();
    for separator in ["=", ":"] {
        if let Some(value) = tail.strip_prefix(separator) {
            let value = value.trim().trim_matches(['\"', '\'']);
            return !value.is_empty() && !matches!(value, "unknown" | "pending" | "none" | "null");
        }
    }
    false
}

fn has_windows_absolute_path(line: &str) -> bool {
    let bytes = line.as_bytes();
    bytes.windows(3).enumerate().any(|(index, v)| {
        let boundary = index == 0 || !bytes[index - 1].is_ascii_alphanumeric();
        boundary && v[0].is_ascii_alphabetic() && v[1] == b':' && (v[2] == b'\\' || v[2] == b'/')
    })
}

fn looks_like_email(line: &str) -> bool {
    line.split_whitespace().any(|token| {
        let token = token.trim_matches(|c: char| {
            !c.is_ascii_alphanumeric() && c != '@' && c != '.' && c != '_' && c != '-'
        });
        let Some((left, right)) = token.split_once('@') else {
            return false;
        };
        !left.is_empty() && right.contains('.')
    })
}

fn looks_like_ip(line: &str) -> bool {
    line.split(|c: char| !(c.is_ascii_digit() || c == '.'))
        .any(|token| {
            let parts: Vec<_> = token.split('.').collect();
            parts.len() == 4
                && parts
                    .iter()
                    .all(|part| !part.is_empty() && part.parse::<u8>().is_ok())
        })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn detects_required_patterns_without_echoing_values() {
        let findings=scan("url=https://example.invalid\nip=192.0.2.1\npassword=fake-value\ntoken=pending\nrun=tool.exe\nintent://x\npath=C:\\Users\\fake");
        assert!(findings
            .iter()
            .any(|f| f.finding_type == "credential" && f.blocking_credential));
        assert!(findings.iter().any(|f| f.finding_type == "url"));
        assert!(findings
            .iter()
            .any(|f| f.finding_type == "external_process"));
        assert!(!format!("{findings:?}").contains("fake-value"));
    }
    #[test]
    fn safe_text_has_no_findings() {
        assert!(scan("普通词\tabcd").is_empty());
    }

    #[test]
    fn url_is_not_misclassified_as_windows_path() {
        let findings = scan("x=https://example.invalid");
        assert!(findings.iter().any(|finding| finding.finding_type == "url"));
        assert!(!findings
            .iter()
            .any(|finding| finding.finding_type == "windows_absolute_path"));
    }
}
