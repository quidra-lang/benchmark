use std::collections::{BTreeMap, BTreeSet};

#[derive(Clone)]
pub struct Grammar {
    pub order: Vec<String>,
    pub rules: BTreeMap<String, Vec<Vec<String>>>,
    pub start: String,
}

pub fn nonterminal(symbol: &str) -> bool {
    symbol.starts_with('<') && symbol.ends_with('>')
}

pub fn notation(symbols: &[String]) -> String {
    if symbols.is_empty() { "%empty".into() } else { symbols.join(" ") }
}

pub fn production(lhs: &str, rhs: &[String]) -> String {
    format!("{} -> {}", lhs, notation(rhs))
}

#[derive(Clone, Copy, PartialEq)]
enum Kind { Nonterminal, Word, Quoted, Define, Pipe, Empty, Start, Token, Invalid }

struct Token {
    kind: Kind,
    text: String,
    start: usize,
    end: usize,
}

fn word(c: u8) -> bool {
    c.is_ascii_alphanumeric() || c == b'_'
}

fn lex(line: &str) -> Vec<Token> {
    let bytes = line.as_bytes();
    let mut tokens = Vec::new();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b' ' { i += 1; continue; }
        if bytes[i] == b'#' { break; }
        let start = i;
        let mut kind = Kind::Invalid;
        let mut name = String::new();
        if bytes[i] == b'<' {
            let mut j = i + 1;
            if j < bytes.len() && bytes[j].is_ascii_alphabetic() {
                j += 1;
                while j < bytes.len() && word(bytes[j]) { j += 1; }
                if j < bytes.len() && bytes[j] == b'>' { i = j + 1; kind = Kind::Nonterminal; name = line[start..i].into(); }
            }
        } else if bytes[i] == b'"' {
            let mut j = i + 1;
            while j < bytes.len() && bytes[j] != b' ' && bytes[j] != b'"' { j += 1; }
            if j > i + 1 && j < bytes.len() && bytes[j] == b'"' { name = line[i + 1..j].into(); i = j + 1; kind = Kind::Quoted; }
        } else if bytes[i].is_ascii_alphabetic() {
            i += 1;
            while i < bytes.len() && word(bytes[i]) { i += 1; }
            name = line[start..i].into();
            kind = Kind::Word;
        } else if line[i..].starts_with("::=") {
            i += 3;
            kind = Kind::Define;
        } else if bytes[i] == b'|' {
            i += 1;
            kind = Kind::Pipe;
        } else if bytes[i] == b'%' {
            let mut j = i + 1;
            while j < bytes.len() && bytes[j].is_ascii_alphabetic() { j += 1; }
            kind = match &line[i + 1..j] { "empty" => Kind::Empty, "start" => Kind::Start, "token" => Kind::Token, _ => Kind::Invalid };
            if kind != Kind::Invalid { i = j; }
        }
        if kind == Kind::Invalid {
            tokens.push(Token { kind, text: String::new(), start: start + 1, end: start + 1 });
            break;
        }
        tokens.push(Token { kind, text: name, start: start + 1, end: i });
    }
    tokens
}

fn validate(tokens: &[Token]) -> Result<(), usize> {
    let mut state = 0;
    for token in tokens {
        state = match (state, token.kind) {
            (0, Kind::Nonterminal) => 1,
            (0, Kind::Pipe) => 2,
            (0, Kind::Start) => 5,
            (0, Kind::Token) => 7,
            (1, Kind::Define) => 2,
            (2, Kind::Nonterminal | Kind::Word | Kind::Quoted) => 3,
            (2, Kind::Empty) => 4,
            (3, Kind::Nonterminal | Kind::Word | Kind::Quoted) => 3,
            (3 | 4, Kind::Pipe) => 2,
            (5, Kind::Nonterminal) => 6,
            (7 | 8, Kind::Word) => 8,
            _ => return Err(token.start),
        };
    }
    if [3, 4, 6, 8].contains(&state) { Ok(()) } else { Err(tokens.last().unwrap().end + 1) }
}

pub struct Parsed {
    pub grammar: Grammar,
    pub diagnostics: Vec<String>,
    pub declared: BTreeSet<String>,
    pub declaration_seen: bool,
    pub words: BTreeMap<String, usize>,
}

pub fn parse(text: &str) -> Parsed {
    let mut grammar = Grammar { order: Vec::new(), rules: BTreeMap::new(), start: String::new() };
    let mut diagnostics = Vec::new();
    let mut declared = BTreeSet::new();
    let mut declaration_seen = false;
    let mut words = BTreeMap::new();
    let mut attachment: Option<String> = None;
    for (line, content) in text.lines().enumerate() {
        let number = line + 1;
        let tokens = lex(content);
        if tokens.is_empty() { continue; }
        if let Err(column) = validate(&tokens) {
            diagnostics.push(format!("line {}: syntax error at column {}", number, column));
            attachment = None;
            continue;
        }
        match tokens[0].kind {
            Kind::Start => {
                if grammar.start.is_empty() { grammar.start = tokens[1].text.clone(); }
                else { diagnostics.push(format!("line {}: duplicate %start", number)); }
                attachment = None;
            }
            Kind::Token => {
                declaration_seen = true;
                declared.extend(tokens[1..].iter().map(|t| t.text.clone()));
                attachment = None;
            }
            _ => {
                let offset;
                let lhs;
                if tokens[0].kind == Kind::Nonterminal {
                    lhs = tokens[0].text.clone();
                    if !grammar.rules.contains_key(&lhs) {
                        grammar.order.push(lhs.clone());
                        grammar.rules.insert(lhs.clone(), Vec::new());
                    }
                    offset = 2;
                    attachment = Some(lhs.clone());
                } else if let Some(previous) = &attachment {
                    lhs = previous.clone();
                    offset = 1;
                } else {
                    diagnostics.push(format!("line {}: continuation without a rule", number));
                    continue;
                }
                let mut alternative = Vec::new();
                for token in &tokens[offset..] {
                    if token.kind == Kind::Pipe {
                        add(&mut grammar, &lhs, std::mem::take(&mut alternative), number, &mut diagnostics);
                    } else if token.kind != Kind::Empty {
                        if token.kind == Kind::Word { words.entry(token.text.clone()).or_insert(number); }
                        alternative.push(token.text.clone());
                    }
                }
                add(&mut grammar, &lhs, alternative, number, &mut diagnostics);
            }
        }
    }
    if grammar.start.is_empty() { grammar.start = grammar.order[0].clone(); }
    Parsed { grammar, diagnostics, declared, declaration_seen, words }
}

fn add(grammar: &mut Grammar, lhs: &str, rhs: Vec<String>, line: usize, diagnostics: &mut Vec<String>) {
    let alternatives = grammar.rules.get_mut(lhs).unwrap();
    if alternatives.contains(&rhs) { diagnostics.push(format!("line {}: duplicate alternative {}", line, production(lhs, &rhs))); }
    else { alternatives.push(rhs); }
}
