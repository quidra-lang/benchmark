use crate::dataset::Row;
use crate::linalg::{cholesky, log_determinant, quadratic, sum, Matrix};

pub struct Statistics {
    pub counts: Vec<usize>,
    pub means: Vec<Vec<f64>>,
    pub scatter: Vec<Matrix>,
    pub center: Vec<f64>,
    pub variances: Vec<f64>,
    pub priors: Vec<f64>,
}

pub fn statistics(rows: &[Row], features: &[usize], classes: usize, prior: &str) -> Statistics {
    let p = features.len();
    let counts: Vec<_> = (0..classes).map(|k| rows.iter().filter(|row| row.class == k).count()).collect();
    let means: Vec<Vec<_>> = (0..classes).map(|k| features.iter().map(|&f| sum(rows.iter().filter(|row| row.class == k).map(|row| row.values[f])) / counts[k] as f64).collect()).collect();
    let scatter: Vec<Matrix> = (0..classes).map(|k| {
        (0..p).map(|a| (0..p).map(|b| sum(rows.iter().filter(|row| row.class == k).map(|row| (row.values[features[a]] - means[k][a]) * (row.values[features[b]] - means[k][b])))).collect()).collect()
    }).collect();
    let center: Vec<_> = features.iter().map(|&f| sum(rows.iter().map(|row| row.values[f])) / rows.len() as f64).collect();
    let variances = features.iter().enumerate().map(|(j, &f)| sum(rows.iter().map(|row| { let d = row.values[f] - center[j]; d * d })) / rows.len() as f64).collect();
    let priors = counts.iter().map(|&n| if prior == "empirical" { n as f64 / rows.len() as f64 } else { 1.0 / classes as f64 }).collect();
    Statistics { counts, means, scatter, center, variances, priors }
}

pub struct Model {
    pub features: Vec<usize>,
    pub statistics: Statistics,
    pub covariance: Vec<Matrix>,
    pub lower: Vec<Matrix>,
    pub log_determinants: Vec<f64>,
}

pub struct Prediction {
    pub class: usize,
    pub posterior: Vec<f64>,
    pub log_posterior: Vec<f64>,
    pub confidence: f64,
    pub decision: usize,
    pub distances: Vec<f64>,
}

pub fn first_max(values: &[f64]) -> usize {
    let mut best = 0;
    for i in 1..values.len() { if values[i] > values[best] { best = i; } }
    best
}

pub fn first_min(values: &[f64]) -> usize {
    let mut best = 0;
    for i in 1..values.len() { if values[i] < values[best] { best = i; } }
    best
}

impl Model {
    pub fn train(rows: &[Row], features: &[usize], classes: usize, kind: usize, epsilon: f64, gamma: f64, prior: &str) -> Self {
        let statistics = statistics(rows, features, classes, prior);
        let p = features.len();
        let maximum = statistics.variances.iter().copied().fold(f64::NEG_INFINITY, f64::max);
        let covariance: Vec<Matrix> = (0..classes).map(|k| {
            (0..p).map(|a| (0..p).map(|b| match kind {
                0 => if a == b { statistics.scatter[k][a][a] / statistics.counts[k] as f64 + epsilon * maximum } else { 0.0 },
                1 => sum((0..classes).map(|c| statistics.scatter[c][a][b])) / (rows.len() - classes) as f64,
                _ => {
                    let value = statistics.scatter[k][a][b] / (statistics.counts[k] - 1) as f64;
                    if a == b { value } else { value * (1.0 - gamma) }
                }
            }).collect()).collect()
        }).collect();
        let lower: Vec<_> = covariance.iter().map(cholesky).collect();
        let log_determinants = lower.iter().map(log_determinant).collect();
        Self { features: features.to_vec(), statistics, covariance, lower, log_determinants }
    }

    pub fn predict(&self, vector: &[f64], costs: &[Vec<f64>]) -> Prediction {
        let h = vector.len() as f64 * (2.0 * std::f64::consts::PI).ln() / 2.0;
        let distances: Vec<_> = self.statistics.means.iter().enumerate().map(|(k, mean)| quadratic(&self.lower[k], &vector.iter().zip(mean).map(|(&x, &m)| x - m).collect::<Vec<_>>())).collect();
        let scores: Vec<_> = (0..distances.len()).map(|k| self.statistics.priors[k].ln() - h - self.log_determinants[k] / 2.0 - distances[k] / 2.0).collect();
        let class = first_max(&scores);
        let maximum = scores[class];
        let exponentials: Vec<_> = scores.iter().map(|&score| (score - maximum).exp()).collect();
        let total = sum(exponentials.iter().copied());
        let posterior: Vec<_> = exponentials.iter().map(|&value| value / total).collect();
        let log_posterior = scores.iter().map(|&score| (score - maximum) - total.ln()).collect();
        let risks: Vec<_> = (0..posterior.len()).map(|b| sum(posterior.iter().enumerate().map(|(k, &p)| p * costs[k][b]))).collect();
        Prediction { class, confidence: posterior[class], posterior, log_posterior, decision: first_min(&risks), distances }
    }

    pub fn row(&self, row: &Row, costs: &[Vec<f64>]) -> Prediction {
        self.predict(&self.features.iter().map(|&f| row.values[f]).collect::<Vec<_>>(), costs)
    }
}
