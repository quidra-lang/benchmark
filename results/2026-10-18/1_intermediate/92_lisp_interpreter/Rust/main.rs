use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::io::{self, Read, Write};
use std::rc::Rc;
type Result<T> = std::result::Result<T, String>;
type Scope = Rc<Environment>;
#[derive(Clone)]
enum Value {
    Int(i64),
    Bool(bool),
    Str(String),
    Sym(String),
    Nil,
    Pair(Rc<(Value, Value)>),
    Proc(Rc<Procedure>),
    Void,
    Uninitialized,
}
struct Environment {
    frame: RefCell<HashMap<String, Value>>,
    parent: Option<Scope>,
}
impl Environment {
    fn new(parent: Option<Scope>) -> Scope {
        Rc::new(Self {
            frame: RefCell::new(HashMap::new()),
            parent,
        })
    }
    fn find(self: &Rc<Self>, name: &str) -> Result<Scope> {
        let mut e = Some(self.clone());
        while let Some(scope) = e {
            if scope.frame.borrow().contains_key(name) {
                return Ok(scope);
            }
            e = scope.parent.clone();
        }
        Err(format!("unbound variable: {name}"))
    }
    fn get(self: &Rc<Self>, name: &str) -> Result<Value> {
        let v = self.find(name)?.frame.borrow()[name].clone();
        if matches!(v, Value::Uninitialized) {
            Err(format!("uninitialized variable: {name}"))
        } else {
            Ok(v)
        }
    }
    fn bind(&self, name: &str, v: Value) {
        self.frame.borrow_mut().insert(name.to_owned(), v);
    }
}
struct Procedure {
    name: RefCell<Option<String>>,
    minimum: usize,
    variadic: bool,
    implementation: Implementation,
}
enum Implementation {
    Builtin(&'static str),
    Closure {
        params: Vec<String>,
        rest: Option<String>,
        body: Vec<Value>,
        env: Scope,
    },
}
fn list(a: &[Value], mut tail: Value) -> Value {
    for x in a.iter().rev() {
        tail = Value::Pair(Rc::new((x.clone(), tail)));
    }
    tail
}
fn items(v: &Value) -> Option<Vec<Value>> {
    let mut a = Vec::new();
    let mut v = v;
    while let Value::Pair(p) = v {
        a.push(p.0.clone());
        v = &p.1;
    }
    if matches!(v, Value::Nil) {
        Some(a)
    } else {
        None
    }
}
fn truth(v: &Value) -> bool {
    !matches!(v, Value::Bool(false))
}
fn repr(v: &Value, quoted: bool) -> String {
    match v {
        Value::Int(n) => n.to_string(),
        Value::Bool(b) => (if *b { "#t" } else { "#f" }).into(),
        Value::Str(s) => {
            if quoted {
                format!(
                    "\"{}\"",
                    s.replace('\\', "\\\\")
                        .replace('"', "\\\"")
                        .replace('\n', "\\n")
                )
            } else {
                s.clone()
            }
        }
        Value::Sym(s) => s.clone(),
        Value::Nil => "()".into(),
        Value::Void | Value::Uninitialized => "#<void>".into(),
        Value::Proc(p) => match &*p.name.borrow() {
            Some(n) => format!("#<procedure {n}>"),
            None => "#<procedure>".into(),
        },
        Value::Pair(_) => {
            let mut a = Vec::new();
            let mut v = v;
            while let Value::Pair(p) = v {
                a.push(repr(&p.0, quoted));
                v = &p.1;
            }
            if !matches!(v, Value::Nil) {
                a.push(".".into());
                a.push(repr(v, quoted));
            }
            format!("({})", a.join(" "))
        }
    }
}
fn equal(a: &Value, b: &Value, deep: bool) -> bool {
    match (a, b) {
        (Value::Int(a), Value::Int(b)) => a == b,
        (Value::Bool(a), Value::Bool(b)) => a == b,
        (Value::Str(a), Value::Str(b)) | (Value::Sym(a), Value::Sym(b)) => a == b,
        (Value::Nil, Value::Nil) | (Value::Void, Value::Void) => true,
        (Value::Pair(a), Value::Pair(b)) => {
            if deep {
                equal(&a.0, &b.0, true) && equal(&a.1, &b.1, true)
            } else {
                Rc::ptr_eq(a, b)
            }
        }
        (Value::Proc(a), Value::Proc(b)) => Rc::ptr_eq(a, b),
        _ => false,
    }
}
fn shape(valid: bool, x: &Value) -> Result<()> {
    if valid {
        Ok(())
    } else {
        Err(format!("bad syntax: {}", repr(x, true)))
    }
}
fn parameters(v: &Value) -> Option<(Vec<String>, Option<String>)> {
    let mut names = Vec::new();
    let mut v = v;
    while let Value::Pair(p) = v {
        if let Value::Sym(s) = &p.0 {
            names.push(s.clone())
        } else {
            return None;
        }
        v = &p.1;
    }
    let rest = match v {
        Value::Nil => None,
        Value::Sym(s) => Some(s.clone()),
        _ => return None,
    };
    let mut seen = HashSet::new();
    for n in names.iter().chain(rest.iter()) {
        if !seen.insert(n) {
            return None;
        }
    }
    Some((names, rest))
}
fn closure(
    p: (Vec<String>, Option<String>),
    body: Vec<Value>,
    env: Scope,
    name: Option<String>,
) -> Value {
    Value::Proc(Rc::new(Procedure {
        name: RefCell::new(name),
        minimum: p.0.len(),
        variadic: p.1.is_some(),
        implementation: Implementation::Closure {
            params: p.0,
            rest: p.1,
            body,
            env,
        },
    }))
}
fn bindings(v: &Value, unique: bool) -> Option<Vec<(String, Value)>> {
    let a = items(v)?;
    let mut bs = Vec::new();
    let mut seen = HashSet::new();
    for x in a {
        let b = items(&x)?;
        if b.len() != 2 {
            return None;
        }
        if let Value::Sym(n) = &b[0] {
            if unique && !seen.insert(n.clone()) {
                return None;
            }
            bs.push((n.clone(), b[1].clone()));
        } else {
            return None;
        }
    }
    Some(bs)
}
fn body(a: &[Value], e: &Scope, out: &mut Output) -> Result<Value> {
    let mut v = Value::Void;
    for x in a {
        v = evaluate(x, e, out)?;
    }
    Ok(v)
}
fn evaluate(x: &Value, e: &Scope, out: &mut Output) -> Result<Value> {
    if let Value::Sym(n) = x {
        return e.get(n);
    }
    if !matches!(x, Value::Pair(_)) {
        shape(!matches!(x, Value::Nil), x)?;
        return Ok(x.clone());
    }
    let a = items(x).ok_or_else(|| format!("bad syntax: {}", repr(x, true)))?;
    let n = a.len();
    let h = if let Value::Sym(s) = &a[0] {
        s.as_str()
    } else {
        ""
    };
    match h {
        "quote" => {
            shape(n == 2, x)?;
            return Ok(a[1].clone());
        }
        "if" => {
            shape(n == 3 || n == 4, x)?;
            return if truth(&evaluate(&a[1], e, out)?) {
                evaluate(&a[2], e, out)
            } else if n == 4 {
                evaluate(&a[3], e, out)
            } else {
                Ok(Value::Void)
            };
        }
        "begin" => return body(&a[1..], e, out),
        "lambda" => {
            let p = if n >= 3 { parameters(&a[1]) } else { None };
            shape(p.is_some(), x)?;
            return Ok(closure(p.unwrap(), a[2..].to_vec(), e.clone(), None));
        }
        "define" => {
            if n > 1 {
                if let Value::Sym(name) = &a[1] {
                    shape(n == 3, x)?;
                    let v = evaluate(&a[2], e, out)?;
                    if let Value::Proc(p) = &v {
                        if matches!(p.implementation, Implementation::Closure { .. })
                            && p.name.borrow().is_none()
                        {
                            *p.name.borrow_mut() = Some(name.clone());
                        }
                    }
                    e.bind(name, v);
                    return Ok(Value::Void);
                }
            }
            shape(n >= 3, x)?;
            if let Value::Pair(t) = &a[1] {
                if let Value::Sym(name) = &t.0 {
                    let p = parameters(&t.1);
                    shape(p.is_some(), x)?;
                    e.bind(
                        name,
                        closure(p.unwrap(), a[2..].to_vec(), e.clone(), Some(name.clone())),
                    );
                    return Ok(Value::Void);
                }
            }
            shape(false, x)?;
        }
        "set!" => {
            shape(n == 3 && matches!(&a[1], Value::Sym(_)), x)?;
            let name = if let Value::Sym(s) = &a[1] {
                s
            } else {
                unreachable!()
            };
            let v = evaluate(&a[2], e, out)?;
            e.find(name)?.bind(name, v);
            return Ok(Value::Void);
        }
        "let" | "let*" | "letrec" => {
            let named = h == "let" && n > 1 && matches!(&a[1], Value::Sym(_));
            let at = if named { 2 } else { 1 };
            let bs = if n >= at + 2 {
                bindings(&a[at], h != "let*")
            } else {
                None
            };
            shape(bs.is_some(), x)?;
            let bs = bs.unwrap();
            let mut scope = Environment::new(Some(e.clone()));
            if h == "let*" {
                if !bs.is_empty() {
                    scope = e.clone()
                }
                for (name, expr) in &bs {
                    let v = evaluate(expr, &scope, out)?;
                    scope = Environment::new(Some(scope));
                    scope.bind(name, v);
                }
            } else if h == "letrec" {
                for (name, _) in &bs {
                    scope.bind(name, Value::Uninitialized)
                }
                for (name, expr) in &bs {
                    let v = evaluate(expr, &scope, out)?;
                    scope.bind(name, v);
                }
            } else {
                let mut vs = Vec::new();
                for (_, expr) in &bs {
                    vs.push(evaluate(expr, e, out)?)
                }
                if named {
                    let name = if let Value::Sym(s) = &a[1] {
                        s
                    } else {
                        unreachable!()
                    };
                    let f = closure(
                        (bs.iter().map(|b| b.0.clone()).collect(), None),
                        a[3..].to_vec(),
                        scope.clone(),
                        Some(name.clone()),
                    );
                    scope.bind(name, f.clone());
                    return call(&f, &vs, out);
                }
                for ((name, _), v) in bs.iter().zip(vs) {
                    scope.bind(name, v)
                }
            }
            return body(&a[at + 1..], &scope, out);
        }
        "cond" => {
            let mut cs = Vec::new();
            for (i, c) in a[1..].iter().enumerate() {
                let c = items(c);
                shape(c.as_ref().is_some_and(|c| !c.is_empty()), x)?;
                let c = c.unwrap();
                if matches!(&c[0], Value::Sym(s)if s == "else") {
                    shape(c.len() >= 2 && i == n - 2, x)?
                }
                cs.push(c)
            }
            for c in cs {
                if matches!(&c[0], Value::Sym(s)if s == "else") {
                    return body(&c[1..], e, out);
                }
                let v = evaluate(&c[0], e, out)?;
                if truth(&v) {
                    return if c.len() == 1 {
                        Ok(v)
                    } else {
                        body(&c[1..], e, out)
                    };
                }
            }
            return Ok(Value::Void);
        }
        "and" => {
            let mut v = Value::Bool(true);
            for z in &a[1..] {
                v = evaluate(z, e, out)?;
                if !truth(&v) {
                    break;
                }
            }
            return Ok(v);
        }
        "or" => {
            for z in &a[1..] {
                let v = evaluate(z, e, out)?;
                if truth(&v) {
                    return Ok(v);
                }
            }
            return Ok(Value::Bool(false));
        }
        "when" | "unless" => {
            shape(n >= 3, x)?;
            return if truth(&evaluate(&a[1], e, out)?) == (h == "when") {
                body(&a[2..], e, out)
            } else {
                Ok(Value::Void)
            };
        }
        _ => {}
    }
    let f = evaluate(&a[0], e, out)?;
    let mut args = Vec::new();
    for z in &a[1..] {
        args.push(evaluate(z, e, out)?)
    }
    call(&f, &args, out)
}
fn call(f: &Value, a: &[Value], out: &mut Output) -> Result<Value> {
    let Value::Proc(p) = f else {
        return Err(format!("not a procedure: {}", repr(f, true)));
    };
    if a.len() < p.minimum || (!p.variadic && a.len() != p.minimum) {
        return Err(format!(
            "{}: wrong number of arguments (expected {}{}, got {})",
            p.name.borrow().as_deref().unwrap_or("lambda"),
            if p.variadic { "at least " } else { "" },
            p.minimum,
            a.len()
        ));
    }
    match &p.implementation {
        Implementation::Builtin(n) => builtin(n, a, out),
        Implementation::Closure {
            params,
            rest,
            body: b,
            env,
        } => {
            let e = Environment::new(Some(env.clone()));
            for (n, v) in params.iter().zip(a) {
                e.bind(n, v.clone())
            }
            if let Some(r) = rest {
                e.bind(r, list(&a[params.len()..], Value::Nil))
            }
            body(b, &e, out)
        }
    }
}
struct Output {
    text: String,
    mid: bool,
}
impl Output {
    fn write(&mut self, s: &str) {
        self.text.push_str(s);
        if !s.is_empty() {
            self.mid = !s.ends_with('\n')
        }
    }
    fn line(&mut self, s: &str) {
        if self.mid {
            self.write("\n")
        }
        self.write(s);
        self.write("\n")
    }
}
fn expect(n: &str, v: &Value, k: &str) -> Result<()> {
    let ok = match k {
        "integer" => matches!(v, Value::Int(_)),
        "string" => matches!(v, Value::Str(_)),
        "pair" => matches!(v, Value::Pair(_)),
        "procedure" => matches!(v, Value::Proc(_)),
        _ => items(v).is_some(),
    };
    if ok {
        Ok(())
    } else {
        Err(format!("{n}: expected {k}, got {}", repr(v, true)))
    }
}
fn as_list(n: &str, v: &Value) -> Result<Vec<Value>> {
    expect(n, v, "list")?;
    Ok(items(v).unwrap())
}
fn integer(v: &Value) -> i64 {
    if let Value::Int(n) = v {
        *n
    } else {
        unreachable!()
    }
}
fn builtin(n: &str, a: &[Value], out: &mut Output) -> Result<Value> {
    if [
        "+",
        "*",
        "-",
        "quotient",
        "remainder",
        "modulo",
        "abs",
        "min",
        "max",
        "gcd",
        "=",
        "<",
        ">",
        "<=",
        ">=",
    ]
    .contains(&n)
    {
        for v in a {
            expect(n, v, "integer")?
        }
        let z: Vec<i64> = a.iter().map(integer).collect();
        let v = z.first().copied().unwrap_or(0);
        return Ok(match n {
            "+" => Value::Int(z.iter().sum()),
            "*" => Value::Int(z.iter().product()),
            "-" => Value::Int(if z.len() == 1 {
                -v
            } else {
                v - z[1..].iter().sum::<i64>()
            }),
            "abs" => Value::Int(v.abs()),
            "min" => Value::Int(*z.iter().min().unwrap()),
            "max" => Value::Int(*z.iter().max().unwrap()),
            "gcd" => Value::Int(z.into_iter().fold(0, |mut g, x| {
                let mut b = x.abs();
                while b != 0 {
                    (g, b) = (b, g % b)
                }
                g
            })),
            "quotient" | "remainder" | "modulo" => {
                let b = z[1];
                if b == 0 {
                    return Err(format!("{n}: division by zero"));
                }
                let r = v % b;
                Value::Int(if n == "quotient" {
                    v / b
                } else if n == "modulo" && r != 0 && ((r < 0) != (b < 0)) {
                    r + b
                } else {
                    r
                })
            }
            _ => Value::Bool(z.windows(2).all(|w| match n {
                "=" => w[0] == w[1],
                "<" => w[0] < w[1],
                ">" => w[0] > w[1],
                "<=" => w[0] <= w[1],
                _ => w[0] >= w[1],
            })),
        });
    }
    Ok(match n {
        "not" => Value::Bool(!truth(&a[0])),
        "eq?" | "equal?" => Value::Bool(equal(&a[0], &a[1], n == "equal?")),
        "null?" => Value::Bool(matches!(a[0], Value::Nil)),
        "pair?" => Value::Bool(matches!(a[0], Value::Pair(_))),
        "list?" => Value::Bool(items(&a[0]).is_some()),
        "number?" => Value::Bool(matches!(a[0], Value::Int(_))),
        "symbol?" => Value::Bool(matches!(a[0], Value::Sym(_))),
        "procedure?" => Value::Bool(matches!(a[0], Value::Proc(_))),
        "cons" => Value::Pair(Rc::new((a[0].clone(), a[1].clone()))),
        "list" => list(a, Value::Nil),
        "car" | "cdr" | "cadr" => {
            expect(n, &a[0], "pair")?;
            let Value::Pair(p) = &a[0] else {
                unreachable!()
            };
            if n == "car" {
                p.0.clone()
            } else if n == "cdr" {
                p.1.clone()
            } else {
                expect(n, &p.1, "pair")?;
                let Value::Pair(q) = &p.1 else { unreachable!() };
                q.0.clone()
            }
        }
        "length" | "reverse" | "list-ref" => {
            let mut z = as_list(n, &a[0])?;
            if n == "length" {
                Value::Int(z.len() as i64)
            } else if n == "reverse" {
                z.reverse();
                list(&z, Value::Nil)
            } else {
                expect(n, &a[1], "integer")?;
                let k = integer(&a[1]);
                if k < 0 || k as usize >= z.len() {
                    return Err(format!("list-ref: index out of range: {k}"));
                }
                z[k as usize].clone()
            }
        }
        "append" => {
            if a.is_empty() {
                Value::Nil
            } else {
                let mut z = Vec::new();
                for v in &a[..a.len() - 1] {
                    z.extend(as_list(n, v)?)
                }
                list(&z, a.last().unwrap().clone())
            }
        }
        "map" | "filter" | "fold-left" | "apply" => {
            expect(n, &a[0], "procedure")?;
            if n == "apply" {
                let mut z = a[1..a.len() - 1].to_vec();
                z.extend(as_list(n, a.last().unwrap())?);
                return call(&a[0], &z, out);
            }
            let mut ls = Vec::new();
            for v in &a[if n == "fold-left" { 2 } else { 1 }..] {
                ls.push(as_list(n, v)?)
            }
            let count = ls.iter().map(Vec::len).min().unwrap();
            let mut result = Vec::new();
            let mut acc = a[1].clone();
            for i in 0..count {
                if n == "filter" {
                    if truth(&call(&a[0], &[ls[0][i].clone()], out)?) {
                        result.push(ls[0][i].clone())
                    }
                } else {
                    let mut z = Vec::new();
                    if n == "fold-left" {
                        z.push(acc.clone())
                    }
                    z.extend(ls.iter().map(|l| l[i].clone()));
                    let v = call(&a[0], &z, out)?;
                    if n == "map" { result.push(v) } else { acc = v }
                }
            }
            if n == "fold-left" {
                acc
            } else {
                list(&result, Value::Nil)
            }
        }
        "string-append" => {
            let mut s = String::new();
            for v in a {
                expect(n, v, "string")?;
                if let Value::Str(t) = v {
                    s.push_str(t)
                }
            }
            Value::Str(s)
        }
        "number->string" => {
            expect(n, &a[0], "integer")?;
            Value::Str(repr(&a[0], true))
        }
        "display" => {
            out.write(&repr(&a[0], false));
            Value::Void
        }
        "newline" => {
            out.write("\n");
            Value::Void
        }
        "error" => {
            expect(n, &a[0], "string")?;
            let Value::Str(mut s) = a[0].clone() else {
                unreachable!()
            };
            for v in &a[1..] {
                s.push(' ');
                s.push_str(&repr(v, true))
            }
            return Err(s);
        }
        _ => unreachable!(),
    })
}
fn global() -> Scope {
    let e = Environment::new(None);
    let specs: [(&str, usize, bool); 42] = [
        ("+", 0, true),
        ("*", 0, true),
        ("-", 1, true),
        ("quotient", 2, false),
        ("remainder", 2, false),
        ("modulo", 2, false),
        ("abs", 1, false),
        ("min", 1, true),
        ("max", 1, true),
        ("gcd", 0, true),
        ("=", 1, true),
        ("<", 1, true),
        (">", 1, true),
        ("<=", 1, true),
        (">=", 1, true),
        ("not", 1, false),
        ("eq?", 2, false),
        ("equal?", 2, false),
        ("null?", 1, false),
        ("pair?", 1, false),
        ("list?", 1, false),
        ("number?", 1, false),
        ("symbol?", 1, false),
        ("procedure?", 1, false),
        ("cons", 2, false),
        ("car", 1, false),
        ("cdr", 1, false),
        ("cadr", 1, false),
        ("list", 0, true),
        ("length", 1, false),
        ("append", 0, true),
        ("reverse", 1, false),
        ("list-ref", 2, false),
        ("map", 2, true),
        ("filter", 2, false),
        ("fold-left", 3, true),
        ("apply", 2, true),
        ("string-append", 0, true),
        ("number->string", 1, false),
        ("display", 1, false),
        ("newline", 0, false),
        ("error", 1, true),
    ];
    for (n, m, r) in specs {
        e.bind(
            n,
            Value::Proc(Rc::new(Procedure {
                name: RefCell::new(Some(n.into())),
                minimum: m,
                variadic: r,
                implementation: Implementation::Builtin(n),
            })),
        )
    }
    e
}
enum Token {
    Datum(Value),
    Mark(u8),
}
struct Reader {
    lines: Vec<Vec<u8>>,
    row: usize,
    col: usize,
}
impl Reader {
    fn skip(&mut self) {
        self.row += 1;
        self.col = 0
    }
    fn end(&mut self) -> bool {
        while self.row < self.lines.len() {
            let s = &self.lines[self.row];
            while self.col < s.len() && s[self.col] == b' ' {
                self.col += 1
            }
            if self.col < s.len() && s[self.col] != b';' {
                return false;
            }
            self.skip()
        }
        true
    }
    fn token(&mut self) -> Result<Token> {
        if self.end() {
            return Err("unexpected end of input".into());
        }
        let s = &self.lines[self.row];
        let c = s[self.col];
        self.col += 1;
        if b"()'".contains(&c) {
            return Ok(Token::Mark(c));
        }
        if c == b'"' {
            let mut v = String::new();
            while self.col < s.len() {
                let mut c = s[self.col];
                self.col += 1;
                if c == b'"' {
                    return Ok(Token::Datum(Value::Str(v)));
                }
                if c == b'\\' {
                    if self.col == s.len() {
                        break;
                    }
                    c = s[self.col];
                    self.col += 1;
                    if !b"\"\\n".contains(&c) {
                        return Err("bad escape".into());
                    }
                    if c == b'n' {
                        c = b'\n'
                    }
                }
                v.push(c as char)
            }
            return Err("unterminated string".into());
        }
        let first = self.col - 1;
        while self.col < s.len() && !b" ()'\";".contains(&s[self.col]) {
            self.col += 1
        }
        let a = String::from_utf8(s[first..self.col].to_vec()).unwrap();
        if a == "." {
            return Ok(Token::Mark(b'.'));
        }
        let digits = a.trim_start_matches(['+', '-']);
        let integer = !digits.is_empty()
            && digits.bytes().all(|c| c.is_ascii_digit())
            && a.bytes().filter(|c| *c == b'+' || *c == b'-').count() <= 1;
        if integer {
            return Ok(Token::Datum(Value::Int(a.parse().unwrap())));
        }
        if a == "#t" || a == "#f" {
            return Ok(Token::Datum(Value::Bool(a == "#t")));
        }
        if a.starts_with('#') {
            return Err(format!("bad token: {a}"));
        }
        Ok(Token::Datum(Value::Sym(a)))
    }
    fn datum(&mut self) -> Result<Value> {
        let t = self.token()?;
        self.from(t)
    }
    fn from(&mut self, t: Token) -> Result<Value> {
        match t {
            Token::Datum(v) => Ok(v),
            Token::Mark(b'\'') => Ok(list(
                &[Value::Sym("quote".into()), self.datum()?],
                Value::Nil,
            )),
            Token::Mark(b'(') => {
                let mut a = Vec::new();
                loop {
                    let t = self.token()?;
                    if matches!(t, Token::Mark(b')')) {
                        return Ok(list(&a, Value::Nil));
                    }
                    if matches!(t, Token::Mark(b'.')) && !a.is_empty() {
                        let tail = self.datum()?;
                        if !matches!(self.token()?, Token::Mark(b')')) {
                            return Err("expected )".into());
                        }
                        return Ok(list(&a, tail));
                    }
                    a.push(self.from(t)?)
                }
            }
            Token::Mark(c) => Err(format!("unexpected {}", c as char)),
        }
    }
}
fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let lines = input
        .lines()
        .take_while(|s| *s != "(exit)")
        .map(|s| s.as_bytes().to_vec())
        .collect();
    let mut r = Reader {
        lines,
        row: 0,
        col: 0,
    };
    let e = global();
    let mut out = Output {
        text: String::new(),
        mid: false,
    };
    while !r.end() {
        let x = match r.datum() {
            Ok(x) => x,
            Err(err) => {
                out.line(&format!("Error: read: {err}"));
                if err == "unexpected end of input" {
                    break;
                }
                r.skip();
                continue;
            }
        };
        match evaluate(&x, &e, &mut out) {
            Ok(Value::Void) => {}
            Ok(v) => out.line(&repr(&v, true)),
            Err(err) => out.line(&format!("Error: {err}")),
        }
    }
    if out.mid {
        out.write("\n")
    }
    io::stdout().write_all(out.text.as_bytes()).unwrap();
}
