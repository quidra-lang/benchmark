use std::fs;
use std::io;
use crate::agglomerative::Linkage;
use crate::distances::DistanceKind;

pub struct Observation {
    pub id: String,
    pub label: String,
    pub values: Vec<f64>,
}

pub struct Settings {
    pub distance: DistanceKind,
    pub standardize: bool,
    pub linkages: Vec<Linkage>,
    pub cut_heights: Vec<f64>,
    pub cut_counts: Vec<usize>,
    pub inconsistency_depth: usize,
    pub inconsistency_depth_text: String,
    pub inconsistency_count: usize,
    pub gap_max_k: usize,
    pub list_size: usize,
    pub width: usize,
    pub compare_linkage: Linkage,
    pub replicates: usize,
    pub percent: usize,
    pub seed: i64,
    pub refine_iterations: usize,
}

pub fn read_observations() -> io::Result<(Vec<String>, Vec<Observation>)> {
    let text = fs::read_to_string("input/data.csv")?;
    let mut lines = text.lines();
    let features = lines.next().unwrap().split(',').skip(2).map(str::to_owned).collect();
    let observations = lines.map(|line| {
        let mut fields = line.split(',');
        Observation {
            id: fields.next().unwrap().to_owned(),
            label: fields.next().unwrap().to_owned(),
            values: fields.map(|value| value.parse().unwrap()).collect(),
        }
    }).collect();
    Ok((features, observations))
}

pub fn read_settings() -> io::Result<Settings> {
    let text = fs::read_to_string("input/params.txt")?;
    let rows: Vec<Vec<&str>> = text.lines().map(|line| line.split(' ').skip(1).collect()).collect();
    Ok(Settings {
        distance: DistanceKind::parse(rows[0][0]),
        standardize: rows[1][0] == "yes",
        linkages: rows[2].iter().map(|value| Linkage::parse(value)).collect(),
        cut_heights: rows[3].iter().map(|value| value.parse().unwrap()).collect(),
        cut_counts: rows[4].iter().map(|value| value.parse().unwrap()).collect(),
        inconsistency_depth: rows[5][0].bytes().fold(0usize, |value, digit| (value * 10 + (digit - b'0') as usize).min(120)),
        inconsistency_depth_text: rows[5][0].to_owned(),
        inconsistency_count: rows[5][1].parse().unwrap(),
        gap_max_k: rows[6][0].parse().unwrap(),
        list_size: rows[7][0].parse().unwrap(),
        width: rows[8][0].parse().unwrap(),
        compare_linkage: Linkage::parse(rows[9][0]),
        replicates: rows[10][0].parse().unwrap(),
        percent: rows[10][1].parse().unwrap(),
        seed: rows[10][2].parse().unwrap(),
        refine_iterations: rows[11][0].parse().unwrap(),
    })
}

pub fn write_lines(name: &str, lines: &[String]) -> io::Result<()> {
    let text = if lines.is_empty() { String::new() } else { lines.join("\n") + "\n" };
    fs::write(format!("output/{name}"), text)
}
