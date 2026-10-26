use std::collections::{BTreeMap, BTreeSet};
use std::io::{self, Read};
use std::rc::Rc;

type F = Rc<Formula>;

struct Formula {
    op: String,
    left: Option<F>,
    right: Option<F>,
}
fn leaf(op: &str) -> F {
    Rc::new(Formula {
        op: op.into(),
        left: None,
        right: None,
    })
}
fn unary(a: F) -> F {
    Rc::new(Formula {
        op: "~".into(),
        left: Some(a),
        right: None,
    })
}
fn binary(op: &str, a: F, b: F) -> F {
    Rc::new(Formula {
        op: op.into(),
        left: Some(a),
        right: Some(b),
    })
}
fn identity(f: &F) -> usize {
    Rc::as_ptr(f) as usize
}
fn same(a: &F, b: &F) -> bool {
    Rc::ptr_eq(a, b)
        || a.op == b.op
            && match (&a.left, &b.left, &a.right, &b.right) {
                (None, None, None, None) => true,
                (Some(x), Some(y), None, None) => same(x, y),
                (Some(x), Some(y), Some(z), Some(w)) => same(x, y) && same(z, w),
                _ => false,
            }
}
fn precedence(op: &str) -> usize {
    match op {
        "<->" => 1,
        "->" => 2,
        "|" => 3,
        "^" => 4,
        "&" => 5,
        "~" => 6,
        _ => 7,
    }
}
fn notation(f: &F) -> String {
    let Some(a) = &f.left else {
        return f.op.clone();
    };
    if f.op == "~" {
        let s = notation(a);
        return "~".to_string()
            + &if a.right.is_some() {
                format!("({})", s)
            } else {
                s
            };
    }
    let b = f.right.as_ref().unwrap();
    let left = notation(a);
    let right = notation(b);
    format!(
        "{} {} {}",
        if a.right.is_some()
            && (precedence(&a.op) < precedence(&f.op) || a.op == "->" && f.op == "->")
        {
            format!("({})", left)
        } else {
            left
        },
        f.op,
        if b.right.is_some()
            && (precedence(&b.op) < precedence(&f.op) || b.op == f.op && f.op != "->")
        {
            format!("({})", right)
        } else {
            right
        }
    )
}
fn variables(f: &F, result: &mut BTreeSet<char>) {
    if f.left.is_none() && f.op.as_bytes()[0].is_ascii_uppercase() {
        result.insert(f.op.chars().next().unwrap());
    }
    if let Some(a) = &f.left {
        variables(a, result);
    }
    if let Some(b) = &f.right {
        variables(b, result);
    }
}
fn evaluate(f: &F, vars: &[char], row: usize) -> u8 {
    if f.left.is_none() {
        return match f.op.as_str() {
            "0" => 0,
            "1" => 1,
            _ => {
                ((row
                    >> (vars.len() - 1 - vars.iter().position(|c| f.op.starts_with(*c)).unwrap()))
                    & 1) as u8
            }
        };
    }
    let a = evaluate(f.left.as_ref().unwrap(), vars, row);
    if f.op == "~" {
        return 1 - a;
    }
    let b = evaluate(f.right.as_ref().unwrap(), vars, row);
    match f.op.as_str() {
        "&" => a & b,
        "|" => a | b,
        "^" => a ^ b,
        "->" => (1 - a) | b,
        _ => u8::from(a == b),
    }
}
#[derive(Clone)]
struct Token {
    text: String,
    position: usize,
}
struct Parser<'a> {
    tokens: Vec<Token>,
    at: usize,
    end: usize,
    definitions: &'a BTreeMap<String, F>,
}
impl<'a> Parser<'a> {
    fn new(text: &str, start: usize, definitions: &'a BTreeMap<String, F>) -> Result<Self, String> {
        let b = text.as_bytes();
        let mut i = 0;
        let mut tokens = Vec::new();
        while i < b.len() {
            if b[i] == b' ' {
                i += 1;
                continue;
            }
            let begin = i;
            if text[i..].starts_with("<->") {
                i += 3;
            } else if text[i..].starts_with("->") {
                i += 2;
            } else if b[i].is_ascii_lowercase() {
                i += 1;
                while i < b.len() && (b[i].is_ascii_lowercase() || b[i].is_ascii_digit()) {
                    i += 1;
                }
            } else if b[i].is_ascii_uppercase() || b"01~&^|()".contains(&b[i]) {
                i += 1;
            } else {
                return Err(format!(
                    "invalid character '{}' at {}",
                    b[i] as char,
                    start + i
                ));
            }
            tokens.push(Token {
                text: text[begin..i].into(),
                position: start + begin,
            });
        }
        Ok(Self {
            tokens,
            at: 0,
            end: start + text.len(),
            definitions,
        })
    }
    fn peek(&self) -> &str {
        self.tokens.get(self.at).map_or("", |t| t.text.as_str())
    }
    fn error(&self) -> String {
        self.tokens.get(self.at).map_or_else(
            || format!("unexpected end of formula at {}", self.end),
            |t| format!("unexpected '{}' at {}", t.text, t.position),
        )
    }
    fn unary(&mut self) -> Result<F, String> {
        if self.peek() == "~" {
            self.at += 1;
            return Ok(unary(self.unary()?));
        }
        if self.peek() == "(" {
            self.at += 1;
            let f = self.expression(1)?;
            if self.peek() != ")" {
                return Err(self.error());
            }
            self.at += 1;
            return Ok(f);
        }
        let Some(t) = self.tokens.get(self.at) else {
            return Err(self.error());
        };
        if t.text.as_bytes()[0].is_ascii_lowercase() {
            let f = self
                .definitions
                .get(&t.text)
                .cloned()
                .ok_or_else(|| format!("undefined name '{}' at {}", t.text, t.position))?;
            self.at += 1;
            return Ok(f);
        }
        if t.text == "0"
            || t.text == "1"
            || t.text.len() == 1 && t.text.as_bytes()[0].is_ascii_uppercase()
        {
            let f = leaf(&t.text);
            self.at += 1;
            return Ok(f);
        }
        Err(self.error())
    }
    fn expression(&mut self, level: usize) -> Result<F, String> {
        if level == 6 {
            return self.unary();
        }
        let mut f = self.expression(level + 1)?;
        let op = ["", "<->", "->", "|", "^", "&"][level];
        while self.peek() == op {
            self.at += 1;
            let right = self.expression(if op == "->" { level } else { level + 1 })?;
            f = binary(op, f, right);
        }
        Ok(f)
    }
    fn parse(mut self) -> Result<F, String> {
        let f = self.expression(1)?;
        if self.at != self.tokens.len() {
            return Err(self.error());
        }
        Ok(f)
    }
}
fn negate(a: F) -> F {
    match a.op.as_str() {
        "0" => leaf("1"),
        "1" => leaf("0"),
        "~" => a.left.as_ref().unwrap().clone(),
        _ => unary(a),
    }
}
fn simplify_pair(op: &str, a: F, b: F) -> F {
    let eq = same(&a, &b);
    let complementary = a.op == "~" && same(a.left.as_ref().unwrap(), &b)
        || b.op == "~" && same(&a, b.left.as_ref().unwrap());
    let result = match op {
        "&" if a.op == "0" || b.op == "0" => Some(leaf("0")),
        "&" if a.op == "1" => Some(b.clone()),
        "&" if b.op == "1" || eq => Some(a.clone()),
        "&" if complementary => Some(leaf("0")),
        "|" if a.op == "1" || b.op == "1" => Some(leaf("1")),
        "|" if a.op == "0" => Some(b.clone()),
        "|" if b.op == "0" || eq => Some(a.clone()),
        "|" if complementary => Some(leaf("1")),
        "^" if a.op == "0" => Some(b.clone()),
        "^" if b.op == "0" => Some(a.clone()),
        "^" if a.op == "1" => Some(negate(b.clone())),
        "^" if b.op == "1" => Some(negate(a.clone())),
        "^" if eq => Some(leaf("0")),
        "^" if complementary => Some(leaf("1")),
        "->" if a.op == "0" || b.op == "1" => Some(leaf("1")),
        "->" if a.op == "1" => Some(b.clone()),
        "->" if b.op == "0" => Some(negate(a.clone())),
        "->" if eq => Some(leaf("1")),
        "->" if complementary => Some(b.clone()),
        "<->" if a.op == "1" => Some(b.clone()),
        "<->" if b.op == "1" => Some(a.clone()),
        "<->" if a.op == "0" => Some(negate(b.clone())),
        "<->" if b.op == "0" => Some(negate(a.clone())),
        "<->" if eq => Some(leaf("1")),
        "<->" if complementary => Some(leaf("0")),
        _ => None,
    };
    result.unwrap_or_else(|| binary(op, a, b))
}
fn simplify(f: &F, assignments: &BTreeMap<char, u8>) -> F {
    let Some(a) = &f.left else {
        return assignments
            .get(&f.op.chars().next().unwrap())
            .map_or_else(|| f.clone(), |n| leaf(&n.to_string()));
    };
    let a = simplify(a, assignments);
    if f.op == "~" {
        negate(a)
    } else {
        simplify_pair(&f.op, a, simplify(f.right.as_ref().unwrap(), assignments))
    }
}
fn dual(f: &F) -> F {
    let Some(a) = &f.left else {
        return match f.op.as_str() {
            "0" => leaf("1"),
            "1" => leaf("0"),
            _ => f.clone(),
        };
    };
    let a = dual(a);
    if f.op == "~" {
        return unary(a);
    }
    let b = dual(f.right.as_ref().unwrap());
    match f.op.as_str() {
        "&" => binary("|", a, b),
        "|" => binary("&", a, b),
        "^" => binary("<->", a, b),
        "<->" => binary("^", a, b),
        _ => binary("&", unary(a), b),
    }
}
fn nnf(f: &F, positive: bool, memo: &mut BTreeMap<(usize, bool), F>) -> F {
    let key = (identity(f), positive);
    if let Some(result) = memo.get(&key) {
        return result.clone();
    }
    let result = if f.left.is_none() {
        if positive {
            f.clone()
        } else if f.op == "0" {
            leaf("1")
        } else if f.op == "1" {
            leaf("0")
        } else {
            unary(f.clone())
        }
    } else if f.op == "~" {
        nnf(f.left.as_ref().unwrap(), !positive, memo)
    } else {
        let a = f.left.as_ref().unwrap();
        let b = f.right.as_ref().unwrap();
        match f.op.as_str() {
            "&" | "|" => {
                let op = if (f.op == "&") == positive { "&" } else { "|" };
                let left = nnf(a, positive, memo);
                let right = nnf(b, positive, memo);
                binary(op, left, right)
            }
            "->" => {
                let left = nnf(a, !positive, memo);
                let right = nnf(b, positive, memo);
                binary(if positive { "|" } else { "&" }, left, right)
            }
            _ => {
                let equal = (f.op == "<->") == positive;
                let ap = nnf(a, true, memo);
                let an = nnf(a, false, memo);
                let bp = nnf(b, equal, memo);
                let bn = nnf(b, !equal, memo);
                binary("|", binary("&", ap, bp), binary("&", an, bn))
            }
        }
    };
    memo.insert(key, result.clone());
    result
}
fn pattern(row: usize, n: usize) -> String {
    (0..n)
        .map(|i| {
            if row & (1 << (n - 1 - i)) == 0 {
                '0'
            } else {
                '1'
            }
        })
        .collect()
}
fn invert(p: &str) -> String {
    p.chars()
        .map(|c| match c {
            '0' => '1',
            '1' => '0',
            _ => '-',
        })
        .collect()
}
fn pattern_key(p: &str) -> Vec<u8> {
    p.bytes()
        .map(|c| match c {
            b'1' => 0,
            b'0' => 1,
            _ => 2,
        })
        .collect()
}
fn sorted_patterns(mut ps: Vec<String>) -> Vec<String> {
    ps.sort_by_key(|p| pattern_key(p));
    ps
}
fn literals(p: &str) -> usize {
    p.bytes().filter(|c| *c != b'-').count()
}
fn contains(p: &str, row: usize) -> bool {
    p.bytes()
        .zip(pattern(row, p.len()).bytes())
        .all(|(a, b)| a == b'-' || a == b)
}
fn term_text(p: &str, vars: &[char], clause: bool) -> String {
    let list: Vec<String> = p
        .chars()
        .zip(vars)
        .filter_map(|(c, v)| match c {
            '1' => Some(v.to_string()),
            '0' => Some(format!("~{}", v)),
            _ => None,
        })
        .collect();
    if list.is_empty() {
        if clause { "0" } else { "1" }.into()
    } else {
        list.join(if clause { " | " } else { " & " })
    }
}
fn cover_text(ps: &[String], vars: &[char], clause: bool) -> String {
    if ps.is_empty() {
        return if clause { "1" } else { "0" }.into();
    }
    ps.iter()
        .map(|p| {
            let s = term_text(p, vars, clause);
            if clause && ps.len() >= 2 && literals(p) >= 2 {
                format!("({})", s)
            } else {
                s
            }
        })
        .collect::<Vec<_>>()
        .join(if clause { " & " } else { " | " })
}
fn coefficients(values: &[u8]) -> Vec<u8> {
    let mut c = values.to_vec();
    let mut bit = 1;
    while bit < c.len() {
        for s in 0..c.len() {
            if s & bit != 0 {
                c[s] ^= c[s ^ bit];
            }
        }
        bit *= 2;
    }
    c
}
fn assignment(row: usize, vars: &[char]) -> String {
    format!(
        "{{{}}}",
        vars.iter()
            .zip(pattern(row, vars.len()).chars())
            .map(|(v, n)| format!("{}={}", v, n))
            .collect::<Vec<_>>()
            .join(" ")
    )
}
fn minimize(vars: &[char], on: &[usize], dc: &[usize], pos: bool) -> Vec<String> {
    let mut stage: BTreeSet<String> = on
        .iter()
        .chain(dc)
        .map(|r| pattern(*r, vars.len()))
        .collect();
    let mut primes = Vec::new();
    let mut output = Vec::new();
    let mut k = 0;
    loop {
        let list: Vec<String> = stage.iter().cloned().collect();
        let mut used = BTreeSet::new();
        let mut next = BTreeSet::new();
        for i in 0..list.len() {
            for j in i + 1..list.len() {
                let differing: Vec<usize> = list[i]
                    .bytes()
                    .zip(list[j].bytes())
                    .enumerate()
                    .filter(|(_, (a, b))| a != b)
                    .map(|(i, _)| i)
                    .collect();
                if differing.len() == 1 {
                    let d = differing[0];
                    if list[i].as_bytes()[d] != b'-' && list[j].as_bytes()[d] != b'-' {
                        let mut p = list[i].as_bytes().to_vec();
                        p[d] = b'-';
                        next.insert(String::from_utf8(p).unwrap());
                        used.insert(i);
                        used.insert(j);
                    }
                }
            }
        }
        let new_primes: Vec<String> = list
            .into_iter()
            .enumerate()
            .filter(|(i, _)| !used.contains(i))
            .map(|(_, p)| p)
            .collect();
        if !pos {
            output.push(format!(
                "stage {}: implicants {} primes {}",
                k,
                stage.len(),
                new_primes.len()
            ));
        }
        primes.extend(new_primes);
        if next.is_empty() {
            break;
        }
        stage = next;
        k += 1;
    }
    let primes = sorted_patterns(
        primes
            .into_iter()
            .filter(|p| on.iter().any(|r| contains(p, *r)))
            .collect(),
    );
    let mut essential = BTreeSet::new();
    for &r in on {
        let list: Vec<usize> = primes
            .iter()
            .enumerate()
            .filter(|(_, p)| contains(p, r))
            .map(|(i, _)| i)
            .collect();
        if list.len() == 1 {
            essential.insert(list[0]);
        }
    }
    let optional: Vec<usize> = (0..primes.len())
        .filter(|i| !essential.contains(i))
        .collect();
    let mut best: Option<(usize, usize, Vec<Vec<u8>>, Vec<String>)> = None;
    for mask in 0usize..1 << optional.len() {
        let mut chosen = essential.clone();
        for (i, p) in optional.iter().enumerate() {
            if mask & (1 << i) != 0 {
                chosen.insert(*p);
            }
        }
        if best.as_ref().is_some_and(|b| chosen.len() > b.0) {
            continue;
        }
        if !on
            .iter()
            .all(|r| chosen.iter().any(|i| contains(&primes[*i], *r)))
        {
            continue;
        }
        let ps = sorted_patterns(
            chosen
                .iter()
                .map(|i| {
                    if pos {
                        invert(&primes[*i])
                    } else {
                        primes[*i].clone()
                    }
                })
                .collect(),
        );
        let count = ps.iter().map(|p| literals(p)).sum();
        let key = (
            ps.len(),
            count,
            ps.iter().map(|p| pattern_key(p)).collect::<Vec<_>>(),
        );
        if best.as_ref().is_none_or(|b| key < (b.0, b.1, b.2.clone())) {
            best = Some((key.0, key.1, key.2, ps));
        }
    }
    let (count, literal_count, _, cover) = best.unwrap();
    if !pos {
        for (heading, ps) in [
            ("primes", primes.clone()),
            (
                "essential",
                essential.iter().map(|i| primes[*i].clone()).collect(),
            ),
        ] {
            output.push(format!(
                "{}: {}",
                heading,
                if ps.is_empty() {
                    "none".into()
                } else {
                    ps.iter()
                        .map(|p| term_text(p, vars, false))
                        .collect::<Vec<_>>()
                        .join(", ")
                }
            ));
        }
    }
    output.push(format!("minimal: {}", cover_text(&cover, vars, pos)));
    output.push(format!(
        "{} {} literals {}",
        if pos { "clauses" } else { "terms" },
        count,
        literal_count
    ));
    output
}
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
struct Clause {
    positive: u32,
    negative: u32,
}
fn tidy(clauses: BTreeSet<Clause>) -> BTreeSet<Clause> {
    clauses
        .iter()
        .filter(|c| {
            c.positive & c.negative == 0
                && !clauses.iter().any(|e| {
                    e != *c
                        && e.positive & c.positive == e.positive
                        && e.negative & c.negative == e.negative
                })
        })
        .copied()
        .collect()
}
fn clauses(f: &F, vars: &[char], memo: &mut BTreeMap<usize, BTreeSet<Clause>>) -> BTreeSet<Clause> {
    if let Some(c) = memo.get(&identity(f)) {
        return c.clone();
    }
    let result = if f.op == "1" {
        BTreeSet::new()
    } else if f.op == "0" {
        BTreeSet::from([Clause {
            positive: 0,
            negative: 0,
        }])
    } else if f.op == "~" || f.left.is_none() {
        let n = if f.op == "~" {
            &f.left.as_ref().unwrap().op
        } else {
            &f.op
        };
        let bit = 1u32 << vars.iter().position(|c| n.starts_with(*c)).unwrap();
        BTreeSet::from([Clause {
            positive: if f.op == "~" { 0 } else { bit },
            negative: if f.op == "~" { bit } else { 0 },
        }])
    } else {
        let a = clauses(f.left.as_ref().unwrap(), vars, memo);
        let b = clauses(f.right.as_ref().unwrap(), vars, memo);
        let c = if f.op == "&" {
            a.union(&b).copied().collect()
        } else {
            a.iter()
                .flat_map(|x| {
                    b.iter().filter_map(move |y| {
                        let c = Clause {
                            positive: x.positive | y.positive,
                            negative: x.negative | y.negative,
                        };
                        (c.positive & c.negative == 0).then_some(c)
                    })
                })
                .collect()
        };
        tidy(c)
    };
    memo.insert(identity(f), result.clone());
    result
}
fn clause_patterns(cs: &BTreeSet<Clause>, n: usize) -> Vec<String> {
    sorted_patterns(
        cs.iter()
            .map(|c| {
                (0..n)
                    .map(|i| {
                        if c.positive & (1 << i) != 0 {
                            '1'
                        } else if c.negative & (1 << i) != 0 {
                            '0'
                        } else {
                            '-'
                        }
                    })
                    .collect()
            })
            .collect(),
    )
}
fn valid_name(s: &str) -> bool {
    !s.is_empty()
        && s.len() <= 8
        && s.as_bytes()[0].is_ascii_lowercase()
        && s.bytes()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit())
}
struct Workbench {
    definitions: BTreeMap<String, F>,
}
impl Workbench {
    fn parse(&self, text: &str, start: usize) -> Result<F, String> {
        Parser::new(text, start, &self.definitions)?.parse()
    }
    fn define(&mut self, name: &str, f: F) -> Vec<String> {
        let heading = if self.definitions.contains_key(name) {
            "redefined"
        } else {
            "defined"
        };
        let line = format!("{} {} = {}", heading, name, notation(&f));
        self.definitions.insert(name.into(), f);
        vec![line]
    }
    fn command(&mut self, line: &str) -> Result<Vec<String>, String> {
        let (command, argument) = line.split_once(' ').unwrap_or((line, ""));
        let known = [
            "DEF", "DEFSUM", "DEL", "LIST", "PRINT", "TABLE", "MINTERMS", "MAXTERMS", "DNF", "CNF",
            "NNF", "DUAL", "ANF", "SIMPLIFY", "RESTRICT", "COFACTOR", "MINIMIZE", "MINDC",
            "MINPOS", "KMAP", "SAT", "TAUT", "COUNT", "EQUIV", "IMPLIES", "PROPS", "BDD",
            "CLAUSES", "DP",
        ];
        if !known.contains(&command) {
            return Err(format!("unknown command {}", command));
        }
        if command == "LIST" {
            if line.contains(' ') {
                return Err("unexpected argument".into());
            }
            return Ok(
                std::iter::once(format!("names: {}", self.definitions.len()))
                    .chain(
                        self.definitions
                            .iter()
                            .map(|(n, f)| format!("{} = {}", n, notation(f))),
                    )
                    .collect(),
            );
        }
        if !line.contains(' ') {
            return Err("missing argument".into());
        }
        if command == "DEL" {
            if !valid_name(argument) {
                return Err(format!("invalid name '{}'", argument));
            }
            if self.definitions.remove(argument).is_none() {
                return Err(format!("undefined name '{}'", argument));
            }
            return Ok(vec![format!("deleted {}", argument)]);
        }
        if command == "DEF" {
            let (name, text) = argument.split_once(' ').ok_or("missing argument")?;
            if !valid_name(name) {
                return Err(format!("invalid name '{}'", name));
            }
            let f = self.parse(text, name.len() + 6)?;
            return Ok(self.define(name, f));
        }
        if command == "DEFSUM" {
            let (front, back) = argument.split_once(';').ok_or("missing ';'")?;
            let words: Vec<&str> = front.split_whitespace().collect();
            let name = *words.first().ok_or("missing argument")?;
            if !valid_name(name) {
                return Err(format!("invalid name '{}'", name));
            }
            let list = &words[1..];
            if list.is_empty()
                || list
                    .iter()
                    .any(|v| v.len() != 1 || !v.as_bytes()[0].is_ascii_uppercase())
                || list.windows(2).any(|p| p[0] >= p[1])
            {
                return Err("bad variable list".into());
            }
            if list.len() >= 9 {
                return Err(format!("too many variables: {}", list.len()));
            }
            let mut previous = None;
            let mut terms = Vec::new();
            for word in back.split_whitespace() {
                if word.is_empty()
                    || !word.bytes().all(|c| c.is_ascii_digit())
                    || word.len() > 1 && word.starts_with('0')
                {
                    return Err(format!("bad minterm '{}'", word));
                }
                let row: usize = word.parse().unwrap();
                if row >= 1 << list.len() || previous.is_some_and(|p| row <= p) {
                    return Err(format!("bad minterm '{}'", word));
                }
                previous = Some(row);
                let literals: Vec<F> = list
                    .iter()
                    .zip(pattern(row, list.len()).chars())
                    .map(|(v, n)| if n == '1' { leaf(v) } else { unary(leaf(v)) })
                    .collect();
                terms.push(
                    literals
                        .into_iter()
                        .reduce(|a, b| binary("&", a, b))
                        .unwrap(),
                );
            }
            let f = terms
                .into_iter()
                .reduce(|a, b| binary("|", a, b))
                .unwrap_or_else(|| leaf("0"));
            return Ok(self.define(name, f));
        }
        let split = ["RESTRICT", "COFACTOR", "MINDC", "EQUIV", "IMPLIES"].contains(&command);
        let (front, back, back_start) = if split {
            let i = argument.find(';').ok_or("missing ';'")?;
            (&argument[..i], &argument[i + 1..], command.len() + i + 3)
        } else {
            (argument, "", 0)
        };
        let f = self.parse(front, command.len() + 2)?;
        let g = if ["MINDC", "EQUIV", "IMPLIES"].contains(&command) {
            Some(self.parse(back, back_start)?)
        } else {
            None
        };
        if command == "RESTRICT" || command == "COFACTOR" {
            let words: Vec<&str> = back.split_whitespace().collect();
            let mut assignments = BTreeMap::new();
            if command == "RESTRICT" {
                if words.is_empty() {
                    return Err("missing assignment".into());
                }
                for word in words {
                    let b = word.as_bytes();
                    if b.len() != 3
                        || !b[0].is_ascii_uppercase()
                        || b[1] != b'='
                        || !b"01".contains(&b[2])
                    {
                        return Err(format!("bad assignment '{}'", word));
                    }
                    if assignments.insert(b[0] as char, b[2] - b'0').is_some() {
                        return Err(format!("duplicate variable {}", b[0] as char));
                    }
                }
                return Ok(vec![format!(
                    "restricted: {}",
                    notation(&simplify(&f, &assignments))
                )]);
            }
            if words.len() != 1
                || words[0].len() != 1
                || !words[0].as_bytes()[0].is_ascii_uppercase()
            {
                return Err("bad variable".into());
            }
            let x = words[0].as_bytes()[0] as char;
            assignments.insert(x, 1);
            let high = simplify(&f, &assignments);
            assignments.insert(x, 0);
            let low = simplify(&f, &assignments);
            return Ok(vec![
                format!("cofactor {}=1: {}", x, notation(&high)),
                format!("cofactor {}=0: {}", x, notation(&low)),
                format!("difference: {}", notation(&simplify_pair("^", high, low))),
            ]);
        }
        let mut names = BTreeSet::new();
        variables(&f, &mut names);
        if let Some(g) = &g {
            variables(g, &mut names);
        }
        let vars: Vec<char> = names.into_iter().collect();
        if !["PRINT", "NNF", "DUAL", "SIMPLIFY", "CLAUSES", "DP"].contains(&command)
            && vars.len() >= 9
        {
            return Err(format!("too many variables: {}", vars.len()));
        }
        match command {
            "PRINT" => {
                fn measure(f: &F) -> (usize, usize) {
                    let a = f.left.as_ref().map(measure).unwrap_or((0, 0));
                    let b = f.right.as_ref().map(measure).unwrap_or((0, 0));
                    (1 + a.0 + b.0, 1 + a.1.max(b.1))
                }
                let (size, depth) = measure(&f);
                return Ok(vec![
                    format!("formula: {}", notation(&f)),
                    format!(
                        "variables: {}",
                        if vars.is_empty() {
                            "none".into()
                        } else {
                            vars.iter()
                                .map(char::to_string)
                                .collect::<Vec<_>>()
                                .join(" ")
                        }
                    ),
                    format!("size {} depth {}", size, depth),
                ]);
            }
            "NNF" => {
                return Ok(vec![format!(
                    "nnf: {}",
                    notation(&nnf(&f, true, &mut BTreeMap::new()))
                )]);
            }
            "DUAL" => return Ok(vec![format!("dual: {}", notation(&dual(&f)))]),
            "SIMPLIFY" => {
                return Ok(vec![format!(
                    "simplified: {}",
                    notation(&simplify(&f, &BTreeMap::new()))
                )]);
            }
            "CLAUSES" | "DP" => {
                let normal = nnf(&f, true, &mut BTreeMap::new());
                let mut cs = clauses(&normal, &vars, &mut BTreeMap::new());
                if command == "CLAUSES" {
                    return Ok(vec![format!(
                        "clauses: {}",
                        cover_text(&clause_patterns(&cs, vars.len()), &vars, true)
                    )]);
                }
                let empty = Clause {
                    positive: 0,
                    negative: 0,
                };
                let mut out = vec![format!("start: clauses {}", cs.len())];
                for (i, v) in vars.iter().enumerate() {
                    if cs.is_empty() || cs.contains(&empty) {
                        break;
                    }
                    let bit = 1 << i;
                    let p: Vec<Clause> = cs
                        .iter()
                        .filter(|c| c.positive & bit != 0)
                        .copied()
                        .collect();
                    let q: Vec<Clause> = cs
                        .iter()
                        .filter(|c| c.negative & bit != 0)
                        .copied()
                        .collect();
                    let mut resolvents = BTreeSet::new();
                    for a in &p {
                        for b in &q {
                            let c = Clause {
                                positive: (a.positive | b.positive) & !bit,
                                negative: (a.negative | b.negative) & !bit,
                            };
                            if c.positive & c.negative == 0 {
                                resolvents.insert(c);
                            }
                        }
                    }
                    cs.retain(|c| (c.positive | c.negative) & bit == 0);
                    let count = resolvents.len();
                    cs.extend(resolvents);
                    cs = tidy(cs);
                    out.push(format!(
                        "eliminate {}: resolvents {} clauses {}",
                        v,
                        count,
                        cs.len()
                    ));
                }
                out.push(format!(
                    "result: {}",
                    if cs.contains(&empty) {
                        "unsatisfiable"
                    } else {
                        "satisfiable"
                    }
                ));
                return Ok(out);
            }
            _ => (),
        }
        let values: Vec<u8> = (0..1 << vars.len())
            .map(|r| evaluate(&f, &vars, r))
            .collect();
        let other: Vec<u8> = g
            .as_ref()
            .map(|g| (0..values.len()).map(|r| evaluate(g, &vars, r)).collect())
            .unwrap_or_default();
        let models: Vec<usize> = (0..values.len()).filter(|r| values[*r] == 1).collect();
        let false_rows: Vec<usize> = (0..values.len()).filter(|r| values[*r] == 0).collect();
        let output = match command {
            "TABLE" => {
                std::iter::once(vars.iter().map(|v| format!("{} ", v)).collect::<String>() + "| F")
                    .chain((0..values.len()).map(|r| {
                        pattern(r, vars.len())
                            .chars()
                            .map(|c| format!("{} ", c))
                            .collect::<String>()
                            + &format!("| {}", values[r])
                    }))
                    .collect()
            }
            "MINTERMS" | "MAXTERMS" => {
                let rows = if command == "MINTERMS" {
                    &models
                } else {
                    &false_rows
                };
                vec![format!(
                    "{}: {}",
                    command.to_lowercase(),
                    if rows.is_empty() {
                        "none".into()
                    } else {
                        rows.iter()
                            .map(usize::to_string)
                            .collect::<Vec<_>>()
                            .join(" ")
                    }
                )]
            }
            "DNF" | "CNF" => {
                let pos = command == "CNF";
                let rows = if pos { &false_rows } else { &models };
                let ps = rows
                    .iter()
                    .map(|r| {
                        let p = pattern(*r, vars.len());
                        if pos { invert(&p) } else { p }
                    })
                    .collect::<Vec<_>>();
                vec![format!(
                    "{}: {}",
                    command.to_lowercase(),
                    cover_text(&ps, &vars, pos)
                )]
            }
            "ANF" => {
                let c = coefficients(&values);
                let mut ps: Vec<String> = (0..c.len())
                    .filter(|s| c[*s] == 1)
                    .map(|s| pattern(s, vars.len()).replace('0', "-"))
                    .collect();
                ps.sort_by_key(|p| (literals(p), pattern_key(p)));
                vec![format!(
                    "anf: {}",
                    if ps.is_empty() {
                        "0".into()
                    } else {
                        ps.iter()
                            .map(|p| term_text(p, &vars, false))
                            .collect::<Vec<_>>()
                            .join(" ^ ")
                    }
                )]
            }
            "SAT" => vec![models.first().map_or("unsatisfiable".into(), |r| {
                format!("satisfiable: {}", assignment(*r, &vars))
            })],
            "TAUT" => vec![false_rows.first().map_or("tautology".into(), |r| {
                format!("not a tautology: {}", assignment(*r, &vars))
            })],
            "COUNT" => vec![format!("models: {} of {}", models.len(), values.len())],
            "EQUIV" | "IMPLIES" => {
                let r = (0..values.len()).find(|r| {
                    if command == "EQUIV" {
                        values[*r] != other[*r]
                    } else {
                        values[*r] == 1 && other[*r] == 0
                    }
                });
                vec![
                    r.map_or(
                        if command == "EQUIV" {
                            "equivalent"
                        } else {
                            "implies"
                        }
                        .into(),
                        |r| {
                            if command == "EQUIV" {
                                format!(
                                    "not equivalent: {} f={} g={}",
                                    assignment(r, &vars),
                                    values[r],
                                    other[r]
                                )
                            } else {
                                format!("does not imply: {}", assignment(r, &vars))
                            }
                        },
                    ),
                ]
            }
            "MINIMIZE" | "MINDC" | "MINPOS" => {
                let on: Vec<usize> = (0..values.len())
                    .filter(|r| {
                        if command == "MINPOS" {
                            values[*r] == 0
                        } else {
                            values[*r] == 1 && (other.is_empty() || other[*r] == 0)
                        }
                    })
                    .collect();
                let dc: Vec<usize> = (0..other.len()).filter(|r| other[*r] == 1).collect();
                minimize(&vars, &on, &dc, command == "MINPOS")
            }
            "PROPS" => {
                let dependencies: Vec<String> = vars
                    .iter()
                    .enumerate()
                    .filter(|(i, _)| {
                        (0..values.len())
                            .any(|r| values[r] != values[r ^ (1 << (vars.len() - 1 - i))])
                    })
                    .map(|(_, v)| v.to_string())
                    .collect();
                let c = coefficients(&values);
                let mut by_weight = BTreeMap::new();
                let mut symmetric = true;
                for (r, &v) in values.iter().enumerate() {
                    if by_weight
                        .insert(r.count_ones(), v)
                        .is_some_and(|old| old != v)
                    {
                        symmetric = false;
                    }
                }
                let props = [
                    ("zero-preserving", values[0] == 0),
                    ("one-preserving", *values.last().unwrap() == 1),
                    (
                        "self-dual",
                        (0..values.len()).all(|r| values[r] != values[values.len() - 1 - r]),
                    ),
                    (
                        "monotone",
                        (0..values.len()).all(|r| {
                            (0..vars.len())
                                .all(|i| r & (1 << i) != 0 || values[r] <= values[r | (1 << i)])
                        }),
                    ),
                    (
                        "linear",
                        (0..c.len()).all(|s| c[s] == 0 || s.count_ones() <= 1),
                    ),
                    ("symmetric", symmetric),
                ];
                std::iter::once(format!(
                    "depends: {}",
                    if dependencies.is_empty() {
                        "none".into()
                    } else {
                        dependencies.join(" ")
                    }
                ))
                .chain(
                    props
                        .iter()
                        .map(|(n, v)| format!("{}: {}", n, if *v { "yes" } else { "no" })),
                )
                .collect()
            }
            "KMAP" => {
                if !(2..=4).contains(&vars.len()) {
                    return Err("kmap needs 2 to 4 variables".into());
                }
                let p = vars.len() / 2;
                let q = vars.len() - p;
                let mut out = vec![format!(
                    "{}\\{}{}",
                    vars[..p].iter().collect::<String>(),
                    vars[p..].iter().collect::<String>(),
                    (0..1 << q)
                        .map(|i| " ".to_string() + &pattern(i ^ (i / 2), q))
                        .collect::<String>()
                )];
                for i in 0..1 << p {
                    let r = i ^ (i / 2);
                    let mut s = pattern(r, p) + &" ".repeat(q + 1);
                    for j in 0..1 << q {
                        s += &format!("{}{}", " ".repeat(q), values[(r << q) | (j ^ (j / 2))]);
                    }
                    out.push(s);
                }
                out
            }
            "BDD" => {
                fn build(
                    level: usize,
                    values: &[u8],
                    nodes: &mut Vec<(usize, usize, usize)>,
                ) -> usize {
                    if values.len() == 1 {
                        return values[0] as usize;
                    }
                    let lo = build(level + 1, &values[..values.len() / 2], nodes);
                    let hi = build(level + 1, &values[values.len() / 2..], nodes);
                    if lo == hi {
                        return lo;
                    }
                    let triple = (level, lo, hi);
                    if let Some(i) = nodes.iter().position(|n| *n == triple) {
                        i + 2
                    } else {
                        nodes.push(triple);
                        nodes.len() + 1
                    }
                }
                let mut nodes = Vec::new();
                let root = build(0, &values, &mut nodes);
                let mut paths = vec![0usize, 1];
                let mut out = vec![format!("nodes: {}", nodes.len())];
                for (i, &(v, lo, hi)) in nodes.iter().enumerate() {
                    out.push(format!("{} = ite({}, {}, {})", i + 2, vars[v], hi, lo));
                    paths.push(paths[lo] + paths[hi]);
                }
                out.push(format!("root: {}", root));
                out.push(format!("paths: {}", paths[root]));
                out
            }
            _ => unreachable!(),
        };
        Ok(output)
    }
}
fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let count: usize = lines.next().unwrap().parse().unwrap();
    let mut workbench = Workbench {
        definitions: BTreeMap::new(),
    };
    for line in lines.take(count) {
        match workbench.command(line) {
            Ok(out) => {
                for line in out {
                    println!("{}", line);
                }
            }
            Err(e) => println!("error: {}", e),
        }
    }
}
