use std::cmp::Ordering;
use std::collections::BTreeMap;
use std::fmt::{self, Write as _};
use std::io::{self, Read, Write as _};

type Pattern = u32;
type Flags = u8;
const INVALID: Flags = 1;
const DIVBYZERO: Flags = 2;
const OVERFLOW: Flags = 4;
const UNDERFLOW: Flags = 8;
const INEXACT: Flags = 16;

#[derive(Clone, Copy, PartialEq)]
enum Mode { Rne, Rna, Rtz, Rup, Rdn }

impl Mode {
    fn parse(word: &str) -> Result<Self, String> {
        match word {
            "RNE" => Ok(Self::Rne), "RNA" => Ok(Self::Rna), "RTZ" => Ok(Self::Rtz),
            "RUP" => Ok(Self::Rup), "RDN" => Ok(Self::Rdn),
            _ => Err(format!("ERROR BAD MODE {word}")),
        }
    }

    fn optional(word: Option<&&str>) -> Result<Self, String> {
        word.map_or(Ok(Self::Rne), |word| Self::parse(word))
    }
}

impl fmt::Display for Mode {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self { Self::Rne => "RNE", Self::Rna => "RNA", Self::Rtz => "RTZ", Self::Rup => "RUP", Self::Rdn => "RDN" })
    }
}

#[derive(Clone, Copy, PartialEq)]
enum Class { Zero, Subnormal, Normal, Infinity, QuietNan, SignalingNan }

impl fmt::Display for Class {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Zero => "zero", Self::Subnormal => "subnormal", Self::Normal => "normal",
            Self::Infinity => "infinity", Self::QuietNan => "qnan", Self::SignalingNan => "snan",
        })
    }
}

#[derive(Clone, Copy, PartialEq)]
enum Operation { Add, Sub, Mul, Div, Sqrt, Fma }

#[derive(Clone, Copy)]
struct Term { negative: bool, magnitude: u64, exponent: i32 }

impl Term {
    fn product(self, other: Self) -> Self {
        Self { negative: self.negative != other.negative, magnitude: self.magnitude * other.magnitude, exponent: self.exponent + other.exponent }
    }

    fn exact(self) -> Exact { Exact::new(self.negative, self.magnitude, self.exponent, 1) }

    fn decimal(self) -> String {
        if self.magnitude == 0 { return "0".into(); }
        let value = self.exact();
        let (numerator, denominator) = value.scaled(0);
        let sign = if value.negative { "-" } else { "" };
        let mut output = format!("{sign}{}", numerator / denominator);
        let mut remainder = numerator % denominator;
        if remainder != 0 { output.push('.'); }
        while remainder != 0 {
            remainder *= 10;
            output.push(char::from(b'0' + (remainder / denominator) as u8));
            remainder %= denominator;
        }
        output
    }
}

fn sum_terms(terms: &[Term], mode: Mode) -> Term {
    let exponent = terms.iter().filter(|term| term.magnitude != 0).map(|term| term.exponent).min().unwrap_or(0);
    let mut sum = 0i64;
    for term in terms.iter().filter(|term| term.magnitude != 0) {
        let magnitude = (term.magnitude << (term.exponent - exponent)) as i64;
        sum += if term.negative { -magnitude } else { magnitude };
    }
    let negative = if sum == 0 {
        if terms.iter().all(|term| term.magnitude == 0 && term.negative == terms[0].negative) { terms[0].negative }
        else { mode == Mode::Rdn }
    } else { sum < 0 };
    Term { negative, magnitude: sum.unsigned_abs(), exponent }
}

#[derive(Clone, Copy)]
struct Exact { negative: bool, numerator: u64, denominator: u64, exponent: i32 }

impl Exact {
    fn new(negative: bool, mut numerator: u64, mut exponent: i32, mut denominator: u64) -> Self {
        if numerator == 0 { return Self { negative, numerator: 0, denominator: 1, exponent: 0 }; }
        let (mut a, mut b) = (numerator, denominator);
        while b != 0 { (a, b) = (b, a % b); }
        numerator /= a;
        denominator /= a;
        let shift = numerator.trailing_zeros();
        numerator >>= shift;
        exponent += shift as i32;
        let shift = denominator.trailing_zeros();
        denominator >>= shift;
        exponent -= shift as i32;
        Self { negative, numerator, denominator, exponent }
    }

    fn scaled(self, quantum: i32) -> (u64, u64) {
        let shift = self.exponent - quantum;
        if shift >= 0 { (self.numerator << shift, self.denominator) }
        else { (self.numerator, self.denominator << -shift) }
    }

    fn floor_log(self) -> i32 {
        let power = self.denominator.leading_zeros() as i32 - self.numerator.leading_zeros() as i32;
        let below = if power >= 0 { self.numerator < self.denominator << power }
            else { self.numerator << -power < self.denominator };
        self.exponent + power - i32::from(below)
    }

    fn fraction(self) -> String {
        if self.numerator == 0 { return "0".into(); }
        let (numerator, denominator) = self.scaled(0);
        let sign = if self.negative { "-" } else { "" };
        if denominator == 1 { format!("{sign}{numerator}") }
        else { format!("{sign}{numerator}/{denominator}") }
    }
}

#[derive(Clone, Copy)]
struct Quantized { whole: u64, inexact: bool, half: Ordering }

impl Quantized {
    fn new(value: Exact, quantum: i32, square_root: bool) -> Self {
        let (numerator, denominator) = value.scaled(if square_root { 2 * quantum } else { quantum });
        if !square_root {
            let remainder = numerator % denominator;
            return Self { whole: numerator / denominator, inexact: remainder != 0, half: remainder.cmp(&(denominator - remainder)) };
        }
        let whole = (numerator / denominator).isqrt();
        let midpoint = 2 * whole + 1;
        Self { whole, inexact: whole * whole * denominator != numerator, half: (4 * numerator).cmp(&(midpoint * midpoint * denominator)) }
    }

    fn increment(self, mode: Mode, negative: bool) -> u64 {
        u64::from(match mode {
            Mode::Rne => self.half == Ordering::Greater || (self.half == Ordering::Equal && self.whole & 1 != 0),
            Mode::Rna => self.half != Ordering::Less,
            Mode::Rtz => false,
            Mode::Rup => self.inexact && !negative,
            Mode::Rdn => self.inexact && negative,
        })
    }
}

#[derive(Clone, Copy)]
struct Rounded { pattern: Pattern, flags: Flags }

impl Rounded {
    fn plain(pattern: Pattern) -> Self { Self { pattern, flags: 0 } }
}

enum Input { Number(Exact), Pattern(Pattern) }

struct Format {
    name: String,
    e: i32, m: i32, w: i32, bias: i32, emin: i32, emax: i32,
    sign: Pattern, base: Pattern, infinity: Pattern, nan: Pattern,
}

impl Format {
    fn new(name: &str, e: i32, m: i32) -> Self {
        let bias = (1 << (e - 1)) - 1;
        let base = 1 << m;
        let infinity = ((1 << e) - 1) << m;
        Self { name: name.into(), e, m, w: 1 + e + m, bias, emin: 1 - bias, emax: bias,
            sign: 1 << (e + m), base, infinity, nan: infinity | (base / 2) }
    }

    fn negative(&self, p: Pattern) -> bool { p & self.sign != 0 }
    fn signed(&self, p: Pattern, negative: bool) -> Pattern { p | if negative { self.sign } else { 0 } }
    fn zero(&self, p: Pattern) -> bool { p & (self.sign - 1) == 0 }
    fn class(&self, p: Pattern) -> Class {
        let magnitude = p & (self.sign - 1);
        let fraction = p & (self.base - 1);
        if magnitude >= self.infinity {
            if fraction == 0 { Class::Infinity }
            else if fraction >= self.base / 2 { Class::QuietNan } else { Class::SignalingNan }
        } else if magnitude == 0 { Class::Zero }
        else if magnitude < self.base { Class::Subnormal } else { Class::Normal }
    }

    fn finite(&self, p: Pattern) -> bool { matches!(self.class(p), Class::Zero | Class::Subnormal | Class::Normal) }
    fn is_nan(&self, p: Pattern) -> bool { matches!(self.class(p), Class::QuietNan | Class::SignalingNan) }
    fn term(&self, p: Pattern) -> Term {
        let field = (p & (self.sign - 1)) >> self.m;
        let fraction = p & (self.base - 1);
        Term { negative: self.negative(p), magnitude: u64::from(if field == 0 { fraction } else { self.base + fraction }),
            exponent: if field == 0 { self.emin - self.m } else { field as i32 - self.bias - self.m } }
    }

    fn overflow(&self, mode: Mode, negative: bool) -> Rounded {
        let infinity = matches!(mode, Mode::Rne | Mode::Rna) || (mode == Mode::Rup && !negative) || (mode == Mode::Rdn && negative);
        Rounded { pattern: self.signed(if infinity { self.infinity } else { self.infinity - 1 }, negative), flags: OVERFLOW | INEXACT }
    }

    fn round(&self, value: Exact, mode: Mode, square_root: bool) -> Rounded {
        if value.numerator == 0 { return Rounded::plain(self.signed(0, value.negative)); }
        let mut t = value.floor_log();
        if square_root { t = t.div_euclid(2); }
        if t > self.emax { return self.overflow(mode, value.negative); }
        let mut quantum = t.max(self.emin) - self.m;
        let divided = Quantized::new(value, quantum, square_root);
        let mut significand = divided.whole + divided.increment(mode, value.negative);
        let base = u64::from(self.base);
        if significand == 2 * base { significand = base; quantum += 1; }
        if quantum > self.emax - self.m { return self.overflow(mode, value.negative); }
        let mut flags = if divided.inexact { INEXACT } else { 0 };
        if divided.inexact && t < self.emin {
            let tiny = t < self.emin - 1 || {
                let unbounded = Quantized::new(value, t - self.m, square_root);
                unbounded.whole + unbounded.increment(mode, value.negative) < 2 * base
            };
            if tiny { flags |= UNDERFLOW; }
        }
        let magnitude = if significand < base { significand as Pattern }
            else { ((quantum + self.m + self.bias) as Pattern) << self.m | (significand - base) as Pattern };
        Rounded { pattern: self.signed(magnitude, value.negative), flags }
    }

    fn round_term(&self, term: Term, mode: Mode) -> Rounded { self.round(term.exact(), mode, false) }
    fn round_sum(&self, terms: &[Term], mode: Mode) -> Rounded { self.round_term(sum_terms(terms, mode), mode) }

    fn arithmetic(&self, mut operation: Operation, a: Pattern, mut b: Pattern, c: Pattern, mode: Mode) -> Rounded {
        if operation == Operation::Sub { b ^= self.sign; operation = Operation::Add; }
        let inputs = [a, b, c];
        let count = match operation { Operation::Sqrt => 1, Operation::Fma => 3, _ => 2 };
        if inputs[..count].iter().any(|&p| self.is_nan(p)) {
            let flags = if inputs[..count].iter().any(|&p| self.class(p) == Class::SignalingNan) { INVALID } else { 0 };
            return Rounded { pattern: self.nan, flags };
        }
        let ai = self.class(a) == Class::Infinity;
        let bi = self.class(b) == Class::Infinity;
        let negative = self.negative(a) != self.negative(b);
        let invalid = Rounded { pattern: self.nan, flags: INVALID };
        match operation {
            Operation::Add => {
                if ai && bi && negative { invalid }
                else if ai || bi { Rounded::plain(if ai { a } else { b }) }
                else { self.round_sum(&[self.term(a), self.term(b)], mode) }
            }
            Operation::Mul => {
                if ai || bi {
                    if self.zero(a) || self.zero(b) { invalid } else { Rounded::plain(self.signed(self.infinity, negative)) }
                } else { self.round_term(self.term(a).product(self.term(b)), mode) }
            }
            Operation::Div => {
                if ai { if bi { invalid } else { Rounded::plain(self.signed(self.infinity, negative)) } }
                else if bi { Rounded::plain(self.signed(0, negative)) }
                else if self.zero(b) {
                    if self.zero(a) { invalid } else { Rounded { pattern: self.signed(self.infinity, negative), flags: DIVBYZERO } }
                } else if self.zero(a) { Rounded::plain(self.signed(0, negative)) }
                else {
                    let (x, y) = (self.term(a), self.term(b));
                    self.round(Exact::new(negative, x.magnitude, x.exponent - y.exponent, y.magnitude), mode, false)
                }
            }
            Operation::Sqrt => {
                if self.zero(a) { Rounded::plain(a) }
                else if self.negative(a) { invalid }
                else if ai { Rounded::plain(a) }
                else { self.round(self.term(a).exact(), mode, true) }
            }
            Operation::Fma => {
                if ai || bi {
                    if self.zero(a) || self.zero(b) || (self.class(c) == Class::Infinity && self.negative(c) != negative) { invalid }
                    else { Rounded::plain(self.signed(self.infinity, negative)) }
                } else if self.class(c) == Class::Infinity { Rounded::plain(c) }
                else { self.round_sum(&[self.term(a).product(self.term(b)), self.term(c)], mode) }
            }
            Operation::Sub => unreachable!(),
        }
    }

    fn raw_operand(&self, word: &str, encoding: bool) -> Result<Input, String> {
        let invalid = || format!("ERROR BAD OPERAND {word}");
        if word.starts_with("0b") || word.starts_with("0x") {
            let binary = word.starts_with("0b");
            let width = if binary { self.w } else { (self.w + 3) / 4 } as usize;
            if encoding || word.len() - 2 != width { return Err(invalid()); }
            let pattern = Pattern::from_str_radix(&word[2..], if binary { 2 } else { 16 }).unwrap();
            return if pattern < 2 * self.sign { Ok(Input::Pattern(pattern)) } else { Err(invalid()) };
        }
        match word {
            "nan" => return Ok(Input::Pattern(self.nan)),
            "inf" => return Ok(Input::Pattern(self.infinity)),
            "-inf" => return Ok(Input::Pattern(self.infinity | self.sign)),
            _ => {}
        }
        let negative = word.starts_with('-');
        let digits = word.strip_prefix('-').unwrap_or(word);
        let (numerator, denominator) = if let Some((p, q)) = digits.split_once('/') {
            (p.parse().unwrap(), q.parse().unwrap())
        } else if let Some((integer, fraction)) = digits.split_once('.') {
            (format!("{integer}{fraction}").parse().unwrap(), 10u64.pow(fraction.len() as u32))
        } else { (digits.parse().unwrap(), 1) };
        if denominator == 0 { return Err(invalid()); }
        Ok(Input::Number(Exact::new(negative, numerator, 0, denominator)))
    }

    fn operand(&self, word: &str) -> Result<Pattern, String> {
        Ok(match self.raw_operand(word, false)? {
            Input::Pattern(pattern) => pattern,
            Input::Number(value) => self.round(value, Mode::Rne, false).pattern,
        })
    }

    fn bits(&self, p: Pattern) -> String {
        format!("{}|{:0ew$b}|{:0mw$b}", u8::from(self.negative(p)), (p & (self.sign - 1)) >> self.m,
            p & (self.base - 1), ew = self.e as usize, mw = self.m as usize)
    }

    fn hex(&self, p: Pattern) -> String { format!("0x{p:0width$X}", width = ((self.w + 3) / 4) as usize) }
    fn value(&self, p: Pattern) -> String {
        match self.class(p) {
            Class::QuietNan | Class::SignalingNan => "nan".into(),
            Class::Infinity => if self.negative(p) { "-inf" } else { "inf" }.into(),
            Class::Zero => if self.negative(p) { "-0" } else { "0" }.into(),
            _ => self.term(p).decimal(),
        }
    }

    fn pattern(&self, p: Pattern) -> String { format!("{} {} {}", self.bits(p), self.hex(p), self.value(p)) }
    fn result(&self, result: Rounded) -> String { format!("{} {}", self.pattern(result.pattern), flag_text(result.flags)) }
    fn difference(&self, p: Pattern, mut exact_sum: Term) -> String {
        if !self.finite(p) { return self.value(p); }
        exact_sum.negative = !exact_sum.negative;
        sum_terms(&[self.term(p), exact_sum], Mode::Rne).exact().fraction()
    }

    fn order_key(&self, p: Pattern) -> i64 { if self.negative(p) { -i64::from(p - self.sign) - 1 } else { i64::from(p) } }
    fn next_up(&self, p: Pattern) -> Pattern {
        if p == self.infinity { p } else if self.zero(p) { 1 }
        else if self.negative(p) { p - 1 } else { p + 1 }
    }
}

fn flag_text(flags: Flags) -> String {
    let names = ["invalid", "divbyzero", "overflow", "underflow", "inexact"];
    let set: Vec<_> = names.into_iter().enumerate().filter_map(|(i, name)| (flags & (1 << i) != 0).then_some(name)).collect();
    format!("flags={}", if set.is_empty() { "none".into() } else { set.join(",") })
}

fn relation(a: i64, b: i64) -> &'static str { match a.cmp(&b) { Ordering::Less => "LT", Ordering::Equal => "EQ", Ordering::Greater => "GT" } }

fn integer_range(word: &str) -> Result<(i64, i64), String> {
    match word {
        "I8" => Ok((-128, 127)), "U8" => Ok((0, 255)), "I16" => Ok((-32768, 32767)),
        "U16" => Ok((0, 65535)), "I32" => Ok((-2147483648, 2147483647)), "U32" => Ok((0, 4294967295)),
        _ => Err(format!("ERROR BAD TYPE {word}")),
    }
}

fn summation(f: &Format, words: &[&str]) -> Result<String, String> {
    let command = words[0];
    let mode = Mode::parse(words[2])?;
    let mut values = Vec::new();
    let mut left_count = 0;
    for &word in &words[3..] {
        if word == "|" { left_count = values.len(); } else { values.push(f.operand(word)?); }
    }
    if command == "DOT" && left_count != values.len() - left_count { return Err("ERROR LENGTH MISMATCH".into()); }
    if values.iter().any(|&p| !f.finite(p)) { return Err("ERROR NOT FINITE".into()); }
    let mut output = String::new();
    if command == "DOT" {
        let terms: Vec<_> = (0..left_count).map(|i| f.term(values[i]).product(f.term(values[left_count + i]))).collect();
        let exact_sum = sum_terms(&terms, mode);
        let first = f.arithmetic(Operation::Mul, values[0], values[left_count], 0, mode);
        let (mut naive, mut chained) = (first, first);
        for i in 1..left_count {
            let multiplied = f.arithmetic(Operation::Mul, values[i], values[left_count + i], 0, mode);
            let added = f.arithmetic(Operation::Add, naive.pattern, multiplied.pattern, 0, mode);
            naive = Rounded { pattern: added.pattern, flags: naive.flags | multiplied.flags | added.flags };
        }
        for i in 1..left_count {
            let fused = f.arithmetic(Operation::Fma, values[i], values[left_count + i], chained.pattern, mode);
            chained = Rounded { pattern: fused.pattern, flags: chained.flags | fused.flags };
        }
        writeln!(output, "DOT {} {mode} n={left_count}", f.name).unwrap();
        writeln!(output, "NAIVE {}", f.result(naive)).unwrap();
        writeln!(output, "CHAINED {}", f.result(chained)).unwrap();
        writeln!(output, "EXACT {}", exact_sum.decimal()).unwrap();
        writeln!(output, "FUSED {}", f.result(f.round_term(exact_sum, mode))).unwrap();
        writeln!(output, "DIFF naive={} chained={}", f.difference(naive.pattern, exact_sum), f.difference(chained.pattern, exact_sum)).unwrap();
        return Ok(output);
    }
    let terms: Vec<_> = values.iter().map(|&p| f.term(p)).collect();
    let exact_sum = sum_terms(&terms, mode);
    let mut result = Rounded::plain(values[0]);
    let mut compensation = 0;
    writeln!(output, "{command} {} {mode} count={}", f.name, values.len()).unwrap();
    for (i, &value) in values.iter().enumerate().skip(1) {
        if command == "SUM" {
            let next = f.arithmetic(Operation::Add, result.pattern, value, 0, mode);
            result = Rounded { pattern: next.pattern, flags: result.flags | next.flags };
            writeln!(output, "PARTIAL {} {}", i + 1, f.result(next)).unwrap();
        } else {
            let y = f.arithmetic(Operation::Sub, value, compensation, 0, mode);
            let t = f.arithmetic(Operation::Add, result.pattern, y.pattern, 0, mode);
            let d = f.arithmetic(Operation::Sub, t.pattern, result.pattern, 0, mode);
            let c = f.arithmetic(Operation::Sub, d.pattern, y.pattern, 0, mode);
            let flags = y.flags | t.flags | d.flags | c.flags;
            result = Rounded { pattern: t.pattern, flags: result.flags | flags };
            compensation = c.pattern;
            writeln!(output, "KSTEP {} sum={} comp={} {}", i + 1, f.value(result.pattern), f.value(compensation), flag_text(flags)).unwrap();
        }
    }
    writeln!(output, "RESULT {}", f.result(result)).unwrap();
    writeln!(output, "EXACT {}", exact_sum.decimal()).unwrap();
    writeln!(output, "ROUNDED {}", f.result(f.round_term(exact_sum, mode))).unwrap();
    writeln!(output, "DIFF {}", f.difference(result.pattern, exact_sum)).unwrap();
    Ok(output)
}

fn table(f: &Format) -> Result<String, String> {
    if f.w > 8 { return Err("ERROR TABLE TOO LARGE".into()); }
    let mut output = format!("TABLE {} count={}\n", f.name, f.infinity);
    for p in 0..f.infinity {
        let gap = if p + 1 == f.infinity { "-".into() } else {
            let mut previous = f.term(p);
            previous.negative = true;
            sum_terms(&[f.term(p + 1), previous], Mode::Rne).decimal()
        };
        writeln!(output, "ENTRY {p} {} gap={gap}", f.pattern(p)).unwrap();
    }
    writeln!(output, "MAX {}", f.pattern(f.infinity - 1)).unwrap();
    writeln!(output, "MINNORMAL {}", f.pattern(f.base)).unwrap();
    writeln!(output, "MINSUBNORMAL {}", f.pattern(1)).unwrap();
    writeln!(output, "EPSILON {}", Term { negative: false, magnitude: 1, exponent: -f.m }.decimal()).unwrap();
    writeln!(output, "PATTERNS finite={} infinite=2 nan={} total={}", 2 * f.infinity, 2 * (f.base - 1), 2 * f.sign).unwrap();
    Ok(output)
}

fn find_format<'a>(formats: &'a BTreeMap<String, Format>, name: &str) -> Result<&'a Format, String> {
    formats.get(name).ok_or_else(|| format!("ERROR UNKNOWN FORMAT {name}"))
}

fn execute(formats: &mut BTreeMap<String, Format>, words: &[&str]) -> Result<String, String> {
    let command = words[0];
    if command == "FORMAT" {
        if formats.contains_key(words[1]) { return Err(format!("ERROR FORMAT EXISTS {}", words[1])); }
        let e = words[2].parse().unwrap();
        let m = words[3].parse().unwrap();
        if !(2..=5).contains(&e) || !(1..=10).contains(&m) { return Err("ERROR BAD FORMAT".into()); }
        let f = Format::new(words[1], e, m);
        let output = format!("FORMAT {} e={e} m={m} bits={} bias={} emin={} emax={}\n", f.name, f.w, f.bias, f.emin, f.emax);
        formats.insert(f.name.clone(), f);
        return Ok(output);
    }
    let f = find_format(formats, words[1])?;
    if command == "TABLE" { return table(f); }
    if matches!(command, "SUM" | "KAHAN" | "DOT") { return summation(f, words); }
    if command == "CONVERT" {
        let g = find_format(formats, words[2])?;
        let a = f.operand(words[3])?;
        let mode = Mode::optional(words.get(4))?;
        let result = match f.class(a) {
            Class::QuietNan => Rounded::plain(g.nan),
            Class::SignalingNan => Rounded { pattern: g.nan, flags: INVALID },
            Class::Infinity => Rounded::plain(g.signed(g.infinity, f.negative(a))),
            Class::Zero => Rounded::plain(g.signed(0, f.negative(a))),
            _ => g.round_term(f.term(a), mode),
        };
        return Ok(format!("CONVERT {} {} {mode} {}\n", f.name, g.name, g.result(result)));
    }
    if command == "ENCODE" {
        let value = f.raw_operand(words[2], true)?;
        let mode = Mode::optional(words.get(3))?;
        let (source, result) = match value {
            Input::Number(value) => (value.fraction(), f.round(value, mode, false)),
            Input::Pattern(p) => (f.value(p), Rounded::plain(p)),
        };
        return Ok(format!("ENCODE {} {mode} {source} {}\n", f.name, f.result(result)));
    }
    let a = f.operand(words[2])?;
    match command {
        "DECODE" => {
            let kind = f.class(a);
            let exponent = (a & (f.sign - 1)) >> f.m;
            let fraction = a & (f.base - 1);
            let mut output = format!("DECODE {} {} {} {kind} sign={}\n", f.name, f.bits(a), f.hex(a), u8::from(f.negative(a)));
            if f.finite(a) {
                let term = f.term(a);
                writeln!(output, "FIELDS exponent={exponent} fraction={fraction} unbiased={} significand={}.{:0width$b}",
                    term.exponent + f.m, u8::from(kind == Class::Normal), fraction, width = f.m as usize).unwrap();
                writeln!(output, "VALUE {} {}", term.exact().fraction(), f.value(a)).unwrap();
            } else if kind == Class::Infinity {
                writeln!(output, "FIELDS exponent={exponent} fraction={fraction}").unwrap();
            } else {
                writeln!(output, "FIELDS exponent={exponent} fraction={fraction} payload={}", fraction % (f.base / 2)).unwrap();
            }
            Ok(output)
        }
        "COMPARE" => {
            let b = f.operand(words[3])?;
            let (ak, bk) = (f.order_key(a), f.order_key(b));
            let numeric = if f.is_nan(a) || f.is_nan(b) { "UN" }
                else if f.zero(a) && f.zero(b) { "EQ" } else { relation(ak, bk) };
            let flags = if f.class(a) == Class::SignalingNan || f.class(b) == Class::SignalingNan { INVALID } else { 0 };
            Ok(format!("COMPARE {} {} {} {numeric} total={} {}\n", f.name, f.hex(a), f.hex(b), relation(ak, bk), flag_text(flags)))
        }
        "TOINT" => {
            let (minimum, maximum) = integer_range(words[3])?;
            let mode = Mode::optional(words.get(4))?;
            let prefix = format!("TOINT {} {} {mode}", f.name, words[3]);
            if !f.finite(a) { return Ok(format!("{prefix} invalid flags=invalid\n")); }
            let value = f.term(a).exact();
            let divided = Quantized::new(value, 0, false);
            let magnitude = (divided.whole + divided.increment(mode, value.negative)) as i64;
            let result = if value.negative { -magnitude } else { magnitude };
            if result < minimum || result > maximum { Ok(format!("{prefix} invalid flags=invalid\n")) }
            else { Ok(format!("{prefix} {result} {}\n", flag_text(if divided.inexact { INEXACT } else { 0 }))) }
        }
        "NEXTUP" | "NEXTDOWN" | "ULP" => {
            let result = if f.is_nan(a) {
                Rounded { pattern: f.nan, flags: if f.class(a) == Class::SignalingNan { INVALID } else { 0 } }
            } else {
                let pattern = match command {
                    "NEXTUP" => f.next_up(a),
                    "NEXTDOWN" => f.next_up(a ^ f.sign) ^ f.sign,
                    _ => if f.class(a) == Class::Infinity { f.infinity }
                        else { f.round_term(Term { negative: false, magnitude: 1, exponent: f.term(a).exponent }, Mode::Rne).pattern },
                };
                Rounded::plain(pattern)
            };
            Ok(format!("{command} {} {}\n", f.name, f.result(result)))
        }
        _ => {
            let operation = match command {
                "ADD" => Operation::Add, "SUB" => Operation::Sub, "MUL" => Operation::Mul,
                "DIV" => Operation::Div, "SQRT" => Operation::Sqrt, "FMA" => Operation::Fma,
                _ => unreachable!(),
            };
            let arity = match operation { Operation::Sqrt => 1, Operation::Fma => 3, _ => 2 };
            let b = if arity >= 2 { f.operand(words[3])? } else { 0 };
            let c = if arity == 3 { f.operand(words[4])? } else { 0 };
            let mode = Mode::optional(words.get(arity + 2))?;
            Ok(format!("{command} {} {mode} {}\n", f.name, f.result(f.arithmetic(operation, a, b, c, mode))))
        }
    }
}

fn main() -> io::Result<()> {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input)?;
    let mut lines = input.lines();
    let count: usize = lines.next().unwrap().parse().unwrap();
    let mut formats = BTreeMap::new();
    for (name, e, m) in [("HALF", 5, 10), ("E5M2", 5, 2), ("E4M3", 4, 3)] {
        formats.insert(name.into(), Format::new(name, e, m));
    }
    let mut output = io::BufWriter::new(io::stdout().lock());
    for line in lines.take(count) {
        let words: Vec<_> = line.split_whitespace().collect();
        match execute(&mut formats, &words) {
            Ok(response) => output.write_all(response.as_bytes())?,
            Err(error) => writeln!(output, "{error}")?,
        }
    }
    output.flush()
}
