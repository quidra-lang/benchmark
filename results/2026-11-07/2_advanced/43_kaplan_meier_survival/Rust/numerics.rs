pub type Matrix = Vec<Vec<f64>>;
pub fn sum(values: impl IntoIterator<Item = f64>) -> f64 { values.into_iter().fold(0.0, |total, v| total + v) }

pub fn solve(matrix: &Matrix, right: &[f64]) -> Vec<f64> {
    let mut a = matrix.clone();
    let mut b = right.to_vec();
    let n = b.len();
    for k in 0..n {
        for i in k + 1..n {
            let factor = a[i][k] / a[k][k];
            for j in k..n {
                let correction = factor * a[k][j];
                a[i][j] -= correction;
            }
            let correction = factor * b[k];
            b[i] -= correction;
        }
    }
    let mut solution = vec![0.0; n];
    for i in (0..n).rev() {
        let mut value = b[i];
        for j in i + 1..n { value -= a[i][j] * solution[j]; }
        solution[i] = value / a[i][i];
    }
    solution
}

pub fn inverse(matrix: &Matrix) -> Matrix {
    let n = matrix.len();
    let mut result = vec![vec![0.0; n]; n];
    for column in 0..n {
        let mut unit = vec![0.0; n];
        unit[column] = 1.0;
        let solution = solve(matrix, &unit);
        for row in 0..n { result[row][column] = solution[row]; }
    }
    result
}

fn log_gamma(a: f64) -> f64 {
    let coefficients = [76.18009172947146, -86.50532032941677, 24.01409824083091, -1.231739572450155, 0.001208650973866179, -0.000005395239384953];
    let x0 = a + 5.5;
    let x1 = x0 - (a + 0.5) * x0.ln();
    let mut sigma = 1.000000000190015;
    let mut y = a;
    for coefficient in coefficients { y += 1.0; sigma += coefficient / y; }
    -x1 + (2.5066282746310005 * sigma / a).ln()
}

fn gamma_q(a: f64, x: f64) -> f64 {
    if x == 0.0 { return 1.0; }
    let prefactor = (-x + a * x.ln() - log_gamma(a)).exp();
    if x < a + 1.0 {
        let mut alpha = a;
        let mut term = 1.0 / a;
        let mut total = term;
        for _ in 0..1000 {
            alpha += 1.0;
            term *= x / alpha;
            total += term;
            if term.abs() < total.abs() * 1e-15 { break; }
        }
        1.0 - total * prefactor
    } else {
        let epsilon = 1e-300;
        let mut b = x + 1.0 - a;
        let mut c = 1.0 / epsilon;
        let mut d = 1.0 / b;
        let mut h = d;
        for i in 1..=1000 {
            let i = i as f64;
            let an = -i * (i - a);
            b += 2.0;
            d = an * d + b;
            if d.abs() < epsilon { d = epsilon; }
            c = b + an / c;
            if c.abs() < epsilon { c = epsilon; }
            d = 1.0 / d;
            let delta = d * c;
            h *= delta;
            if (delta - 1.0).abs() < 1e-15 { break; }
        }
        prefactor * h
    }
}

pub fn p_value(statistic: f64, degrees: usize) -> f64 { gamma_q(degrees as f64 / 2.0, statistic / 2.0) }
