use std::collections::BTreeMap;
pub const PI: f64 = 3.141592653589793;

pub fn angle(speed: f64, time: f64) -> f64 {
    let degrees = speed*time;
    let reduced = degrees-360.0*(degrees/360.0).floor();
    reduced*PI/180.0
}

pub fn regressors(speeds: &[f64], time: f64) -> Vec<f64> {
    let mut x = vec![1.0];
    for &speed in speeds { let theta = angle(speed, time); x.push(theta.cos()); x.push(theta.sin()); }
    x
}

pub struct Fit { pub speeds: Vec<f64>, pub coefficients: Vec<f64>, pub inverse: Vec<Vec<f64>> }

pub fn fit(times: &[i64], levels: &BTreeMap<i64, f64>, speeds: &[f64]) -> Fit {
    let p = 2*speeds.len()+1;
    let mut matrix = vec![vec![0.0; 2*p+1]; p];
    for &time in times {
        let x = regressors(speeds, time as f64);
        for i in 0..p {
            for j in 0..p { matrix[i][j] += x[i]*x[j]; }
            matrix[i][p] += x[i]*levels[&time];
        }
    }
    for i in 0..p { matrix[i][p+1+i] = 1.0; }
    for j in 0..p {
        let pivot = (j..p).min_by(|&a, &b| matrix[b][j].abs().total_cmp(&matrix[a][j].abs()).then(a.cmp(&b))).unwrap();
        matrix.swap(j, pivot);
        for i in j+1..p {
            let factor = matrix[i][j]/matrix[j][j];
            for c in j..=2*p { let value = matrix[j][c]; matrix[i][c] -= factor*value; }
        }
    }
    let mut solutions = Vec::new();
    for c in p..=2*p {
        let mut sol = vec![0.0; p];
        for i in (0..p).rev() {
            let mut sum = matrix[i][c];
            for j in i+1..p { sum -= matrix[i][j]*sol[j]; }
            sol[i] = sum/matrix[i][i];
        }
        solutions.push(sol);
    }
    let coefficients = solutions[0].clone();
    let inverse = (0..p).map(|i| (0..p).map(|m| solutions[m+1][i]).collect()).collect();
    Fit { speeds: speeds.to_vec(), coefficients, inverse }
}

pub fn amplitude_phase(a: f64, b: f64) -> (f64, f64) {
    let amplitude = (a*a+b*b).sqrt();
    let mut phase = b.atan2(a)*180.0/PI;
    if phase < 0.0 { phase += 360.0; }
    (amplitude, phase)
}
