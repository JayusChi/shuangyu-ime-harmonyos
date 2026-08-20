use std::collections::BTreeMap;

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum JsonValue {
    Object(BTreeMap<String, JsonValue>),
    Array(Vec<JsonValue>),
    String(String),
    Number(u64),
    Bool(bool),
    Null,
}

impl JsonValue {
    pub fn object(values: impl IntoIterator<Item = (impl Into<String>, JsonValue)>) -> Self {
        Self::Object(
            values
                .into_iter()
                .map(|(key, value)| (key.into(), value))
                .collect(),
        )
    }

    pub fn array(values: impl IntoIterator<Item = JsonValue>) -> Self {
        Self::Array(values.into_iter().collect())
    }

    pub fn string(value: impl Into<String>) -> Self {
        Self::String(value.into())
    }

    pub fn as_object(&self) -> Option<&BTreeMap<String, JsonValue>> {
        match self {
            Self::Object(value) => Some(value),
            _ => None,
        }
    }

    pub fn as_array(&self) -> Option<&[JsonValue]> {
        match self {
            Self::Array(value) => Some(value),
            _ => None,
        }
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            Self::String(value) => Some(value),
            _ => None,
        }
    }

    pub fn as_u64(&self) -> Option<u64> {
        match self {
            Self::Number(value) => Some(*value),
            _ => None,
        }
    }

    pub fn as_bool(&self) -> Option<bool> {
        match self {
            Self::Bool(value) => Some(*value),
            _ => None,
        }
    }
}

pub fn parse(input: &[u8]) -> Result<JsonValue, String> {
    let text = std::str::from_utf8(input).map_err(|_| "JSON is not UTF-8".to_owned())?;
    let mut parser = Parser {
        input: text.as_bytes(),
        offset: 0,
    };
    let value = parser.value()?;
    parser.whitespace();
    if parser.offset != parser.input.len() {
        return Err(format!("trailing bytes at offset {}", parser.offset));
    }
    Ok(value)
}

pub fn serialize(value: &JsonValue) -> Vec<u8> {
    let mut output = String::new();
    write_value(value, 0, &mut output);
    output.push('\n');
    output.into_bytes()
}

pub fn serialize_line(value: &JsonValue) -> Vec<u8> {
    let mut output = String::new();
    write_compact(value, &mut output);
    output.push('\n');
    output.into_bytes()
}

struct Parser<'a> {
    input: &'a [u8],
    offset: usize,
}

impl Parser<'_> {
    fn value(&mut self) -> Result<JsonValue, String> {
        self.whitespace();
        match self.peek() {
            Some(b'{') => self.object(),
            Some(b'[') => self.array(),
            Some(b'"') => self.string().map(JsonValue::String),
            Some(b't') => self.literal(b"true", JsonValue::Bool(true)),
            Some(b'f') => self.literal(b"false", JsonValue::Bool(false)),
            Some(b'n') => self.literal(b"null", JsonValue::Null),
            Some(b'0'..=b'9') => self.number().map(JsonValue::Number),
            Some(value) => Err(format!(
                "unexpected byte 0x{value:02x} at offset {}",
                self.offset
            )),
            None => Err("unexpected end of JSON".to_owned()),
        }
    }

    fn object(&mut self) -> Result<JsonValue, String> {
        self.expect(b'{')?;
        let mut values = BTreeMap::new();
        self.whitespace();
        if self.consume(b'}') {
            return Ok(JsonValue::Object(values));
        }
        loop {
            self.whitespace();
            let key = self.string()?;
            self.whitespace();
            self.expect(b':')?;
            let value = self.value()?;
            if values.insert(key.clone(), value).is_some() {
                return Err(format!("duplicate object key {key:?}"));
            }
            self.whitespace();
            if self.consume(b'}') {
                break;
            }
            self.expect(b',')?;
        }
        Ok(JsonValue::Object(values))
    }

    fn array(&mut self) -> Result<JsonValue, String> {
        self.expect(b'[')?;
        let mut values = Vec::new();
        self.whitespace();
        if self.consume(b']') {
            return Ok(JsonValue::Array(values));
        }
        loop {
            values.push(self.value()?);
            self.whitespace();
            if self.consume(b']') {
                break;
            }
            self.expect(b',')?;
        }
        Ok(JsonValue::Array(values))
    }

    fn string(&mut self) -> Result<String, String> {
        self.expect(b'"')?;
        let mut output = String::new();
        let mut segment_start = self.offset;
        loop {
            let byte = self
                .peek()
                .ok_or_else(|| "unterminated string".to_owned())?;
            match byte {
                b'"' => {
                    self.push_utf8_segment(&mut output, segment_start, self.offset)?;
                    self.offset += 1;
                    return Ok(output);
                }
                b'\\' => {
                    self.push_utf8_segment(&mut output, segment_start, self.offset)?;
                    self.offset += 1;
                    let escaped = self
                        .next()
                        .ok_or_else(|| "unterminated escape".to_owned())?;
                    match escaped {
                        b'"' => output.push('"'),
                        b'\\' => output.push('\\'),
                        b'/' => output.push('/'),
                        b'b' => output.push('\u{0008}'),
                        b'f' => output.push('\u{000c}'),
                        b'n' => output.push('\n'),
                        b'r' => output.push('\r'),
                        b't' => output.push('\t'),
                        b'u' => output.push(self.unicode_escape()?),
                        _ => return Err("invalid string escape".to_owned()),
                    }
                    segment_start = self.offset;
                }
                value if value < 0x20 => return Err("control byte in string".to_owned()),
                _ => self.offset += 1,
            }
        }
    }

    fn push_utf8_segment(
        &self,
        output: &mut String,
        start: usize,
        end: usize,
    ) -> Result<(), String> {
        output.push_str(
            std::str::from_utf8(&self.input[start..end])
                .map_err(|_| format!("invalid UTF-8 at offset {start}"))?,
        );
        Ok(())
    }

    fn unicode_escape(&mut self) -> Result<char, String> {
        let start = self.offset;
        let end = start
            .checked_add(4)
            .ok_or_else(|| "escape overflow".to_owned())?;
        let bytes = self
            .input
            .get(start..end)
            .ok_or_else(|| "short unicode escape".to_owned())?;
        let digits = std::str::from_utf8(bytes).map_err(|_| "bad unicode escape".to_owned())?;
        let value = u32::from_str_radix(digits, 16).map_err(|_| "bad unicode escape".to_owned())?;
        self.offset = end;
        char::from_u32(value).ok_or_else(|| "unsupported unicode escape".to_owned())
    }

    fn number(&mut self) -> Result<u64, String> {
        let start = self.offset;
        while matches!(self.peek(), Some(b'0'..=b'9')) {
            self.offset += 1;
        }
        let text = std::str::from_utf8(&self.input[start..self.offset]).expect("ASCII digits");
        if text.len() > 1 && text.starts_with('0') {
            return Err("leading zero in number".to_owned());
        }
        text.parse().map_err(|_| "integer out of range".to_owned())
    }

    fn literal(&mut self, expected: &[u8], value: JsonValue) -> Result<JsonValue, String> {
        if self.input.get(self.offset..self.offset + expected.len()) == Some(expected) {
            self.offset += expected.len();
            Ok(value)
        } else {
            Err(format!("invalid literal at offset {}", self.offset))
        }
    }

    fn whitespace(&mut self) {
        while matches!(self.peek(), Some(b' ' | b'\n' | b'\r' | b'\t')) {
            self.offset += 1;
        }
    }

    fn expect(&mut self, expected: u8) -> Result<(), String> {
        if self.consume(expected) {
            Ok(())
        } else {
            Err(format!(
                "expected byte 0x{expected:02x} at offset {}",
                self.offset
            ))
        }
    }

    fn consume(&mut self, expected: u8) -> bool {
        if self.peek() == Some(expected) {
            self.offset += 1;
            true
        } else {
            false
        }
    }

    fn peek(&self) -> Option<u8> {
        self.input.get(self.offset).copied()
    }

    fn next(&mut self) -> Option<u8> {
        let value = self.peek()?;
        self.offset += 1;
        Some(value)
    }
}

fn write_value(value: &JsonValue, depth: usize, output: &mut String) {
    match value {
        JsonValue::Object(values) => {
            output.push('{');
            if !values.is_empty() {
                output.push('\n');
            }
            for (index, (key, value)) in values.iter().enumerate() {
                output.push_str(&"  ".repeat(depth + 1));
                quote(key, output);
                output.push_str(": ");
                write_value(value, depth + 1, output);
                if index + 1 < values.len() {
                    output.push(',');
                }
                output.push('\n');
            }
            if !values.is_empty() {
                output.push_str(&"  ".repeat(depth));
            }
            output.push('}');
        }
        JsonValue::Array(values) => {
            output.push('[');
            if !values.is_empty() {
                output.push('\n');
            }
            for (index, value) in values.iter().enumerate() {
                output.push_str(&"  ".repeat(depth + 1));
                write_value(value, depth + 1, output);
                if index + 1 < values.len() {
                    output.push(',');
                }
                output.push('\n');
            }
            if !values.is_empty() {
                output.push_str(&"  ".repeat(depth));
            }
            output.push(']');
        }
        _ => write_scalar(value, output),
    }
}

fn write_compact(value: &JsonValue, output: &mut String) {
    match value {
        JsonValue::Object(values) => {
            output.push('{');
            for (index, (key, value)) in values.iter().enumerate() {
                if index > 0 {
                    output.push(',');
                }
                quote(key, output);
                output.push(':');
                write_compact(value, output);
            }
            output.push('}');
        }
        JsonValue::Array(values) => {
            output.push('[');
            for (index, value) in values.iter().enumerate() {
                if index > 0 {
                    output.push(',');
                }
                write_compact(value, output);
            }
            output.push(']');
        }
        _ => write_scalar(value, output),
    }
}

fn write_scalar(value: &JsonValue, output: &mut String) {
    match value {
        JsonValue::String(value) => quote(value, output),
        JsonValue::Number(value) => output.push_str(&value.to_string()),
        JsonValue::Bool(value) => output.push_str(if *value { "true" } else { "false" }),
        JsonValue::Null => output.push_str("null"),
        JsonValue::Object(_) | JsonValue::Array(_) => unreachable!("container handled above"),
    }
}

fn quote(value: &str, output: &mut String) {
    use std::fmt::Write;
    output.push('"');
    for ch in value.chars() {
        match ch {
            '"' => output.push_str("\\\""),
            '\\' => output.push_str("\\\\"),
            '\n' => output.push_str("\\n"),
            '\r' => output.push_str("\\r"),
            '\t' => output.push_str("\\t"),
            value if value.is_control() => {
                write!(output, "\\u{:04x}", value as u32).expect("string write");
            }
            value => output.push(value),
        }
    }
    output.push('"');
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip_is_stable_utf8_lf() {
        let value = JsonValue::object([
            ("name", JsonValue::string("码表")),
            ("ok", JsonValue::Bool(true)),
        ]);
        let bytes = serialize(&value);
        assert_eq!(parse(&bytes).unwrap(), value);
        assert!(bytes.ends_with(b"\n"));
        assert!(!bytes.windows(2).any(|value| value == b"\r\n"));
    }
}
