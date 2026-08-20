#[derive(Clone, Debug)]
pub enum Json {
    Object(Vec<(&'static str, Json)>),
    Array(Vec<Json>),
    String(String),
    Number(u64),
    Bool(bool),
    Null,
}

impl Json {
    pub fn string(value: impl Into<String>) -> Self {
        Self::String(value.into())
    }
    pub fn array(values: impl IntoIterator<Item = Json>) -> Self {
        Self::Array(values.into_iter().collect())
    }
    pub fn object(values: Vec<(&'static str, Json)>) -> Self {
        Self::Object(values)
    }
}

pub fn serialize(value: &Json) -> Vec<u8> {
    let mut output = String::new();
    write_value(value, 0, &mut output);
    output.push('\n');
    output.into_bytes()
}

fn write_value(value: &Json, depth: usize, output: &mut String) {
    match value {
        Json::Object(values) => {
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
        Json::Array(values) => {
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
        Json::String(value) => quote(value, output),
        Json::Number(value) => output.push_str(&value.to_string()),
        Json::Bool(value) => output.push_str(if *value { "true" } else { "false" }),
        Json::Null => output.push_str("null"),
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
                write!(output, "\\u{:04x}", value as u32).expect("string write")
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
    fn stable_utf8_lf_serialization() {
        let bytes = serialize(&Json::object(vec![
            ("name", Json::string("码表")),
            ("ok", Json::Bool(true)),
        ]));
        assert_eq!(
            String::from_utf8(bytes).unwrap(),
            "{\n  \"name\": \"码表\",\n  \"ok\": true\n}\n"
        );
    }
}
