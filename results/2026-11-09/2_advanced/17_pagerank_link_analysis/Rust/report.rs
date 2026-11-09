use std::{fs, io};

pub fn fixed(value: f64, places: usize) -> String {
    let text = format!("{value:.places$}");
    if text.starts_with('-') && text.parse::<f64>().unwrap() == 0.0 { text[1..].to_owned() } else { text }
}

pub fn scaled(value: f64, places: u32) -> i64 { (value * 10i64.pow(places) as f64).round() as i64 }

fn gcd(mut first: i64, mut second: i64) -> i64 {
    while second != 0 { let remainder = first % second; first = second; second = remainder; }
    first
}

pub fn fraction(numerator: i64, denominator: i64) -> String {
    let divisor = gcd(numerator.abs(), denominator);
    let numerator = numerator / divisor;
    let denominator = denominator / divisor;
    format!("{numerator}/{denominator} {}", fixed(numerator as f64 / denominator as f64, 4))
}

pub fn write_lines(path: &str, lines: &[String]) -> io::Result<()> {
    fs::write(path, lines.join("\n") + "\n")
}
