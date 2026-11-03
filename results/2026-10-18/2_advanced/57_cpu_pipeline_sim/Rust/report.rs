use std::{fs, io};

pub fn decimal(p: usize, q: usize) -> String {
    if q == 0 { return "-".into(); }
    let units = (2 * p * 10000 + q) / (2 * q);
    format!("{}.{:04}", units / 10000, units % 10000)
}

pub fn percentage(p: usize, q: usize) -> String {
    if q == 0 { return "-".into(); }
    let units = (2 * p * 10000 + q) / (2 * q);
    format!("{}.{:02}", units / 100, units % 100)
}

pub fn fraction(p: usize, q: usize) -> String {
    let (mut a, mut b) = (p, q);
    while b != 0 { let remainder = a % b; a = b; b = remainder; }
    format!("{}/{}", p / a, q / a)
}

pub fn hex(value: i64) -> String {
    format!("{:08x}", value)
}

pub struct Span {
    pub start: usize,
    pub end: usize,
    pub first: char,
    pub rest: char,
    pub stage: Option<usize>,
}

pub struct Row {
    pub instruction: Option<usize>,
    pub pc: i64,
    pub class: String,
    pub spans: Vec<Span>,
    pub annotation: String,
}

impl Row {
    pub fn cell(&self, cycle: usize) -> (char, Option<usize>) {
        for span in &self.spans {
            if cycle >= span.start && cycle <= span.end { return (if cycle == span.start { span.first } else { span.rest }, span.stage); }
        }
        ('.', None)
    }

    pub fn format(&self, start: usize, end: usize) -> Option<String> {
        let cells: String = (start..=end).map(|c| self.cell(c).0).collect();
        if cells.chars().all(|c| c == '.') { return None; }
        let number = self.instruction.map_or("-".into(), |i| (i + 1).to_string());
        Some(format!("{:>6} {} {:<6} {}{}", number, hex(self.pc), self.class, cells, self.annotation))
    }
}

pub fn digits(start: usize, end: usize) -> String {
    format!("cycle{}{}", " ".repeat(18), (start..=end).map(|c| (b'0' + (c % 10) as u8) as char).collect::<String>())
}

pub fn write(name: &str, lines: &[String]) -> io::Result<()> {
    fs::create_dir_all("output")?;
    fs::write(format!("output/{}", name), lines.join("\n") + "\n")
}
