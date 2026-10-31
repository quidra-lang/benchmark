use std::fs;
use crate::network::Network;

#[derive(Clone)]
pub struct Image {
    pub id: String,
    pub label: usize,
    pub pixels: Vec<u8>,
    pub input: Vec<f64>,
}

pub struct Run {
    pub name: String,
    pub network: String,
    pub optimizer: String,
    pub eta: f64,
    pub decay: f64,
    pub arguments: Vec<f64>,
}

pub struct Settings {
    pub seed: i64,
    pub batch: usize,
    pub epochs: usize,
    pub patience: usize,
    pub step: usize,
    pub gamma: f64,
    pub stride: usize,
    pub bins: usize,
    pub prune: Vec<usize>,
    pub noise: Vec<usize>,
    pub runs: Vec<Run>,
}

pub struct Generator { pub state: i64 }
impl Generator {
    pub fn next(&mut self) -> i64 { self.state = self.state*48271%2147483647; self.state }
    pub fn shuffle(&mut self, order: &mut [usize]) {
        for i in (1..order.len()).rev() { let j = self.next() as usize%(i+1); order.swap(i, j); }
    }
}

pub fn images(file: &str) -> Vec<Image> {
    fs::read_to_string(file).unwrap().lines().skip(1).map(|line| {
        let w: Vec<_> = line.split(',').collect();
        Image { id: w[0].to_owned(), label: w[1].parse().unwrap(), pixels: w[2].bytes().collect(),
            input: w[2].bytes().map(|b| if b == b'1' { 1.0 } else { 0.0 }).collect() }
    }).collect()
}

pub fn networks() -> (usize, usize, Vec<Network>) {
    let input = fs::read_to_string("input/network.txt").unwrap();
    let mut lines = input.lines();
    let first: Vec<_> = lines.next().unwrap().split_whitespace().collect();
    let (width, height) = (first[1].parse::<usize>().unwrap(), first[2].parse::<usize>().unwrap());
    let mut networks = Vec::<Network>::new();
    for line in lines.filter(|l| !l.is_empty()) {
        let w: Vec<_> = line.split_whitespace().collect();
        if w[0] == "NETWORK" { networks.push(Network::new(w[1].to_owned())); }
        else {
            let net = networks.last_mut().unwrap();
            let inputs = net.layers.last().map_or(width*height, |l| l.units);
            net.add_layer(inputs, w[1].parse().unwrap(), w[2].to_owned());
        }
    }
    let mut current = 0;
    for line in fs::read_to_string("input/weights.txt").unwrap().lines().filter(|l| !l.is_empty()) {
        let w: Vec<_> = line.split_whitespace().collect();
        if w[0] == "NETWORK" { current = networks.iter().position(|n| n.name == w[1]).unwrap(); }
        else if w[0] == "W" || w[0] == "B" { networks[current].initial.extend(w[1..].iter().map(|v| v.parse::<f64>().unwrap())); }
    }
    (width, height, networks)
}

pub fn settings() -> Settings {
    let mut p = Settings { seed: 0, batch: 0, epochs: 0, patience: 0, step: 0, gamma: 0.0,
        stride: 0, bins: 0, prune: Vec::new(), noise: Vec::new(), runs: Vec::new() };
    for line in fs::read_to_string("input/params.txt").unwrap().lines() {
        let w: Vec<_> = line.split_whitespace().collect();
        match w[0] {
            "SEED" => p.seed = w[1].parse().unwrap(), "BATCH_SIZE" => p.batch = w[1].parse().unwrap(),
            "MAX_EPOCHS" => p.epochs = w[1].parse().unwrap(), "PATIENCE" => p.patience = w[1].parse().unwrap(),
            "LR_STEP" => { p.step = w[1].parse().unwrap(); p.gamma = w[2].parse().unwrap(); }
            "GRADIENT_CHECK_STRIDE" => p.stride = w[1].parse().unwrap(), "CALIBRATION_BINS" => p.bins = w[1].parse().unwrap(),
            "PRUNE" => p.prune = w[1..].iter().map(|v| v.parse().unwrap()).collect(),
            "NOISE" => p.noise = w[1..].iter().map(|v| v.parse().unwrap()).collect(),
            _ => p.runs.push(Run { name: w[1].to_owned(), network: w[2].to_owned(), optimizer: w[3].to_owned(),
                eta: w[4].parse().unwrap(), decay: w[5].parse().unwrap(), arguments: w[6..].iter().map(|v| v.parse().unwrap()).collect() }),
        }
    }
    p
}
