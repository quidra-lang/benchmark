use std::collections::BTreeSet;
#[derive(Clone)]
pub struct Token {
    pub kind: &'static str,
    pub text: String,
    pub line: i64,
    pub space: bool,
    pub hide: BTreeSet<String>
}
impl Token {
    pub fn new(kind: &'static str, text: String, line: i64, space: bool) -> Self {
        Self {
            kind,
            text,
            line,
            space,
            hide: BTreeSet::new()
        }
    }
}
#[derive(Clone)]
pub struct LogicalLine {
    pub tokens: Vec<Token>,
    pub start: usize,
    pub end: usize
}
pub fn one(text: &str, header: bool) -> (&'static str, usize) {
    let bytes = text.as_bytes();
    if bytes.is_empty() {
        return ("other", 0);
    }
    let c = bytes[0];
    if header && c == b'<' {
        if let Some(end) = text.find('>') {
            if !text[..end].contains('\n') {
                return ("header", end + 1);
            }
        }
    }
    if c.is_ascii_alphabetic() || c == b'_' {
        let mut n = 1;
        while n < bytes.len() && (bytes[n].is_ascii_alphanumeric() || bytes[n] == b'_') {
            n += 1;
        }
        return ("identifier", n);
    }
    if c.is_ascii_digit() || (c == b'.' && bytes.get(1).map_or(false, |b| b.is_ascii_digit())) {
        let mut n = 1;
        while n < bytes.len() {
            if b"eEpP".contains(&bytes[n]) && bytes.get(n + 1).map_or(false, |b| *b == b'+' || *b == b'-') {
                n += 2;
            }
            else if bytes[n].is_ascii_alphanumeric() || bytes[n] == b'_' || bytes[n] == b'.' {
                n += 1;
            } else {
                break;
            }
        }
        return ("number", n);
    }
    if c == b'\'' || c == b'"' {
        let mut n = 1;
        while n < bytes.len() && bytes[n] != b'\n' {
            if bytes[n] == c {
                return (if c == b'\'' {
                    "character"
                } else {
                    "string"
                }, n + 1);
            }
            if bytes[n] == b'\\' && n + 1 < bytes.len() && bytes[n + 1] != b'\n' {
                n += 2;
            } else {
                n += 1;
            }
        }
    }
    for punct in ["...", "<<=", ">>=", "->", "++", "--", "<<", ">>", "<=", ">=", "==", "!=", "&&", "||", "*=", "/=", "%=", "+=", "-=", "&=", "^=", "|=", "##"] {
        if text.starts_with(punct) {
            return ("punctuator", punct.len());
        }
    }
    if b"[](){}.&*+-~!/%<>^|?:;=,#".contains(&c) {
        ("punctuator", 1)
    } else {
        ("other", 1)
    }
}
pub fn single(text: &str) -> Option<&'static str> {
    if text.is_empty() || text.starts_with("//") || text.starts_with("/*") {
        return None;
    }
    let (kind, n) = one(text, false);
    if n == text.len() {
        Some(kind)
    } else {
        None
    }
}
pub fn separator(left: &str, right: &str) -> bool {
    (left == "/" && (right.starts_with('/') || right.starts_with('*'))) || one(&(left.to_string() + right), false).1 != left.len()
}
pub fn render(tokens: &[Token], output: bool) -> String {
    let mut text = String::new();
    for (i, token) in tokens.iter().enumerate() {
        if i > 0 && (token.space || (output && separator(&tokens[i - 1].text, &token.text))) {
            text.push(' ');
        }
        text.push_str(&token.text);
    }
    text
}
pub fn lex(source: &str) -> Vec<LogicalLine> {
    let bytes = source.as_bytes();
    let mut spliced = Vec::new();
    let mut physical = Vec::new();
    let mut i = 0;
    let mut line = 1usize;
    while i < bytes.len() {
        if bytes[i] == b'\\' && bytes.get(i + 1) == Some(&b'\n') {
            i += 2;
            line += 1;
            continue;
        }
        spliced.push(bytes[i]);
        physical.push(line);
        if bytes[i] == b'\n' {
            line += 1;
        }
        i += 1;
    }
    let source = String::from_utf8(spliced).unwrap();
    let bytes = source.as_bytes();
    let mut result = Vec::new();
    let mut tokens: Vec<Token> = Vec::new();
    let mut start = 1;
    let mut i = 0;
    let mut space = true;
    while i < bytes.len() {
        if bytes[i] == b' ' {
            i += 1;
            space = true;
            continue;
        }
        if bytes[i] == b'\n' {
            let end = physical[i];
            result.push(LogicalLine {
                tokens: std::mem::take(&mut tokens),
                start,
                end
            });
            start = end + 1;
            i += 1;
            space = true;
            continue;
        }
        if source[i..].starts_with("//") {
            while i < bytes.len() && bytes[i] != b'\n' {
                i += 1;
            }
            space = true;
            continue;
        }
        if source[i..].starts_with("/*") {
            let end = source[i + 2..].find("*/").unwrap();
            i += end + 4;
            space = true;
            continue;
        }
        let header = tokens.len() == 2 && tokens[0].text == "#" && tokens[1].text == "include";
        let (kind, n) = one(&source[i..], header);
        tokens.push(Token::new(kind, source[i..i + n].into(), physical[i] as i64, space));
        i += n;
        space = false;
    }
    if !tokens.is_empty() {
        result.push(LogicalLine {
            tokens,
            start,
            end: line
        });
    }
    result
}
