pub fn sum(values: impl IntoIterator<Item = f64>) -> f64 {
    values.into_iter().fold(0.0, |total, value| total + value)
}

pub fn cv(observed: &[f64], predictions: &[Option<f64>]) -> Option<f64> {
    let mut total = 0.0;
    for (&y, prediction) in observed.iter().zip(predictions) {
        let difference = y - prediction.as_ref()?;
        total += difference * difference;
    }
    Some(total / observed.len() as f64)
}

pub fn gcv(rss: f64, edf: f64, count: usize) -> f64 {
    let tau = 1.0 - edf / count as f64;
    rss / count as f64 / (tau * tau)
}

pub fn select(scores: &[Option<f64>]) -> usize {
    let mut selected: Option<usize> = None;
    for (index, &score) in scores.iter().enumerate() {
        if let Some(score) = score {
            if selected.is_none_or(|i| score < scores[i].unwrap()) { selected = Some(index); }
        }
    }
    selected.unwrap()
}
