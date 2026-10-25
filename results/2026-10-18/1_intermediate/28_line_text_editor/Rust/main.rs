use std::cmp::Ordering;
use std::collections::BTreeMap;
use std::fmt::Write as FmtWrite;
use std::io::{self, Read, Write as IoWrite};
use std::rc::Rc;

type Result<T> = std::result::Result<T, &'static str>;

#[derive(Clone)]
struct Atom {
    byte: u8,
    matched: bool,
}

type Replacement = Vec<Atom>;

fn replacement_text(atoms: &[Atom]) -> String {
    String::from_utf8(atoms.iter().map(|a| a.byte).collect()).unwrap()
}

fn delimited(s: &str, mut position: usize, delimiter: u8) -> Result<(Replacement, usize)> {
    let bytes = s.as_bytes();
    let mut atoms = Vec::new();
    while position < bytes.len() {
        let mut byte = bytes[position];
        position += 1;
        if byte == delimiter {
            return Ok((atoms, position));
        }
        let escaped = byte == b'\\';
        if escaped {
            byte = *bytes.get(position).ok_or("missing delimiter")?;
            position += 1;
        }
        atoms.push(Atom { byte, matched: byte == b'&' && !escaped });
    }
    Err("missing delimiter")
}

#[derive(Clone)]
enum Token {
    Number(i32),
    Offset(i32),
    Current,
    Last,
    Separator(u8),
    Percent,
    Mark(Option<u8>),
    Search { backward: bool, text: String },
}

fn number(bytes: &[u8], position: &mut usize) -> i32 {
    let mut value = 0;
    while let Some(&byte) = bytes.get(*position).filter(|b| b.is_ascii_digit()) {
        value = value * 10 + i32::from(byte - b'0');
        *position += 1;
    }
    value
}

fn lex_addresses(s: &str) -> Result<(Vec<Token>, usize)> {
    let bytes = s.as_bytes();
    let mut position = 0;
    let mut tokens = Vec::new();
    while let Some(&byte) = bytes.get(position) {
        let token = match byte {
            b'0'..=b'9' => Token::Number(number(bytes, &mut position)),
            b'+' | b'-' => {
                position += 1;
                let value = if bytes.get(position).is_some_and(u8::is_ascii_digit) {
                    number(bytes, &mut position)
                } else { 1 };
                Token::Offset(if byte == b'-' { -value } else { value })
            }
            b'.' => { position += 1; Token::Current }
            b'$' => { position += 1; Token::Last }
            b',' | b';' => { position += 1; Token::Separator(byte) }
            b'%' => { position += 1; Token::Percent }
            b'\'' => {
                position += 1;
                let name = bytes.get(position).copied();
                if name.is_some() { position += 1; }
                Token::Mark(name)
            }
            b'/' | b'?' => {
                let (atoms, end) = delimited(s, position + 1, byte)?;
                position = end;
                Token::Search { backward: byte == b'?', text: replacement_text(&atoms) }
            }
            _ => break,
        };
        tokens.push(token);
    }
    Ok((tokens, position))
}

fn with_text(line: &str) -> bool {
    let Ok((_, end)) = lex_addresses(line) else { return false };
    let part = &line[end..];
    if matches!(part, "a" | "i" | "c") { return true; }
    let bytes = part.as_bytes();
    if bytes.len() >= 2 && matches!(bytes[0], b'g' | b'v') && !matches!(bytes[1], b' ' | b'\\') {
        if let Ok((_, end)) = delimited(part, 2, bytes[1]) {
            return matches!(&part[end..], "a" | "i" | "c");
        }
    }
    false
}

fn valid_address(tokens: &[Token]) -> bool {
    tokens.iter().enumerate().all(|(i, token)| match token {
        Token::Offset(_) => true,
        Token::Number(_) | Token::Current | Token::Last | Token::Mark(_) | Token::Search { .. } => i == 0,
        _ => false,
    })
}

enum Addresses {
    None,
    One(Vec<Token>),
    Two { left: Vec<Token>, right: Vec<Token>, semicolon: bool },
}

impl Addresses {
    fn parse(tokens: Vec<Token>) -> Result<Self> {
        if tokens.is_empty() { return Ok(Self::None); }
        if matches!(tokens.as_slice(), [Token::Percent]) {
            return Ok(Self::Two { left: vec![Token::Number(1)], right: vec![Token::Last], semicolon: false });
        }
        let separators: Vec<usize> = tokens.iter().enumerate()
            .filter_map(|(i, t)| matches!(t, Token::Separator(_)).then_some(i)).collect();
        if separators.len() > 1 { return Err("bad address"); }
        if let Some(&index) = separators.first() {
            let left = tokens[..index].to_vec();
            let right = tokens[index + 1..].to_vec();
            if !valid_address(&left) || !valid_address(&right) { return Err("bad address"); }
            Ok(Self::Two { left, right, semicolon: matches!(tokens[index], Token::Separator(b';')) })
        } else {
            if !valid_address(&tokens) { return Err("bad address"); }
            Ok(Self::One(tokens))
        }
    }

    fn count(&self) -> usize {
        match self { Self::None => 0, Self::One(_) => 1, Self::Two { .. } => 2 }
    }
}

#[derive(Default)]
struct SortOptions {
    reverse: bool,
    unique: bool,
    insensitive: bool,
    numeric: bool,
}

struct Substitution {
    search: String,
    replacement: Option<Replacement>,
    all: bool,
    count: usize,
    suffix: Option<u8>,
}

enum Command {
    Empty, Append, Insert, Change, Print(u8), Equals, Count, Yank, Marks, History, Files,
    Delete(Option<u8>), Put(Option<u8>), Join { spaced: bool, suffix: Option<u8> },
    Page(Option<usize>), Indent { remove: bool, width: usize }, Undo { redo: bool, count: usize },
    Case(Option<u8>), Read(String), Write { name: String, append: bool }, Edit(String), WritePrint,
    Mark(usize), Move { copy: bool, destination: Vec<Token>, suffix: Option<u8> },
    Substitute(Substitution), Global { inverse: bool, search: String, sub: Box<Command> }, Sort(SortOptions),
}

fn suffix(s: &str) -> Result<Option<u8>> {
    match s.as_bytes() {
        [] => Ok(None),
        [byte @ (b'p' | b'n' | b'l')] => Ok(Some(*byte)),
        _ => Err("invalid suffix"),
    }
}

fn positive(s: &str) -> Result<Option<usize>> {
    if s.is_empty() { return Ok(None); }
    if !s.bytes().all(|b| b.is_ascii_digit()) { return Err("invalid suffix"); }
    let value: usize = s.parse().unwrap();
    if value == 0 { return Err("invalid suffix"); }
    Ok(Some(value))
}

fn filename(s: &str) -> Result<String> {
    let name = s.strip_prefix(' ').ok_or("invalid file name")?;
    if name.is_empty() || name.len() > 8 || !name.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit()) {
        return Err("invalid file name");
    }
    Ok(name.to_owned())
}

fn sort_form(s: &str) -> bool { s == "sort" || s.starts_with("sort ") }

impl Command {
    fn parse(part: &str) -> Result<Self> {
        if sort_form(part) {
            let mut options = SortOptions::default();
            if part == "sort " { return Err("invalid suffix"); }
            for byte in part.get(5..).unwrap_or("").bytes() {
                let flag = match byte {
                    b'r' => &mut options.reverse, b'u' => &mut options.unique,
                    b'i' => &mut options.insensitive, b'n' => &mut options.numeric,
                    _ => return Err("invalid suffix"),
                };
                if *flag { return Err("invalid suffix"); }
                *flag = true;
            }
            if options.insensitive && options.numeric { return Err("invalid suffix"); }
            return Ok(Self::Sort(options));
        }
        let Some(&first) = part.as_bytes().first() else { return Ok(Self::Empty) };
        let arg = &part[1..];
        if b"aicpnl=#yKhf".contains(&first) {
            if !arg.is_empty() { return Err("invalid suffix"); }
            return Ok(match first {
                b'a' => Self::Append, b'i' => Self::Insert, b'c' => Self::Change,
                b'p' | b'n' | b'l' => Self::Print(first), b'=' => Self::Equals, b'#' => Self::Count,
                b'y' => Self::Yank, b'K' => Self::Marks, b'h' => Self::History, _ => Self::Files,
            });
        }
        Ok(match first {
            b'd' => Self::Delete(suffix(arg)?),
            b'x' => Self::Put(suffix(arg)?),
            b'j' | b'J' => Self::Join { spaced: first == b'J', suffix: suffix(arg)? },
            b'z' => Self::Page(positive(arg)?),
            b'>' | b'<' => Self::Indent { remove: first == b'<', width: positive(arg)?.unwrap_or(4) },
            b'u' => Self::Undo { redo: false, count: positive(arg)?.unwrap_or(1) },
            b'r' if arg.bytes().all(|b| b.is_ascii_digit()) => Self::Undo { redo: true, count: positive(arg)?.unwrap_or(1) },
            b'r' => Self::Read(filename(arg)?),
            b'w' if arg.is_empty() => Self::WritePrint,
            b'w' | b'W' => Self::Write { name: filename(arg)?, append: first == b'W' },
            b'e' => Self::Edit(filename(arg)?),
            b'~' => Self::Case(match arg { "" => None, "u" => Some(b'u'), "l" => Some(b'l'), _ => return Err("invalid suffix") }),
            b'k' => {
                if arg.len() != 1 || !arg.as_bytes()[0].is_ascii_lowercase() { return Err("invalid mark"); }
                Self::Mark(usize::from(arg.as_bytes()[0] - b'a'))
            }
            b'm' | b't' => {
                let (destination, end) = lex_addresses(arg)?;
                if destination.is_empty() || !valid_address(&destination) { return Err("invalid destination"); }
                Self::Move { copy: first == b't', destination, suffix: suffix(&arg[end..])? }
            }
            b's' => {
                let repeated = arg.bytes().all(|b| b"gpnl".contains(&b) || b.is_ascii_digit());
                let (search, replacement, mut position) = if repeated {
                    (String::new(), None, 0)
                } else {
                    let delimiter = arg.as_bytes()[0];
                    if matches!(delimiter, b' ' | b'\\') { return Err("missing delimiter"); }
                    let (search, start) = delimited(arg, 1, delimiter)?;
                    let (replacement, end) = delimited(arg, start, delimiter)?;
                    let previous = &arg[start..end - 1] == "%";
                    (replacement_text(&search), if previous { None } else { Some(replacement) }, end)
                };
                let mut value = Substitution { search, replacement, all: false, count: 1, suffix: None };
                let mut counted = false;
                let bytes = arg.as_bytes();
                while let Some(&byte) = bytes.get(position) {
                    position += 1;
                    match byte {
                        b'g' => {
                            if value.all { return Err("invalid suffix"); }
                            value.all = true;
                        }
                        b'p' | b'n' | b'l' => {
                            if value.suffix.is_some() { return Err("invalid suffix"); }
                            value.suffix = Some(byte);
                        }
                        b'0'..=b'9' => {
                            if counted { return Err("invalid suffix"); }
                            counted = true;
                            position -= 1;
                            value.count = number(bytes, &mut position) as usize;
                            if value.count == 0 { return Err("invalid suffix"); }
                        }
                        _ => return Err("invalid suffix"),
                    }
                }
                Self::Substitute(value)
            }
            b'g' | b'v' => {
                let delimiter = *arg.as_bytes().first().ok_or("missing delimiter")?;
                if matches!(delimiter, b' ' | b'\\') { return Err("missing delimiter"); }
                let (search, end) = delimited(arg, 1, delimiter)?;
                let body = if end == arg.len() { "p" } else { &arg[end..] };
                if !b"pnldmtjJs><~aicx".contains(&body.as_bytes()[0]) || sort_form(body) {
                    return Err("invalid global command");
                }
                Self::Global { inverse: first == b'v', search: replacement_text(&search), sub: Box::new(Self::parse(body)?) }
            }
            _ => return Err("unknown command"),
        })
    }

    fn address_kind(&self) -> usize {
        match self {
            Self::Undo { .. } | Self::History | Self::Marks | Self::Files | Self::Edit(_) => 0,
            Self::Append | Self::Insert | Self::Put(_) | Self::Equals | Self::Read(_) | Self::Mark(_) | Self::Page(_) => 1,
            _ => 2,
        }
    }

    fn modifying(&self) -> bool {
        match self {
            Self::Append | Self::Insert | Self::Change | Self::Delete(_) | Self::Put(_) | Self::Join { .. } |
            Self::Move { .. } | Self::Substitute(_) | Self::Indent { .. } | Self::Case(_) | Self::Sort(_) |
            Self::Read(_) | Self::Edit(_) => true,
            Self::Global { sub, .. } => sub.modifying(),
            _ => false,
        }
    }

    fn print_suffix(&self) -> Option<u8> {
        match self {
            Self::Delete(s) | Self::Put(s) | Self::Join { suffix: s, .. } | Self::Move { suffix: s, .. } => *s,
            _ => None,
        }
    }
}

#[derive(Clone)]
struct Line { id: u64, text: String }

#[derive(Clone)]
struct Snapshot { buffer: Rc<Vec<Line>>, current: usize }

struct Record { command: String, state: Snapshot }

#[derive(Clone)]
struct Editor {
    buffer: Rc<Vec<Line>>,
    current: usize,
    marks: [Option<u64>; 26],
    cut: Rc<Vec<String>>,
    pattern: Option<String>,
    replacement: Option<Replacement>,
    display: usize,
    undo: Vec<Rc<Record>>,
    redo: Vec<Rc<Record>>,
    files: BTreeMap<String, Rc<Vec<String>>>,
    next_id: u64,
}

#[derive(Clone, Copy)]
struct Range { first: usize, last: usize }

impl Editor {
    fn new() -> Self {
        Self { buffer: Rc::new(Vec::new()), current: 0, marks: [None; 26], cut: Rc::new(Vec::new()),
            pattern: None, replacement: None, display: 5, undo: Vec::new(), redo: Vec::new(),
            files: BTreeMap::new(), next_id: 1 }
    }

    fn snapshot(&self) -> Snapshot { Snapshot { buffer: Rc::clone(&self.buffer), current: self.current } }
    fn lines_mut(&mut self) -> &mut Vec<Line> { Rc::make_mut(&mut self.buffer) }
    fn locate(&self, id: u64) -> Option<usize> { self.buffer.iter().position(|line| line.id == id).map(|i| i + 1) }

    fn pattern(&mut self, search: &str) -> Result<String> {
        if !search.is_empty() { self.pattern = Some(search.to_owned()); }
        self.pattern.clone().ok_or("no previous pattern")
    }

    fn address(&mut self, tokens: &[Token]) -> Result<i32> {
        let mut value = self.current as i32;
        for token in tokens {
            match token {
                Token::Offset(n) => value += n,
                Token::Number(n) => value = *n,
                Token::Current => value = self.current as i32,
                Token::Last => value = self.buffer.len() as i32,
                Token::Mark(name) => {
                    let name = name.filter(u8::is_ascii_lowercase).ok_or("invalid mark")?;
                    value = self.marks[usize::from(name - b'a')].and_then(|id| self.locate(id))
                        .ok_or("mark not set")? as i32;
                }
                Token::Search { backward, text } => {
                    let pattern = self.pattern(text)?;
                    let size = self.buffer.len() as i32;
                    let start = if *backward && self.current == 0 { size + 1 } else { self.current as i32 };
                    value = (1..=size).find_map(|step| {
                        let index = if *backward { (start - step - 1).rem_euclid(size) } else { (start + step - 1) % size };
                        self.buffer[index as usize].text.contains(&pattern).then_some(index + 1)
                    }).ok_or("no match")?;
                }
                _ => unreachable!(),
            }
        }
        Ok(value)
    }

    fn evaluate(&mut self, addresses: &Addresses) -> Result<(i32, i32)> {
        match addresses {
            Addresses::None => Ok((0, 0)),
            Addresses::One(tokens) => Ok((self.address(tokens)?, 0)),
            Addresses::Two { left, right, semicolon } => {
                let a = if left.is_empty() { if *semicolon { self.current as i32 } else { 1 } } else { self.address(left)? };
                if *semicolon {
                    if a < 0 || a > self.buffer.len() as i32 { return Err("address out of range"); }
                    self.current = a as usize;
                }
                let b = if right.is_empty() { self.buffer.len() as i32 } else { self.address(right)? };
                Ok((a, b))
            }
        }
    }

    fn checked_range(&self, command: &Command, count: usize, (mut a, mut b): (i32, i32)) -> Result<Range> {
        let size = self.buffer.len() as i32;
        match command.address_kind() {
            0 => return Ok(Range { first: 0, last: 0 }),
            1 => {
                if count == 0 {
                    a = match command {
                        Command::Equals | Command::Read(_) => size,
                        Command::Page(_) => self.current as i32 + 1,
                        _ => self.current as i32,
                    };
                }
                let minimum = if matches!(command, Command::Mark(_) | Command::Page(_)) { 1 } else { 0 };
                if a < minimum || a > size { return Err("address out of range"); }
                return Ok(Range { first: a as usize, last: a as usize });
            }
            _ => {}
        }
        if count == 0 {
            match command {
                Command::WritePrint | Command::Write { .. } | Command::Count => return Ok(Range { first: 1, last: size as usize }),
                Command::Global { .. } | Command::Sort(_) => { a = 1; b = size; }
                Command::Join { .. } => { a = self.current as i32; b = a + 1; }
                _ => { a = self.current as i32; b = a; }
            }
        } else if count == 1 { b = a; }
        if a < 1 || a > size || b < 1 || b > size { return Err("address out of range"); }
        if a > b || a == b && matches!(command, Command::Join { .. }) { return Err("invalid range"); }
        Ok(Range { first: a as usize, last: b as usize })
    }

    fn print_line(&self, number: usize, form: u8, output: &mut String) {
        let text = &self.buffer[number - 1].text;
        match form {
            b'n' => writeln!(output, "{number:>3} {text}").unwrap(),
            b'l' => {
                let escaped = text.replace('\\', "\\\\") + "$";
                let mut remaining = escaped.as_str();
                while remaining.len() > 40 {
                    writeln!(output, "{}\\", &remaining[..39]).unwrap();
                    remaining = &remaining[39..];
                }
                writeln!(output, "{remaining}").unwrap();
            }
            _ => writeln!(output, "{text}").unwrap(),
        }
    }

    fn contents(&self, range: Range) -> Vec<String> {
        self.buffer[range.first - 1..range.last].iter().map(|line| line.text.clone()).collect()
    }

    fn fresh_lines(&mut self, text: &[String]) -> Vec<Line> {
        let first_id = self.next_id;
        self.next_id += text.len() as u64;
        text.iter().enumerate().map(|(i, text)| Line { id: first_id + i as u64, text: text.clone() }).collect()
    }

    fn insert(&mut self, after: usize, text: &[String]) {
        let lines = self.fresh_lines(text);
        self.lines_mut().splice(after..after, lines);
    }

    fn substitute(&mut self, sub: &Substitution, range: Range, output: &mut String, in_global: bool) -> Result<bool> {
        let pattern = self.pattern(&sub.search)?;
        let replacement = sub.replacement.clone().or_else(|| self.replacement.clone()).ok_or("no previous substitution")?;
        self.replacement = Some(replacement.clone());
        let mut expanded = String::new();
        for atom in replacement {
            if atom.matched { expanded.push_str(&pattern); }
            else { expanded.push(char::from(atom.byte)); }
        }
        let mut last = None;
        for i in range.first..=range.last {
            let old = &self.buffer[i - 1].text;
            let mut result = String::new();
            let mut position = 0;
            let mut changed = false;
            for (index, (start, matched)) in old.match_indices(&pattern).enumerate() {
                result.push_str(&old[position..start]);
                if index + 1 == sub.count || sub.all && index + 1 > sub.count {
                    result.push_str(&expanded);
                    changed = true;
                } else { result.push_str(matched); }
                position = start + pattern.len();
            }
            result.push_str(&old[position..]);
            if changed {
                if result.len() > 80 { return Err("line too long"); }
                if result.is_empty() || result.ends_with(' ') { return Err("bad line"); }
                self.lines_mut()[i - 1].text = result;
                last = Some(i);
            }
        }
        if let Some(last) = last {
            self.current = last;
            if let Some(suffix) = sub.suffix { self.print_line(last, suffix, output); }
        } else if !in_global { return Err("no match"); }
        Ok(last.is_some())
    }

    fn transfer_history(&mut self, redo: bool, count: usize) -> Result<()> {
        if (if redo { self.redo.len() } else { self.undo.len() }) < count {
            return Err(if redo { "nothing to redo" } else { "nothing to undo" });
        }
        for _ in 0..count {
            let record = if redo { self.redo.pop().unwrap() } else { self.undo.pop().unwrap() };
            let replacement = Rc::new(Record { command: record.command.clone(), state: self.snapshot() });
            if redo { self.undo.push(replacement); } else { self.redo.push(replacement); }
            self.buffer = Rc::clone(&record.state.buffer);
            self.current = record.state.current;
        }
        Ok(())
    }

    fn execute(&mut self, command: &Command, range: Range, text: &[String], output: &mut String, in_global: bool) -> Result<bool> {
        let Range { first: a, last: b } = range;
        match command {
            Command::Empty => { self.print_line(b, b'p', output); self.current = b; }
            Command::Print(form) => {
                for i in a..=b { self.print_line(i, *form, output); }
                self.current = b;
            }
            Command::Page(count) => {
                if let Some(count) = count { self.display = *count; }
                let last = (a + self.display - 1).min(self.buffer.len());
                for i in a..=last { self.print_line(i, b'p', output); }
                self.current = last;
            }
            Command::Equals => writeln!(output, "{a}").unwrap(),
            Command::Count | Command::WritePrint => {
                let lines = &self.buffer[a - 1..b];
                let chars: usize = lines.iter().map(|line| line.text.len()).sum();
                if matches!(command, Command::Count) {
                    let words: usize = lines.iter().map(|line| line.text.split(' ').filter(|word| !word.is_empty()).count()).sum();
                    writeln!(output, "count lines={} words={words} chars={chars}", lines.len()).unwrap();
                } else {
                    for i in a..=b { self.print_line(i, b'p', output); }
                    writeln!(output, "lines={} bytes={}", lines.len(), chars + lines.len()).unwrap();
                }
            }
            Command::Append | Command::Insert => {
                let after = if matches!(command, Command::Append) { a } else { a.saturating_sub(1) };
                self.insert(after, text);
                self.current = after + text.len();
            }
            Command::Change | Command::Delete(_) => {
                self.cut = Rc::new(self.contents(range));
                self.lines_mut().drain(a - 1..b);
                if matches!(command, Command::Change) { self.insert(a - 1, text); }
                self.current = if matches!(command, Command::Change) && !text.is_empty() {
                    a + text.len() - 1
                } else { a.min(self.buffer.len()) };
            }
            Command::Yank => self.cut = Rc::new(self.contents(range)),
            Command::Put(_) => {
                if self.cut.is_empty() { return Err("nothing to put"); }
                let cut = Rc::clone(&self.cut);
                self.insert(a, &cut);
                self.current = a + cut.len();
            }
            Command::Move { copy, destination, .. } => {
                let destination = self.address(destination)?;
                if destination < 0 || destination > self.buffer.len() as i32 { return Err("address out of range"); }
                let mut destination = destination as usize;
                if !*copy && a <= destination && destination < b { return Err("invalid destination"); }
                let mut moved = self.buffer[a - 1..b].to_vec();
                if *copy {
                    for line in &mut moved { line.id = self.next_id; self.next_id += 1; }
                } else {
                    self.lines_mut().drain(a - 1..b);
                    if destination >= b { destination -= moved.len(); }
                }
                self.current = destination + moved.len();
                self.lines_mut().splice(destination..destination, moved);
            }
            Command::Join { spaced, .. } => {
                let mut joined = self.buffer[a - 1].text.clone();
                for line in &self.buffer[a..b] {
                    if *spaced { joined.push(' '); joined.push_str(line.text.trim_start_matches(' ')); }
                    else { joined.push_str(&line.text); }
                }
                if joined.len() > 80 { return Err("line too long"); }
                self.lines_mut()[a - 1].text = joined;
                self.lines_mut().drain(a..b);
                self.current = a;
            }
            Command::Indent { remove, width } => {
                for line in &mut self.lines_mut()[a - 1..b] {
                    if *remove {
                        let count = line.text.bytes().take_while(|b| *b == b' ').count().min(*width);
                        line.text.drain(..count);
                    } else {
                        if line.text.len() + *width > 80 { return Err("line too long"); }
                        line.text.insert_str(0, &" ".repeat(*width));
                    }
                }
                self.current = b;
            }
            Command::Case(option) => {
                for line in &mut self.lines_mut()[a - 1..b] {
                    line.text = match option {
                        Some(b'u') => line.text.to_ascii_uppercase(),
                        Some(b'l') => line.text.to_ascii_lowercase(),
                        _ => line.text.bytes().map(|byte| char::from(if byte.is_ascii_lowercase() {
                            byte.to_ascii_uppercase()
                        } else { byte.to_ascii_lowercase() })).collect(),
                    };
                }
                self.current = b;
            }
            Command::Sort(options) => {
                let mut lines = self.buffer[a - 1..b].to_vec();
                lines.sort_by(|left, right| {
                    let order = compare_lines(left, right, options);
                    if options.reverse { order.reverse() } else { order }
                });
                if options.unique { lines.dedup_by(|left, right| compare_lines(left, right, options) == Ordering::Equal); }
                self.current = a + lines.len() - 1;
                self.lines_mut().splice(a - 1..b, lines);
            }
            Command::Substitute(sub) => return self.substitute(sub, range, output, in_global),
            Command::Mark(name) => self.marks[*name] = Some(self.buffer[a - 1].id),
            Command::Marks => {
                output.push_str("marks");
                let mut any = false;
                for (name, mark) in self.marks.iter().enumerate() {
                    if let Some(position) = mark.and_then(|id| self.locate(id)) {
                        write!(output, " {}={position}", char::from(b'a' + name as u8)).unwrap();
                        any = true;
                    }
                }
                output.push_str(if any { "\n" } else { " none\n" });
            }
            Command::Undo { redo, count } => self.transfer_history(*redo, *count)?,
            Command::History => {
                writeln!(output, "history undo={} redo={}", self.undo.len(), self.redo.len()).unwrap();
                for (name, records) in [("undo", &self.undo), ("redo", &self.redo)] {
                    for (i, record) in records.iter().rev().enumerate() {
                        writeln!(output, "{name} {}: {}", i + 1, record.command).unwrap();
                    }
                }
            }
            Command::Read(name) | Command::Edit(name) => {
                let file = self.files.get(name).cloned().ok_or("no such file")?;
                let after = if matches!(command, Command::Edit(_)) { self.lines_mut().clear(); 0 } else { a };
                self.insert(after, &file);
                self.current = after + file.len();
                writeln!(output, "file {name} lines={} bytes={}", file.len(), file_bytes(&file)).unwrap();
            }
            Command::Write { name, append } => {
                let mut file = if *append { self.files.get(name).map(|file| (**file).clone()).unwrap_or_default() } else { Vec::new() };
                file.extend(self.contents(range));
                writeln!(output, "file {name} lines={} bytes={}", file.len(), file_bytes(&file)).unwrap();
                self.files.insert(name.clone(), Rc::new(file));
            }
            Command::Files => {
                output.push_str("files");
                for (name, file) in &self.files { write!(output, " {name}={}", file.len()).unwrap(); }
                output.push_str(if self.files.is_empty() { " none\n" } else { "\n" });
            }
            Command::Global { inverse, search, sub } => {
                let pattern = self.pattern(search)?;
                let selected: Vec<u64> = self.buffer[a - 1..b].iter()
                    .filter(|line| line.text.contains(&pattern) != *inverse).map(|line| line.id).collect();
                if selected.is_empty() { return Err("no match"); }
                let mut substituted = false;
                for id in selected {
                    if let Some(position) = self.locate(id) {
                        self.current = position;
                        let range = self.checked_range(sub, 0, (0, 0))?;
                        let changed = self.execute(sub, range, text, output, true)?;
                        substituted |= changed;
                    }
                }
                if matches!(sub.as_ref(), Command::Substitute(_)) && !substituted { return Err("no match"); }
            }
        }
        if let Some(suffix) = command.print_suffix() {
            if self.current > 0 { self.print_line(self.current, suffix, output); }
        }
        Ok(false)
    }

    fn apply(&mut self, line: &str, text: &[String]) -> Result<String> {
        let (tokens, end) = lex_addresses(line)?;
        let addresses = Addresses::parse(tokens)?;
        let command = Command::parse(&line[end..])?;
        let count = addresses.count();
        if command.address_kind() == 0 && count > 0 { return Err("unexpected address"); }
        if command.address_kind() == 1 && count == 2 { return Err("too many addresses"); }
        let mut trial = self.clone();
        let values = trial.evaluate(&addresses)?;
        let range = trial.checked_range(&command, count, values)?;
        let mut output = String::new();
        trial.execute(&command, range, text, &mut output, false)?;
        if trial.buffer.len() > 200 { return Err("buffer full"); }
        if command.modifying() {
            trial.undo.push(Rc::new(Record { command: line.to_owned(), state: self.snapshot() }));
            trial.redo.clear();
        }
        *self = trial;
        Ok(output)
    }
}

fn leading_integer(s: &str) -> i64 {
    let (negative, digits) = if let Some(rest) = s.strip_prefix('-') { (true, rest) } else { (false, s) };
    let value = digits.bytes().take_while(u8::is_ascii_digit).fold(0_i64, |n, b| n * 10 + i64::from(b - b'0'));
    if negative { -value } else { value }
}

fn compare_lines(a: &Line, b: &Line, options: &SortOptions) -> Ordering {
    if options.numeric { leading_integer(&a.text).cmp(&leading_integer(&b.text)) }
    else if options.insensitive { a.text.to_ascii_lowercase().cmp(&b.text.to_ascii_lowercase()) }
    else { a.text.cmp(&b.text) }
}

fn file_bytes(file: &[String]) -> usize { file.iter().map(|line| line.len() + 1).sum() }

fn main() -> io::Result<()> {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input)?;
    let mut lines = input.lines();
    let mut editor = Editor::new();
    let stdout = io::stdout();
    let mut output = io::BufWriter::new(stdout.lock());
    while let Some(line) = lines.next() {
        if line == "Q" { break; }
        let mut text = Vec::new();
        if with_text(line) {
            for entered in lines.by_ref() {
                if entered == "." { break; }
                text.push(entered.to_owned());
            }
        }
        match editor.apply(line, &text) {
            Ok(response) => output.write_all(response.as_bytes())?,
            Err(reason) => writeln!(output, "? {reason}")?,
        }
    }
    output.flush()
}
