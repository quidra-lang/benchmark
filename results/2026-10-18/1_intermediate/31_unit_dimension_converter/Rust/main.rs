use std::cmp::Ordering;
use std::collections::BTreeMap;
use std::fmt::{self, Display};
use std::io::{self, Read, Write};
use std::ops::{Add, Div, Mul, Neg, Sub};

type Result<T> = std::result::Result<T, String>;

#[derive(Clone, Copy, PartialEq, Eq)]
struct Rational { n: i64, d: i64 }
impl Rational {
    const ONE: Self = Self { n: 1, d: 1 };
    fn new(mut n: i64, mut d: i64) -> Self {
        if d < 0 { n = -n; d = -d; }
        let (mut a, mut b) = (n.abs(), d);
        while b != 0 { (a, b) = (b, a % b); }
        Self { n: n / a, d: d / a }
    }
    fn integer(n: i64) -> Self { Self { n, d: 1 } }
    fn pow(mut self, mut exponent: i32) -> Self {
        if exponent < 0 { self = Self::new(self.d, self.n); exponent = -exponent; }
        let mut result = Self::ONE;
        for _ in 0..exponent { result = result * self; }
        result
    }
    fn abs(self) -> Self { Self { n: self.n.abs(), d: self.d } }
    fn decimal(self) -> String {
        let magnitude = self.n.abs();
        format!("{}{}.{:06}", if self.n < 0 { "-" } else { "" }, magnitude / self.d, magnitude % self.d * 1_000_000 / self.d)
    }
    fn notation(self, unit: &str) -> String { format!("{self} {unit} ({})", self.decimal()) }
}
impl Display for Rational {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.d == 1 { write!(out, "{}", self.n) } else { write!(out, "{}/{}", self.n, self.d) }
    }
}
impl Add for Rational { type Output = Self; fn add(self, rhs: Self) -> Self { Self::new(self.n * rhs.d + rhs.n * self.d, self.d * rhs.d) } }
impl Sub for Rational { type Output = Self; fn sub(self, rhs: Self) -> Self { Self::new(self.n * rhs.d - rhs.n * self.d, self.d * rhs.d) } }
impl Mul for Rational { type Output = Self; fn mul(self, rhs: Self) -> Self { Self::new(self.n * rhs.n, self.d * rhs.d) } }
impl Div for Rational { type Output = Self; fn div(self, rhs: Self) -> Self { Self::new(self.n * rhs.d, self.d * rhs.n) } }
impl Neg for Rational { type Output = Self; fn neg(self) -> Self { Self { n: -self.n, d: self.d } } }
impl Ord for Rational { fn cmp(&self, rhs: &Self) -> Ordering { (self.n * rhs.d).cmp(&(rhs.n * self.d)) } }
impl PartialOrd for Rational { fn partial_cmp(&self, rhs: &Self) -> Option<Ordering> { Some(self.cmp(rhs)) } }

#[derive(Clone, Copy, Default, PartialEq, Eq)]
struct Dimension([i64; 7]);
impl Dimension {
    fn combine(self, rhs: Self, sign: i64) -> Self { Self(std::array::from_fn(|i| self.0[i] + sign * rhs.0[i])) }
    fn scale(self, factor: i64) -> Self { Self(self.0.map(|x| x * factor)) }
    fn dimensionless(self) -> bool { self.0 == [0; 7] }
    fn matches(self, rhs: Self) -> Result<()> {
        if self == rhs { Ok(()) } else { Err(format!("DIMENSION MISMATCH {self} vs {rhs}")) }
    }
}
impl Display for Dimension {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        let mut first = true;
        for (name, exponent) in ["kg", "m", "s", "A", "K", "mol", "cd"].iter().zip(self.0) {
            if exponent == 0 { continue; }
            if !first { write!(out, " ")?; }
            first = false;
            write!(out, "{name}")?;
            if exponent != 1 { write!(out, "^{exponent}")?; }
        }
        if first { write!(out, "1") } else { Ok(()) }
    }
}
#[derive(Clone, Copy)]
struct Quantity { value: Rational, dim: Dimension }

fn number(text: &str) -> Result<Rational> {
    let unsigned = text.strip_prefix('-').unwrap_or(text);
    let digits = |part: &str| !part.is_empty() && part.bytes().all(|c| c.is_ascii_digit());
    let parse = |part: &str| part.parse::<i64>().unwrap();
    let value = if digits(unsigned) {
        Rational::integer(parse(unsigned))
    } else if let Some((whole, tail)) = unsigned.split_once('.') {
        if !digits(whole) || !digits(tail) { return Err(format!("BAD NUMBER {text}")); }
        let mut scale = 1;
        for _ in tail.bytes() { scale *= 10; }
        Rational::new(parse(whole) * scale + parse(tail), scale)
    } else if let Some((n, d)) = unsigned.split_once('/') {
        if !digits(n) || !digits(d) || parse(d) == 0 { return Err(format!("BAD NUMBER {text}")); }
        Rational::new(parse(n), parse(d))
    } else { return Err(format!("BAD NUMBER {text}")); };
    Ok(if text.starts_with('-') { -value } else { value })
}
fn exponent(text: &str) -> Result<i32> {
    let value = text.parse::<i32>().unwrap();
    if value == 0 || !(-3..=3).contains(&value) { Err(format!("BAD EXPONENT {text}")) } else { Ok(value) }
}
fn check_name(name: &str, variable: bool) -> Result<()> {
    if name.is_empty() || name.len() > 12 || !name.bytes().all(|c| c.is_ascii_alphabetic()) || variable && ["abs", "sqrt", "min", "max"].contains(&name) {
        Err(format!("BAD NAME {name}"))
    } else { Ok(()) }
}
fn integer_sqrt(n: i64) -> i64 {
    if n < 2 { return n; }
    let (mut x, mut next) = (n, (n + 1) / 2);
    while next < x { x = next; next = (x + n / x) / 2; }
    x
}

const KINDS: [(&str, Dimension); 29] = [
    ("dimensionless", Dimension([0,0,0,0,0,0,0])), ("length", Dimension([0,1,0,0,0,0,0])),
    ("mass", Dimension([1,0,0,0,0,0,0])), ("time", Dimension([0,0,1,0,0,0,0])),
    ("current", Dimension([0,0,0,1,0,0,0])), ("temperature", Dimension([0,0,0,0,1,0,0])),
    ("amount", Dimension([0,0,0,0,0,1,0])), ("luminous_intensity", Dimension([0,0,0,0,0,0,1])),
    ("area", Dimension([0,2,0,0,0,0,0])), ("volume", Dimension([0,3,0,0,0,0,0])),
    ("speed", Dimension([0,1,-1,0,0,0,0])), ("acceleration", Dimension([0,1,-2,0,0,0,0])),
    ("density", Dimension([1,-3,0,0,0,0,0])), ("momentum", Dimension([1,1,-1,0,0,0,0])),
    ("force", Dimension([1,1,-2,0,0,0,0])), ("energy", Dimension([1,2,-2,0,0,0,0])),
    ("power", Dimension([1,2,-3,0,0,0,0])), ("pressure", Dimension([1,-1,-2,0,0,0,0])),
    ("frequency", Dimension([0,0,-1,0,0,0,0])), ("charge", Dimension([0,0,1,1,0,0,0])),
    ("voltage", Dimension([1,2,-3,-1,0,0,0])), ("resistance", Dimension([1,2,-3,-2,0,0,0])),
    ("conductance", Dimension([-1,-2,3,2,0,0,0])), ("capacitance", Dimension([-1,-2,4,2,0,0,0])),
    ("magnetic_flux", Dimension([1,2,-2,-1,0,0,0])), ("flux_density", Dimension([1,0,-2,-1,0,0,0])),
    ("inductance", Dimension([1,2,-2,-2,0,0,0])), ("illuminance", Dimension([0,-2,0,0,0,0,1])),
    ("catalytic_activity", Dimension([0,0,-1,0,0,1,0])),
];
fn kind_dimension(name: &str) -> Option<Dimension> { KINDS.iter().find(|(key, _)| *key == name).map(|(_, dim)| *dim) }
fn kind_name(dim: Dimension) -> &'static str { KINDS.iter().find(|(_, value)| *value == dim).map_or("-", |(name, _)| *name) }

#[derive(Clone, Copy, PartialEq, Eq)]
enum TokenKind { Identifier, Number, Unit, Punctuation(u8), Invalid, End }
#[derive(Clone, Copy)]
struct Token<'a> { kind: TokenKind, start: usize, end: usize, text: &'a str }
struct Parser<'a> { source: &'a str, tokens: Vec<Token<'a>>, position: usize }
enum RawUnit<'a> {
    Number(&'a str), Name(&'a str), Power(Box<RawUnit<'a>>, &'a str), Product(Vec<(u8, RawUnit<'a>)>),
}
enum UnitExpr<'a> {
    Number(i64), Name(&'a str, Quantity), Power(Box<UnitExpr<'a>>, i32), Product(Vec<(u8, UnitExpr<'a>)>),
}
enum Expr<'a> {
    Number(&'a str), Unit(&'a str, &'a str), Variable(&'a str), Power(Box<Expr<'a>>, &'a str),
    Negative(Box<Expr<'a>>), Binary(u8, Box<Expr<'a>>, Box<Expr<'a>>), Call(&'a str, Vec<Expr<'a>>),
}
impl<'a> Parser<'a> {
    fn new(source: &'a str, quantity: bool) -> Self {
        let bytes = source.as_bytes();
        let mut tokens = Vec::new();
        let mut i = 0;
        while i < bytes.len() {
            let start = i;
            let kind;
            if bytes[i].is_ascii_alphabetic() {
                kind = TokenKind::Identifier;
                while bytes.get(i).is_some_and(u8::is_ascii_alphabetic) { i += 1; }
            } else if bytes[i].is_ascii_digit() {
                kind = TokenKind::Number;
                while bytes.get(i).is_some_and(u8::is_ascii_digit) { i += 1; }
                if quantity && bytes.get(i) == Some(&b'.') && bytes.get(i + 1).is_some_and(u8::is_ascii_digit) {
                    i += 1;
                    while bytes.get(i).is_some_and(u8::is_ascii_digit) { i += 1; }
                }
            } else if quantity && bytes[i] == b'[' && bytes[i + 1..].iter().position(|c| *c == b']').is_some_and(|end| end > 0) {
                kind = TokenKind::Unit;
                i += bytes[i + 1..].iter().position(|c| *c == b']').unwrap() + 2;
            } else {
                let punctuation = if quantity { b"+-*/^(),".as_slice() } else { b"*/^()-".as_slice() };
                kind = if punctuation.contains(&bytes[i]) { TokenKind::Punctuation(bytes[i]) } else { TokenKind::Invalid };
                i += 1;
            }
            tokens.push(Token { kind, start, end: i, text: &source[start..i] });
        }
        tokens.push(Token { kind: TokenKind::End, start: i, end: i, text: "" });
        Self { source, tokens, position: 0 }
    }
    fn current(&self) -> Token<'a> { self.tokens[self.position] }
    fn syntax(&self) -> String {
        let at = if self.current().kind == TokenKind::End { "END".to_owned() } else { (self.current().start + 1).to_string() };
        format!("SYNTAX {} AT {at}", self.source)
    }
    fn accept(&mut self, kind: TokenKind) -> bool {
        if self.current().kind != kind { return false; }
        self.position += 1; true
    }
    fn eat(&mut self, c: u8) -> bool { self.accept(TokenKind::Punctuation(c)) }
    fn expect(&mut self, c: u8) -> Result<()> { if self.eat(c) { Ok(()) } else { Err(self.syntax()) } }
    fn exponent(&mut self) -> Result<&'a str> {
        let start = self.current().start;
        self.eat(b'-');
        let token = self.current();
        if token.kind != TokenKind::Number || token.text.contains('.') { return Err(self.syntax()); }
        self.position += 1;
        Ok(&self.source[start..token.end])
    }
    fn unit_term(&mut self) -> Result<RawUnit<'a>> {
        let token = self.current();
        let mut result = if self.accept(TokenKind::Identifier) {
            RawUnit::Name(token.text)
        } else if token.kind == TokenKind::Number && !token.text.starts_with('0') {
            self.position += 1; RawUnit::Number(token.text)
        } else if self.eat(b'(') {
            let inner = self.unit_expression()?; self.expect(b')')?; inner
        } else { return Err(self.syntax()); };
        if self.eat(b'^') { result = RawUnit::Power(Box::new(result), self.exponent()?); }
        Ok(result)
    }
    fn unit_expression(&mut self) -> Result<RawUnit<'a>> {
        let mut terms = vec![(b'*', self.unit_term()?)];
        while let TokenKind::Punctuation(op @ (b'*' | b'/')) = self.current().kind {
            self.position += 1; terms.push((op, self.unit_term()?));
        }
        Ok(RawUnit::Product(terms))
    }
    fn unit_complete(mut self) -> Result<RawUnit<'a>> {
        let result = self.unit_expression()?;
        if self.current().kind != TokenKind::End { return Err(self.syntax()); }
        Ok(result)
    }
    fn primary(&mut self) -> Result<Expr<'a>> {
        let token = self.current();
        let mut result = if self.accept(TokenKind::Number) {
            if self.current().kind == TokenKind::Unit {
                let unit = self.current().text; self.position += 1;
                Expr::Unit(token.text, &unit[1..unit.len() - 1])
            } else { Expr::Number(token.text) }
        } else if self.accept(TokenKind::Unit) {
            Expr::Unit("1", &token.text[1..token.text.len() - 1])
        } else if self.accept(TokenKind::Identifier) {
            if self.eat(b'(') {
                let mut args = vec![self.expression()?];
                while self.eat(b',') { args.push(self.expression()?); }
                self.expect(b')')?; Expr::Call(token.text, args)
            } else { Expr::Variable(token.text) }
        } else if self.eat(b'(') {
            let inner = self.expression()?; self.expect(b')')?; inner
        } else { return Err(self.syntax()); };
        if self.eat(b'^') { result = Expr::Power(Box::new(result), self.exponent()?); }
        Ok(result)
    }
    fn unary(&mut self) -> Result<Expr<'a>> {
        if self.eat(b'-') { Ok(Expr::Negative(Box::new(self.unary()?))) } else { self.primary() }
    }
    fn product(&mut self) -> Result<Expr<'a>> {
        let mut result = self.unary()?;
        while let TokenKind::Punctuation(op @ (b'*' | b'/')) = self.current().kind {
            self.position += 1;
            let right = self.unary()?; result = Expr::Binary(op, Box::new(result), Box::new(right));
        }
        Ok(result)
    }
    fn expression(&mut self) -> Result<Expr<'a>> {
        let mut result = self.product()?;
        while let TokenKind::Punctuation(op @ (b'+' | b'-')) = self.current().kind {
            self.position += 1;
            let right = self.product()?; result = Expr::Binary(op, Box::new(result), Box::new(right));
        }
        Ok(result)
    }
    fn complete(mut self) -> Result<Expr<'a>> {
        let result = self.expression()?;
        if self.current().kind != TokenKind::End { return Err(self.syntax()); }
        Ok(result)
    }
}
impl<'a> RawUnit<'a> {
    fn resolve(self, db: &Database) -> Result<UnitExpr<'a>> {
        Ok(match self {
            Self::Number(text) => UnitExpr::Number(text.parse().unwrap()),
            Self::Name(name) => UnitExpr::Name(name, db.resolve(name).ok_or_else(|| format!("UNKNOWN UNIT {name}"))?),
            Self::Power(inner, text) => {
                let resolved = inner.resolve(db)?;
                UnitExpr::Power(Box::new(resolved), exponent(text)?)
            }
            Self::Product(terms) => {
                let mut resolved = Vec::new();
                for (op, term) in terms { resolved.push((op, term.resolve(db)?)); }
                UnitExpr::Product(resolved)
            }
        })
    }
}
struct Reduced<'a> { coefficient: Rational, names: Vec<(&'a str, i64)> }
impl<'a> UnitExpr<'a> {
    fn value(&self) -> Quantity {
        match self {
            Self::Number(n) => Quantity { value: Rational::integer(*n), dim: Dimension::default() },
            Self::Name(_, quantity) => *quantity,
            Self::Power(inner, k) => {
                let quantity = inner.value();
                Quantity { value: quantity.value.pow(*k), dim: quantity.dim.scale(i64::from(*k)) }
            }
            Self::Product(terms) => {
                let mut result = Quantity { value: Rational::ONE, dim: Dimension::default() };
                for (op, term) in terms {
                    let right = term.value();
                    result.value = if *op == b'*' { result.value * right.value } else { result.value / right.value };
                    result.dim = result.dim.combine(right.dim, if *op == b'*' { 1 } else { -1 });
                }
                result
            }
        }
    }
    fn reduce(&self) -> Reduced<'a> {
        match self {
            Self::Number(n) => Reduced { coefficient: Rational::integer(*n), names: Vec::new() },
            Self::Name(name, _) => Reduced { coefficient: Rational::ONE, names: vec![(*name, 1)] },
            Self::Power(inner, k) => {
                let mut result = inner.reduce(); result.coefficient = result.coefficient.pow(*k);
                for (_, count) in &mut result.names { *count *= i64::from(*k); }
                result
            }
            Self::Product(terms) => {
                let mut result = Reduced { coefficient: Rational::ONE, names: Vec::new() };
                for (op, term) in terms {
                    let right = term.reduce();
                    let sign = if *op == b'*' { 1 } else { -1 };
                    result.coefficient = if sign == 1 { result.coefficient * right.coefficient } else { result.coefficient / right.coefficient };
                    for (name, count) in right.names {
                        if let Some((_, existing)) = result.names.iter_mut().find(|(key, _)| *key == name) { *existing += sign * count; }
                        else { result.names.push((name, sign * count)); }
                    }
                }
                result
            }
        }
    }
    fn reduced_text(&self) -> String {
        let result = self.reduce();
        let mut parts = Vec::new();
        if result.coefficient != Rational::ONE { parts.push(result.coefficient.to_string()); }
        for (name, count) in result.names {
            if count != 0 { parts.push(if count == 1 { name.to_owned() } else { format!("{name}^{count}") }); }
        }
        if parts.is_empty() { "1".to_owned() } else { parts.join(" ") }
    }
}
impl Expr<'_> {
    fn evaluate(&self, db: &Database) -> Result<Quantity> {
        match self {
            Self::Number(text) => Ok(Quantity { value: number(text)?, dim: Dimension::default() }),
            Self::Unit(text, unit) => {
                let mut result = db.unit(unit)?; result.value = number(text)? * result.value; Ok(result)
            }
            Self::Variable(name) => db.variables.get(*name).copied().ok_or_else(|| format!("UNKNOWN VARIABLE {name}")),
            Self::Power(inner, text) => {
                let quantity = inner.evaluate(db)?; let k = exponent(text)?;
                if quantity.value.n == 0 && k < 0 { return Err("DIVISION BY ZERO".to_owned()); }
                Ok(Quantity { value: quantity.value.pow(k), dim: quantity.dim.scale(i64::from(k)) })
            }
            Self::Negative(inner) => { let mut result = inner.evaluate(db)?; result.value = -result.value; Ok(result) }
            Self::Binary(op, left, right) => {
                let a = left.evaluate(db)?; let b = right.evaluate(db)?;
                if *op == b'+' || *op == b'-' {
                    a.dim.matches(b.dim)?;
                    Ok(Quantity { value: if *op == b'+' { a.value + b.value } else { a.value - b.value }, dim: a.dim })
                } else {
                    if *op == b'/' && b.value.n == 0 { return Err("DIVISION BY ZERO".to_owned()); }
                    Ok(Quantity { value: if *op == b'*' { a.value * b.value } else { a.value / b.value }, dim: a.dim.combine(b.dim, if *op == b'*' { 1 } else { -1 }) })
                }
            }
            Self::Call(name, args) => {
                let arity = match *name { "abs" | "sqrt" => 1, "min" | "max" => 2, _ => return Err(format!("UNKNOWN FUNCTION {name}")) };
                if args.len() != arity { return Err(format!("BAD ARGUMENTS {name}")); }
                let mut a = args[0].evaluate(db)?;
                match *name {
                    "abs" => { a.value = a.value.abs(); Ok(a) }
                    "sqrt" => {
                        if a.value.n < 0 { return Err("NEGATIVE ROOT".to_owned()); }
                        if a.dim.0.iter().any(|x| x % 2 != 0) { return Err(format!("ODD DIMENSION {}", a.dim)); }
                        let n = integer_sqrt(a.value.n); let d = integer_sqrt(a.value.d);
                        if n * n != a.value.n || d * d != a.value.d { return Err("NOT EXACT".to_owned()); }
                        Ok(Quantity { value: Rational::new(n, d), dim: Dimension(a.dim.0.map(|x| x / 2)) })
                    }
                    _ => {
                        let b = args[1].evaluate(db)?; a.dim.matches(b.dim)?;
                        let take_left = if *name == "min" { a.value <= b.value } else { a.value >= b.value };
                        Ok(if take_left { a } else { b })
                    }
                }
            }
        }
    }
}

struct Definition { value: Rational, unit: String }
struct Unit { symbol: String, quantity: Quantity, prefix: bool, definition: Option<Definition> }
struct Database { units: Vec<Unit>, variables: BTreeMap<String, Quantity> }
impl Database {
    fn new() -> Self {
        let builtins = [
            ("m",1,1,"length",true), ("g",1,1000,"mass",true), ("s",1,1,"time",true),
            ("A",1,1,"current",true), ("K",1,1,"temperature",true), ("mol",1,1,"amount",true),
            ("cd",1,1,"luminous_intensity",true), ("N",1,1,"force",true), ("J",1,1,"energy",true),
            ("W",1,1,"power",true), ("Pa",1,1,"pressure",true), ("Hz",1,1,"frequency",true),
            ("C",1,1,"charge",true), ("V",1,1,"voltage",true), ("ohm",1,1,"resistance",true),
            ("S",1,1,"conductance",true), ("F",1,1,"capacitance",true), ("Wb",1,1,"magnetic_flux",true),
            ("T",1,1,"flux_density",true), ("H",1,1,"inductance",true), ("lx",1,1,"illuminance",true),
            ("kat",1,1,"catalytic_activity",true), ("L",1,1000,"volume",true), ("t",1000,1,"mass",false),
            ("min",60,1,"time",false), ("h",3600,1,"time",false), ("day",86400,1,"time",false),
            ("in",127,5000,"length",false), ("ft",381,1250,"length",false), ("yd",1143,1250,"length",false),
            ("mi",201168,125,"length",false), ("nmi",1852,1,"length",false), ("ha",10000,1,"area",false),
            ("kn",463,900,"speed",false), ("bar",100000,1,"pressure",true), ("atm",101325,1,"pressure",false),
            ("Torr",20265,152,"pressure",false), ("cal",523,125,"energy",true), ("Wh",3600,1,"energy",true),
            ("Ah",3600,1,"charge",true), ("dC",1,1,"temperature",false), ("dF",5,9,"temperature",false),
        ];
        let units = builtins.into_iter().map(|(symbol, n, d, kind, prefix)| Unit {
            symbol: symbol.to_owned(), quantity: Quantity { value: Rational::new(n, d), dim: kind_dimension(kind).unwrap() }, prefix, definition: None,
        }).collect();
        Self { units, variables: BTreeMap::new() }
    }
    fn resolve(&self, name: &str) -> Option<Quantity> {
        if let Some(unit) = self.units.iter().find(|unit| unit.symbol == name) { return Some(unit.quantity); }
        let prefixes = [("G",1_000_000_000,1), ("M",1_000_000,1), ("k",1000,1), ("h",100,1), ("da",10,1),
            ("d",1,10), ("c",1,100), ("m",1,1000), ("u",1,1_000_000), ("n",1,1_000_000_000)];
        for (prefix, n, d) in prefixes {
            if let Some(symbol) = name.strip_prefix(prefix) {
                if let Some(unit) = self.units[..42].iter().find(|unit| unit.prefix && unit.symbol == symbol) {
                    return Some(Quantity { value: Rational::new(n, d) * unit.quantity.value, dim: unit.quantity.dim });
                }
            }
        }
        None
    }
    fn parse_unit<'a>(&self, text: &'a str) -> Result<UnitExpr<'a>> { Parser::new(text, false).unit_complete()?.resolve(self) }
    fn unit(&self, text: &str) -> Result<Quantity> { Ok(self.parse_unit(text)?.value()) }
    fn quantity(&self, text: &str) -> Result<Quantity> { Parser::new(text, true).complete()?.evaluate(self) }
    fn simplified(&self, dim: Dimension) -> String {
        self.units.iter().find(|unit| unit.quantity.value == Rational::ONE && unit.quantity.dim == dim).map_or_else(|| dim.to_string(), |unit| unit.symbol.clone())
    }
    fn selected(&self, dim: Dimension) -> Vec<&Unit> {
        let mut units: Vec<_> = self.units.iter().filter(|unit| unit.quantity.dim == dim).collect();
        units.sort_by(|a, b| a.quantity.value.cmp(&b.quantity.value).then_with(|| a.symbol.cmp(&b.symbol)));
        units
    }
    fn command(&mut self, line: &str) -> Result<Vec<String>> {
        let w: Vec<_> = line.split(' ').collect();
        let mut output = Vec::new();
        match w[0] {
            "DEFINE" => {
                check_name(w[1], false)?;
                let value = number(w[3])?; let unit = self.unit(w[4])?;
                if kind_dimension(w[1]).is_some() || self.resolve(w[1]).is_some() { return Err(format!("NAME TAKEN {}", w[1])); }
                if value.n <= 0 { return Err(format!("NOT POSITIVE {}", w[3])); }
                let factor = value * unit.value;
                self.units.push(Unit { symbol: w[1].to_owned(), quantity: Quantity { value: factor, dim: unit.dim }, prefix: false,
                    definition: Some(Definition { value, unit: w[4].to_owned() }) });
                output.push(format!("DEFINE {} factor={factor} dim={} kind={}", w[1], unit.dim, kind_name(unit.dim)));
            }
            "UNDEF" => {
                let index = self.units.iter().position(|unit| unit.symbol == w[1]).ok_or_else(|| format!("NOT DEFINED {}", w[1]))?;
                if index < 42 { return Err(format!("BUILTIN UNIT {}", w[1])); }
                self.units.remove(index); output.push(format!("UNDEF {}", w[1]));
            }
            "DEFS" => {
                output.push(format!("DEFS count={}", self.units.len() - 42));
                for unit in &self.units[42..] {
                    let definition = unit.definition.as_ref().unwrap();
                    output.push(format!("DEF {} = {} {} factor={} dim={}", unit.symbol, definition.value, definition.unit, unit.quantity.value, unit.quantity.dim));
                }
            }
            "CONVERT" | "INVERT" => {
                let value = number(w[1])?; let from = self.unit(w[2])?; let to = self.unit(w[4])?;
                let inverse = w[0] == "INVERT";
                if inverse {
                    if from.dim.dimensionless() || !from.dim.combine(to.dim, 1).dimensionless() { return Err(format!("NOT RECIPROCAL {} vs {}", from.dim, to.dim)); }
                    if value.n == 0 { return Err("DIVISION BY ZERO".to_owned()); }
                } else { from.dim.matches(to.dim)?; }
                let mut result = value * from.value;
                if inverse { result = Rational::ONE / result; }
                result = result / to.value;
                output.push(format!("{} {value} {} = {}", w[0], w[2], result.notation(w[4])));
            }
            "DIM" | "REDUCE" | "SIMPLIFY" => {
                let expression = self.parse_unit(w[1])?; let unit = expression.value();
                output.push(match w[0] {
                    "DIM" => format!("DIM {} = {} factor={} kind={}", w[1], unit.dim, unit.value, kind_name(unit.dim)),
                    "REDUCE" => format!("REDUCE {} = {}", w[1], expression.reduced_text()),
                    _ => format!("SIMPLIFY {} = {}", w[1], unit.value.notation(&self.simplified(unit.dim))),
                });
            }
            "ADD" | "SUB" | "MUL" | "DIV" | "COMPARE" => {
                let a = number(w[1])?; let first = self.unit(w[2])?;
                let b = number(w[3])?; let second = self.unit(w[4])?;
                let target = w.len() == 7;
                let destination = if target { self.unit(w[6])? } else { first };
                if ["ADD", "SUB", "COMPARE"].contains(&w[0]) {
                    first.dim.matches(second.dim)?;
                    if target { first.dim.matches(destination.dim)?; }
                    let left = a * first.value; let right = b * second.value;
                    if w[0] == "COMPARE" {
                        let relation = match left.cmp(&right) { Ordering::Less => '<', Ordering::Equal => '=', Ordering::Greater => '>' };
                        let ratio = if right.n == 0 { "undefined".to_owned() } else { (left / right).to_string() };
                        output.push(format!("COMPARE {a} {} {relation} {b} {} ratio={ratio}", w[2], w[4]));
                    } else {
                        let op = if w[0] == "ADD" { '+' } else { '-' };
                        let sum = if op == '+' { left + right } else { left - right };
                        let result = sum / destination.value;
                        output.push(format!("{} {a} {} {op} {b} {} = {}", w[0], w[2], w[4], result.notation(if target { w[6] } else { w[2] })));
                    }
                } else {
                    let product = w[0] == "MUL";
                    let dim = first.dim.combine(second.dim, if product { 1 } else { -1 });
                    if !product && b.n == 0 { return Err("DIVISION BY ZERO".to_owned()); }
                    if target { dim.matches(destination.dim)?; }
                    let raw = if product { a * b } else { a / b };
                    let left = a * first.value; let right = b * second.value;
                    let coherent = if product { left * right } else { left / right };
                    let op = if product { '*' } else { '/' };
                    let prefix = format!("{} {a} {} {op} {b} {} = ", w[0], w[2], w[4]);
                    if target { output.push(prefix + &(coherent / destination.value).notation(w[6])); }
                    else {
                        let right_unit = if !product && w[4].contains(['*', '/']) { format!("({})", w[4]) } else { w[4].to_owned() };
                        output.push(format!("{prefix}{raw} {}{op}{right_unit} = {}", w[2], coherent.notation(&self.simplified(dim))));
                    }
                }
            }
            "TEMP" => {
                let value = number(w[1])?;
                for scale in [w[2], w[4]] { if !["C", "F", "K", "R"].contains(&scale) { return Err(format!("UNKNOWN SCALE {scale}")); } }
                let kelvin = match w[2] {
                    "C" => value + Rational::new(5463, 20),
                    "F" => (value + Rational::new(45967, 100)) * Rational::new(5, 9),
                    "R" => value * Rational::new(5, 9), _ => value,
                };
                if kelvin.n < 0 { return Err("BELOW ABSOLUTE ZERO".to_owned()); }
                let result = match w[4] {
                    "C" => kelvin - Rational::new(5463, 20),
                    "F" => kelvin * Rational::new(9, 5) - Rational::new(45967, 100),
                    "R" => kelvin * Rational::new(9, 5), _ => kelvin,
                };
                output.push(format!("TEMP {value} {} = {}", w[2], result.notation(w[4])));
            }
            "LIST" => {
                let dim = match kind_dimension(w[1]) { Some(dim) => dim, None => self.unit(w[1])?.dim };
                let units = self.selected(dim);
                output.push(format!("LIST {} dim={dim} kind={} count={}", w[1], kind_name(dim), units.len()));
                for unit in units { output.push(format!("UNIT {} factor={} origin={} prefix={}", unit.symbol, unit.quantity.value,
                    if unit.definition.is_none() { "builtin" } else { "user" }, if unit.prefix { "yes" } else { "no" })); }
            }
            "TABLE" => {
                let value = number(w[1])?; let from = self.unit(w[2])?; let units = self.selected(from.dim);
                output.push(format!("TABLE {value} {} dim={} count={}", w[2], from.dim, units.len()));
                for unit in units { output.push(format!("ROW {}", ((value * from.value) / unit.quantity.value).notation(&unit.symbol))); }
            }
            "AUTO" => {
                let value = number(w[1])?; let unit = self.unit(w[2])?;
                let reference = self.units[..42].iter().find(|item| item.prefix && item.quantity.dim == unit.dim)
                    .ok_or_else(|| format!("NO PREFIXABLE UNIT {}", unit.dim))?;
                let scaled = (value * unit.value) / reference.quantity.value;
                let magnitude = scaled.abs(); let mut k = 0;
                if magnitude.n != 0 {
                    if magnitude >= Rational::ONE {
                        while k < 9 && magnitude >= Rational::integer(10).pow(k + 3) { k += 3; }
                    } else {
                        while k > -9 && magnitude < Rational::integer(10).pow(k) { k -= 3; }
                    }
                }
                let prefix = ["n", "u", "m", "", "k", "M", "G"][((k + 9) / 3) as usize];
                let symbol = format!("{prefix}{}", reference.symbol);
                output.push(format!("AUTO {value} {} = {}", w[2], (scaled / Rational::integer(10).pow(k)).notation(&symbol)));
            }
            "SPLIT" => {
                let value = number(w[1])?; let unit = self.unit(w[2])?;
                let parts: Vec<_> = w[4].split(',').collect();
                let mut destinations = Vec::new();
                for part in &parts { destinations.push(self.unit(part)?); }
                if value.n < 0 { return Err("NEGATIVE VALUE".to_owned()); }
                for destination in &destinations { unit.dim.matches(destination.dim)?; }
                if destinations.windows(2).any(|pair| pair[0].value <= pair[1].value) { return Err("UNIT ORDER".to_owned()); }
                let mut remaining = value * unit.value; let mut pieces = Vec::new();
                for i in 0..parts.len() - 1 {
                    let quotient = remaining / destinations[i].value; let count = quotient.n / quotient.d;
                    remaining = remaining - Rational::integer(count) * destinations[i].value;
                    pieces.push(format!("{count} {}", parts[i]));
                }
                pieces.push((remaining / destinations.last().unwrap().value).notation(parts.last().unwrap()));
                output.push(format!("SPLIT {value} {} = {}", w[2], pieces.join(" ")));
            }
            "LET" => {
                check_name(w[1], true)?; let quantity = self.quantity(w[3])?;
                self.variables.insert(w[1].to_owned(), quantity);
                output.push(format!("LET {} = {}", w[1], quantity.value.notation(&self.simplified(quantity.dim))));
            }
            "EVAL" => {
                let quantity = self.quantity(w[1])?;
                let result = if w.len() == 4 {
                    let unit = self.unit(w[3])?; quantity.dim.matches(unit.dim)?;
                    (quantity.value / unit.value).notation(w[3])
                } else { quantity.value.notation(&self.simplified(quantity.dim)) };
                output.push(format!("EVAL {} = {result}", w[1]));
            }
            "VARS" => {
                output.push(format!("VARS count={}", self.variables.len()));
                for (name, quantity) in &self.variables { output.push(format!("VAR {name} = {}", quantity.value.notation(&self.simplified(quantity.dim)))); }
            }
            _ => return Err(format!("UNKNOWN COMMAND {}", w[0])),
        }
        Ok(output)
    }
}

fn main() -> io::Result<()> {
    let mut input = String::new(); io::stdin().read_to_string(&mut input)?;
    let mut lines = input.lines(); let count: usize = lines.next().unwrap().parse().unwrap();
    let mut database = Database::new(); let mut out = io::BufWriter::new(io::stdout().lock());
    for line in lines.take(count) {
        match database.command(line) {
            Ok(output) => for text in output { writeln!(out, "{text}")?; },
            Err(error) => writeln!(out, "ERROR {error}")?,
        }
    }
    out.flush()
}
