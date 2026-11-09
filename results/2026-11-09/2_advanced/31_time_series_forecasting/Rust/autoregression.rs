use crate::decomposition::{mean, total};

pub const KINDS: [&str; 4] = ["none", "first", "seasonal", "both"];

pub fn difference(values: &[f64], season: usize, kind: usize) -> (Vec<f64>, usize) {
    match kind {
        0 => (values.to_vec(), 0),
        1 => ((1..values.len()).map(|t| values[t] - values[t - 1]).collect(), 1),
        2 => ((season..values.len()).map(|t| values[t] - values[t - season]).collect(), season),
        _ => ((season + 1..values.len()).map(|t| (values[t] - values[t - 1]) - (values[t - season] - values[t - season - 1])).collect(), season + 1),
    }
}

pub fn autocorrelation(values: &[f64], max_lag: usize) -> (f64, f64, Vec<f64>) {
    let average = mean(values);
    let centered: Vec<f64> = values.iter().map(|v| v - average).collect();
    let count = values.len();
    let variance = total(centered.iter().map(|v| v * v)) / count as f64;
    let mut correlations = vec![1.0];
    for lag in 1..=max_lag {
        let numerator = total((0..count - lag).map(|i| centered[i] * centered[i + lag]));
        correlations.push(numerator / count as f64 / variance);
    }
    (average, variance, correlations)
}

pub struct DurbinLevinson {
    pub coefficients: Vec<Vec<f64>>,
    pub partial: Vec<f64>,
    pub variances: Vec<f64>,
}

pub fn durbin_levinson(correlations: &[f64]) -> DurbinLevinson {
    let mut coefficients: Vec<Vec<f64>> = vec![Vec::new()];
    let mut partial = vec![0.0];
    let mut variances = vec![1.0];
    for order in 1..correlations.len() {
        let previous = &coefficients[order - 1];
        let correction = total((1..order).map(|j| previous[j - 1] * correlations[order - j]));
        let theta = (correlations[order] - correction) / variances[order - 1];
        let mut current: Vec<f64> = (1..order).map(|j| previous[j - 1] - theta * previous[order - j - 1]).collect();
        current.push(theta);
        coefficients.push(current);
        partial.push(theta);
        variances.push(variances[order - 1] * (1.0 - theta * theta));
    }
    DurbinLevinson { coefficients, partial, variances }
}

pub fn residuals(values: &[f64], average: f64, coefficients: &[f64]) -> Vec<f64> {
    let order = coefficients.len();
    (order..values.len()).map(|i| values[i] - average - total((1..=order).map(|j| coefficients[j - 1] * (values[i - j] - average)))).collect()
}

pub fn forecast(values: &[f64], differenced: &[f64], offset: usize, kind: usize, average: f64,
                coefficients: &[f64], origin: usize, steps: usize, season: usize) -> Vec<f64> {
    let mut transformed = differenced[..origin - offset].to_vec();
    let mut extended = values[..origin].to_vec();
    let mut result = Vec::new();
    for _ in 0..steps {
        let mut predicted = average + total(coefficients.iter().enumerate().map(|(j, coefficient)| coefficient * (transformed[transformed.len() - j - 1] - average)));
        transformed.push(predicted);
        let n = extended.len();
        predicted = match kind {
            1 => predicted + extended[n - 1],
            2 => predicted + extended[n - season],
            3 => predicted + extended[n - 1] + extended[n - season] - extended[n - season - 1],
            _ => predicted,
        };
        extended.push(predicted);
        result.push(predicted);
    }
    result
}

pub fn ljung_box(errors: &[f64], lags: &[usize]) -> Vec<(usize, f64, f64)> {
    let count = errors.len();
    let (_, _, correlations) = autocorrelation(errors, *lags.iter().max().unwrap());
    lags.iter().map(|&lag| {
        let q = count as f64 * (count + 2) as f64 * total((1..=lag).map(|k| correlations[k] * correlations[k] / (count - k) as f64));
        let x = q / 2.0;
        let mut term = 1.0;
        let mut sum = term;
        for i in 1..lag / 2 {
            term = term * x / i as f64;
            sum += term;
        }
        (lag, q, (-x).exp() * sum)
    }).collect()
}
