use crate::decomposition::total;

pub struct Accuracy {
    pub me: f64,
    pub mae: f64,
    pub rmse: f64,
    pub mape: f64,
    pub smape: f64,
    pub mase: f64,
}

pub fn seasonal_scale(values: &[f64], season: usize) -> f64 {
    total((season..values.len()).map(|t| (values[t] - values[t - season]).abs())) / (values.len() - season) as f64
}

pub fn accuracy(actual: &[f64], predicted: &[f64], scale: f64) -> Accuracy {
    let count = actual.len() as f64;
    let errors: Vec<f64> = actual.iter().zip(predicted).map(|(a, f)| a - f).collect();
    let mae = total(errors.iter().map(|e| e.abs())) / count;
    Accuracy {
        me: total(errors.iter().copied()) / count,
        mae,
        rmse: (total(errors.iter().map(|e| e * e)) / count).sqrt(),
        mape: 100.0 * total(errors.iter().zip(actual).map(|(e, a)| e.abs() / a)) / count,
        smape: 100.0 * total(errors.iter().zip(actual).zip(predicted).map(|((e, a), f)| 2.0 * e.abs() / (a.abs() + f.abs()))) / count,
        mase: mae / scale,
    }
}

pub fn winkler(actual: f64, low: f64, high: f64, multiplier: f64) -> f64 {
    if actual < low {
        high - low + multiplier * (low - actual)
    } else if actual > high {
        high - low + multiplier * (actual - high)
    } else {
        high - low
    }
}

pub fn rank_models(scores: &[f64]) -> Vec<usize> {
    let mut order: Vec<usize> = (0..scores.len()).collect();
    order.sort_by(|&a, &b| scores[a].partial_cmp(&scores[b]).unwrap().then(a.cmp(&b)));
    order
}
