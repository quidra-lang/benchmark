use std::fs;

pub struct Material {
    pub code: u8,
    pub name: String,
    pub k: f64,
    pub rho: f64,
    pub cp: f64,
}

pub fn read() -> Vec<Material> {
    fs::read_to_string("input/materials.txt").unwrap().lines().map(|line| {
        let w: Vec<_> = line.split_whitespace().collect();
        Material { code: w[0].as_bytes()[0], name: w[1].to_owned(), k: w[2].parse().unwrap(),
            rho: w[3].parse().unwrap(), cp: w[4].parse().unwrap() }
    }).collect()
}

pub fn capacity(m: &Material, dx: f64, d: f64) -> f64 { m.rho * m.cp * dx * dx * d }
pub fn interior(a: f64, b: f64, d: f64) -> f64 { 2.0 * a * b / (a + b) * d }
pub fn fixed(k: f64, d: f64) -> f64 { 2.0 * k * d }
pub fn convective(k: f64, h: f64, dx: f64, d: f64) -> f64 {
    1.0 / (1.0 / (h * dx * d) + 1.0 / (2.0 * k * d))
}
