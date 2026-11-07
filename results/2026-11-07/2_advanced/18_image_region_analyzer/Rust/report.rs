use std::cmp::Ordering;
use std::{fs, io};

#[derive(Clone, Copy, Eq, PartialEq)]
pub struct Rational { pub numerator: i64, pub denominator: i64 }

fn gcd(mut first: i64, mut second: i64) -> i64 {
    while second != 0 { let remainder = first % second; first = second; second = remainder; }
    first
}

impl Rational {
    pub fn new(numerator: i64, denominator: i64) -> Self {
        let divisor = gcd(numerator.abs(), denominator);
        Self { numerator: numerator / divisor, denominator: denominator / divisor }
    }
    pub fn integer(value: i64) -> Self { Self::new(value, 1) }
}

impl Ord for Rational {
    fn cmp(&self, other: &Self) -> Ordering { (self.numerator * other.denominator).cmp(&(other.numerator * self.denominator)) }
}
impl PartialOrd for Rational {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> { Some(self.cmp(other)) }
}

pub fn decimal(value: Rational, digits: u32) -> String {
    let scale = 10i64.pow(digits);
    let rounded = (2 * scale * value.numerator.abs() + value.denominator) / (2 * value.denominator);
    let sign = if value.numerator < 0 && rounded > 0 { "-" } else { "" };
    format!("{sign}{}.{:0width$}", rounded / scale, rounded % scale, width = digits as usize)
}

pub fn hull_area_text(doubled: i64) -> String { format!("{}.{}", doubled / 2, if doubled % 2 == 0 { 0 } else { 5 }) }

pub fn write_files(directory: &str, files: &[(&str, Vec<String>)]) -> io::Result<()> {
    fs::create_dir_all(directory)?;
    for (name, lines) in files { fs::write(format!("{directory}/{name}"), lines.join("\n") + "\n")?; }
    Ok(())
}
