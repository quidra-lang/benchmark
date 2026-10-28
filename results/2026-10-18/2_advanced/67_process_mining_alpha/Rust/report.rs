use std::cmp::Ordering;
use std::fs;

#[derive(Clone, Copy, Eq, PartialEq)]
pub struct Fraction { pub numerator: i64, pub denominator: i64 }
impl Fraction {
    pub fn new(numerator: i64, denominator: i64) -> Self {
        let (mut a, mut b) = (numerator.abs(), denominator.abs());
        while b != 0 { let r = a%b; a = b; b = r; }
        let sign = if denominator < 0 { -1 } else { 1 };
        Self { numerator: sign*numerator/a, denominator: denominator.abs()/a }
    }
    pub fn parse(value: &str) -> Self {
        let (a, b) = value.split_once('/').unwrap(); Self::new(a.parse().unwrap(), b.parse().unwrap())
    }
    pub fn subtract(self, other: Self) -> Self {
        Self::new(self.numerator*other.denominator-other.numerator*self.denominator, self.denominator*other.denominator)
    }
    pub fn text(self) -> String {
        let n = self.numerator.abs();
        let decimal = 10000*n/self.denominator;
        format!("{}{}/{}={}{}.{:04}", if self.numerator < 0 { "-" } else { "" }, n, self.denominator,
            if self.numerator < 0 && decimal != 0 { "-" } else { "" }, decimal/10000, decimal%10000)
    }
}
impl Ord for Fraction {
    fn cmp(&self, other: &Self) -> Ordering { (self.numerator*other.denominator).cmp(&(other.numerator*self.denominator)) }
}
impl PartialOrd for Fraction { fn partial_cmp(&self, other: &Self) -> Option<Ordering> { Some(self.cmp(other)) } }
pub fn fraction(a: i64, b: i64) -> String { Fraction::new(a, b).text() }
pub fn percentage(a: usize, b: usize) -> String { let t = 10000*a/b; format!("{}.{:02}%", t/100, t%100) }
pub fn list(values: &[String]) -> String { if values.is_empty() { "-".to_owned() } else { values.join(",") } }
pub fn write(file: &str, lines: &[String]) {
    fs::create_dir_all("output").unwrap(); fs::write(format!("output/{}", file), lines.join("\n")+"\n").unwrap();
}
