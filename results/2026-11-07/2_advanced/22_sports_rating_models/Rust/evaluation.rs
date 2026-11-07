use crate::report::Fraction;

pub fn sigma(value: f64) -> f64 { 1.0 / (1.0 + (-value).exp()) }
pub fn fit_link(features: &[f64], results: &[f64], iterations: usize) -> (f64, f64) {
    let (mut alpha, mut beta) = (0.0, 0.0);
    for _ in 0..iterations {
        let (mut g0, mut g1, mut h00, mut h01, mut h11) = (0.0, 0.0, 0.0, 0.0, 0.0);
        for (&z, &y) in features.iter().zip(results) {
            let p = sigma(alpha + beta * z);
            let w = p * (1.0 - p);
            g0 += y - p; g1 += (y - p) * z; h00 += w; h01 += w * z; h11 += w * z * z;
        }
        let determinant = h00 * h11 - h01 * h01;
        alpha += (h11 * g0 - h01 * g1) / determinant; beta += (h00 * g1 - h01 * g0) / determinant;
    }
    (alpha, beta)
}
pub fn log_loss(probability: f64, result_twice: i64) -> f64 {
    match result_twice { 2 => -probability.ln(), 0 => -(1.0 - probability).ln(), _ => -(probability.ln() / 2.0 + (1.0 - probability).ln() / 2.0) }
}
pub fn brier_score(probability: f64, result_twice: i64) -> f64 { let difference = probability - result_twice as f64 / 2.0; difference * difference }
pub fn correctness_twice(probability: f64, result_twice: i64) -> i64 {
    if result_twice == 1 { 1 } else if probability > 0.5 && result_twice == 2 || probability < 0.5 && result_twice == 0 { 2 } else { 0 }
}
fn doubled_average_ranks(values: &[Fraction]) -> Vec<i64> {
    values.iter().map(|value| { let greater = values.iter().filter(|&other| other > value).count() as i64;
        let equal = values.iter().filter(|&other| other == value).count() as i64; 2 * greater + equal + 1 }).collect()
}
pub fn kendall_tau(first: &[Fraction], second: &[Fraction]) -> Fraction {
    let mut signed = 0i64;
    for team in 0..first.len() { for other in team + 1..first.len() {
        let first = first[team].cmp(&first[other]) as i8;
        let second = second[team].cmp(&second[other]) as i8;
        signed += (first * second) as i64;
    } }
    Fraction::new(signed, (first.len() * (first.len() - 1) / 2) as i64)
}
pub fn spearman_rho(first: &[Fraction], second: &[Fraction]) -> Fraction {
    let first_ranks = doubled_average_ranks(first);
    let second_ranks = doubled_average_ranks(second);
    let mut squares = 0;
    for (a, b) in first_ranks.into_iter().zip(second_ranks) { squares += (a - b) * (a - b); }
    let count = first.len() as i64;
    Fraction::integer(1) - Fraction::new(6 * squares, 4 * count * (count * count - 1))
}
