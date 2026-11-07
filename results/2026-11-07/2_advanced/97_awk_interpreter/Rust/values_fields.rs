use std::cmp::Ordering;
#[derive(Clone)]
pub enum Value {
    Number(i64),
    String(String),
    Numeric(String, i64),
    Uninitialized
}
fn whitespace(c: char) -> bool {
    c == ' ' || c == '\t' || c == '\n'
}
impl Value {
    pub fn input(text: String) -> Self {
        let trimmed = text.trim_matches(whitespace);
        let digits = trimmed.strip_prefix('+').or_else(|| trimmed.strip_prefix('-')).unwrap_or(trimmed);
        if !digits.is_empty() && digits.bytes().all(|b| b.is_ascii_digit()) {
            let number = Self::String(text.clone()).number();
            Self::Numeric(text, number)
        } else {
            Self::String(text)
        }
    }
    pub fn number(&self) -> i64 {
        match self {
            Self::Number(n) | Self::Numeric(_, n) => *n,
            Self::Uninitialized => 0,
            Self::String(text) => {
                let text = text.trim_start_matches(whitespace);
                let negative = text.starts_with('-');
                let text = text.strip_prefix('+').or_else(|| text.strip_prefix('-')).unwrap_or(text);
                let digits: String = text.chars().take_while(|c| c.is_ascii_digit()).collect();
                let number = digits.parse::<i64>().unwrap_or(0);
                if negative {
                    -number
                } else {
                    number
                }
            }
        }
    }
    pub fn text(&self) -> String {
        match self {
            Self::Number(n) => n.to_string(),
            Self::String(s) | Self::Numeric(s, _) => s.clone(),
            Self::Uninitialized => String::new()
        }
    }
    pub fn truth(&self) -> bool {
        match self {
            Self::String(s) => !s.is_empty(),
            _ => self.number() != 0
        }
    }
    pub fn compare(&self, other: &Self) -> Ordering {
        if !matches!(self, Self::String(_)) && !matches!(other, Self::String(_)) {
            self.number().cmp(&other.number())
        } else {
            self.text().cmp(&other.text())
        }
    }
    pub fn display(&self) -> String {
        match self {
            Self::Number(n) => n.to_string(),
            Self::String(s) => quote(s),
            Self::Numeric(s, _) => format!("{} (strnum)", quote(s)),
            Self::Uninitialized => "(uninitialized)".into()
        }
    }
}
pub fn quote(text: &str) -> String {
    let mut result = String::from("\"");
    for b in text.bytes() {
        match b {
            b'"' => result.push_str("\\\""),
            b'\\' => result.push_str("\\\\"),
            10 => result.push_str("\\n"),
            9 => result.push_str("\\t"),
            32..=126 => result.push(b as char),
            _ => result.push_str(&format!("\\{:03o}", b))
        }
    }
    result.push('"');
    result
}
pub fn split(text: &str, separator: &str) -> Vec<String> {
    if separator == " " {
        text.split(whitespace).filter(|s| !s.is_empty()).map(str::to_string).collect()
    }
    else if separator.is_empty() {
        text.chars().map(|c| c.to_string()).collect()
    }
    else if text.is_empty() {
        Vec::new()
    } else {
        text.split(separator).map(str::to_string).collect()
    }
}
pub fn integer_key(text: &str) -> Option<i64> {
    if text == "0" {
        return Some(0);
    }
    let digits = text.strip_prefix('-').unwrap_or(text);
    if !digits.is_empty() && digits.as_bytes()[0] >= b'1' && digits.as_bytes()[0] <= b'9' && digits.bytes().all(|b| b.is_ascii_digit()) {
        text.parse().ok()
    } else {
        None
    }
}
pub fn key_order(a: &str, b: &str) -> Ordering {
    match (integer_key(a), integer_key(b)) {
        (Some(a), Some(b)) => a.cmp(&b),
        (Some(_), None) => Ordering::Less,
        (None, Some(_)) => Ordering::Greater,
        _ => a.cmp(b)
    }
}
pub struct Fields {
    pub record: Value,
    pub fields: Vec<Value>
}
impl Fields {
    pub fn new() -> Self {
        Self {
            record: Value::String(String::new()),
            fields: Vec::new()
        }
    }
    pub fn set(&mut self, text: String, separator: &str) {
        self.record = Value::input(text.clone());
        self.fields = split(&text, separator).into_iter().map(Value::input).collect();
    }
    pub fn get(&self, index: usize) -> Value {
        if index == 0 {
            self.record.clone()
        } else {
            self.fields.get(index - 1).cloned().unwrap_or(Value::Uninitialized)
        }
    }
    pub fn rebuild(&mut self, separator: &str) {
        self.record = Value::input(self.fields.iter().map(Value::text).collect::<Vec<_>>().join(separator));
    }
    pub fn assign(&mut self, index: usize, value: Value, fs: &str, ofs: &str) {
        if index == 0 {
            self.set(value.text(), fs);
        } else {
            if index > self.fields.len() {
                self.fields.resize(index, Value::String(String::new()));
            }
            self.fields[index - 1] = value;
            self.rebuild(ofs);
        }
    }
    pub fn nf(&mut self, size: usize, ofs: &str) {
        self.fields.resize(size, Value::String(String::new()));
        self.rebuild(ofs);
    }
}
