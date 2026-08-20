use crate::{
    model::{Occurrence, Record, SyntaxStats},
    sha256,
};

pub fn scan(text: &str) -> SyntaxStats {
    let mut stats = SyntaxStats::default();
    for (index, raw) in text.split_terminator('\n').enumerate() {
        let line_no = index as u64 + 1;
        let line = raw.strip_suffix('\r').unwrap_or(raw);
        let trimmed = line.trim();
        let kind = classify(trimmed);
        match kind.as_str() {
            "ordinary" => stats.ordinary += 1,
            "user_deletion" => stats.user_delete += 1,
            "user_pin" => stats.user_pin += 1,
            "user_position" => stats.user_position += 1,
            "user_mixed_rule" => stats.user_mixed += 1,
            "cmd" => stats.cmd += 1,
            "ddcmd" => stats.ddcmd += 1,
            "configuration_header" => stats.config_header += 1,
            "configuration_item" => stats.config_item += 1,
            "comment" => stats.comment += 1,
            "empty" => stats.empty += 1,
            _ => stats.unrecognized += 1,
        }
        stats
            .first
            .entry(kind.clone())
            .or_insert_with(|| Occurrence {
                line: line_no,
                sample_sha256: sha256::hex(trimmed.as_bytes()),
            });
        if let Some((left, right)) = table_fields(line) {
            if matches!(
                kind.as_str(),
                "ordinary"
                    | "user_deletion"
                    | "user_pin"
                    | "user_position"
                    | "user_mixed_rule"
                    | "cmd"
                    | "ddcmd"
            ) {
                stats.records.push(Record {
                    text: left.to_owned(),
                    code: right.to_owned(),
                    syntax: kind,
                    line: line_no,
                });
            }
        }
    }
    if !text.is_empty() && !text.ends_with('\n') {
        // split_terminator already includes the final unterminated segment.
    }
    stats
}

fn classify(line: &str) -> String {
    if line.is_empty() {
        return "empty".into();
    }
    if line.starts_with("//") || line.starts_with(';') || line.starts_with("##") {
        return "comment".into();
    }
    if line.starts_with('[') && line.ends_with(']') {
        return "configuration_header".into();
    }
    if line.contains("$ddcmd") {
        return "ddcmd".into();
    }
    if line.contains("$cmd") {
        return "cmd".into();
    }
    let fields: Vec<_> = line.split('\t').collect();
    if fields.len() == 2 && !fields[0].is_empty() && !fields[1].is_empty() {
        let code = fields[1];
        let hashes = code.matches('#').count();
        if hashes > 1 {
            return "user_mixed_rule".into();
        }
        if let Some((base, marker)) = code.rsplit_once('#') {
            if base.is_empty() {
                return "unrecognized".into();
            }
            return match marker {
                "删" => "user_deletion",
                "固" => "user_pin",
                value
                    if !value.is_empty()
                        && value.bytes().all(|b| b.is_ascii_digit())
                        && !value.starts_with('0') =>
                {
                    "user_position"
                }
                _ => "unrecognized",
            }
            .into();
        }
        return "ordinary".into();
    }
    if !line.starts_with('=') && line.split_once('=').is_some() {
        return "configuration_item".into();
    }
    "unrecognized".into()
}

fn table_fields(line: &str) -> Option<(&str, &str)> {
    let mut fields = line.split('\t');
    let left = fields.next()?;
    let right = fields.next()?;
    if fields.next().is_none() {
        Some((left, right))
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn classifies_required_syntaxes() {
        let stats=scan("词\tabc\n删\tab#删\n固\tab#固\n位\tab#2\n混\tab#删#固\nx\tab$cmd(foo)\ny\tab$ddcmd(foo)\n[main]\nk=v\n// c\n\nmissing tab");
        assert_eq!(
            (
                stats.ordinary,
                stats.user_delete,
                stats.user_pin,
                stats.user_position
            ),
            (1, 1, 1, 1)
        );
        assert_eq!(
            (
                stats.user_mixed,
                stats.cmd,
                stats.ddcmd,
                stats.config_header,
                stats.config_item,
                stats.comment,
                stats.empty,
                stats.unrecognized
            ),
            (1, 1, 1, 1, 1, 1, 1, 1)
        );
    }
    #[test]
    fn rejects_bad_table_shapes() {
        let s = scan("\tabc\na\t\na\tb\tc\na\tab#0\na\tab#unknown");
        assert_eq!(s.unrecognized, 5);
    }
}
