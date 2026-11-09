use crate::dataset::Subject;
use crate::numerics::{p_value, solve, Matrix};
use std::collections::BTreeSet;

pub struct Test {
    pub groups: Vec<usize>,
    pub events: Vec<usize>,
    pub observed: Vec<f64>,
    pub expected: Vec<f64>,
    pub covariance: Matrix,
    pub statistic: f64,
    pub p: f64,
}

impl Test {
    pub fn empty(groups: &[usize]) -> Self {
        let k = groups.len();
        Self { groups: groups.to_vec(), events: vec![0; k], observed: vec![0.0; k], expected: vec![0.0; k], covariance: vec![vec![0.0; k]; k], statistic: 0.0, p: 1.0 }
    }
    pub fn add(&mut self, other: &Self) {
        for i in 0..self.groups.len() {
            self.events[i] += other.events[i];
            self.observed[i] += other.observed[i];
            self.expected[i] += other.expected[i];
            for j in 0..self.groups.len() { self.covariance[i][j] += other.covariance[i][j]; }
        }
    }
    pub fn finish(&mut self) {
        let n = self.groups.len() - 1;
        let matrix = self.covariance[..n].iter().map(|row| row[..n].to_vec()).collect();
        let u: Vec<_> = (0..n).map(|i| self.observed[i] - self.expected[i]).collect();
        let x = solve(&matrix, &u);
        self.statistic = u.iter().zip(x).fold(0.0, |total, (&u, x)| total + u * x);
        self.p = p_value(self.statistic, n);
    }
}

pub fn weighted(subjects: &[Subject], groups: &[usize], kind: &str, total_subjects: usize) -> Test {
    let mut result = Test::empty(groups);
    let times: BTreeSet<_> = subjects.iter().filter(|s| s.event).map(|s| s.time).collect();
    for time in times {
        let risk: Vec<_> = groups.iter().map(|&g| subjects.iter().filter(|s| s.group == g && s.time >= time).count() as i64).collect();
        let events: Vec<_> = groups.iter().map(|&g| subjects.iter().filter(|s| s.group == g && s.time == time && s.event).count() as i64).collect();
        let n = risk.iter().sum::<i64>();
        let d = events.iter().sum::<i64>();
        let weight = match kind { "gehan_wilcoxon" => n as f64 / total_subjects as f64, "tarone_ware" => (n as f64 / total_subjects as f64).sqrt(), _ => 1.0 };
        for h in 0..groups.len() {
            result.events[h] += events[h] as usize;
            result.observed[h] += weight * events[h] as f64;
            result.expected[h] += weight * ((d * risk[h]) as f64 / n as f64);
            if n >= 2 {
                let factor = (d * (n - d)) as f64 / ((n - 1) * n * n) as f64;
                for l in 0..groups.len() {
                    let m = if h == l { risk[h] * (n - risk[h]) } else { -(risk[h] * risk[l]) };
                    result.covariance[h][l] += weight * weight * factor * m as f64;
                }
            }
        }
    }
    result.finish();
    result
}
