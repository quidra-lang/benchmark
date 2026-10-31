use std::{fs, io};

pub fn fraction(a: i64, b: i64) -> String {
    let (mut x, mut y) = (a.abs(), b);
    while y != 0 {
        let r = x % y;
        x = y;
        y = r;
    }
    format!("{}/{}", a / x, b / x)
}

pub fn root(value: i64) -> String { format!("{:.3}", (value as f64).sqrt()) }

pub fn ari(a: i64, b: i64) -> String {
    let value = format!("{:.4}", a as f64 / b as f64);
    format!("{} {}", fraction(a, b), if value == "-0.0000" { "0.0000" } else { &value })
}

pub fn framed(rows: Vec<String>, width: usize) -> Vec<String> {
    let border = format!("+{}+", "-".repeat(width));
    let mut lines = vec![border.clone()];
    lines.extend(rows.into_iter().map(|row| format!("|{row}|")));
    lines.push(border);
    lines
}

pub fn write_lines(name: &str, lines: Vec<String>) -> io::Result<()> {
    fs::create_dir_all("output")?;
    fs::write(format!("output/{name}"), if lines.is_empty() { String::new() } else { lines.join("\n") + "\n" })
}
