use std::collections::BTreeMap;

use crate::scoring::letter_value;

pub fn letter_counts(text: &str) -> [usize; 26] {
    let mut counts = [0; 26];
    for byte in text.bytes() {
        counts[letter_value(byte)] += 1;
    }
    counts
}

pub fn index_of_coincidence(text: &str) -> i64 {
    let length = text.len() as i64;
    if length < 2 {
        return 0;
    }
    let sum: i64 = letter_counts(text).iter().map(|&count| {
        let count = count as i64;
        count * (count - 1)
    }).sum();
    100000 * sum / (length * (length - 1))
}

pub fn columns(text: &str, period: usize) -> Vec<String> {
    let mut columns = vec![String::new(); period];
    for (index, byte) in text.bytes().enumerate() {
        columns[index % period].push(byte as char);
    }
    columns
}

pub fn column_indices(text: &str, period: usize) -> Vec<i64> {
    columns(text, period).iter().map(|column| index_of_coincidence(column)).collect()
}

pub struct Repeat {
    pub trigram: String,
    pub positions: Vec<usize>,
    pub gaps: Vec<usize>,
    pub gcd: usize,
}

fn gcd(mut a: usize, mut b: usize) -> usize {
    while b != 0 {
        (a, b) = (b, a % b);
    }
    a
}

pub fn repeated_trigrams(text: &str) -> Vec<Repeat> {
    let mut positions: BTreeMap<String, Vec<usize>> = BTreeMap::new();
    for (index, trigram) in text.as_bytes().windows(3).enumerate() {
        positions.entry(String::from_utf8(trigram.to_vec()).unwrap()).or_default().push(index + 1);
    }
    positions.into_iter().filter_map(|(trigram, positions)| {
        if positions.len() < 2 {
            return None;
        }
        let gaps: Vec<usize> = positions.windows(2).map(|pair| pair[1] - pair[0]).collect();
        let divisor = gaps.iter().copied().fold(0, gcd);
        Some(Repeat { trigram, positions, gaps, gcd: divisor })
    }).collect()
}

pub fn percentage(count: usize, total: usize) -> String {
    let value = (2000 * count + total) / (2 * total);
    format!("{}.{}", value / 10, value % 10)
}

pub fn pair_counts(text: &str, step: usize) -> Vec<(String, usize)> {
    let mut counts = BTreeMap::new();
    for pair in text.as_bytes().windows(2).step_by(step) {
        *counts.entry(String::from_utf8(pair.to_vec()).unwrap()).or_insert(0) += 1;
    }
    let mut entries: Vec<(String, usize)> = counts.into_iter().collect();
    entries.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
    entries
}
