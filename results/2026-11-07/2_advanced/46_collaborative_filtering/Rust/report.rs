use std::{fs, io};

pub fn real(value: f64) -> String {
    let text = format!("{:.4}", value);
    if text == "-0.0000" { "0.0000".into() } else { text }
}

pub fn optional(value: Option<f64>) -> String {
    value.map_or("-".into(), real)
}

pub fn write(name: &str, lines: &[String]) -> io::Result<()> {
    fs::create_dir_all("output")?;
    fs::write(format!("output/{}", name), lines.join("\n") + "\n")
}
