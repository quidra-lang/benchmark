use crate::dataset::CONSTANTS;

pub struct Subgroup {
    pub values: Vec<i64>,
    pub total: i64,
    pub range: i64,
    pub mean: f64,
    pub sd: f64,
}

#[derive(Clone, Copy, Default)]
pub struct Limits { pub lcl: f64, pub cl: f64, pub ucl: f64 }

impl Limits {
    pub fn new(lcl: f64, cl: f64, ucl: f64) -> Self { Self { lcl, cl, ucl } }
    pub fn outside(self, value: f64) -> bool { value < self.lcl || value > self.ucl }
}

pub fn real_sum(values: impl IntoIterator<Item = f64>) -> f64 { values.into_iter().fold(0.0, |sum, value| sum + value) }

pub fn subgroup_statistics(values: &[i64], size: usize) -> Vec<Subgroup> {
    values.chunks(size).map(|points| {
        let n = size as i64;
        let total: i64 = points.iter().sum();
        let squares: i64 = points.iter().map(|x| x * x).sum();
        Subgroup { values: points.to_vec(), total, range: points.iter().max().unwrap() - points.iter().min().unwrap(), mean: total as f64 / n as f64, sd: ((n * squares - total * total) as f64 / (n * (n - 1)) as f64).sqrt() }
    }).collect()
}

pub fn moving_ranges(values: &[i64]) -> Vec<i64> { values.windows(2).map(|p| (p[1] - p[0]).abs()).collect() }

pub fn variable_limits(family: usize, points: &[usize], groups: &[Subgroup], values: &[i64], size: usize) -> [Limits; 2] {
    if family == 2 {
        let selected: Vec<i64> = points.iter().map(|&i| values[i - 1]).collect();
        let ranges = moving_ranges(&selected);
        let mean = selected.iter().sum::<i64>() as f64 / selected.len() as f64;
        let average = ranges.iter().sum::<i64>() as f64 / ranges.len() as f64;
        let width = 3.0 * average / CONSTANTS[0][6];
        return [Limits::new(mean - width, mean, mean + width), Limits::new(CONSTANTS[0][4] * average, average, CONSTANTS[0][5] * average)];
    }
    let c = CONSTANTS[size - 2];
    let mean = points.iter().map(|&i| groups[i - 1].total).sum::<i64>() as f64 / (points.len() * size) as f64;
    if family == 0 {
        let average = points.iter().map(|&i| groups[i - 1].range).sum::<i64>() as f64 / points.len() as f64;
        [Limits::new(mean - c[0] * average, mean, mean + c[0] * average), Limits::new(c[4] * average, average, c[5] * average)]
    } else {
        let average = real_sum(points.iter().map(|&i| groups[i - 1].sd)) / points.len() as f64;
        [Limits::new(mean - c[1] * average, mean, mean + c[1] * average), Limits::new(c[2] * average, average, c[3] * average)]
    }
}
