#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TextProfile {
    pub encoding: &'static str,
    pub bom: bool,
    pub newline_style: &'static str,
    pub final_newline: bool,
    pub physical_lines: u64,
    pub non_empty_lines: u64,
    pub text: Option<String>,
}

pub fn profile(bytes: &[u8]) -> TextProfile {
    let binary = is_binary(bytes);
    let bom = bytes.starts_with(&[0xef, 0xbb, 0xbf]);
    let body = if bom { &bytes[3..] } else { bytes };
    // Strictly decoded text remains available to the syntax/security scanners even when
    // embedded control bytes make the file unsafe as a text-table input.
    let text = std::str::from_utf8(body).ok().map(str::to_owned);
    let encoding = if binary {
        "Binary / Unknown"
    } else if text.is_some() && bom {
        "UTF-8 with BOM"
    } else if text.is_some() {
        "UTF-8"
    } else if valid_gb18030(body) {
        "Possible GBK / GB18030"
    } else {
        "Other or unknown"
    };
    let (newline_style, final_newline) = newlines(bytes, binary);
    let physical_lines = physical_line_count(bytes, binary);
    let non_empty_lines = text
        .as_deref()
        .map(|value| value.lines().filter(|line| !line.trim().is_empty()).count() as u64)
        .unwrap_or(0);
    TextProfile {
        encoding,
        bom,
        newline_style,
        final_newline,
        physical_lines,
        non_empty_lines,
        text,
    }
}

fn is_binary(bytes: &[u8]) -> bool {
    if bytes.contains(&0) {
        return true;
    }
    let controls = bytes
        .iter()
        .filter(|byte| matches!(byte,0x01..=0x08|0x0b|0x0c|0x0e..=0x1f))
        .count();
    !bytes.is_empty() && controls * 100 / bytes.len() > 2
}

fn newlines(bytes: &[u8], binary: bool) -> (&'static str, bool) {
    if binary {
        return ("Binary / Not applicable", false);
    }
    if bytes.is_empty() {
        return ("No final newline", false);
    }
    let mut lf = 0;
    let mut crlf = 0;
    let mut cr = 0;
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] == b'\r' {
            if bytes.get(index + 1) == Some(&b'\n') {
                crlf += 1;
                index += 2;
            } else {
                cr += 1;
                index += 1;
            }
        } else if bytes[index] == b'\n' {
            lf += 1;
            index += 1;
        } else {
            index += 1;
        }
    }
    let final_newline = bytes.ends_with(b"\n") || bytes.ends_with(b"\r");
    if !final_newline {
        return ("No final newline", false);
    }
    let kinds = (lf > 0) as u8 + (crlf > 0) as u8 + (cr > 0) as u8;
    (
        if kinds > 1 {
            "Mixed"
        } else if crlf > 0 {
            "CRLF"
        } else if cr > 0 {
            "CR"
        } else {
            "LF"
        },
        true,
    )
}

fn physical_line_count(bytes: &[u8], binary: bool) -> u64 {
    if bytes.is_empty() || binary {
        return 0;
    }
    let mut count = 0;
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] == b'\r' {
            count += 1;
            if bytes.get(index + 1) == Some(&b'\n') {
                index += 2
            } else {
                index += 1
            }
        } else if bytes[index] == b'\n' {
            count += 1;
            index += 1
        } else {
            index += 1
        }
    }
    if bytes.ends_with(b"\n") || bytes.ends_with(b"\r") {
        count
    } else {
        count + 1
    }
}

fn valid_gb18030(bytes: &[u8]) -> bool {
    let mut index = 0;
    while index < bytes.len() {
        match bytes[index] {
            0x00..=0x7f => index += 1,
            0x81..=0xfe if matches!(bytes.get(index + 1), Some(0x40..=0x7e | 0x80..=0xfe)) => {
                index += 2
            }
            0x81..=0xfe
                if matches!(bytes.get(index + 1), Some(0x30..=0x39))
                    && matches!(bytes.get(index + 2), Some(0x81..=0xfe))
                    && matches!(bytes.get(index + 3), Some(0x30..=0x39)) =>
            {
                index += 4
            }
            _ => return false,
        }
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn detects_utf8_bom_and_newlines() {
        assert_eq!(profile(b"\xef\xbb\xbfa\r\nb\n").encoding, "UTF-8 with BOM");
        assert_eq!(profile(b"a\r\nb\n").newline_style, "Mixed");
    }
    #[test]
    fn detects_no_final_binary_and_possible_gbk() {
        assert_eq!(profile(b"a\nlast").newline_style, "No final newline");
        assert!(profile(b"a\0b").encoding.starts_with("Binary"));
        assert_eq!(
            profile(&[0xd6, 0xd0, 0xce, 0xc4]).encoding,
            "Possible GBK / GB18030"
        );
    }
    #[test]
    fn counts_physical_lines() {
        assert_eq!(profile(b"").physical_lines, 0);
        assert_eq!(profile(b"a\n").physical_lines, 1);
        assert_eq!(profile(b"a\nb").physical_lines, 2);
    }
}
