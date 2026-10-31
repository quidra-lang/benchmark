#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct Position {
    pub line: usize,
    pub column: usize
}
impl Position {
    pub fn text(self) -> String {
        format!("{}:{}", self.line, self.column)
    }
}
#[derive(Clone)]
pub struct Token {
    pub kind: &'static str,
    pub text: String,
    pub position: Position
}
pub struct Error {
    pub kind: &'static str,
    pub position: Position,
    pub message: String
}
pub fn lex(lines: &[(usize, String)]) -> Result<Vec<Token>, Error> {
    let mut text = String::new();
    let mut positions = Vec::new();
    for (line, source) in lines {
        for (i, c) in source.chars().enumerate() {
            text.push(c);
            positions.push(Position {
                line: *line,
                column: i + 1
            });
        }
        text.push('\n');
        positions.push(Position {
            line: *line,
            column: source.len() + 1
        });
    }
    let bytes = text.as_bytes();
    let mut i = 0;
    let mut tokens = Vec::new();
    while i < bytes.len() {
        if bytes[i] == b' ' || bytes[i] == b'\n' {
            i += 1;
            continue;
        }
        let start = i;
        let error = |message: String| Error {
            kind: "lexical",
            position: positions[start],
            message
        };
        if text[i..].starts_with("//") {
            while i < bytes.len() && bytes[i] != b'\n' {
                i += 1;
            }
            continue;
        }
        if text[i..].starts_with("/*") {
            if let Some(end) = text[i + 2..].find("*/") {
                i += end + 4;
                continue;
            }
            return Err(error("unterminated comment".into()));
        }
        let kind;
        if bytes[i].is_ascii_alphabetic() || bytes[i] == b'_' {
            i += 1;
            while i < bytes.len() && (bytes[i].is_ascii_alphanumeric() || bytes[i] == b'_') {
                i += 1;
            }
            kind = if ["int", "bool", "void", "true", "false", "if", "else", "while", "for", "break", "continue", "return", "print", "read"].contains(&&text[start..i]) {
                "keyword"
            } else {
                "identifier"
            };
        } else if bytes[i].is_ascii_digit() {
            i += 1;
            while i < bytes.len() && bytes[i].is_ascii_digit() {
                i += 1;
            }
            if text[start..i].parse::<i64>().ok().map_or(true, |value| value > 2147483647) {
                return Err(error("integer literal too large".into()));
            }
            kind = "integer";
        } else if i + 1 < bytes.len() && ["<=", ">=", "==", "!=", "&&", "||"].contains(&&text[i..i + 2]) {
            i += 2;
            kind = "symbol";
        }
        else if b"+-*/%<>=!(){}[],;".contains(&bytes[i]) {
            i += 1;
            kind = "symbol";
        }
        else {
            return Err(error(format!("unexpected character '{}'", bytes[i] as char)));
        }
        tokens.push(Token {
            kind,
            text: text[start..i].into(),
            position: positions[start]
        });
    }
    let (last, source) = lines.last().unwrap();
    tokens.push(Token {
        kind: "end",
        text: String::new(),
        position: Position {
            line: *last,
            column: source.len() + 1
        }
    });
    Ok(tokens)
}
