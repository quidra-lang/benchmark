use std::collections::BTreeMap;
use std::io::{self, Read};

#[derive(Clone)]
struct Fault {
    word: String,
    reason: String,
    code: Option<i64>,
}
type Running<T> = Result<T, Fault>;

fn fault(word: &str, reason: impl Into<String>, code: Option<i64>) -> Fault {
    Fault {
        word: word.into(),
        reason: reason.into(),
        code,
    }
}

#[derive(Clone)]
struct Instruction {
    op: String,
    spelling: String,
    value: i64,
    word: usize,
    text: String,
    slots: Vec<usize>,
    target: usize,
}

impl Instruction {
    fn new(op: &str, spelling: &str) -> Self {
        Self {
            op: op.into(),
            spelling: spelling.into(),
            value: 0,
            word: 0,
            text: String::new(),
            slots: Vec::new(),
            target: 0,
        }
    }
}

struct Word {
    name: String,
    original: String,
    kind: String,
    here: usize,
    value: i64,
    address: usize,
    token: usize,
    deferred: Option<usize>,
    does: Option<(usize, usize)>,
    locals: usize,
    code: Vec<Instruction>,
}

impl Word {
    fn new(name: &str, original: &str, kind: &str, here: usize) -> Self {
        Self {
            name: name.into(),
            original: original.into(),
            kind: kind.into(),
            here,
            value: 0,
            address: 0,
            token: 0,
            deferred: None,
            does: None,
            locals: 0,
            code: Vec::new(),
        }
    }
}

struct Control {
    kind: String,
    index: usize,
    begin: usize,
    leaves: Vec<usize>,
    ends: Vec<usize>,
}

impl Control {
    fn new(kind: &str, index: usize, begin: usize) -> Self {
        Self {
            kind: kind.into(),
            index,
            begin,
            leaves: Vec::new(),
            ends: Vec::new(),
        }
    }
}

struct Compiler {
    word: usize,
    anonymous: bool,
    locals: BTreeMap<String, usize>,
    control: Vec<Control>,
}

struct Forth {
    data: Vec<i64>,
    returns: Vec<i64>,
    memory: Vec<i64>,
    words: Vec<Word>,
    users: Vec<usize>,
    builtins: BTreeMap<String, usize>,
    tokens: Vec<usize>,
    output: Vec<String>,
    pending: String,
    compiler: Option<Compiler>,
    line: String,
    at: usize,
    depth: usize,
}

fn compile_only(n: &str) -> bool {
    [
        "IF", "ELSE", "THEN", "DO", "?DO", "LOOP", "+LOOP", "LEAVE", "UNLOOP", "I", "J", "BEGIN",
        "UNTIL", "WHILE", "REPEAT", "AGAIN", "CASE", "OF", "ENDOF", "ENDCASE", "EXIT", "RECURSE",
        "DOES>", ";", ">R", "R>", "R@", "ABORT\"", "[']", "{:",
    ]
    .contains(&n)
}

fn interpret_only(n: &str) -> bool {
    [":", ":NONAME", "FORGET"].contains(&n)
}

fn both(n: &str) -> bool {
    [".\"", "(", "\\", "TO", "IS"].contains(&n)
}

impl Forth {
    fn new() -> Self {
        let mut f = Self {
            data: Vec::new(),
            returns: Vec::new(),
            memory: vec![10],
            words: Vec::new(),
            users: Vec::new(),
            builtins: BTreeMap::new(),
            tokens: Vec::new(),
            output: Vec::new(),
            pending: String::new(),
            compiler: None,
            line: String::new(),
            at: 0,
            depth: 0,
        };
        for n in "+ - * / MOD /MOD */ */MOD NEGATE ABS MIN MAX 1+ 1- 2* 2/ = <> < > 0= 0<> 0< 0> WITHIN TRUE FALSE AND OR XOR INVERT DUP ?DUP DROP SWAP OVER ROT -ROT NIP TUCK 2DUP 2DROP 2SWAP 2OVER DEPTH PICK ROLL . .R .S ? CR EMIT SPACE SPACES BL ! @ +! , ALLOT HERE CELLS CELL+ BASE HEX DECIMAL CREATE VARIABLE CONSTANT VALUE DEFER ' EXECUTE CATCH THROW ABORT WORDS".split(' ') {
            let i = f.words.len();
            f.words.push(Word::new(n, n, "builtin", 8));
            f.builtins.insert(n.into(), i);
        }
        f
    }

    fn pop(&mut self, n: usize, owner: &str) -> Running<Vec<i64>> {
        if self.data.len() < n {
            return Err(fault(owner, "stack underflow", Some(-4)));
        }
        Ok(self.data.split_off(self.data.len() - n))
    }

    fn push(&mut self, n: i64, owner: &str) -> Running<()> {
        self.data.push(n);
        if self.data.len() > 1000 {
            Err(fault(owner, "stack overflow", Some(-3)))
        } else {
            Ok(())
        }
    }

    fn push_all(&mut self, values: &[i64], owner: &str) -> Running<()> {
        for &n in values {
            self.push(n, owner)?;
        }
        Ok(())
    }

    fn return_need(&self, n: usize, owner: &str) -> Running<()> {
        if self.returns.len() < n {
            Err(fault(owner, "return stack underflow", Some(-6)))
        } else {
            Ok(())
        }
    }

    fn return_push(&mut self, n: i64, owner: &str) -> Running<()> {
        self.returns.push(n);
        if self.returns.len() > 1000 {
            Err(fault(owner, "return stack overflow", Some(-5)))
        } else {
            Ok(())
        }
    }

    fn address(&self, n: i64, owner: &str) -> Running<usize> {
        if n < 0 || n % 8 != 0 || n >= self.memory.len() as i64 * 8 {
            Err(fault(owner, "invalid address", Some(-9)))
        } else {
            Ok(n as usize / 8)
        }
    }

    fn read_word(&mut self) -> Option<String> {
        let b = self.line.as_bytes();
        while self.at < b.len() && b[self.at] == b' ' {
            self.at += 1;
        }
        let start = self.at;
        while self.at < b.len() && b[self.at] != b' ' {
            self.at += 1;
        }
        if self.at == start {
            None
        } else {
            Some(self.line[start..self.at].into())
        }
    }

    fn read_name(&mut self, owner: &str) -> Running<String> {
        self.read_word()
            .ok_or_else(|| fault(owner, "missing name", Some(-16)))
    }

    fn find(&self, raw: &str) -> Option<usize> {
        let n = raw.to_ascii_uppercase();
        self.users
            .iter()
            .rev()
            .copied()
            .find(|&i| self.words[i].name == n)
            .or_else(|| self.builtins.get(&n).copied())
    }

    fn number(&self, raw: &str, owner: &str, base: i64) -> Running<Option<i64>> {
        let bytes = raw.as_bytes();
        if bytes.len() == 3 && bytes[0] == b'\'' && bytes[2] == b'\'' {
            return Ok(Some(bytes[1] as i64));
        }
        let upper = raw.to_ascii_uppercase();
        let mut s = upper.as_str();
        let mut radix = base;
        if let Some(c) = s.as_bytes().first() {
            if b"$#%".contains(c) {
                radix = match c {
                    b'$' => 16,
                    b'#' => 10,
                    _ => 2,
                };
                s = &s[1..];
            } else if !(2..=36).contains(&radix) {
                return Err(fault(owner, "invalid base", Some(-40)));
            }
        } else if !(2..=36).contains(&radix) {
            return Err(fault(owner, "invalid base", Some(-40)));
        }
        let sign = if let Some(rest) = s.strip_prefix('-') {
            s = rest;
            -1
        } else {
            1
        };
        if s.is_empty() {
            return Ok(None);
        }
        let mut digits = Vec::new();
        for c in s.bytes() {
            let d = if c.is_ascii_digit() {
                (c - b'0') as i64
            } else if c.is_ascii_uppercase() {
                (c - b'A' + 10) as i64
            } else {
                return Ok(None);
            };
            if d >= radix {
                return Ok(None);
            }
            digits.push(d);
        }
        let mut value = 0;
        for d in digits {
            value = value * radix + d;
        }
        Ok(Some(sign * value))
    }

    fn check_name(&self, raw: &str) -> Running<()> {
        let n = raw.to_ascii_uppercase();
        if compile_only(&n)
            || interpret_only(&n)
            || both(&n)
            || self.number(raw, raw, 10)?.is_some()
        {
            Err(fault(raw, "invalid name", Some(-19)))
        } else {
            Ok(())
        }
    }

    fn token(&mut self, i: usize) -> i64 {
        if self.words[i].token == 0 {
            self.tokens.push(i);
            self.words[i].token = self.tokens.len();
        }
        self.words[i].token as i64
    }

    fn token_word(&self, n: i64, owner: &str) -> Running<usize> {
        if n < 1 || n > self.tokens.len() as i64 {
            Err(fault(owner, "invalid argument", Some(-24)))
        } else {
            Ok(self.tokens[n as usize - 1])
        }
    }

    fn radix(&self, owner: &str) -> Running<i64> {
        let b = self.memory[0];
        if (2..=36).contains(&b) {
            Ok(b)
        } else {
            Err(fault(owner, "invalid base", Some(-40)))
        }
    }

    fn format(n: i64, base: i64) -> String {
        let mut v = n.abs();
        let mut out = Vec::new();
        loop {
            out.push(b"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"[(v % base) as usize] as char);
            v /= base;
            if v == 0 {
                break;
            }
        }
        if n < 0 {
            out.push('-');
        }
        out.into_iter().rev().collect()
    }

    fn flush(&mut self) {
        self.output.push(self.pending.trim_end_matches(' ').into());
        self.pending.clear();
    }

    fn quotient(a: i64, b: i64) -> i64 {
        let q = a / b;
        if a % b != 0 && (a < 0) != (b < 0) {
            q - 1
        } else {
            q
        }
    }

    fn execute_definition(&mut self, definition: usize, start: usize, owner: &str) -> Running<()> {
        if self.depth == 100 {
            return Err(fault(owner, "nesting too deep", Some(-7)));
        }
        self.depth += 1;
        let old_return = self.returns.len();
        let mut locals = vec![0; self.words[definition].locals];
        let mut pc = start;
        while pc < self.words[definition].code.len() {
            let i = self.words[definition].code[pc].clone();
            pc += 1;
            let s = i.spelling.as_str();
            match i.op.as_str() {
                "literal" => self.push(i.value, s)?,
                "call" => self.execute(i.word, s)?,
                "local" => self.push(locals[i.value as usize], s)?,
                "local-set" => locals[i.value as usize] = self.pop(1, s)?[0],
                "locals" => {
                    let a = self.pop(i.slots.len(), s)?;
                    for (&slot, v) in i.slots.iter().zip(a) {
                        locals[slot] = v;
                    }
                }
                "value-set" => {
                    let v = self.pop(1, s)?[0];
                    self.memory[self.words[i.word].address / 8] = v;
                }
                "defer-set" => {
                    let v = self.pop(1, s)?[0];
                    self.words[i.word].deferred = Some(self.token_word(v, s)?);
                }
                "jump" => pc = i.target,
                "zero" => {
                    if self.pop(1, s)?[0] == 0 {
                        pc = i.target;
                    }
                }
                "exit" => break,
                "does" => {
                    let latest = self
                        .users
                        .last()
                        .copied()
                        .ok_or_else(|| fault(s, "no CREATE word", Some(-31)))?;
                    if self.words[latest].kind != "create" {
                        return Err(fault(s, "no CREATE word", Some(-31)));
                    }
                    self.words[latest].does = Some((definition, pc));
                    break;
                }
                "abort-string" => {
                    if self.pop(1, s)?[0] != 0 {
                        return Err(fault(s, i.text.clone(), Some(-2)));
                    }
                }
                "write" => self.pending.push_str(&i.text),
                "do" | "?do" => {
                    let a = self.pop(2, s)?;
                    if i.op == "?do" && a[0] == a[1] {
                        pc = i.target;
                    } else {
                        self.return_push(a[0], s)?;
                        self.return_push(a[1], s)?;
                    }
                }
                "loop" | "+loop" => {
                    let step = if i.op == "loop" {
                        1
                    } else {
                        self.pop(1, s)?[0]
                    };
                    self.return_need(2, s)?;
                    let p = self.returns.len() - 1;
                    let index = self.returns[p];
                    let limit = self.returns[p - 1];
                    let next = index + step;
                    if (index - limit < 0) != (next - limit < 0) {
                        self.returns.truncate(p - 1);
                    } else {
                        self.returns[p] = next;
                        pc = i.target;
                    }
                }
                "leave" => {
                    self.return_need(2, s)?;
                    self.returns.truncate(self.returns.len() - 2);
                    pc = i.target;
                }
                "of" => {
                    let a = self.pop(2, s)?;
                    if a[0] != a[1] {
                        self.push(a[0], s)?;
                        pc = i.target;
                    }
                }
                "endcase" => {
                    self.pop(1, s)?;
                }
                ">R" => {
                    let v = self.pop(1, s)?[0];
                    self.return_push(v, s)?;
                }
                "R>" => {
                    self.return_need(1, s)?;
                    let v = self.returns.pop().unwrap();
                    self.push(v, s)?;
                }
                "R@" | "I" => {
                    self.return_need(1, s)?;
                    self.push(*self.returns.last().unwrap(), s)?;
                }
                "J" => {
                    self.return_need(3, s)?;
                    self.push(self.returns[self.returns.len() - 3], s)?;
                }
                "UNLOOP" => {
                    self.return_need(2, s)?;
                    self.returns.truncate(self.returns.len() - 2);
                }
                _ => unreachable!(),
            }
        }
        if self.returns.len() > old_return {
            self.returns.truncate(old_return);
        }
        self.depth -= 1;
        Ok(())
    }

    fn execute(&mut self, mut i: usize, spelling: &str) -> Running<()> {
        let mut owner = spelling.to_string();
        while self.words[i].kind == "defer" {
            i = self.words[i]
                .deferred
                .ok_or_else(|| fault(&owner, "deferred word not set", Some(-21)))?;
            owner = self.words[i].name.clone();
        }
        let spelling = owner.as_str();
        match self.words[i].kind.as_str() {
            "colon" => self.execute_definition(i, 0, spelling),
            "create" | "variable" => {
                self.push(self.words[i].address as i64, spelling)?;
                if let Some((d, start)) = self.words[i].does {
                    self.execute_definition(d, start, spelling)?;
                }
                Ok(())
            }
            "constant" => self.push(self.words[i].value, spelling),
            "value" => self.push(self.memory[self.words[i].address / 8], spelling),
            _ => {
                let name = self.words[i].name.clone();
                self.builtin(&name, spelling)
            }
        }
    }

    fn builtin(&mut self, name: &str, owner: &str) -> Running<()> {
        match name {
            "+" | "-" | "*" | "/" | "MOD" | "/MOD" | "MIN" | "MAX" | "=" | "<>" | "<" | ">"
            | "AND" | "OR" | "XOR" => {
                let a = self.pop(2, owner)?;
                let (x, y) = (a[0], a[1]);
                if ["/", "MOD", "/MOD"].contains(&name) && y == 0 {
                    return Err(fault(owner, "division by zero", Some(-10)));
                }
                let v = match name {
                    "+" => x + y,
                    "-" => x - y,
                    "*" => x * y,
                    "/" | "/MOD" => Self::quotient(x, y),
                    "MOD" => x - y * Self::quotient(x, y),
                    "MIN" => x.min(y),
                    "MAX" => x.max(y),
                    "=" => -i64::from(x == y),
                    "<>" => -i64::from(x != y),
                    "<" => -i64::from(x < y),
                    ">" => -i64::from(x > y),
                    "AND" => x & y,
                    "OR" => x | y,
                    _ => x ^ y,
                };
                if name == "/MOD" {
                    self.push(x - y * v, owner)?;
                }
                self.push(v, owner)?;
            }
            "*/" | "*/MOD" => {
                let a = self.pop(3, owner)?;
                if a[2] == 0 {
                    return Err(fault(owner, "division by zero", Some(-10)));
                }
                let p = a[0] * a[1];
                let q = Self::quotient(p, a[2]);
                if name == "*/MOD" {
                    self.push(p - a[2] * q, owner)?;
                }
                self.push(q, owner)?;
            }
            "NEGATE" | "ABS" | "1+" | "1-" | "2*" | "2/" | "0=" | "0<>" | "0<" | "0>"
            | "INVERT" | "CELLS" | "CELL+" => {
                let a = self.pop(1, owner)?[0];
                let v = match name {
                    "NEGATE" => -a,
                    "ABS" => a.abs(),
                    "1+" => a + 1,
                    "1-" => a - 1,
                    "2*" => 2 * a,
                    "2/" => Self::quotient(a, 2),
                    "0=" => -i64::from(a == 0),
                    "0<>" => -i64::from(a != 0),
                    "0<" => -i64::from(a < 0),
                    "0>" => -i64::from(a > 0),
                    "INVERT" => !a,
                    "CELLS" => 8 * a,
                    _ => a + 8,
                };
                self.push(v, owner)?;
            }
            "WITHIN" => {
                let a = self.pop(3, owner)?;
                self.push(-i64::from(a[1] <= a[0] && a[0] < a[2]), owner)?;
            }
            "TRUE" => self.push(-1, owner)?,
            "FALSE" | "BASE" => self.push(0, owner)?,
            "BL" => self.push(32, owner)?,
            "DEPTH" => self.push(self.data.len() as i64, owner)?,
            "HERE" => self.push(self.memory.len() as i64 * 8, owner)?,
            "DUP" | "?DUP" | "DROP" | "SWAP" | "OVER" | "ROT" | "-ROT" | "NIP" | "TUCK"
            | "2DUP" | "2DROP" | "2SWAP" | "2OVER" => {
                let count = match name {
                    "DUP" | "?DUP" | "DROP" => 1,
                    "ROT" | "-ROT" => 3,
                    "2SWAP" | "2OVER" => 4,
                    _ => 2,
                };
                let a = self.pop(count, owner)?;
                let values = match name {
                    "DUP" => vec![a[0], a[0]],
                    "?DUP" => {
                        if a[0] == 0 {
                            a.clone()
                        } else {
                            vec![a[0], a[0]]
                        }
                    }
                    "DROP" | "2DROP" => Vec::new(),
                    "SWAP" => vec![a[1], a[0]],
                    "OVER" => vec![a[0], a[1], a[0]],
                    "ROT" => vec![a[1], a[2], a[0]],
                    "-ROT" => vec![a[2], a[0], a[1]],
                    "NIP" => vec![a[1]],
                    "TUCK" => vec![a[1], a[0], a[1]],
                    "2DUP" => vec![a[0], a[1], a[0], a[1]],
                    "2SWAP" => vec![a[2], a[3], a[0], a[1]],
                    _ => vec![a[0], a[1], a[2], a[3], a[0], a[1]],
                };
                self.push_all(&values, owner)?;
            }
            "PICK" | "ROLL" => {
                let u = self.pop(1, owner)?[0];
                if u < 0 {
                    return Err(fault(owner, "invalid argument", Some(-24)));
                }
                if u >= self.data.len() as i64 {
                    return Err(fault(owner, "stack underflow", Some(-4)));
                }
                let i = self.data.len() - 1 - u as usize;
                let v = if name == "ROLL" {
                    self.data.remove(i)
                } else {
                    self.data[i]
                };
                self.push(v, owner)?;
            }
            "." => {
                let n = self.pop(1, owner)?[0];
                let s = Self::format(n, self.radix(owner)?);
                self.pending.push_str(&s);
                self.pending.push(' ');
            }
            ".R" => {
                let a = self.pop(2, owner)?;
                let s = Self::format(a[0], self.radix(owner)?);
                if a[1] > s.len() as i64 {
                    self.pending.push_str(&" ".repeat(a[1] as usize - s.len()));
                }
                self.pending.push_str(&s);
            }
            ".S" => {
                let b = self.radix(owner)?;
                self.pending
                    .push_str(&format!("<{}> ", Self::format(self.data.len() as i64, b)));
                for &n in &self.data {
                    self.pending.push_str(&Self::format(n, b));
                    self.pending.push(' ');
                }
            }
            "?" => {
                let n = self.pop(1, owner)?[0];
                let i = self.address(n, owner)?;
                let s = Self::format(self.memory[i], self.radix(owner)?);
                self.pending.push_str(&s);
                self.pending.push(' ');
            }
            "CR" => self.flush(),
            "EMIT" => {
                let c = self.pop(1, owner)?[0];
                if !(32..=126).contains(&c) {
                    return Err(fault(owner, "invalid argument", Some(-24)));
                }
                self.pending.push(c as u8 as char);
            }
            "SPACE" => self.pending.push(' '),
            "SPACES" => {
                let n = self.pop(1, owner)?[0];
                if n > 0 {
                    self.pending.push_str(&" ".repeat(n as usize));
                }
            }
            "!" | "+!" => {
                let a = self.pop(2, owner)?;
                let i = self.address(a[1], owner)?;
                self.memory[i] = if name == "!" {
                    a[0]
                } else {
                    self.memory[i] + a[0]
                };
            }
            "@" => {
                let n = self.pop(1, owner)?[0];
                let i = self.address(n, owner)?;
                self.push(self.memory[i], owner)?;
            }
            "," => {
                let v = self.pop(1, owner)?[0];
                self.memory.push(v);
            }
            "ALLOT" => {
                let n = self.pop(1, owner)?[0];
                if n < 0 || n % 8 != 0 {
                    return Err(fault(owner, "invalid argument", Some(-24)));
                }
                self.memory.resize(self.memory.len() + (n / 8) as usize, 0);
            }
            "HEX" => self.memory[0] = 16,
            "DECIMAL" => self.memory[0] = 10,
            "CREATE" | "VARIABLE" | "CONSTANT" | "VALUE" | "DEFER" => {
                let raw = self.read_name(owner)?;
                self.check_name(&raw)?;
                let value = if name == "CONSTANT" || name == "VALUE" {
                    self.pop(1, owner)?[0]
                } else {
                    0
                };
                let mut w = Word::new(
                    &raw.to_ascii_uppercase(),
                    &raw,
                    &name.to_ascii_lowercase(),
                    self.memory.len() * 8,
                );
                w.address = self.memory.len() * 8;
                w.value = value;
                let i = self.words.len();
                self.words.push(w);
                self.users.push(i);
                if name == "VARIABLE" || name == "VALUE" {
                    self.memory.push(value);
                }
            }
            "'" => {
                let raw = self.read_name(owner)?;
                let w = self
                    .find(&raw)
                    .ok_or_else(|| fault(&raw, "undefined word", Some(-13)))?;
                let xt = self.token(w);
                self.push(xt, owner)?;
            }
            "EXECUTE" => {
                let xt = self.pop(1, owner)?[0];
                let w = self.token_word(xt, owner)?;
                let n = self.words[w].name.clone();
                self.execute(w, &n)?;
            }
            "CATCH" => {
                let xt = self.pop(1, owner)?[0];
                let w = self.token_word(xt, owner)?;
                let saved = self.data.clone();
                let size = self.returns.len();
                let level = self.depth;
                let n = self.words[w].name.clone();
                let code = match self.execute(w, &n) {
                    Ok(()) => 0,
                    Err(e) => {
                        let Some(code) = e.code else {
                            return Err(e);
                        };
                        self.data = saved;
                        if self.returns.len() > size {
                            self.returns.truncate(size);
                        }
                        self.depth = level;
                        code
                    }
                };
                self.push(code, owner)?;
            }
            "THROW" => {
                let n = self.pop(1, owner)?[0];
                if n != 0 {
                    return Err(fault(owner, format!("exception {}", n), Some(n)));
                }
            }
            "ABORT" => return Err(fault(owner, "aborted", Some(-1))),
            "WORDS" => {
                for &w in self.users.iter().rev() {
                    self.pending.push_str(&self.words[w].name);
                    self.pending.push(' ');
                }
            }
            _ => unreachable!(),
        }
        Ok(())
    }

    fn string(&mut self, owner: &str) -> Running<String> {
        if self.at == self.line.len() {
            return Err(fault(owner, "unterminated string", None));
        }
        let start = self.at + 1;
        let offset = self.line[start..]
            .find('"')
            .ok_or_else(|| fault(owner, "unterminated string", None))?;
        self.at = start + offset + 1;
        Ok(self.line[start..start + offset].into())
    }

    fn target(&self, raw: &str, kind: &str) -> Running<usize> {
        let w = self
            .find(raw)
            .ok_or_else(|| fault(raw, "undefined word", Some(-13)))?;
        if self.words[w].kind != kind {
            Err(fault(
                raw,
                if kind == "value" {
                    "not a value"
                } else {
                    "not deferred"
                },
                None,
            ))
        } else {
            Ok(w)
        }
    }

    fn process(&mut self, raw: &str) -> Running<()> {
        let name = raw.to_ascii_uppercase();
        if name == "\\" {
            self.at = self.line.len();
            return Ok(());
        }
        if name == "(" {
            let end = self.line[self.at..]
                .find(')')
                .ok_or_else(|| fault(raw, "unterminated comment", None))?;
            self.at += end + 1;
            return Ok(());
        }
        if self.compiler.is_none() && compile_only(&name) {
            return Err(fault(raw, "compile only", None));
        }
        if self.compiler.is_some() && interpret_only(&name) {
            return Err(fault(raw, "interpret only", None));
        }
        if name == ".\"" || name == "ABORT\"" {
            let text = self.string(raw)?;
            if let Some(c) = &self.compiler {
                let mut i = Instruction::new(
                    if name == ".\"" {
                        "write"
                    } else {
                        "abort-string"
                    },
                    raw,
                );
                i.text = text;
                self.words[c.word].code.push(i);
            } else {
                self.pending.push_str(&text);
            }
            return Ok(());
        }
        if name == "TO" || name == "IS" {
            let n = self.read_name(raw)?;
            let upper = n.to_ascii_uppercase();
            if name == "TO" {
                if let Some(c) = &self.compiler {
                    if let Some(&slot) = c.locals.get(&upper) {
                        let mut i = Instruction::new("local-set", raw);
                        i.value = slot as i64;
                        self.words[c.word].code.push(i);
                        return Ok(());
                    }
                }
            }
            let w = self.target(&n, if name == "TO" { "value" } else { "defer" })?;
            if let Some(c) = &self.compiler {
                let mut i = Instruction::new(
                    if name == "TO" {
                        "value-set"
                    } else {
                        "defer-set"
                    },
                    raw,
                );
                i.word = w;
                self.words[c.word].code.push(i);
            } else {
                let v = self.pop(1, raw)?[0];
                if name == "TO" {
                    self.memory[self.words[w].address / 8] = v;
                } else {
                    self.words[w].deferred = Some(self.token_word(v, raw)?);
                }
            }
            return Ok(());
        }
        if name == ":" || name == ":NONAME" {
            let n = if name == ":" {
                let n = self.read_name(raw)?;
                self.check_name(&n)?;
                n
            } else {
                raw.into()
            };
            let i = self.words.len();
            let upper = if name == ":" {
                n.to_ascii_uppercase()
            } else {
                ":NONAME".into()
            };
            self.words
                .push(Word::new(&upper, &n, "colon", self.memory.len() * 8));
            self.compiler = Some(Compiler {
                word: i,
                anonymous: name == ":NONAME",
                locals: BTreeMap::new(),
                control: Vec::new(),
            });
            return Ok(());
        }
        if name == "FORGET" {
            let n = self.read_name(raw)?;
            let upper = n.to_ascii_uppercase();
            let i = self
                .users
                .iter()
                .rposition(|&w| self.words[w].name == upper)
                .ok_or_else(|| fault(&n, "undefined word", Some(-13)))?;
            let here = self.words[self.users[i]].here / 8;
            self.users.truncate(i);
            self.memory.truncate(here);
            return Ok(());
        }
        if let Some(mut c) = self.compiler.take() {
            let keep = self.compile(raw, &name, &mut c)?;
            if keep {
                self.compiler = Some(c);
            }
            return Ok(());
        }
        if let Some(w) = self.find(raw) {
            self.execute(w, raw)
        } else {
            let n = self
                .number(raw, raw, self.memory[0])?
                .ok_or_else(|| fault(raw, "undefined word", Some(-13)))?;
            self.push(n, raw)
        }
    }

    fn instruction(
        &mut self,
        c: &Compiler,
        op: &str,
        raw: &str,
        value: i64,
        target: usize,
    ) -> usize {
        let code = &mut self.words[c.word].code;
        let mut i = Instruction::new(op, raw);
        i.value = value;
        i.target = target;
        code.push(i);
        code.len() - 1
    }

    fn top(c: &Compiler, kinds: &[&str], raw: &str) -> Running<()> {
        if c.control
            .last()
            .is_some_and(|t| kinds.contains(&t.kind.as_str()))
        {
            Ok(())
        } else {
            Err(fault(raw, "control structure mismatch", None))
        }
    }

    fn compile(&mut self, raw: &str, name: &str, c: &mut Compiler) -> Running<bool> {
        match name {
            ";" => {
                if let Some(t) = c.control.last() {
                    let kind = match t.kind.as_str() {
                        "ELSE" => "IF",
                        "WHILE" => "BEGIN",
                        k => k,
                    };
                    return Err(fault(raw, format!("unclosed {}", kind), None));
                }
                if c.anonymous {
                    let xt = self.token(c.word);
                    self.push(xt, raw)?;
                } else {
                    self.users.push(c.word);
                }
                return Ok(false);
            }
            "IF" => {
                let i = self.instruction(c, "zero", raw, 0, 0);
                c.control.push(Control::new("IF", i, 0));
            }
            "ELSE" => {
                Self::top(c, &["IF"], raw)?;
                let t = c.control.pop().unwrap();
                let i = self.instruction(c, "jump", raw, 0, 0);
                self.words[c.word].code[t.index].target = i + 1;
                c.control.push(Control::new("ELSE", i, 0));
            }
            "THEN" => {
                Self::top(c, &["IF", "ELSE"], raw)?;
                let t = c.control.pop().unwrap();
                let end = self.words[c.word].code.len();
                self.words[c.word].code[t.index].target = end;
            }
            "BEGIN" => c
                .control
                .push(Control::new("BEGIN", self.words[c.word].code.len(), 0)),
            "UNTIL" | "AGAIN" => {
                Self::top(c, &["BEGIN"], raw)?;
                let t = c.control.pop().unwrap();
                self.instruction(
                    c,
                    if name == "UNTIL" { "zero" } else { "jump" },
                    raw,
                    0,
                    t.index,
                );
            }
            "WHILE" => {
                Self::top(c, &["BEGIN"], raw)?;
                let t = c.control.pop().unwrap();
                let i = self.instruction(c, "zero", raw, 0, 0);
                c.control.push(Control::new("WHILE", i, t.index));
            }
            "REPEAT" => {
                Self::top(c, &["WHILE"], raw)?;
                let t = c.control.pop().unwrap();
                self.instruction(c, "jump", raw, 0, t.begin);
                let end = self.words[c.word].code.len();
                self.words[c.word].code[t.index].target = end;
            }
            "DO" | "?DO" => {
                let i = self.instruction(c, if name == "DO" { "do" } else { "?do" }, raw, 0, 0);
                c.control.push(Control::new(name, i, 0));
            }
            "LOOP" | "+LOOP" => {
                Self::top(c, &["DO", "?DO"], raw)?;
                let t = c.control.pop().unwrap();
                self.instruction(
                    c,
                    if name == "LOOP" { "loop" } else { "+loop" },
                    raw,
                    0,
                    t.index + 1,
                );
                let end = self.words[c.word].code.len();
                self.words[c.word].code[t.index].target = end;
                for i in t.leaves {
                    self.words[c.word].code[i].target = end;
                }
            }
            "LEAVE" => {
                let p = c
                    .control
                    .iter()
                    .rposition(|t| t.kind == "DO" || t.kind == "?DO")
                    .ok_or_else(|| fault(raw, "control structure mismatch", None))?;
                let i = self.instruction(c, "leave", raw, 0, 0);
                c.control[p].leaves.push(i);
            }
            "CASE" => c
                .control
                .push(Control::new("CASE", self.words[c.word].code.len(), 0)),
            "OF" => {
                Self::top(c, &["CASE"], raw)?;
                let i = self.instruction(c, "of", raw, 0, 0);
                c.control.push(Control::new("OF", i, 0));
            }
            "ENDOF" => {
                Self::top(c, &["OF"], raw)?;
                let t = c.control.pop().unwrap();
                let i = self.instruction(c, "jump", raw, 0, 0);
                self.words[c.word].code[t.index].target = i + 1;
                c.control.last_mut().unwrap().ends.push(i);
            }
            "ENDCASE" => {
                Self::top(c, &["CASE"], raw)?;
                let t = c.control.pop().unwrap();
                self.instruction(c, "endcase", raw, 0, 0);
                let end = self.words[c.word].code.len();
                for i in t.ends {
                    self.words[c.word].code[i].target = end;
                }
            }
            "EXIT" => {
                self.instruction(c, "exit", raw, 0, 0);
            }
            "DOES>" => {
                if !c.control.is_empty() {
                    return Err(fault(raw, "control structure mismatch", None));
                }
                self.instruction(c, "does", raw, 0, 0);
            }
            "RECURSE" => {
                let mut i = Instruction::new("call", raw);
                i.word = c.word;
                self.words[c.word].code.push(i);
            }
            "[']" => {
                let n = self.read_name(raw)?;
                let word = self
                    .find(&n)
                    .ok_or_else(|| fault(&n, "undefined word", Some(-13)))?;
                let xt = self.token(word);
                self.instruction(c, "literal", raw, xt, 0);
            }
            "{:" => {
                let mut names = Vec::new();
                let mut closed = false;
                while let Some(n) = self.read_word() {
                    if n.to_ascii_uppercase() == ":}" {
                        closed = true;
                        break;
                    }
                    names.push(n);
                }
                if !closed {
                    return Err(fault(raw, "unterminated locals", None));
                }
                let mut i = Instruction::new("locals", raw);
                for n in names.iter().take_while(|n| n.as_str() != "--") {
                    self.check_name(n)?;
                    let slot = self.words[c.word].locals;
                    self.words[c.word].locals += 1;
                    c.locals.insert(n.to_ascii_uppercase(), slot);
                    i.slots.push(slot);
                }
                self.words[c.word].code.push(i);
            }
            ">R" | "R>" | "R@" | "I" | "J" | "UNLOOP" => {
                self.instruction(c, name, raw, 0, 0);
            }
            _ => {
                if let Some(&slot) = c.locals.get(name) {
                    self.instruction(c, "local", raw, slot as i64, 0);
                } else if let Some(word) = self.find(raw) {
                    let mut i = Instruction::new("call", raw);
                    i.word = word;
                    self.words[c.word].code.push(i);
                } else {
                    let n = self
                        .number(raw, raw, self.memory[0])?
                        .ok_or_else(|| fault(raw, "undefined word", Some(-13)))?;
                    self.instruction(c, "literal", raw, n, 0);
                }
            }
        }
        Ok(true)
    }

    fn input(&mut self, text: &str) {
        self.line = text.into();
        self.at = 0;
        while let Some(word) = self.read_word() {
            if let Err(e) = self.process(&word) {
                if !self.pending.is_empty() {
                    self.flush();
                }
                self.output.push(format!("ERROR {}: {}", e.word, e.reason));
                self.data.clear();
                self.returns.clear();
                self.compiler = None;
                self.depth = 0;
                break;
            }
        }
        if !self.pending.is_empty() {
            self.flush();
        }
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut f = Forth::new();
    for line in input.lines() {
        if line == "BYE" {
            if let Some(c) = &f.compiler {
                f.output.push(format!(
                    "ERROR {}: unterminated definition",
                    f.words[c.word].original
                ));
            }
            break;
        }
        f.input(line);
    }
    for line in f.output {
        println!("{}", line);
    }
}
