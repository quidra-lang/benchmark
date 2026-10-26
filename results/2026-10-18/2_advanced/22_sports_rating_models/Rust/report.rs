use std::cmp::Ordering;
use std::ops::{Add, Div, Mul, Sub};
use std::{fs, io};

#[derive(Clone, Copy, Eq, PartialEq)]
pub struct Fraction { pub numerator: i64, pub denominator: i64 }
impl Fraction {
    pub fn new(mut numerator: i64, mut denominator: i64) -> Self {
        if denominator < 0 { numerator = -numerator; denominator = -denominator; }
        let (mut a, mut b) = (numerator.abs(), denominator);
        while b != 0 { (a, b) = (b, a % b); }
        Self { numerator: numerator / a, denominator: denominator / a }
    }
    pub fn integer(value: i64) -> Self { Self::new(value, 1) }
    pub fn real(self) -> f64 { self.numerator as f64 / self.denominator as f64 }
    pub fn text(self) -> String { format!("{}/{}", self.numerator, self.denominator) }
    pub fn fixed(self, places: usize) -> String {
        let scale = 10i64.pow(places as u32);
        let mut whole = self.numerator.abs() / self.denominator;
        let mut remainder = self.numerator.abs() % self.denominator;
        let mut fraction = 0;
        for _ in 0..places {
            remainder *= 10;
            fraction = fraction * 10 + remainder / self.denominator;
            remainder %= self.denominator;
        }
        if 2 * remainder >= self.denominator { fraction += 1; }
        if fraction == scale { whole += 1; fraction = 0; }
        format!("{}{}.{:0places$}", if self.numerator < 0 && (whole > 0 || fraction > 0) { "-" } else { "" }, whole, fraction)
    }
    pub fn with_real(self) -> String { format!("{} {}", self.text(), self.fixed(4)) }
}
impl Ord for Fraction { fn cmp(&self, other: &Self) -> Ordering { (self.numerator * other.denominator).cmp(&(other.numerator * self.denominator)) } }
impl PartialOrd for Fraction { fn partial_cmp(&self, other: &Self) -> Option<Ordering> { Some(self.cmp(other)) } }
impl Add for Fraction { type Output = Self; fn add(self, rhs: Self) -> Self { Self::new(self.numerator * rhs.denominator + rhs.numerator * self.denominator, self.denominator * rhs.denominator) } }
impl Sub for Fraction { type Output = Self; fn sub(self, rhs: Self) -> Self { Self::new(self.numerator * rhs.denominator - rhs.numerator * self.denominator, self.denominator * rhs.denominator) } }
impl Mul for Fraction { type Output = Self; fn mul(self, rhs: Self) -> Self { Self::new(self.numerator * rhs.numerator, self.denominator * rhs.denominator) } }
impl Div for Fraction { type Output = Self; fn div(self, rhs: Self) -> Self { Self::new(self.numerator * rhs.denominator, self.denominator * rhs.numerator) } }
pub fn decimal_value(value: f64, places: usize) -> i64 { (value * 10f64.powi(places as i32)).round() as i64 }
pub fn fixed(value: f64, places: usize) -> String {
    let text = format!("{value:.places$}");
    if text.starts_with('-') && text.parse::<f64>().unwrap() == 0.0 { text[1..].to_owned() } else { text }
}
pub fn write_lines(path: &str, lines: &[String]) -> io::Result<()> { fs::write(path, lines.join("\n") + "\n") }
