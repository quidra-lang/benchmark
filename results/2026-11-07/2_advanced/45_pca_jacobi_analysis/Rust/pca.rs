use crate::matrix::{self, Matrix};

pub struct Statistics {
    pub means: Vec<f64>,
    pub covariance: Matrix,
    pub correlation: Matrix,
    pub deviations: Vec<f64>,
}

pub fn statistics(data: &Matrix) -> Statistics {
    let n = data.len();
    let p = data[0].len();
    let means: Vec<f64> = (0..p).map(|j| data.iter().map(|r| r[j]).sum::<f64>() / n as f64).collect();
    let mut covariance = vec![vec![0.0; p]; p];
    for j in 0..p {
        for k in j..p {
            let mut total = 0.0;
            for row in data {
                total += (row[j] - means[j]) * (row[k] - means[k]);
            }
            covariance[j][k] = total / (n - 1) as f64;
            covariance[k][j] = covariance[j][k];
        }
    }
    let deviations: Vec<f64> = (0..p).map(|j| covariance[j][j].sqrt()).collect();
    let correlation = (0..p).map(|j| (0..p).map(|k| {
        if j == k { 1.0 } else { covariance[j][k] / (deviations[j] * deviations[k]) }
    }).collect()).collect();
    Statistics { means, covariance, correlation, deviations }
}

pub fn standardize(row: &[f64], means: &[f64], scales: &[f64]) -> Vec<f64> {
    (0..row.len()).map(|j| (row[j] - means[j]) / scales[j]).collect()
}

pub fn supplementary(row: &[Option<f64>], means: &[f64], scales: &[f64]) -> Vec<f64> {
    (0..row.len()).map(|j| row[j].map_or(0.0, |x| (x - means[j]) / scales[j])).collect()
}

pub fn scores(z: &[f64], vectors: &Matrix) -> Vec<f64> {
    vectors.iter().map(|v| matrix::dot(z, v)).collect()
}

pub fn residuals(z: &[f64], scores: &[f64], vectors: &Matrix, k: usize) -> Vec<f64> {
    (0..z.len()).map(|j| {
        let mut fitted = 0.0;
        for h in 0..k {
            fitted += scores[h] * vectors[h][j];
        }
        z[j] - fitted
    }).collect()
}

pub fn t2(scores: &[f64], values: &[f64], k: usize) -> f64 {
    let mut result = 0.0;
    for h in 0..k {
        result += (scores[h] * scores[h]) / values[h];
    }
    result
}
