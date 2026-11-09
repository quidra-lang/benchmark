use std::{fs, io};

pub fn fixed(value: f64, decimals: usize) -> String {
    let s = format!("{:.*}", decimals, value);
    if s.starts_with('-') && s[1..].chars().all(|c| c == '0' || c == '.') { s[1..].into() } else { s }
}

pub fn real(value: f64) -> String {
    fixed(value, 4)
}

pub fn optional(value: Option<f64>) -> String {
    value.map_or("-".into(), real)
}

pub fn rounded(value: f64) -> i64 {
    (value * 10000.0).round() as i64
}

pub fn frame(grid: &[Vec<char>]) -> Vec<String> {
    let border = format!("+{}+", "-".repeat(grid[0].len()));
    let mut lines = vec![border.clone()];
    lines.extend(grid.iter().map(|r| format!("|{}|", r.iter().collect::<String>())));
    lines.push(border);
    lines
}

pub fn write(name: &str, lines: &[String]) -> io::Result<()> {
    fs::create_dir_all("output")?;
    fs::write(format!("output/{}", name), lines.join("\n") + "\n")
}
