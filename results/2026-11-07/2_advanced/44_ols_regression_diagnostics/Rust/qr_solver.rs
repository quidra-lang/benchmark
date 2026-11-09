pub type Matrix = Vec<Vec<f64>>;
pub fn sum(values: impl IntoIterator<Item = f64>) -> f64 { values.into_iter().fold(0.0, |total, value| total + value) }

pub struct Fit {
    pub accepted: Vec<usize>,
    pub coefficients: Vec<Option<f64>>,
    pub effects: Vec<f64>,
    pub inverse: Matrix,
    pub variance_factors: Vec<f64>,
    pub leverage: Vec<f64>,
    pub g: Matrix,
    pub fitted: Vec<f64>,
    pub residuals: Vec<f64>,
    pub weighted_residuals: Vec<f64>,
    pub rss: f64,
}

pub fn fit(x: &Matrix, y: &[f64], weights: &[f64], tolerance: f64) -> Fit {
    let n = x.len();
    let p = x[0].len();
    let roots: Vec<_> = weights.iter().map(|w| w.sqrt()).collect();
    let z: Matrix = x.iter().zip(&roots).map(|(row, &root)| row.iter().map(|&v| root * v).collect()).collect();
    let norms: Vec<_> = (0..p).map(|j| sum((0..n).map(|i| z[i][j] * z[i][j])).sqrt()).collect();
    let mut a = z.clone();
    let mut b: Vec<_> = y.iter().zip(&roots).map(|(&y, &root)| root * y).collect();
    let mut r_matrix = vec![vec![0.0; p]; p];
    let mut accepted = Vec::new();
    for j in 0..p {
        let k = accepted.len();
        let eta = sum((k..n).map(|i| a[i][j] * a[i][j])).sqrt();
        if norms[j] == 0.0 || eta <= tolerance * norms[j] { continue; }
        accepted.push(j);
        let alpha = if a[k][j] >= 0.0 { -eta } else { eta };
        let mut v: Vec<_> = (k..n).map(|i| a[i][j]).collect();
        v[0] -= alpha;
        let norm = sum(v.iter().map(|v| v * v));
        for l in 0..k { r_matrix[l][k] = a[l][j]; }
        r_matrix[k][k] = alpha;
        for l in j + 1..p {
            let delta = 2.0 * sum((k..n).map(|i| v[i - k] * a[i][l])) / norm;
            for i in k..n { a[i][l] -= delta * v[i - k]; }
        }
        let delta = 2.0 * sum((k..n).map(|i| v[i - k] * b[i])) / norm;
        for i in k..n { b[i] -= delta * v[i - k]; }
    }
    let rank = accepted.len();
    let effects = b[..rank].to_vec();
    let mut beta = vec![0.0; rank];
    for k in (0..rank).rev() { beta[k] = (effects[k] - sum((k + 1..rank).map(|l| r_matrix[k][l] * beta[l]))) / r_matrix[k][k]; }
    let mut coefficients = vec![None; p];
    for (k, &j) in accepted.iter().enumerate() { coefficients[j] = Some(beta[k]); }
    let mut inverse = vec![vec![0.0; rank]; rank];
    for m in 0..rank {
        for l in (0..rank).rev() { inverse[l][m] = ((if l == m { 1.0 } else { 0.0 }) - sum((l + 1..rank).map(|q| r_matrix[l][q] * inverse[q][m]))) / r_matrix[l][l]; }
    }
    let variance_factors = inverse.iter().map(|row| sum(row.iter().map(|v| v * v))).collect();
    let u: Matrix = (0..n).map(|i| (0..rank).map(|k| sum((0..rank).map(|m| z[i][accepted[m]] * inverse[m][k]))).collect()).collect();
    let leverage = u.iter().map(|row| sum(row.iter().map(|v| v * v))).collect();
    let g = (0..n).map(|i| (0..rank).map(|k| sum((0..rank).map(|m| inverse[k][m] * u[i][m]))).collect()).collect();
    let fitted: Vec<_> = x.iter().map(|row| sum((0..rank).map(|k| row[accepted[k]] * beta[k]))).collect();
    let residuals: Vec<_> = y.iter().zip(&fitted).map(|(&y, &fitted)| y - fitted).collect();
    let weighted_residuals: Vec<_> = residuals.iter().zip(roots).map(|(&residual, root)| root * residual).collect();
    let rss = sum(weighted_residuals.iter().map(|v| v * v));
    Fit { accepted, coefficients, effects, inverse, variance_factors, leverage, g, fitted, residuals, weighted_residuals, rss }
}
