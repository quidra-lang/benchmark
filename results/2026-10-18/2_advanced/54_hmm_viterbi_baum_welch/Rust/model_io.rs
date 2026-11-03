use std::{fs, io};

#[derive(Clone)]
pub struct Model {
    pub name: String,
    pub initial: Vec<f64>,
    pub transition: Vec<Vec<f64>>,
    pub emission: Vec<Vec<f64>>,
}

pub type Observation = Vec<Option<usize>>;

pub struct RawRecord {
    pub name: String,
    pub role: String,
    pub text: String,
    pub labels: Option<String>,
    pub line: usize,
}

pub struct Input {
    pub model: Model,
    pub states: Vec<char>,
    pub symbols: Vec<char>,
    pub missing: char,
    pub unlabeled: Vec<RawRecord>,
    pub labeled: Vec<RawRecord>,
    pub params: Vec<Vec<String>>,
}

pub fn normalize(values: &mut [f64]) {
    let sum: f64 = values.iter().sum();
    for value in values { *value /= sum; }
}

pub fn read() -> io::Result<Input> {
    let text = fs::read_to_string("input/model.txt")?;
    let q: Vec<Vec<&str>> = text.lines().map(|s| s.split_whitespace().collect()).collect();
    let states: Vec<char> = q[0][1..].iter().map(|s| s.chars().next().unwrap()).collect();
    let symbols = q[1][1..].iter().map(|s| s.chars().next().unwrap()).collect();
    let missing = q[2][1].chars().next().unwrap();
    let k = states.len();
    let row = |values: &[&str]| {
        let mut values: Vec<f64> = values.iter().map(|s| s.parse().unwrap()).collect();
        normalize(&mut values);
        values
    };
    let model = Model { name: "INITIAL".into(), initial: row(&q[3][1..]), transition: (0..k).map(|i| row(&q[4 + i][2..])).collect(),
        emission: (0..k).map(|i| row(&q[4 + k + i][2..])).collect() };
    let unlabeled = fs::read_to_string("input/sequences.txt")?.lines().enumerate().map(|(i, l)| {
        let v: Vec<&str> = l.split_whitespace().collect();
        RawRecord { name: v[0].into(), role: String::new(), text: v[1].into(), labels: None, line: i + 1 }
    }).collect();
    let content = fs::read_to_string("input/labeled.txt")?;
    let lines: Vec<&str> = content.lines().collect();
    let labeled = lines.chunks(2).enumerate().map(|(i, lines)| {
        let v: Vec<&str> = lines[0].split_whitespace().collect();
        RawRecord { name: v[0].into(), role: v[1].into(), text: v[2].into(), labels: Some(lines[1].into()), line: 2 * i + 1 }
    }).collect();
    let params = fs::read_to_string("input/params.txt")?.lines().map(|s| s.split_whitespace().skip(1).map(str::to_owned).collect()).collect();
    Ok(Input { model, states, symbols, missing, unlabeled, labeled, params })
}

pub fn fixed(value: f64, digits: usize) -> String {
    let text = format!("{:.*}", digits, value);
    if text.starts_with('-') && text[1..].chars().all(|c| c == '0' || c == '.') { text[1..].into() } else { text }
}

pub fn real(value: f64) -> String {
    fixed(value, 4)
}

pub fn format(model: &Model, states: &[char], symbols: &[char], missing: char) -> Vec<String> {
    let numbers = |v: &[f64]| v.iter().map(|&x| real(x)).collect::<Vec<_>>().join(" ");
    let mut lines = vec![std::format!("MODEL {}", model.name), std::format!("STATES {}", states.iter().map(ToString::to_string).collect::<Vec<_>>().join(" ")),
        std::format!("SYMBOLS {}", symbols.iter().map(ToString::to_string).collect::<Vec<_>>().join(" ")), std::format!("MISSING {}", missing), std::format!("INITIAL {}", numbers(&model.initial))];
    for i in 0..states.len() { lines.push(std::format!("TRANSITION {} {}", states[i], numbers(&model.transition[i]))); }
    for i in 0..states.len() { lines.push(std::format!("EMISSION {} {}", states[i], numbers(&model.emission[i]))); }
    lines
}

pub fn write(name: &str, lines: &[String]) -> io::Result<()> {
    fs::create_dir_all("output")?;
    fs::write(std::format!("output/{}", name), lines.join("\n") + "\n")
}
