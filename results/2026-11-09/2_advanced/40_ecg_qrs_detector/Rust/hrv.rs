use crate::report::rdiv;
use std::collections::BTreeMap;

pub fn isqrt(value: i64) -> i64 {
    let (mut low, mut high) = (0, value + 1);
    while high - low > 1 {
        let middle = (low + high) / 2;
        if middle <= value / middle { low = middle; } else { high = middle; }
    }
    low
}

pub fn root(numerator: i64, denominator: i64) -> i64 { (isqrt(40000 * numerator / denominator) + 1) / 2 }

pub fn mean(values: &[i64]) -> Option<i64> {
    if values.is_empty() { None } else { Some(rdiv(100 * values.iter().sum::<i64>(), values.len() as i64)) }
}

pub fn heart_rate(values: &[i64]) -> Option<i64> {
    if values.is_empty() { None } else { Some(rdiv(6000000 * values.len() as i64, values.iter().sum())) }
}

pub fn deviation(values: &[i64], factor: i64) -> Option<i64> {
    let n = values.len() as i64;
    if n < 2 { return None; }
    let sum = values.iter().sum::<i64>();
    Some(root(n * values.iter().map(|v| v * v).sum::<i64>() - sum * sum, factor * n * (n - 1)))
}

pub fn histogram(values: &[i64]) -> BTreeMap<i64, usize> {
    let mut bins = BTreeMap::new();
    for &value in values { *bins.entry(16 * value / 125).or_default() += 1; }
    bins
}

pub fn ranges<T>(items: &[T], predicate: impl Fn(&T) -> bool) -> Vec<(usize, usize)> {
    let mut output = Vec::new();
    let mut i = 0;
    while i < items.len() {
        if !predicate(&items[i]) { i += 1; continue; }
        let start = i;
        while i + 1 < items.len() && predicate(&items[i + 1]) { i += 1; }
        output.push((start, i));
        i += 1;
    }
    output
}
