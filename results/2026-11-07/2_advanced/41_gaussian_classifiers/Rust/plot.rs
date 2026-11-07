use crate::evaluation::Fraction;
use std::fs;

pub fn real(value: f64) -> String {
    if value.abs() < 0.00005 { "0.0000".into() } else { format!("{value:.4}") }
}

pub fn fraction(value: Fraction) -> String {
    format!("{}/{} {}", value.numerator, value.denominator, real(value.numerator as f64 / value.denominator as f64))
}

pub fn ratio(numerator: usize, denominator: usize) -> String {
    if denominator == 0 { "-".into() } else { fraction(Fraction::new(numerator as i64, denominator as i64)) }
}

pub fn frame(cells: &[Vec<u8>]) -> Vec<String> {
    let border = format!("+{}+", "-".repeat(cells[0].len()));
    let mut lines = vec![border.clone()];
    lines.extend(cells.iter().map(|row| format!("|{}|", String::from_utf8(row.clone()).unwrap())));
    lines.push(border);
    lines
}

pub fn cell(value: f64, low: f64, high: f64, size: usize) -> usize { ((value - low) / (high - low) * (size - 1) as f64 + 0.5).floor() as usize }

pub fn write(name: &str, lines: &[String]) {
    fs::write(format!("output/{name}"), format!("{}\n", lines.join("\n"))).unwrap();
}
