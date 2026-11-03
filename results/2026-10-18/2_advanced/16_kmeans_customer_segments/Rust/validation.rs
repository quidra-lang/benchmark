use std::collections::BTreeMap;
use crate::features::{Point, ordered_sum};
use crate::kmeans::{mean_point, squared_distance};

pub fn distance_table(points: &[Point]) -> Vec<Vec<f64>> {
    let mut table = vec![vec![0.0; points.len()]; points.len()];
    for first in 0..points.len() {
        for second in first + 1..points.len() {
            let distance = squared_distance(&points[first], &points[second]).sqrt();
            table[first][second] = distance;
            table[second][first] = distance;
        }
    }
    table
}
pub fn silhouettes(table: &[Vec<f64>], labels: &[usize], sizes: &[usize]) -> Vec<f64> {
    table.iter().enumerate().map(|(index, row)| {
        let own = labels[index];
        if sizes[own] == 1 { return 0.0; }
        let mut totals = vec![0.0; sizes.len()];
        for (other, &distance) in row.iter().enumerate() { if other != index { totals[labels[other]] += distance; } }
        let inner = totals[own] / (sizes[own] - 1) as f64;
        let mut outer = f64::INFINITY;
        for segment in 0..sizes.len() { if segment != own { outer = outer.min(totals[segment] / sizes[segment] as f64); } }
        let largest = inner.max(outer);
        if largest == 0.0 { 0.0 } else { (outer - inner) / largest }
    }).collect()
}
pub fn calinski_harabasz(points: &[Point], centers: &[Point], sizes: &[usize], within: f64) -> f64 {
    let overall = mean_point(points);
    let mut between = 0.0;
    for (center, &size) in centers.iter().zip(sizes) { between += size as f64 * squared_distance(center, &overall); }
    (between / (centers.len() - 1) as f64) / (within / (points.len() - centers.len()) as f64)
}
pub fn davies_bouldin(points: &[Point], labels: &[usize], centers: &[Point], sizes: &[usize]) -> f64 {
    let k = centers.len();
    let mut spreads = vec![0.0; k];
    for (point, &label) in points.iter().zip(labels) { spreads[label] += squared_distance(point, &centers[label]).sqrt(); }
    for (spread, &size) in spreads.iter_mut().zip(sizes) { *spread /= size as f64; }
    let mut worsts = Vec::new();
    for first in 0..k {
        let mut worst = f64::NEG_INFINITY;
        for second in 0..k {
            if first != second { worst = worst.max((spreads[first] + spreads[second]) / squared_distance(&centers[first], &centers[second]).sqrt()); }
        }
        worsts.push(worst);
    }
    ordered_sum(&worsts) / k as f64
}
pub fn elbow(k: usize, minimum: usize, maximum: usize, within: f64, first: f64, last: f64) -> f64 {
    let x = (k - minimum) as f64 / (maximum - minimum) as f64;
    let y = (within - last) / (first - last);
    ((1.0 - x) - y) / 2.0f64.sqrt()
}
pub fn hartigan(within: f64, next: f64, count: usize, k: usize) -> f64 { (within / next - 1.0) * (count - k - 1) as f64 }
fn pair_count(size: i64) -> i64 { size * (size - 1) / 2 }
pub fn adjusted_rand_index<A: Ord + Clone, B: Ord + Clone>(first: &[A], second: &[B]) -> f64 {
    let mut joint = BTreeMap::new();
    let mut first_sizes = BTreeMap::new();
    let mut second_sizes = BTreeMap::new();
    for (a, b) in first.iter().zip(second) {
        *joint.entry((a.clone(), b.clone())).or_insert(0i64) += 1;
        *first_sizes.entry(a.clone()).or_insert(0i64) += 1;
        *second_sizes.entry(b.clone()).or_insert(0i64) += 1;
    }
    let total = pair_count(first.len() as i64);
    let shared: i64 = joint.values().map(|&size| pair_count(size)).sum();
    let first_pairs: i64 = first_sizes.values().map(|&size| pair_count(size)).sum();
    let second_pairs: i64 = second_sizes.values().map(|&size| pair_count(size)).sum();
    let numerator = 2 * (total * shared - first_pairs * second_pairs);
    let denominator = total * (first_pairs + second_pairs) - 2 * first_pairs * second_pairs;
    if denominator == 0 { 1.0 } else { numerator as f64 / denominator as f64 }
}
