#[derive(Clone, Copy)]
pub enum DistanceKind { Euclidean, Manhattan, Correlation }

impl DistanceKind {
    pub fn parse(value: &str) -> Self {
        match value { "euclidean" => Self::Euclidean, "manhattan" => Self::Manhattan, _ => Self::Correlation }
    }
    pub fn name(self) -> &'static str {
        match self { Self::Euclidean => "euclidean", Self::Manhattan => "manhattan", Self::Correlation => "correlation" }
    }
}

pub const DISTANCE_TYPES: [DistanceKind; 3] = [DistanceKind::Euclidean, DistanceKind::Manhattan, DistanceKind::Correlation];

pub fn sequential_sum(values: impl IntoIterator<Item = f64>) -> f64 {
    let mut sum = 0.0;
    for value in values { sum += value; }
    sum
}

pub fn squared_distance(first: &[f64], second: &[f64]) -> f64 {
    sequential_sum(first.iter().zip(second).map(|(a, b)| (a - b) * (a - b)))
}

pub fn feature_statistics(rows: &[Vec<f64>]) -> (Vec<f64>, Vec<f64>) {
    let mut means = Vec::new();
    let mut deviations = Vec::new();
    for f in 0..rows[0].len() {
        let mean = sequential_sum(rows.iter().map(|row| row[f])) / rows.len() as f64;
        let variance = sequential_sum(rows.iter().map(|row| (row[f] - mean) * (row[f] - mean))) / (rows.len() - 1) as f64;
        means.push(mean);
        deviations.push(variance.sqrt());
    }
    (means, deviations)
}

pub fn standardize(rows: &[Vec<f64>], means: &[f64], deviations: &[f64]) -> Vec<Vec<f64>> {
    rows.iter().map(|row| row.iter().enumerate().map(|(f, value)| (value - means[f]) / deviations[f]).collect()).collect()
}

pub fn distance(first: &[f64], second: &[f64], kind: DistanceKind) -> f64 {
    match kind {
        DistanceKind::Euclidean => squared_distance(first, second).sqrt(),
        DistanceKind::Manhattan => sequential_sum(first.iter().zip(second).map(|(a, b)| (a - b).abs())),
        DistanceKind::Correlation => {
            let first_mean = sequential_sum(first.iter().copied()) / first.len() as f64;
            let second_mean = sequential_sum(second.iter().copied()) / second.len() as f64;
            let cross = sequential_sum(first.iter().zip(second).map(|(a, b)| (a - first_mean) * (b - second_mean)));
            let first_spread = sequential_sum(first.iter().map(|a| (a - first_mean) * (a - first_mean)));
            let second_spread = sequential_sum(second.iter().map(|b| (b - second_mean) * (b - second_mean)));
            1.0 - cross / (first_spread * second_spread).sqrt()
        }
    }
}

pub fn distance_matrix(vectors: &[Vec<f64>], kind: DistanceKind) -> Vec<Vec<f64>> {
    let n = vectors.len();
    let mut matrix = vec![vec![0.0; n]; n];
    for i in 0..n {
        for j in i + 1..n {
            let value = distance(&vectors[i], &vectors[j], kind);
            matrix[i][j] = value;
            matrix[j][i] = value;
        }
    }
    matrix
}
