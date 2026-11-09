use std::collections::{BTreeMap, BTreeSet};
use std::io::{self, Read};
#[derive(Clone, PartialEq, Eq, PartialOrd, Ord)]
enum Value {
    Null,
    Int(i64),
    Text(String),
}
impl Value {
    fn text(&self) -> String {
        match self {
            Self::Null => "NULL".into(),
            Self::Int(n) => n.to_string(),
            Self::Text(s) => s.clone(),
        }
    }
    fn truth(&self) -> Option<bool> {
        match self {
            Self::Int(n) => Some(*n != 0),
            _ => None,
        }
    }
    fn boolean(v: Option<bool>) -> Self {
        v.map_or(Self::Null, |v| Self::Int(v as i64))
    }
    fn ty(&self) -> u8 {
        match self {
            Self::Null => 0,
            Self::Int(_) => 1,
            Self::Text(_) => 2,
        }
    }
}
#[derive(Clone)]
struct Token {
    raw: String,
    text: String,
    kind: u8,
}
fn lex(s: &str) -> Result<Vec<Token>, String> {
    let b = s.as_bytes();
    let mut i = 0;
    let mut out = Vec::new();
    let reserved = "SELECT DISTINCT FROM AS JOIN INNER LEFT OUTER ON WHERE GROUP BY HAVING ORDER ASC DESC LIMIT OFFSET INSERT INTO VALUES UPDATE SET DELETE CREATE TABLE DROP PRIMARY KEY NOT NULL INT TEXT AND OR IS IN BETWEEN LIKE COUNT SUM MIN MAX AVG EXIT";
    while i < b.len() {
        if b[i].is_ascii_whitespace() {
            i += 1;
            continue;
        }
        let start = i;
        let kind;
        if b[i] == b'\'' {
            i += 1;
            while i < b.len() && b[i] != b'\'' {
                i += 1
            }
            i += 1;
            kind = 3
        } else if b[i].is_ascii_digit() {
            i += 1;
            while i < b.len() && b[i].is_ascii_digit() {
                i += 1
            }
            kind = 2
        } else if b[i].is_ascii_alphabetic() || b[i] == b'_' {
            i += 1;
            while i < b.len() && (b[i].is_ascii_alphanumeric() || b[i] == b'_') {
                i += 1
            }
            kind = if reserved
                .split_whitespace()
                .any(|w| w == s[start..i].to_ascii_uppercase())
            {
                1
            } else {
                0
            }
        } else {
            if i + 1 < b.len() && ["<>", "!=", "<=", ">=", "||"].contains(&&s[i..i + 2]) {
                i += 2
            } else if b"(),.;*/%+-=<>".contains(&b[i]) {
                i += 1
            } else {
                return Err(format!("unexpected character '{}'", b[i] as char));
            }
            kind = 4
        }
        let raw = s[start..i].to_string();
        let text = if kind == 1 {
            raw.to_ascii_uppercase()
        } else if kind == 3 {
            raw[1..raw.len() - 1].into()
        } else {
            raw.clone()
        };
        out.push(Token { raw, text, kind })
    }
    Ok(out)
}
#[derive(Clone)]
enum Expr {
    Literal(Value),
    Column(Option<String>, String),
    Op(String, Vec<Expr>),
    Aggregate(String, bool, Option<Box<Expr>>),
    Paren(Box<Expr>),
}
impl Expr {
    fn aggregate(&self) -> bool {
        match self {
            Self::Aggregate(..) => true,
            Self::Op(_, v) => v.iter().any(Self::aggregate),
            Self::Paren(e) => e.aggregate(),
            _ => false,
        }
    }
}
struct Parser {
    t: Vec<Token>,
    i: usize,
}
#[derive(Clone)]
struct Column {
    name: String,
    ty: u8,
    not_null: bool,
    pk: usize,
}
#[derive(Clone)]
struct Table {
    columns: Vec<Column>,
    rows: Vec<Vec<Value>>,
}
#[derive(Clone)]
struct Item {
    expr: Expr,
    alias: Option<String>,
    heading: String,
}
struct Query {
    distinct: bool,
    items: Option<Vec<Item>>,
    from: (String, String),
    joins: Vec<(bool, (String, String), Expr)>,
    filter: Option<Expr>,
    groups: Option<Vec<Expr>>,
    having: Option<Expr>,
    order: Vec<(Expr, bool)>,
    limit: Option<usize>,
    offset: usize,
}
enum Command {
    Empty,
    Exit,
    Create(String, Vec<Column>),
    Drop(String),
    Insert(String, Option<Vec<String>>, Vec<Vec<Expr>>),
    Update(String, Vec<(String, Expr)>, Option<Expr>),
    Delete(String, Option<Expr>),
    Select(Query),
}
impl Parser {
    fn peek(&self) -> &str {
        self.t.get(self.i).map_or("", |t| {
            if t.kind == 3 {
                t.raw.as_str()
            } else {
                t.text.as_str()
            }
        })
    }
    fn eat(&mut self, s: &str) -> bool {
        if self.peek() == s {
            self.i += 1;
            true
        } else {
            false
        }
    }
    fn error(&self) -> String {
        format!(
            "syntax error at '{}'",
            self.t.get(self.i).map_or(";", |t| t.raw.as_str())
        )
    }
    fn expect(&mut self, s: &str) -> Result<(), String> {
        if self.eat(s) {
            Ok(())
        } else {
            Err(self.error())
        }
    }
    fn name(&mut self) -> Result<String, String> {
        if self.t.get(self.i).is_some_and(|t| t.kind == 0) {
            let s = self.t[self.i].text.clone();
            self.i += 1;
            Ok(s)
        } else {
            Err(self.error())
        }
    }
    fn integer(&mut self) -> Result<usize, String> {
        if self.t.get(self.i).is_some_and(|t| t.kind == 2) {
            let s = self.t[self.i].text.parse().unwrap();
            self.i += 1;
            Ok(s)
        } else {
            Err(self.error())
        }
    }
    fn expr(&mut self) -> Result<Expr, String> {
        self.binary(0)
    }
    fn binary(&mut self, level: usize) -> Result<Expr, String> {
        if level == 2 {
            if self.eat("NOT") {
                return Ok(Expr::Op("NOT".into(), vec![self.binary(2)?]));
            }
            return self.binary(3);
        }
        if level == 6 {
            if self.eat("-") {
                return Ok(Expr::Op("NEG".into(), vec![self.binary(6)?]));
            }
            return self.primary();
        }
        let mut left = self.binary(level + 1)?;
        if level == 3 {
            let op = self.peek().to_string();
            if ["=", "!=", "<>", "<", ">", "<=", ">="].contains(&op.as_str()) {
                self.i += 1;
                return Ok(Expr::Op(op, vec![left, self.binary(4)?]));
            }
            if self.eat("IS") {
                let neg = self.eat("NOT");
                self.expect("NULL")?;
                return Ok(Expr::Op(
                    if neg { "IS NOT NULL" } else { "IS NULL" }.into(),
                    vec![left],
                ));
            }
            let neg = self.eat("NOT");
            let result = if self.eat("IN") {
                self.expect("(")?;
                let mut args = vec![left];
                args.push(self.expr()?);
                while self.eat(",") {
                    args.push(self.expr()?)
                }
                self.expect(")")?;
                Some(Expr::Op("IN".into(), args))
            } else if self.eat("BETWEEN") {
                let low = self.binary(4)?;
                self.expect("AND")?;
                let high = self.binary(4)?;
                Some(Expr::Op("BETWEEN".into(), vec![left, low, high]))
            } else if self.eat("LIKE") {
                Some(Expr::Op("LIKE".into(), vec![left, self.binary(4)?]))
            } else {
                if neg {
                    return Err(self.error());
                }
                return Ok(left);
            };
            let result = result.unwrap();
            return Ok(if neg {
                Expr::Op("NOT".into(), vec![result])
            } else {
                result
            });
        }
        loop {
            let op = self.peek().to_string();
            let matches = match level {
                0 => op == "OR",
                1 => op == "AND",
                4 => ["+", "-", "||"].contains(&op.as_str()),
                5 => ["*", "/", "%"].contains(&op.as_str()),
                _ => false,
            };
            if !matches {
                break;
            }
            self.i += 1;
            left = Expr::Op(op, vec![left, self.binary(level + 1)?])
        }
        Ok(left)
    }
    fn column(&mut self) -> Result<Expr, String> {
        let s = self.name()?;
        if self.eat(".") {
            Ok(Expr::Column(Some(s), self.name()?))
        } else {
            Ok(Expr::Column(None, s))
        }
    }
    fn primary(&mut self) -> Result<Expr, String> {
        let Some(t) = self.t.get(self.i).cloned() else {
            return Err(self.error());
        };
        if t.kind == 2 {
            self.i += 1;
            return Ok(Expr::Literal(Value::Int(t.text.parse().unwrap())));
        }
        if t.kind == 3 {
            self.i += 1;
            return Ok(Expr::Literal(Value::Text(t.text)));
        }
        if self.eat("NULL") {
            return Ok(Expr::Literal(Value::Null));
        }
        if self.eat("(") {
            let e = self.expr()?;
            self.expect(")")?;
            return Ok(Expr::Paren(Box::new(e)));
        }
        if ["COUNT", "SUM", "MIN", "MAX", "AVG"].contains(&t.text.as_str()) {
            self.i += 1;
            self.expect("(")?;
            if t.text == "COUNT" && self.eat("*") {
                self.expect(")")?;
                return Ok(Expr::Aggregate(t.text, false, None));
            }
            let distinct = self.eat("DISTINCT");
            let e = self.expr()?;
            self.expect(")")?;
            return Ok(Expr::Aggregate(t.text, distinct, Some(Box::new(e))));
        }
        self.column()
    }
    fn optional_where(&mut self) -> Result<Option<Expr>, String> {
        if self.eat("WHERE") {
            Ok(Some(self.expr()?))
        } else {
            Ok(None)
        }
    }
    fn table(&mut self) -> Result<(String, String), String> {
        let n = self.name()?;
        let alias = if self.eat("AS") || self.t.get(self.i).is_some_and(|t| t.kind == 0) {
            self.name()?
        } else {
            n.clone()
        };
        Ok((n, alias))
    }
    fn parse(&mut self) -> Result<Command, String> {
        let command = if self.peek() == ";" {
            Command::Empty
        } else if self.eat("EXIT") {
            Command::Exit
        } else if self.eat("CREATE") {
            self.expect("TABLE")?;
            let n = self.name()?;
            self.expect("(")?;
            let mut cols = Vec::new();
            loop {
                let name = self.name()?;
                let ty = if self.eat("INT") {
                    1
                } else {
                    self.expect("TEXT")?;
                    2
                };
                let mut not_null = false;
                let mut pk = 0;
                loop {
                    if self.eat("PRIMARY") {
                        self.expect("KEY")?;
                        pk += 1;
                        not_null = true
                    } else if self.eat("NOT") {
                        self.expect("NULL")?;
                        not_null = true
                    } else {
                        break;
                    }
                }
                cols.push(Column {
                    name,
                    ty,
                    not_null,
                    pk,
                });
                if !self.eat(",") {
                    break;
                }
            }
            self.expect(")")?;
            Command::Create(n, cols)
        } else if self.eat("DROP") {
            self.expect("TABLE")?;
            Command::Drop(self.name()?)
        } else if self.eat("INSERT") {
            self.expect("INTO")?;
            let n = self.name()?;
            let columns = if self.eat("(") {
                let mut c = vec![self.name()?];
                while self.eat(",") {
                    c.push(self.name()?)
                }
                self.expect(")")?;
                Some(c)
            } else {
                None
            };
            self.expect("VALUES")?;
            let mut tuples = Vec::new();
            loop {
                self.expect("(")?;
                let mut es = vec![self.expr()?];
                while self.eat(",") {
                    es.push(self.expr()?)
                }
                self.expect(")")?;
                tuples.push(es);
                if !self.eat(",") {
                    break;
                }
            }
            Command::Insert(n, columns, tuples)
        } else if self.eat("UPDATE") {
            let n = self.name()?;
            self.expect("SET")?;
            let mut assignments = Vec::new();
            loop {
                let c = self.name()?;
                self.expect("=")?;
                assignments.push((c, self.expr()?));
                if !self.eat(",") {
                    break;
                }
            }
            let filter = self.optional_where()?;
            Command::Update(n, assignments, filter)
        } else if self.eat("DELETE") {
            self.expect("FROM")?;
            let n = self.name()?;
            let filter = self.optional_where()?;
            Command::Delete(n, filter)
        } else if self.eat("SELECT") {
            let distinct = self.eat("DISTINCT");
            let items = if self.eat("*") {
                None
            } else {
                let mut items = Vec::new();
                loop {
                    let start = self.i;
                    let expr = self.expr()?;
                    let end = self.i;
                    let alias = if self.eat("AS") || self.t.get(self.i).is_some_and(|t| t.kind == 0)
                    {
                        Some(self.name()?)
                    } else {
                        None
                    };
                    let heading = if let Some(a) = &alias {
                        a.clone()
                    } else if let Expr::Column(_, c) = &expr {
                        c.clone()
                    } else {
                        let mut h = String::new();
                        for j in start..end {
                            if j > start && self.t[j - 1].kind != 4 && self.t[j].kind != 4 {
                                h.push(' ')
                            }
                            h.push_str(&self.t[j].raw)
                        }
                        h
                    };
                    items.push(Item {
                        expr,
                        alias,
                        heading,
                    });
                    if !self.eat(",") {
                        break;
                    }
                }
                Some(items)
            };
            self.expect("FROM")?;
            let from = self.table()?;
            let mut joins = Vec::new();
            while ["JOIN", "INNER", "LEFT"].contains(&self.peek()) {
                let left = if self.eat("LEFT") {
                    self.eat("OUTER");
                    true
                } else {
                    self.eat("INNER");
                    false
                };
                self.expect("JOIN")?;
                let t = self.table()?;
                self.expect("ON")?;
                joins.push((left, t, self.expr()?));
            }
            let filter = self.optional_where()?;
            let groups = if self.eat("GROUP") {
                self.expect("BY")?;
                let mut g = vec![self.column()?];
                while self.eat(",") {
                    g.push(self.column()?)
                }
                Some(g)
            } else {
                None
            };
            let having = if self.eat("HAVING") {
                Some(self.expr()?)
            } else {
                None
            };
            let mut order = Vec::new();
            if self.eat("ORDER") {
                self.expect("BY")?;
                loop {
                    let e = self.expr()?;
                    let desc = if self.eat("DESC") {
                        true
                    } else {
                        self.eat("ASC");
                        false
                    };
                    order.push((e, desc));
                    if !self.eat(",") {
                        break;
                    }
                }
            }
            let mut offset = 0;
            let limit = if self.eat("LIMIT") {
                let n = self.integer()?;
                if self.eat("OFFSET") {
                    offset = self.integer()?
                }
                Some(n)
            } else {
                None
            };
            Command::Select(Query {
                distinct,
                items,
                from,
                joins,
                filter,
                groups,
                having,
                order,
                limit,
                offset,
            })
        } else {
            return Err(self.error());
        };
        self.expect(";")?;
        if self.i != self.t.len() {
            return Err(self.error());
        }
        Ok(command)
    }
}
#[derive(Clone)]
struct ScopeColumn {
    table: String,
    name: String,
    ty: u8,
}
type Scope = Vec<ScopeColumn>;
fn scope(table: &Table, n: &str) -> Scope {
    table
        .columns
        .iter()
        .map(|c| ScopeColumn {
            table: n.into(),
            name: c.name.clone(),
            ty: c.ty,
        })
        .collect()
}
fn resolve(r: &Option<String>, c: &str, s: &Scope) -> Result<usize, String> {
    let raw = r.as_ref().map_or(c.to_string(), |r| format!("{}.{}", r, c));
    if let Some(r) = r {
        if !s.iter().any(|x| x.table == *r) {
            return Err(format!("unknown table {}", r));
        }
    }
    let matches: Vec<_> = s
        .iter()
        .enumerate()
        .filter(|(_, x)| x.name == c && r.as_ref().is_none_or(|r| x.table == *r))
        .map(|(i, _)| i)
        .collect();
    if matches.is_empty() {
        Err(format!("unknown column {}", raw))
    } else if matches.len() > 1 {
        Err(format!("ambiguous column {}", c))
    } else {
        Ok(matches[0])
    }
}
fn compatible(a: u8, b: u8) -> bool {
    a == 0 || b == 0 || a == b
}
fn check(
    e: &Expr,
    s: &Scope,
    aggregates: bool,
    groups: Option<&[usize]>,
    inside: bool,
) -> Result<u8, String> {
    match e {
        Expr::Literal(v) => Ok(v.ty()),
        Expr::Column(r, c) => {
            let i = resolve(r, c, s)?;
            if !inside && groups.is_some_and(|g| !g.contains(&i)) {
                return Err(format!(
                    "column {} is not grouped",
                    r.as_ref().map_or(c.clone(), |r| format!("{}.{}", r, c))
                ));
            }
            Ok(s[i].ty)
        }
        Expr::Paren(e) => check(e, s, aggregates, groups, inside),
        Expr::Aggregate(n, _, arg) => {
            if !aggregates || inside {
                return Err(format!("misuse of aggregate {}", n));
            }
            let ty = if let Some(arg) = arg {
                check(arg, s, aggregates, groups, true)?
            } else {
                1
            };
            if (n == "SUM" || n == "AVG") && !compatible(ty, 1) {
                return Err(format!("type mismatch for {}", n));
            }
            Ok(if ["COUNT", "SUM", "AVG"].contains(&n.as_str()) {
                1
            } else {
                ty
            })
        }
        Expr::Op(op, args) => {
            let types = args
                .iter()
                .map(|e| check(e, s, aggregates, groups, inside))
                .collect::<Result<Vec<_>, _>>()?;
            let error = || format!("type mismatch for {}", if op == "NEG" { "-" } else { op });
            let required = match op.as_str() {
                "||" | "LIKE" => 2,
                "IS NULL" | "IS NOT NULL" => return Ok(1),
                "IN" | "BETWEEN" | "=" | "!=" | "<>" | "<" | ">" | "<=" | ">=" => {
                    if types.iter().skip(1).any(|&t| !compatible(types[0], t)) {
                        return Err(error());
                    }
                    return Ok(1);
                }
                _ => 1,
            };
            if types.iter().any(|&t| !compatible(t, required)) {
                return Err(error());
            }
            Ok(if op == "||" { 2 } else { 1 })
        }
    }
}
fn condition(
    e: &Option<Expr>,
    s: &Scope,
    ag: bool,
    g: Option<&[usize]>,
    kind: &str,
) -> Result<(), String> {
    if let Some(e) = e {
        if !compatible(check(e, s, ag, g, false)?, 1) {
            return Err(format!("type mismatch for {}", kind));
        }
    }
    Ok(())
}
fn logical(a: &Value, b: &Value, and: bool) -> Value {
    let a = a.truth();
    let b = b.truth();
    Value::boolean(if and {
        if a == Some(false) || b == Some(false) {
            Some(false)
        } else if a.is_none() || b.is_none() {
            None
        } else {
            Some(true)
        }
    } else if a == Some(true) || b == Some(true) {
        Some(true)
    } else if a.is_none() || b.is_none() {
        None
    } else {
        Some(false)
    })
}
fn compare(a: &Value, b: &Value, op: &str) -> Value {
    if *a == Value::Null || *b == Value::Null {
        return Value::Null;
    }
    let ord = a.cmp(b);
    Value::Int(match op {
        "=" => a == b,
        "!=" | "<>" => a != b,
        "<" => ord.is_lt(),
        ">" => ord.is_gt(),
        "<=" => !ord.is_gt(),
        _ => !ord.is_lt(),
    } as i64)
}
fn like(s: &str, p: &str) -> bool {
    let mut dp = vec![false; s.len() + 1];
    dp[0] = true;
    for c in p.bytes() {
        let mut next = vec![false; s.len() + 1];
        if c == b'%' {
            next[0] = dp[0]
        }
        for i in 1..=s.len() {
            next[i] = if c == b'%' {
                dp[i] || next[i - 1]
            } else {
                dp[i - 1] && (c == b'_' || c == s.as_bytes()[i - 1])
            }
        }
        dp = next
    }
    dp[s.len()]
}
fn evaluate(e: &Expr, s: &Scope, row: &[Value], group: &[Vec<Value>]) -> Value {
    match e {
        Expr::Literal(v) => v.clone(),
        Expr::Column(r, c) => row
            .get(resolve(r, c, s).unwrap())
            .cloned()
            .unwrap_or(Value::Null),
        Expr::Paren(e) => evaluate(e, s, row, group),
        Expr::Aggregate(n, distinct, arg) => {
            if arg.is_none() {
                return Value::Int(group.len() as i64);
            }
            let arg = arg.as_ref().unwrap();
            let mut values = Vec::new();
            for r in group {
                let v = evaluate(arg, s, r, &[]);
                if v != Value::Null && (!distinct || !values.contains(&v)) {
                    values.push(v)
                }
            }
            if n == "COUNT" {
                return Value::Int(values.len() as i64);
            }
            if values.is_empty() {
                return Value::Null;
            }
            match n.as_str() {
                "MIN" => values.into_iter().min().unwrap(),
                "MAX" => values.into_iter().max().unwrap(),
                _ => {
                    let sum: i64 = values
                        .iter()
                        .map(|v| if let Value::Int(n) = v { *n } else { 0 })
                        .sum();
                    Value::Int(if n == "AVG" {
                        sum / values.len() as i64
                    } else {
                        sum
                    })
                }
            }
        }
        Expr::Op(op, args) => {
            let v: Vec<_> = args.iter().map(|e| evaluate(e, s, row, group)).collect();
            match op.as_str() {
                "NOT" => Value::boolean(v[0].truth().map(|b| !b)),
                "AND" => logical(&v[0], &v[1], true),
                "OR" => logical(&v[0], &v[1], false),
                "IS NULL" => Value::Int((v[0] == Value::Null) as i64),
                "IS NOT NULL" => Value::Int((v[0] != Value::Null) as i64),
                "IN" => {
                    if v[0] == Value::Null {
                        Value::Null
                    } else if v[1..].contains(&v[0]) {
                        Value::Int(1)
                    } else if v[1..].contains(&Value::Null) {
                        Value::Null
                    } else {
                        Value::Int(0)
                    }
                }
                "BETWEEN" => logical(
                    &compare(&v[0], &v[1], ">="),
                    &compare(&v[0], &v[2], "<="),
                    true,
                ),
                "=" | "!=" | "<>" | "<" | ">" | "<=" | ">=" => compare(&v[0], &v[1], op),
                _ => {
                    if v.contains(&Value::Null) {
                        return Value::Null;
                    }
                    if op == "LIKE" || op == "||" {
                        if let (Value::Text(a), Value::Text(b)) = (&v[0], &v[1]) {
                            if op == "LIKE" {
                                Value::Int(like(a, b) as i64)
                            } else {
                                Value::Text(format!("{}{}", a, b))
                            }
                        } else {
                            Value::Null
                        }
                    } else {
                        let a = if let Value::Int(a) = v[0] { a } else { 0 };
                        let b = if v.len() > 1 {
                            if let Value::Int(b) = v[1] { b } else { 0 }
                        } else {
                            0
                        };
                        match op.as_str() {
                            "NEG" => Value::Int(-a),
                            "+" => Value::Int(a + b),
                            "-" => Value::Int(a - b),
                            "*" => Value::Int(a * b),
                            "/" => {
                                if b == 0 {
                                    Value::Null
                                } else {
                                    Value::Int(a / b)
                                }
                            }
                            "%" => {
                                if b == 0 {
                                    Value::Null
                                } else {
                                    Value::Int(a % b)
                                }
                            }
                            _ => Value::Null,
                        }
                    }
                }
            }
        }
    }
}
fn table<'a>(db: &'a BTreeMap<String, Table>, n: &str) -> Result<&'a Table, String> {
    db.get(n).ok_or_else(|| format!("unknown table {}", n))
}
fn targets(t: &Table, names: &[String]) -> Result<Vec<usize>, String> {
    let mut ids = Vec::new();
    for n in names {
        let i = t
            .columns
            .iter()
            .position(|c| c.name == *n)
            .ok_or_else(|| format!("unknown column {}", n))?;
        if ids.contains(&i) {
            return Err(format!("duplicate column {}", n));
        }
        ids.push(i)
    }
    Ok(ids)
}
fn constraints(t: &Table, ids: &[usize]) -> Result<(), String> {
    let primary = t.columns.iter().position(|c| c.pk > 0);
    for &i in ids {
        let row = &t.rows[i];
        for (j, c) in t.columns.iter().enumerate() {
            if c.not_null && row[j] == Value::Null {
                return Err(format!("NULL value in column {}", c.name));
            }
        }
        if let Some(pk) = primary {
            if t.rows
                .iter()
                .enumerate()
                .any(|(j, r)| j != i && r[pk] == row[pk])
            {
                return Err(format!("duplicate primary key {}", row[pk].text()));
            }
        }
    }
    Ok(())
}
fn result_table(items: &[Item], types: &[u8], rows: &[Vec<Value>]) -> Vec<String> {
    let strings: Vec<Vec<_>> = rows
        .iter()
        .map(|r| r.iter().map(Value::text).collect())
        .collect();
    let widths: Vec<_> = items
        .iter()
        .enumerate()
        .map(|(i, item)| {
            strings
                .iter()
                .map(|r| r[i].len())
                .chain(std::iter::once(item.heading.len()))
                .max()
                .unwrap()
        })
        .collect();
    let separator = format!(
        "+{}",
        widths
            .iter()
            .map(|w| format!("{}+", "-".repeat(w + 2)))
            .collect::<String>()
    );
    let line = |cells: &[String], header: bool| {
        format!(
            "|{}",
            cells
                .iter()
                .enumerate()
                .map(|(i, c)| format!(
                    " {} |",
                    if !header && types[i] == 1 {
                        format!("{:>width$}", c, width = widths[i])
                    } else {
                        format!("{:<width$}", c, width = widths[i])
                    }
                ))
                .collect::<String>()
        )
    };
    let mut out = vec![
        separator.clone(),
        line(
            &items.iter().map(|i| i.heading.clone()).collect::<Vec<_>>(),
            true,
        ),
        separator.clone(),
    ];
    for r in strings {
        out.push(line(&r, false))
    }
    out.push(separator);
    out.push(format!(
        "({} row{})",
        rows.len(),
        if rows.len() == 1 { "" } else { "s" }
    ));
    out
}
fn execute(command: Command, db: &mut BTreeMap<String, Table>) -> Result<Vec<String>, String> {
    let message = |n: usize, verb: &str| {
        vec![format!(
            "{} row{} {}.",
            n,
            if n == 1 { "" } else { "s" },
            verb
        )]
    };
    match command {
        Command::Empty | Command::Exit => Ok(Vec::new()),
        Command::Create(n, cols) => {
            if db.contains_key(&n) {
                return Err(format!("table {} already exists", n));
            }
            let mut seen = BTreeSet::new();
            let mut pk = 0;
            for c in &cols {
                if !seen.insert(&c.name) {
                    return Err(format!("duplicate column {}", c.name));
                }
                pk += c.pk;
                if pk > 1 {
                    return Err("multiple primary keys".into());
                }
            }
            db.insert(
                n.clone(),
                Table {
                    columns: cols,
                    rows: Vec::new(),
                },
            );
            Ok(vec![format!("Table {} created.", n)])
        }
        Command::Drop(n) => {
            table(db, &n)?;
            db.remove(&n);
            Ok(vec![format!("Table {} dropped.", n)])
        }
        Command::Insert(n, names, tuples) => {
            let mut t = table(db, &n)?.clone();
            let ids = if let Some(names) = names {
                targets(&t, &names)?
            } else {
                (0..t.columns.len()).collect()
            };
            for es in &tuples {
                if es.len() != ids.len() {
                    return Err(format!("expected {} values, got {}", ids.len(), es.len()));
                }
                for (e, &i) in es.iter().zip(&ids) {
                    let ty = check(e, &vec![], false, None, false)?;
                    if !compatible(ty, t.columns[i].ty) {
                        return Err(format!("type mismatch for column {}", t.columns[i].name));
                    }
                }
            }
            let old = t.rows.len();
            for es in &tuples {
                let mut row = vec![Value::Null; t.columns.len()];
                for (e, &i) in es.iter().zip(&ids) {
                    row[i] = evaluate(e, &vec![], &[], &[])
                }
                t.rows.push(row)
            }
            constraints(&t, &(old..t.rows.len()).collect::<Vec<_>>())?;
            let count = tuples.len();
            db.insert(n, t);
            Ok(message(count, "inserted"))
        }
        Command::Update(n, assignments, filter) => {
            let mut t = table(db, &n)?.clone();
            let ids = targets(
                &t,
                &assignments
                    .iter()
                    .map(|(n, _)| n.clone())
                    .collect::<Vec<_>>(),
            )?;
            let s = scope(&t, &n);
            for ((_, e), &i) in assignments.iter().zip(&ids) {
                if !compatible(check(e, &s, false, None, false)?, t.columns[i].ty) {
                    return Err(format!("type mismatch for column {}", t.columns[i].name));
                }
            }
            condition(&filter, &s, false, None, "WHERE")?;
            let mut modified = Vec::new();
            for i in 0..t.rows.len() {
                if filter
                    .as_ref()
                    .is_none_or(|e| evaluate(e, &s, &t.rows[i], &[]).truth() == Some(true))
                {
                    let old = t.rows[i].clone();
                    for ((_, e), &j) in assignments.iter().zip(&ids) {
                        t.rows[i][j] = evaluate(e, &s, &old, &[])
                    }
                    modified.push(i)
                }
            }
            constraints(&t, &modified)?;
            db.insert(n, t);
            Ok(message(modified.len(), "updated"))
        }
        Command::Delete(n, filter) => {
            let mut t = table(db, &n)?.clone();
            let s = scope(&t, &n);
            condition(&filter, &s, false, None, "WHERE")?;
            let old = t.rows.len();
            t.rows.retain(|r| {
                !filter
                    .as_ref()
                    .is_none_or(|e| evaluate(e, &s, r, &[]).truth() == Some(true))
            });
            let count = old - t.rows.len();
            db.insert(n, t);
            Ok(message(count, "deleted"))
        }
        Command::Select(q) => {
            let first = table(db, &q.from.0)?;
            let mut s = scope(first, &q.from.1);
            let mut seen = BTreeSet::from([q.from.1.clone()]);
            let mut scopes = vec![s.clone()];
            for (_, t, on) in &q.joins {
                let table = table(db, &t.0)?;
                if !seen.insert(t.1.clone()) {
                    return Err(format!("duplicate table name {}", t.1));
                }
                s.extend(scope(table, &t.1));
                condition(&Some(on.clone()), &s, false, None, "ON")?;
                scopes.push(s.clone())
            }
            condition(&q.filter, &s, false, None, "WHERE")?;
            let mut groups = Vec::new();
            if let Some(es) = &q.groups {
                for e in es {
                    if let Expr::Column(r, c) = e {
                        groups.push(resolve(r, c, &s)?);
                    }
                }
            }
            let expanded = q.items.is_none();
            let items = q.items.unwrap_or_else(|| {
                s.iter()
                    .map(|c| Item {
                        expr: Expr::Column(Some(c.table.clone()), c.name.clone()),
                        alias: None,
                        heading: c.name.clone(),
                    })
                    .collect()
            });
            let ag = q.groups.is_some()
                || q.having.is_some()
                || items.iter().any(|i| i.expr.aggregate())
                || q.order.iter().any(|(e, _)| e.aggregate());
            let grouping = if ag { Some(groups.as_slice()) } else { None };
            let mut types = Vec::new();
            for item in &items {
                let ty = check(&item.expr, &s, true, grouping, false).map_err(|error| {
                    if expanded
                        && error.starts_with("column ")
                        && error.ends_with(" is not grouped")
                    {
                        format!("column {} is not grouped", item.heading)
                    } else {
                        error
                    }
                })?;
                types.push(ty);
            }
            condition(&q.having, &s, true, grouping, "HAVING")?;
            let mut keys = Vec::new();
            for (e, desc) in &q.order {
                let position = match e {
                    Expr::Literal(Value::Int(n)) => {
                        if *n < 1 || *n as usize > items.len() {
                            return Err(format!("ORDER BY position {} is out of range", n));
                        }
                        Some(*n as usize - 1)
                    }
                    Expr::Column(None, n) => items.iter().position(|i| i.alias.as_ref() == Some(n)),
                    _ => None,
                };
                if position.is_none() {
                    check(e, &s, true, grouping, false)?;
                }
                keys.push((e.clone(), *desc, position));
            }
            let mut rows = first.rows.clone();
            for (j, (left, t, on)) in q.joins.iter().enumerate() {
                let other = table(db, &t.0)?;
                let mut next = Vec::new();
                for r in &rows {
                    let mut matched = false;
                    for right in &other.rows {
                        let mut row = r.clone();
                        row.extend(right.clone());
                        if evaluate(on, &scopes[j + 1], &row, &[]).truth() == Some(true) {
                            next.push(row);
                            matched = true
                        }
                    }
                    if *left && !matched {
                        let mut row = r.clone();
                        row.extend(vec![Value::Null; other.columns.len()]);
                        next.push(row)
                    }
                }
                rows = next
            }
            rows.retain(|r| {
                q.filter
                    .as_ref()
                    .is_none_or(|e| evaluate(e, &s, r, &[]).truth() == Some(true))
            });
            let mut grouped: Vec<Vec<Vec<Value>>> = Vec::new();
            if ag {
                if q.groups.is_some() {
                    let mut indices: BTreeMap<Vec<Value>, usize> = BTreeMap::new();
                    for row in rows {
                        let key = groups.iter().map(|&i| row[i].clone()).collect::<Vec<_>>();
                        let i = if let Some(&i) = indices.get(&key) {
                            i
                        } else {
                            let i = grouped.len();
                            indices.insert(key, i);
                            grouped.push(Vec::new());
                            i
                        };
                        grouped[i].push(row)
                    }
                } else {
                    grouped.push(rows)
                }
            } else {
                for row in rows {
                    grouped.push(vec![row])
                }
            }
            let mut result = Vec::new();
            for group in grouped {
                let empty = Vec::new();
                let row = group.first().unwrap_or(&empty);
                if q.having
                    .as_ref()
                    .is_some_and(|e| evaluate(e, &s, row, &group).truth() != Some(true))
                {
                    continue;
                }
                let values = items
                    .iter()
                    .map(|i| evaluate(&i.expr, &s, row, &group))
                    .collect::<Vec<_>>();
                let order = keys
                    .iter()
                    .map(|(e, _, p)| {
                        p.map_or_else(|| evaluate(e, &s, row, &group), |i| values[i].clone())
                    })
                    .collect::<Vec<_>>();
                result.push((values, order))
            }
            result.sort_by(|a, b| {
                for (i, (_, desc, _)) in keys.iter().enumerate() {
                    let ord = a.1[i].cmp(&b.1[i]);
                    if !ord.is_eq() {
                        return if *desc { ord.reverse() } else { ord };
                    }
                }
                std::cmp::Ordering::Equal
            });
            if q.distinct {
                let mut unique = BTreeSet::new();
                result.retain(|r| unique.insert(r.0.clone()))
            }
            let output = result
                .into_iter()
                .skip(q.offset)
                .take(q.limit.unwrap_or(usize::MAX))
                .map(|r| r.0)
                .collect::<Vec<_>>();
            Ok(result_table(&items, &types, &output))
        }
    }
}
fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let b = input.as_bytes();
    let mut i = 0;
    let mut buffer = String::new();
    let mut statements = Vec::new();
    while i < b.len() {
        if b[i] == b'\'' {
            buffer.push('\'');
            i += 1;
            while i < b.len() {
                buffer.push(b[i] as char);
                let end = b[i] == b'\'';
                i += 1;
                if end {
                    break;
                }
            }
        } else if b[i] == b'-' && i + 1 < b.len() && b[i + 1] == b'-' {
            while i < b.len() && b[i] != b'\n' {
                i += 1
            }
            buffer.push(' ')
        } else {
            let c = b[i] as char;
            buffer.push(c);
            i += 1;
            if c == ';' {
                statements.push(std::mem::take(&mut buffer))
            }
        }
    }
    let mut db = BTreeMap::new();
    for statement in statements {
        let result = lex(&statement).and_then(|t| Parser { t, i: 0 }.parse());
        match result {
            Err(e) => println!("ERROR: {}", e),
            Ok(Command::Exit) => break,
            Ok(c) => match execute(c, &mut db) {
                Ok(lines) => {
                    for l in lines {
                        println!("{}", l)
                    }
                }
                Err(e) => println!("ERROR: {}", e),
            },
        }
    }
}
