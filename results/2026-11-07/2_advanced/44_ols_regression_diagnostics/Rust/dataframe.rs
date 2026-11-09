use std::collections::BTreeMap;
use std::fs;

#[derive(Clone)]
pub enum Value {
    Number(f64),
    Label(String),
    Missing,
}

impl Value {
    pub fn number(&self) -> Option<f64> { if let Self::Number(value) = self { Some(*value) } else { None } }
    pub fn label(&self) -> Option<&str> { if let Self::Label(value) = self { Some(value) } else { None } }
    pub fn missing(&self) -> bool { matches!(self, Self::Missing) }
}

pub struct Input {
    pub names: Vec<String>,
    pub categorical: Vec<bool>,
    pub rows: Vec<Vec<Value>>,
    pub prediction_rows: Vec<Vec<Value>>,
    pub model_lines: Vec<String>,
    pub params: BTreeMap<String, Vec<String>>,
}

impl Input {
    pub fn number(&self, name: &str) -> f64 { self.params[name][0].parse().unwrap() }
}

fn parse(value: &str, categorical: bool) -> Value {
    if value == "NA" { Value::Missing } else if categorical { Value::Label(value.into()) } else { Value::Number(value.parse().unwrap()) }
}

pub fn read() -> Input {
    let data = fs::read_to_string("input/data.csv").unwrap();
    let lines: Vec<_> = data.lines().collect();
    let names: Vec<_> = lines[0].split(',').map(String::from).collect();
    let raw: Vec<Vec<_>> = lines[1..].iter().map(|line| line.split(',').collect()).collect();
    let categorical: Vec<_> = (0..names.len()).map(|column| raw.iter().any(|row| row[column] != "NA" && row[column].as_bytes()[0].is_ascii_uppercase())).collect();
    let rows = raw.iter().map(|row| row.iter().enumerate().map(|(i, value)| parse(value, categorical[i])).collect()).collect();
    let prediction_text = fs::read_to_string("input/predict.csv").unwrap();
    let prediction_lines: Vec<_> = prediction_text.lines().collect();
    let columns: Vec<_> = prediction_lines[0].split(',').map(|name| names.iter().position(|column| column == name).unwrap()).collect();
    let prediction_rows = prediction_lines[1..].iter().map(|line| {
        let mut row = vec![Value::Missing; names.len()];
        for (value, &column) in line.split(',').zip(&columns) { row[column] = parse(value, categorical[column]); }
        row
    }).collect();
    let model_lines = fs::read_to_string("input/model.txt").unwrap().lines().map(String::from).collect();
    let params = fs::read_to_string("input/params.txt").unwrap().lines().map(|line| {
        let mut parts = line.split(' ');
        (parts.next().unwrap().into(), parts.map(String::from).collect())
    }).collect();
    Input { names, categorical, rows, prediction_rows, model_lines, params }
}
