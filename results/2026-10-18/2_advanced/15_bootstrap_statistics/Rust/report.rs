use std::{fs, io};
use crate::tests::reduced_fraction;

pub fn real(value: f64) -> String { let text = format!("{value:.4}"); if text == "-0.0000" { "0.0000".to_owned() } else { text } }
pub fn p_value(numerator: usize, denominator: usize) -> String {
    let (numerator, denominator) = reduced_fraction(numerator as i64, denominator as i64);
    format!("{numerator}/{denominator} {}", real(numerator as f64 / denominator as f64))
}
pub fn number_list(numbers: &[usize]) -> String { if numbers.is_empty() { "none".to_owned() } else { let mut values = numbers.to_vec(); values.sort_unstable(); values.iter().map(usize::to_string).collect::<Vec<_>>().join(" ") } }
pub fn bin_number(value: f64, low: f64, high: f64, bins: usize) -> usize { ((bins as f64 * (value - low) / (high - low)).floor() as usize).min(bins - 1) }
pub fn bar(count: usize, top: usize) -> String { "#".repeat((40 * count).div_ceil(top)) }
pub fn write_lines(path: &str, lines: &[String]) -> io::Result<()> { fs::write(path, lines.join("\n") + "\n") }
