use std::collections::{BTreeMap, BTreeSet};
use std::io::{self, Read};
use std::rc::Rc;
type T = Rc<Term>;

#[derive(Clone, PartialEq, Eq)]
enum Term {
    Var(String),
    Macro(String),
    Num(usize),
    Lambda(String, T),
    Apply(T, T),
    Index(usize),
}

fn var(name: &str) -> T {
    Rc::new(Term::Var(name.into()))
}

fn lam(name: &str, body: T) -> T {
    Rc::new(Term::Lambda(name.into(), body))
}

fn app(a: T, b: T) -> T {
    Rc::new(Term::Apply(a, b))
}

fn free(t: &T) -> BTreeSet<String> {
    match t.as_ref() {
        Term::Var(n) => BTreeSet::from([n.clone()]),
        Term::Lambda(n, b) => {
            let mut f = free(b);
            f.remove(n);
            f
        }
        Term::Apply(a, b) => {
            let mut f = free(a);
            f.extend(free(b));
            f
        }
        _ => BTreeSet::new(),
    }
}

fn references(t: &T) -> Vec<String> {
    match t.as_ref() {
        Term::Macro(n) => vec![n.clone()],
        Term::Lambda(_, b) => references(b),
        Term::Apply(a, b) => {
            let mut r = references(a);
            r.extend(references(b));
            r
        }
        _ => Vec::new(),
    }
}

fn printed(t: &T, end: bool, db: bool) -> String {
    match t.as_ref() {
        Term::Var(n) | Term::Macro(n) => n.clone(),
        Term::Num(n) => format!("#{}", n),
        Term::Index(i) => i.to_string(),
        Term::Lambda(_, _) => {
            let mut names = Vec::new();
            let mut body = t;
            while let Term::Lambda(n, b) = body.as_ref() {
                names.push(n.clone());
                body = b;
            }
            let s = if db {
                "\\".repeat(names.len()) + &printed(body, true, true)
            } else {
                format!("\\{}. {}", names.join(" "), printed(body, true, false))
            };
            if end { s } else { format!("({})", s) }
        }
        Term::Apply(a, b) => {
            let left = if matches!(a.as_ref(), Term::Lambda(_, _)) {
                format!("({})", printed(a, true, db))
            } else {
                printed(a, false, db)
            };
            let right = if matches!(b.as_ref(), Term::Apply(_, _)) {
                format!("({})", printed(b, true, db))
            } else {
                printed(b, end, db)
            };
            format!("{} {}", left, right)
        }
    }
}

fn sequence_name(n: usize) -> String {
    let mut s = ((b'a' + (n % 26) as u8) as char).to_string();
    if n >= 26 {
        s.push_str(&(n / 26).to_string());
    }
    s
}

fn canonical(t: &T) -> T {
    fn visit(t: &T, env: &mut Vec<(String, String)>, f: &BTreeSet<String>, next: &mut usize) -> T {
        match t.as_ref() {
            Term::Var(n) => var(env
                .iter()
                .rev()
                .find(|(a, _)| a == n)
                .map_or(n.as_str(), |(_, b)| b.as_str())),
            Term::Lambda(n, b) => {
                while f.contains(&sequence_name(*next)) {
                    *next += 1;
                }
                let fresh = sequence_name(*next);
                *next += 1;
                env.push((n.clone(), fresh.clone()));
                let body = visit(b, env, f, next);
                env.pop();
                lam(&fresh, body)
            }
            Term::Apply(a, b) => app(visit(a, env, f, next), visit(b, env, f, next)),
            _ => t.clone(),
        }
    }
    visit(t, &mut Vec::new(), &free(t), &mut 0)
}

fn debruijn(t: &T, env: &mut Vec<String>) -> T {
    match t.as_ref() {
        Term::Var(n) => env
            .iter()
            .rev()
            .position(|a| a == n)
            .map_or_else(|| t.clone(), |i| Rc::new(Term::Index(i))),
        Term::Lambda(n, b) => {
            env.push(n.clone());
            let result = lam("", debruijn(b, env));
            env.pop();
            result
        }
        Term::Apply(a, b) => app(debruijn(a, env), debruijn(b, env)),
        _ => t.clone(),
    }
}

fn substitute(t: &T, x: &str, n: &T) -> T {
    match t.as_ref() {
        Term::Var(v) => {
            if v == x {
                n.clone()
            } else {
                t.clone()
            }
        }
        Term::Apply(a, b) => app(substitute(a, x, n), substitute(b, x, n)),
        Term::Lambda(y, b) => {
            let fb = free(b);
            let fnn = free(n);
            if y == x || !fb.contains(x) {
                return t.clone();
            }
            if !fnn.contains(y) {
                return lam(y, substitute(b, x, n));
            }
            let base = y.trim_end_matches(|c: char| c.is_ascii_digit());
            let mut i = 1;
            while fb.contains(&format!("{}{}", base, i)) || fnn.contains(&format!("{}{}", base, i))
            {
                i += 1;
            }
            let z = format!("{}{}", base, i);
            lam(&z, substitute(&substitute(b, y, &var(&z)), x, n))
        }
        _ => t.clone(),
    }
}

fn eta(t: &T) -> Option<T> {
    if let Term::Lambda(x, b) = t.as_ref() {
        if let Term::Apply(m, n) = b.as_ref() {
            if matches!(n.as_ref(), Term::Var(v) if v == x) && !free(m).contains(x) {
                return Some(m.clone());
            }
        }
    }
    None
}

fn step(t: &T, strategy: &str, use_eta: bool) -> Option<(T, &'static str)> {
    match t.as_ref() {
        Term::Apply(a, b) => {
            if strategy == "NORMAL" || strategy == "CBN" {
                if let Term::Lambda(x, body) = a.as_ref() {
                    return Some((substitute(body, x, b), "beta"));
                }
            }
            if let Some((n, kind)) = step(a, strategy, use_eta) {
                return Some((app(n, b.clone()), kind));
            }
            if strategy != "CBN" {
                if let Some((n, kind)) = step(b, strategy, use_eta) {
                    return Some((app(a.clone(), n), kind));
                }
            }
            if strategy == "APPLICATIVE" || strategy == "CBV" {
                if let Term::Lambda(x, body) = a.as_ref() {
                    if strategy != "CBV" || matches!(b.as_ref(), Term::Var(_) | Term::Lambda(_, _))
                    {
                        return Some((substitute(body, x, b), "beta"));
                    }
                }
            }
        }
        Term::Lambda(x, b) if strategy == "NORMAL" || strategy == "APPLICATIVE" => {
            if strategy == "NORMAL" && use_eta {
                if let Some(n) = eta(t) {
                    return Some((n, "eta"));
                }
            }
            if let Some((n, kind)) = step(b, strategy, use_eta) {
                return Some((lam(x, n), kind));
            }
            if strategy == "APPLICATIVE" && use_eta {
                if let Some(n) = eta(t) {
                    return Some((n, "eta"));
                }
            }
        }
        _ => (),
    }
    None
}

#[derive(Clone)]
enum Type {
    Variable(usize),
    Function(Rc<Type>, Rc<Type>),
}
type Ty = Rc<Type>;

struct Inference {
    next: usize,
    bindings: BTreeMap<usize, Ty>,
    globals: BTreeMap<String, Ty>,
}

impl Inference {
    fn fresh(&mut self) -> Ty {
        let i = self.next;
        self.next += 1;
        Rc::new(Type::Variable(i))
    }

    fn resolve(&self, t: &Ty) -> Ty {
        if let Type::Variable(i) = t.as_ref() {
            if let Some(v) = self.bindings.get(i) {
                return self.resolve(v);
            }
        }
        t.clone()
    }

    fn occurs(&self, id: usize, t: &Ty) -> bool {
        match self.resolve(t).as_ref() {
            Type::Variable(i) => *i == id,
            Type::Function(a, b) => self.occurs(id, a) || self.occurs(id, b),
        }
    }

    fn unify(&mut self, a: &Ty, b: &Ty) -> Result<(), ()> {
        let a = self.resolve(a);
        let b = self.resolve(b);
        match (a.as_ref(), b.as_ref()) {
            (Type::Variable(i), Type::Variable(j)) if i == j => Ok(()),
            (Type::Variable(i), _) => {
                if self.occurs(*i, &b) {
                    return Err(());
                }
                self.bindings.insert(*i, b.clone());
                Ok(())
            }
            (_, Type::Variable(i)) => {
                if self.occurs(*i, &a) {
                    return Err(());
                }
                self.bindings.insert(*i, a.clone());
                Ok(())
            }
            (Type::Function(a, b), Type::Function(c, d)) => {
                self.unify(a, c)?;
                self.unify(b, d)
            }
        }
    }

    fn visit(&mut self, t: &T, env: &mut Vec<(String, Ty)>) -> Result<Ty, ()> {
        match t.as_ref() {
            Term::Var(n) => {
                if let Some((_, t)) = env.iter().rev().find(|(v, _)| v == n) {
                    return Ok(t.clone());
                }
                if let Some(t) = self.globals.get(n) {
                    return Ok(t.clone());
                }
                let t = self.fresh();
                self.globals.insert(n.clone(), t.clone());
                Ok(t)
            }
            Term::Lambda(n, b) => {
                let a = self.fresh();
                env.push((n.clone(), a.clone()));
                let body = self.visit(b, env)?;
                env.pop();
                Ok(Rc::new(Type::Function(a, body)))
            }
            Term::Apply(a, b) => {
                let a = self.visit(a, env)?;
                let b = self.visit(b, env)?;
                let result = self.fresh();
                self.unify(&a, &Rc::new(Type::Function(b, result.clone())))?;
                Ok(result)
            }
            _ => unreachable!(),
        }
    }

    fn show(&self, t: &Ty, names: &mut BTreeMap<usize, String>) -> String {
        match self.resolve(t).as_ref() {
            Type::Variable(i) => {
                if !names.contains_key(i) {
                    names.insert(*i, sequence_name(names.len()));
                }
                names[i].clone()
            }
            Type::Function(a, b) => {
                let left = self.show(a, names);
                let left = if matches!(self.resolve(a).as_ref(), Type::Function(_, _)) {
                    format!("({})", left)
                } else {
                    left
                };
                format!("{} -> {}", left, self.show(b, names))
            }
        }
    }
}

fn infer(t: &T) -> String {
    let mut i = Inference {
        next: 0,
        bindings: BTreeMap::new(),
        globals: BTreeMap::new(),
    };
    match i.visit(t, &mut Vec::new()) {
        Ok(t) => i.show(&t, &mut BTreeMap::new()),
        Err(()) => "not typable".into(),
    }
}

fn abstract_term(x: &str, e: &T) -> T {
    if !free(e).contains(x) {
        return app(Rc::new(Term::Macro("K".into())), e.clone());
    }
    if matches!(e.as_ref(), Term::Var(n) if n == x) {
        return Rc::new(Term::Macro("I".into()));
    }
    let Term::Apply(a, b) = e.as_ref() else {
        unreachable!()
    };
    if matches!(b.as_ref(), Term::Var(n) if n == x) && !free(a).contains(x) {
        return a.clone();
    }
    app(
        app(Rc::new(Term::Macro("S".into())), abstract_term(x, a)),
        abstract_term(x, b),
    )
}

fn ski(t: &T) -> T {
    match t.as_ref() {
        Term::Var(_) => t.clone(),
        Term::Lambda(n, b) => abstract_term(n, &ski(b)),
        Term::Apply(a, b) => app(ski(a), ski(b)),
        _ => unreachable!(),
    }
}

fn build(mut head: T, args: &[T]) -> T {
    for a in args {
        head = app(head, a.clone());
    }
    head
}

fn ski_step(t: &T) -> Option<(T, &'static str)> {
    let mut head = t;
    let mut args = Vec::new();
    while let Term::Apply(a, b) = head.as_ref() {
        args.push(b.clone());
        head = a;
    }
    args.reverse();
    if let Term::Macro(n) = head.as_ref() {
        match n.as_str() {
            "I" if !args.is_empty() => return Some((build(args[0].clone(), &args[1..]), "I")),
            "K" if args.len() >= 2 => return Some((build(args[0].clone(), &args[2..]), "K")),
            "S" if args.len() >= 3 => {
                return Some((
                    build(
                        app(
                            app(args[0].clone(), args[2].clone()),
                            app(args[1].clone(), args[2].clone()),
                        ),
                        &args[3..],
                    ),
                    "S",
                ));
            }
            _ => (),
        }
    }
    for i in 0..args.len() {
        if let Some((n, kind)) = ski_step(&args[i]) {
            args[i] = n;
            return Some((build(head.clone(), &args), kind));
        }
    }
    None
}

fn church(t: &T) -> String {
    if let Term::Lambda(f, inner) = t.as_ref() {
        if let Term::Lambda(x, body) = inner.as_ref() {
            let mut b = body;
            let mut count = 0;
            while let Term::Apply(a, n) = b.as_ref() {
                if !matches!(a.as_ref(), Term::Var(v) if v == f) {
                    break;
                }
                count += 1;
                b = n;
            }
            if matches!(b.as_ref(), Term::Var(v) if v == x) {
                return count.to_string();
            }
            if matches!(body.as_ref(), Term::Var(v) if v == f) {
                return "true".into();
            }
        }
        if let Term::Apply(left, q) = inner.as_ref() {
            if let Term::Apply(h, p) = left.as_ref() {
                if matches!(h.as_ref(), Term::Var(v) if v == f)
                    && !free(p).contains(f)
                    && !free(q).contains(f)
                {
                    return format!("({}, {})", church(p), church(q));
                }
            }
        }
    }
    printed(&canonical(t), true, false)
}

#[derive(Clone)]
struct Token {
    kind: String,
    text: String,
    column: usize,
}

struct Parser {
    tokens: Vec<Token>,
    at: usize,
}

impl Parser {
    fn new(line: &str, arg: &str, offset: usize) -> Result<Self, String> {
        let b = arg.as_bytes();
        let mut i = 0;
        let mut tokens = Vec::new();
        while i < b.len() {
            let c = b[i];
            if c == b' ' {
                i += 1;
                continue;
            }
            let start = i;
            let kind;
            if b"\\.()=;".contains(&c) {
                i += 1;
                kind = (c as char).to_string();
            } else if c.is_ascii_lowercase() {
                i += 1;
                while i < b.len() && (b[i].is_ascii_lowercase() || b[i].is_ascii_digit()) {
                    i += 1;
                }
                kind = "var".into();
            } else if c.is_ascii_uppercase() {
                i += 1;
                while i < b.len()
                    && (b[i].is_ascii_uppercase() || b[i].is_ascii_digit() || b[i] == b'_')
                {
                    i += 1;
                }
                kind = "macro".into();
            } else if c == b'#' && i + 1 < b.len() && b[i + 1].is_ascii_digit() {
                i += 2;
                while i < b.len() && b[i].is_ascii_digit() {
                    i += 1;
                }
                kind = "num".into();
            } else {
                return Err(format!(
                    "column {}: unexpected character '{}'",
                    offset + i,
                    c as char
                ));
            }
            tokens.push(Token {
                kind,
                text: arg[start..i].into(),
                column: offset + start,
            });
        }
        tokens.push(Token {
            kind: "end".into(),
            text: String::new(),
            column: line.len() + 1,
        });
        Ok(Self { tokens, at: 0 })
    }

    fn expect(&mut self, kind: &str) -> Result<Token, String> {
        let t = self.tokens[self.at].clone();
        if t.kind != kind {
            let expected = match kind {
                "var" => "variable".into(),
                "macro" => "macro name".into(),
                _ => format!("'{}'", kind),
            };
            return Err(format!("column {}: expected {}", t.column, expected));
        }
        self.at += 1;
        Ok(t)
    }

    fn term(&mut self) -> Result<T, String> {
        let mut elements = Vec::new();
        while ["var", "macro", "num", "("].contains(&self.tokens[self.at].kind.as_str()) {
            let t = self.tokens[self.at].clone();
            self.at += 1;
            elements.push(match t.kind.as_str() {
                "(" => {
                    let e = self.term()?;
                    self.expect(")")?;
                    e
                }
                "num" => Rc::new(Term::Num(t.text[1..].parse().unwrap())),
                "var" => var(&t.text),
                _ => Rc::new(Term::Macro(t.text)),
            });
        }
        if self.tokens[self.at].kind == "\\" {
            self.at += 1;
            let mut names = vec![self.expect("var")?.text];
            while self.tokens[self.at].kind == "var" {
                names.push(self.tokens[self.at].text.clone());
                self.at += 1;
            }
            self.expect(".")?;
            let mut body = self.term()?;
            for n in names.iter().rev() {
                body = lam(n, body);
            }
            elements.push(body);
        }
        if elements.is_empty() {
            return Err(format!(
                "column {}: expected term",
                self.tokens[self.at].column
            ));
        }
        Ok(build(elements[0].clone(), &elements[1..]))
    }

    fn end(&self) -> Result<(), String> {
        let t = &self.tokens[self.at];
        if t.kind == "end" {
            Ok(())
        } else {
            Err(format!("column {}: unexpected '{}'", t.column, t.text))
        }
    }
}

struct Closure {
    code: T,
    env: Vec<Rc<Closure>>,
}

fn reify<'a>(mut t: &'a T, mut env: &'a [Rc<Closure>], mut depth: usize) -> T {
    while let Term::Index(i) = t.as_ref() {
        if *i < depth {
            break;
        }
        let closure = &env[*i - depth];
        t = &closure.code;
        env = &closure.env;
        depth = 0;
    }
    match t.as_ref() {
        Term::Lambda(_, b) => lam("", reify(b, env, depth + 1)),
        Term::Apply(a, b) => app(reify(a, env, depth), reify(b, env, depth)),
        _ => t.clone(),
    }
}

fn named_db(t: &T, env: &mut Vec<String>, f: &BTreeSet<String>, next: &mut usize) -> T {
    match t.as_ref() {
        Term::Index(i) => var(&env[env.len() - 1 - *i]),
        Term::Lambda(_, b) => {
            while f.contains(&sequence_name(*next)) {
                *next += 1;
            }
            let n = sequence_name(*next);
            *next += 1;
            env.push(n.clone());
            let body = named_db(b, env, f, next);
            env.pop();
            lam(&n, body)
        }
        Term::Apply(a, b) => app(named_db(a, env, f, next), named_db(b, env, f, next)),
        _ => t.clone(),
    }
}

struct Workbench {
    macros: BTreeMap<String, T>,
    display: bool,
    eta: bool,
    limit: usize,
}

impl Workbench {
    fn new() -> Self {
        let mut macros = BTreeMap::new();
        macros.insert("I".into(), lam("x", var("x")));
        macros.insert("K".into(), lam("x", lam("y", var("x"))));
        macros.insert(
            "S".into(),
            lam(
                "x",
                lam(
                    "y",
                    lam("z", app(app(var("x"), var("z")), app(var("y"), var("z")))),
                ),
            ),
        );
        Self {
            macros,
            display: false,
            eta: false,
            limit: 10000,
        }
    }

    fn reserved(n: &str) -> bool {
        ["S", "K", "I", "NORMAL", "APPLICATIVE", "CBN", "CBV"].contains(&n)
    }

    fn expand(&self, t: &T) -> Result<T, String> {
        Ok(match t.as_ref() {
            Term::Macro(n) => self.expand(
                self.macros
                    .get(n)
                    .ok_or_else(|| format!("unbound macro {}", n))?,
            )?,
            Term::Num(n) => {
                let mut b = var("x");
                for _ in 0..*n {
                    b = app(var("f"), b);
                }
                lam("f", lam("x", b))
            }
            Term::Lambda(n, b) => lam(n, self.expand(b)?),
            Term::Apply(a, b) => app(self.expand(a)?, self.expand(b)?),
            _ => t.clone(),
        })
    }

    fn depends(&self, name: &str, target: &str) -> bool {
        fn visit(
            name: &str,
            target: &str,
            macros: &BTreeMap<String, T>,
            visited: &mut BTreeSet<String>,
        ) -> bool {
            if !visited.insert(name.into()) {
                return false;
            }
            macros.get(name).is_some_and(|t| {
                references(t)
                    .iter()
                    .any(|n| n == target || visit(n, target, macros, visited))
            })
        }
        visit(name, target, &self.macros, &mut BTreeSet::new())
    }

    fn reduce(
        &self,
        mut t: T,
        strategy: &str,
        eta: bool,
        display: bool,
        combinators: bool,
        output: &mut Vec<String>,
    ) -> Option<(T, usize)> {
        let mut count = 0;
        loop {
            let next = if combinators {
                ski_step(&t)
            } else {
                step(&t, strategy, eta)
            };
            let Some((n, kind)) = next else {
                return Some((t, count));
            };
            if count == self.limit {
                return None;
            }
            count += 1;
            t = n;
            if display && self.display {
                output.push(format!(
                    "step {} ({}): {}",
                    count,
                    kind,
                    printed(&t, true, false)
                ));
            }
        }
    }

    fn kam(&self, t: &T) -> Vec<String> {
        let mut code = debruijn(t, &mut Vec::new());
        let mut env = Vec::new();
        let mut stack = Vec::new();
        let mut count = 0;
        let mut out = Vec::new();
        loop {
            let kind = match code.as_ref() {
                Term::Apply(_, _) => "push",
                Term::Lambda(_, _) if !stack.is_empty() => "grab",
                Term::Index(_) => "access",
                _ => break,
            };
            if count == self.limit {
                out.push(format!("no result within {} transitions", self.limit));
                return out;
            }
            match code.as_ref() {
                Term::Apply(a, b) => {
                    stack.push(Rc::new(Closure {
                        code: b.clone(),
                        env: env.clone(),
                    }));
                    code = a.clone();
                }
                Term::Lambda(_, b) => {
                    env.insert(0, stack.pop().unwrap());
                    code = b.clone();
                }
                Term::Index(i) => {
                    let c = env[*i].clone();
                    code = c.code.clone();
                    env = c.env.clone();
                }
                _ => unreachable!(),
            }
            count += 1;
            if self.display {
                out.push(format!(
                    "step {} ({}): {} [env {}, stack {}]",
                    count,
                    kind,
                    printed(&code, true, true),
                    env.len(),
                    stack.len()
                ));
            }
        }
        let mut result = reify(&code, &env, 0);
        for c in stack.iter().rev() {
            result = app(result, reify(&c.code, &c.env, 0));
        }
        let named = named_db(&result, &mut Vec::new(), &free(&result), &mut 0);
        out.push(format!(
            "result: {} (transitions: {})",
            printed(&named, true, false),
            count
        ));
        out
    }

    fn command(&mut self, line: &str) -> Result<Vec<String>, String> {
        let (command, arg) = line.split_once(' ').unwrap_or((line, ""));
        if ![
            "let",
            "unlet",
            "macros",
            "steps",
            "eta",
            "limit",
            "expand",
            "subst",
            "reduce",
            "equal",
            "alpha",
            "debruijn",
            "fv",
            "size",
            "depth",
            "type",
            "church",
            "ski",
            "skireduce",
            "kam",
        ]
        .contains(&command)
        {
            return Err(format!("unknown command {}", command));
        }
        let words: Vec<&str> = arg.split(' ').filter(|s| !s.is_empty()).collect();
        if command == "steps" || command == "eta" {
            if words.len() != 1 || !["on", "off"].contains(&words[0]) {
                return Err("bad argument".into());
            }
            if command == "steps" {
                self.display = words[0] == "on";
            } else {
                self.eta = words[0] == "on";
            }
            return Ok(Vec::new());
        }
        if command == "limit" {
            if words.len() != 1
                || words[0].is_empty()
                || words[0].len() > 5
                || !words[0].bytes().all(|c| c.is_ascii_digit())
                || !(1..=10000).contains(&words[0].parse::<usize>().unwrap())
            {
                return Err("bad argument".into());
            }
            self.limit = words[0].parse().unwrap();
            return Ok(Vec::new());
        }
        if command == "macros" {
            if !words.is_empty() {
                return Err("bad argument".into());
            }
            let out: Vec<String> = self
                .macros
                .iter()
                .filter(|(n, _)| !Self::reserved(n))
                .map(|(n, t)| format!("{} = {}", n, printed(t, true, false)))
                .collect();
            return Ok(if out.is_empty() {
                vec!["(none)".into()]
            } else {
                out
            });
        }
        if command == "unlet" {
            if words.len() != 1
                || words[0].is_empty()
                || !words[0].as_bytes()[0].is_ascii_uppercase()
                || !words[0]
                    .bytes()
                    .all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || c == b'_')
            {
                return Err("bad argument".into());
            }
            let n = words[0];
            if Self::reserved(n) {
                return Err(format!("reserved name {}", n));
            }
            if !self.macros.contains_key(n) {
                return Err(format!("unbound macro {}", n));
            }
            if let Some((used, _)) = self
                .macros
                .iter()
                .find(|(name, t)| !Self::reserved(name) && references(t).iter().any(|r| r == n))
            {
                return Err(format!("{} is used by {}", n, used));
            }
            self.macros.remove(n);
            return Ok(vec![format!("removed {}", n)]);
        }
        let mut p = Parser::new(
            line,
            arg,
            if line.contains(' ') {
                command.len() + 2
            } else {
                line.len() + 1
            },
        )?;
        let mut name = String::new();
        let mut strategy = "NORMAL".to_string();
        let mut terms = Vec::new();
        match command {
            "let" => {
                name = p.expect("macro")?.text;
                p.expect("=")?;
                terms.push(p.term()?);
            }
            "subst" => {
                name = p.expect("var")?.text;
                p.expect("=")?;
                terms.push(p.term()?);
                p.expect(";")?;
                terms.push(p.term()?);
            }
            "equal" | "alpha" => {
                terms.push(p.term()?);
                p.expect(";")?;
                terms.push(p.term()?);
            }
            "reduce" => {
                if p.tokens[p.at].kind == "macro"
                    && ["NORMAL", "APPLICATIVE", "CBN", "CBV"]
                        .contains(&p.tokens[p.at].text.as_str())
                {
                    strategy = p.tokens[p.at].text.clone();
                    p.at += 1;
                }
                terms.push(p.term()?);
            }
            _ => terms.push(p.term()?),
        }
        p.end()?;
        if command == "let" {
            let t = &terms[0];
            if Self::reserved(&name) {
                return Err(format!("reserved name {}", name));
            }
            for r in references(t) {
                if r == name || self.depends(&r, &name) {
                    return Err(format!("recursive definition of {}", name));
                }
                if !self.macros.contains_key(&r) {
                    return Err(format!("unbound macro {}", r));
                }
            }
            if let Some(v) = free(t).first() {
                return Err(format!("free variable {} in definition of {}", v, name));
            }
            let exists = self.macros.contains_key(&name);
            self.macros.insert(name.clone(), t.clone());
            return Ok(vec![format!(
                "{} {}",
                if exists { "redefined" } else { "defined" },
                name
            )]);
        }
        let terms: Vec<T> = terms
            .iter()
            .map(|t| self.expand(t))
            .collect::<Result<_, _>>()?;
        let t = &terms[0];
        let mut out = Vec::new();
        let failure = format!("no normal form within {} steps", self.limit);
        match command {
            "expand" => out.push(printed(t, true, false)),
            "subst" => out.push(printed(&substitute(&terms[1], &name, t), true, false)),
            "alpha" => out.push(
                if debruijn(t, &mut Vec::new()) == debruijn(&terms[1], &mut Vec::new()) {
                    "yes"
                } else {
                    "no"
                }
                .into(),
            ),
            "debruijn" => out.push(printed(&debruijn(t, &mut Vec::new()), true, true)),
            "fv" => {
                let f = free(t);
                out.push(if f.is_empty() {
                    "(none)".into()
                } else {
                    f.into_iter().collect::<Vec<_>>().join(" ")
                });
            }
            "size" | "depth" => {
                fn measure(t: &T, size: bool) -> usize {
                    match t.as_ref() {
                        Term::Var(_) => 1,
                        Term::Lambda(_, b) => 1 + measure(b, size),
                        Term::Apply(a, b) => {
                            1 + if size {
                                measure(a, size) + measure(b, size)
                            } else {
                                measure(a, size).max(measure(b, size))
                            }
                        }
                        _ => unreachable!(),
                    }
                }
                out.push(measure(t, command == "size").to_string());
            }
            "type" => out.push(infer(t)),
            "ski" => out.push(printed(&ski(t), true, false)),
            "kam" => return Ok(self.kam(t)),
            "equal" => {
                let a = self.reduce(t.clone(), "NORMAL", self.eta, false, false, &mut out);
                let b = self.reduce(terms[1].clone(), "NORMAL", self.eta, false, false, &mut out);
                out.push(
                    match (a, b) {
                        (Some((a, _)), Some((b, _))) => {
                            if debruijn(&a, &mut Vec::new()) == debruijn(&b, &mut Vec::new()) {
                                "yes"
                            } else {
                                "no"
                            }
                        }
                        _ => "unknown",
                    }
                    .into(),
                );
            }
            "church" => {
                let result = self.reduce(t.clone(), "NORMAL", false, false, false, &mut out);
                out.push(result.map_or(failure, |(r, _)| church(&canonical(&r))));
            }
            _ => {
                let combinators = command == "skireduce";
                let result = self.reduce(
                    if combinators { ski(t) } else { t.clone() },
                    &strategy,
                    self.eta,
                    true,
                    combinators,
                    &mut out,
                );
                out.push(result.map_or(failure, |(r, n)| {
                    format!(
                        "result: {} (steps: {})",
                        printed(&if combinators { r } else { canonical(&r) }, true, false),
                        n
                    )
                }));
            }
        }
        Ok(out)
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut w = Workbench::new();
    for line in input.lines() {
        if line == "quit" {
            break;
        }
        if line.is_empty() || line.starts_with("--") {
            continue;
        }
        match w.command(line) {
            Ok(lines) => {
                for line in lines {
                    println!("{}", line);
                }
            }
            Err(e) => println!("error: {}", e),
        }
    }
}
