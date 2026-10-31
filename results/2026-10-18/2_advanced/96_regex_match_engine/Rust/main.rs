mod charset;
mod formatter;
mod backtrack_vm;
mod pike_vm;
use std::collections::{
    BTreeMap,
    BTreeSet
};
use std::fs;
use charset::Set;
#[derive(Clone, Copy)]
pub struct Flags {
    pub i: bool,
    pub m: bool,
    pub s: bool
}
pub type Capture = Vec<Option<usize>>;
#[derive(Clone)]
pub enum Instruction {
    Char(u8),
    Any,
    Class(Set, bool),
    Split(usize, usize),
    Jump(usize),
    Save(usize),
    Assert(String),
    Backref(usize),
    Look(String, usize),
    Match
}
#[derive(Clone)]
enum Node {
    Literal(u8),
    Any,
    Class(Set, bool),
    Assert(String),
    Backref(usize),
    Named(String),
    Group(usize, Box<Node>),
    Look(bool, Box<Node>),
    Concat(Vec<Node>),
    Alternate(Vec<Node>),
    Repeat(Box<Node>, usize, Option<usize>, String),
}
struct Pattern {
    name: String,
    flags_text: String,
    flags: Flags,
    text: String,
    groups: usize,
    names: BTreeMap<String,
    usize>,
    root: Option<Node>,
    code: Vec<Instruction>,
    error: Option<(String, usize)>,
    pike: bool
}
struct Parser {
    bytes: Vec<u8>,
    index: usize,
    groups: usize,
    names: BTreeMap<String,
    usize>,
    references: Vec<(usize, Option<usize>, String)>
}
type ParseResult<T> = Result<T, (String, usize)>;
impl Parser {
    fn peek(&self) -> Option<u8> {
        self.bytes.get(self.index).copied()
    }
    fn error<T>(&self, message: &str, at: usize) -> ParseResult<T> {
        Err((message.into(), at + 1))
    }
    fn alternation(&mut self) -> ParseResult<Node> {
        let mut nodes = vec![self.concatenation()?];
        while self.peek() == Some(b'|') {
            self.index += 1;
            nodes.push(self.concatenation()?);
        }
        if nodes.len() == 1 {
            Ok(nodes.remove(0))
        } else {
            Ok(Node::Alternate(nodes))
        }
    }
    fn concatenation(&mut self) -> ParseResult<Node> {
        let mut nodes = Vec::new();
        while self.peek().map_or(false, |c| c != b'|' && c != b')') {
            nodes.push(self.quantified()?);
        }
        if nodes.len() == 1 {
            Ok(nodes.remove(0))
        } else {
            Ok(Node::Concat(nodes))
        }
    }
    fn quantified(&mut self) -> ParseResult<Node> {
        if self.peek().map_or(false, |c| b"*+?{".contains(&c)) {
            return self.error("nothing to repeat", self.index);
        }
        let node = self.element()?;
        if !self.peek().map_or(false, |c| b"*+?{".contains(&c)) {
            return Ok(node);
        }
        if matches!(node, Node::Assert(_) | Node::Look(_, _)) {
            return self.error("nothing to repeat", self.index);
        }
        let quantifier = self.peek().unwrap();
        let (minimum, maximum) = if quantifier == b'{' {
            self.braces()?
        } else {
            self.index += 1;
            match quantifier {
                b'*' => (0, None),
                b'+' => (1, None),
                _ => (0, Some(1))
            }
        };
        let kind = if self.peek() == Some(b'?') {
            self.index += 1;
            "lazy"
        } else if self.peek() == Some(b'+') {
            self.index += 1;
            "possessive"
        } else {
            "greedy"
        };
        if self.peek().map_or(false, |c| b"*+?{".contains(&c)) {
            return self.error("nested quantifier", self.index);
        }
        Ok(Node::Repeat(Box::new(node), minimum, maximum, kind.into()))
    }
    fn digits(&mut self) -> Option<usize> {
        let start = self.index;
        while self.peek().map_or(false, |c| c.is_ascii_digit()) {
            self.index += 1;
        }
        if start == self.index {
            None
        } else {
            Some(std::str::from_utf8(&self.bytes[start..self.index]).unwrap().parse().unwrap())
        }
    }
    fn braces(&mut self) -> ParseResult<(usize, Option<usize>)> {
        let start = self.index;
        self.index += 1;
        let minimum = match self.digits() {
            Some(value) => value,
            None => return self.error("invalid quantifier", start)
        };
        let maximum = if self.peek() == Some(b'}') {
            Some(minimum)
        } else if self.peek() == Some(b',') {
            self.index += 1;
            if self.peek() == Some(b'}') {
                None
            } else {
                match self.digits() {
                    Some(value) => Some(value),
                    None => return self.error("invalid quantifier", start)
                }
            }
        } else {
            return self.error("invalid quantifier", start);
        };
        if self.peek() != Some(b'}') {
            return self.error("invalid quantifier", start);
        }
        self.index += 1;
        if minimum > 100 || maximum.map_or(false, |v| v > 100) {
            return self.error("quantifier too large", start);
        }
        if maximum.map_or(false, |v| minimum > v) {
            return self.error("quantifier range out of order", start);
        }
        Ok((minimum, maximum))
    }
    fn name(&mut self) -> ParseResult<String> {
        let start = self.index;
        if self.peek().map_or(false, |c| c.is_ascii_alphabetic() || c == b'_') {
            self.index += 1;
            while self.peek().map_or(false, |c| c.is_ascii_alphanumeric() || c == b'_') {
                self.index += 1;
            }
        }
        if self.index == start || self.peek() != Some(b'>') {
            return self.error("invalid group name", self.index);
        }
        let name = String::from_utf8(self.bytes[start..self.index].to_vec()).unwrap();
        self.index += 1;
        Ok(name)
    }
    fn group(&mut self) -> ParseResult<Node> {
        let start = self.index;
        self.index += 1;
        let mut mode = "capture";
        let mut named = None;
        if self.peek() == Some(b'?') {
            self.index += 1;
            mode = match self.peek() {
                Some(b':') => "plain",
                Some(b'=') => "ahead",
                Some(b'!') => "negative",
                Some(b'<') => "capture",
                _ => return self.error("invalid group", start)
            };
            let named_group = self.peek() == Some(b'<');
            self.index += 1;
            if named_group {
                let name_start = self.index;
                let name = self.name()?;
                if self.names.contains_key(&name) {
                    return self.error("duplicate group name", name_start);
                }
                named = Some(name);
            }
        }
        let group = if mode == "capture" {
            self.groups += 1;
            if let Some(name) = named {
                self.names.insert(name, self.groups);
            }
            Some(self.groups)
        } else {
            None
        };
        let content = self.alternation()?;
        if self.peek() != Some(b')') {
            return self.error("missing )", start);
        }
        self.index += 1;
        Ok(if let Some(number) = group {
            Node::Group(number, Box::new(content))
        } else if mode == "plain" {
            content
        } else {
            Node::Look(mode == "ahead", Box::new(content))
        })
    }
    fn class_item(&mut self) -> ParseResult<(Set, bool)> {
        let start = self.index;
        let c = match self.peek() {
            Some(c) => c,
            None => return self.error("missing ]", start)
        };
        self.index += 1;
        if c != b'\\' {
            return Ok((BTreeSet::from([c]), false));
        }
        let c = match self.peek() {
            Some(c) => c,
            None => return self.error("trailing backslash", start)
        };
        self.index += 1;
        if b"dDwWsS".contains(&c) {
            return Ok((charset::base(c), true));
        }
        let c = match c {
            b'n' => 10,
            b't' => 9,
            c if c.is_ascii_alphanumeric() => return self.error("invalid escape", start),
            c => c
        };
        Ok((BTreeSet::from([c]), false))
    }
    fn class(&mut self) -> ParseResult<Node> {
        let start = self.index;
        self.index += 1;
        let negated = self.peek() == Some(b'^');
        if negated {
            self.index += 1;
        }
        if self.peek() == Some(b']') {
            return self.error("empty class", self.index);
        }
        let mut set = Set::new();
        loop {
            if self.peek().is_none() {
                return self.error("missing ]", start);
            }
            if self.peek() == Some(b']') {
                self.index += 1;
                break;
            }
            let (left, is_set) = self.class_item()?;
            if self.peek() == Some(b'-') && self.bytes.get(self.index + 1).map_or(false, |c| *c != b']') {
                let hyphen = self.index;
                self.index += 1;
                if is_set {
                    return self.error("invalid range", hyphen);
                }
                let (right, is_set) = self.class_item()?;
                let a = *left.iter().next().unwrap();
                let b = *right.iter().next().unwrap();
                if is_set || a > b {
                    return self.error("invalid range", hyphen);
                }
                set.extend(a..=b);
            } else {
                set.extend(left);
            }
        }
        Ok(Node::Class(set, negated))
    }
    fn escape(&mut self) -> ParseResult<Node> {
        let start = self.index;
        self.index += 1;
        let c = match self.peek() {
            Some(c) => c,
            None => return self.error("trailing backslash", start)
        };
        self.index += 1;
        if b"dDwWsS".contains(&c) {
            return Ok(Node::Class(charset::base(c.to_ascii_lowercase()), c.is_ascii_uppercase()));
        }
        match c {
            b'b' => Ok(Node::Assert("WORD".into())),
            b'B' => Ok(Node::Assert("NOTWORD".into())),
            b'n' => Ok(Node::Literal(10)),
            b't' => Ok(Node::Literal(9)),
            b'1'..=b'9' => {
                self.index -= 1;
                let number = self.digits().unwrap();
                self.references.push((start, Some(number), String::new()));
                Ok(Node::Backref(number))
            },
            b'k' => {
                if self.peek() != Some(b'<') {
                    return self.error("invalid escape", start);
                }
                self.index += 1;
                let name = self.name()?;
                self.references.push((start, None, name.clone()));
                Ok(Node::Named(name))
            },
            c if c.is_ascii_alphanumeric() => self.error("invalid escape", start),
            c => Ok(Node::Literal(c))
        }
    }
    fn element(&mut self) -> ParseResult<Node> {
        match self.peek().unwrap() {
            b'(' => self.group(),
            b'[' => self.class(),
            b'\\' => self.escape(),
            b'.' => {
                self.index += 1;
                Ok(Node::Any)
            },
            b'^' => {
                self.index += 1;
                Ok(Node::Assert("BOL".into()))
            },
            b'$' => {
                self.index += 1;
                Ok(Node::Assert("EOL".into()))
            },
            c => {
                self.index += 1;
                Ok(Node::Literal(c))
            }
        }
    }
}
fn compile(node: &Node, code: &mut Vec<Instruction>, names: &BTreeMap<String, usize>) {
    match node {
        Node::Literal(c) => code.push(Instruction::Char(*c)),
        Node::Any => code.push(Instruction::Any),
        Node::Class(s, n) => code.push(Instruction::Class(s.clone(), *n)),
        Node::Assert(kind) => code.push(Instruction::Assert(kind.clone())),
        Node::Backref(k) => code.push(Instruction::Backref(*k)),
        Node::Named(name) => code.push(Instruction::Backref(names[name])),
        Node::Group(k, content) => {
            code.push(Instruction::Save(2 * k));
            compile(content, code, names);
            code.push(Instruction::Save(2 * k + 1));
        },
        Node::Look(positive, content) => {
            let start = code.len();
            code.push(Instruction::Look(if *positive {
                "AHEAD"
            } else {
                "NOT"
            }.into(), 0));
            compile(content, code, names);
            code.push(Instruction::Match);
            let end = code.len();
            if let Instruction::Look(_, target) = &mut code[start] {
                *target = end;
            }
        },
        Node::Concat(nodes) => for node in nodes {
            compile(node, code, names);
        },
        Node::Alternate(nodes) => {
            let mut jumps = Vec::new();
            for node in &nodes[..nodes.len() - 1] {
                let split = code.len();
                code.push(Instruction::Split(split + 1, 0));
                compile(node, code, names);
                jumps.push(code.len());
                code.push(Instruction::Jump(0));
                let end = code.len();
                if let Instruction::Split(_, b) = &mut code[split] {
                    *b = end;
                }
            }
            compile(nodes.last().unwrap(), code, names);
            let end = code.len();
            for jump in jumps {
                code[jump] = Instruction::Jump(end);
            }
        },
        Node::Repeat(content, minimum, maximum, kind) => {
            if kind == "possessive" {
                let start = code.len();
                code.push(Instruction::Look("ATOMIC".into(), 0));
                compile(&Node::Repeat(content.clone(), *minimum, *maximum, "greedy".into()), code, names);
                code.push(Instruction::Match);
                let end = code.len();
                code[start] = Instruction::Look("ATOMIC".into(), end);
                return;
            }
            let greedy = kind == "greedy";
            if let Some(maximum) = maximum {
                for _ in 0..*minimum {
                    compile(content, code, names);
                }
                let mut splits = Vec::new();
                for _ in *minimum..*maximum {
                    let split = code.len();
                    splits.push(split);
                    code.push(Instruction::Split(0, 0));
                    compile(content, code, names);
                }
                let end = code.len();
                for split in splits {
                    code[split] = if greedy {
                        Instruction::Split(split + 1, end)
                    } else {
                        Instruction::Split(end, split + 1)
                    };
                }
            } else if *minimum == 0 {
                let split = code.len();
                code.push(Instruction::Split(0, 0));
                compile(content, code, names);
                code.push(Instruction::Jump(split));
                let end = code.len();
                code[split] = if greedy {
                    Instruction::Split(split + 1, end)
                } else {
                    Instruction::Split(end, split + 1)
                };
            } else {
                for _ in 0..minimum - 1 {
                    compile(content, code, names);
                }
                let start = code.len();
                compile(content, code, names);
                let end = code.len() + 1;
                code.push(if greedy {
                    Instruction::Split(start, end)
                } else {
                    Instruction::Split(end, start)
                });
            }
        }
    }
}
fn length(node: &Node) -> (usize, Option<usize>) {
    match node {
        Node::Literal(_) | Node::Any | Node::Class(_, _) => (1, Some(1)),
        Node::Assert(_) | Node::Look(_, _) => (0, Some(0)),
        Node::Backref(_) | Node::Named(_) => (0, None),
        Node::Group(_, content) => length(content),
        Node::Concat(nodes) => {
            let ranges: Vec<_> = nodes.iter().map(length).collect();
            (ranges.iter().map(|r| r.0).sum(), ranges.iter().try_fold(0, |sum, r| r.1.map(|n| sum + n)))
        },
        Node::Alternate(nodes) => {
            let ranges: Vec<_> = nodes.iter().map(length).collect();
            (ranges.iter().map(|r| r.0).min().unwrap(), if ranges.iter().any(|r| r.1.is_none()) {
                None
            } else {
                Some(ranges.iter().map(|r| r.1.unwrap()).max().unwrap())
            })
        },
        Node::Repeat(content, minimum, maximum, _) => {
            let (a, b) = length(content);
            (a * minimum, if b == Some(0) {
                Some(0)
            } else {
                match (b, maximum) {
                    (Some(b), Some(n)) => Some(b * n),
                    _ => None
                }
            })
        }
    }
}
fn first(node: &Node, flags: Flags) -> (Set, bool) {
    match node {
        Node::Literal(c) => {
            let mut set = BTreeSet::from([*c]);
            if flags.i && c.is_ascii_alphabetic() {
                set.insert(charset::swap(*c));
            }
            (set, false)
        },
        Node::Any => ((0..128).filter(|&c| flags.s || c != 10).collect(), false),
        Node::Class(set, negated) => ((0..128).filter(|&c| charset::class(c, set, *negated, flags)).collect(), false),
        Node::Assert(_) | Node::Look(_, _) => (Set::new(), true),
        Node::Backref(_) | Node::Named(_) => ((0..128).collect(), true),
        Node::Group(_, content) => first(content, flags),
        Node::Concat(nodes) => {
            let mut set = Set::new();
            for node in nodes {
                let (part, nullable) = first(node, flags);
                set.extend(part);
                if !nullable {
                    return (set, false);
                }
            }
            (set, true)
        },
        Node::Alternate(nodes) => {
            let mut set = Set::new();
            let mut nullable = false;
            for node in nodes {
                let (part, empty) = first(node, flags);
                set.extend(part);
                nullable |= empty;
            }
            (set, nullable)
        },
        Node::Repeat(content, minimum, maximum, _) => if *maximum == Some(0) {
            (Set::new(), true)
        } else {
            let (set, nullable) = first(content, flags);
            (set, nullable || *minimum == 0)
        }
    }
}
pub fn consumes(instruction: &Instruction, subject: &[u8], position: usize, flags: Flags) -> bool {
    if position == subject.len() {
        return false;
    }
    match instruction {
        Instruction::Char(c) => charset::equal(*c, subject[position], flags),
        Instruction::Any => flags.s || subject[position] != 10,
        Instruction::Class(set, negated) => charset::class(subject[position], set, *negated, flags),
        _ => false
    }
}
fn pattern(line: &str) -> Pattern {
    let fields: Vec<&str> = line.splitn(3, ' ').collect();
    let mut parser = Parser {
        bytes: fields[2].as_bytes().to_vec(),
        index: 0,
        groups: 0,
        names: BTreeMap::new(),
        references: Vec::new()
    };
    let parsed = parser.alternation().and_then(|root| if parser.index < parser.bytes.len() {
        parser.error("unmatched )", parser.index)
    } else {
        Ok(root)
    }).and_then(|root| {
        for (column, number, name) in &parser.references {
            if number.map_or(false, |k| k > parser.groups) {
                return Err(("invalid group reference".into(), column + 1));
            }
            if number.is_none() && !parser.names.contains_key(name) {
                return Err(("unknown group name".into(), column + 1));
            }
        }
        Ok(root)
    });
    let flags = Flags {
        i: fields[1].contains('i'),
        m: fields[1].contains('m'),
        s: fields[1].contains('s')
    };
    let mut code = Vec::new();
    let (root, error) = match parsed {
        Ok(root) => {
            code.push(Instruction::Save(0));
            compile(&root, &mut code, &parser.names);
            code.push(Instruction::Save(1));
            code.push(Instruction::Match);
            (Some(root), None)
        },
        Err(error) => (None, Some(error))
    };
    let pike = !code.iter().any(|i| matches!(i, Instruction::Look(_, _) | Instruction::Backref(_)));
    Pattern {
        name: fields[0].into(),
        flags_text: fields[1].into(),
        flags,
        text: fields[2].into(),
        groups: parser.groups,
        names: parser.names,
        root,
        code,
        error,
        pike
    }
}
fn decode(quoted: &str) -> Vec<u8> {
    let bytes = quoted.as_bytes();
    let mut result = Vec::new();
    let mut i = 1;
    while i + 1 < bytes.len() {
        if bytes[i] == b'\\' {
            i += 1;
            result.push(match bytes[i] {
                b'n' => 10,
                b't' => 9,
                c => c
            });
        } else {
            result.push(bytes[i]);
        }
        i += 1;
    }
    result
}
enum Part {
    Character(u8),
    Group(usize)
}
fn template(bytes: &[u8], pattern: &Pattern) -> Option<Vec<Part>> {
    let mut parts = Vec::new();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] != b'$' {
            parts.push(Part::Character(bytes[i]));
            i += 1;
            continue;
        }
        i += 1;
        if bytes.get(i) == Some(&b'$') {
            parts.push(Part::Character(b'$'));
            i += 1;
            continue;
        }
        let number = if bytes.get(i).map_or(false, |c| c.is_ascii_digit()) {
            let n = (bytes[i] - b'0') as usize;
            i += 1;
            n
        }
        else if bytes.get(i) == Some(&b'{') {
            i += 1;
            let end = (i..bytes.len()).find(|&j| bytes[j] == b'}')?;
            let name = std::str::from_utf8(&bytes[i..end]).unwrap();
            i = end + 1;
            if !name.is_empty() && name.bytes().all(|c| c.is_ascii_digit()) {
                name.parse().ok()?
            } else {
                *pattern.names.get(name)?
            }
        } else {
            return None;
        };
        if number > pattern.groups {
            return None;
        }
        parts.push(Part::Group(number));
    }
    Some(parts)
}
fn group<'a>(capture: &Capture, k: usize, subject: &'a [u8]) -> Option<&'a [u8]> {
    match (capture[2 * k], capture[2 * k + 1]) {
        (Some(a), Some(b)) => Some(&subject[a..b]),
        _ => None
    }
}
fn match_lines(capture: &Capture, pattern: &Pattern, subject: &[u8], output: &mut Vec<String>) {
    for k in 0..=pattern.groups {
        let heading = if k == 0 {
            "match".into()
        } else {
            format!("group {}", k)
        };
        output.push(if let Some(value) = group(capture, k, subject) {
            format!("{} {}-{} {}", heading, capture[2 * k].unwrap(), capture[2 * k + 1].unwrap(), formatter::quote(value))
        } else {
            format!("{} -", heading)
        });
    }
}
fn scan_backtrack(vm: &mut backtrack_vm::Backtrack, length: usize, scan: bool) -> Result<Vec<Capture>, ()> {
    let mut matches = Vec::new();
    let mut start = 0;
    while start <= length {
        match vm.search(start)? {
            Some(capture) => {
                let a = capture[0].unwrap();
                let b = capture[1].unwrap();
                start = if a == b {
                    b + 1
                } else {
                    b
                };
                matches.push(capture);
            },
            None => break
        }
        if !scan {
            break;
        }
    }
    Ok(matches)
}
fn scan_pike(vm: &mut pike_vm::Pike, length: usize, scan: bool) -> Vec<Capture> {
    let mut matches = Vec::new();
    let mut start = 0;
    while start <= length {
        match vm.search(start) {
            Some(capture) => {
                let a = capture[0].unwrap();
                let b = capture[1].unwrap();
                start = if a == b {
                    b + 1
                } else {
                    b
                };
                matches.push(capture);
            },
            None => break
        }
        if !scan {
            break;
        }
    }
    matches
}
fn list(pattern: &Pattern, output: &mut Vec<String>) {
    let mut names: Vec<_> = pattern.names.iter().collect();
    names.sort_by_key(|e| *e.1);
    let names = if names.is_empty() {
        "-".into()
    } else {
        names.iter().map(|e| format!("{}:{}", e.0, e.1)).collect::<Vec<_>>().join(",")
    };
    let root = pattern.root.as_ref().unwrap();
    let (minimum, maximum) = length(root);
    let (set, _) = first(root, pattern.flags);
    output.push(format!("=== {}", pattern.name));
    output.push(format!("flags={} groups={} names={} length={}..{} first={} pike={} size={}", pattern.flags_text, pattern.groups, names, minimum, maximum.map_or("inf".into(), |v| v.to_string()), if set.is_empty() {
        "-".into()
    } else {
        formatter::set(&set, false)
    }, if pattern.pike {
        "yes"
    } else {
        "no"
    }, pattern.code.len()));
    for (i, instruction) in pattern.code.iter().enumerate() {
        output.push(format!("{} {}", i, formatter::instruction(instruction)));
    }
}
fn write(name: &str, lines: &[String]) {
    fs::create_dir_all("output").unwrap();
    fs::write(format!("output/{}", name), if lines.is_empty() {
        String::new()
    } else {
        lines.join("\n") + "\n"
    }).unwrap();
}
fn main() {
    let patterns: Vec<Pattern> = fs::read_to_string("input/patterns.txt").unwrap().lines().map(pattern).collect();
    let by_name: BTreeMap<String,
    usize> = patterns.iter().enumerate().map(|(i, p)| (p.name.clone(), i)).collect();
    let mut subjects = BTreeMap::new();
    for line in fs::read_to_string("input/subjects.txt").unwrap().lines() {
        let (name, value) = line.split_once(' ').unwrap();
        subjects.insert(name.to_string(), decode(value));
    }
    let mut errors = Vec::new();
    for pattern in &patterns {
        if let Some((message, column)) = &pattern.error {
            errors.push(format!("{}: {} at column {}", pattern.name, message, column));
            errors.push(format!("  {}", pattern.text));
            errors.push(format!("{}^", " ".repeat(column + 1)));
        }
    }
    if errors.is_empty() {
        errors.push("no errors".into());
    }
    let mut results = Vec::new();
    let mut programs = Vec::new();
    let mut steps = vec!["command,engine,steps".into()];
    for (index, line) in fs::read_to_string("input/commands.txt").unwrap().lines().enumerate() {
        results.push(format!("#{} {}", index + 1, line));
        let fields: Vec<&str> = line.splitn(5, ' ').collect();
        let command = fields[0];
        let replacing = command == "REPLACE";
        let p = if replacing {
            fields[2]
        } else {
            fields[1]
        };
        let pattern = &patterns[by_name[p]];
        if pattern.error.is_some() {
            results.push("invalid pattern".into());
            continue;
        }
        if command == "LIST" {
            results.push(format!("instructions {}", pattern.code.len()));
            list(pattern, &mut programs);
            continue;
        }
        let subject_name = if replacing {
            fields[3]
        } else {
            fields[2]
        };
        let subject = &subjects[subject_name];
        let parts = if replacing {
            match template(&decode(fields[4]), pattern) {
                Some(parts) => parts,
                None => {
                    results.push("invalid template".into());
                    continue;
                }
            }
        } else {
            Vec::new()
        };
        let scan = command == "FINDALL" || command == "SPLIT" || (replacing && fields[1] == "ALL");
        let full = command == "MATCH";
        let mut backtrack = backtrack_vm::Backtrack::new(&pattern.code, subject, pattern.flags, pattern.groups, full);
        let backtrack_matches = scan_backtrack(&mut backtrack, subject.len(), scan);
        steps.push(format!("{},backtrack,{}", index + 1, backtrack.steps));
        let (matches, label) = if pattern.pike {
            let mut pike = pike_vm::Pike::new(&pattern.code, subject, pattern.flags, pattern.groups, full);
            let matches = scan_pike(&mut pike, subject.len(), scan);
            steps.push(format!("{},pike,{}", index + 1, pike.steps));
            if let Ok(backtrack_matches) = &backtrack_matches {
                if *backtrack_matches != matches {
                    results.push("MISMATCH".into());
                    continue;
                }
                (matches, "both")
            } else {
                (matches, "pike (backtrack: TOO_MANY_STEPS)")
            }
        } else {
            match backtrack_matches {
                Ok(matches) => (matches, "backtrack"),
                Err(()) => {
                    results.push("TOO_MANY_STEPS".into());
                    continue;
                }
            }
        };
        results.push(format!("engine {}", label));
        if command == "MATCH" || command == "SEARCH" {
            if matches.is_empty() {
                results.push("no match".into());
            } else {
                match_lines(&matches[0], pattern, subject, &mut results);
            }
        }
        else if command == "FINDALL" {
            results.push(format!("matches {}", matches.len()));
            for capture in &matches {
                match_lines(capture, pattern, subject, &mut results);
            }
        }
        else if replacing {
            let mut result = Vec::new();
            let mut last = 0;
            for capture in &matches {
                result.extend(&subject[last..capture[0].unwrap()]);
                for part in &parts {
                    match part {
                        Part::Character(c) => result.push(*c),
                        Part::Group(k) => if let Some(value) = group(capture, *k, subject) {
                            result.extend(value);
                        }
                    }
                }
                last = capture[1].unwrap();
            }
            result.extend(&subject[last..]);
            results.push(format!("replacements {}", matches.len()));
            results.push(format!("result {}", formatter::quote(&result)));
        } else {
            results.push(format!("pieces {}", matches.len() + 1));
            let first_end = matches.first().map_or(subject.len(), |c| c[0].unwrap());
            results.push(format!("piece {}", formatter::quote(&subject[..first_end])));
            for (i, capture) in matches.iter().enumerate() {
                for k in 1..=pattern.groups {
                    results.push(if let Some(value) = group(capture, k, subject) {
                        format!("group {} {}", k, formatter::quote(value))
                    } else {
                        format!("group {} -", k)
                    });
                }
                let end = matches.get(i + 1).map_or(subject.len(), |c| c[0].unwrap());
                results.push(format!("piece {}", formatter::quote(&subject[capture[1].unwrap()..end])));
            }
        }
    }
    if programs.is_empty() {
        programs.push("no programs".into());
    }
    write("results.txt", &results);
    write("programs.txt", &programs);
    write("steps.csv", &steps);
    write("errors.txt", &errors);
}
