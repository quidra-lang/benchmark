use std::{collections::BTreeMap, fs, rc::Rc};

pub struct Row {
    pub id: String,
    pub values: Vec<f64>,
    pub label: Option<String>,
    pub target: Option<f64>,
}
pub type Rows = Vec<Rc<Row>>;

pub struct Settings {
    pub scalings: Vec<String>,
    pub k_values: Vec<usize>,
    pub metrics: Vec<String>,
    pub weightings: Vec<String>,
    pub folds: usize,
    pub edit_k: usize,
    pub curve: Vec<usize>,
    pub bins: Vec<f64>,
    pub top: usize,
}
impl Settings {
    pub fn read() -> Self {
        let text = fs::read_to_string("input/params.txt").unwrap();
        let entries: BTreeMap<&str, Vec<&str>> = text.lines().map(|line| {
            let mut parts = line.split(' '); (parts.next().unwrap(), parts.collect())
        }).collect();
        let strings = |key: &str| -> Vec<String> { entries[key].iter().map(|value| (*value).to_owned()).collect() };
        let integers = |key: &str| -> Vec<usize> { entries[key].iter().map(|value| value.parse().unwrap()).collect() };
        Self {
            scalings: strings("SCALINGS"), k_values: integers("K_VALUES"), metrics: strings("METRICS"), weightings: strings("WEIGHTINGS"),
            folds: entries["FOLDS"][0].parse().unwrap(), edit_k: entries["EDIT_K"][0].parse().unwrap(), curve: integers("CURVE"),
            bins: entries["BINS"].iter().map(|value| value.parse().unwrap()).collect(), top: entries["TOP"][0].parse().unwrap(),
        }
    }
}
pub fn read_rows(name: &str) -> (Vec<String>, Rows) {
    let text = fs::read_to_string(format!("input/{name}")).unwrap();
    let mut lines = text.lines(); let header: Vec<&str> = lines.next().unwrap().split(',').collect();
    let rows = lines.map(|line| {
        let parts: Vec<&str> = line.split(',').collect(); let size = parts.len();
        Rc::new(Row {
            id: parts[0].to_owned(), values: parts[1..size - 2].iter().map(|value| value.parse().unwrap()).collect(),
            label: (!parts[size - 2].is_empty()).then(|| parts[size - 2].to_owned()),
            target: (!parts[size - 1].is_empty()).then(|| parts[size - 1].parse().unwrap()),
        })
    }).collect();
    (header[1..header.len() - 2].iter().map(|name| (*name).to_owned()).collect(), rows)
}
