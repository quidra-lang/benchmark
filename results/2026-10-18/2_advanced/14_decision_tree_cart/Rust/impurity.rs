use std::cmp::Ordering;
use crate::dataset::Row;

#[derive(Clone, Copy)]
pub struct Fraction { pub numerator: i64, pub denominator: i64 }

impl Fraction {
    pub fn compare(self, other: Self) -> Ordering {
        (self.numerator * other.denominator).cmp(&(other.numerator * self.denominator))
    }
    pub fn real(self) -> f64 { self.numerator as f64 / self.denominator as f64 }
}

pub fn class_counts(rows: &[Row], classes: usize) -> Vec<i64> {
    let mut counts = vec![0; classes];
    for row in rows { counts[row.label] += 1; }
    counts
}

pub fn square_sum(counts: &[i64]) -> i64 { counts.iter().map(|count| count * count).sum() }
pub fn majority(counts: &[i64]) -> usize {
    let mut best = 0;
    for index in 1..counts.len() { if counts[index] > counts[best] { best = index; } }
    best
}
pub fn error_count(counts: &[i64]) -> i64 { counts.iter().sum::<i64>() - counts[majority(counts)] }

pub fn evaluation_value(left: &[i64], right: &[i64]) -> Fraction {
    let left_size: i64 = left.iter().sum();
    let right_size: i64 = right.iter().sum();
    Fraction { numerator: square_sum(left) * right_size + square_sum(right) * left_size,
        denominator: left_size * right_size }
}

pub fn improves(value: Fraction, counts: &[i64]) -> bool {
    value.numerator * counts.iter().sum::<i64>() > square_sum(counts) * value.denominator
}

pub fn impurity_decrease(counts: &[i64], left: &[i64], right: &[i64]) -> f64 {
    square_sum(left) as f64 / left.iter().sum::<i64>() as f64
        + square_sum(right) as f64 / right.iter().sum::<i64>() as f64
        - square_sum(counts) as f64 / counts.iter().sum::<i64>() as f64
}
