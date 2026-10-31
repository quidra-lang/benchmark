use std::collections::BTreeMap;
use std::fs;

pub struct Annotation {
    pub sample: usize,
    pub label: u8,
}

pub struct Input {
    pub ecg: Vec<i64>,
    pub annotations: Vec<Annotation>,
    pub params: BTreeMap<String, i64>,
}

pub fn read() -> Input {
    let ecg = fs::read_to_string("input/ecg.csv").unwrap().lines().skip(1).map(|line| line.split_once(',').unwrap().1.parse().unwrap()).collect();
    let annotations = fs::read_to_string("input/annotations.csv").unwrap().lines().skip(1).map(|line| {
        let (sample, label) = line.split_once(',').unwrap();
        Annotation { sample: sample.parse().unwrap(), label: label.as_bytes()[0] }
    }).collect();
    let params = fs::read_to_string("input/params.txt").unwrap().lines().map(|line| {
        let (key, value) = line.split_once(' ').unwrap();
        (key.into(), value.parse().unwrap())
    }).collect();
    Input { ecg, annotations, params }
}

pub fn write(name: &str, lines: &[String]) {
    fs::write(format!("output/{name}"), if lines.is_empty() { String::new() } else { format!("{}\n", lines.join("\n")) }).unwrap();
}
