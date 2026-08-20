use std::collections::BTreeMap;

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum JsonValue {
    Object(BTreeMap<String, JsonValue>),
    Array(Vec<JsonValue>),
    String(String),
    Number(i64),
    Bool(bool),
    Null,
}

pub fn parse_json(input: &str) -> Result<JsonValue, String> {
    let mut parser = Parser {
        chars: input.chars().collect(),
        index: 0,
    };
    let value = parser.parse_value()?;
    parser.skip_ws();
    if parser.index != parser.chars.len() {
        return Err("trailing characters after JSON value".to_owned());
    }
    Ok(value)
}

struct Parser {
    chars: Vec<char>,
    index: usize,
}

impl Parser {
    fn parse_value(&mut self) -> Result<JsonValue, String> {
        self.skip_ws();
        match self.peek() {
            Some('{') => self.parse_object(),
            Some('[') => self.parse_array(),
            Some('"') => self.parse_string().map(JsonValue::String),
            Some('-') | Some('0'..='9') => self.parse_number().map(JsonValue::Number),
            Some('t') => {
                self.expect_literal("true")?;
                Ok(JsonValue::Bool(true))
            }
            Some('f') => {
                self.expect_literal("false")?;
                Ok(JsonValue::Bool(false))
            }
            Some('n') => {
                self.expect_literal("null")?;
                Ok(JsonValue::Null)
            }
            Some(ch) => Err(format!("unexpected JSON character: {ch}")),
            None => Err("unexpected end of JSON".to_owned()),
        }
    }

    fn parse_object(&mut self) -> Result<JsonValue, String> {
        self.expect_char('{')?;
        let mut object = BTreeMap::new();
        self.skip_ws();
        if self.consume_if('}') {
            return Ok(JsonValue::Object(object));
        }

        loop {
            self.skip_ws();
            let key = self.parse_string()?;
            self.skip_ws();
            self.expect_char(':')?;
            let value = self.parse_value()?;
            object.insert(key, value);
            self.skip_ws();
            if self.consume_if('}') {
                break;
            }
            self.expect_char(',')?;
        }

        Ok(JsonValue::Object(object))
    }

    fn parse_array(&mut self) -> Result<JsonValue, String> {
        self.expect_char('[')?;
        let mut array = Vec::new();
        self.skip_ws();
        if self.consume_if(']') {
            return Ok(JsonValue::Array(array));
        }

        loop {
            array.push(self.parse_value()?);
            self.skip_ws();
            if self.consume_if(']') {
                break;
            }
            self.expect_char(',')?;
        }

        Ok(JsonValue::Array(array))
    }

    fn parse_string(&mut self) -> Result<String, String> {
        self.expect_char('"')?;
        let mut value = String::new();
        loop {
            let ch = self
                .next()
                .ok_or_else(|| "unterminated JSON string".to_owned())?;
            match ch {
                '"' => break,
                '\\' => value.push(self.parse_escape()?),
                c if c.is_control() => {
                    return Err("control character in JSON string".to_owned());
                }
                c => value.push(c),
            }
        }
        Ok(value)
    }

    fn parse_escape(&mut self) -> Result<char, String> {
        match self
            .next()
            .ok_or_else(|| "unterminated JSON escape".to_owned())?
        {
            '"' => Ok('"'),
            '\\' => Ok('\\'),
            '/' => Ok('/'),
            'b' => Ok('\u{0008}'),
            'f' => Ok('\u{000c}'),
            'n' => Ok('\n'),
            'r' => Ok('\r'),
            't' => Ok('\t'),
            'u' => self.parse_unicode_escape(),
            ch => Err(format!("unsupported JSON escape: {ch}")),
        }
    }

    fn parse_unicode_escape(&mut self) -> Result<char, String> {
        let mut code = 0_u32;
        for _ in 0..4 {
            let ch = self
                .next()
                .ok_or_else(|| "short unicode escape".to_owned())?;
            code = (code << 4)
                + ch.to_digit(16)
                    .ok_or_else(|| format!("invalid unicode escape digit: {ch}"))?;
        }
        char::from_u32(code).ok_or_else(|| "invalid unicode scalar".to_owned())
    }

    fn parse_number(&mut self) -> Result<i64, String> {
        let start = self.index;
        self.consume_if('-');
        while matches!(self.peek(), Some('0'..='9')) {
            self.index += 1;
        }
        self.chars[start..self.index]
            .iter()
            .collect::<String>()
            .parse::<i64>()
            .map_err(|err| format!("invalid JSON number: {err}"))
    }

    fn expect_literal(&mut self, expected: &str) -> Result<(), String> {
        for expected_ch in expected.chars() {
            let actual = self
                .next()
                .ok_or_else(|| format!("expected literal {expected}"))?;
            if actual != expected_ch {
                return Err(format!("expected literal {expected}"));
            }
        }
        Ok(())
    }

    fn skip_ws(&mut self) {
        while matches!(self.peek(), Some(' ' | '\n' | '\r' | '\t')) {
            self.index += 1;
        }
    }

    fn expect_char(&mut self, expected: char) -> Result<(), String> {
        match self.next() {
            Some(actual) if actual == expected => Ok(()),
            Some(actual) => Err(format!("expected {expected}, found {actual}")),
            None => Err(format!("expected {expected}, found end of JSON")),
        }
    }

    fn consume_if(&mut self, expected: char) -> bool {
        if self.peek() == Some(expected) {
            self.index += 1;
            true
        } else {
            false
        }
    }

    fn peek(&self) -> Option<char> {
        self.chars.get(self.index).copied()
    }

    fn next(&mut self) -> Option<char> {
        let ch = self.peek()?;
        self.index += 1;
        Some(ch)
    }
}
