use std::collections::BTreeSet;

pub fn clip(value: f64) -> f64 {
    value.max(1.0).min(5.0)
}

pub fn rmse(errors: &[f64]) -> f64 {
    (errors.iter().map(|x| x * x).sum::<f64>() / errors.len() as f64).sqrt()
}

pub fn mae(errors: &[f64]) -> f64 {
    errors.iter().map(|x| x.abs()).sum::<f64>() / errors.len() as f64
}

pub fn weight(rank: usize) -> f64 {
    1.0 / ((rank + 1) as f64).log2()
}

pub struct Ranking {
    pub hits: usize,
    pub recall: f64,
    pub ndcg: f64,
    pub ap: f64,
    pub rr: f64,
}

pub fn ranking(list: &[usize], relevant: &BTreeSet<usize>, c: usize) -> Ranking {
    let mut hits = 0;
    let (mut dcg, mut ap, mut rr) = (0.0, 0.0, 0.0);
    for (index, item) in list.iter().take(c).enumerate() {
        if relevant.contains(item) {
            hits += 1;
            let rank = index + 1;
            dcg += weight(rank);
            ap += hits as f64 / rank as f64;
            if rr == 0.0 {
                rr = 1.0 / rank as f64;
            }
        }
    }
    let d = c.min(relevant.len());
    let ideal: f64 = (1..=d).map(weight).sum();
    Ranking { hits, recall: hits as f64 / relevant.len() as f64, ndcg: dcg / ideal, ap: ap / d as f64, rr }
}
