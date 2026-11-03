use std::collections::{BTreeMap, BTreeSet};
use crate::{dataset::Rows, neighbors::{distance, sort_neighbors, Neighbor, Prediction}, report::four_decimal, scaling::Scaling};

#[derive(Clone)]
pub struct Model {
    pub k: usize,
    pub metric: String,
    pub weighting: String,
    pub scaling: String,
}
impl Model {
    pub fn notation(&self) -> String { format!("k={} metric={} weighting={} scaling={}", self.k, self.metric, self.weighting, self.scaling) }
}
pub fn stratified_folds(rows: &Rows, count: usize) -> Vec<Vec<usize>> {
    let mut ordered: Vec<_> = (0..rows.len()).collect();
    ordered.sort_by(|&a, &b| rows[a].label.cmp(&rows[b].label).then_with(|| rows[a].id.cmp(&rows[b].id)));
    let mut folds = vec![Vec::new(); count]; for (j, index) in ordered.into_iter().enumerate() { folds[j % count].push(index); }
    for fold in &mut folds { fold.sort_unstable(); } folds
}
pub fn training_rows(rows: &Rows, fold: &[usize]) -> Rows {
    let excluded: BTreeSet<_> = fold.iter().copied().collect();
    rows.iter().enumerate().filter(|(j, _)| !excluded.contains(j)).map(|(_, row)| row.clone()).collect()
}
pub fn neighbor_orders(training: &Rows, queries: &Rows, method: &str, metric: &str, features: &[usize]) -> Vec<Vec<Neighbor>> {
    let scaling = Scaling::fit(training, method);
    let references: Vec<_> = training.iter().map(|row| (scaling.transform(&row.values, features), row)).collect();
    queries.iter().map(|query| {
        let vector = scaling.transform(&query.values, features);
        sort_neighbors(references.iter().map(|(reference, row)| Neighbor { gap: distance(&vector, reference, metric), row: (*row).clone() }).collect())
    }).collect()
}
pub fn predict_rows(model: &Model, training: &Rows, queries: &Rows, features: &[usize]) -> Vec<Prediction> {
    neighbor_orders(training, queries, &model.scaling, &model.metric, features).iter().map(|order| Prediction::from_order(order, model.k, &model.weighting, true)).collect()
}
pub fn rmse(errors: &[f64]) -> f64 { let mut sum = 0.0; for error in errors { sum += error * error; } (sum / errors.len() as f64).sqrt() }
pub fn mae(errors: &[f64]) -> f64 { let mut sum = 0.0; for error in errors { sum += error.abs(); } sum / errors.len() as f64 }
pub fn r_squared(errors: &[f64], targets: &[f64]) -> f64 {
    let mut sum = 0.0; for target in targets { sum += target; } let mean = sum / targets.len() as f64;
    let mut residual = 0.0; for error in errors { residual += error * error; }
    let mut spread = 0.0; for target in targets { let difference = target - mean; spread += difference * difference; }
    1.0 - residual / spread
}
pub fn correct_count(predictions: &[Prediction], rows: &Rows) -> usize {
    predictions.iter().zip(rows).filter(|(p, row)| Some(p.label.as_str()) == row.label.as_deref()).count()
}
pub struct CrossValidation {
    pub model: Model,
    pub predictions: Vec<Prediction>,
    pub hits: Vec<bool>,
    pub correct: usize,
    pub rmse: f64,
}
pub fn cross_validate(models: &[Model], rows: &Rows, count: usize, features: &[usize]) -> Vec<CrossValidation> {
    let mut predictions = vec![vec![None; rows.len()]; models.len()]; let mut spaces = BTreeMap::<(&str, &str), Vec<usize>>::new();
    for (j, model) in models.iter().enumerate() { spaces.entry((&model.scaling, &model.metric)).or_default().push(j); }
    for fold in stratified_folds(rows, count) {
        let training = training_rows(rows, &fold); let queries = fold.iter().map(|&j| rows[j].clone()).collect();
        for (&(method, metric), indices) in &spaces {
            let orders = neighbor_orders(&training, &queries, method, metric, features);
            for &j in indices { for (&index, order) in fold.iter().zip(&orders) { predictions[j][index] = Some(Prediction::from_order(order, models[j].k, &models[j].weighting, false)); } }
        }
    }
    models.iter().zip(predictions).map(|(model, predictions)| {
        let predictions: Vec<_> = predictions.into_iter().map(Option::unwrap).collect();
        let hits: Vec<_> = predictions.iter().zip(rows).map(|(p, row)| Some(p.label.as_str()) == row.label.as_deref()).collect();
        let correct = hits.iter().filter(|&&hit| hit).count(); let errors: Vec<_> = predictions.iter().zip(rows).map(|(p, row)| p.estimate - row.target.unwrap()).collect();
        CrossValidation { model: model.clone(), predictions, hits, correct, rmse: rmse(&errors) }
    }).collect()
}
pub fn best_classifier(results: &[CrossValidation]) -> usize {
    let mut best = 0; for j in 1..results.len() { if results[j].correct > results[best].correct { best = j; } } best
}
pub fn best_regressor(results: &[CrossValidation]) -> usize {
    let mut best = 0; for j in 1..results.len() { if four_decimal(results[j].rmse) < four_decimal(results[best].rmse) { best = j; } } best
}
