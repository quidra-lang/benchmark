#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
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
    pub value: String,
    pub position: Position
}
pub fn lex(text: &str) -> Result<Vec<Token>, Position> {
    let bytes = text.as_bytes();
    let mut result = Vec::new();
    let mut i = 0;
    let mut line = 1;
    let mut column = 1;
    while i < bytes.len() {
        let position = Position {
            line,
            column
        };
        let start = i;
        if bytes[i] == b' ' {
            i += 1;
            column += 1;
            continue;
        }
        if bytes[i] == b'\\' && bytes.get(i + 1) == Some(&b'\n') {
            i += 2;
            line += 1;
            column = 1;
            continue;
        }
        if bytes[i] == b'#' {
            while i < bytes.len() && bytes[i] != b'\n' {
                i += 1;
                column += 1;
            }
            continue;
        }
        if bytes[i] == b'\n' {
            result.push(Token {
                kind: "newline",
                text: "\n".into(),
                value: String::new(),
                position
            });
            i += 1;
            line += 1;
            column = 1;
            continue;
        }
        let kind;
        let mut value = String::new();
        if bytes[i].is_ascii_digit() {
            i += 1;
            while i < bytes.len() && bytes[i].is_ascii_digit() {
                i += 1;
            }
            kind = "number";
        }
        else if bytes[i].is_ascii_alphabetic() || bytes[i] == b'_' {
            i += 1;
            while i < bytes.len() && (bytes[i].is_ascii_alphanumeric() || bytes[i] == b'_') {
                i += 1;
            }
            let word = &text[start..i];
            kind = if ["BEGIN", "END", "function", "if", "else", "while", "for", "do", "break", "continue", "next", "exit", "return", "delete", "in", "getline", "print", "printf"].contains(&word) {
                "keyword"
            }
            else if ["length", "substr", "index", "split", "sprintf", "toupper", "tolower", "close", "int"].contains(&word) {
                "builtin"
            } else if bytes.get(i) == Some(&b'(') {
                "function"
            } else {
                "name"
            };
        } else if bytes[i] == b'"' {
            i += 1;
            loop {
                if i >= bytes.len() || bytes[i] == b'\n' {
                    return Err(position);
                }
                if bytes[i] == b'"' {
                    i += 1;
                    break;
                }
                if bytes[i] == b'\\' {
                    let escape = Position {
                        line,
                        column: column + i - start
                    };
                    i += 1;
                    let c = match bytes.get(i) {
                        Some(b'n') => '\n',
                        Some(b't') => '\t',
                        Some(b'\\') => '\\',
                        Some(b'"') => '"',
                        Some(b'/') => '/',
                        _ => return Err(escape)
                    };
                    value.push(c);
                    i += 1;
                } else {
                    value.push(bytes[i] as char);
                    i += 1;
                }
            }
            kind = "string";
        } else {
            let matched = ["+=", "-=", "*=", "/=", "%=", "^=", "==", "<=", ">=", "!=", "++", "--", "&&", "||", ">>"].iter().find(|op| text[i..].starts_with(**op));
            if let Some(op) = matched {
                i += op.len();
                kind = "symbol";
            }
            else if b"+-*/%^!><?:=()[]{};,$".contains(&bytes[i]) {
                i += 1;
                kind = "symbol";
            } else {
                return Err(position);
            }
        }
        column += i - start;
        result.push(Token {
            kind,
            text: text[start..i].into(),
            value,
            position
        });
    }
    result.push(Token {
        kind: "end",
        text: String::new(),
        value: String::new(),
        position: Position {
            line,
            column: 1
        }
    });
    Ok(result)
}
