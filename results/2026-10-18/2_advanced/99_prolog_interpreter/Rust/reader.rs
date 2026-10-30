use std::collections::BTreeMap;
use crate::terms::{
    Term,
    Store,
    list
};
#[derive(Clone)]
pub struct Token {
    pub kind: &'static str,
    pub spelling: String,
    pub name: String,
    pub line: usize,
    pub column: usize,
    pub space: bool
}
pub struct Error {
    pub line: usize,
    pub column: usize,
    pub message: String,
    pub index: usize,
    pub eof: bool
}
#[derive(Clone)]
pub struct Variable {
    pub name: String,
    pub term: Term,
    pub count: usize
}
pub struct Parsed {
    pub term: Term,
    pub variables: Vec<Variable>,
    pub next: usize
}
pub fn symbol(c: u8) -> bool {
    b"+-*/\\^<>=~:.?@#&$".contains(&c)
}
pub fn infix(name: &str) -> Option<(usize, usize, usize)> {
    let (p, kind) = match name {
        ":-" => (1200, "xfx"),
        ";" => (1100, "xfy"),
        "->" => (1050, "xfy"),
        "," => (1000, "xfy"),
        "=" | "\\=" | "==" | "\\==" | "is" | "=:=" | "=\\=" | "<" | ">" | "=<" | ">=" | "=.." => (700, "xfx"),
        "+" | "-" => (500, "yfx"),
        "*" | "/" | "//" | "mod" | "rem" => (400, "yfx"),
        _ => return None
    };
    Some((p, if kind == "yfx" {
        p
    } else {
        p - 1
    }, if kind == "xfy" {
        p
    } else {
        p - 1
    }))
}
pub fn prefix(name: &str) -> Option<usize> {
    match name {
        "\\+" => Some(900),
        "-" => Some(200),
        _ => None
    }
}
pub fn operator(name: &str) -> bool {
    infix(name).is_some() || prefix(name).is_some()
}
pub fn lex(text: &str, first_column: usize) -> Vec<Token> {
    let bytes = text.as_bytes();
    let mut tokens = Vec::new();
    let mut i = 0;
    let mut line = 1;
    let mut column = first_column;
    let mut space = true;
    while i < bytes.len() {
        if bytes[i] == b' ' {
            i += 1;
            column += 1;
            space = true;
            continue;
        }
        if bytes[i] == b'\n' {
            i += 1;
            line += 1;
            column = 1;
            space = true;
            continue;
        }
        if bytes[i] == b'%' {
            while i < bytes.len() && bytes[i] != b'\n' {
                i += 1;
                column += 1;
            }
            space = true;
            continue;
        }
        let start = i;
        let at = column;
        let kind;
        let mut name = String::new();
        if bytes[i].is_ascii_digit() {
            i += 1;
            while i < bytes.len() && bytes[i].is_ascii_digit() {
                i += 1;
            }
            if text[start..i].parse::<i64>().ok().map_or(true, |n| n > 2147483647) {
                kind = "invalid";
                name = "integer too large".into();
            } else {
                kind = "integer";
            }
        }
        else if bytes[i].is_ascii_alphabetic() || bytes[i] == b'_' {
            i += 1;
            while i < bytes.len() && (bytes[i].is_ascii_alphanumeric() || bytes[i] == b'_') {
                i += 1;
            }
            kind = if bytes[start].is_ascii_lowercase() {
                "name"
            } else {
                "variable"
            };
        }
        else if symbol(bytes[i]) {
            i += 1;
            while i < bytes.len() && symbol(bytes[i]) {
                i += 1;
            }
            kind = if &text[start..i] == "." && (i == bytes.len() || b" \n%".contains(&bytes[i])) {
                "end"
            } else {
                "name"
            };
        }
        else if bytes[i] == b'!' || bytes[i] == b';' {
            i += 1;
            kind = "name";
        }
        else if b",|()[]".contains(&bytes[i]) {
            i += 1;
            kind = "punctuation";
        }
        else if bytes[i] == b'\'' {
            i += 1;
            let mut invalid = false;
            let mut closed = false;
            while i < bytes.len() && bytes[i] != b'\n' {
                if bytes[i] == b'\'' {
                    if bytes.get(i + 1) == Some(&b'\'') {
                        name.push('\'');
                        i += 2;
                    } else {
                        i += 1;
                        closed = true;
                        break;
                    }
                }
                else if bytes[i] == b'\\' {
                    i += 1;
                    if i < bytes.len() && bytes[i] != b'\n' {
                        match bytes[i] {
                            b'n' => name.push('\n'),
                            b't' => name.push('\t'),
                            b'\\' => name.push('\\'),
                            b'\'' => name.push('\''),
                            _ => invalid = true
                        }
                        i += 1;
                    }
                } else {
                    name.push(bytes[i] as char);
                    i += 1;
                }
            }
            if !closed {
                kind = "invalid";
                name = "unterminated quoted atom".into();
            } else if invalid {
                kind = "invalid";
                name = "undefined escape sequence".into();
            } else {
                kind = "quoted";
            }
        } else {
            i += 1;
            kind = "invalid";
            name = format!("illegal character '{}'", bytes[start] as char);
        }
        let spelling = text[start..i].to_string();
        if name.is_empty() && kind != "quoted" {
            name = spelling.clone();
        }
        tokens.push(Token {
            kind,
            spelling,
            name,
            line,
            column: at,
            space
        });
        column += i - start;
        space = false;
    }
    tokens.push(Token {
        kind: "eof",
        spelling: String::new(),
        name: String::new(),
        line,
        column,
        space
    });
    tokens
}
struct Parser<'a> {
    tokens: &'a [Token],
    index: usize,
    store: &'a mut Store,
    variables: Vec<Variable>,
    names: BTreeMap<String,
    usize>
}
impl<'a> Parser<'a> {
    fn error(&self, index: usize) -> Error {
        let token = &self.tokens[index];
        let message = match token.kind {
            "invalid" => token.name.clone(),
            "eof" => "unexpected end of file".into(),
            "end" => "unexpected end of clause".into(),
            "name" if infix(&token.name).is_some() => "operator priority clash".into(),
            _ => format!("unexpected \"{}\"", token.spelling)
        };
        Error {
            line: token.line,
            column: token.column,
            message,
            index,
            eof: token.kind == "eof"
        }
    }
    fn peek(&self) -> &Token {
        &self.tokens[self.index]
    }
    fn take(&mut self) -> (usize, Token) {
        let index = self.index;
        let token = self.peek().clone();
        if token.kind != "eof" {
            self.index += 1;
        }
        (index, token)
    }
    fn expect(&mut self, text: &str) -> Result<(),
    Error> {
        let (i, token) = self.take();
        if token.kind == "punctuation" && token.name == text {
            Ok(())
        } else {
            Err(self.error(i))
        }
    }
    fn term(&mut self, limit: usize) -> Result<(Term, usize),
    Error> {
        let (mut term, mut priority) = self.primary(limit)?;
        loop {
            let token = self.peek();
            if token.kind != "name" && !(token.kind == "punctuation" && token.name == ",") {
                break;
            }
            let (p, left, right) = match infix(&token.name) {
                Some(operator) => operator,
                None => break
            };
            if p > limit || priority > left {
                break;
            }
            let name = self.take().1.name;
            let argument = self.term(right)?.0;
            term = Term::compound(&name, vec![term, argument]);
            priority = p;
        }
        Ok((term, priority))
    }
    fn starts(token: &Token) -> bool {
        ["integer", "variable", "quoted"].contains(&token.kind) || (token.kind == "punctuation" && (token.name == "(" || token.name == "[")) || (token.kind == "name" && (infix(&token.name).is_none() || prefix(&token.name).is_some()))
    }
    fn primary(&mut self, limit: usize) -> Result<(Term, usize),
    Error> {
        let (index, token) = self.take();
        match token.kind {
            "integer" => Ok((Term::Integer(token.name.parse().unwrap()), 0)),
            "variable" => {
                if token.name == "_" {
                    return Ok((self.store.fresh(), 0));
                }
                let variable = if let Some(&i) = self.names.get(&token.name) {
                    self.variables[i].count += 1;
                    self.variables[i].term.clone()
                } else {
                    let term = self.store.fresh();
                    self.names.insert(token.name.clone(), self.variables.len());
                    self.variables.push(Variable {
                        name: token.name,
                        term: term.clone(),
                        count: 1
                    });
                    term
                };
                Ok((variable, 0))
            },
            "punctuation" if token.name == "(" => {
                let term = self.term(1200)?.0;
                self.expect(")")?;
                Ok((term, 0))
            },
            "punctuation" if token.name == "[" => {
                if self.peek().kind == "punctuation" && self.peek().name == "]" {
                    self.take();
                    return Ok((Term::atom("[]"), 0));
                }
                let mut elements = vec![self.term(999)?.0];
                while self.peek().kind == "punctuation" && self.peek().name == "," {
                    self.take();
                    elements.push(self.term(999)?.0);
                }
                let tail = if self.peek().kind == "punctuation" && self.peek().name == "|" {
                    self.take();
                    self.term(999)?.0
                } else {
                    Term::atom("[]")
                };
                self.expect("]")?;
                Ok((list(elements, tail), 0))
            },
            "name" | "quoted" => {
                if self.peek().kind == "punctuation" && self.peek().name == "(" && !self.peek().space {
                    self.take();
                    let mut arguments = vec![self.term(999)?.0];
                    while self.peek().kind == "punctuation" && self.peek().name == "," {
                        self.take();
                        arguments.push(self.term(999)?.0);
                    }
                    self.expect(")")?;
                    return Ok((Term::compound(&token.name, arguments), 0));
                }
                if token.kind == "name" && token.name == "-" && self.peek().kind == "integer" && !self.peek().space {
                    let integer = self.take().1.name.parse::<i64>().unwrap();
                    return Ok((Term::Integer(-integer), 0));
                }
                if token.kind == "name" && prefix(&token.name).is_some() && Self::starts(self.peek()) {
                    let priority = prefix(&token.name).unwrap();
                    if priority > limit {
                        let mut error = self.error(index);
                        error.message = "operator priority clash".into();
                        return Err(error);
                    }
                    let argument = self.term(priority)?.0;
                    return Ok((Term::compound(&token.name, vec![argument]), priority));
                }
                Ok((Term::Atom(token.name), 0))
            },
            _ => Err(self.error(index))
        }
    }
}
pub fn clause(tokens: &[Token], start: usize, store: &mut Store, query: bool) -> Result<Parsed, Error> {
    let mut parser = Parser {
        tokens,
        index: start,
        store,
        variables: Vec::new(),
        names: BTreeMap::new()
    };
    let term = parser.term(1200)?.0;
    let (index, token) = parser.take();
    if token.kind != "end" {
        return Err(parser.error(index));
    }
    if query && parser.peek().kind != "eof" {
        return Err(parser.error(parser.index));
    }
    Ok(Parsed {
        term,
        variables: parser.variables,
        next: parser.index
    })
}
