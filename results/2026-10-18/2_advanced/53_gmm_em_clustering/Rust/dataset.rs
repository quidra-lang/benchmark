use crate::gaussian::{Component, Point};
use std::{collections::BTreeMap, fs, io};

pub struct Params {
    pub ks: Vec<usize>,
    pub iterations: usize,
    pub types: Vec<String>,
    pub regularization: f64,
    pub tolerance: f64,
    pub kmeans_iterations: usize,
    pub folds: usize,
    pub uncertain: f64,
    pub low_density: f64,
    pub edges: Vec<f64>,
    pub x: (f64, f64),
    pub y: (f64, f64),
    pub size: (usize, usize),
}

pub struct Data {
    pub ids: Vec<String>,
    pub points: Vec<Point>,
    pub initial: BTreeMap<usize, Vec<Component>>,
    pub params: Params,
}

pub fn read() -> io::Result<Data> {
    let content = fs::read_to_string("input/points.csv")?;
    let mut ids = Vec::new();
    let mut points = Vec::new();
    for line in content.lines().skip(1) {
        let v: Vec<&str> = line.split(',').collect();
        ids.push(v[0].into());
        points.push((v[1].parse().unwrap(), v[2].parse().unwrap()));
    }
    let initial_text = fs::read_to_string("input/init.txt")?;
    let mut lines = initial_text.lines().filter(|s| !s.is_empty());
    let mut initial = BTreeMap::new();
    while let Some(line) = lines.next() {
        let k: usize = line.split_whitespace().nth(1).unwrap().parse().unwrap();
        let weights: Vec<f64> = lines.next().unwrap().split_whitespace().skip(1).map(|s| s.parse().unwrap()).collect();
        let mut components = Vec::new();
        for j in 0..k {
            let v: Vec<f64> = lines.next().unwrap().split_whitespace().skip(2).map(|s| s.parse().unwrap()).collect();
            components.push(Component { weight: weights[j], mean: (v[0], v[1]), covariance: [v[2], v[3], v[4]] });
        }
        initial.insert(k, components);
    }
    let text = fs::read_to_string("input/params.txt")?;
    let q: Vec<Vec<&str>> = text.lines().map(|l| l.split_whitespace().skip(1).collect()).collect();
    let params = Params {
        ks: q[0].iter().map(|s| s.parse().unwrap()).collect(), iterations: q[1][0].parse().unwrap(), types: q[2].iter().map(|s| s.to_string()).collect(),
        regularization: q[3][0].parse().unwrap(), tolerance: q[4][0].parse().unwrap(), kmeans_iterations: q[5][0].parse().unwrap(), folds: q[6][0].parse().unwrap(),
        uncertain: q[7][0].parse().unwrap(), low_density: q[8][0].parse().unwrap(), edges: q[9].iter().map(|s| s.parse().unwrap()).collect(),
        x: (q[10][0].parse().unwrap(), q[10][1].parse().unwrap()), y: (q[11][0].parse().unwrap(), q[11][1].parse().unwrap()),
        size: (q[12][0].parse().unwrap(), q[12][1].parse().unwrap()),
    };
    Ok(Data { ids, points, initial, params })
}
