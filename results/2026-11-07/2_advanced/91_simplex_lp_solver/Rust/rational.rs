use std::cmp::Ordering;
use std::fmt;
use std::ops::{Add, Sub, Mul, Div, Neg};
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Fraction { pub n: i64, pub d: i64 }
impl Fraction {
    pub fn new(mut n: i64, mut d: i64) -> Self {
        if d < 0 { n = -n; d = -d; }
        let (mut a, mut b) = (n.abs(), d);
        while b != 0 { let r = a % b; a = b; b = r; }
        Self { n: n / a, d: d / a }
    }
    pub fn integer(n: i64) -> Self { Self { n, d: 1 } }
    pub fn zero() -> Self { Self::integer(0) }
    pub fn floor(self) -> i64 { self.n.div_euclid(self.d) }
    pub fn ceil(self) -> i64 { -(-self.n).div_euclid(self.d) }
    pub fn abs(self) -> Self { Self::new(self.n.abs(), self.d) }
    pub fn approximate(self) -> String {
        let t = (2 * self.n.abs() * 1_000_000 + self.d) / (2 * self.d);
        format!("{}{}.{:06}", if self.n < 0 && t > 0 { "-" } else { "" }, t / 1_000_000, t % 1_000_000)
    }
    pub fn parse(s: &str) -> Option<Self> {
        let (negative, s) = if let Some(s) = s.strip_prefix('-') { (true, s) } else { (false, s) };
        let digits = |s: &str| !s.is_empty() && s.bytes().all(|c| c.is_ascii_digit());
        let f = if digits(s) { Self::integer(s.parse().ok()?) }
        else if let Some((a, b)) = s.split_once('.') {
            if !digits(a) || !digits(b) { return None; }
            Self::new(format!("{}{}", a, b).parse().ok()?, 10i64.pow(b.len() as u32))
        } else if let Some((a, b)) = s.split_once('/') {
            if !digits(a) || !digits(b) { return None; }
            let d = b.parse().ok()?;
            if d == 0 { return None; }
            Self::new(a.parse().ok()?, d)
        } else { return None; };
        Some(if negative { -f } else { f })
    }
}
impl Ord for Fraction { fn cmp(&self, b: &Self) -> Ordering { (self.n * b.d).cmp(&(b.n * self.d)) } }
impl PartialOrd for Fraction { fn partial_cmp(&self, b: &Self) -> Option<Ordering> { Some(self.cmp(b)) } }
impl Add for Fraction { type Output = Self; fn add(self, b: Self) -> Self { Self::new(self.n * b.d + b.n * self.d, self.d * b.d) } }
impl Sub for Fraction { type Output = Self; fn sub(self, b: Self) -> Self { Self::new(self.n * b.d - b.n * self.d, self.d * b.d) } }
impl Mul for Fraction { type Output = Self; fn mul(self, b: Self) -> Self { Self::new(self.n * b.n, self.d * b.d) } }
impl Div for Fraction { type Output = Self; fn div(self, b: Self) -> Self { Self::new(self.n * b.d, self.d * b.n) } }
impl Neg for Fraction { type Output = Self; fn neg(self) -> Self { Self { n: -self.n, d: self.d } } }
impl fmt::Display for Fraction {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.d == 1 { write!(f, "{}", self.n) } else { write!(f, "{}/{}", self.n, self.d) }
    }
}
