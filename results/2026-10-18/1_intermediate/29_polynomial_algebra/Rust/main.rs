use std::cmp::Ordering;
use std::collections::BTreeMap;
use std::fmt;
use std::io::{self, BufRead, Write};
use std::ops::{Add, Div, Mul, Neg, Sub};

#[derive(Debug)]
enum Error {
    Syntax(Option<usize>), Unknown(String), DivisionByZero, NonconstantDivisor, DegreeLimit,
    SameName, ZeroDenominator, ZeroPolynomial, BadInterval, DegreeTooLow, NotCoprime,
    DuplicateX(Fraction), UnknownKind(String),
}
impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let text = match self {
            Self::Syntax(Some(position)) => return write!(f, "ERROR SYNTAX AT {position}"),
            Self::Syntax(None) => "SYNTAX AT END",
            Self::Unknown(name) => return write!(f, "ERROR UNKNOWN {name}"),
            Self::DuplicateX(value) => return write!(f, "ERROR DUPLICATE X {value}"),
            Self::UnknownKind(kind) => return write!(f, "ERROR UNKNOWN KIND {kind}"),
            Self::DivisionByZero => "DIVISION BY ZERO", Self::NonconstantDivisor => "NONCONSTANT DIVISOR",
            Self::DegreeLimit => "DEGREE LIMIT", Self::SameName => "SAME NAME",
            Self::ZeroDenominator => "ZERO DENOMINATOR", Self::ZeroPolynomial => "ZERO POLYNOMIAL",
            Self::BadInterval => "BAD INTERVAL", Self::DegreeTooLow => "DEGREE TOO LOW",
            Self::NotCoprime => "NOT COPRIME",
        };
        write!(f, "ERROR {text}")
    }
}
type CalcResult<T> = Result<T, Error>;

fn gcd(mut a: i64, mut b: i64) -> i64 {
    a = a.abs();
    b = b.abs();
    while b != 0 { (a, b) = (b, a % b); }
    a
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct Fraction { n: i64, d: i64 }
impl Fraction {
    const ZERO: Self = Self { n: 0, d: 1 };
    const ONE: Self = Self { n: 1, d: 1 };
    fn new(mut n: i64, mut d: i64) -> Self {
        if d < 0 { n = -n; d = -d; }
        let divisor = gcd(n, d);
        Self { n: n / divisor, d: d / divisor }
    }
    fn integer(n: i64) -> Self { Self { n, d: 1 } }
    fn parse(text: &str) -> CalcResult<Self> {
        let (n, d) = match text.split_once('/') {
            Some((n, d)) => (n.parse().unwrap(), d.parse().unwrap()),
            None => (text.parse().unwrap(), 1),
        };
        if d == 0 { Err(Error::ZeroDenominator) } else { Ok(Self::new(n, d)) }
    }
    fn abs(self) -> Self { Self { n: self.n.abs(), d: self.d } }
    fn pow(self, n: u32) -> Self {
        let mut result = Self::ONE;
        for _ in 0..n { result = result * self; }
        result
    }
}
impl Add for Fraction {
    type Output = Self;
    fn add(self, b: Self) -> Self { Self::new(self.n * b.d + b.n * self.d, self.d * b.d) }
}
impl Sub for Fraction {
    type Output = Self;
    fn sub(self, b: Self) -> Self { Self::new(self.n * b.d - b.n * self.d, self.d * b.d) }
}
impl Mul for Fraction {
    type Output = Self;
    fn mul(self, b: Self) -> Self { Self::new(self.n * b.n, self.d * b.d) }
}
impl Div for Fraction {
    type Output = Self;
    fn div(self, b: Self) -> Self { Self::new(self.n * b.d, self.d * b.n) }
}
impl Neg for Fraction {
    type Output = Self;
    fn neg(self) -> Self { Self { n: -self.n, d: self.d } }
}
impl Ord for Fraction {
    fn cmp(&self, other: &Self) -> Ordering { (self.n * other.d).cmp(&(other.n * self.d)) }
}
impl PartialOrd for Fraction {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> { Some(self.cmp(other)) }
}
impl fmt::Display for Fraction {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.d == 1 { write!(f, "{}", self.n) } else { write!(f, "{}/{}", self.n, self.d) }
    }
}

#[derive(Clone, Default)]
struct Polynomial(Vec<Fraction>);
impl Polynomial {
    fn new(mut values: Vec<Fraction>) -> Self {
        while values.last().is_some_and(|c| c.n == 0) { values.pop(); }
        Self(values)
    }
    fn zero() -> Self { Self::default() }
    fn constant(value: Fraction) -> Self { Self::new(vec![value]) }
    fn one() -> Self { Self::constant(Fraction::ONE) }
    fn linear(value: Fraction, slope: Fraction) -> Self { Self::new(vec![value, slope]) }
    fn is_zero(&self) -> bool { self.0.is_empty() }
    fn degree(&self) -> i32 { self.0.len() as i32 - 1 }
    fn leading(&self) -> Fraction { *self.0.last().unwrap() }
    fn coefficient(&self, i: usize) -> Fraction { self.0.get(i).copied().unwrap_or(Fraction::ZERO) }
    fn add(&self, b: &Self) -> Self {
        Self::new((0..self.0.len().max(b.0.len())).map(|i| self.coefficient(i) + b.coefficient(i)).collect())
    }
    fn sub(&self, b: &Self) -> Self {
        Self::new((0..self.0.len().max(b.0.len())).map(|i| self.coefficient(i) - b.coefficient(i)).collect())
    }
    fn neg(&self) -> Self { Self(self.0.iter().map(|c| -*c).collect()) }
    fn scale(&self, value: Fraction) -> Self { Self::new(self.0.iter().map(|c| value * *c).collect()) }
    fn divide_scalar(&self, value: Fraction) -> Self { Self::new(self.0.iter().map(|c| *c / value).collect()) }
    fn mul(&self, b: &Self) -> Self {
        if self.is_zero() || b.is_zero() { return Self::zero(); }
        let mut result = vec![Fraction::ZERO; self.0.len() + b.0.len() - 1];
        for (i, &a) in self.0.iter().enumerate() {
            for (j, &b) in b.0.iter().enumerate() { result[i + j] = result[i + j] + a * b; }
        }
        Self::new(result)
    }
    fn pow(&self, n: u32) -> Self {
        if n != 0 && self.is_zero() { return Self::zero(); }
        if self.0.len() == 1 && self.0[0].d == 1 && self.0[0].n.abs() == 1 {
            return Self::constant(Fraction::integer(if self.0[0].n < 0 && n % 2 == 1 { -1 } else { 1 }));
        }
        let mut result = Self::one();
        for _ in 0..n { result = result.mul(self); }
        result
    }
    fn divmod(&self, b: &Self) -> (Self, Self) {
        let count = if self.0.len() >= b.0.len() { self.0.len() - b.0.len() + 1 } else { 0 };
        let mut q = vec![Fraction::ZERO; count];
        let mut r = self.0.clone();
        while !r.is_empty() && r.len() >= b.0.len() {
            let factor = *r.last().unwrap() / b.leading();
            let shift = r.len() - b.0.len();
            q[shift] = factor;
            for (j, &c) in b.0.iter().enumerate() { r[shift + j] = r[shift + j] - factor * c; }
            while r.last().is_some_and(|c| c.n == 0) { r.pop(); }
        }
        (Self::new(q), Self(r))
    }
    fn monic(&self) -> Self { if self.is_zero() { Self::zero() } else { self.divide_scalar(self.leading()) } }
    fn derivative(&self) -> Self {
        Self(self.0.iter().enumerate().skip(1).map(|(i, &c)| Fraction::integer(i as i64) * c).collect())
    }
    fn differentiate(&self, n: u32) -> Self {
        let mut result = self.clone();
        for _ in 0..n {
            if result.is_zero() { break; }
            result = result.derivative();
        }
        result
    }
    fn integral(&self) -> Self {
        let mut result = vec![Fraction::ZERO];
        for (i, &c) in self.0.iter().enumerate() { result.push(c / Fraction::integer(i as i64 + 1)); }
        Self::new(result)
    }
    fn evaluate(&self, point: Fraction) -> Fraction {
        let mut result = Fraction::ZERO;
        for &c in self.0.iter().rev() { result = result * point + c; }
        result
    }
    fn compose(&self, inner: &Self) -> Self {
        let mut result = Self::zero();
        for &c in self.0.iter().rev() { result = result.mul(inner).add(&Self::constant(c)); }
        result
    }
    fn gcd(&self, b: &Self) -> Self {
        let (mut a, mut b) = (self.clone(), b.clone());
        while !b.is_zero() {
            let remainder = a.divmod(&b).1;
            (a, b) = (b, remainder);
        }
        a.monic()
    }
    fn extended_gcd(&self, b: &Self) -> Bezout {
        let (mut r0, mut r1) = (self.clone(), b.clone());
        let (mut s0, mut s1) = (Self::one(), Self::zero());
        let (mut t0, mut t1) = (Self::zero(), Self::one());
        while !r1.is_zero() {
            let (q, r) = r0.divmod(&r1);
            let s = s0.sub(&q.mul(&s1));
            let t = t0.sub(&q.mul(&t1));
            (r0, r1) = (r1, r);
            (s0, s1) = (s1, s);
            (t0, t1) = (t1, t);
        }
        if r0.is_zero() { Bezout { g: r0, s: s0, t: t0 } }
        else { Bezout { g: r0.monic(), s: s0.divide_scalar(r0.leading()), t: t0.divide_scalar(r0.leading()) } }
    }
    fn content(&self) -> Fraction {
        let (mut lcm, mut divisor) = (1, 0);
        for c in &self.0 {
            lcm = lcm * c.d / gcd(lcm, c.d);
            divisor = gcd(divisor, c.n);
        }
        Fraction::new(if self.leading().n < 0 { -divisor } else { divisor }, lcm)
    }
    fn primitive(&self) -> Self { self.divide_scalar(self.content()) }
    fn square_free(&self) -> Self {
        if self.degree() < 1 { self.clone() } else { self.divmod(&self.gcd(&self.derivative())).0 }
    }
    fn is_one(&self) -> bool { self.0.as_slice() == [Fraction::ONE] }
    fn check_product(&self, b: &Self) -> CalcResult<()> {
        if !self.is_zero() && !b.is_zero() && self.degree() + b.degree() > 30 { Err(Error::DegreeLimit) } else { Ok(()) }
    }
    fn check_power(&self, n: u32) -> CalcResult<()> {
        if !self.is_zero() && self.degree() as i64 * n as i64 > 30 { Err(Error::DegreeLimit) } else { Ok(()) }
    }
    fn check_composition(&self, b: &Self) -> CalcResult<()> {
        if self.degree() >= 1 && b.degree() >= 1 && self.degree() * b.degree() > 30 { Err(Error::DegreeLimit) } else { Ok(()) }
    }
    fn require_nonzero(&self) -> CalcResult<()> { if self.is_zero() { Err(Error::ZeroPolynomial) } else { Ok(()) } }
    fn require_divisor(&self) -> CalcResult<()> { if self.is_zero() { Err(Error::DivisionByZero) } else { Ok(()) } }
    fn require_degree(&self) -> CalcResult<()> { if self.degree() == 0 { Err(Error::DegreeTooLow) } else { Ok(()) } }
    fn format(&self, variable: &str) -> String {
        let mut result = String::new();
        for (i, &c) in self.0.iter().enumerate().rev() {
            if c.n == 0 { continue; }
            if result.is_empty() { if c.n < 0 { result.push('-'); } }
            else { result.push_str(if c.n < 0 { " - " } else { " + " }); }
            if i == 0 || c.abs() != Fraction::ONE { result.push_str(&c.abs().to_string()); }
            if i > 0 { result.push_str(variable); }
            if i > 1 { result.push_str(&format!("^{i}")); }
        }
        if result.is_empty() { result.push('0'); }
        result
    }
}
struct Bezout { g: Polynomial, s: Polynomial, t: Polynomial }

enum Expression {
    Number(u32), X, Name(String, u32), Negative(Box<Expression>),
    Binary(u8, Box<Expression>, Box<Expression>), Power(Box<Expression>, u32),
    Compose(Box<Expression>, Box<Expression>),
}
impl Expression {
    fn evaluate(&self, names: &BTreeMap<String, Polynomial>) -> CalcResult<Polynomial> {
        match self {
            Self::Number(n) => Ok(Polynomial::constant(Fraction::integer(*n as i64))),
            Self::X => Ok(Polynomial::linear(Fraction::ZERO, Fraction::ONE)),
            Self::Name(name, n) => names.get(name).map(|p| p.differentiate(*n)).ok_or_else(|| Error::Unknown(name.clone())),
            Self::Negative(expression) => Ok(expression.evaluate(names)?.neg()),
            Self::Power(expression, n) => {
                let value = expression.evaluate(names)?;
                value.check_power(*n)?;
                Ok(value.pow(*n))
            }
            Self::Binary(op, left, right) => {
                let a = left.evaluate(names)?;
                let b = right.evaluate(names)?;
                match op {
                    b'+' => Ok(a.add(&b)), b'-' => Ok(a.sub(&b)),
                    b'*' => { a.check_product(&b)?; Ok(a.mul(&b)) }
                    b'/' => {
                        b.require_divisor()?;
                        if b.degree() >= 1 { return Err(Error::NonconstantDivisor); }
                        Ok(a.divide_scalar(b.coefficient(0)))
                    }
                    _ => unreachable!(),
                }
            }
            Self::Compose(function, argument) => {
                let a = function.evaluate(names)?;
                let b = argument.evaluate(names)?;
                a.check_composition(&b)?;
                Ok(a.compose(&b))
            }
        }
    }
}

#[derive(Clone)]
enum TokenKind { Number(u32), Name(String), Symbol(u8), End }
struct Token { kind: TokenKind, position: usize }
struct Parser { tokens: Vec<Token>, position: usize }
impl Parser {
    fn new(text: &str) -> Self {
        let bytes = text.as_bytes();
        let mut tokens = Vec::new();
        let mut i = 0;
        while i < bytes.len() {
            if bytes[i] == b' ' { i += 1; continue; }
            let start = i;
            i += 1;
            let kind = if bytes[start].is_ascii_digit() {
                while i < bytes.len() && bytes[i].is_ascii_digit() { i += 1; }
                TokenKind::Number(text[start..i].parse().unwrap())
            } else if bytes[start].is_ascii_uppercase() {
                while i < bytes.len() && (bytes[i].is_ascii_uppercase() || bytes[i].is_ascii_digit()) { i += 1; }
                TokenKind::Name(text[start..i].to_owned())
            } else { TokenKind::Symbol(bytes[start]) };
            tokens.push(Token { kind, position: start + 1 });
        }
        tokens.push(Token { kind: TokenKind::End, position: text.len() + 1 });
        Self { tokens, position: 0 }
    }
    fn current(&self) -> &TokenKind { &self.tokens[self.position].kind }
    fn syntax(&self) -> Error {
        Error::Syntax(if matches!(self.current(), TokenKind::End) { None } else { Some(self.tokens[self.position].position) })
    }
    fn accept(&mut self, symbol: u8) -> bool {
        if matches!(self.current(), TokenKind::Symbol(c) if *c == symbol) { self.position += 1; true } else { false }
    }
    fn expect(&mut self, symbol: u8) -> CalcResult<()> { if self.accept(symbol) { Ok(()) } else { Err(self.syntax()) } }
    fn parse(mut self) -> CalcResult<Expression> {
        let expression = self.expression()?;
        if !matches!(self.current(), TokenKind::End) { return Err(self.syntax()); }
        Ok(expression)
    }
    fn expression(&mut self) -> CalcResult<Expression> {
        let negative = self.accept(b'-');
        let mut result = self.term()?;
        if negative { result = Expression::Negative(Box::new(result)); }
        loop {
            let op = if self.accept(b'+') { b'+' } else if self.accept(b'-') { b'-' } else { break; };
            result = Expression::Binary(op, Box::new(result), Box::new(self.term()?));
        }
        Ok(result)
    }
    fn term(&mut self) -> CalcResult<Expression> {
        let mut result = self.factor()?;
        loop {
            let op = if self.accept(b'*') { b'*' }
                else if self.accept(b'/') { b'/' }
                else if matches!(self.current(), TokenKind::Name(_) | TokenKind::Symbol(b'x' | b'(')) { b'*' }
                else { break; };
            result = Expression::Binary(op, Box::new(result), Box::new(self.factor()?));
        }
        Ok(result)
    }
    fn factor(&mut self) -> CalcResult<Expression> {
        let mut result = self.primary()?;
        if self.accept(b'^') {
            let TokenKind::Number(n) = self.current().clone() else { return Err(self.syntax()); };
            self.position += 1;
            result = Expression::Power(Box::new(result), n);
        }
        Ok(result)
    }
    fn primary(&mut self) -> CalcResult<Expression> {
        match self.current().clone() {
            TokenKind::Number(n) => { self.position += 1; Ok(Expression::Number(n)) }
            TokenKind::Symbol(b'x') => { self.position += 1; Ok(Expression::X) }
            TokenKind::Name(name) => {
                self.position += 1;
                let mut order = 0;
                while self.accept(b'\'') { order += 1; }
                let reference = Expression::Name(name, order);
                if !self.accept(b'(') { return Ok(reference); }
                let argument = self.expression()?;
                self.expect(b')')?;
                Ok(Expression::Compose(Box::new(reference), Box::new(argument)))
            }
            TokenKind::Symbol(b'(') => {
                self.position += 1;
                let expression = self.expression()?;
                self.expect(b')')?;
                Ok(expression)
            }
            _ => Err(self.syntax()),
        }
    }
}

struct RootResult { content: Fraction, remaining: Polynomial, roots: Vec<(Fraction, u32)> }
fn rational_roots(a: &Polynomial) -> RootResult {
    let content = a.content();
    let primitive = a.divide_scalar(content);
    let zeros = primitive.0.iter().take_while(|c| c.n == 0).count();
    let mut p = Polynomial(primitive.0[zeros..].to_vec());
    let first = p.0[0].n.abs();
    let last = p.leading().n;
    let numerators: Vec<_> = (1..=first).filter(|s| first % s == 0).collect();
    let denominators: Vec<_> = (1..=last).filter(|t| last % t == 0).collect();
    let mut candidates = Vec::new();
    for s in numerators {
        for &t in &denominators {
            if gcd(s, t) == 1 { candidates.extend([Fraction::new(-s, t), Fraction::new(s, t)]); }
        }
    }
    candidates.sort();
    let mut roots = Vec::new();
    for r in candidates {
        let mut multiplicity = 0;
        while p.degree() >= 1 && p.evaluate(r) == Fraction::ZERO {
            p = p.divmod(&Polynomial::linear(Fraction::integer(-r.n), Fraction::integer(r.d))).0;
            multiplicity += 1;
        }
        if multiplicity != 0 { roots.push((r, multiplicity)); }
    }
    if zeros != 0 { roots.push((Fraction::ZERO, zeros as u32)); }
    roots.sort_by_key(|r| r.0);
    RootResult { content, remaining: p, roots }
}
fn append_factor(text: &mut String, p: &Polynomial, multiplicity: u32, simple_x: bool) {
    text.push_str(" * ");
    if simple_x { text.push('x'); } else { text.push_str(&format!("({})", p.format("x"))); }
    if multiplicity > 1 { text.push_str(&format!("^{multiplicity}")); }
}
fn square_free_factors(a: &Polynomial) -> Vec<(Polynomial, u32)> {
    if a.degree() < 1 { return Vec::new(); }
    let w0 = a.monic();
    let mut c = w0.gcd(&w0.derivative());
    let mut w = w0.divmod(&c).0;
    let mut result = Vec::new();
    let mut multiplicity = 1;
    while w.degree() >= 1 {
        let y = w.gcd(&c);
        let f = w.divmod(&y).0;
        if f.degree() >= 1 { result.push((f.primitive(), multiplicity)); }
        c = c.divmod(&y).0;
        w = y;
        multiplicity += 1;
    }
    result
}

#[derive(Clone, Copy, Eq, PartialEq, Ord, PartialOrd)]
enum Bound { NegativeInfinity, Finite(Fraction), PositiveInfinity }
impl Bound {
    fn parse(text: &str) -> CalcResult<Self> {
        match text {
            "-inf" => Ok(Self::NegativeInfinity), "inf" => Ok(Self::PositiveInfinity),
            _ => Ok(Self::Finite(Fraction::parse(text)?)),
        }
    }
}
impl fmt::Display for Bound {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::NegativeInfinity => write!(f, "-inf"), Self::PositiveInfinity => write!(f, "inf"),
            Self::Finite(value) => write!(f, "{value}"),
        }
    }
}
fn sturm_sequence(a: &Polynomial) -> Vec<Polynomial> {
    let mut p = a.square_free();
    let mut q = p.derivative();
    let mut result = vec![p.clone()];
    while !q.is_zero() {
        result.push(q.clone());
        let remainder = p.divmod(&q).1.neg();
        (p, q) = (q, remainder);
    }
    result
}
fn variations(sequence: &[Polynomial], point: Bound) -> i32 {
    let (mut previous, mut count) = (0, 0);
    for p in sequence {
        let mut sign = match point {
            Bound::Finite(value) => p.evaluate(value).n.signum(),
            _ => p.leading().n.signum(),
        };
        if point == Bound::NegativeInfinity && p.degree() % 2 == 1 { sign = -sign; }
        if sign != 0 { if previous != 0 && previous != sign { count += 1; } previous = sign; }
    }
    count
}
fn root_count(sequence: &[Polynomial], low: Bound, high: Bound) -> i32 {
    let left = variations(sequence, low);
    let right = variations(sequence, high);
    left - right
}
fn examine(sequence: &[Polynomial], mut low: Fraction, mut high: Fraction, width: Fraction,
    result: &mut Vec<(Fraction, Fraction)>) {
    let count = root_count(sequence, Bound::Finite(low), Bound::Finite(high));
    if count >= 2 {
        let middle = (low + high) / Fraction::integer(2);
        examine(sequence, low, middle, width, result);
        examine(sequence, middle, high, width, result);
    } else if count == 1 {
        while high - low > width {
            let middle = (low + high) / Fraction::integer(2);
            if root_count(sequence, Bound::Finite(low), Bound::Finite(middle)) >= 1 { high = middle; }
            else { low = middle; }
        }
        result.push((low, high));
    }
}
fn isolate(a: &Polynomial, n: u32) -> Vec<(Fraction, Fraction)> {
    let sequence = sturm_sequence(a);
    let first = &sequence[0];
    let mut maximum = Fraction::ZERO;
    for &c in &first.0[..first.0.len() - 1] { maximum = maximum.max((c / first.leading()).abs()); }
    let beta = Fraction::ONE + maximum;
    let width = Fraction::new(1, 1_i64 << n);
    let mut result = Vec::new();
    examine(&sequence, -beta, beta, width, &mut result);
    result
}
fn resultant(a: &Polynomial, b: &Polynomial) -> Fraction {
    let (mut p, mut q) = (a.clone(), b.clone());
    let mut r = Fraction::ONE;
    while q.degree() >= 1 {
        let t = p.divmod(&q).1;
        if t.is_zero() { return Fraction::ZERO; }
        r = r * q.leading().pow((p.degree() - t.degree()) as u32);
        if p.degree() * q.degree() % 2 == 1 { r = -r; }
        (p, q) = (q, t);
    }
    r * q.0[0].pow(p.degree() as u32)
}
fn interpolate(values: &[Fraction]) -> CalcResult<Polynomial> {
    let x: Vec<_> = values.iter().step_by(2).copied().collect();
    let mut d: Vec<_> = values.iter().skip(1).step_by(2).copied().collect();
    for j in 1..x.len() {
        for i in 0..j { if x[j] == x[i] { return Err(Error::DuplicateX(x[j])); } }
    }
    for j in 1..x.len() {
        for i in (j..x.len()).rev() { d[i] = (d[i] - d[i - 1]) / (x[i] - x[i - j]); }
    }
    let mut result = Polynomial::zero();
    for i in (0..x.len()).rev() {
        result = result.mul(&Polynomial::linear(-x[i], Fraction::ONE)).add(&Polynomial::constant(d[i]));
    }
    Ok(result)
}
fn special(kind: &str, n: u32) -> CalcResult<Polynomial> {
    if !matches!(kind, "chebyshev" | "chebyshev2" | "legendre" | "hermite" | "laguerre") {
        return Err(Error::UnknownKind(kind.to_owned()));
    }
    if n > 30 { return Err(Error::DegreeLimit); }
    let mut a = Polynomial::one();
    let mut b = if kind == "laguerre" { Polynomial::linear(Fraction::ONE, Fraction::integer(-1)) }
        else { Polynomial::linear(Fraction::ZERO, Fraction::integer(if matches!(kind, "chebyshev2" | "hermite") { 2 } else { 1 })) };
    if n == 0 { return Ok(a); }
    for j in 1..n as i64 {
        let factor = if kind == "laguerre" { Polynomial::linear(Fraction::integer(2 * j + 1), Fraction::integer(-1)) }
            else { Polynomial::linear(Fraction::ZERO, Fraction::integer(if kind == "legendre" { 2 * j + 1 } else { 2 })) };
        let multiplier = Fraction::integer(match kind { "legendre" | "laguerre" => j, "hermite" => 2 * j, _ => 1 });
        let mut next = factor.mul(&b).sub(&a.scale(multiplier));
        if matches!(kind, "legendre" | "laguerre") { next = next.scale(Fraction::new(1, j + 1)); }
        (a, b) = (b, next);
    }
    Ok(b)
}

#[derive(Default)]
struct Response { stores: Vec<(String, Polynomial)>, output: Vec<String>, deletion: Option<String> }
impl Response {
    fn save(&mut self, name: &str, value: Polynomial) {
        self.output.push(format!("{name} = {}", value.format("x")));
        self.stores.push((name.to_owned(), value));
    }
}
#[derive(Default)]
struct Calculator { names: BTreeMap<String, Polynomial> }
impl Calculator {
    fn process(&mut self, line: &str) -> CalcResult<Vec<String>> {
        let mut response = Response::default();
        if line.starts_with("DEF ") {
            let mut parts = line.splitn(3, ' ');
            parts.next();
            let name = parts.next().unwrap();
            let expression = Parser::new(parts.next().unwrap()).parse()?;
            response.save(name, expression.evaluate(&self.names)?);
        } else {
            let words: Vec<_> = line.split_ascii_whitespace().collect();
            let command = words[0];
            if (command == "DIV" && words[1] == words[2]) || (command == "XGCD" &&
                (words[1] == words[2] || words[1] == words[3] || words[2] == words[3])) { return Err(Error::SameName); }
            let positions: &[usize] = match command {
                "ADD" | "SUB" | "MUL" | "GCD" | "LCM" | "INVMOD" | "COMPOSE" => &[2, 3],
                "POW" | "DERIV" | "INTEG" | "TANGENT" => &[2], "MODPOW" => &[2, 4],
                "DIV" => &[3, 4], "XGCD" => &[4, 5], "CRT" => &[2, 3, 4, 5], "RESULTANT" => &[1, 2],
                "LIST" | "INTERP" | "SPECIAL" => &[], _ => &[1],
            };
            let p: Vec<_> = positions.iter().map(|&i| self.names.get(words[i]).cloned()
                .ok_or_else(|| Error::Unknown(words[i].to_owned()))).collect::<CalcResult<_>>()?;
            let start = match command { "AREA" | "TAYLOR" | "EVAL" | "INTERP" => 2, "TANGENT" => 3, _ => words.len() };
            let values = words[start..].iter().map(|text| Fraction::parse(text)).collect::<CalcResult<Vec<_>>>()?;
            let bounds = if command == "STURM" { Some((Bound::parse(words[2])?, Bound::parse(words[3])?)) } else { None };
            let zero = Polynomial::zero();
            let a = p.first().unwrap_or(&zero);
            let b = p.get(1).unwrap_or(&zero);
            match command {
                "PRINT" => response.output.push(format!("{} = {}", words[1], a.format("x"))),
                "DELETE" => { response.deletion = Some(words[1].to_owned()); response.output.push(format!("deleted {}", words[1])); }
                "LIST" => {
                    for (name, value) in &self.names { response.output.push(format!("{name} = {}", value.format("x"))); }
                    if self.names.is_empty() { response.output.push("no polynomials".to_owned()); }
                }
                "DEGREE" => response.output.push(format!("deg({}) = {}", words[1], if a.is_zero() { "-inf".to_owned() } else { a.degree().to_string() })),
                "ADD" => response.save(words[1], a.add(b)), "SUB" => response.save(words[1], a.sub(b)),
                "MUL" => { a.check_product(b)?; response.save(words[1], a.mul(b)); }
                "POW" => { let n = words[3].parse().unwrap(); a.check_power(n)?; response.save(words[1], a.pow(n)); }
                "DIV" => {
                    b.require_divisor()?;
                    let (quotient, remainder) = a.divmod(b);
                    response.save(words[1], quotient); response.save(words[2], remainder);
                }
                "GCD" => response.save(words[1], a.gcd(b)),
                "XGCD" => {
                    let e = a.extended_gcd(b);
                    response.save(words[1], e.g); response.save(words[2], e.s); response.save(words[3], e.t);
                }
                "LCM" => {
                    let value = if a.is_zero() || b.is_zero() { Polynomial::zero() } else {
                        let g = a.gcd(b);
                        if a.degree() + b.degree() - g.degree() > 30 { return Err(Error::DegreeLimit); }
                        a.divmod(&g).0.mul(b).monic()
                    };
                    response.save(words[1], value);
                }
                "INVMOD" => {
                    b.require_divisor()?; b.require_degree()?;
                    let e = a.extended_gcd(b);
                    if !e.g.is_one() { return Err(Error::NotCoprime); }
                    response.save(words[1], e.s.divmod(b).1);
                }
                "CRT" => {
                    let (m1, a2, m2) = (&p[1], &p[2], &p[3]);
                    m1.require_divisor()?; m2.require_divisor()?;
                    if m1.degree() + m2.degree() > 30 { return Err(Error::DegreeLimit); }
                    let e = m1.extended_gcd(m2);
                    if !e.g.is_one() { return Err(Error::NotCoprime); }
                    let r1 = a.divmod(m1).1;
                    let r2 = a2.divmod(m2).1;
                    let u = r2.sub(&r1).mul(&e.s).divmod(m2).1;
                    response.save(words[1], r1.add(&m1.mul(&u)));
                }
                "MODPOW" => {
                    b.require_divisor()?;
                    if 2 * b.degree() - 2 > 30 { return Err(Error::DegreeLimit); }
                    let mut x = Polynomial::one().divmod(b).1;
                    let mut y = a.divmod(b).1;
                    let mut exponent: u32 = words[3].parse().unwrap();
                    while exponent != 0 {
                        if exponent % 2 == 1 { x = x.mul(&y).divmod(b).1; }
                        exponent /= 2;
                        if exponent != 0 { y = y.mul(&y).divmod(b).1; }
                    }
                    response.save(words[1], x);
                }
                "DERIV" => response.save(words[1], a.differentiate(words[3].parse().unwrap())),
                "INTEG" => { if !a.is_zero() && a.degree() + 1 > 30 { return Err(Error::DegreeLimit); } response.save(words[1], a.integral()); }
                "AREA" => {
                    let integral = a.integral();
                    let high = integral.evaluate(values[1]);
                    let low = integral.evaluate(values[0]);
                    response.output.push(format!("integral({}, {}, {}) = {}", words[1], values[0], values[1], high - low));
                }
                "TANGENT" => {
                    let y = a.evaluate(values[0]);
                    let slope = a.derivative().evaluate(values[0]);
                    response.save(words[1], Polynomial::linear(y - slope * values[0], slope));
                }
                "TAYLOR" => {
                    let center = values[0];
                    let shifted = a.compose(&Polynomial::linear(center, Fraction::ONE));
                    let variable = if center.n == 0 { "x".to_owned() }
                        else { format!("(x {} {})", if center.n > 0 { "-" } else { "+" }, center.abs()) };
                    response.output.push(format!("taylor({}, {center}) = {}", words[1], shifted.format(&variable)));
                }
                "COMPOSE" => { a.check_composition(b)?; response.save(words[1], a.compose(b)); }
                "EVAL" => for value in values { response.output.push(format!("{}({value}) = {}", words[1], a.evaluate(value))); },
                "ROOTS" | "FACTOR" => {
                    a.require_nonzero()?;
                    let roots = rational_roots(a);
                    if command == "ROOTS" {
                        let entries: Vec<_> = roots.roots.iter().map(|(value, m)| format!("{value} ({m})")).collect();
                        response.output.push(format!("roots({}) = {}", words[1], if entries.is_empty() { "none".to_owned() } else { entries.join(", ") }));
                    } else {
                        let mut text = format!("factor({}) = {}", words[1], roots.content);
                        for (value, m) in roots.roots {
                            append_factor(&mut text, &Polynomial::linear(Fraction::integer(-value.n), Fraction::integer(value.d)), m, value.n == 0);
                        }
                        if roots.remaining.degree() >= 1 { append_factor(&mut text, &roots.remaining, 1, false); }
                        response.output.push(text);
                    }
                }
                "SQFREE" => {
                    a.require_nonzero()?;
                    let mut text = format!("sqfree({}) = {}", words[1], a.content());
                    for (h, m) in square_free_factors(a) {
                        let simple_x = h.degree() == 1 && h.0[0] == Fraction::ZERO && h.0[1] == Fraction::ONE;
                        append_factor(&mut text, &h, m, simple_x);
                    }
                    response.output.push(text);
                }
                "DESCARTES" => {
                    a.require_nonzero()?;
                    let mut counts = [0; 2];
                    for (negative, count) in counts.iter_mut().enumerate() {
                        let mut previous = 0;
                        for (i, c) in a.0.iter().enumerate().rev() {
                            let mut sign = c.n.signum();
                            if negative == 1 && i % 2 == 1 { sign = -sign; }
                            if sign != 0 { if previous != 0 && previous != sign { *count += 1; } previous = sign; }
                        }
                    }
                    response.output.push(format!("descartes({}) = positive {}, negative {}", words[1], counts[0], counts[1]));
                }
                "STURM" => {
                    a.require_nonzero()?;
                    let (low, high) = bounds.unwrap();
                    if low >= high { return Err(Error::BadInterval); }
                    let sequence = sturm_sequence(a);
                    response.output.push(format!("sturm({}, {low}, {high}) = {}", words[1], root_count(&sequence, low, high)));
                }
                "ISOLATE" => {
                    a.require_nonzero()?;
                    let n = words[2].parse().unwrap();
                    let entries: Vec<_> = isolate(a, n).into_iter().map(|(low, high)| format!("({low}, {high}]")).collect();
                    response.output.push(format!("isolate({}, {n}) = {}", words[1], if entries.is_empty() { "none".to_owned() } else { entries.join(", ") }));
                }
                "RESULTANT" => {
                    a.require_nonzero()?; b.require_nonzero()?;
                    response.output.push(format!("res({}, {}) = {}", words[1], words[2], resultant(a, b)));
                }
                "DISCRIM" | "POWERSUM" => {
                    a.require_nonzero()?; a.require_degree()?;
                    let degree = a.degree() as usize;
                    if command == "DISCRIM" {
                        let mut d = resultant(a, &a.derivative()) / a.leading();
                        if degree * (degree - 1) / 2 % 2 == 1 { d = -d; }
                        response.output.push(format!("disc({}) = {d}", words[1]));
                    } else {
                        let n = words[2].parse().unwrap();
                        let c = a.monic();
                        let mut sums = vec![Fraction::ZERO; n + 1];
                        for j in 1..=n {
                            let mut w = if j <= degree { Fraction::integer(j as i64) * c.0[degree - j] } else { Fraction::ZERO };
                            for i in 1..=degree.min(j - 1) { w = w + c.0[degree - i] * sums[j - i]; }
                            sums[j] = -w;
                        }
                        let text: Vec<_> = sums[1..].iter().map(ToString::to_string).collect();
                        response.output.push(format!("powersum({}) = {}", words[1], text.join(", ")));
                    }
                }
                "INTERP" => response.save(words[1], interpolate(&values)?),
                "SPECIAL" => response.save(words[1], special(words[2], words[3].parse().unwrap())?),
                _ => unreachable!(),
            }
        }
        if let Some(name) = response.deletion { self.names.remove(&name); }
        for (name, value) in response.stores { self.names.insert(name, value); }
        Ok(response.output)
    }
}

fn main() {
    let stdin = io::stdin();
    let mut lines = stdin.lock().lines();
    let Some(Ok(first)) = lines.next() else { return; };
    let count: usize = first.trim().parse().unwrap();
    let mut calculator = Calculator::default();
    let mut output = io::BufWriter::new(io::stdout().lock());
    for line in lines.take(count) {
        match calculator.process(&line.unwrap()) {
            Ok(response) => for text in response { writeln!(output, "{text}").unwrap(); },
            Err(error) => writeln!(output, "{error}").unwrap(),
        }
    }
}
