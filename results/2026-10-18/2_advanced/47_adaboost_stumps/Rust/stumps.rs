use crate::dataset::Row;

#[derive(Clone)]
pub struct Stump {
    pub feature: usize,
    pub thresholds: Vec<f64>,
    pub values: Vec<f64>,
}

impl Stump {
    pub fn output(&self, x: &[f64]) -> f64 {
        let bin = self.thresholds.iter().filter(|&&t| x[self.feature] > t).count();
        self.values[bin]
    }

    pub fn magnitude(&self) -> f64 {
        self.values.iter().map(|x| x.abs()).fold(0.0, f64::max)
    }
}

pub struct Search {
    pub orders: Vec<Vec<usize>>,
    pub thresholds: Vec<Vec<f64>>,
}

impl Search {
    pub fn new(rows: &[Row]) -> Self {
        let d = rows[0].values.len();
        let mut orders = Vec::new();
        let mut thresholds = Vec::new();
        for j in 0..d {
            let mut order: Vec<usize> = (0..rows.len()).collect();
            order.sort_by(|&a, &b| rows[a].values[j].partial_cmp(&rows[b].values[j]).unwrap().then(a.cmp(&b)));
            let mut distinct: Vec<f64> = order.iter().map(|&i| rows[i].values[j]).collect();
            distinct.dedup();
            let mut candidates = vec![distinct[0] - 1.0];
            candidates.extend(distinct.windows(2).map(|w| (w[0] + w[1]) / 2.0));
            orders.push(order);
            thresholds.push(candidates);
        }
        Self { orders, thresholds }
    }

    pub fn prefix(&self, rows: &[Row], feature: usize, values: &[f64]) -> Vec<f64> {
        let order = &self.orders[feature];
        let mut prefix = vec![0.0];
        let mut sum = 0.0;
        for t in 0..order.len() - 1 {
            sum += values[order[t]];
            if rows[order[t]].values[feature] != rows[order[t + 1]].values[feature] {
                prefix.push(sum);
            }
        }
        prefix
    }
}

pub fn choose(values: &[f64]) -> usize {
    let minimum = values.iter().copied().fold(f64::INFINITY, f64::min);
    values.iter().position(|&value| value <= minimum + 0.000000001).unwrap()
}

pub fn discrete(rows: &[Row], weights: &[f64], search: &Search) -> (Stump, f64, i32) {
    let positive: Vec<f64> = rows.iter().zip(weights).map(|(r, &w)| if r.label == 1 { w } else { 0.0 }).collect();
    let negative: Vec<f64> = rows.iter().zip(weights).map(|(r, &w)| if r.label == -1 { w } else { 0.0 }).collect();
    let wp: f64 = positive.iter().sum();
    let wn: f64 = negative.iter().sum();
    let mut candidates = Vec::new();
    let mut errors = Vec::new();
    for j in 0..search.orders.len() {
        let lp = search.prefix(rows, j, &positive);
        let ln = search.prefix(rows, j, &negative);
        for h in 0..search.thresholds[j].len() {
            for s in [1, -1] {
                candidates.push((j, h, s));
                errors.push(if s == 1 { lp[h] + (wn - ln[h]) } else { ln[h] + (wp - lp[h]) });
            }
        }
    }
    let best = choose(&errors);
    let (j, h, s) = candidates[best];
    (Stump { feature: j, thresholds: vec![search.thresholds[j][h]], values: vec![-s as f64, s as f64] }, errors[best], s)
}

pub fn regression(rows: &[Row], weights: &[f64], targets: &[f64], search: &Search) -> (Stump, f64) {
    let w: f64 = weights.iter().sum();
    let products: Vec<f64> = weights.iter().zip(targets).map(|(w, r)| w * r).collect();
    let s: f64 = products.iter().sum();
    let q: f64 = weights.iter().zip(targets).map(|(w, r)| w * r * r).sum();
    let mut candidates = Vec::new();
    let mut errors = Vec::new();
    for j in 0..search.orders.len() {
        let wl = search.prefix(rows, j, weights);
        let sl = search.prefix(rows, j, &products);
        for h in 0..search.thresholds[j].len() {
            let wr = w - wl[h];
            let sr = s - sl[h];
            let left = if h == 0 { 0.0 } else { sl[h] / wl[h] };
            let right = sr / wr;
            let gain = if h == 0 { sr * sr / wr } else { sl[h] * sl[h] / wl[h] + sr * sr / wr };
            candidates.push(Stump { feature: j, thresholds: vec![search.thresholds[j][h]], values: vec![left, right] });
            errors.push(q - gain);
        }
    }
    let index = choose(&errors);
    (candidates[index].clone(), errors[index])
}

pub fn multiclass(rows: &[Row], weights: &[f64], search: &Search, classes: usize) -> (Stump, f64) {
    let total: f64 = weights.iter().sum();
    let mut totals = Vec::new();
    let mut class_weights = Vec::new();
    for class in 1..=classes {
        let values: Vec<f64> = rows.iter().zip(weights).map(|(r, &w)| if r.label as usize == class { w } else { 0.0 }).collect();
        totals.push(values.iter().sum::<f64>());
        class_weights.push(values);
    }
    let mut candidates = Vec::new();
    let mut errors = Vec::new();
    for j in 0..search.orders.len() {
        let lefts: Vec<Vec<f64>> = class_weights.iter().map(|w| search.prefix(rows, j, w)).collect();
        for h in 0..search.thresholds[j].len() {
            let mut a = 0;
            let mut b = 0;
            for class in 1..classes {
                if lefts[class][h] > lefts[a][h] { a = class; }
                if totals[class] - lefts[class][h] > totals[b] - lefts[b][h] { b = class; }
            }
            errors.push(total - (lefts[a][h] + (totals[b] - lefts[b][h])));
            candidates.push(Stump { feature: j, thresholds: vec![search.thresholds[j][h]], values: vec![(a + 1) as f64, (b + 1) as f64] });
        }
    }
    let index = choose(&errors);
    (candidates[index].clone(), errors[index])
}

pub fn cuts(rows: &[Row], bins: usize, search: &Search) -> Vec<Vec<f64>> {
    search.orders.iter().enumerate().map(|(j, order)| (1..bins).map(|b| {
        let r = b * rows.len() / bins;
        (rows[order[r - 1]].values[j] + rows[order[r]].values[j]) / 2.0
    }).collect()).collect()
}

pub fn bin_weights(rows: &[Row], weights: &[f64], cuts: &[Vec<f64>]) -> Vec<(Vec<f64>, Vec<f64>, f64)> {
    cuts.iter().enumerate().map(|(j, thresholds)| {
        let mut positive = vec![0.0; thresholds.len() + 1];
        let mut negative = positive.clone();
        for (row, &w) in rows.iter().zip(weights) {
            let bin = thresholds.iter().filter(|&&t| row.values[j] > t).count();
            if row.label == 1 { positive[bin] += w; } else { negative[bin] += w; }
        }
        let z = 2.0 * positive.iter().zip(&negative).map(|(a, b)| (a * b).sqrt()).sum::<f64>();
        (positive, negative, z)
    }).collect()
}
