use crate::waveform_io::{Station, Params};

#[derive(Clone, Copy)]
pub struct Solution {
    pub x: f64,
    pub y: f64,
    pub z: f64,
    pub time: f64,
    pub rms: f64,
}

#[derive(Clone, Copy)]
pub struct Observation {
    pub station: usize,
    pub time: f64,
}

pub struct Run {
    pub grid: Solution,
    pub profile: Vec<f64>,
    pub iterations: Vec<Solution>,
}

impl Run {
    pub fn solution(&self) -> Solution {
        *self.iterations.last().unwrap()
    }
}

pub fn distance(solution: Solution, station: &Station) -> f64 {
    let dx = solution.x - station.x as f64;
    let dy = solution.y - station.y as f64;
    let dz = solution.z + station.elevation as f64;
    (dx * dx + dy * dy + dz * dz).sqrt()
}

pub fn residuals(solution: Solution, observations: &[Observation], stations: &[Station], velocity: f64) -> Vec<f64> {
    observations.iter().map(|o| o.time - solution.time - distance(solution, &stations[o.station]) / velocity).collect()
}

pub fn rms(solution: Solution, observations: &[Observation], stations: &[Station], velocity: f64) -> f64 {
    (residuals(solution, observations, stations, velocity).iter().map(|r| r * r).sum::<f64>() / observations.len() as f64).sqrt()
}

pub fn normal(solution: Solution, observations: &[Observation], stations: &[Station], velocity: f64) -> ([[f64; 4]; 4], [f64; 4]) {
    let mut a = [[0.0; 4]; 4];
    let mut b = [0.0; 4];
    for o in observations {
        let station = &stations[o.station];
        let d = distance(solution, station);
        let r = o.time - solution.time - d / velocity;
        let g = [(solution.x - station.x as f64) / (velocity * d), (solution.y - station.y as f64) / (velocity * d),
            (solution.z + station.elevation as f64) / (velocity * d), 1.0];
        for row in 0..4 {
            for column in 0..4 { a[row][column] += g[row] * g[column]; }
            b[row] += g[row] * r;
        }
    }
    (a, b)
}

pub fn cholesky(a: &[[f64; 4]; 4]) -> [[f64; 4]; 4] {
    let mut l = [[0.0; 4]; 4];
    for row in 0..4 {
        for column in 0..=row {
            let sum: f64 = (0..column).map(|k| l[row][k] * l[column][k]).sum();
            l[row][column] = if row == column { (a[row][column] - sum).sqrt() } else { (a[row][column] - sum) / l[column][column] };
        }
    }
    l
}

pub fn solve(l: &[[f64; 4]; 4], b: &[f64; 4]) -> [f64; 4] {
    let mut u = [0.0; 4];
    for row in 0..4 {
        let sum: f64 = (0..row).map(|k| l[row][k] * u[k]).sum();
        u[row] = (b[row] - sum) / l[row][row];
    }
    let mut delta = [0.0; 4];
    for row in (0..4).rev() {
        let sum: f64 = (row + 1..4).map(|k| l[k][row] * delta[k]).sum();
        delta[row] = (u[row] - sum) / l[row][row];
    }
    delta
}

pub fn geiger(initial: Solution, observations: &[Observation], stations: &[Station], velocity: f64) -> Vec<Solution> {
    let mut solution = initial;
    let mut iterations = Vec::new();
    for _ in 0..8 {
        let (a, b) = normal(solution, observations, stations, velocity);
        let delta = solve(&cholesky(&a), &b);
        solution.x += delta[0];
        solution.y += delta[1];
        solution.z = (solution.z + delta[2]).max(0.0);
        solution.time += delta[3];
        solution.rms = rms(solution, observations, stations, velocity);
        iterations.push(solution);
    }
    iterations
}

pub fn run(observations: &[Observation], stations: &[Station], params: &Params) -> Run {
    let [gx, gy, gz] = params.grid;
    let depths = ((gz[1] - gz[0]) / gz[2] + 1) as usize;
    let mut profile = vec![f64::INFINITY; depths];
    let mut minimum = f64::INFINITY;
    let mut grid = Solution { x: 0.0, y: 0.0, z: 0.0, time: 0.0, rms: 0.0 };
    for x in (gx[0]..=gx[1]).step_by(gx[2] as usize) {
        for y in (gy[0]..=gy[1]).step_by(gy[2] as usize) {
            for (k, z) in (gz[0]..=gz[1]).step_by(gz[2] as usize).enumerate() {
                let mut solution = Solution { x: x as f64, y: y as f64, z: z as f64, time: 0.0, rms: 0.0 };
                let delta: Vec<f64> = observations.iter().map(|o| o.time - distance(solution, &stations[o.station]) / params.velocity).collect();
                solution.time = delta.iter().sum::<f64>() / observations.len() as f64;
                let sum: f64 = delta.iter().map(|d| (d - solution.time) * (d - solution.time)).sum();
                profile[k] = profile[k].min(sum);
                if sum < minimum {
                    minimum = sum;
                    solution.rms = (sum / observations.len() as f64).sqrt();
                    grid = solution;
                }
            }
        }
    }
    for value in &mut profile { *value = (*value / observations.len() as f64).sqrt(); }
    Run { grid, profile, iterations: geiger(grid, observations, stations, params.velocity) }
}

pub struct Ellipse {
    pub major: f64,
    pub minor: f64,
    pub azimuth: f64,
    pub depth: f64,
    pub time: f64,
}

pub fn ellipse(solution: Solution, observations: &[Observation], stations: &[Station], velocity: f64) -> Ellipse {
    let (a, _) = normal(solution, observations, stations, velocity);
    let l = cholesky(&a);
    let sigma = residuals(solution, observations, stations, velocity).iter().map(|r| r * r).sum::<f64>() / (observations.len() - 4) as f64;
    let mut c = [[0.0; 4]; 4];
    for column in 0..4 {
        let mut unit = [0.0; 4];
        unit[column] = 1.0;
        let values = solve(&l, &unit);
        for row in 0..4 { c[row][column] = sigma * values[row]; }
    }
    let mu = (c[0][0] + c[1][1]) / 2.0;
    let difference = (c[0][0] - c[1][1]) / 2.0;
    let rho = (difference * difference + c[0][1] * c[0][1]).sqrt();
    let theta = (2.0 * c[0][1]).atan2(c[0][0] - c[1][1]) / 2.0 * 180.0 / 3.141592653589793;
    let azimuth = (90.0 - theta).rem_euclid(180.0);
    Ellipse { major: (mu + rho).sqrt(), minor: (mu - rho).sqrt(), azimuth, depth: c[2][2].sqrt(), time: c[3][3].sqrt() }
}
