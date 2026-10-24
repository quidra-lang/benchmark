use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::io::{self, Read};
use std::rc::Rc;

#[derive(Clone)]
struct Token {
    text: String,
    kind: &'static str,
    line: usize
}

struct Problem {
    line: usize,
    reason: String
}

fn problem(t: &Token, reason: impl Into<String>) -> Problem {
    Problem {
        line: t.line,
        reason: reason.into()
    }
}

fn canonical(s: &str) -> &str {
    match s {
        "FORWARD" => "FD",
        "BACK" => "BK",
        "RIGHT" => "RT",
        "LEFT" => "LT",
        "SETHEADING" => "SETH",
        "PENUP" => "PU",
        "PENDOWN" => "PD",
        "PENERASE" => "PE",
        "CLEARSCREEN" => "CS",
        "IFT" => "IFTRUE",
        "IFF" => "IFFALSE",
        "OP" => "OUTPUT",
        "PR" => "PRINT",
        _ => s
    }
}

fn signature(s: &str) -> Option<&'static str> {
    match canonical(s) {
        "FD" | "BK" | "RT" | "LT" | "SETH" | "SETPEN" | "SETX" | "SETY" | "TEST" | "OUTPUT" | "SEED" => Some("E"),
        "PU" | "PD" | "PE" | "HOME" | "CS" | "CLEAN" | "FILL" | "SNAPSHOT" | "STOP" => Some(""),
        "SETXY" => Some("EE"),
        "LABEL" | "PRINT" => Some("P"),
        "REPEAT" | "WHILE" | "IF" => Some("EL"),
        "IFELSE" => Some("ELL"),
        "FOR" => Some("QEEL"),
        "IFTRUE" | "IFFALSE" => Some("L"),
        "MAKE" | "LOCALMAKE" => Some("QE"),
        "LOCAL" | "TRACE" | "UNTRACE" => Some("Q"),
        _ => None
    }
}

fn inputs(s: &str) -> Option<usize> {
    match s {
        "XCOR" | "YCOR" | "HEADING" | "REPCOUNT" => Some(0),
        "RANDOM" | "ABS" | "NOT" => Some(1),
        "AND" | "OR" | "MAX" | "MIN" => Some(2),
        _ => None
    }
}

fn primitive(s: &str) -> bool {
    signature(s).is_some() || inputs(s).is_some() || ["TO", "END", "MOD"].contains(&s)
}

fn name(s: &str) -> bool {
    !s.is_empty() && s.as_bytes()[0].is_ascii_uppercase() && s.bytes().all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || c == b'_')
}

fn lex(text: &str, line: usize) -> Result<Vec<Token>, Problem> {
    let s = text.split(';').next().unwrap().to_ascii_uppercase();
    let b = s.as_bytes();
    let mut i = 0;
    let mut out = Vec::new();
    while i < b.len() {
        let c = b[i];
        if c == b' ' {
            i += 1;
            continue;
        }
        if b"[]()+-*/=<>".contains(&c) {
            let start = i;
            let kind = if c == b'-' && (i == 0 || b" [(".contains(&b[i - 1])) && i + 1 < b.len() && b[i + 1] != b' ' {
                "sign"
            } else {
                "symbol"
            };
            if (c == b'<' && i + 1 < b.len() && b"=>".contains(&b[i + 1])) || (c == b'>' && i + 1 < b.len() && b[i + 1] == b'=') {
                i += 1;
            }
            i += 1;
            out.push(Token {
                text: s[start..i].into(),
                kind,
                line
            });
            continue;
        }
        let start = i;
        while i < b.len() && !b" []()+-*/=<>".contains(&b[i]) {
            i += 1;
        }
        let word = &s[start..i];
        let kind = if word.bytes().all(|c| c.is_ascii_digit()) {
            "number"
        } else if word.starts_with(':') && name(&word[1..]) {
            "variable"
        } else if word.starts_with('"') && name(&word[1..]) {
            "quote"
        } else if name(word) {
            "word"
        } else {
            return Err(Problem {
                line, reason: format!("bad token '{}'", word)
            });
        };
        out.push(Token {
            text: word.into(),
            kind,
            line
        });
    }
    Ok(out)
}

#[derive(Clone)]
struct Expr {
    token: Token,
    op: String,
    args: Vec<Expr>
}

#[derive(Clone)]
enum Item {
    Word(String), Expression(Expr)
}

#[derive(Clone)]
struct Command {
    token: Token,
    op: String,
    exprs: Vec<Expr>,
    words: Vec<String>,
    lists: Vec<Vec<Command>>,
    items: Vec<Item>
}

struct Procedure {
    token: Token,
    params: Vec<String>,
    raw: Vec<Token>,
    body: Rc<Vec<Command>>
}

struct Parser<'a> {
    tokens: &'a [Token],
    procedures: &'a BTreeMap<String, Procedure>,
    inside: bool,
    at: usize
}

impl Parser<'_> {

    fn unknown(&self, t: &Token) -> bool {
        t.kind == "word" && !primitive(&t.text) && !self.procedures.contains_key(&t.text)
    }

    fn next(&self, owner: &Token) -> Result<Token, Problem> {
        let t = self.tokens.get(self.at).ok_or_else(|| problem(owner, format!("not enough inputs to {}", owner.text)))?;
        if t.text == "]" || t.text == ")" {
            return Err(problem(owner, format!("not enough inputs to {}", owner.text)));
        }
        if self.unknown(t) {
            return Err(problem(t, format!("I don't know how to {}", t.text)));
        }
        Ok(t.clone())
    }

    fn rejected(owner: &Token, t: &Token) -> Problem {
        problem(t, format!("{} doesn't like {} as input", owner.text, t.text))
    }

    fn expression(&mut self, owner: &Token) -> Result<Expr, Problem> {
        self.binary(owner, 0)
    }

    fn binary(&mut self, owner: &Token, level: usize) -> Result<Expr, Problem> {
        if level == 3 {
            return self.term(owner);
        }
        let operators: &[&str] = match level {
            0 => &["=", "<>", "<", ">", "<=", ">="],
            1 => &["+", "-"],
            _ => &["*", "/", "MOD"]
        };
        let mut left = self.binary(owner, level + 1)?;
        while self.at < self.tokens.len() && operators.contains(&self.tokens[self.at].text.as_str()) && self.tokens[self.at].kind != "sign" {
            let t = self.tokens[self.at].clone();
            self.at += 1;
            let right = self.binary(&t, level + 1)?;
            left = Expr {
                op: t.text.clone(),
                token: t,
                args: vec![left, right]
            };
        }
        Ok(left)
    }

    fn expressions(&mut self, owner: &Token, count: usize) -> Result<Vec<Expr>, Problem> {
        (0..count).map(|_| self.expression(owner)).collect()
    }

    fn term(&mut self, owner: &Token) -> Result<Expr, Problem> {
        let t = self.next(owner)?;
        self.at += 1;
        let (op, args) = if t.kind == "number" {
            ("NUMBER", Vec::new())
        } else if t.kind == "variable" {
            ("VARIABLE", Vec::new())
        } else if t.text == "-" {
            ("NEG", vec![self.term(&t)?])
        } else if t.text == "(" {
            let e = self.expression(&t)?;
            if self.tokens.get(self.at).map(|t| t.text.as_str()) != Some(")") {
                return Err(problem(&t, "missing )"));
            }
            self.at += 1;
            return Ok(e);
        } else if t.kind == "word" && inputs(&t.text).is_some() {
            ("FUNCTION", self.expressions(&t, inputs(&t.text).unwrap())?)
        } else if t.kind == "word" && self.procedures.contains_key(&t.text) {
            ("CALL", self.expressions(&t, self.procedures[&t.text].params.len())?)
        } else {
            return Err(Self::rejected(owner, &t));
        };
        Ok(Expr {
            token: t,
            op: op.into(),
            args
        })
    }

    fn item(&mut self, owner: &Token) -> Result<Item, Problem> {
        let t = self.next(owner)?;
        if t.kind == "quote" {
            self.at += 1;
            Ok(Item::Word(t.text[1..].into()))
        } else {
            Ok(Item::Expression(self.expression(owner)?))
        }
    }

    fn list(&mut self, owner: &Token) -> Result<Vec<Command>, Problem> {
        let open = self.next(owner)?;
        if open.text != "[" {
            return Err(Self::rejected(owner, &open));
        }
        self.at += 1;
        let mut out = Vec::new();
        while self.at < self.tokens.len() && self.tokens[self.at].text != "]" {
            out.push(self.command()?);
        }
        if self.at == self.tokens.len() {
            return Err(problem(&open, "missing ]"));
        }
        self.at += 1;
        Ok(out)
    }

    fn command(&mut self) -> Result<Command, Problem> {
        let t = self.tokens[self.at].clone();
        self.at += 1;
        if t.text == "]" {
            return Err(problem(&t, "unexpected ]"));
        }
        let mut result = Command {
            token: t.clone(),
            op: String::new(),
            exprs: Vec::new(),
            words: Vec::new(),
            lists: Vec::new(),
            items: Vec::new()
        };
        if t.text == "(" && self.tokens.get(self.at).is_some_and(|t| t.kind == "word" && canonical(&t.text) == "PRINT") {
            let owner = self.tokens[self.at].clone();
            self.at += 1;
            while self.tokens.get(self.at).map(|t| t.text.as_str()) != Some(")") {
                if self.at == self.tokens.len() || self.tokens[self.at].text == "]" {
                    return Err(problem(&t, "missing )"));
                }
                result.items.push(self.item(&owner)?);
            }
            self.at += 1;
            result.op = "MULTIPRINT".into();
            return Ok(result);
        }
        if t.kind == "word" && ["TO", "END"].contains(&t.text.as_str()) {
            return Err(problem(&t, format!("misplaced {}", t.text)));
        }
        if t.kind == "word" {
            if let Some(sig) = signature(&t.text) {
                let op = canonical(&t.text);
                if !self.inside && ["STOP", "OUTPUT", "LOCAL", "LOCALMAKE"].contains(&op) {
                    return Err(problem(&t, format!("can only use {} inside a procedure", t.text)));
                }
                for kind in sig.chars() {
                    match kind {
                        'E' => result.exprs.push(self.expression(&t)?),
                        'L' => result.lists.push(self.list(&t)?),
                        'P' => result.items.push(self.item(&t)?),
                        'Q' => {
                            let q = self.next(&t)?;
                            if q.kind != "quote" {
                                return Err(Self::rejected(&t, &q));
                            }
                            self.at += 1;
                            if ["TRACE", "UNTRACE"].contains(&op) && !self.procedures.contains_key(&q.text[1..]) {
                                return Err(problem(&q, format!("I don't know how to {}", &q.text[1..])));
                            }
                            result.words.push(q.text[1..].into());
                        },
                        _ => unreachable!()
                    }
                }
                result.op = op.into();
                return Ok(result);
            }
            if let Some(p) = self.procedures.get(&t.text) {
                result.exprs = self.expressions(&t, p.params.len())?;
                result.op = "CALL".into();
                return Ok(result);
            }
        }
        if self.unknown(&t) {
            return Err(problem(&t, format!("I don't know how to {}", t.text)));
        }
        Err(problem(&t, format!("you don't say what to do with {}", t.text)))
    }

    fn sequence(&mut self) -> Result<Vec<Command>, Problem> {
        let mut out = Vec::new();
        while self.at < self.tokens.len() {
            out.push(self.command()?);
        }
        Ok(out)
    }
}

struct Environment {
    values: BTreeMap<String, i64>,
    test: Option<bool>
}

enum Signal {
    Failure(Problem), Stop, Output(i64)
}
type Running<T> = Result<T, Signal>;

fn runtime_error(t: &Token, reason: impl Into<String>) -> Signal {
    Signal::Failure(problem(t, reason))
}

struct Runtime<'a> {
    procedures: &'a BTreeMap<String, Procedure>,
    output: Vec<String>,
    x: i64,
    y: i64,
    heading: i64,
    pen: &'static str,
    character: char,
    random: i64,
    canvas: BTreeMap<(i64, i64), char>,
    envs: Vec<Environment>,
    calls: Vec<String>,
    repetitions: Vec<i64>,
    traced: BTreeSet<String>
}

impl Runtime<'_> {

    fn variable(&self, t: &Token) -> Running<i64> {
        for env in self.envs.iter().rev() {
            if let Some(&v) = env.values.get(&t.text[1..]) {
                return Ok(v);
            }
        }
        Err(runtime_error(t, format!("{} has no value", &t.text[1..])))
    }

    fn make(&mut self, name: &str, value: i64) {
        for i in (1..self.envs.len()).rev() {
            if self.envs[i].values.contains_key(name) {
                self.envs[i].values.insert(name.into(), value);
                return;
            }
        }
        self.envs[0].values.insert(name.into(), value);
    }

    fn invoke(&mut self, t: &Token, values: &[i64]) -> Running<Option<i64>> {
        if self.calls.len() == 100 {
            return Err(runtime_error(t, "recursion too deep"));
        }
        let p = &self.procedures[&t.text];
        let trace = self.traced.contains(&t.text);
        let indent = "  ".repeat(self.calls.len());
        if trace {
            self.output.push(format!("{}( {}{} )", indent, t.text, values.iter().map(|v| format!(" {}", v)).collect::<String>()));
        }
        let body = p.body.clone();
        self.envs.push(Environment {
            values: p.params.iter().cloned().zip(values.iter().copied()).collect(),
            test: None
        });
        self.calls.push(t.text.clone());
        let value = match self.execute(&body) {
            Ok(()) | Err(Signal::Stop) => None,
            Err(Signal::Output(v)) => Some(v),
            Err(e) => return Err(e)
        };
        self.envs.pop();
        self.calls.pop();
        if trace {
            self.output.push(format!("{}{}{}", indent, t.text, value.map_or(" stops".into(), |v| format!(" outputs {}", v))));
        }
        Ok(value)
    }

    fn evaluate(&mut self, e: &Expr) -> Running<i64> {
        let t = &e.token;
        if e.op == "NUMBER" {
            return Ok(t.text.parse().unwrap());
        }
        if e.op == "VARIABLE" {
            return self.variable(t);
        }
        let mut a = Vec::new();
        for arg in &e.args {
            a.push(self.evaluate(arg)?);
        }
        if e.op == "NEG" {
            return Ok(-a[0]);
        }
        if e.op == "CALL" {
            return self.invoke(t, &a)?.ok_or_else(|| runtime_error(t, format!("{} did not output", t.text)));
        }
        if e.op == "FUNCTION" {
            return Ok(match t.text.as_str() {
                "XCOR" => self.x,
                "YCOR" => self.y,
                "HEADING" => self.heading,
                "REPCOUNT" => *self.repetitions.last().ok_or_else(|| runtime_error(t, "REPCOUNT outside REPEAT"))?,
                "RANDOM" => {
                    if a[0] <= 0 {
                        return Err(runtime_error(t, format!("RANDOM doesn't like {} as input", a[0])));
                    }
                    self.random = 48271 * self.random % 2147483647;
                    self.random % a[0]
                },
                "ABS" => a[0].abs(),
                "NOT" => i64::from(a[0] == 0),
                "AND" => i64::from(a[0] != 0 && a[1] != 0),
                "OR" => i64::from(a[0] != 0 || a[1] != 0),
                "MAX" => a[0].max(a[1]),
                "MIN" => a[0].min(a[1]),
                _ => unreachable!()
            });
        }
        if (e.op == "/" || e.op == "MOD") && a[1] == 0 {
            return Err(runtime_error(t, format!("{} doesn't like 0 as input", t.text)));
        }
        Ok(match e.op.as_str() {
            "+" => a[0] + a[1],
            "-" => a[0] - a[1],
            "*" => a[0] * a[1],
            "/" => a[0] / a[1],
            "MOD" => a[0] % a[1],
            "=" => i64::from(a[0] == a[1]),
            "<>" => i64::from(a[0] != a[1]),
            "<" => i64::from(a[0] < a[1]),
            ">" => i64::from(a[0] > a[1]),
            "<=" => i64::from(a[0] <= a[1]),
            ">=" => i64::from(a[0] >= a[1]),
            _ => unreachable!()
        })
    }

    fn item(&mut self, item: &Item) -> Running<String> {
        match item {
            Item::Word(word) => Ok(word.clone()),
            Item::Expression(e) => Ok(self.evaluate(e)?.to_string())
        }
    }

    fn direction(&self) -> (i64, i64) {
        [(0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1)][(self.heading / 45) as usize]
    }

    fn apply(&mut self, x: i64, y: i64) {
        if self.pen == "DOWN" {
            self.canvas.insert((x, y), self.character);
        } else if self.pen == "ERASE" {
            self.canvas.remove(&(x, y));
        }
    }

    fn move_forward(&mut self, n: i64) {
        let (dx, dy) = self.direction();
        let sign = if n < 0 {
            -1
        } else {
            1
        };
        self.apply(self.x, self.y);
        for _ in 0..n.abs() {
            self.x += sign * dx;
            self.y += sign * dy;
            self.apply(self.x, self.y);
        }
    }

    fn straight(&mut self, x: i64, y: i64) {
        let (dx, dy) = (x - self.x, y - self.y);
        let s = dx.abs().max(dy.abs());
        if s == 0 {
            self.apply(self.x, self.y);
        } else {
            for i in 0..=s {
                self.apply(self.x + (2 * i * dx + s).div_euclid(2 * s), self.y + (2 * i * dy + s).div_euclid(2 * s));
            }
        }
        self.x = x;
        self.y = y;
    }

    fn bounds(&self) -> Option<(i64, i64, i64, i64)> {
        if self.canvas.is_empty() {
            return None;
        }
        Some((self.canvas.keys().map(|p| p.0).min().unwrap(), self.canvas.keys().map(|p| p.1).min().unwrap(), self.canvas.keys().map(|p| p.0).max().unwrap(), self.canvas.keys().map(|p| p.1).max().unwrap()))
    }

    fn fill(&mut self) {
        let Some((x1, y1, x2, y2)) = self.bounds() else {
            return;
        };
        if self.canvas.contains_key(&(self.x, self.y)) || self.x < x1 || self.x > x2 || self.y < y1 || self.y > y2 {
            return;
        }
        let mut queue = VecDeque::from(vec![(self.x, self.y)]);
        self.canvas.insert((self.x, self.y), self.character);
        while let Some((x, y)) = queue.pop_front() {
            for (dx, dy) in [(0, 1), (1, 0), (0, -1), (-1, 0)].iter().copied() {
                let p = (x + dx, y + dy);
                if x1 <= p.0 && p.0 <= x2 && y1 <= p.1 && p.1 <= y2 && !self.canvas.contains_key(&p) {
                    self.canvas.insert(p, self.character);
                    queue.push_back(p);
                }
            }
        }
    }

    fn picture(&mut self) {
        let Some((x1, y1, x2, y2)) = self.bounds() else {
            self.output.push("CANVAS 0 0 0".into());
            return;
        };
        self.output.push(format!("CANVAS {} {} {}", x2 - x1 + 1, y2 - y1 + 1, self.canvas.len()));
        for y in (y1..=y2).rev() {
            let line: String = (x1..=x2).map(|x| self.canvas.get(&(x, y)).copied().unwrap_or(' ')).collect();
            self.output.push(line.trim_end_matches(' ').into());
        }
    }

    fn execute(&mut self, commands: &[Command]) -> Running<()> {
        for c in commands {
            self.command(c)?;
        }
        Ok(())
    }

    fn command(&mut self, c: &Command) -> Running<()> {
        let t = &c.token;
        let op = c.op.as_str();
        if op == "WHILE" {
            while self.evaluate(&c.exprs[0])? != 0 {
                self.execute(&c.lists[0])?;
            }
            return Ok(());
        }
        if op == "PRINT" || op == "MULTIPRINT" {
            let mut values = Vec::new();
            for item in &c.items {
                values.push(self.item(item)?);
            }
            self.output.push(values.join(" "));
            return Ok(());
        }
        if op == "LABEL" {
            let text = self.item(&c.items[0])?;
            let (dx, dy) = self.direction();
            for (i, ch) in text.chars().enumerate() {
                self.canvas.insert((self.x + i as i64 * dx, self.y + i as i64 * dy), ch);
            }
            return Ok(());
        }
        let mut a = Vec::new();
        for e in &c.exprs {
            a.push(self.evaluate(e)?);
        }
        match op {
            "CALL" => if let Some(v) = self.invoke(t, &a)? {
                return Err(runtime_error(t, format!("you don't say what to do with {}", v)));
            },
            "FD" => self.move_forward(a[0]),
            "BK" => self.move_forward(-a[0]),
            "RT" | "LT" | "SETH" => {
                let angle = a[0];
                if angle % 45 != 0 {
                    return Err(runtime_error(t, format!("{} doesn't like {} as input", t.text, angle)));
                }
                self.heading = (if op == "SETH" {
                    angle
                } else {
                    self.heading + if op == "RT" {
                        angle
                    } else {
                        -angle
                    }
                }).rem_euclid(360);
            },
            "PU" => self.pen = "UP",
            "PD" => self.pen = "DOWN",
            "PE" => self.pen = "ERASE",
            "SETPEN" => {
                if !(33..=126).contains(&a[0]) {
                    return Err(runtime_error(t, format!("SETPEN doesn't like {} as input", a[0])));
                }
                self.character = a[0] as u8 as char;
            },
            "SETXY" => self.straight(a[0], a[1]),
            "SETX" => self.straight(a[0], self.y),
            "SETY" => self.straight(self.x, a[0]),
            "HOME" => {
                self.straight(0, 0);
                self.heading = 0;
            },
            "CS" => {
                self.canvas.clear();
                self.x = 0;
                self.y = 0;
                self.heading = 0;
            },
            "CLEAN" => self.canvas.clear(),
            "FILL" => self.fill(),
            "SNAPSHOT" => self.picture(),
            "MAKE" => self.make(&c.words[0], a[0]),
            "LOCAL" => {
                self.envs.last_mut().unwrap().values.insert(c.words[0].clone(), 0);
            },
            "LOCALMAKE" => {
                self.envs.last_mut().unwrap().values.insert(c.words[0].clone(), a[0]);
            },
            "TRACE" => {
                self.traced.insert(c.words[0].clone());
            },
            "UNTRACE" => {
                self.traced.remove(&c.words[0]);
            },
            "SEED" => {
                if a[0] <= 0 {
                    return Err(runtime_error(t, format!("SEED doesn't like {} as input", a[0])));
                }
                self.random = a[0];
            },
            "STOP" => return Err(Signal::Stop),
            "OUTPUT" => return Err(Signal::Output(a[0])),
            "REPEAT" => {
                if c.lists[0].is_empty() {
                    return Ok(());
                }
                for i in 1..=a[0] {
                    self.repetitions.push(i);
                    let result = self.execute(&c.lists[0]);
                    self.repetitions.pop();
                    result?;
                }
            },
            "FOR" => {
                if c.lists[0].is_empty() {
                    self.make(&c.words[0], a[1]);
                    return Ok(());
                }
                let step = if a[0] <= a[1] {
                    1
                } else {
                    -1
                };
                let mut i = a[0];
                loop {
                    self.make(&c.words[0], i);
                    self.execute(&c.lists[0])?;
                    if i == a[1] {
                        break;
                    }
                    i += step;
                }
            },
            "IF" => if a[0] != 0 {
                self.execute(&c.lists[0])?;
            },
            "IFELSE" => self.execute(&c.lists[if a[0] != 0 {
                0
            } else {
                1
            }])?,
            "TEST" => self.envs.last_mut().unwrap().test = Some(a[0] != 0),
            "IFTRUE" | "IFFALSE" => {
                let test = self.envs.last().unwrap().test.ok_or_else(|| runtime_error(t, format!("{} without TEST", t.text)))?;
                if test == (op == "IFTRUE") {
                    self.execute(&c.lists[0])?;
                }
            },
            _ => unreachable!(),
        }
        Ok(())
    }

    fn errors(&mut self) {
        let mut i = self.calls.len();
        while i > 0 {
            let p = &self.calls[i - 1];
            let mut count = 0;
            while i > 0 && self.calls[i - 1] == *p {
                count += 1;
                i -= 1;
            }
            self.output.push(format!("  in {}{}", p, if count == 1 {
                String::new()
            } else {
                format!(" x{}", count)
            }));
        }
    }
}

fn prepare(source: &[(usize, &str)]) -> Result<(BTreeMap<String, Procedure>, Vec<Command>), Problem> {
    let mut procedures: BTreeMap<String, Procedure> = BTreeMap::new();
    let mut order = Vec::new();
    let mut current: Option<String> = None;
    let mut top = Vec::new();
    for &(line, text) in source {
        let tokens = lex(text, line)?;
        if tokens.is_empty() {
            continue;
        }
        let start = &tokens[0];
        if start.kind == "word" && start.text == "TO" {
            if let Some(p) = &current {
                return Err(problem(start, format!("TO inside definition of {}", p)));
            }
            if tokens.len() < 2 || tokens[1].kind != "word" {
                return Err(problem(start, "bad procedure header"));
            }
            let name = &tokens[1];
            if primitive(&name.text) {
                return Err(problem(start, format!("{} is a primitive", name.text)));
            }
            if procedures.contains_key(&name.text) {
                return Err(problem(start, format!("{} is already defined", name.text)));
            }
            let mut params = Vec::new();
            for t in &tokens[2..] {
                if t.kind != "variable" {
                    return Err(problem(start, "bad procedure header"));
                }
                let input = t.text[1..].to_string();
                if params.contains(&input) {
                    return Err(problem(start, format!("duplicate input {}", t.text)));
                }
                params.push(input);
            }
            current = Some(name.text.clone());
            order.push(name.text.clone());
            procedures.insert(name.text.clone(), Procedure {
                token: name.clone(),
                params,
                raw: Vec::new(),
                body: Rc::new(Vec::new())
            });
        } else if tokens.len() == 1 && start.kind == "word" && start.text == "END" {
            if current.is_none() {
                return Err(problem(start, "END without TO"));
            }
            current = None;
        } else if let Some(p) = &current {
            procedures.get_mut(p).unwrap().raw.extend(tokens);
        } else {
            top.extend(tokens);
        }
    }
    if let Some(p) = current {
        return Err(problem(&procedures[&p].token, format!("missing END for {}", p)));
    }
    for p in order {
        let raw = procedures[&p].raw.clone();
        let body = Parser {
            tokens: &raw,
            procedures: &procedures,
            inside: true,
            at: 0
        }.sequence()?;
        procedures.get_mut(&p).unwrap().body = Rc::new(body);
    }
    let body = Parser {
        tokens: &top,
        procedures: &procedures,
        inside: false,
        at: 0
    }.sequence()?;
    Ok((procedures, body))
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let lines: Vec<&str> = input.lines().collect();
    let mut output = Vec::new();
    let mut at = 0;
    while at < lines.len() && lines[at] != "#EOF" {
        output.push(format!("PROGRAM {}", &lines[at][9..]));
        at += 1;
        let mut source = Vec::new();
        while at < lines.len() && lines[at] != "#EOF" && !lines[at].starts_with("#PROGRAM ") {
            source.push((at + 1, lines[at]));
            at += 1;
        }
        match prepare(&source) {
            Err(e) => output.push(format!("ERROR line {}: {}", e.line, e.reason)),
            Ok((procedures, body)) => {
                let mut runtime = Runtime {
                    procedures: &procedures,
                    output: Vec::new(),
                    x: 0,
                    y: 0,
                    heading: 0,
                    pen: "DOWN",
                    character: '*',
                    random: 1,
                    canvas: BTreeMap::new(),
                    envs: vec![Environment {
                        values: BTreeMap::new(),
                        test: None
                    }], calls: Vec::new(), repetitions: Vec::new(), traced: BTreeSet::new()
                };
                match runtime.execute(&body) {
                    Ok(()) => {
                        runtime.output.push(format!("TURTLE {} {} {} {} {}", runtime.x, runtime.y, runtime.heading, runtime.pen, runtime.character));
                        runtime.picture();
                    },
                    Err(Signal::Failure(e)) => {
                        runtime.output.push(format!("ERROR line {}: {}", e.line, e.reason));
                        runtime.errors();
                    },
                    _ => unreachable!()
                }
                output.extend(runtime.output);
            }
        }
    }
    for line in output {
        println!("{}", line);
    }
}
