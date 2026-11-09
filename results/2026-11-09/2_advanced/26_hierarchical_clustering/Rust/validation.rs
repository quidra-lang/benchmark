use crate::distances::sequential_sum;

#[derive(Clone, Copy)]
pub struct Fraction { pub numerator: i64, pub denominator: i64 }

impl Fraction {
    pub fn value(self) -> f64 { self.numerator as f64 / self.denominator as f64 }
    pub fn greater(self, other: Self) -> bool { self.numerator * other.denominator > other.numerator * self.denominator }
}

pub fn correlation(first: &[f64], second: &[f64]) -> f64 {
    let mean_a = sequential_sum(first.iter().copied()) / first.len() as f64;
    let mean_b = sequential_sum(second.iter().copied()) / second.len() as f64;
    let cross = sequential_sum(first.iter().zip(second).map(|(a, b)| (a - mean_a) * (b - mean_b)));
    let spread_a = sequential_sum(first.iter().map(|a| (a - mean_a) * (a - mean_a)));
    let spread_b = sequential_sum(second.iter().map(|b| (b - mean_b) * (b - mean_b)));
    cross / (spread_a * spread_b).sqrt()
}

pub fn contingency_table(first: &[usize], second: &[usize], rows: usize, columns: usize) -> Vec<Vec<i64>> {
    let mut table = vec![vec![0; columns]; rows];
    for (&a, &b) in first.iter().zip(second) { table[a][b] += 1; }
    table
}

fn pair_count(count: i64) -> i64 { count * (count - 1) / 2 }

pub fn adjusted_rand_index(table: &[Vec<i64>]) -> Fraction {
    let count: i64 = table.iter().map(|row| row.iter().sum::<i64>()).sum();
    let same: i64 = table.iter().flat_map(|row| row.iter()).map(|&cell| pair_count(cell)).sum();
    let row_pairs: i64 = table.iter().map(|row| pair_count(row.iter().sum())).sum();
    let column_pairs: i64 = (0..table[0].len()).map(|column| pair_count(table.iter().map(|row| row[column]).sum())).sum();
    let total = pair_count(count);
    let mut numerator = 2 * (total * same - row_pairs * column_pairs);
    let mut denominator = total * (row_pairs + column_pairs) - 2 * row_pairs * column_pairs;
    if denominator == 0 { return Fraction { numerator: 1, denominator: 1 }; }
    if denominator < 0 { numerator = -numerator; denominator = -denominator; }
    let (mut a, mut b) = (numerator.abs(), denominator);
    while b != 0 { (a, b) = (b, a % b); }
    Fraction { numerator: numerator / a, denominator: denominator / a }
}

pub fn silhouette_values(partition: &[usize], groups: usize, delta: &[Vec<f64>]) -> Vec<f64> {
    let mut sizes = vec![0; groups + 1];
    for &number in partition { sizes[number] += 1; }
    let mut values = Vec::new();
    for (i, &own) in partition.iter().enumerate() {
        if sizes[own] == 1 { values.push(0.0); continue; }
        let mut sums = vec![0.0; groups + 1];
        for (j, &other) in partition.iter().enumerate() { if j != i { sums[other] += delta[i][j]; } }
        let inner = sums[own] / (sizes[own] - 1) as f64;
        let mut outer = f64::INFINITY;
        for g in 1..=groups { if g != own { outer = outer.min(sums[g] / sizes[g] as f64); } }
        values.push((outer - inner) / inner.max(outer));
    }
    values
}
