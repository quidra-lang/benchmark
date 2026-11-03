use std::collections::BTreeMap;
use std::fs;

pub struct Series {
    pub name: String,
    pub periods: Vec<String>,
    pub raw: Vec<Option<i64>>,
    pub events: BTreeMap<String, String>,
    pub inventory: Inventory,
}

#[derive(Default)]
pub struct Inventory {
    pub on_hand: i64,
    pub lead_time: usize,
    pub review: usize,
    pub service: f64,
}

pub struct Settings {
    pub season: usize,
    pub holdout: usize,
    pub horizon: usize,
    pub cv_start: usize,
    pub combo: usize,
    pub alpha: Vec<f64>,
    pub beta: Vec<f64>,
    pub gamma: Vec<f64>,
    pub phi: Vec<f64>,
    pub max_ar: usize,
    pub max_lag: usize,
    pub ljung_box: Vec<usize>,
    pub outlier: f64,
    pub interval: Vec<f64>,
}

pub fn read_inputs() -> (Vec<Series>, Settings) {
    let mut series: Vec<Series> = Vec::new();
    let content = fs::read_to_string("input/series.csv").unwrap();
    for line in content.lines().skip(1) {
        let row: Vec<&str> = line.split(',').collect();
        if series.last().map(|s| s.name.as_str()) != Some(row[0]) {
            series.push(Series {
                name: row[0].to_owned(),
                periods: Vec::new(),
                raw: Vec::new(),
                events: BTreeMap::new(),
                inventory: Inventory::default(),
            });
        }
        let record = series.last_mut().unwrap();
        record.periods.push(row[1].to_owned());
        record.raw.push(if row[2] == "NA" { None } else { Some(row[2].parse().unwrap()) });
    }
    let content = fs::read_to_string("input/events.csv").unwrap();
    for line in content.lines().skip(1) {
        let row: Vec<&str> = line.split(',').collect();
        let record = series.iter_mut().find(|s| s.name == row[0]).unwrap();
        record.events.insert(row[1].to_owned(), row[2].to_owned());
    }
    let content = fs::read_to_string("input/inventory.csv").unwrap();
    for line in content.lines().skip(1) {
        let row: Vec<&str> = line.split(',').collect();
        let record = series.iter_mut().find(|s| s.name == row[0]).unwrap();
        record.inventory = Inventory {
            on_hand: row[1].parse().unwrap(),
            lead_time: row[2].parse().unwrap(),
            review: row[3].parse().unwrap(),
            service: row[4].parse().unwrap(),
        };
    }
    let content = fs::read_to_string("input/params.txt").unwrap();
    let rows: Vec<Vec<&str>> = content.lines().map(|line| line.split(' ').skip(1).collect()).collect();
    let integer = |i: usize| rows[i][0].parse::<usize>().unwrap();
    let reals = |i: usize| rows[i].iter().map(|s| s.parse::<f64>().unwrap()).collect();
    let settings = Settings {
        season: integer(0), holdout: integer(1), horizon: integer(2),
        cv_start: integer(3), combo: integer(4), alpha: reals(5), beta: reals(6),
        gamma: reals(7), phi: reals(8), max_ar: integer(9), max_lag: integer(10),
        ljung_box: rows[11].iter().map(|s| s.parse().unwrap()).collect(),
        outlier: rows[12][0].parse().unwrap(), interval: reals(13),
    };
    (series, settings)
}

pub fn next_month(period: &str) -> String {
    let mut year: usize = period[..4].parse().unwrap();
    let mut month: usize = period[5..].parse().unwrap();
    year += month / 12;
    month = month % 12 + 1;
    format!("{year:04}-{month:02}")
}

pub fn real(value: f64) -> String {
    let result = format!("{value:.4}");
    if result == "-0.0000" { "0.0000".to_owned() } else { result }
}

pub fn optional_real(value: Option<f64>) -> String {
    value.map(real).unwrap_or_else(|| "NA".to_owned())
}

pub fn write_lines(name: &str, lines: &[String]) {
    fs::create_dir_all("output").unwrap();
    fs::write(format!("output/{name}"), lines.join("\n") + "\n").unwrap();
}
