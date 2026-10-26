use std::collections::BTreeMap;
use std::io::{self, Read};
type Int = i128;
type Composition = BTreeMap<String, Int>;
const SYMBOLS: &str = "H He Li Be B C N O F Ne Na Mg Al Si P S Cl Ar K Ca Sc Ti V Cr Mn Fe Co Ni Cu Zn Ga Ge As Se Br Kr Rb Sr Y Zr Nb Mo Tc Ru Rh Pd Ag Cd In Sn Sb Te I Xe";
const WEIGHTS: [Int; 54] = [
    1008, 4003, 6941, 9012, 10811, 12011, 14007, 15999, 18998, 20180, 22990, 24305, 26982, 28086,
    30974, 32065, 35453, 39948, 39098, 40078, 44956, 47867, 50942, 51996, 54938, 55845, 58933,
    58693, 63546, 65380, 69723, 72630, 74922, 78971, 79904, 83798, 85468, 87620, 88906, 91224,
    92906, 95950, 98000, 101070, 102906, 106420, 107868, 112414, 114818, 118710, 121760, 127600,
    126904, 131293,
];
fn element(s: &str) -> Option<usize> {
    SYMBOLS.split_whitespace().position(|x| x == s)
}
fn weight(s: &str) -> Int {
    WEIGHTS[element(s).unwrap()]
}
fn gcd(mut a: Int, mut b: Int) -> Int {
    a = a.abs();
    b = b.abs();
    while b != 0 {
        (a, b) = (b, a % b)
    }
    a
}
fn decimal(n: Int, d: u32) -> String {
    let b = 10i128.pow(d);
    format!(
        "{}{}.{:0width$}",
        if n < 0 { "-" } else { "" },
        n.abs() / b,
        n.abs() % b,
        width = d as usize
    )
}
fn signed(n: Int) -> String {
    if n > 0 {
        format!("+{}", n)
    } else {
        n.to_string()
    }
}
#[derive(Clone, Copy)]
struct Rational {
    n: Int,
    d: Int,
}
impl Rational {
    fn new(n: Int, d: Int) -> Self {
        let g = gcd(n, d);
        Self {
            n: n / g * if d < 0 { -1 } else { 1 },
            d: d.abs() / g,
        }
    }
    fn from(n: Int) -> Self {
        Self { n, d: 1 }
    }
    fn sub(self, b: Self) -> Self {
        Self::new(self.n * b.d - b.n * self.d, self.d * b.d)
    }
    fn mul(self, b: Self) -> Self {
        Self::new(self.n * b.n, self.d * b.d)
    }
    fn div(self, b: Self) -> Self {
        Self::new(self.n * b.d, self.d * b.n)
    }
    fn display(self) -> String {
        if self.d == 1 {
            signed(self.n)
        } else {
            format!("{}/{}", signed(self.n), self.d)
        }
    }
}
fn order(c: &Composition) -> Vec<String> {
    let mut v: Vec<_> = c.keys().cloned().collect();
    if c.contains_key("C") {
        v.sort_by_key(|s| {
            if s == "C" {
                (0, s.clone())
            } else if s == "H" {
                (1, s.clone())
            } else {
                (2, s.clone())
            }
        })
    }
    v
}
fn hill(c: &Composition, q: Int) -> String {
    let mut s = order(c)
        .iter()
        .map(|e| {
            format!(
                "{}{}",
                e,
                if c[e] == 1 {
                    String::new()
                } else {
                    c[e].to_string()
                }
            )
        })
        .collect::<String>();
    if q != 0 {
        s.push_str(&format!(
            "^{}{}",
            if q.abs() == 1 {
                String::new()
            } else {
                q.abs().to_string()
            },
            if q > 0 { "+" } else { "-" }
        ))
    }
    s
}
fn add(a: &mut Composition, b: &Composition, k: Int) {
    for (e, n) in b {
        let entry = a.entry(e.clone()).or_default();
        *entry = entry.saturating_add(n.saturating_mul(k));
    }
}
struct Parser<'a> {
    b: &'a [u8],
    i: usize,
    seen: Vec<String>,
}
impl Parser<'_> {
    fn num(&mut self) -> Result<Int, ()> {
        if self.i == self.b.len() || !self.b[self.i].is_ascii_digit() {
            return Ok(1);
        }
        if self.b[self.i] == b'0' {
            return Err(());
        }
        let mut n = 0;
        while self.i < self.b.len() && self.b[self.i].is_ascii_digit() {
            n = n * 10 + (self.b[self.i] - b'0') as Int;
            self.i += 1
        }
        Ok(n)
    }
    fn seq(&mut self) -> Result<Composition, ()> {
        let mut c = Composition::new();
        let mut count = 0;
        while self.i < self.b.len() {
            let ch = self.b[self.i];
            let part = if ch.is_ascii_uppercase() {
                let begin = self.i;
                self.i += 1;
                if self.i < self.b.len() && self.b[self.i].is_ascii_lowercase() {
                    self.i += 1
                }
                let e = String::from_utf8(self.b[begin..self.i].to_vec()).unwrap();
                self.seen.push(e.clone());
                BTreeMap::from([(e, 1)])
            } else if ch == b'(' || ch == b'[' {
                self.i += 1;
                let v = self.seq()?;
                if self.i == self.b.len() || self.b[self.i] != if ch == b'(' { b')' } else { b']' }
                {
                    return Err(());
                }
                self.i += 1;
                v
            } else {
                break;
            };
            let n = self.num()?;
            add(&mut c, &part, n);
            count += 1
        }
        if count == 0 { Err(()) } else { Ok(c) }
    }
}
#[derive(Clone)]
struct Species {
    name: String,
    formula: String,
    c: Composition,
    q: Int,
    m: Int,
    co: Int,
    gas: bool,
}
fn formula(s: &str) -> Result<(Composition, Int), String> {
    let invalid = || format!("invalid formula {}", s);
    let mut p = Parser {
        b: s.as_bytes(),
        i: 0,
        seen: Vec::new(),
    };
    let mut c = p.seq().map_err(|_| invalid())?;
    while p.i < p.b.len() && p.b[p.i] == b'.' {
        p.i += 1;
        let n = p.num().map_err(|_| invalid())?;
        let v = p.seq().map_err(|_| invalid())?;
        add(&mut c, &v, n)
    }
    let mut q = 0;
    if p.i < p.b.len() && p.b[p.i] == b'^' {
        p.i += 1;
        q = p.num().map_err(|_| invalid())?;
        if p.i == p.b.len() || !b"+-".contains(&p.b[p.i]) {
            return Err(invalid());
        }
        if p.b[p.i] == b'-' {
            q = -q
        }
        p.i += 1
    }
    if p.i != p.b.len() {
        return Err(invalid());
    }
    for e in p.seen {
        if element(&e).is_none() {
            return Err(format!("unknown element {}", e));
        }
    }
    Ok((c, q))
}
fn species(w: &str, coeff: bool) -> Result<Species, String> {
    let mut f = w;
    let mut gas = false;
    for st in ["(s)", "(l)", "(g)", "(aq)"] {
        if f.ends_with(st) {
            gas = st == "(g)";
            f = &f[..f.len() - st.len()];
            break;
        }
    }
    let mut co = 1;
    let mut begin = 0;
    if coeff && f.as_bytes().first().is_some_and(|c| c.is_ascii_digit()) {
        begin = f.bytes().take_while(|c| c.is_ascii_digit()).count();
        if f.starts_with('0') {
            return Err(format!("invalid formula {}", w));
        }
        co = f[..begin].parse().unwrap();
        f = &f[begin..]
    }
    let (c, q) = formula(f).map_err(|e| {
        if e.starts_with("invalid formula") {
            format!("invalid formula {}", w)
        } else {
            e
        }
    })?;
    let m = c.iter().map(|(e, n)| weight(e) * n).sum();
    Ok(Species {
        name: w[begin..].into(),
        formula: f.into(),
        c,
        q,
        m,
        co,
        gas,
    })
}
fn equation(a: &[&str], check: bool) -> Result<(Vec<Species>, usize), String> {
    if a.len() < 3
        || a.len() % 2 == 0
        || a.iter().enumerate().any(|(i, w)| {
            if i % 2 == 1 {
                *w != "+" && *w != "->"
            } else {
                *w == "+" || *w == "->"
            }
        })
        || a.iter().filter(|&&w| w == "->").count() != 1
    {
        return Err("malformed equation".into());
    }
    let r = (a.iter().position(|&w| w == "->").unwrap() + 1) / 2;
    let s = a
        .iter()
        .step_by(2)
        .map(|w| species(w, check))
        .collect::<Result<Vec<_>, _>>()?;
    Ok((s, r))
}
fn matrix(s: &[Species], r: usize) -> (Vec<String>, Vec<Vec<Int>>) {
    let mut all = Composition::new();
    for x in s {
        for e in x.c.keys() {
            all.insert(e.clone(), 1);
        }
    }
    let mut labels = order(&all);
    labels.push("charge".into());
    let rows = labels
        .iter()
        .map(|element| {
            s.iter()
                .enumerate()
                .map(|(i, species)| {
                    let sign = if i < r { 1 } else { -1 };
                    let count = if element == "charge" {
                        species.q
                    } else {
                        *species.c.get(element).unwrap_or(&0)
                    };
                    sign * count
                })
                .collect()
        })
        .collect();
    (labels, rows)
}
fn basis(rows: &[Vec<Int>], n: usize) -> (usize, Vec<Vec<Int>>) {
    let mut a: Vec<Vec<_>> = rows
        .iter()
        .map(|r| r.iter().map(|&n| Rational::from(n)).collect())
        .collect();
    let mut piv = Vec::new();
    for j in 0..n {
        let r = piv.len();
        if let Some(i) = (r..a.len()).find(|&i| a[i][j].n != 0) {
            a.swap(r, i);
            let v = a[r][j];
            for k in 0..n {
                a[r][k] = a[r][k].div(v)
            }
            for i in 0..a.len() {
                if i != r {
                    let v = a[i][j];
                    for k in 0..n {
                        a[i][k] = a[i][k].sub(v.mul(a[r][k]))
                    }
                }
            }
            piv.push(j)
        }
    }
    let mut result = Vec::new();
    for f in 0..n {
        if piv.contains(&f) {
            continue;
        }
        let mut v = vec![Rational::from(0); n];
        v[f] = Rational::from(1);
        for (i, &j) in piv.iter().enumerate() {
            v[j] = Rational::from(0).sub(a[i][f])
        }
        let l = v.iter().fold(1, |l, x| l / gcd(l, x.d) * x.d);
        let mut ints: Vec<_> = v.iter().map(|x| x.n * (l / x.d)).collect();
        let g = ints.iter().fold(0, |g, &x| gcd(g, x));
        for x in &mut ints {
            *x /= g
        }
        result.push(ints)
    }
    (piv.len(), result)
}
fn coefficients(s: &[Species], r: usize, k: usize) -> Result<Vec<Int>, String> {
    let (_, rows) = matrix(s, r);
    solve(&rows, s.len(), k)
}
fn solve(rows: &[Vec<Int>], n: usize, k: usize) -> Result<Vec<Int>, String> {
    let (_, mut b) = basis(rows, n);
    if b.len() > 1 {
        return Err(format!("AMBIGUOUS (nullity {})", b.len()));
    }
    if b.is_empty() {
        return Err("IMPOSSIBLE".into());
    }
    let mut c = b.remove(0);
    if c[0] < 0 {
        for x in &mut c {
            *x = -*x
        }
    }
    if c[..k].iter().any(|&x| x <= 0) {
        return Err("IMPOSSIBLE".into());
    }
    Ok(c)
}
fn term(s: &str, c: Int) -> String {
    format!(
        "{}{}",
        if c == 1 { String::new() } else { c.to_string() },
        s
    )
}
fn balanced(s: &[Species], r: usize, c: &[Int]) -> String {
    format!(
        "{} -> {}",
        (0..r)
            .map(|i| term(&s[i].name, c[i]))
            .collect::<Vec<_>>()
            .join(" + "),
        (r..s.len())
            .map(|i| term(&s[i].name, c[i]))
            .collect::<Vec<_>>()
            .join(" + ")
    )
}
fn value(w: &str, d: usize, max: usize, negative: bool, positive: bool) -> Option<Int> {
    let mut s = w;
    let mut sign = 1;
    if negative && s.starts_with('-') {
        s = &s[1..];
        sign = -1
    }
    let p: Vec<_> = s.split('.').collect();
    if p.len() > 2
        || p[0].is_empty()
        || p[0].len() > max
        || !p[0].bytes().all(|c| c.is_ascii_digit())
        || (p[0].len() > 1 && p[0].starts_with('0'))
    {
        return None;
    }
    let fraction = if p.len() == 2 {
        if p[1].is_empty() || p[1].len() > d || !p[1].bytes().all(|c| c.is_ascii_digit()) {
            return None;
        }
        p[1].parse::<Int>().ok()? * 10i128.pow((d - p[1].len()) as u32)
    } else {
        0
    };
    let n = sign * (p[0].parse::<Int>().ok()? * 10i128.pow(d as u32) + fraction);
    if positive && n <= 0 { None } else { Some(n) }
}
fn quantity(w: &str) -> Result<Int, String> {
    value(w, 3, 4, false, true).ok_or_else(|| format!("invalid quantity {}", w))
}
fn ratio(a: &Composition) -> Vec<String> {
    let keys = order(a);
    let f = keys
        .iter()
        .min_by(|x, y| (a[*x] * weight(y)).cmp(&(a[*y] * weight(x))))
        .unwrap();
    let mut out = keys
        .iter()
        .map(|e| {
            format!(
                "{} {}",
                e,
                decimal(1000 * a[e] * weight(f) / (weight(e) * a[f]), 3)
            )
        })
        .collect::<Vec<_>>();
    for k in 1..=12 {
        let mut c = Composition::new();
        let mut ok = true;
        for e in &keys {
            let n = k * a[e] * weight(f);
            let d = weight(e) * a[f];
            let i = (2 * n + d) / (2 * d);
            if 20 * (n - i * d).abs() > d {
                ok = false;
                break;
            }
            c.insert(e.clone(), i);
        }
        if ok {
            out.push(format!("{} (k = {})", hill(&c, 0), k));
            return out;
        }
    }
    out.push("no simple ratio".into());
    out
}
fn process(w: &[&str], heats: &mut BTreeMap<String, Int>) -> Result<Vec<String>, String> {
    let cmd = w[0];
    let a = &w[1..];
    let wrong = || format!("wrong argument count for {}", cmd);
    let valid = match cmd {
        "ELEMENT" | "PARSE" | "MASS" | "PERCENT" | "EMPIRICAL" | "DBE" | "OXSTATE" => a.len() == 1,
        "MOLES" | "GRAMS" | "MOLECULAR" | "SALT" | "HEAT" => a.len() == 2,
        "COMBUST" => a.len() == 3,
        "HEATS" => a.is_empty(),
        "DERIVE" => a.len() >= 2 && a.len() % 2 == 0,
        "BALANCE" | "MATRIX" | "CHECK" | "DELTAH" => !a.is_empty(),
        "REDOX" | "HALF" => a.len() >= 2,
        "STOICH" | "LIMITING" | "YIELD" => true,
        _ => return Err(format!("unknown command {}", cmd)),
    };
    if !valid {
        return Err(wrong());
    }
    let mut out = Vec::new();
    match cmd {
        "ELEMENT" => {
            let i = element(a[0]).ok_or_else(|| format!("unknown element {}", a[0]))?;
            out.push(format!(
                "{} (Z = {}) {} u",
                a[0],
                i + 1,
                decimal(WEIGHTS[i], 3)
            ))
        }
        "HEATS" => {
            if heats.is_empty() {
                out.push("no enthalpies".into())
            } else {
                for (s, h) in heats.iter() {
                    out.push(format!("{} {} kJ/mol", s, decimal(*h, 2)))
                }
            }
        }
        "HEAT" => {
            species(a[0], false)?;
            let h = value(a[1], 2, 5, true, false)
                .ok_or_else(|| format!("invalid enthalpy {}", a[1]))?;
            let old = heats.get(a[0]);
            out.push(format!(
                "dHf({}) = {} kJ/mol{}",
                a[0],
                decimal(h, 2),
                old.map(|x| format!(" (was {})", decimal(*x, 2)))
                    .unwrap_or_default()
            ));
            heats.insert(a[0].into(), h);
        }
        "DERIVE" => {
            let mut amounts = Composition::new();
            let mut sum = 0;
            for pair in a.chunks(2) {
                if element(pair[0]).is_none() {
                    return Err(format!("unknown element {}", pair[0]));
                }
                if amounts.contains_key(pair[0]) {
                    return Err(format!("duplicate element {}", pair[0]));
                }
                let q = quantity(pair[1])?;
                if q > 100000 {
                    return Err(format!("invalid percentage {}", pair[1]));
                }
                amounts.insert(pair[0].into(), q);
                sum += q;
            }
            if (sum - 100000).abs() > 1000 {
                return Err(format!("percentages sum to {}", decimal(sum, 3)));
            }
            out = ratio(&amounts)
        }
        "COMBUST" => {
            let s = quantity(a[0])?;
            let p = quantity(a[1])?;
            let r = quantity(a[2])?;
            let c = p * 12011 / 44009;
            let h = r * 2016 / 18015;
            let o = s - c - h;
            if c == 0 || h == 0 || 100 * o < -s {
                return Err("inconsistent masses".into());
            }
            let mut amounts = Composition::from([("C".into(), c), ("H".into(), h)]);
            if 100 * o > s {
                amounts.insert("O".into(), o);
            }
            for e in ["C", "H", "O"] {
                if let Some(n) = amounts.get(e) {
                    out.push(format!("mass {} {} g", e, decimal(*n, 3)))
                }
            }
            out.extend(ratio(&amounts));
        }
        "SALT" => {
            let (c, p) = formula(a[0])?;
            let (d, q) = formula(a[1])?;
            if p <= 0 {
                return Err(format!("not a cation {}", a[0]));
            }
            if q >= 0 {
                return Err(format!("not an anion {}", a[1]));
            }
            for f in a {
                if f.contains('.') {
                    return Err(format!("hydrate ion {}", f));
                }
            }
            let g = gcd(p, q);
            let n = -q / g;
            let m = p / g;
            let part = |f: &str, k: Int| {
                let core = f.split('^').next().unwrap();
                if k == 1 {
                    return core.to_string();
                }
                let single = core.bytes().enumerate().all(|(i, c)| {
                    if i == 0 {
                        c.is_ascii_uppercase()
                    } else {
                        i == 1 && c.is_ascii_lowercase()
                    }
                });
                let mut depth = 0;
                let mut whole = core.starts_with('[') && core.ends_with(']');
                for (i, ch) in core.bytes().enumerate() {
                    if ch == b'[' {
                        depth += 1
                    }
                    if ch == b']' {
                        depth -= 1;
                        if depth == 0 && i + 1 < core.len() {
                            whole = false
                        }
                    }
                }
                if single || whole {
                    format!("{}{}", core, k)
                } else {
                    format!("({}){}", core, k)
                }
            };
            let mut all = Composition::new();
            add(&mut all, &c, n);
            add(&mut all, &d, m);
            let mass: Int = all.iter().map(|(e, n)| weight(e) * n).sum();
            out.push(format!(
                "{}{} ({}, {} g/mol)",
                part(a[0], n),
                part(a[1], m),
                hill(&all, 0),
                decimal(mass, 3)
            ));
        }
        "PARSE" | "MASS" | "PERCENT" | "EMPIRICAL" | "DBE" | "OXSTATE" | "MOLES" | "GRAMS"
        | "MOLECULAR" => {
            let (c, q) = formula(a[0])?;
            let mass: Int = c.iter().map(|(e, n)| weight(e) * n).sum();
            let keys = order(&c);
            match cmd {
                "PARSE" => out.push(format!(
                    "{} ({}; charge {})",
                    hill(&c, q),
                    keys.iter()
                        .map(|e| format!("{} {}", e, c[e]))
                        .collect::<Vec<_>>()
                        .join(", "),
                    signed(q)
                )),
                "MASS" => out.push(format!("M({}) = {} g/mol", a[0], decimal(mass, 3))),
                "PERCENT" => {
                    for e in keys {
                        out.push(format!(
                            "{} {}%",
                            e,
                            decimal(10000 * c[&e] * weight(&e) / mass, 2)
                        ))
                    }
                }
                "EMPIRICAL" => {
                    let g = c.values().fold(0, |g, &n| gcd(g, n));
                    let cc = c.iter().map(|(e, n)| (e.clone(), n / g)).collect();
                    out.push(format!("{} (n = {})", hill(&cc, 0), g))
                }
                "DBE" => {
                    if q != 0 {
                        return Err(format!("charged formula {}", a[0]));
                    }
                    let mut t = 2;
                    for e in keys {
                        let v = match e.as_str() {
                            "H" | "F" | "Cl" | "Br" | "I" => 1,
                            "O" | "S" | "Se" => 2,
                            "B" | "N" | "P" | "As" => 3,
                            "C" | "Si" | "Ge" => 4,
                            _ => return Err(format!("no valence for {}", e)),
                        };
                        t += c[&e] * (v - 2)
                    }
                    out.push(format!(
                        "DBE = {}{}.{}",
                        if t < 0 { "-" } else { "" },
                        t.abs() / 2,
                        if t % 2 == 0 { 0 } else { 5 }
                    ));
                }
                "OXSTATE" => {
                    let mut assigned: BTreeMap<String, Rational> = BTreeMap::new();
                    let metals = |e: &str| match e {
                        "Li" | "Na" | "K" | "Rb" => Some(1),
                        "Be" | "Mg" | "Ca" | "Sr" => Some(2),
                        "Al" => Some(3),
                        _ => None,
                    };
                    if keys.len() == 1 {
                        assigned.insert(keys[0].clone(), Rational::new(q, c[&keys[0]]));
                    } else {
                        let mut assignments = Vec::new();
                        if c.contains_key("F") {
                            assignments.push(("F".to_string(), -1))
                        }
                        for e in &keys {
                            if let Some(v) = metals(e) {
                                assignments.push((e.clone(), v))
                            }
                        }
                        if c.contains_key("H") {
                            assignments.push((
                                "H".into(),
                                if keys
                                    .iter()
                                    .filter(|e| *e != "H")
                                    .all(|e| metals(e).is_some())
                                {
                                    -1
                                } else {
                                    1
                                },
                            ))
                        }
                        if c.contains_key("O") {
                            assignments.push(("O".into(), -2))
                        }
                        if !c.contains_key("O") && !c.contains_key("F") {
                            for e in ["Cl", "Br", "I"] {
                                if c.contains_key(e) {
                                    assignments.push((e.into(), -1));
                                    break;
                                }
                            }
                        }
                        let sum: Int = assignments.iter().map(|(e, n)| c[e] * n).sum();
                        for (e, n) in &assignments {
                            assigned.insert(e.clone(), Rational::from(*n));
                        }
                        let unknown: Vec<_> =
                            keys.iter().filter(|e| !assigned.contains_key(*e)).collect();
                        if unknown.len() > 1 {
                            out.push(format!(
                                "indeterminate: {}",
                                unknown
                                    .iter()
                                    .map(|s| s.as_str())
                                    .collect::<Vec<_>>()
                                    .join(" ")
                            ));
                            return Ok(out);
                        }
                        if unknown.len() == 1 {
                            let e = unknown[0];
                            assigned.insert(e.clone(), Rational::new(q - sum, c[e]));
                        } else if sum != q {
                            let (e, n) = assignments.last().unwrap();
                            assigned.insert(e.clone(), Rational::new(q - sum + c[e] * n, c[e]));
                        }
                    }
                    out.push(
                        keys.iter()
                            .map(|e| format!("{} {}", e, assigned[e].display()))
                            .collect::<Vec<_>>()
                            .join(", "),
                    );
                }
                "MOLES" | "GRAMS" => {
                    let n = quantity(a[1])?;
                    out.push(if cmd == "MOLES" {
                        format!(
                            "{} g {} = {} mol",
                            decimal(n, 3),
                            a[0],
                            decimal(n * 1000000 / mass, 6)
                        )
                    } else {
                        format!(
                            "{} mol {} = {} g",
                            decimal(n, 3),
                            a[0],
                            decimal(n * mass / 1000, 3)
                        )
                    })
                }
                "MOLECULAR" => {
                    if q != 0 {
                        return Err(format!("charged formula {}", a[0]));
                    }
                    let n = quantity(a[1])?;
                    let k = (2 * n + mass) / (2 * mass);
                    if k == 0 || 10 * (n - k * mass).abs() > mass {
                        out.push(format!(
                            "no integer multiple (ratio {})",
                            decimal(1000 * n / mass, 3)
                        ))
                    } else {
                        let cc = c.iter().map(|(e, n)| (e.clone(), n * k)).collect();
                        out.push(format!(
                            "{} (n = {}, {} g/mol)",
                            hill(&cc, 0),
                            k,
                            decimal(k * mass, 3)
                        ))
                    }
                }
                _ => {}
            }
        }
        "REDOX" | "HALF" => {
            if a[0] != "acidic" && a[0] != "basic" {
                return Err(format!("invalid medium {}", a[0]));
            }
            let (mut s, r) = equation(&a[1..], false)?;
            for x in &s {
                if ["H^+", "OH^-", "H2O"].contains(&x.formula.as_str()) {
                    return Err(format!("reserved species {}", x.name));
                }
            }
            let n = s.len();
            let original = s.clone();
            let aux = if a[0] == "acidic" { "H^+" } else { "OH^-" };
            s.push(species(aux, false)?);
            s.push(species("H2O", false)?);
            if cmd == "HALF" {
                s.push(Species {
                    name: "e^-".into(),
                    formula: "e^-".into(),
                    c: Composition::new(),
                    q: -1,
                    m: 0,
                    co: 1,
                    gas: false,
                })
            }
            let (_, mut rows) = matrix(&s, r);
            for row in &mut rows {
                for value in &mut row[n..] {
                    *value = -*value;
                }
            }
            let c = match solve(&rows, s.len(), n) {
                Ok(c) => c,
                Err(e) => {
                    out.push(e);
                    return Ok(out);
                }
            };
            let mut left = (0..r)
                .map(|i| term(&original[i].name, c[i]))
                .collect::<Vec<_>>();
            let mut right = (r..n)
                .map(|i| term(&original[i].name, c[i]))
                .collect::<Vec<_>>();
            for i in n..s.len() {
                if c[i] > 0 {
                    left.push(term(&s[i].name, c[i]))
                } else if c[i] < 0 {
                    right.push(term(&s[i].name, -c[i]))
                }
            }
            out.push(format!("{} -> {}", left.join(" + "), right.join(" + ")));
            if cmd == "HALF" {
                out.push(
                    if *c.last().unwrap() > 0 {
                        "reduction"
                    } else if *c.last().unwrap() < 0 {
                        "oxidation"
                    } else {
                        "no electron transfer"
                    }
                    .into(),
                )
            }
        }
        _ => {
            let mut tail = &[][..];
            let eq = if ["STOICH", "LIMITING", "YIELD"].contains(&cmd) {
                if a.iter().filter(|&&x| x == ":").count() != 1 {
                    return Err("invalid separator".into());
                }
                let j = a.iter().position(|&x| x == ":").unwrap();
                tail = &a[j + 1..];
                if (cmd == "STOICH" && tail.len() != 2) || (cmd == "YIELD" && tail.len() != 4) {
                    return Err(wrong());
                }
                &a[..j]
            } else {
                a
            };
            let (s, r) = equation(eq, cmd == "CHECK")?;
            if cmd == "MATRIX" {
                let (labels, rows) = matrix(&s, r);
                out.push(format!(
                    "columns: {}",
                    s.iter()
                        .map(|x| x.name.as_str())
                        .collect::<Vec<_>>()
                        .join(" ")
                ));
                for (e, row) in labels.iter().zip(&rows) {
                    out.push(format!(
                        "{}: {}",
                        e,
                        row.iter()
                            .map(ToString::to_string)
                            .collect::<Vec<_>>()
                            .join(" ")
                    ))
                }
                let (rank, b) = basis(&rows, s.len());
                out.push(format!("rank {}, nullity {}", rank, b.len()));
                for v in b {
                    out.push(format!(
                        "null: {}",
                        v.iter()
                            .map(ToString::to_string)
                            .collect::<Vec<_>>()
                            .join(" ")
                    ))
                }
                return Ok(out);
            }
            if cmd == "CHECK" {
                let (labels, rows) = matrix(&s, r);
                for (e, row) in labels.iter().zip(&rows) {
                    let l: Int = (0..r).map(|i| row[i] * s[i].co).sum();
                    let h: Int = (r..s.len()).map(|i| -row[i] * s[i].co).sum();
                    if l != h {
                        out.push(format!(
                            "{}: {} != {}",
                            e,
                            if e == "charge" {
                                signed(l)
                            } else {
                                l.to_string()
                            },
                            if e == "charge" {
                                signed(h)
                            } else {
                                h.to_string()
                            }
                        ))
                    }
                }
                if !out.is_empty() {
                    out.insert(0, "not balanced".into())
                } else {
                    let g = s.iter().fold(0, |g, x| gcd(g, x.co));
                    out.push(if g == 1 {
                        "balanced".into()
                    } else {
                        format!("balanced, not in lowest terms (gcd {})", g)
                    })
                }
                return Ok(out);
            }
            let mut quantities = Vec::new();
            let mut ia = 0;
            let mut ib = 0;
            if cmd == "STOICH" {
                ia = s
                    .iter()
                    .position(|x| x.name == tail[0])
                    .ok_or_else(|| format!("species {} not in equation", tail[0]))?;
                quantities.push(quantity(tail[1])?)
            }
            if cmd == "LIMITING" {
                if tail.len() != r {
                    return Err(format!("expected {} masses, got {}", r, tail.len()));
                }
                for q in tail {
                    quantities.push(quantity(q)?);
                }
            }
            if cmd == "YIELD" {
                ia = s[..r]
                    .iter()
                    .position(|x| x.name == tail[0])
                    .ok_or_else(|| format!("{} is not a reactant", tail[0]))?;
                ib = r + s[r..]
                    .iter()
                    .position(|x| x.name == tail[2])
                    .ok_or_else(|| format!("{} is not a product", tail[2]))?;
                quantities.push(quantity(tail[1])?);
                quantities.push(quantity(tail[3])?);
            }
            if cmd == "DELTAH" {
                for x in &s {
                    if !heats.contains_key(&x.name) {
                        return Err(format!("no enthalpy for {}", x.name));
                    }
                }
            }
            let c = match coefficients(&s, r, s.len()) {
                Ok(c) => c,
                Err(e) => {
                    out.push(e);
                    return Ok(out);
                }
            };
            out.push(balanced(&s, r, &c));
            match cmd {
                "STOICH" => {
                    let d = c[ia] * s[ia].m;
                    let q = quantities[0];
                    for (i, x) in s.iter().enumerate() {
                        out.push(format!(
                            "{} {} mol {} g{}",
                            x.name,
                            decimal(q * c[i] * 1000000 / d, 6),
                            decimal(q * c[i] * x.m / d, 3),
                            if x.gas {
                                format!(" {} L", decimal(q * c[i] * 22414 / d, 3))
                            } else {
                                String::new()
                            }
                        ))
                    }
                }
                "LIMITING" => {
                    let l = (0..r)
                        .min_by(|&i, &j| {
                            (quantities[i] * c[j] * s[j].m).cmp(&(quantities[j] * c[i] * s[i].m))
                        })
                        .unwrap();
                    let q = quantities[l];
                    let d = c[l] * s[l].m;
                    out.push(format!("limiting {}", s[l].name));
                    out.push(format!("extent {} mol", decimal(q * 1000000 / d, 6)));
                    for i in r..s.len() {
                        out.push(format!(
                            "product {} {} g{}",
                            s[i].name,
                            decimal(q * c[i] * s[i].m / d, 3),
                            if s[i].gas {
                                format!(" {} L", decimal(q * c[i] * 22414 / d, 3))
                            } else {
                                String::new()
                            }
                        ))
                    }
                    for i in 0..r {
                        if i != l {
                            out.push(format!(
                                "remaining {} {} g",
                                s[i].name,
                                decimal((quantities[i] * d - q * c[i] * s[i].m) / d, 3)
                            ))
                        }
                    }
                }
                "YIELD" => {
                    let t = quantities[0] * c[ib] * s[ib].m / (c[ia] * s[ia].m);
                    out.push(format!("theoretical {} g", decimal(t, 3)));
                    out.push(format!("actual {} g", decimal(quantities[1], 3)));
                    out.push(if t == 0 {
                        "yield undefined".into()
                    } else {
                        format!("yield {}%", decimal(quantities[1] * 10000 / t, 2))
                    })
                }
                "DELTAH" => {
                    let h: Int = s
                        .iter()
                        .enumerate()
                        .map(|(i, x)| c[i] * heats[&x.name] * if i < r { -1 } else { 1 })
                        .sum();
                    out.push(format!(
                        "dH = {} kJ ({})",
                        decimal(h, 2),
                        if h < 0 {
                            "exothermic"
                        } else if h > 0 {
                            "endothermic"
                        } else {
                            "thermoneutral"
                        }
                    ))
                }
                _ => {}
            }
        }
    }
    Ok(out)
}
fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut heats = BTreeMap::new();
    for line in input.lines().skip(1) {
        let w: Vec<_> = line.split_whitespace().collect();
        if w.is_empty() {
            continue;
        }
        match process(&w, &mut heats) {
            Ok(lines) => {
                for l in lines {
                    println!("{}", l)
                }
            }
            Err(e) => println!("error: {}", e),
        }
    }
}
