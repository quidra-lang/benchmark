use std::{fs, io};

pub fn real(value: f64) -> String {
    let text = format!("{:.4}", value);
    if text == "-0.0000" { "0.0000".into() } else { text }
}

pub fn shade_line(frequency: f64, values: &[Vec<f64>], bin: usize, maximum: f64, band: i64) -> String {
    let characters: Vec<char> = " .:-=+*#%@".chars().collect();
    let shades: String = values.iter().map(|frame| {
        let d = 20.0 * (frame[bin] / maximum).log10();
        let level = (9 - (-d / band as f64).floor() as i64).max(0).min(9);
        characters[level as usize]
    }).collect();
    format!("{:>9} |{}|", real(frequency), shades)
}

pub fn write(name: &str, lines: &[String]) -> io::Result<()> {
    fs::create_dir_all("output")?;
    fs::write(format!("output/{}", name), lines.join("\n") + "\n")
}
