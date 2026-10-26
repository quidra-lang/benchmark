use std::collections::BTreeMap;
use crate::mime::{hex_byte, strict_base64};

pub struct Header { pub fields: Vec<(String, String)>, pub invalid_lines: Vec<usize> }
impl Header {
    pub fn value(&self, name: &str) -> Option<&str> { self.fields.iter().find(|(key, _)| key.eq_ignore_ascii_case(name)).map(|(_, value)| value.as_str()) }
    pub fn count(&self, name: &str) -> usize { self.fields.iter().filter(|(key, _)| key.eq_ignore_ascii_case(name)).count() }
}
#[derive(Clone, Copy, PartialEq)]
pub enum TokenKind { Word, Quoted, Special(u8) }
pub struct Token { pub kind: TokenKind, pub text: String, pub spaced: bool }
pub fn split_words(text: &str) -> Vec<&str> { text.split([' ', '\t']).filter(|word| !word.is_empty()).collect() }
pub fn collapse_whitespace(text: &str) -> String { split_words(text).join(" ") }
pub fn parse_fields(lines: &[(usize, String)]) -> Header {
    let mut header = Header { fields: Vec::new(), invalid_lines: Vec::new() };
    let mut in_field = false;
    for (number, text) in lines {
        if text.starts_with([' ', '\t']) {
            if in_field { header.fields.last_mut().unwrap().1.push_str(text); }
            else { header.invalid_lines.push(*number); }
            continue;
        }
        in_field = false;
        if let Some((name, value)) = text.split_once(':') {
            if !name.is_empty() && name.bytes().all(|byte| (33..=126).contains(&byte)) {
                header.fields.push((name.to_ascii_lowercase(), value.to_owned())); in_field = true;
            }
        }
        if !in_field { header.invalid_lines.push(*number); }
    }
    for (_, value) in &mut header.fields { *value = value.trim_matches([' ', '\t']).to_owned(); }
    header
}
pub fn remove_comments(text: &str) -> Option<String> {
    let mut result = String::new();
    let (mut depth, mut escaped) = (0usize, false);
    for byte in text.bytes() {
        if depth == 0 {
            if byte == b'(' { depth = 1; result.push(' '); } else { result.push(byte as char); }
        } else if escaped { escaped = false; }
        else if byte == b'\\' { escaped = true; }
        else if byte == b'(' { depth += 1; }
        else if byte == b')' { depth -= 1; }
    }
    (depth == 0).then_some(result)
}
fn word_byte(byte: u8, address: bool) -> bool {
    if address { byte.is_ascii_alphanumeric() || b"!#$%&'*+-/=?^_`{|}~".contains(&byte) }
    else { (33..=126).contains(&byte) && !b"()<>@,;:\\\"/[]?=".contains(&byte) }
}
pub fn tokenize(text: &str, address: bool) -> Option<Vec<Token>> {
    let data = text.as_bytes();
    let specials: &[u8] = if address { b"<>:;@,." } else { b"/;=" };
    let (mut position, mut spaced) = (0, false);
    let mut tokens = Vec::new();
    while position < data.len() {
        let byte = data[position];
        if byte == b' ' || byte == b'\t' { spaced = true; position += 1; continue; }
        if byte == b'(' {
            let mut depth = 1;
            position += 1;
            while position < data.len() && depth > 0 {
                match data[position] { b'\\' => { position += 2; continue; }, b'(' => depth += 1, b')' => depth -= 1, _ => {} }
                position += 1;
            }
            if depth != 0 { return None; }
            spaced = true; continue;
        }
        if byte == b'"' {
            position += 1;
            let mut value = String::new();
            while position < data.len() && data[position] != b'"' {
                if data[position] == b'\\' { position += 1; }
                value.push(*data.get(position)? as char); position += 1;
            }
            if position == data.len() { return None; }
            position += 1;
            tokens.push(Token { kind: TokenKind::Quoted, text: value, spaced });
        } else if specials.contains(&byte) {
            tokens.push(Token { kind: TokenKind::Special(byte), text: (byte as char).to_string(), spaced }); position += 1;
        } else if word_byte(byte, address) {
            let start = position;
            while position < data.len() && word_byte(data[position], address) { position += 1; }
            tokens.push(Token { kind: TokenKind::Word, text: text[start..position].to_owned(), spaced });
        } else { return None; }
        spaced = false;
    }
    Some(tokens)
}
pub fn decode_word(word: &str) -> (String, bool, bool) {
    if word.len() < 4 || !word.starts_with("=?") || !word.ends_with("?=") { return (word.to_owned(), false, false); }
    let pieces: Vec<_> = word[2..word.len() - 2].split('?').collect();
    if pieces.len() != 3 || pieces.iter().any(|part| part.is_empty()) { return (word.to_owned(), false, false); }
    let decode = || -> Option<String> {
        if !pieces[0].eq_ignore_ascii_case("us-ascii") { return None; }
        let data = match pieces[1] {
            "B" | "b" => strict_base64(pieces[2])?,
            "Q" | "q" => {
                let bytes = pieces[2].as_bytes();
                let mut result = Vec::new();
                let mut position = 0;
                while position < bytes.len() {
                    match bytes[position] { b'_' => { result.push(32); position += 1; },
                        b'=' => { result.push(hex_byte(bytes, position + 1)?); position += 3; },
                        byte => { result.push(byte); position += 1; } }
                }
                result
            }
            _ => return None,
        };
        if data.iter().all(|byte| (32..=126).contains(byte)) { Some(String::from_utf8(data).unwrap()) } else { None }
    };
    match decode() { Some(text) => (text, true, false), None => (word.to_owned(), false, true) }
}
pub fn decode_unstructured(value: &str) -> (String, bool) {
    let (mut result, mut previous, mut error) = (String::new(), false, false);
    for (index, word) in split_words(value).into_iter().enumerate() {
        let (text, decoded, failed) = decode_word(word);
        if index > 0 && !(decoded && previous) { result.push(' '); }
        result.push_str(&text); previous = decoded; error |= failed;
    }
    (collapse_whitespace(&result), error)
}
pub struct Parameters { pub main_type: String, pub subtype: String, pub values: BTreeMap<String, String> }
pub fn parse_parameters(value: &str, with_subtype: bool) -> Option<Parameters> {
    let tokens = tokenize(value, false)?;
    if tokens.first()?.kind != TokenKind::Word { return None; }
    let mut result = Parameters { main_type: tokens[0].text.to_ascii_lowercase(), subtype: String::new(), values: BTreeMap::new() };
    let mut position = 1;
    if with_subtype {
        if tokens.get(1)?.kind != TokenKind::Special(b'/') || tokens.get(2)?.kind != TokenKind::Word { return None; }
        result.subtype = tokens[2].text.to_ascii_lowercase(); position = 3;
    }
    while position < tokens.len() {
        if position + 4 > tokens.len() || tokens[position].kind != TokenKind::Special(b';') || tokens[position + 1].kind != TokenKind::Word ||
            tokens[position + 2].kind != TokenKind::Special(b'=') || !matches!(tokens[position + 3].kind, TokenKind::Word | TokenKind::Quoted) { return None; }
        result.values.entry(tokens[position + 1].text.to_ascii_lowercase()).or_insert_with(|| tokens[position + 3].text.clone());
        position += 4;
    }
    Some(result)
}
