use std::{fs, io};

pub fn fraction(mut a: i64, mut b: i64) -> String {
    let (n, d) = (a, b);
    while b != 0 {
        let remainder = a % b;
        a = b;
        b = remainder;
    }
    format!("{}/{}", n / a, d / a)
}

pub fn ids(values: &[i64]) -> String {
    if values.is_empty() { "-".into() } else { values.iter().map(ToString::to_string).collect::<Vec<_>>().join(" ") }
}

pub fn write(name: &str, lines: &[String]) -> io::Result<()> {
    fs::create_dir_all("output")?;
    fs::write(format!("output/{}", name), lines.join("\n") + "\n")
}
