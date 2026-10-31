use std::collections::BTreeMap;

pub fn log10(value: f64) -> f64 {
    value.ln() / 2.302585092994046
}

pub fn local(amplitude: i64, distance_km: f64, coefficients: [f64; 3]) -> f64 {
    log10(amplitude as f64) + coefficients[0] * log10(distance_km / 100.0)
        + coefficients[1] * (distance_km - 100.0) + coefficients[2]
}

pub fn duration(samples: usize, distance_km: f64, coefficients: [f64; 3]) -> f64 {
    coefficients[0] + coefficients[1] * log10(samples as f64 / 100.0) + coefficients[2] * distance_km
}

pub fn median(values: &[f64]) -> f64 {
    let mut sorted = values.to_vec();
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let n = sorted.len();
    if n % 2 == 1 { sorted[n / 2] } else { (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0 }
}

pub fn rounded(value: f64, decimals: u32) -> i64 {
    let scale = 10i64.pow(decimals) as f64;
    let units = (value.abs() * scale + 0.5).floor() as i64;
    if value < 0.0 { -units } else { units }
}

pub fn class(value: f64) -> i64 {
    (rounded(value, 2) + 5).div_euclid(10)
}

pub struct Frequency {
    pub histogram: BTreeMap<i64, usize>,
    pub completeness: i64,
    pub count: usize,
    pub b: f64,
    pub sigma: f64,
    pub a: f64,
}

pub fn frequency(values: &[f64]) -> Frequency {
    let mut histogram = BTreeMap::new();
    for &value in values { *histogram.entry(class(value)).or_insert(0usize) += 1; }
    let mut completeness = *histogram.keys().next().unwrap();
    for (&t, &count) in &histogram {
        if count > histogram[&completeness] { completeness = t; }
    }
    let count: usize = histogram.range(completeness..).map(|(_, n)| n).sum();
    let sum: i64 = histogram.range(completeness..).map(|(t, &n)| t * n as i64).sum();
    let mean = sum as f64 / (10 * count) as f64;
    let mc = completeness as f64 / 10.0;
    let b = 0.4342944819032518 / (mean - (mc - 0.05));
    Frequency { histogram, completeness, count, b, sigma: b / (count as f64).sqrt(), a: log10(count as f64) + b * mc }
}
