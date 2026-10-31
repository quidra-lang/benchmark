use std::fs;

pub struct Group { pub name: String, pub population: i64, pub fatality: f64 }
pub struct ContactChange { pub name: String, pub group: String, pub factor: f64 }
pub struct Settings {
    pub sigma: f64, pub gamma: f64, pub e0: f64, pub i0: f64,
    pub beta: (f64, f64, usize), pub rho: (f64, f64, usize),
    pub golden: usize, pub rounds: usize, pub simplex: [f64; 2],
    pub nm: [f64; 4], pub iterations: usize, pub holdout: usize,
    pub effect: f64, pub outlier: f64, pub lag: usize,
    pub milestones: Vec<i64>, pub generation: usize, pub horizon: usize, pub threshold: f64,
    pub scenarios: Vec<(String, f64)>, pub changes: Vec<ContactChange>,
}

pub struct Data {
    pub cases: Vec<i64>, pub deaths: Vec<i64>, pub groups: Vec<Group>,
    pub contacts: Vec<Vec<f64>>, pub interventions: Vec<(usize, f64)>, pub params: Settings,
}

pub fn read() -> Data {
    let mut cases = Vec::new();
    let mut deaths = Vec::new();
    for line in fs::read_to_string("input/cases.csv").unwrap().lines().skip(1) {
        let w: Vec<_> = line.split(',').collect();
        cases.push(w[1].parse().unwrap()); deaths.push(w[2].parse().unwrap());
    }
    let mut groups = Vec::new();
    let mut contacts = Vec::new();
    for line in fs::read_to_string("input/population.txt").unwrap().lines() {
        let w: Vec<_> = line.split_whitespace().collect();
        if w[0] == "group" { groups.push(Group { name: w[1].to_owned(), population: w[2].parse().unwrap(), fatality: w[3].parse().unwrap() }); }
        else { contacts.push(w[1..].iter().map(|v| v.parse().unwrap()).collect()); }
    }
    let interventions = fs::read_to_string("input/interventions.txt").unwrap().lines().map(|line| {
        let w: Vec<_> = line.split_whitespace().collect(); (w[0].parse().unwrap(), w[1].parse().unwrap())
    }).collect();
    let mut p = Settings { sigma: 0.0, gamma: 0.0, e0: 0.0, i0: 0.0, beta: (0.0, 0.0, 0), rho: (0.0, 0.0, 0),
        golden: 0, rounds: 0, simplex: [0.0; 2], nm: [0.0; 4], iterations: 0, holdout: 0, effect: 0.0, outlier: 0.0, lag: 0,
        milestones: Vec::new(), generation: 0, horizon: 0, threshold: 0.0, scenarios: Vec::new(), changes: Vec::new() };
    for line in fs::read_to_string("input/params.txt").unwrap().lines() {
        let w: Vec<_> = line.split_whitespace().collect();
        match w[0] {
            "sigma" => p.sigma = w[1].parse().unwrap(), "gamma" => p.gamma = w[1].parse().unwrap(),
            "initial" => { p.e0 = w[1].parse().unwrap(); p.i0 = w[2].parse().unwrap(); }
            "beta_grid" => p.beta = (w[1].parse().unwrap(), w[2].parse().unwrap(), w[3].parse().unwrap()),
            "rho_grid" => p.rho = (w[1].parse().unwrap(), w[2].parse().unwrap(), w[3].parse().unwrap()),
            "golden" => { p.golden = w[1].parse().unwrap(); p.rounds = w[2].parse().unwrap(); }
            "simplex" => p.simplex = [w[1].parse().unwrap(), w[2].parse().unwrap()],
            "nelder_mead" => { for i in 0..4 { p.nm[i] = w[i+1].parse().unwrap(); } p.iterations = w[5].parse().unwrap(); }
            "holdout" => p.holdout = w[1].parse().unwrap(), "effect_width" => p.effect = w[1].parse().unwrap(),
            "outlier" => p.outlier = w[1].parse().unwrap(), "death_lag" => p.lag = w[1].parse().unwrap(),
            "milestones" => p.milestones = w[1..].iter().map(|v| v.parse().unwrap()).collect(),
            "generation" => p.generation = w[1].parse().unwrap(), "horizon" => p.horizon = w[1].parse().unwrap(),
            "threshold" => p.threshold = w[1].parse().unwrap(),
            "scenario" => p.scenarios.push((w[1].to_owned(), w[2].parse().unwrap())),
            _ => p.changes.push(ContactChange { name: w[1].to_owned(), group: w[2].to_owned(), factor: w[3].parse().unwrap() }),
        }
    }
    Data { cases, deaths, groups, contacts, interventions, params: p }
}

pub fn write(name: &str, lines: &[String]) {
    fs::create_dir_all("output").unwrap();
    fs::write(format!("output/{}", name), lines.join("\n")+"\n").unwrap();
}
