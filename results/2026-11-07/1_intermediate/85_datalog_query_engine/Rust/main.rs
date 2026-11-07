use std::collections::{BTreeMap, BTreeSet};
use std::io::{self, Read};
const RESERVED: [&str; 17] = [
    "not",
    "mod",
    "count",
    "sum",
    "min",
    "max",
    "retract",
    "dump",
    "why",
    "forget",
    "listing",
    "strata",
    "stats",
    "check",
    "predicates",
    "undo",
    "halt",
];

#[derive(Clone, PartialEq, Eq, PartialOrd, Ord)]
enum Value {
    Integer(i64),
    Symbol(String),
}
impl Value {
    fn text(&self) -> String {
        match self {
            Self::Integer(n) => n.to_string(),
            Self::Symbol(s) => {
                if s.as_bytes().first().is_some_and(u8::is_ascii_lowercase)
                    && s.bytes().all(word_character)
                    && !RESERVED.contains(&s.as_str())
                {
                    s.clone()
                } else {
                    format!("\"{}\"", s)
                }
            }
        }
    }
}
type Tuple = Vec<Value>;

type Environment = BTreeMap<String, Value>;

type Database = BTreeMap<String, BTreeSet<Tuple>>;

type Derivations = BTreeMap<String, BTreeMap<Tuple, (usize, usize)>>;

#[derive(Clone)]
enum Term {
    Constant(Value),
    Variable(String),
    Anonymous,
}
impl Term {
    fn text(&self, env: Option<&Environment>) -> String {
        match self {
            Self::Constant(v) => v.text(),
            Self::Variable(n) => env
                .and_then(|e| e.get(n))
                .map_or_else(|| n.clone(), Value::text),
            Self::Anonymous => "_".into(),
        }
    }
    fn value(&self, env: &Environment) -> Option<Value> {
        match self {
            Self::Constant(v) => Some(v.clone()),
            Self::Variable(n) => env.get(n).cloned(),
            Self::Anonymous => None,
        }
    }
    fn variables(&self, names: &mut Vec<String>) {
        if let Self::Variable(n) = self {
            names.push(n.clone());
        }
    }
}
#[derive(Clone)]
enum Expression {
    Term(Term),
    Parentheses(Box<Expression>),
    Operation(String, Box<Expression>, Box<Expression>),
}
impl Expression {
    fn text(&self, env: Option<&Environment>) -> String {
        match self {
            Self::Term(t) => t.text(env),
            Self::Parentheses(e) => format!("({})", e.text(env)),
            Self::Operation(op, a, b) => format!("{} {} {}", a.text(env), op, b.text(env)),
        }
    }
    fn variables(&self, names: &mut Vec<String>) {
        match self {
            Self::Term(t) => t.variables(names),
            Self::Parentheses(e) => e.variables(names),
            Self::Operation(_, a, b) => {
                a.variables(names);
                b.variables(names);
            }
        }
    }
    fn anonymous(&self) -> bool {
        match self {
            Self::Term(t) => matches!(t, Term::Anonymous),
            Self::Parentheses(e) => e.anonymous(),
            Self::Operation(_, a, b) => a.anonymous() || b.anonymous(),
        }
    }
    fn value(&self, env: &Environment) -> Option<Value> {
        match self {
            Self::Term(t) => t.value(env),
            Self::Parentheses(e) => e.value(env),
            Self::Operation(op, a, b) => {
                let (Value::Integer(a), Value::Integer(b)) = (a.value(env)?, b.value(env)?) else {
                    return None;
                };
                Some(Value::Integer(match op.as_str() {
                    "+" => a + b,
                    "-" => a - b,
                    "*" => a * b,
                    "/" | "mod" => {
                        if b == 0 {
                            return None;
                        }
                        let q = a / b
                            - if a % b != 0 && (a < 0) != (b < 0) {
                                1
                            } else {
                                0
                            };
                        if op == "/" { q } else { a - b * q }
                    }
                    _ => unreachable!(),
                }))
            }
        }
    }
}
#[derive(Clone)]
struct Atom {
    name: String,
    terms: Vec<Term>,
}
impl Atom {
    fn text(&self, env: Option<&Environment>) -> String {
        if self.terms.is_empty() {
            self.name.clone()
        } else {
            format!(
                "{}({})",
                self.name,
                self.terms
                    .iter()
                    .map(|t| t.text(env))
                    .collect::<Vec<_>>()
                    .join(", ")
            )
        }
    }
    fn variables(&self, names: &mut Vec<String>) {
        for t in &self.terms {
            t.variables(names);
        }
    }
    fn tuple(&self, env: &Environment) -> Tuple {
        self.terms.iter().map(|t| t.value(env).unwrap()).collect()
    }
    fn matching(&self, tuple: &Tuple, env: &Environment) -> Option<Environment> {
        let mut result = env.clone();
        for (term, value) in self.terms.iter().zip(tuple) {
            match term {
                Term::Constant(v) if v != value => return None,
                Term::Variable(n) => {
                    if let Some(v) = result.get(n) {
                        if v != value {
                            return None;
                        }
                    } else {
                        result.insert(n.clone(), value.clone());
                    }
                }
                _ => (),
            }
        }
        Some(result)
    }
}
fn tuple_text(name: &str, tuple: &Tuple) -> String {
    Atom {
        name: name.into(),
        terms: tuple.iter().cloned().map(Term::Constant).collect(),
    }
    .text(None)
}
#[derive(Clone)]
enum Literal {
    Atom(Atom, bool),
    Comparison(String, Expression, Expression),
}
impl Literal {
    fn variables(&self, names: &mut Vec<String>) {
        match self {
            Self::Atom(a, _) => a.variables(names),
            Self::Comparison(_, a, b) => {
                a.variables(names);
                b.variables(names);
            }
        }
    }
    fn text(&self, env: Option<&Environment>) -> String {
        match self {
            Self::Atom(a, negative) => {
                format!("{}{}", if *negative { "not " } else { "" }, a.text(env))
            }
            Self::Comparison(op, a, b) => format!("{} {} {}", a.text(env), op, b.text(env)),
        }
    }
    fn holds(&self, env: &Environment, data: &Database) -> bool {
        match self {
            Self::Atom(a, true) => !data[&a.name].iter().any(|t| a.matching(t, env).is_some()),
            Self::Comparison(op, a, b) => {
                let (Some(a), Some(b)) = (a.value(env), b.value(env)) else {
                    return false;
                };
                match op.as_str() {
                    "=" => a == b,
                    "!=" => a != b,
                    _ => {
                        let (Value::Integer(a), Value::Integer(b)) = (a, b) else {
                            return false;
                        };
                        match op.as_str() {
                            "<" => a < b,
                            "<=" => a <= b,
                            ">" => a > b,
                            ">=" => a >= b,
                            _ => unreachable!(),
                        }
                    }
                }
            }
            _ => true,
        }
    }
}
#[derive(Clone)]
struct Rule {
    number: usize,
    head: Option<Atom>,
    body: Vec<Literal>,
}
impl Rule {
    fn text(&self) -> String {
        format!(
            "{}:- {}.",
            self.head
                .as_ref()
                .map_or(String::new(), |a| a.text(None) + " "),
            self.body
                .iter()
                .map(|l| l.text(None))
                .collect::<Vec<_>>()
                .join(", ")
        )
    }
    fn variables(&self) -> Vec<String> {
        let mut result = Vec::new();
        if let Some(a) = &self.head {
            a.variables(&mut result);
        }
        for l in &self.body {
            l.variables(&mut result);
        }
        result
    }
    fn atoms(&self) -> Vec<&Atom> {
        self.head
            .iter()
            .chain(self.body.iter().filter_map(|l| match l {
                Literal::Atom(a, _) => Some(a),
                _ => None,
            }))
            .collect()
    }
}
#[derive(Clone)]
struct Token {
    kind: String,
    text: String,
}
fn word_character(c: u8) -> bool {
    c.is_ascii_alphanumeric() || c == b'_'
}
fn lex(line: &str) -> Result<Vec<Token>, String> {
    let b = line.as_bytes();
    let mut at = 0;
    let mut tokens = Vec::new();
    while at < b.len() {
        if b[at] == b' ' {
            at += 1;
            continue;
        }
        if b[at] == b'%' {
            break;
        }
        let start = at;
        let kind;
        if b[at] == b'"' {
            at += 1;
            while at < b.len() && b[at] != b'"' {
                at += 1;
            }
            if at == b.len() {
                return Err("unterminated string".into());
            }
            at += 1;
            kind = "string".into();
        } else if at + 1 < b.len() && [":-", "?-", "!=", "<=", ">="].contains(&&line[at..at + 2]) {
            at += 2;
            kind = line[start..at].into();
        } else if b"(),.:=<>+-*/".contains(&b[at]) {
            at += 1;
            kind = line[start..at].into();
        } else if word_character(b[at]) {
            at += 1;
            while at < b.len() && word_character(b[at]) {
                at += 1;
            }
            let word = &line[start..at];
            kind = if b[start].is_ascii_lowercase() {
                if RESERVED.contains(&word) {
                    word.into()
                } else {
                    "name".into()
                }
            } else if b[start].is_ascii_uppercase() {
                "variable".into()
            } else if word == "_" {
                "anonymous".into()
            } else if word.bytes().all(|c| c.is_ascii_digit()) {
                if word.parse::<u64>().unwrap() > 1_000_000_000 {
                    return Err(format!("integer out of range '{}'", word));
                }
                "integer".into()
            } else {
                return Err(format!("bad token '{}'", word));
            };
        } else {
            return Err(format!("bad character '{}'", b[at] as char));
        }
        tokens.push(Token {
            kind,
            text: line[start..at].into(),
        });
    }
    Ok(tokens)
}
enum Statement {
    Clause(Rule),
    Query(String, String, Vec<Literal>),
    AtomCommand(String, Atom),
    Command(String, String),
}
struct Parser {
    tokens: Vec<Token>,
    at: usize,
}
impl Parser {
    fn kind(&self) -> &str {
        self.tokens.get(self.at).map_or("end", |t| t.kind.as_str())
    }
    fn error(&self) -> String {
        self.tokens
            .get(self.at)
            .map_or("syntax error at end of line".into(), |t| {
                format!("syntax error at '{}'", t.text)
            })
    }
    fn take(&mut self, kind: &str) -> Result<Token, String> {
        if self.kind() != kind {
            return Err(self.error());
        }
        let token = self.tokens[self.at].clone();
        self.at += 1;
        Ok(token)
    }
    fn term(&mut self) -> Result<Term, String> {
        Ok(match self.kind() {
            "name" => Term::Constant(Value::Symbol(self.take("name")?.text)),
            "string" => {
                let s = self.take("string")?.text;
                Term::Constant(Value::Symbol(s[1..s.len() - 1].into()))
            }
            "integer" => {
                Term::Constant(Value::Integer(self.take("integer")?.text.parse().unwrap()))
            }
            "-" => {
                self.take("-")?;
                Term::Constant(Value::Integer(
                    -self.take("integer")?.text.parse::<i64>().unwrap(),
                ))
            }
            "variable" => Term::Variable(self.take("variable")?.text),
            "anonymous" => {
                self.take("anonymous")?;
                Term::Anonymous
            }
            _ => return Err(self.error()),
        })
    }
    fn atom(&mut self) -> Result<Atom, String> {
        let name = self.take("name")?.text;
        let mut terms = Vec::new();
        if self.kind() == "(" {
            self.take("(")?;
            terms.push(self.term()?);
            while self.kind() == "," {
                self.take(",")?;
                terms.push(self.term()?);
            }
            self.take(")")?;
        }
        Ok(Atom { name, terms })
    }
    fn factor(&mut self) -> Result<Expression, String> {
        if self.kind() == "(" {
            self.take("(")?;
            let e = self.expression()?;
            self.take(")")?;
            Ok(Expression::Parentheses(Box::new(e)))
        } else {
            Ok(Expression::Term(self.term()?))
        }
    }
    fn product(&mut self) -> Result<Expression, String> {
        let mut e = self.factor()?;
        while ["*", "/", "mod"].contains(&self.kind()) {
            let op = self.tokens[self.at].text.clone();
            self.at += 1;
            e = Expression::Operation(op, Box::new(e), Box::new(self.factor()?));
        }
        Ok(e)
    }
    fn expression(&mut self) -> Result<Expression, String> {
        let mut e = self.product()?;
        while ["+", "-"].contains(&self.kind()) {
            let op = self.tokens[self.at].text.clone();
            self.at += 1;
            e = Expression::Operation(op, Box::new(e), Box::new(self.product()?));
        }
        Ok(e)
    }
    fn literal(&mut self) -> Result<Literal, String> {
        if self.kind() == "not" {
            self.take("not")?;
            return Ok(Literal::Atom(self.atom()?, true));
        }
        let following = self
            .tokens
            .get(self.at + 1)
            .map_or("end", |t| t.kind.as_str());
        if self.kind() == "name"
            && !["=", "!=", "<", "<=", ">", ">=", "+", "-", "*", "/", "mod"].contains(&following)
        {
            return Ok(Literal::Atom(self.atom()?, false));
        }
        let a = self.expression()?;
        if !["=", "!=", "<", "<=", ">", ">="].contains(&self.kind()) {
            return Err(self.error());
        }
        let op = self.tokens[self.at].text.clone();
        self.at += 1;
        Ok(Literal::Comparison(op, a, self.expression()?))
    }
    fn body(&mut self) -> Result<Vec<Literal>, String> {
        let mut result = vec![self.literal()?];
        while self.kind() == "," {
            self.take(",")?;
            result.push(self.literal()?);
        }
        Ok(result)
    }
    fn statement(&mut self) -> Result<Statement, String> {
        let result = match self.kind() {
            "name" => {
                let head = self.atom()?;
                let body = if self.kind() == ":-" {
                    self.take(":-")?;
                    self.body()?
                } else {
                    Vec::new()
                };
                Statement::Clause(Rule {
                    number: 0,
                    head: Some(head),
                    body,
                })
            }
            ":-" => {
                self.take(":-")?;
                Statement::Clause(Rule {
                    number: 0,
                    head: None,
                    body: self.body()?,
                })
            }
            "?-" => {
                self.take("?-")?;
                let mut aggregate = String::new();
                let mut variable = String::new();
                if ["count", "sum", "min", "max"].contains(&self.kind()) {
                    aggregate = self.tokens[self.at].text.clone();
                    self.at += 1;
                    if aggregate != "count" {
                        variable = self.take("variable")?.text;
                        self.take(":")?;
                    }
                }
                Statement::Query(aggregate, variable, self.body()?)
            }
            "retract" | "why" => {
                let command = self.tokens[self.at].text.clone();
                self.at += 1;
                Statement::AtomCommand(command, self.atom()?)
            }
            "dump" | "forget" | "listing" | "strata" | "stats" | "check" | "predicates"
            | "undo" | "halt" => {
                let command = self.tokens[self.at].text.clone();
                self.at += 1;
                let argument = match command.as_str() {
                    "dump" => self.take("name")?.text,
                    "forget" => self.take("integer")?.text,
                    "listing" if self.kind() == "name" => self.take("name")?.text,
                    _ => String::new(),
                };
                Statement::Command(command, argument)
            }
            _ => return Err(self.error()),
        };
        self.take(".")?;
        if self.kind() != "end" {
            return Err(self.error());
        }
        Ok(result)
    }
}
#[derive(Clone, Default)]
struct State {
    predicates: BTreeMap<String, usize>,
    facts: Database,
    rules: Vec<Rule>,
}
fn variables(body: &[Literal]) -> Vec<String> {
    let mut all = Vec::new();
    for l in body {
        l.variables(&mut all);
    }
    unique(all)
}
fn unique(all: Vec<String>) -> Vec<String> {
    let mut seen = BTreeSet::new();
    all.into_iter().filter(|n| seen.insert(n.clone())).collect()
}
fn safety(rule: &Rule, aggregate: &str) -> Result<(), String> {
    if rule
        .head
        .as_ref()
        .is_some_and(|a| a.terms.iter().any(|t| matches!(t, Term::Anonymous)))
    {
        return Err("anonymous variable in head".into());
    }
    if rule
        .body
        .iter()
        .any(|l| matches!(l, Literal::Comparison(_, a, b) if a.anonymous() || b.anonymous()))
    {
        return Err("anonymous variable in comparison".into());
    }
    let mut bound = Vec::new();
    for l in &rule.body {
        if let Literal::Atom(a, false) = l {
            a.variables(&mut bound);
        }
    }
    let mut required = Vec::new();
    if let Some(a) = &rule.head {
        a.variables(&mut required);
    } else if !aggregate.is_empty() {
        required.push(aggregate.into());
    }
    for l in &rule.body {
        if !matches!(l, Literal::Atom(_, false)) {
            l.variables(&mut required);
        }
    }
    for n in required {
        if !bound.contains(&n) {
            return Err(format!("unsafe variable {}", n));
        }
    }
    Ok(())
}
fn strata(state: &State) -> Option<BTreeMap<String, usize>> {
    let mut result: BTreeMap<String, usize> =
        state.predicates.keys().map(|n| (n.clone(), 0)).collect();
    if result.is_empty() {
        return Some(result);
    }
    for _ in 0..state.predicates.len() {
        let mut changed = false;
        for r in &state.rules {
            if let Some(h) = &r.head {
                for l in &r.body {
                    if let Literal::Atom(a, negative) = l {
                        let value = result[&a.name] + if *negative { 1 } else { 0 };
                        if value > result[&h.name] {
                            result.insert(h.name.clone(), value);
                            changed = true;
                        }
                    }
                }
            }
        }
        if !changed {
            return Some(result);
        }
    }
    None
}
fn solutions(
    body: &[Literal],
    data: &Database,
    derivations: &Derivations,
    before: Option<usize>,
) -> BTreeSet<Environment> {
    fn visit(
        body: &[Literal],
        data: &Database,
        derivations: &Derivations,
        before: Option<usize>,
        remaining: &[usize],
        env: &Environment,
        output: &mut BTreeSet<Environment>,
    ) {
        for l in body {
            if !matches!(l, Literal::Atom(_, false)) {
                let mut names = Vec::new();
                l.variables(&mut names);
                if names.iter().all(|n| env.contains_key(n)) && !l.holds(env, data) {
                    return;
                }
            }
        }
        if remaining.is_empty() {
            output.insert(env.clone());
            return;
        }
        let mut best = None;
        let mut candidates = BTreeSet::new();
        for &i in remaining {
            let Literal::Atom(a, false) = &body[i] else {
                unreachable!()
            };
            let possible: BTreeSet<Environment> = data[&a.name]
                .iter()
                .filter(|t| before.is_none_or(|m| derivations[&a.name][*t].0 < m))
                .filter_map(|t| a.matching(t, env))
                .collect();
            if best.is_none() || possible.len() < candidates.len() {
                best = Some(i);
                candidates = possible;
            }
        }
        let rest: Vec<usize> = remaining
            .iter()
            .copied()
            .filter(|i| Some(*i) != best)
            .collect();
        for next in candidates {
            visit(body, data, derivations, before, &rest, &next, output);
        }
    }
    let remaining: Vec<usize> = body
        .iter()
        .enumerate()
        .filter(|(_, l)| matches!(l, Literal::Atom(_, false)))
        .map(|(i, _)| i)
        .collect();
    let mut output = BTreeSet::new();
    visit(
        body,
        data,
        derivations,
        before,
        &remaining,
        &Environment::new(),
        &mut output,
    );
    output
}
struct Model {
    data: Database,
    derivations: Derivations,
    strata: BTreeMap<String, usize>,
    rounds: Vec<usize>,
    additions: Vec<usize>,
}
impl Model {
    fn new(state: &State) -> Self {
        let levels = strata(state).unwrap();
        let maximum = levels.values().copied().max().unwrap_or(0);
        let mut model = Self {
            data: state.facts.clone(),
            derivations: state
                .facts
                .iter()
                .map(|(p, ts)| (p.clone(), ts.iter().cloned().map(|t| (t, (0, 0))).collect()))
                .collect(),
            strata: levels,
            rounds: vec![0; maximum + 1],
            additions: vec![0; maximum + 1],
        };
        let mut serial = 0;
        for k in 0..=maximum {
            loop {
                let mut added: BTreeMap<(String, Tuple), usize> = BTreeMap::new();
                for r in &state.rules {
                    let Some(h) = &r.head else { continue };
                    if model.strata[&h.name] != k {
                        continue;
                    }
                    for env in solutions(&r.body, &model.data, &model.derivations, None) {
                        let tuple = h.tuple(&env);
                        if !model.data[&h.name].contains(&tuple) {
                            let entry = added.entry((h.name.clone(), tuple)).or_insert(r.number);
                            *entry = (*entry).min(r.number);
                        }
                    }
                }
                if added.is_empty() {
                    break;
                }
                serial += 1;
                model.rounds[k] += 1;
                model.additions[k] += added.len();
                for ((name, tuple), rule) in added {
                    model.data.get_mut(&name).unwrap().insert(tuple.clone());
                    model
                        .derivations
                        .get_mut(&name)
                        .unwrap()
                        .insert(tuple, (serial, rule));
                }
            }
        }
        model
    }
    fn answers(&self, body: &[Literal]) -> (Vec<String>, BTreeSet<Tuple>) {
        let names = variables(body);
        let answers = solutions(body, &self.data, &self.derivations, None)
            .iter()
            .map(|env| names.iter().map(|n| env[n].clone()).collect())
            .collect();
        (names, answers)
    }
    fn proof(
        &self,
        state: &State,
        name: &str,
        tuple: &Tuple,
        depth: usize,
        output: &mut Vec<String>,
    ) {
        let (round, _) = self.derivations[name][tuple];
        let prefix = "  ".repeat(depth) + &tuple_text(name, tuple);
        if round == 0 {
            output.push(prefix + " [fact]");
            return;
        }
        for r in state
            .rules
            .iter()
            .filter(|r| r.head.as_ref().is_some_and(|a| a.name == name))
        {
            let order = unique(r.variables());
            let mut candidates: Vec<Environment> =
                solutions(&r.body, &self.data, &self.derivations, Some(round))
                    .into_iter()
                    .filter(|env| r.head.as_ref().unwrap().tuple(env) == *tuple)
                    .collect();
            candidates.sort_by_key(|env| order.iter().map(|n| env[n].clone()).collect::<Tuple>());
            if let Some(env) = candidates.first() {
                output.push(format!("{} [rule {}]", prefix, r.number));
                for l in &r.body {
                    if let Literal::Atom(a, false) = l {
                        let child = self.data[&a.name]
                            .iter()
                            .find(|t| {
                                self.derivations[&a.name][*t].0 < round
                                    && a.matching(t, env).is_some()
                            })
                            .unwrap();
                        self.proof(state, &a.name, child, depth + 1, output);
                    } else {
                        output.push("  ".repeat(depth + 1) + &l.text(Some(env)));
                    }
                }
                return;
            }
        }
    }
}
fn answer_text(names: &[String], tuple: &Tuple) -> String {
    names
        .iter()
        .zip(tuple)
        .map(|(n, v)| format!("{} = {}", n, v.text()))
        .collect::<Vec<_>>()
        .join(", ")
}
struct Engine {
    state: State,
    next_rule: usize,
    history: Vec<(State, usize)>,
}
impl Engine {
    fn predicate_check(
        &self,
        atoms: &[&Atom],
        register: bool,
    ) -> Result<BTreeMap<String, usize>, String> {
        let mut predicates = self.state.predicates.clone();
        for a in atoms {
            if let Some(&arity) = predicates.get(&a.name) {
                if arity != a.terms.len() {
                    return Err(format!(
                        "arity mismatch for {}: expected {}, got {}",
                        a.name,
                        arity,
                        a.terms.len()
                    ));
                }
            } else if register {
                predicates.insert(a.name.clone(), a.terms.len());
            } else {
                return Err(format!("unknown predicate {}", a.name));
            }
        }
        Ok(predicates)
    }
    fn save(&mut self, line: usize) {
        self.history.push((self.state.clone(), line));
    }
    fn clause(&mut self, mut rule: Rule, line: usize) -> Result<Vec<String>, String> {
        let predicates = self.predicate_check(&rule.atoms(), true)?;
        safety(&rule, "")?;
        if rule.body.is_empty() {
            let a = rule.head.as_ref().unwrap();
            let tuple = a.tuple(&Environment::new());
            if !self
                .state
                .facts
                .get(&a.name)
                .is_some_and(|ts| ts.contains(&tuple))
            {
                self.save(line);
                self.state.predicates = predicates;
                self.state
                    .facts
                    .entry(a.name.clone())
                    .or_default()
                    .insert(tuple);
            }
            return Ok(Vec::new());
        }
        let notation = rule.text();
        if let Some(r) = self.state.rules.iter().find(|r| r.text() == notation) {
            return Err(format!("duplicate of rule {}", r.number));
        }
        rule.number = self.next_rule;
        let mut proposed = self.state.clone();
        proposed.predicates = predicates;
        proposed.rules.push(rule.clone());
        for n in proposed.predicates.keys() {
            proposed.facts.entry(n.clone()).or_default();
        }
        if strata(&proposed).is_none() {
            return Err(format!(
                "negative cycle through {}",
                rule.head.as_ref().unwrap().name
            ));
        }
        self.save(line);
        self.state = proposed;
        self.next_rule += 1;
        let all = rule.variables();
        Ok(unique(all.clone())
            .into_iter()
            .filter(|n| all.iter().filter(|v| *v == n).count() == 1)
            .map(|n| format!("WARNING line {}: singleton variable {}", line, n))
            .collect())
    }
    fn execute(&mut self, statement: Statement, line: usize) -> Result<Vec<String>, String> {
        match statement {
            Statement::Clause(rule) => self.clause(rule, line),
            Statement::Query(aggregate, variable, body) => {
                let rule = Rule {
                    number: 0,
                    head: None,
                    body,
                };
                self.predicate_check(&rule.atoms(), false)?;
                safety(&rule, &variable)?;
                let (names, answers) = Model::new(&self.state).answers(&rule.body);
                match aggregate.as_str() {
                    "count" => Ok(vec![answers.len().to_string()]),
                    "sum" => {
                        let i = names.iter().position(|n| n == &variable).unwrap();
                        let mut total = 0;
                        for row in answers {
                            let Value::Integer(n) = &row[i] else {
                                return Err("non-integer value in sum".into());
                            };
                            total += *n;
                        }
                        Ok(vec![total.to_string()])
                    }
                    "min" | "max" => {
                        let i = names.iter().position(|n| n == &variable).unwrap();
                        let mut values: Vec<&Value> = answers.iter().map(|r| &r[i]).collect();
                        values.sort();
                        Ok(vec![if values.is_empty() {
                            "no answers".into()
                        } else if aggregate == "min" {
                            values[0].text()
                        } else {
                            values.last().unwrap().text()
                        }])
                    }
                    _ if names.is_empty() => Ok(vec![
                        if answers.is_empty() {
                            "false."
                        } else {
                            "true."
                        }
                        .into(),
                    ]),
                    _ => {
                        let mut out: Vec<String> =
                            answers.iter().map(|t| answer_text(&names, t)).collect();
                        out.push(format!(
                            "{} {}",
                            answers.len(),
                            if answers.len() == 1 {
                                "answer"
                            } else {
                                "answers"
                            }
                        ));
                        Ok(out)
                    }
                }
            }
            Statement::AtomCommand(command, atom) => {
                self.predicate_check(&[&atom], false)?;
                if command == "retract" {
                    let tuples: Vec<Tuple> = self.state.facts[&atom.name]
                        .iter()
                        .filter(|t| atom.matching(t, &Environment::new()).is_some())
                        .cloned()
                        .collect();
                    if tuples.is_empty() {
                        return Err("no matching facts".into());
                    }
                    self.save(line);
                    for t in &tuples {
                        self.state.facts.get_mut(&atom.name).unwrap().remove(t);
                    }
                    Ok(vec![format!(
                        "{} {} retracted",
                        tuples.len(),
                        if tuples.len() == 1 { "fact" } else { "facts" }
                    )])
                } else {
                    if atom.terms.iter().any(|t| !matches!(t, Term::Constant(_))) {
                        return Err("why needs a ground atom".into());
                    }
                    let model = Model::new(&self.state);
                    let tuple = atom.tuple(&Environment::new());
                    if !model.data[&atom.name].contains(&tuple) {
                        return Ok(vec!["false.".into()]);
                    }
                    let mut out = Vec::new();
                    model.proof(&self.state, &atom.name, &tuple, 0, &mut out);
                    Ok(out)
                }
            }
            Statement::Command(command, argument) => self.command(&command, &argument, line),
        }
    }
    fn command(
        &mut self,
        command: &str,
        argument: &str,
        line: usize,
    ) -> Result<Vec<String>, String> {
        if command == "undo" {
            let (state, previous) = self.history.pop().ok_or("nothing to undo")?;
            self.state = state;
            return Ok(vec![format!("undid line {}", previous)]);
        }
        if command == "forget" {
            let n: usize = argument.parse().unwrap();
            let i = self
                .state
                .rules
                .iter()
                .position(|r| r.number == n)
                .ok_or_else(|| format!("no rule {}", n))?;
            self.save(line);
            self.state.rules.remove(i);
            return Ok(Vec::new());
        }
        if ["dump", "listing"].contains(&command)
            && !argument.is_empty()
            && !self.state.predicates.contains_key(argument)
        {
            return Err(format!("unknown predicate {}", argument));
        }
        if command == "listing" {
            let out: Vec<String> = self
                .state
                .rules
                .iter()
                .filter(|r| {
                    argument.is_empty() || r.head.as_ref().is_some_and(|h| h.name == argument)
                })
                .map(|r| format!("{}: {}", r.number, r.text()))
                .collect();
            return Ok(if out.is_empty() {
                vec!["no rules".into()]
            } else {
                out
            });
        }
        let model = Model::new(&self.state);
        let mut out = Vec::new();
        match command {
            "dump" => {
                let tuples = &model.data[argument];
                out.extend(tuples.iter().map(|t| tuple_text(argument, t) + "."));
                out.push(format!(
                    "{} {}",
                    tuples.len(),
                    if tuples.len() == 1 { "tuple" } else { "tuples" }
                ));
            }
            "strata" => {
                if self.state.predicates.is_empty() {
                    return Ok(vec!["no predicates".into()]);
                }
                let edges: BTreeMap<String, Vec<String>> = self
                    .state
                    .predicates
                    .keys()
                    .map(|p| {
                        (
                            p.clone(),
                            self.state
                                .rules
                                .iter()
                                .filter(|r| r.head.as_ref().is_some_and(|h| &h.name == p))
                                .flat_map(|r| {
                                    r.body.iter().filter_map(|l| match l {
                                        Literal::Atom(a, _) => Some(a.name.clone()),
                                        _ => None,
                                    })
                                })
                                .collect(),
                        )
                    })
                    .collect();

                fn reaches(
                    current: &str,
                    target: &str,
                    edges: &BTreeMap<String, Vec<String>>,
                    visited: &mut BTreeSet<String>,
                ) -> bool {
                    if !visited.insert(current.into()) {
                        return false;
                    }
                    edges[current]
                        .iter()
                        .any(|n| n == target || reaches(n, target, edges, visited))
                }
                for k in 0..model.rounds.len() {
                    let names: Vec<String> = model
                        .strata
                        .iter()
                        .filter(|(_, s)| **s == k)
                        .map(|(n, _)| {
                            n.clone()
                                + if reaches(n, n, &edges, &mut BTreeSet::new()) {
                                    "*"
                                } else {
                                    ""
                                }
                        })
                        .collect();
                    out.push(format!("stratum {}: {}", k, names.join(", ")));
                }
            }
            "stats" => {
                let constraints = self.state.rules.iter().filter(|r| r.head.is_none()).count();
                out.push(format!(
                    "facts {}, rules {}, constraints {}, tuples {}",
                    self.state.facts.values().map(BTreeSet::len).sum::<usize>(),
                    self.state.rules.len() - constraints,
                    constraints,
                    model.data.values().map(BTreeSet::len).sum::<usize>()
                ));
                if !self.state.predicates.is_empty() {
                    for k in 0..model.rounds.len() {
                        out.push(format!(
                            "stratum {}: rounds {}, new {}",
                            k, model.rounds[k], model.additions[k]
                        ));
                    }
                }
                for r in self.state.rules.iter().filter(|r| r.head.is_some()) {
                    let count = model
                        .derivations
                        .values()
                        .flat_map(|d| d.values())
                        .filter(|(_, id)| *id == r.number)
                        .count();
                    out.push(format!("rule {}: new {}", r.number, count));
                }
            }
            "predicates" => {
                if self.state.predicates.is_empty() {
                    return Ok(vec!["no predicates".into()]);
                }
                for (p, arity) in &self.state.predicates {
                    out.push(format!(
                        "{}/{}: facts {}, rules {}, tuples {}",
                        p,
                        arity,
                        self.state.facts[p].len(),
                        self.state
                            .rules
                            .iter()
                            .filter(|r| r.head.as_ref().is_some_and(|h| &h.name == p))
                            .count(),
                        model.data[p].len()
                    ));
                }
            }
            "check" => {
                for r in self.state.rules.iter().filter(|r| r.head.is_none()) {
                    let (names, answers) = model.answers(&r.body);
                    out.push(if answers.is_empty() {
                        format!("constraint {}: ok", r.number)
                    } else {
                        format!(
                            "constraint {}: {} {}",
                            r.number,
                            answers.len(),
                            if answers.len() == 1 {
                                "violation"
                            } else {
                                "violations"
                            }
                        )
                    });
                    if !names.is_empty() {
                        out.extend(
                            answers
                                .iter()
                                .map(|t| "  ".to_string() + &answer_text(&names, t)),
                        );
                    }
                }
                if out.is_empty() {
                    out.push("no constraints".into());
                }
            }
            _ => unreachable!(),
        }
        Ok(out)
    }
}
fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut engine = Engine {
        state: State::default(),
        next_rule: 1,
        history: Vec::new(),
    };
    for (line_number, line) in input.lines().enumerate() {
        let result = lex(line).and_then(|tokens| {
            if tokens.is_empty() {
                return Ok(None);
            }
            let statement = Parser { tokens, at: 0 }.statement()?;
            if matches!(&statement, Statement::Command(c, _) if c == "halt") {
                return Ok(Some(None));
            }
            engine
                .execute(statement, line_number + 1)
                .map(|out| Some(Some(out)))
        });
        match result {
            Ok(Some(None)) => break,
            Ok(Some(Some(lines))) => {
                for line in lines {
                    println!("{}", line);
                }
            }
            Ok(None) => (),
            Err(reason) => println!("ERROR line {}: {}", line_number + 1, reason),
        }
    }
}
