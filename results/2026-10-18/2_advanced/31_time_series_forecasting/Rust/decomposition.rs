pub fn total(values: impl IntoIterator<Item = f64>) -> f64 {
    let mut result = 0.0;
    for value in values {
        result += value;
    }
    result
}

pub fn mean(values: &[f64]) -> f64 {
    total(values.iter().copied()) / values.len() as f64
}

pub fn sample_variance(values: &[f64]) -> f64 {
    let average = mean(values);
    total(values.iter().map(|v| (v - average) * (v - average))) / (values.len() - 1) as f64
}

pub struct Decomposition {
    pub trend: Vec<Option<f64>>,
    pub additive: Vec<f64>,
    pub multiplicative: Vec<f64>,
    pub residual_add: Vec<Option<f64>>,
    pub residual_mult: Vec<Option<f64>>,
    pub defined: Vec<usize>,
}

pub fn decompose(values: &[f64], season: usize) -> Decomposition {
    let count = values.len();
    let half = season / 2;
    let defined: Vec<usize> = (half..count - half).collect();
    let mut trend = vec![None; count];
    for &t in &defined {
        let mut value = 0.5 * values[t - half];
        for i in t - half + 1..t + half {
            value += values[i];
        }
        value += 0.5 * values[t + half];
        trend[t] = Some(value / season as f64);
    }
    let mut additive = Vec::new();
    let mut multiplicative = Vec::new();
    for position in 0..season {
        let times: Vec<usize> = defined.iter().copied().filter(|t| t % season == position).collect();
        additive.push(total(times.iter().map(|&t| values[t] - trend[t].unwrap())) / times.len() as f64);
        multiplicative.push(total(times.iter().map(|&t| values[t] / trend[t].unwrap())) / times.len() as f64);
    }
    let average_add = mean(&additive);
    let average_mult = mean(&multiplicative);
    for j in 0..season {
        additive[j] -= average_add;
        multiplicative[j] /= average_mult;
    }
    let mut residual_add = vec![None; count];
    let mut residual_mult = vec![None; count];
    for &t in &defined {
        residual_add[t] = Some(values[t] - trend[t].unwrap() - additive[t % season]);
        residual_mult[t] = Some(values[t] / (trend[t].unwrap() * multiplicative[t % season]));
    }
    Decomposition { trend, additive, multiplicative, residual_add, residual_mult, defined }
}

pub fn least_squares_line(values: &[f64]) -> (f64, f64) {
    let center = (values.len() + 1) as f64 / 2.0;
    let average = mean(values);
    let numerator = total(values.iter().enumerate().map(|(t, v)| (t as f64 + 1.0 - center) * (v - average)));
    let denominator = total((0..values.len()).map(|t| (t as f64 + 1.0 - center) * (t as f64 + 1.0 - center)));
    let slope = numerator / denominator;
    (average - slope * center, slope)
}
