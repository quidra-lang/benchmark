pub type Matrix = Vec<Vec<f64>>;

pub fn sum(values: impl IntoIterator<Item = f64>) -> f64 { values.into_iter().fold(0.0, |total, value| total + value) }

pub fn cholesky(matrix: &Matrix) -> Matrix {
    let n = matrix.len();
    let mut lower = vec![vec![0.0; n]; n];
    for i in 0..n {
        for j in 0..=i {
            let s = matrix[i][j] - sum((0..j).map(|k| lower[i][k] * lower[j][k]));
            lower[i][j] = if i == j { s.sqrt() } else { s / lower[j][j] };
        }
    }
    lower
}

pub fn forward(lower: &Matrix, right: &[f64]) -> Vec<f64> {
    let mut solution = vec![0.0; right.len()];
    for i in 0..right.len() { solution[i] = (right[i] - sum((0..i).map(|k| lower[i][k] * solution[k]))) / lower[i][i]; }
    solution
}

pub fn backward(lower: &Matrix, right: &[f64]) -> Vec<f64> {
    let mut solution = vec![0.0; right.len()];
    for i in (0..right.len()).rev() { solution[i] = (right[i] - sum((i + 1..right.len()).map(|k| lower[k][i] * solution[k]))) / lower[i][i]; }
    solution
}

pub fn log_determinant(lower: &Matrix) -> f64 { 2.0 * sum((0..lower.len()).map(|i| lower[i][i].ln())) }

pub fn quadratic(lower: &Matrix, vector: &[f64]) -> f64 {
    let z = forward(lower, vector);
    sum(z.iter().map(|v| v * v))
}

pub fn jacobi(matrix: &Matrix) -> (Vec<f64>, Matrix, usize) {
    let n = matrix.len();
    let mut m = matrix.clone();
    let mut vectors = vec![vec![0.0; n]; n];
    for i in 0..n { vectors[i][i] = 1.0; }
    let mut sweeps = 0;
    loop {
        let mut off = 0.0;
        for a in 0..n { for b in a + 1..n { off += m[a][b] * m[a][b]; } }
        if off.sqrt() < 1e-12 || sweeps == 50 { break; }
        for a in 0..n {
            for b in a + 1..n {
                if m[a][b] == 0.0 { continue; }
                let theta = (m[b][b] - m[a][a]) / (2.0 * m[a][b]);
                let t = (if theta >= 0.0 { 1.0 } else { -1.0 }) / (theta.abs() + (theta * theta + 1.0).sqrt());
                let co = 1.0 / (t * t + 1.0).sqrt();
                let si = t * co;
                for k in 0..n {
                    if k == a || k == b { continue; }
                    let (x, y) = (m[k][a], m[k][b]);
                    m[k][a] = co * x - si * y;
                    m[a][k] = m[k][a];
                    m[k][b] = si * x + co * y;
                    m[b][k] = m[k][b];
                }
                let w = m[a][b];
                m[a][a] -= t * w;
                m[b][b] += t * w;
                m[a][b] = 0.0;
                m[b][a] = 0.0;
                for row in &mut vectors {
                    let (x, y) = (row[a], row[b]);
                    row[a] = co * x - si * y;
                    row[b] = si * x + co * y;
                }
            }
        }
        sweeps += 1;
    }
    ((0..n).map(|i| m[i][i]).collect(), vectors, sweeps)
}
