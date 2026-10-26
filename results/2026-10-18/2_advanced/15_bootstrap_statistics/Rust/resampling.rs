use crate::minstd::Minstd;

pub fn sequential_sum(values: impl IntoIterator<Item = f64>) -> f64 { let mut total = 0.0; for value in values { total += value; } total }
pub fn total(values: &[i64]) -> i64 { values.iter().sum() }
pub fn mean(values: &[i64]) -> f64 { total(values) as f64 / (100 * values.len()) as f64 }
pub fn doubled_median(values: &[i64]) -> i64 {
    let mut ordered = values.to_vec(); ordered.sort_unstable(); let size = ordered.len();
    ordered[(size + 1) / 2 - 1] + ordered[(size + 2) / 2 - 1]
}
pub fn median(values: &[i64]) -> f64 { doubled_median(values) as f64 / 200.0 }
pub fn trim_count(size: usize) -> usize { size / 10 }
pub fn trimmed_mean(values: &[i64]) -> f64 {
    let mut ordered = values.to_vec(); ordered.sort_unstable(); let size = ordered.len(); let trim = trim_count(size);
    total(&ordered[trim..size - trim]) as f64 / (100 * (size - 2 * trim)) as f64
}
pub fn sd(values: &[i64]) -> f64 {
    let center = mean(values);
    let squares = sequential_sum(values.iter().map(|&value| { let deviation = value as f64 / 100.0 - center; deviation * deviation }));
    (squares / (values.len() - 1) as f64).sqrt()
}
pub fn central_moments(values: &[i64]) -> [f64; 3] {
    let center = mean(values); let mut moments = [0.0; 3];
    for &value in values { let deviation = value as f64 / 100.0 - center;
        moments[0] += deviation * deviation; moments[1] += deviation * deviation * deviation; moments[2] += deviation * deviation * deviation * deviation; }
    for moment in &mut moments { *moment /= values.len() as f64; } moments
}
pub fn mad(values: &[i64]) -> f64 { let center = doubled_median(values); doubled_median(&values.iter().map(|&value| (2 * value - center).abs()).collect::<Vec<_>>()) as f64 / 400.0 }
pub fn quantile_numerator(values: &[i64], percent: usize) -> i64 {
    let mut ordered = values.to_vec(); ordered.sort_unstable(); let position = (values.len() - 1) * percent;
    let index = position / 100; let fraction = (position % 100) as i64;
    if fraction == 0 { 100 * ordered[index] } else { 100 * ordered[index] + fraction * (ordered[index + 1] - ordered[index]) }
}
pub fn winsorized(values: &[i64]) -> Vec<i64> {
    let mut ordered = values.to_vec(); ordered.sort_unstable(); let trim = trim_count(values.len());
    values.iter().map(|&value| value.clamp(ordered[trim], ordered[values.len() - trim - 1])).collect()
}
pub fn mean_difference(x: &[i64], y: &[i64]) -> f64 {
    (y.len() as i64 * total(x) - x.len() as i64 * total(y)) as f64 / (100 * x.len() * y.len()) as f64
}
pub fn median_ratio(x: &[i64], y: &[i64]) -> f64 { doubled_median(x) as f64 / doubled_median(y) as f64 }
pub fn hodges_lehmann(x: &[i64], y: &[i64]) -> f64 { let differences: Vec<_> = x.iter().flat_map(|&first| y.iter().map(move |&second| first - second)).collect(); doubled_median(&differences) as f64 / 200.0 }
pub fn pooled_sd(x: &[i64], y: &[i64]) -> f64 {
    let first = sd(x); let second = sd(y);
    (((x.len() - 1) as f64 * first * first + (y.len() - 1) as f64 * second * second) / (x.len() + y.len() - 2) as f64).sqrt()
}
pub fn cohen_d(x: &[i64], y: &[i64]) -> f64 { mean_difference(x, y) / pooled_sd(x, y) }
pub fn correlation(x: &[i64], y: &[i64]) -> f64 {
    let first_center = mean(x); let second_center = mean(y);
    let first: Vec<_> = x.iter().map(|&value| value as f64 / 100.0 - first_center).collect();
    let second: Vec<_> = y.iter().map(|&value| value as f64 / 100.0 - second_center).collect();
    let products = sequential_sum(first.iter().zip(&second).map(|(a, b)| a * b));
    let first_squares = sequential_sum(first.iter().map(|a| a * a)); let second_squares = sequential_sum(second.iter().map(|b| b * b));
    products / (first_squares * second_squares).sqrt()
}
pub fn group_statistics(values: &[i64]) -> [f64; 4] { [mean(values), median(values), trimmed_mean(values), sd(values)] }
pub fn pair_statistics(x: &[i64], y: &[i64]) -> [f64; 4] { [mean_difference(x, y), median_ratio(x, y), hodges_lehmann(x, y), cohen_d(x, y)] }
pub fn resample_indices(generator: &mut Minstd, size: usize) -> Vec<usize> { (0..size).map(|_| generator.draw_below(size)).collect() }
pub fn ordinary_indices(generator: &mut Minstd, size: usize, count: usize) -> Vec<Vec<usize>> { (0..count).map(|_| resample_indices(generator, size)).collect() }
pub fn balanced_indices(generator: &mut Minstd, size: usize, count: usize) -> Vec<Vec<usize>> {
    let mut indices: Vec<_> = (0..count).flat_map(|_| 0..size).collect(); generator.shuffle(&mut indices); indices.chunks(size).map(<[usize]>::to_vec).collect()
}
pub fn without(values: &[i64], omitted: usize) -> Vec<i64> { values.iter().enumerate().filter_map(|(index, &value)| (index != omitted).then_some(value)).collect() }
pub fn mean_and_se(values: &[f64]) -> (f64, f64) {
    let average = sequential_sum(values.iter().copied()) / values.len() as f64;
    let squares = sequential_sum(values.iter().map(|value| (value - average) * (value - average)));
    (average, (squares / (values.len() - 1) as f64).sqrt())
}
pub fn phi(value: f64) -> f64 {
    if value < 0.0 { return 1.0 - phi(-value); }
    let eta = 1.0 / (1.0 + 0.2316419 * value);
    let psi = eta * (0.319381530 + eta * (-0.356563782 + eta * (1.781477937 + eta * (-1.821255978 + eta * 1.330274429))));
    1.0 - 0.3989422804014327 * (-(value * value) / 2.0).exp() * psi
}
pub fn phi_inverse(probability: f64) -> f64 {
    if probability > 0.5 { return -phi_inverse(1.0 - probability); }
    let eta = (-2.0 * probability.ln()).sqrt();
    let numerator = 2.515517 + eta * (0.802853 + eta * 0.010328);
    let denominator = 1.0 + eta * (1.432788 + eta * (0.189269 + eta * 0.001308));
    -(eta - numerator / denominator)
}
