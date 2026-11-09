use crate::dataset::Row;

#[derive(Clone, Copy)]
pub struct Fraction {
    pub numerator: i64,
    pub denominator: i64,
}

impl Fraction {
    pub fn new(mut numerator: i64, mut denominator: i64) -> Self {
        if denominator < 0 { numerator = -numerator; denominator = -denominator; }
        let (mut a, mut b) = (numerator.abs(), denominator);
        while b != 0 { (a, b) = (b, a % b); }
        Self { numerator: numerator / a, denominator: denominator / a }
    }

    pub fn add(self, other: Self) -> Self {
        Self::new(self.numerator * other.denominator + other.numerator * self.denominator, self.denominator * other.denominator)
    }
}

pub struct Evaluation {
    pub confusion: Vec<Vec<usize>>,
    pub support: Vec<usize>,
    pub predicted: Vec<usize>,
    pub correct: usize,
    pub accuracy: Fraction,
    pub balanced: Fraction,
    pub kappa: Fraction,
    pub macro_f1: f64,
}

pub fn evaluate(rows: &[Row], predictions: &[usize], classes: usize) -> Evaluation {
    let mut confusion = vec![vec![0; classes]; classes];
    for (row, &prediction) in rows.iter().zip(predictions) { confusion[row.class][prediction] += 1; }
    let support: Vec<_> = confusion.iter().map(|row| row.iter().sum()).collect();
    let predicted: Vec<_> = (0..classes).map(|k| confusion.iter().map(|row| row[k]).sum()).collect();
    let correct = (0..classes).map(|k| confusion[k][k]).sum();
    let mut balanced = Fraction::new(0, 1);
    let mut macro_f1 = 0.0;
    for k in 0..classes {
        balanced = balanced.add(Fraction::new(confusion[k][k] as i64, support[k] as i64));
        macro_f1 += 2.0 * confusion[k][k] as f64 / (support[k] + predicted[k]) as f64;
    }
    balanced = Fraction::new(balanced.numerator, balanced.denominator * classes as i64);
    macro_f1 /= classes as f64;
    let expected: i64 = (0..classes).map(|k| (support[k] * predicted[k]) as i64).sum();
    let n = rows.len() as i64;
    Evaluation { confusion, support, predicted, correct, accuracy: Fraction::new(correct as i64, n), balanced, kappa: Fraction::new(n * correct as i64 - expected, n * n - expected), macro_f1 }
}

pub fn mcnemar(rows: &[Row], a: &[usize], b: &[usize]) -> (usize, usize, f64) {
    let mut b01 = 0;
    let mut b10 = 0;
    for ((row, &a), &b) in rows.iter().zip(a).zip(b) {
        if a == row.class && b != row.class { b01 += 1; }
        if a != row.class && b == row.class { b10 += 1; }
    }
    let chi = if b01 == b10 { 0.0 } else { let difference = (b01 as i64 - b10 as i64).abs() - 1; (difference * difference) as f64 / (b01 + b10) as f64 };
    (b01, b10, chi)
}

pub struct Random(pub i64);
impl Random {
    pub fn next(&mut self) -> i64 { self.0 = 48271 * self.0 % 2147483647; self.0 }
}
