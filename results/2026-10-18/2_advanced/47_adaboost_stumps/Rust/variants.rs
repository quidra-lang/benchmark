use crate::{adaboost::{Model, Round}, dataset::{Params, Row}, stumps::{self, Search, Stump}};

pub fn train(rows: &[Row], variant: &str, params: &Params) -> Model {
    let search = Search::new(rows);
    let cuts = if variant == "real" { stumps::cuts(rows, params.bins, &search) } else { Vec::new() };
    let n = rows.len();
    let mut weights = vec![1.0 / n as f64; n];
    let mut scores: Vec<f64> = vec![0.0; n];
    let mut probabilities: Vec<f64> = vec![0.5; n];
    let mut bound = 1.0;
    let mut model = Model { rounds: Vec::new(), stop: "completed".into(), cuts };
    for _ in 0..params.rounds {
        let (mut stump, error, z) = if variant == "real" {
            let bins = stumps::bin_weights(rows, &weights, &model.cuts);
            let values: Vec<f64> = bins.iter().map(|b| b.2).collect();
            let feature = stumps::choose(&values);
            let (positive, negative, z) = &bins[feature];
            if *z >= 1.0 - params.convergence {
                model.stop = "converged".into();
                break;
            }
            let outputs = positive.iter().zip(negative).map(|(a, b)| 0.5 * ((a + params.smoothing) / (b + params.smoothing)).ln()).collect();
            (Stump { feature, thresholds: model.cuts[feature].clone(), values: outputs }, 0.0, *z)
        } else {
            let targets: Vec<f64> = if variant == "gentle" {
                rows.iter().map(|r| r.label as f64).collect()
            } else {
                let q: Vec<f64> = probabilities.iter().map(|p| p * (1.0 - p)).collect();
                let total: f64 = q.iter().sum();
                weights = q.iter().map(|q| q / total).collect();
                rows.iter().enumerate().map(|(i, r)| {
                    let target = if r.label == 1 { 1.0 } else { 0.0 };
                    ((target - probabilities[i]) / q[i]).max(-params.clip).min(params.clip)
                }).collect()
            };
            let (stump, error) = stumps::regression(rows, &weights, &targets, &search);
            (stump, error, 0.0)
        };
        if variant == "logit" {
            for value in &mut stump.values { *value /= 2.0; }
        }
        let before = weights.clone();
        let mut loss = 0.0;
        if variant == "logit" {
            for i in 0..n {
                scores[i] += stump.output(&rows[i].values);
                probabilities[i] = 1.0 / (1.0 + (-2.0 * scores[i]).exp());
            }
            loss = rows.iter().enumerate().map(|(i, row)| (1.0 + (-2.0 * row.label as f64 * scores[i]).exp()).ln()).sum::<f64>() / n as f64;
        } else {
            for i in 0..n {
                weights[i] *= (-rows[i].label as f64 * stump.output(&rows[i].values)).exp();
            }
            let total: f64 = weights.iter().sum();
            for w in &mut weights { *w /= total; }
        }
        if variant == "real" { bound *= z; }
        model.rounds.push(Round { stump, polarity: 0, error, alpha: 0.0, z, bound, weights: before, loss });
    }
    model
}
