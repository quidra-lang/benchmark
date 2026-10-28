use std::collections::BTreeMap;
use std::fs;

#[derive(Clone)]
pub struct Point {
    pub x: i64,
    pub y: i64,
}

pub struct Series {
    pub name: String,
    pub points: Vec<Point>,
}

pub struct Input {
    pub series: Vec<Series>,
    pub tests: Vec<(String, i64)>,
    pub params: BTreeMap<String, Vec<String>>,
}

pub fn hundredths(text: &str) -> i64 {
    text.replace('.', "").parse().unwrap()
}

pub fn read() -> Input {
    let mut series: Vec<Series> = Vec::new();
    for line in fs::read_to_string("input/series.csv").unwrap().lines().skip(1) {
        let fields: Vec<_> = line.split(',').collect();
        let index = series.iter().position(|s| s.name == fields[0]).unwrap_or_else(|| {
            series.push(Series { name: fields[0].into(), points: Vec::new() });
            series.len() - 1
        });
        series[index].points.push(Point { x: hundredths(fields[1]), y: hundredths(fields[2]) });
    }
    for series in &mut series { series.points.sort_by_key(|p| p.x); }
    let tests = fs::read_to_string("input/test_points.csv").unwrap().lines().skip(1).map(|line| {
        let (name, x) = line.split_once(',').unwrap();
        (name.into(), hundredths(x))
    }).collect();
    let params = fs::read_to_string("input/params.txt").unwrap().lines().map(|line| {
        let mut parts = line.split_whitespace();
        (parts.next().unwrap().into(), parts.map(String::from).collect())
    }).collect();
    Input { series, tests, params }
}
