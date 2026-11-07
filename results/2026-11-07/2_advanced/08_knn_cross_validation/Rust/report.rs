use std::fs;

pub fn fixed(value: f64, places: usize) -> String {
    let text = format!("{value:.places$}");
    if text.starts_with('-') && text.parse::<f64>().unwrap() == 0.0 { text[1..].to_owned() } else { text }
}
pub fn four_decimal(value: f64) -> f64 { fixed(value, 4).parse().unwrap() }
pub fn ratio(numerator: usize, denominator: usize) -> String { format!("{numerator}/{denominator} {}", fixed(numerator as f64 / denominator as f64, 4)) }
pub fn fraction(numerator: usize, denominator: usize) -> String {
    if denominator == 0 { return "- -".to_owned(); }
    let mut a = numerator; let mut b = denominator; while b != 0 { let next = a % b; a = b; b = next; }
    format!("{}/{} {}", numerator / a, denominator / a, fixed(numerator as f64 / denominator as f64, 4))
}
pub fn join_parts(parts: Vec<Vec<String>>) -> Vec<String> {
    let mut lines = Vec::new(); for part in parts { if !lines.is_empty() { lines.push(String::new()); } lines.extend(part); } lines
}
pub fn write_lines(name: &str, lines: Vec<String>) { fs::write(format!("output/{name}"), lines.join("\n") + "\n").unwrap(); }
