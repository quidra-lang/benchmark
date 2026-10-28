use crate::dataset::Point;
use crate::selection::sum;

pub fn median(values: &[f64]) -> f64 {
    let mut sorted = values.to_vec();
    sorted.sort_by(f64::total_cmp);
    let middle = sorted.len() / 2;
    if sorted.len() % 2 == 1 { sorted[middle] } else { (sorted[middle - 1] + sorted[middle]) / 2.0 }
}

fn cholesky(matrix: &[Vec<f64>]) -> Vec<Vec<f64>> {
    let mut lower = vec![vec![0.0; matrix.len()]; matrix.len()];
    for k in 0..matrix.len() {
        for l in 0..=k {
            let mut sigma = matrix[k][l];
            for j in 0..l { sigma -= lower[k][j] * lower[l][j]; }
            lower[k][l] = if k == l { sigma.sqrt() } else { sigma / lower[l][l] };
        }
    }
    lower
}

fn solve(lower: &[Vec<f64>], right: &[f64]) -> Vec<f64> {
    let n = right.len();
    let mut eta = vec![0.0; n];
    for k in 0..n {
        let mut value = right[k];
        for j in 0..k { value -= lower[k][j] * eta[j]; }
        eta[k] = value / lower[k][k];
    }
    let mut solution = vec![0.0; n];
    for k in (0..n).rev() {
        let mut value = eta[k];
        for j in k + 1..n { value -= lower[j][k] * solution[j]; }
        solution[k] = value / lower[k][k];
    }
    solution
}

pub struct Loess {
    pub rho: Vec<f64>,
    pub records: Vec<(f64, usize, f64)>,
    pub fitted: Vec<f64>,
    pub leverage: Vec<f64>,
    pub edf: f64,
    degree: usize,
    span: i64,
}

impl Loess {
    pub fn new(points: &[Point], span: i64, degree: usize, iterations: usize, full: bool) -> Self {
        let mut result = Self { rho: vec![1.0; points.len()], records: Vec::new(), fitted: Vec::new(), leverage: Vec::new(), edf: 0.0, degree, span };
        if !full { return result; }
        let mut fits: Vec<_> = points.iter().map(|p| result.local(points, p.x)).collect();
        for _ in 0..iterations {
            let residuals: Vec<_> = points.iter().zip(&fits).map(|(point, fit)| point.y as f64 / 100.0 - fit.0).collect();
            let scale = median(&residuals.iter().map(|v| v.abs()).collect::<Vec<_>>());
            for (rho, &residual) in result.rho.iter_mut().zip(&residuals) {
                let u = residual / (6.0 * scale);
                let v = 1.0 - u * u;
                *rho = if u.abs() < 1.0 { v * v } else { 0.0 };
            }
            let updated: Vec<_> = points.iter().map(|p| result.local(points, p.x)).collect();
            let change = updated.iter().zip(&fits).map(|(a, b)| (a.0 - b.0).abs()).fold(0.0, f64::max);
            result.records.push((scale, result.rho.iter().filter(|&&v| v == 0.0).count(), change));
            fits = updated;
        }
        result.fitted = fits.iter().map(|fit| fit.0).collect();
        result.leverage = result.rho.iter().zip(&fits).map(|(&rho, fit)| rho * fit.1).collect();
        result.edf = sum(result.leverage.iter().copied());
        result
    }

    pub fn local(&self, points: &[Point], position: i64) -> (f64, f64, Vec<f64>) {
        let mut neighbors: Vec<_> = (0..points.len()).collect();
        neighbors.sort_by_key(|&i| ((points[i].x - position).abs(), i));
        neighbors.truncate((self.span * points.len() as i64 / 100) as usize);
        let distance = neighbors.iter().map(|&i| (points[i].x - position).abs()).max().unwrap();
        neighbors.sort_unstable();
        let n = self.degree + 1;
        let mut matrix = vec![vec![0.0; n]; n];
        let mut right = vec![0.0; n];
        let mut rows = Vec::new();
        for i in neighbors {
            let a = (points[i].x - position).abs() as f64 / distance as f64;
            let s = 1.0 - a * a * a;
            let v = s * s * s * self.rho[i];
            let d = points[i].x as f64 / 100.0 - position as f64 / 100.0;
            let basis = if self.degree == 1 { vec![1.0, d] } else { vec![1.0, d, d * d] };
            for k in 0..n {
                right[k] += v * basis[k] * (points[i].y as f64 / 100.0);
                for l in 0..n { matrix[k][l] += v * basis[k] * basis[l]; }
            }
            rows.push((i, v, basis));
        }
        let lower = cholesky(&matrix);
        let beta = solve(&lower, &right);
        let mut e = vec![0.0; n];
        e[0] = 1.0;
        let zeta = solve(&lower, &e);
        let mut weights = vec![0.0; points.len()];
        for (i, v, basis) in rows { weights[i] = v * sum((0..n).map(|k| zeta[k] * basis[k])); }
        (beta[0], zeta[0], weights)
    }
}
