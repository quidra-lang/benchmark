#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct Position { pub file: usize, pub line: usize, pub column: usize }
#[derive(Clone)]
pub struct Token { pub kind: String, pub spelling: String, pub value: String, pub position: Position }
pub fn lex(text: &str, file: usize) -> Vec<Token> {
    let bytes = text.as_bytes();
    let mut positions = Vec::new();
    let (mut row, mut column) = (1, 1);
    for &c in bytes {
        positions.push(Position { file, line: row, column });
        if c == b'\n' { row += 1; column = 1; } else { column += 1; }
    }
    positions.push(Position { file, line: row, column });
    let mut tokens = Vec::new();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b' ' || bytes[i] == b'\n' { i += 1; continue; }
        let start = i;
        let mut kind: &str;
        let mut value = String::new();
        if text[i..].starts_with("(*") {
            if let Some(end) = text[i + 2..].find("*)") { i += end + 4; continue; }
            tokens.push(Token { kind: "invalid".into(), spelling: text[i..].into(), value: "unterminated comment".into(), position: positions[i] });
            break;
        } else if bytes[i].is_ascii_digit() {
            i += 1;
            while i < bytes.len() && bytes[i].is_ascii_digit() { i += 1; }
            if text[start..i].parse::<i64>().ok().map_or(false, |n| n <= 2147483647) {
                kind = "integer"; value = text[start..i].parse::<i64>().unwrap().to_string();
            } else { kind = "invalid"; value = "integer literal too large".into(); }
        } else if bytes[i].is_ascii_alphabetic() || bytes[i] == b'_' {
            i += 1;
            while i < bytes.len() && (bytes[i].is_ascii_alphanumeric() || bytes[i] == b'_' || bytes[i] == b'\'') { i += 1; }
            value = text[start..i].into();
            kind = if ["let", "rec", "and", "in", "fun", "if", "then", "else", "match", "with", "true", "false", "mod", "val"].contains(&value.as_str()) { "keyword" } else { "identifier" };
        } else if bytes[i] == b'\'' && i + 1 < bytes.len() && bytes[i + 1].is_ascii_lowercase() {
            i += 2;
            while i < bytes.len() && (bytes[i].is_ascii_alphanumeric() || bytes[i] == b'_') { i += 1; }
            kind = "type_variable"; value = text[start..i].into();
        } else if bytes[i] == b'"' {
            i += 1;
            let (mut closed, mut valid) = (false, true);
            while i < bytes.len() && bytes[i] != b'\n' {
                if bytes[i] == b'"' { i += 1; closed = true; break; }
                if bytes[i] == b'\\' && i + 1 < bytes.len() && bytes[i + 1] != b'\n' {
                    match bytes[i + 1] { b'n' => value.push('\n'), b't' => value.push('\t'), b'\\' => value.push('\\'), b'"' => value.push('"'), _ => valid = false }
                    i += 2;
                } else if bytes[i] == b'\\' { i += 1; }
                else { value.push(bytes[i] as char); i += 1; }
            }
            if !closed { kind = "invalid"; value = "unterminated string".into(); }
            else if !valid { kind = "invalid"; value = "invalid escape sequence".into(); }
            else { kind = "string"; }
        } else {
            kind = "symbol";
            if i + 1 < bytes.len() && [";;", "->", "::", "||", "&&", "<=", ">=", "<>"].contains(&&text[i..i + 2]) { i += 2; }
            else if b":;=<>+-*/^()[],|".contains(&bytes[i]) { i += 1; }
            else { kind = "invalid"; value = format!("illegal character '{}'", bytes[i] as char); i += 1; }
            if kind == "symbol" { value = text[start..i].into(); }
        }
        tokens.push(Token { kind: kind.into(), spelling: text[start..i].into(), value, position: positions[start] });
    }
    tokens.push(Token { kind: "eof".into(), spelling: String::new(), value: String::new(), position: positions[bytes.len()] });
    tokens
}
