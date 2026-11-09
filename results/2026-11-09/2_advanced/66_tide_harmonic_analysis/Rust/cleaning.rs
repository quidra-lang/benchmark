use std::collections::BTreeMap;

pub fn median(mut values: Vec<f64>) -> f64 {
    values.sort_by(f64::total_cmp);
    let n = values.len();
    if n%2 == 1 { values[n/2] } else { (values[n/2-1]+values[n/2])/2.0 }
}

pub fn flat_runs(values: &[Option<i64>], length: usize) -> Vec<(usize, usize, i64)> {
    let mut runs = Vec::new();
    let mut i = 0;
    while i < values.len() {
        if let Some(value) = values[i] {
            let first = i; i += 1;
            while i < values.len() && values[i] == Some(value) { i += 1; }
            if i-first >= length { runs.push((first, i-1, value)); }
        } else { i += 1; }
    }
    runs
}

pub struct Spike { pub time: i64, pub residual: f64, pub median: f64, pub mad: f64, pub limit: f64 }

pub fn spikes(residuals: &BTreeMap<i64, f64>, window: i64, count: usize, factor: f64, lower: f64) -> (usize, Vec<Spike>) {
    let mut tested = 0;
    let mut spikes = Vec::new();
    for (&time, &residual) in residuals {
        let values: Vec<_> = residuals.range(time-window..=time+window).map(|(_, &e)| e).collect();
        if values.len() < count { continue; }
        tested += 1;
        let center = median(values.clone());
        let mad = median(values.iter().map(|e| (e-center).abs()).collect());
        let limit = (factor*1.4826*mad).max(lower);
        if (residual-center).abs() > limit { spikes.push(Spike { time, residual, median: center, mad, limit }); }
    }
    (tested, spikes)
}

pub fn gaps(reasons: &[String]) -> Vec<(usize, usize, String)> {
    let mut result = Vec::new();
    let mut i = 0;
    while i < reasons.len() {
        if reasons[i].is_empty() { i += 1; continue; }
        let first = i; i += 1;
        while i < reasons.len() && !reasons[i].is_empty() { i += 1; }
        let cause = if reasons[first..i].iter().all(|r| r == &reasons[first]) { reasons[first].clone() } else { "mixed".to_owned() };
        result.push((first, i-1, cause));
    }
    result
}
