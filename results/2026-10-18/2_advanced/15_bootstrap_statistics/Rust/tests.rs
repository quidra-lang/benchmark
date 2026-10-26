use std::collections::BTreeMap;
use crate::resampling::{mean, sequential_sum, total};

pub fn position_choices(total: usize, size: usize) -> Vec<Vec<usize>> {
    let mut choice: Vec<_> = (0..size).collect(); let mut result = Vec::new();
    loop {
        result.push(choice.clone());
        let Some(index) = (0..size).rev().find(|&index| choice[index] < total - size + index) else { break; };
        choice[index] += 1;
        for next in index + 1..size { choice[next] = choice[next - 1] + 1; }
    }
    result
}
pub fn reduced_fraction(numerator: i64, denominator: i64) -> (i64, i64) {
    let (mut first, mut second) = (numerator.abs(), denominator);
    while second != 0 { (first, second) = (second, first % second); }
    (numerator / first, denominator / first)
}
pub fn contrast(first_total: i64, first_size: usize, second_total: i64, second_size: usize) -> i64 { second_size as i64 * first_total - first_size as i64 * second_total }
pub fn value_counts(values: &[i64]) -> BTreeMap<i64, usize> { let mut counts = BTreeMap::new(); for &value in values { *counts.entry(value).or_insert(0) += 1; } counts }
pub fn doubled_ranks(values: &[i64]) -> Vec<i64> {
    let mut ranks = BTreeMap::new(); let mut smaller = 0;
    for (value, count) in value_counts(values) { ranks.insert(value, (2 * smaller + count + 1) as i64); smaller += count; }
    values.iter().map(|value| ranks[value]).collect()
}
pub fn split_list<T: Clone>(items: &[T], sizes: &[usize]) -> Vec<Vec<T>> {
    let mut start = 0;
    sizes.iter().map(|&size| { let part = items[start..start + size].to_vec(); start += size; part }).collect()
}
pub fn sums_of_squares(samples: &[Vec<i64>]) -> (f64, f64) {
    let count: usize = samples.iter().map(Vec::len).sum();
    let grand_mean = samples.iter().map(|sample| total(sample)).sum::<i64>() as f64 / (100 * count) as f64;
    let mut between = 0.0; let mut within = 0.0;
    for sample in samples { let center = mean(sample); let deviation = center - grand_mean;
        between += sample.len() as f64 * (deviation * deviation);
        let mut squares = 0.0; for &value in sample { let delta = value as f64 / 100.0 - center; squares += delta * delta; } within += squares; }
    (between, within)
}
pub fn f_statistic(between: f64, within: f64, groups: usize, count: usize) -> f64 { between / (groups - 1) as f64 / (within / (count - groups) as f64) }
pub fn h_statistic(rank_sums: &[i64], sizes: &[usize], correction: f64) -> f64 {
    let count: usize = sizes.iter().sum();
    let sum = sequential_sum(rank_sums.iter().zip(sizes).map(|(&rank, &size)| (rank * rank) as f64 / (4 * size) as f64));
    (12.0 * sum / (count * (count + 1)) as f64 - 3.0 * (count + 1) as f64) / correction
}
