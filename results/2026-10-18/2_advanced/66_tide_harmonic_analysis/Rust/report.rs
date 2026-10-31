use std::fs;

pub fn real(value: f64, digits: usize) -> String {
    let s = format!("{:.*}", digits, value);
    if s.starts_with('-') && s[1..].bytes().all(|b| b == b'0' || b == b'.') { s[1..].to_owned() } else { s }
}

pub fn plot(cells: &[Vec<u8>], top: i64, step: i64) -> Vec<String> {
    let labels: Vec<_> = (0..cells.len()).map(|q| real((top-q as i64*step) as f64/100.0, 2)).collect();
    let width = labels.iter().map(String::len).max().unwrap();
    let mut lines: Vec<_> = cells.iter().enumerate().map(|(q, row)| format!("{:>width$} |{}|", labels[q], String::from_utf8(row.clone()).unwrap(), width=width)).collect();
    lines.push(format!("{} +{}+", " ".repeat(width), (0..cells[0].len()).map(|c| if c%6 == 0 { '+' } else { '-' }).collect::<String>()));
    lines
}

pub fn write(file: &str, lines: &[String]) {
    fs::create_dir_all("output").unwrap();
    fs::write(format!("output/{}", file), lines.join("\n")+"\n").unwrap();
}
