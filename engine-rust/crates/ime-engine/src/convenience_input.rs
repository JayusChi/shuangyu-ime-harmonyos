//! Shared, bounded convenience composition for touch and physical keyboards.
use engine_protocol::{CompositionResult, FormalCandidate, ProtocolParserState};

#[derive(Clone, Debug, Default)]
pub(crate) struct ConvenienceInput {
    raw: String,
    closing_quote: bool,
}
impl ConvenienceInput {
    pub fn active(&self) -> bool {
        !self.raw.is_empty()
    }
    pub fn clear(&mut self) {
        self.raw.clear();
    }
    pub fn process(&mut self, key: char) -> CompositionResult {
        if self.raw.len() == 1 && self.raw.starts_with(key) {
            let text = if key == '\'' {
                let text = if self.closing_quote { "’" } else { "‘" };
                self.closing_quote = !self.closing_quote;
                text
            } else {
                "="
            };
            self.clear();
            return CompositionResult::committed(text);
        }
        if self.raw.len() < 128 && (key.is_ascii_alphanumeric() || "='.+-*/_@".contains(key)) {
            self.raw.push(key);
        }
        self.state()
    }
    pub fn backspace(&mut self) -> CompositionResult {
        self.raw.pop();
        self.state()
    }
    pub fn select(&mut self, index: usize) -> Option<CompositionResult> {
        let text = self.state().candidates.get(index)?.text.clone();
        self.clear();
        Some(CompositionResult::committed(&text))
    }
    pub fn state(&self) -> CompositionResult {
        let values = self.raw.get(1..).map(candidates).unwrap_or_default();
        let items = values
            .into_iter()
            .enumerate()
            .map(|(index, text)| FormalCandidate {
                id: format!("convenience:{}:{index}", self.raw),
                text,
                display_text: String::new(),
                reading: self.raw.clone(),
                source: "convenience".into(),
                consumed_raw_len: self.raw.len() as u32,
            })
            .collect();
        CompositionResult::success(
            &self.raw,
            &self.raw,
            Vec::new(),
            "",
            if self.raw.is_empty() {
                ProtocolParserState::Empty
            } else {
                ProtocolParserState::Complete
            },
        )
        .with_candidates(items, 0, false, false)
    }
}
fn candidates(input: &str) -> Vec<String> {
    if input.is_empty() {
        return vec![];
    }
    if input.bytes().any(|b| b.is_ascii_alphabetic()) {
        return vec![input.to_owned()];
    }
    if input.contains(['+', '-', '*', '/']) {
        return calculate(input)
            .map(|value| vec![format!("{input}={value}"), value])
            .unwrap_or_default();
    }
    if input.matches('.').count() == 2 {
        return date(input).unwrap_or_default();
    }
    money(input).into_iter().collect()
}
fn date(input: &str) -> Option<Vec<String>> {
    let parts: Vec<_> = input.split('.').collect();
    if parts.len() != 3
        || parts[..2]
            .iter()
            .any(|p| p.is_empty() || !p.bytes().all(|b| b.is_ascii_digit()))
    {
        return None;
    }
    let y: u32 = parts[0].parse().ok()?;
    let m: u32 = parts[1].parse().ok()?;
    if !(1..=9999).contains(&y) || !(1..=12).contains(&m) {
        return None;
    }
    if parts[2].is_empty() {
        return Some(vec![format!("{y}年{m}月")]);
    }
    if !parts[2].bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let d: u32 = parts[2].parse().ok()?;
    let leap = y.is_multiple_of(4) && (!y.is_multiple_of(100) || y.is_multiple_of(400));
    let max = [
        31,
        if leap { 29 } else { 28 },
        31,
        30,
        31,
        30,
        31,
        31,
        30,
        31,
        30,
        31,
    ][(m - 1) as usize];
    if d == 0 || d > max {
        return None;
    }
    Some(vec![
        format!("{y}年{m}月{d}日"),
        format!("{y:04}-{m:02}-{d:02}"),
    ])
}
const DIGITS: [&str; 10] = ["零", "壹", "贰", "叁", "肆", "伍", "陆", "柒", "捌", "玖"];
fn money(input: &str) -> Option<String> {
    let mut parts = input.split('.');
    let whole = parts.next()?;
    let fraction = parts.next().unwrap_or("");
    if parts.next().is_some()
        || whole.is_empty()
        || whole.len() > 16
        || fraction.len() > 2
        || !whole
            .bytes()
            .chain(fraction.bytes())
            .all(|b| b.is_ascii_digit())
    {
        return None;
    }
    let number: u64 = whole.parse().ok()?;
    let mut text = String::new();
    let mut gap = false;
    for group_index in (0..4).rev() {
        let group = (number / 10000_u64.pow(group_index) % 10000) as usize;
        if group == 0 {
            if !text.is_empty() {
                gap = true;
            }
            continue;
        }
        if !text.is_empty() && (gap || group < 1000) {
            text.push('零');
        }
        let mut group_text = String::new();
        let mut zero = false;
        for pos in (0..4).rev() {
            let digit = group / 10_usize.pow(pos) % 10;
            if digit == 0 {
                if !group_text.is_empty() {
                    zero = true;
                }
                continue;
            }
            if zero {
                group_text.push('零');
                zero = false;
            }
            group_text.push_str(DIGITS[digit]);
            group_text.push_str(["", "拾", "佰", "仟"][pos as usize]);
        }
        text.push_str(&group_text);
        text.push_str(["", "万", "亿", "兆"][group_index as usize]);
        gap = false;
    }
    if text.is_empty() {
        text.push('零');
    }
    text.push('元');
    let j = fraction.as_bytes().first().map(|b| b - b'0').unwrap_or(0) as usize;
    let f = fraction.as_bytes().get(1).map(|b| b - b'0').unwrap_or(0) as usize;
    if j > 0 {
        text.push_str(DIGITS[j]);
        text.push('角');
    }
    if f > 0 {
        if j == 0 {
            text.push('零');
        }
        text.push_str(DIGITS[f]);
        text.push('分');
    } else {
        text.push('整');
    }
    Some(text)
}
// Rational arithmetic avoids binary floating-point artifacts such as 0.1+0.2.
#[derive(Clone, Copy)]
struct Rational(i128, i128);
impl Rational {
    fn new(mut n: i128, mut d: i128) -> Option<Self> {
        if d == 0 {
            return None;
        }
        if d < 0 {
            n = n.checked_neg()?;
            d = d.checked_neg()?;
        }
        let (mut a, mut b) = (n.checked_abs()?, d);
        while b != 0 {
            let r = a % b;
            a = b;
            b = r;
        }
        Some(Self(n / a, d / a))
    }
    fn op(self, other: Self, op: u8) -> Option<Self> {
        let Self(a, b) = self;
        let Self(c, d) = other;
        match op {
            b'+' => Self::new(
                a.checked_mul(d)?.checked_add(c.checked_mul(b)?)?,
                b.checked_mul(d)?,
            ),
            b'-' => Self::new(
                a.checked_mul(d)?.checked_sub(c.checked_mul(b)?)?,
                b.checked_mul(d)?,
            ),
            b'*' => Self::new(a.checked_mul(c)?, b.checked_mul(d)?),
            b'/' => Self::new(a.checked_mul(d)?, b.checked_mul(c)?),
            _ => None,
        }
    }
    fn display(self) -> Option<String> {
        let negative = self.0 < 0;
        let n = self.0.checked_abs()?;
        let scale = 10_000_000_000_i128;
        let rounded = n.checked_mul(scale)?.checked_add(self.1 / 2)? / self.1;
        let mut s = format!("{}.{:010}", rounded / scale, rounded % scale);
        while s.ends_with('0') {
            s.pop();
        }
        if s.ends_with('.') {
            s.pop();
        }
        if negative && rounded != 0 {
            s.insert(0, '-');
        }
        Some(s)
    }
}
fn calculate(input: &str) -> Option<String> {
    let bytes = input.as_bytes();
    let mut i = 0;
    let mut total = Rational(0, 1);
    let mut add = b'+';
    fn number(bytes: &[u8], i: &mut usize) -> Option<Rational> {
        let mut sign = 1;
        if bytes.get(*i) == Some(&b'-') {
            sign = -1;
            *i += 1;
        } else if bytes.get(*i) == Some(&b'+') {
            *i += 1;
        }
        let (mut n, mut d) = (0_i128, 1_i128);
        let (mut dot, mut digits) = (false, 0);
        while let Some(&b) = bytes.get(*i) {
            if b == b'.' && !dot {
                dot = true;
                *i += 1;
                continue;
            }
            if !b.is_ascii_digit() {
                break;
            }
            digits += 1;
            n = n.checked_mul(10)?.checked_add((b - b'0') as i128)?;
            if dot {
                d = d.checked_mul(10)?;
            }
            *i += 1;
        }
        if digits == 0 {
            return None;
        }
        Rational::new(n * sign, d)
    }
    while i < bytes.len() {
        let mut term = number(bytes, &mut i)?;
        while matches!(bytes.get(i), Some(b'*' | b'/')) {
            let op = bytes[i];
            i += 1;
            term = term.op(number(bytes, &mut i)?, op)?;
        }
        total = total.op(term, add)?;
        if i == bytes.len() {
            return total.display();
        }
        add = bytes[i];
        if !matches!(add, b'+' | b'-') {
            return None;
        }
        i += 1;
    }
    None
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn requested_formats() {
        assert_eq!(candidates("1234.5"), vec!["壹仟贰佰叁拾肆元伍角整"]);
        assert_eq!(candidates("2026.8."), vec!["2026年8月"]);
        assert_eq!(candidates("2026.5.5"), vec!["2026年5月5日", "2026-05-05"]);
        assert_eq!(candidates("123+5*6"), vec!["123+5*6=153", "153"]);
        assert_eq!(candidates("OpenAI2026"), vec!["OpenAI2026"]);
    }
    #[test]
    fn candidate_identity_tracks_edits_and_kind_changes() {
        let mut q = ConvenienceInput::default();
        q.process('=');
        let money_one = q.process('1').candidates[0].clone();
        let money_twelve = q.process('2').candidates[0].clone();
        assert_ne!(money_one.id, money_twelve.id);
        assert_ne!(money_one.text, money_twelve.text);
        q.process('+');
        let calculation = q.process('3');
        assert_ne!(money_twelve.id, calculation.candidates[0].id);
        assert_eq!(calculation.candidates[0].text, "12+3=15");
        assert_ne!(calculation.candidates[0].id, calculation.candidates[1].id);
        assert_eq!(q.state().candidates[0].id, calculation.candidates[0].id);
        q.backspace();
        assert_eq!(q.backspace().candidates[0].id, money_twelve.id);
    }
    #[test]
    fn validation_and_arithmetic() {
        for raw in ["2026.2.29", "2026.13.", "1/0", "1+", "1..2", "1.234"] {
            assert!(candidates(raw).is_empty(), "{raw}");
        }
        assert_eq!(candidates("2024.2.29").len(), 2);
        for (raw, result) in [
            ("0.1+0.2", "0.3"),
            ("10/4", "2.5"),
            ("2*-3+1", "-5"),
            ("1/3", "0.3333333333"),
            ("2/3", "0.6666666667"),
        ] {
            assert_eq!(calculate(raw).as_deref(), Some(result));
        }
        assert_eq!(money("10001.01").as_deref(), Some("壹万零壹元零壹分"));
        assert_eq!(money("0").as_deref(), Some("零元整"));
    }
    #[test]
    fn guide_edit_select_and_repeat() {
        let mut q = ConvenienceInput::default();
        q.process('=');
        assert_eq!(q.process('=').commit_text, "=");
        q.process('\'');
        assert_eq!(q.process('\'').commit_text, "‘");
        q.clear();
        q.process('\'');
        assert_eq!(q.process('\'').commit_text, "’");
        for c in "=12+3".chars() {
            q.process(c);
        }
        assert_eq!(q.select(1).unwrap().commit_text, "15");
        assert!(!q.active());
        q.process('=');
        assert_eq!(q.backspace().raw_input, "");
    }
}
