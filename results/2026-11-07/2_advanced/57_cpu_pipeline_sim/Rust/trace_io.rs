use std::{fs, io};

pub const CLASSES: [&str; 7] = ["ALU", "MUL", "LOAD", "STORE", "BRANCH", "JUMP", "NOP"];

pub struct Instruction {
    pub pc: i64,
    pub class: usize,
    pub rd: Option<usize>,
    pub rs1: Option<usize>,
    pub rs2: Option<usize>,
    pub taken: bool,
    pub target: Option<i64>,
    pub address: Option<i64>,
    pub line: usize,
}

impl Instruction {
    pub fn control(&self) -> bool {
        self.class == 4 || self.class == 5
    }

    pub fn next(&self) -> i64 {
        if self.taken { self.target.unwrap() } else { self.pc + 4 }
    }

    pub fn call(&self) -> bool {
        self.class == 5 && self.rd == Some(31)
    }

    pub fn returns(&self) -> bool {
        self.class == 5 && self.rd.is_none() && self.rs1 == Some(31)
    }
}

pub struct Predictor {
    pub name: String,
    pub scheme: String,
    pub parameters: Vec<usize>,
}

#[derive(Clone)]
pub struct Variant {
    pub name: String,
    pub forwarding: bool,
    pub id: bool,
    pub multiply: usize,
}

pub struct Config {
    pub btb: usize,
    pub ras: usize,
    pub predictors: Vec<Predictor>,
    pub variants: Vec<Variant>,
    pub primary: (String, String),
    pub window: (usize, usize),
    pub top: usize,
    pub interval: usize,
}

pub fn hex(word: &str) -> Option<i64> {
    if word.len() == 8 && word.bytes().all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c)) { i64::from_str_radix(word, 16).ok() } else { None }
}

pub fn register(word: &str) -> Option<Option<usize>> {
    if word == "-" { return Some(None); }
    let number: usize = word.strip_prefix('r')?.parse().ok()?;
    if number <= 31 && format!("r{}", number) == word { Some(Some(number)) } else { None }
}

pub fn read() -> io::Result<(Vec<String>, Config)> {
    let trace = fs::read_to_string("input/trace.txt")?.lines().map(str::to_owned).collect();
    let mut config = Config { btb: 0, ras: 0, predictors: Vec::new(), variants: Vec::new(), primary: (String::new(), String::new()), window: (0, 0), top: 0, interval: 0 };
    for line in fs::read_to_string("input/config.txt")?.lines() {
        let words: Vec<&str> = line.split_whitespace().collect();
        let integer = |i: usize| words[i].parse::<usize>().unwrap();
        match words[0] {
            "BTB" => config.btb = integer(1),
            "RAS" => config.ras = integer(1),
            "PREDICTOR" => config.predictors.push(Predictor { name: words[1].into(), scheme: words[2].into(), parameters: words[3..].iter().map(|s| s.parse().unwrap()).collect() }),
            "VARIANT" => config.variants.push(Variant { name: words[1].into(), forwarding: words[2] == "ON", id: words[3] == "ID", multiply: integer(4) }),
            "PRIMARY" => config.primary = (words[1].into(), words[2].into()),
            "WINDOW" => config.window = (integer(1), integer(2)),
            "TOP" => config.top = integer(1),
            "INTERVAL" => config.interval = integer(1),
            _ => unreachable!(),
        }
    }
    Ok((trace, config))
}
