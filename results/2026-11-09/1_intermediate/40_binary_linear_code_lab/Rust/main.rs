use std::collections::BTreeMap;
use std::fmt::Write as _;
use std::io::{self, BufRead, Write};

type Word = u32;
type Answer<T> = Result<T, String>;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Command {
    Gen, Pcheck, Hamming, Simplex, Repetition, Parity, Rm, Cyclic,
    Dual, Extend, Puncture, Shorten, Augment, Expurgate, Permute,
    Directsum, Uuv, Product, List, Delete, Show, Info, Systematic,
    Weights, Covering, Burst, Trellis, Stdarray, Equal, Encode,
    Syndrome, Decode, Bounded, Coset, Erasure, Interleave, Crc,
    Crccheck, Factor, Macwilliams, Bounds,
}

impl Command {
    fn format(name: &str) -> Option<(Self, &'static [u8], usize, usize)> {
        use Command::*;
        Some(match name {
            "GEN" => (Gen, b"NV", 2, 25), "PCHECK" => (Pcheck, b"NV", 2, 25),
            "HAMMING" => (Hamming, b"NI", 2, 2), "SIMPLEX" => (Simplex, b"NI", 2, 2),
            "REPETITION" => (Repetition, b"NI", 2, 2), "PARITY" => (Parity, b"NI", 2, 2),
            "RM" => (Rm, b"NII", 3, 3), "CYCLIC" => (Cyclic, b"NIV", 3, 3),
            "DUAL" => (Dual, b"NA", 2, 2), "EXTEND" => (Extend, b"NA", 2, 2),
            "PUNCTURE" => (Puncture, b"NAI", 3, 3), "SHORTEN" => (Shorten, b"NAI", 3, 3),
            "AUGMENT" => (Augment, b"NA", 2, 2), "EXPURGATE" => (Expurgate, b"NA", 2, 2),
            "PERMUTE" => (Permute, b"NAI", 3, 26), "DIRECTSUM" => (Directsum, b"NAB", 3, 3),
            "UUV" => (Uuv, b"NAB", 3, 3), "PRODUCT" => (Product, b"NAB", 3, 3),
            "LIST" => (List, b"", 0, 0), "DELETE" => (Delete, b"A", 1, 1),
            "SHOW" => (Show, b"A", 1, 1), "INFO" => (Info, b"A", 1, 1),
            "SYSTEMATIC" => (Systematic, b"A", 1, 1), "WEIGHTS" => (Weights, b"A", 1, 1),
            "COVERING" => (Covering, b"A", 1, 1), "BURST" => (Burst, b"A", 1, 1),
            "TRELLIS" => (Trellis, b"A", 1, 1), "STDARRAY" => (Stdarray, b"A", 1, 1),
            "EQUAL" => (Equal, b"AB", 2, 2), "ENCODE" => (Encode, b"AV", 2, 2),
            "SYNDROME" => (Syndrome, b"AV", 2, 2), "DECODE" => (Decode, b"AV", 2, 2),
            "BOUNDED" => (Bounded, b"AIV", 3, 3), "COSET" => (Coset, b"AV", 2, 2),
            "ERASURE" => (Erasure, b"AX", 2, 2), "INTERLEAVE" => (Interleave, b"AIIV", 4, 11),
            "CRC" => (Crc, b"VV", 2, 2), "CRCCHECK" => (Crccheck, b"VV", 2, 2),
            "FACTOR" => (Factor, b"I", 1, 1), "MACWILLIAMS" => (Macwilliams, b"II", 2, 26),
            "BOUNDS" => (Bounds, b"II", 2, 2),
            _ => return None,
        })
    }

    fn defining(self) -> bool {
        use Command::*;
        matches!(self, Gen | Pcheck | Hamming | Simplex | Repetition | Parity | Rm | Cyclic
            | Dual | Extend | Puncture | Shorten | Augment | Expurgate | Permute | Directsum | Uuv | Product)
    }
}

fn require(condition: bool, message: &str) -> Answer<()> {
    if condition { Ok(()) } else { Err(message.to_owned()) }
}

fn valid_word(text: &str, kind: u8) -> bool {
    if text.is_empty() { return false; }
    match kind {
        b'N' | b'A' | b'B' => text.len() <= 8 && text.as_bytes()[0].is_ascii_alphabetic()
            && text.bytes().all(|c| c.is_ascii_alphanumeric()),
        b'I' => text.len() <= 4 && (text.len() == 1 || !text.starts_with('0'))
            && text.bytes().all(|c| c.is_ascii_digit()),
        b'V' => text.len() <= 30 && text.bytes().all(|c| matches!(c, b'0' | b'1')),
        b'X' => text.len() <= 30 && text.bytes().all(|c| matches!(c, b'0' | b'1' | b'?')),
        _ => false,
    }
}

fn number(text: &str) -> usize { text.parse().unwrap() }
fn parse_bits(text: &str) -> Word { Word::from_str_radix(text, 2).unwrap() }
fn mask(n: usize) -> Word { (1 << n) - 1 }
fn bit(n: usize, column: usize) -> Word { 1 << (n - column - 1) }
fn bits(value: Word, n: usize) -> String { format!("{value:0width$b}", width = n) }
fn length(value: Word) -> usize { (Word::BITS - value.leading_zeros()) as usize }
fn yes(value: bool) -> &'static str { if value { "yes" } else { "no" } }

fn divide(mut value: Word, divisor: Word) -> (Word, Word) {
    let mut quotient = 0;
    while value != 0 && length(value) >= length(divisor) {
        let shift = length(value) - length(divisor);
        quotient ^= 1 << shift;
        value ^= divisor << shift;
    }
    (quotient, value)
}

fn basis(rows: &[Word], n: usize) -> Vec<Word> {
    let mut pivots = [0; 32];
    let mut result = Vec::new();
    for &original in rows {
        let mut row = original;
        for column in (0..n).rev() {
            if row & (1 << column) == 0 { continue; }
            if pivots[column] != 0 { row ^= pivots[column]; }
            else { pivots[column] = row; result.push(original); break; }
        }
    }
    result
}

fn rref(source: &[Word], n: usize) -> (Vec<Word>, Vec<usize>) {
    let mut rows = source.to_vec();
    let mut pivots = Vec::new();
    for column in 0..n {
        let rank = pivots.len();
        let Some(found) = (rank..rows.len()).find(|&i| rows[i] & bit(n, column) != 0) else { continue };
        rows.swap(rank, found);
        let pivot = rows[rank];
        for (i, row) in rows.iter_mut().enumerate() {
            if i != rank && *row & bit(n, column) != 0 { *row ^= pivot; }
        }
        pivots.push(column);
    }
    rows.truncate(pivots.len());
    (rows, pivots)
}

fn null_space(source: &[Word], n: usize) -> Vec<Word> {
    let (rows, pivots) = rref(source, n);
    (0..n).filter(|column| !pivots.contains(column)).map(|column| {
        let mut row = bit(n, column);
        for (i, &pivot) in pivots.iter().enumerate() {
            if rows[i] & bit(n, column) != 0 { row |= bit(n, pivot); }
        }
        row
    }).collect()
}

fn span(rows: &[Word]) -> Vec<Word> {
    let mut words = vec![0];
    for &row in rows {
        for i in 0..words.len() { words.push(words[i] ^ row); }
    }
    words
}

fn reed_muller(r: usize, m: usize) -> Vec<Word> {
    if r == 0 { return vec![mask(1 << m)]; }
    let half = 1 << (m - 1);
    let mut rows: Vec<_> = reed_muller(r.min(m - 1), m - 1).into_iter()
        .map(|row| (row << half) | row).collect();
    rows.extend(reed_muller(r - 1, m - 1));
    rows
}

fn check_dimension(n: usize, k: usize) -> Answer<()> {
    if (1..=12).contains(&k) && n > k && n - k <= 12 { Ok(()) }
    else { Err(format!("bad dimension {n} {k}")) }
}

struct Code {
    n: usize,
    g: Vec<Word>,
    h: Vec<Word>,
    polynomial: Option<Word>,
}

struct Decoded { word: Word, message: Word, error: Word }

impl Code {
    fn new(n: usize, g: Vec<Word>, h: Option<Vec<Word>>, polynomial: Option<Word>) -> Answer<Self> {
        check_dimension(n, g.len())?;
        let h = h.unwrap_or_else(|| null_space(&g, n));
        Ok(Self { n, g, h, polynomial })
    }

    fn k(&self) -> usize { self.g.len() }
    fn encoder(&self) -> &'static str { if self.polynomial.is_some() { "polynomial" } else { "matrix" } }

    fn encode(&self, message: Word) -> Word {
        if let Some(polynomial) = self.polynomial {
            let shifted = message << self.h.len();
            shifted | divide(shifted, polynomial).1
        } else {
            self.g.iter().enumerate().filter(|(i, _)| message & bit(self.k(), *i) != 0)
                .fold(0, |value, (_, row)| value ^ row)
        }
    }

    fn syndrome(&self, word: Word) -> Word {
        self.h.iter().fold(0, |value, row| (value << 1) | ((word & row).count_ones() & 1))
    }

    fn message(&self, word: Word) -> Word {
        (0..1 << self.k()).find(|&message| self.encode(message) == word).unwrap()
    }

    fn leaders(&self) -> Vec<Word> {
        let mut result = vec![Word::MAX; 1 << self.h.len()];
        result[0] = 0;
        let mut found = 1;
        for weight in 1..=self.n {
            let mut word = mask(weight);
            while word < 1 << self.n {
                let syndrome = self.syndrome(word) as usize;
                if result[syndrome] == Word::MAX {
                    result[syndrome] = word;
                    found += 1;
                    if found == result.len() { return result; }
                }
                let lowest = word & word.wrapping_neg();
                let next = word + lowest;
                word = next | (((next ^ word) >> 2) / lowest);
            }
        }
        result
    }

    fn decode(&self, word: Word, leaders: &[Word]) -> Decoded {
        let error = leaders[self.syndrome(word) as usize];
        Decoded { word: word ^ error, message: self.message(word ^ error), error }
    }

    fn decoded_text(&self, decoded: &Decoded) -> String {
        format!("codeword {} message {} error {} weight {}", bits(decoded.word, self.n),
            bits(decoded.message, self.k()), bits(decoded.error, self.n), decoded.error.count_ones())
    }

    fn burst_correction(&self) -> usize {
        let mut seen = vec![false; 1 << self.h.len()];
        seen[0] = true;
        for size in 1..=self.n {
            let variants = if size == 1 { 1 } else { 1 << (size - 2) };
            for offset in 0..=self.n - size {
                for middle in 0..variants {
                    let word = if size == 1 { 1 } else { (1 << (size - 1)) | (middle << 1) | 1 };
                    let syndrome = self.syndrome(word << offset) as usize;
                    if seen[syndrome] { return size - 1; }
                    seen[syndrome] = true;
                }
            }
        }
        unreachable!()
    }
}

fn construct(command: Command, args: &[&str], a: Option<&Code>, b: Option<&Code>) -> Answer<Code> {
    use Command::*;
    let n;
    let mut g;
    let mut h = None;
    let mut polynomial = None;
    match command {
        Gen | Pcheck => {
            n = args[1].len();
            require(args[1..].iter().all(|word| word.len() == n), "bad length")?;
            let rows = basis(&args[1..].iter().map(|word| parse_bits(word)).collect::<Vec<_>>(), n);
            if command == Gen { g = rows; }
            else { g = null_space(&rows, n); h = Some(rows); }
        }
        Hamming | Simplex => {
            let r = number(args[1]);
            require((2..=4).contains(&r), "bad parameter")?;
            n = (1 << r) - 1;
            let rows: Vec<_> = (0..r).map(|i| (1..=n).fold(0, |row, j|
                (row << 1) | (((j >> (r - i - 1)) & 1) as Word))).collect();
            if command == Simplex { g = rows; }
            else { g = null_space(&rows, n); h = Some(rows); }
        }
        Repetition | Parity => {
            n = number(args[1]);
            require((2..=24).contains(&n), "bad parameter")?;
            g = if command == Repetition { vec![mask(n)] }
                else { (0..n - 1).map(|i| bit(n, i) | 1).collect() };
        }
        Rm => {
            let r = number(args[1]);
            let m = number(args[2]);
            require((1..=4).contains(&m) && r <= m, "bad parameter")?;
            n = 1 << m;
            g = reed_muller(r, m);
        }
        Cyclic => {
            n = number(args[1]);
            let d = args[2].len() - 1;
            require((2..=24).contains(&n) && args[2].starts_with('1') && d >= 1 && d < n, "bad parameter")?;
            let divisor = parse_bits(args[2]);
            require(divide((1 << n) | 1, divisor).1 == 0, "not a divisor")?;
            let k = n - d;
            g = (0..k).map(|i| divisor << (k - i - 1)).collect();
            let mut check = vec![0; d];
            for j in 0..n {
                let remainder = divide(bit(n, j), divisor).1;
                for (i, row) in check.iter_mut().enumerate() { *row = (*row << 1) | ((remainder >> (d - i - 1)) & 1); }
            }
            h = Some(check);
            polynomial = Some(divisor);
        }
        Dual => { let a = a.unwrap(); n = a.n; g = a.h.clone(); h = Some(a.g.clone()); }
        Extend => {
            let a = a.unwrap(); n = a.n + 1;
            g = a.g.iter().map(|row| (row << 1) | (row.count_ones() & 1)).collect();
        }
        Puncture | Shorten | Expurgate => {
            let a = a.unwrap();
            let position = if command == Expurgate { 0 } else { number(args[2]) };
            if command != Expurgate { require((1..=a.n).contains(&position), "bad position")?; }
            n = a.n - usize::from(command != Expurgate);
            let selected = |row: Word| if command == Expurgate { row.count_ones() & 1 != 0 }
                else { row & bit(a.n, position - 1) != 0 };
            let removed = if command == Puncture { None } else { a.g.iter().position(|&row| selected(row)) };
            g = Vec::new();
            for (i, &original) in a.g.iter().enumerate() {
                if Some(i) == removed { continue; }
                let mut row = original;
                if let Some(pivot) = removed { if selected(row) { row ^= a.g[pivot]; } }
                if command != Expurgate {
                    let low = a.n - position;
                    row = ((row >> (low + 1)) << low) | (row & mask(low));
                }
                g.push(row);
            }
            if command == Puncture { g = basis(&g, n); }
        }
        Augment => {
            let a = a.unwrap(); n = a.n;
            g = a.g.clone(); g.push(mask(n)); g = basis(&g, n);
        }
        Permute => {
            let a = a.unwrap(); n = a.n;
            let permutation: Vec<_> = args[2..].iter().map(|word| number(word)).collect();
            let mut sorted = permutation.clone(); sorted.sort_unstable();
            require(sorted == (1..=n).collect::<Vec<_>>(), "bad permutation")?;
            g = a.g.iter().map(|row| permutation.iter().fold(0, |result, &column|
                (result << 1) | Word::from(row & bit(n, column - 1) != 0))).collect();
        }
        Directsum | Uuv | Product => {
            let a = a.unwrap(); let b = b.unwrap();
            if command == Uuv { require(a.n == b.n, "bad length")?; }
            n = if command == Product { a.n * b.n } else { a.n + b.n };
            check_dimension(n, if command == Product { a.k() * b.k() } else { a.k() + b.k() })?;
            g = Vec::new();
            if command == Product {
                for &x in &a.g { for &y in &b.g {
                    g.push((0..a.n).fold(0, |row, column| (row << b.n) | if x & bit(a.n, column) != 0 { y } else { 0 }));
                } }
            } else {
                g.extend(a.g.iter().map(|row| (row << b.n) | if command == Uuv { *row } else { 0 }));
                g.extend_from_slice(&b.g);
            }
        }
        _ => unreachable!(),
    }
    Code::new(n, g, h, polynomial)
}

fn distribution(words: impl IntoIterator<Item = Word>, n: usize) -> Vec<i64> {
    let mut counts = vec![0; n + 1];
    for word in words { counts[word.count_ones() as usize] += 1; }
    counts
}

fn weight_list(counts: &[i64]) -> String {
    counts.iter().enumerate().filter(|(_, count)| **count != 0)
        .map(|(i, count)| format!("{i}:{count}")).collect::<Vec<_>>().join(" ")
}

fn gcd(mut a: i64, mut b: i64) -> i64 {
    a = a.abs();
    while b != 0 { (a, b) = (b, a % b); }
    a
}

const fn binomials() -> [[i64; 25]; 25] {
    let mut table = [[0; 25]; 25];
    let mut n = 0;
    while n <= 24 {
        table[n][0] = 1; table[n][n] = 1;
        let mut k = 1;
        while k < n { table[n][k] = table[n - 1][k - 1] + table[n - 1][k]; k += 1; }
        n += 1;
    }
    table
}

const COMBINATIONS: [[i64; 25]; 25] = binomials();
fn choose(n: usize, k: isize) -> i64 { if k < 0 || k as usize > n { 0 } else { COMBINATIONS[n][k as usize] } }
fn volume(n: usize, radius: usize) -> i64 { (0..=radius).map(|i| choose(n, i as isize)).sum() }

fn krawtchouk(n: usize, j: usize, x: usize) -> i64 {
    (0..=j).map(|y| {
        let term = choose(x, y as isize) * choose(n - x, j as isize - y as isize);
        if y % 2 == 0 { term } else { -term }
    }).sum()
}

fn matrix_text(out: &mut String, label: char, rows: &[Word], n: usize) {
    for &row in rows { writeln!(out, "{label} {}", bits(row, n)).unwrap(); }
}

fn systematic(name: &str, code: &Code) -> String {
    let mut rows = code.g.clone();
    let mut permutation: Vec<_> = (1..=code.n).collect();
    for r in 0..code.k() {
        let column = (r..code.n).find(|&column| rows[r..].iter().any(|row| row & bit(code.n, column) != 0)).unwrap();
        if column != r {
            let left = bit(code.n, r); let right = bit(code.n, column);
            for row in &mut rows { if (*row & left != 0) != (*row & right != 0) { *row ^= left | right; } }
            permutation.swap(r, column);
        }
        let found = (r..code.k()).find(|&i| rows[i] & bit(code.n, r) != 0).unwrap();
        rows.swap(r, found);
        let pivot = rows[r];
        for (i, row) in rows.iter_mut().enumerate() { if i != r && *row & bit(code.n, r) != 0 { *row ^= pivot; } }
    }
    let mut out = format!("systematic {name} perm");
    for column in permutation { write!(out, " {column}").unwrap(); }
    out.push('\n');
    matrix_text(&mut out, 'G', &rows, code.n);
    for j in 0..code.h.len() {
        let row = rows.iter().fold(0, |value, row| (value << 1) | Word::from(row & bit(code.n, code.k() + j) != 0));
        writeln!(out, "H {}", bits((row << code.h.len()) | bit(code.h.len(), j), code.n)).unwrap();
    }
    out
}

fn independent(command: Command, args: &[&str]) -> Answer<String> {
    use Command::*;
    if matches!(command, Crc | Crccheck) {
        let d = args[0].len() - 1;
        require(args[0].starts_with('1') && (1..=16).contains(&d), "bad parameter")?;
        if command == Crc { require(args[1].len() + d <= 30, "bad length")?; }
        let word = parse_bits(args[1]); let divisor = parse_bits(args[0]);
        let remainder = divide(if command == Crc { word << d } else { word }, divisor).1;
        let suffix = bits(remainder, d);
        return Ok(if command == Crc { format!("crc remainder {suffix} frame {}{suffix}\n", args[1]) }
            else { format!("crccheck {} remainder {suffix}\n", if remainder == 0 { "ok" } else { "error" }) });
    }
    let n = number(args[0]);
    if command == Bounds {
        let d = number(args[1]);
        require(d >= 1 && d <= n && n <= 24, "bad parameter")?;
        let v = volume(n, (d - 1) / 2);
        let hamming = (0..=n).filter(|&k| (1i64 << k) * v <= 1i64 << n).last().unwrap();
        let mut sum = 0; let mut griesmer = 0;
        for k in 1..=n { sum += d.div_ceil(1 << (k - 1)); if sum <= n { griesmer = k; } }
        return Ok(format!("bounds n {n} d {d} singleton {} hamming {hamming} griesmer {griesmer}\n", n - d + 1));
    }
    require((1..=24).contains(&n), "bad parameter")?;
    if command == Factor {
        let mut remaining = (1 << n) | 1;
        let mut factor = 3; let mut divisors = 1;
        let mut out = format!("factor {n}");
        while 2 * (length(factor) - 1) <= length(remaining) - 1 {
            let mut exponent = 0;
            loop {
                let (quotient, remainder) = divide(remaining, factor);
                if remainder != 0 { break; }
                exponent += 1; remaining = quotient;
            }
            if exponent != 0 { write!(out, " {}^{exponent}", bits(factor, length(factor))).unwrap(); divisors *= exponent + 1; }
            factor += 2;
        }
        if remaining != 1 { write!(out, " {}^1", bits(remaining, length(remaining))).unwrap(); divisors *= 2; }
        writeln!(out, " divisors {divisors}").unwrap();
        return Ok(out);
    }
    require(args.len() == n + 2, "bad length")?;
    require(number(args[1]) == 1, "bad parameter")?;
    let counts: Vec<_> = args[1..].iter().map(|word| number(word) as i64).collect();
    let size: i64 = counts.iter().sum();
    let mut feasible = size & (size - 1) == 0;
    let mut out = format!("macwilliams n {n} size {size}\ndual");
    for j in 0..=n {
        let numerator: i64 = (0..=n).map(|x| counts[x] * krawtchouk(n, j, x)).sum();
        if numerator < 0 || numerator % size != 0 { feasible = false; }
        let divisor = gcd(numerator, size); let denominator = size / divisor;
        write!(out, " {}", numerator / divisor).unwrap();
        if denominator != 1 { write!(out, "/{denominator}").unwrap(); }
    }
    writeln!(out, "\nfeasible {}", yes(feasible)).unwrap();
    Ok(out)
}

#[derive(Default)]
struct Laboratory { codes: BTreeMap<String, Code> }

impl Laboratory {
    fn process(&mut self, line: &str) -> Answer<String> {
        use Command::*;
        let words: Vec<_> = line.split(' ').collect();
        let (command, types, minimum, maximum) = Command::format(words[0])
            .ok_or_else(|| format!("unknown command {}", words[0]))?;
        let args = &words[1..];
        require((minimum..=maximum).contains(&args.len()), "bad arguments")?;
        for (i, text) in args.iter().enumerate() {
            require(valid_word(text, types[i.min(types.len() - 1)]), "bad arguments")?;
        }
        let mut a = None; let mut b = None;
        for (i, &kind) in types.iter().enumerate() {
            if matches!(kind, b'A' | b'B') {
                let code = self.codes.get(args[i]).ok_or_else(|| format!("no code {}", args[i]))?;
                if kind == b'A' { a = Some(code); } else { b = Some(code); }
            }
        }
        if command.defining() {
            let code = construct(command, args, a, b)?;
            let status = if self.codes.contains_key(args[0]) { "redefined" } else { "defined" };
            let out = format!("{status} {} n {} k {}\n", args[0], code.n, code.k());
            self.codes.insert(args[0].to_owned(), code);
            return Ok(out);
        }
        if matches!(command, Crc | Crccheck | Factor | Macwilliams | Bounds) { return independent(command, args); }
        if command == List {
            let mut out = format!("codes {}\n", self.codes.len());
            for (name, code) in &self.codes { writeln!(out, "{name} n {} k {} encoder {}", code.n, code.k(), code.encoder()).unwrap(); }
            return Ok(out);
        }
        let name = args[0];
        if command == Delete { self.codes.remove(name); return Ok(format!("deleted {name}\n")); }
        let code = a.unwrap(); let n = code.n; let k = code.k();
        let mut out = String::new();
        match command {
            Show => {
                writeln!(out, "code {name} n {n} k {k} encoder {}", code.encoder()).unwrap();
                if let Some(polynomial) = code.polynomial { writeln!(out, "poly g {} h {}", bits(polynomial, n - k + 1), bits(divide((1 << n) | 1, polynomial).0, k + 1)).unwrap(); }
                matrix_text(&mut out, 'G', &code.g, n); matrix_text(&mut out, 'H', &code.h, n);
            }
            Info => {
                let words = span(&code.g);
                let distance = words[1..].iter().map(|word| word.count_ones() as usize).min().unwrap();
                let t = (distance - 1) / 2; let divisor = gcd(k as i64, n as i64) as usize;
                let cyclic = code.g.iter().all(|&row| code.syndrome(((row << 1) & mask(n)) | (row >> (n - 1))) == 0);
                let generator = *words[1..].iter().min().unwrap();
                let generator = if cyclic { bits(generator, length(generator)) } else { "no".into() };
                writeln!(out, "info {name} n {n} k {k} rate {}/{} d {distance} t {t} perfect {} mds {} cyclic {generator}",
                    k / divisor, n / divisor, yes(volume(n, t) == 1 << (n - k)), yes(distance == n - k + 1)).unwrap();
            }
            Systematic => return Ok(systematic(name, code)),
            Weights => {
                let primary = distribution(span(&code.g), n); let dual = distribution(span(&code.h), n);
                let orthogonal = code.g.iter().all(|x| code.g.iter().all(|y| (x & y).count_ones() & 1 == 0));
                writeln!(out, "weights {name} {}\ndual {name} {}", weight_list(&primary), weight_list(&dual)).unwrap();
                writeln!(out, "duality {name} self-orthogonal {} self-dual {} formally-self-dual {}",
                    yes(orthogonal), yes(orthogonal && n == 2 * k), yes(primary == dual)).unwrap();
            }
            Covering => {
                let counts = distribution(code.leaders(), n);
                let radius = counts.iter().rposition(|&count| count != 0).unwrap();
                write!(out, "covering {name} radius {radius} leaders").unwrap();
                for (i, count) in counts.iter().enumerate().take(radius + 1) { write!(out, " {i}:{count}").unwrap(); }
                out.push('\n');
            }
            Burst => {
                let detect = span(&code.g).into_iter().filter(|&word| word != 0)
                    .map(|word| length(word) - word.trailing_zeros() as usize - 1).min().unwrap();
                writeln!(out, "burst {name} detect {detect} correct {}", code.burst_correction()).unwrap();
            }
            Trellis => {
                write!(out, "trellis {name} profile").unwrap();
                let mut maximum = 0;
                for cut in 0..=n {
                    let right = n - cut;
                    let prefix: Vec<_> = code.g.iter().map(|row| row >> right).collect();
                    let suffix: Vec<_> = code.g.iter().map(|row| row & mask(right)).collect();
                    let states = basis(&prefix, cut).len() + basis(&suffix, right).len() - k;
                    maximum = maximum.max(states); write!(out, " {states}").unwrap();
                }
                writeln!(out, " max {maximum}").unwrap();
            }
            Stdarray => {
                require(n - k <= 6 && k <= 4, "too large")?;
                let leaders = code.leaders();
                let mut syndromes: Vec<_> = (0..leaders.len()).collect();
                syndromes.sort_unstable_by_key(|&s| (leaders[s].count_ones(), leaders[s]));
                let mut words = span(&code.g); words.sort_unstable();
                writeln!(out, "stdarray {name} rows {} columns {}", leaders.len(), words.len()).unwrap();
                for s in syndromes {
                    write!(out, "{}:", bits(s as Word, n - k)).unwrap();
                    for &word in &words { write!(out, " {}", bits(leaders[s] ^ word, n)).unwrap(); }
                    out.push('\n');
                }
            }
            Equal => {
                let other = b.unwrap();
                if n != other.n { writeln!(out, "equal {name} {} no lengths {n} {}", args[1], other.n).unwrap(); }
                else {
                    let mut rows = code.g.clone(); rows.extend_from_slice(&other.g);
                    let common = k + other.k() - basis(&rows, n).len();
                    writeln!(out, "equal {name} {} {} intersection {common}", args[1], yes(k == common && other.k() == common)).unwrap();
                }
            }
            Encode => {
                require(args[1].len() == k, "bad length")?;
                writeln!(out, "encode {name} message {} codeword {}", args[1], bits(code.encode(parse_bits(args[1])), n)).unwrap();
            }
            Syndrome | Decode | Bounded | Coset => {
                let text = args[if command == Bounded { 2 } else { 1 }];
                require(text.len() == n, "bad length")?;
                let word = parse_bits(text); let s = code.syndrome(word);
                if command == Syndrome { writeln!(out, "syndrome {name} {} codeword {}", bits(s, n - k), yes(s == 0)).unwrap(); }
                else {
                    let leaders = code.leaders(); let decoded = code.decode(word, &leaders);
                    if command == Coset {
                        let counts = distribution(span(&code.g).into_iter().map(|c| c ^ word), n);
                        writeln!(out, "coset {name} syndrome {} leader {} weights {}", bits(s, n - k), bits(decoded.error, n), weight_list(&counts)).unwrap();
                    } else if command == Bounded && decoded.error.count_ones() as usize > number(args[1]) {
                        writeln!(out, "bounded {name} fail weight {}", decoded.error.count_ones()).unwrap();
                    } else {
                        writeln!(out, "{} {name} {}", if command == Bounded { "bounded" } else { "decode" }, code.decoded_text(&decoded)).unwrap();
                    }
                }
            }
            Erasure => {
                require(args[1].len() == n, "bad length")?;
                let mut known = 0; let mut value = 0; let mut erased = 0;
                for (i, digit) in args[1].bytes().enumerate() {
                    if digit == b'?' { erased += 1; }
                    else { known |= bit(n, i); if digit == b'1' { value |= bit(n, i); } }
                }
                let candidates: Vec<_> = span(&code.g).into_iter().filter(|word| word & known == value).collect();
                write!(out, "erasure {name} erased {erased} candidates {}", candidates.len()).unwrap();
                if candidates.len() == 1 { write!(out, " codeword {} message {}", bits(candidates[0], n), bits(code.message(candidates[0]), k)).unwrap(); }
                out.push('\n');
            }
            Interleave => {
                let depth = args.len() - 3; let start = number(args[1]); let size = number(args[2]);
                require(args[3..].iter().all(|word| word.len() == k), "bad length")?;
                require(start >= 1 && size >= 1 && start + size - 1 <= depth * n, "bad burst")?;
                let sent_rows: Vec<_> = args[3..].iter().map(|word| code.encode(parse_bits(word))).collect();
                let mut received_rows = vec![0; depth];
                let mut sent = String::new(); let mut received = String::new();
                for column in 0..n { for i in 0..depth {
                    let position = column * depth + i + 1;
                    let value = sent_rows[i] & bit(n, column) != 0;
                    sent.push(if value { '1' } else { '0' });
                    let changed = value ^ (position >= start && position < start + size);
                    received.push(if changed { '1' } else { '0' });
                    received_rows[i] = (received_rows[i] << 1) | Word::from(changed);
                } }
                writeln!(out, "interleave {name} depth {depth} burst {start} {size}\nsent {sent}\nrecv {received}").unwrap();
                let leaders = code.leaders(); let mut correct = 0;
                for i in 0..depth {
                    let decoded = code.decode(received_rows[i], &leaders);
                    let ok = decoded.message == parse_bits(args[i + 3]); correct += usize::from(ok);
                    writeln!(out, "row {} errors {} corrected {} message {} {}", i + 1,
                        (sent_rows[i] ^ received_rows[i]).count_ones(), decoded.error.count_ones(), bits(decoded.message, k), if ok { "ok" } else { "wrong" }).unwrap();
                }
                writeln!(out, "result ok {correct} wrong {}", depth - correct).unwrap();
            }
            _ => unreachable!(),
        }
        Ok(out)
    }
}

fn main() -> io::Result<()> {
    let stdin = io::stdin();
    let mut lines = stdin.lock().lines();
    let count: usize = lines.next().unwrap()?.parse().unwrap();
    let mut laboratory = Laboratory::default();
    let stdout = io::stdout();
    let mut output = io::BufWriter::new(stdout.lock());
    for line in lines.take(count) {
        match laboratory.process(&line?) {
            Ok(text) => output.write_all(text.as_bytes())?,
            Err(error) => writeln!(output, "error: {error}")?,
        }
    }
    output.flush()
}
