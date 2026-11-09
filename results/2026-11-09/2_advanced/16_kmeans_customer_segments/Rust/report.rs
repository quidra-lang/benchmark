use std::{fs, io};

pub fn real(value: f64) -> String {
    let text = format!("{value:.4}");
    if text == "-0.0000" { "0.0000".to_owned() } else { text }
}
pub fn reals(values: &[f64]) -> String { values.iter().map(|&value| real(value)).collect::<Vec<_>>().join(" ") }
pub fn four_decimal(value: f64) -> i64 { (value * 10000.0).round() as i64 }
pub fn amount(cents: i64) -> String {
    let sign = if cents < 0 { "-" } else { "" };
    format!("{sign}{}.{:02}", cents.abs() / 100, cents.abs() % 100)
}
pub fn write_lines(path: &str, lines: &[String]) -> io::Result<()> { fs::write(path, lines.join("\n") + "\n") }
