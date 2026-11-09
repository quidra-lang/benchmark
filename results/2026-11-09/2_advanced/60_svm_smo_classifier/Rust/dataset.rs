use std::fs;
use crate::kernels::{Kernel, Kind};

#[derive(Clone)]
pub struct Example { pub id: String, pub point: [f64; 2], pub label: i32 }

pub struct Settings {
    pub candidates: Vec<f64>,
    pub kernels: Vec<Kernel>,
    pub tolerance: f64,
    pub eps: f64,
    pub max_passes: usize,
    pub folds: usize,
    pub fractions: Vec<usize>,
    pub newton: usize,
    pub multi_kernel: String,
    pub multi_c: f64,
    pub lambda: f64,
    pub iterations: usize,
    pub seed: i64,
    pub x: [f64; 2],
    pub y: [f64; 2],
    pub width: usize,
    pub height: usize,
}

pub fn binary(file: &str) -> Vec<Example> {
    fs::read_to_string(file).unwrap().lines().skip(1).map(|line| {
        let w: Vec<_> = line.split(',').collect();
        Example { id: w[0].to_owned(), point: [w[1].parse().unwrap(), w[2].parse().unwrap()], label: w[3].parse().unwrap() }
    }).collect()
}

pub fn multiclass() -> (Vec<Example>, Vec<Example>) {
    let (mut train, mut test) = (Vec::new(), Vec::new());
    for line in fs::read_to_string("input/multiclass.csv").unwrap().lines().skip(1) {
        let w: Vec<_> = line.split(',').collect();
        let e = Example { id: w[0].to_owned(), point: [w[1].parse().unwrap(), w[2].parse().unwrap()], label: w[3].parse().unwrap() };
        if w[4] == "train" { train.push(e); } else { test.push(e); }
    }
    (train, test)
}

pub fn settings() -> Settings {
    let mut p = Settings { candidates: Vec::new(), kernels: Vec::new(), tolerance: 0.0, eps: 0.0,
        max_passes: 0, folds: 0, fractions: Vec::new(), newton: 0, multi_kernel: String::new(), multi_c: 0.0,
        lambda: 0.0, iterations: 0, seed: 0, x: [0.0; 2], y: [0.0; 2], width: 0, height: 0 };
    for line in fs::read_to_string("input/params.txt").unwrap().lines() {
        let w: Vec<_> = line.split_whitespace().collect();
        match w[0] {
            "C_GRID" => p.candidates = w[1..].iter().map(|v| v.parse().unwrap()).collect(),
            "KERNEL" => p.kernels.push(Kernel { name: w[1].to_owned(), kind: match w[2] {
                "linear" => Kind::Linear,
                "poly" => Kind::Polynomial { degree: w[3].parse().unwrap(), gamma: w[4].parse().unwrap(), constant: w[5].parse().unwrap() },
                _ => Kind::Rbf(w[3].parse().unwrap()),
            } }),
            "TOLERANCE" => p.tolerance = w[1].parse().unwrap(),
            "EPS" => p.eps = w[1].parse().unwrap(),
            "MAX_PASSES" => p.max_passes = w[1].parse().unwrap(),
            "FOLDS" => p.folds = w[1].parse().unwrap(),
            "LEARNING_CURVE" => p.fractions = w[1..].iter().map(|v| v.parse().unwrap()).collect(),
            "NEWTON_ITERATIONS" => p.newton = w[1].parse().unwrap(),
            "MULTICLASS" => { p.multi_kernel = w[1].to_owned(); p.multi_c = w[2].parse().unwrap(); }
            "PEGASOS" => { p.lambda = w[1].parse().unwrap(); p.iterations = w[2].parse().unwrap(); p.seed = w[3].parse().unwrap(); }
            "PLOT_X" => p.x = [w[1].parse().unwrap(), w[2].parse().unwrap()],
            "PLOT_Y" => p.y = [w[1].parse().unwrap(), w[2].parse().unwrap()],
            _ => { p.width = w[1].parse().unwrap(); p.height = w[2].parse().unwrap(); }
        }
    }
    p
}
