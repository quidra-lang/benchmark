use std::fs;

pub const CONSTANTS: [[f64; 8]; 9] = [
    [1.880,2.659,0.0,3.267,0.0,3.267,1.128,0.7979],
    [1.023,1.954,0.0,2.568,0.0,2.574,1.693,0.8862],
    [0.729,1.628,0.0,2.266,0.0,2.282,2.059,0.9213],
    [0.577,1.427,0.0,2.089,0.0,2.114,2.326,0.9400],
    [0.483,1.287,0.030,1.970,0.0,2.004,2.534,0.9515],
    [0.419,1.182,0.118,1.882,0.076,1.924,2.704,0.9594],
    [0.373,1.099,0.185,1.815,0.136,1.864,2.847,0.9650],
    [0.337,1.032,0.239,1.761,0.184,1.816,2.970,0.9693],
    [0.308,0.975,0.284,1.716,0.223,1.777,3.078,0.9727],
];

#[derive(Default)]
pub struct Settings {
    pub characteristic: String,
    pub lsl: i64,
    pub usl: i64,
    pub target: i64,
    pub size: usize,
    pub phase1: usize,
    pub passes: usize,
    pub rules: [Vec<u8>; 7],
    pub cusum_k: f64,
    pub cusum_h: f64,
    pub lambda: f64,
    pub ewma_l: f64,
    pub span: usize,
    pub gap: usize,
    pub ci_z: f64,
    pub bin: i64,
    pub window: usize,
    pub step: usize,
}

impl Settings {
    pub fn read() -> Self {
        let mut s = Self::default();
        for line in fs::read_to_string("input/spec.txt").unwrap().lines() {
            let f: Vec<&str> = line.split(' ').collect();
            match f[0] {
                "characteristic" => s.characteristic = f[1].into(),
                "lsl" => s.lsl = f[1].parse().unwrap(), "usl" => s.usl = f[1].parse().unwrap(), "target" => s.target = f[1].parse().unwrap(),
                "subgroup_size" => s.size = f[1].parse().unwrap(), "phase1_subgroups" => s.phase1 = f[1].parse().unwrap(), "max_passes" => s.passes = f[1].parse().unwrap(),
                "rules" => {
                    let index = ["XBAR_R","R","XBAR_S","S","I","MR","STD"].iter().position(|&v| v == f[1]).unwrap();
                    s.rules[index] = f[2..].iter().map(|v| v.parse().unwrap()).collect();
                }
                "cusum_k" => s.cusum_k = f[1].parse().unwrap(), "cusum_h" => s.cusum_h = f[1].parse().unwrap(),
                "ewma_lambda" => s.lambda = f[1].parse().unwrap(), "ewma_l" => s.ewma_l = f[1].parse().unwrap(),
                "ma_span" => s.span = f[1].parse().unwrap(), "event_gap" => s.gap = f[1].parse().unwrap(), "ci_z" => s.ci_z = f[1].parse().unwrap(),
                "histogram_bin" => s.bin = f[1].parse().unwrap(), "rolling_window" => s.window = f[1].parse().unwrap(), "rolling_step" => s.step = f[1].parse().unwrap(),
                _ => unreachable!(),
            }
        }
        s
    }
}

pub struct Lot { pub number: usize, pub inspected: i64, pub defectives: i64, pub defects: i64 }

fn rows(name: &str) -> Vec<Vec<i64>> {
    fs::read_to_string(format!("input/{name}")).unwrap().lines().skip(1).map(|line| line.split(',').map(|v| v.parse().unwrap()).collect()).collect()
}

pub fn read_measurements() -> Vec<i64> { rows("measurements.csv").into_iter().map(|r| r[2]).collect() }
pub fn read_attributes() -> Vec<Lot> {
    rows("attributes.csv").into_iter().map(|r| Lot { number: r[0] as usize, inspected: r[1], defectives: r[2], defects: r[3] }).collect()
}
