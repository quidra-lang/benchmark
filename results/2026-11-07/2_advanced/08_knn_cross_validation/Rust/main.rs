mod dataset;
mod scaling;
mod neighbors;
mod validation;
mod report;

use std::{collections::{BTreeMap, BTreeSet}, fs, rc::Rc};
use dataset::{read_rows, Row, Rows, Settings};
use neighbors::{distance, sort_neighbors, Neighbor, Prediction};
use report::{fixed, four_decimal, fraction, join_parts, ratio, write_lines};
use scaling::Scaling;
use validation::{best_classifier, best_regressor, correct_count, cross_validate, mae, neighbor_orders, predict_rows, r_squared, rmse, stratified_folds, training_rows, CrossValidation, Model};

fn real(value: f64) -> String { fixed(value, 4) }
fn id_order(rows: &Rows) -> Rows { let mut ordered = rows.clone(); ordered.sort_by(|a, b| a.id.cmp(&b.id)); ordered }
fn label_counts(rows: &Rows, labels: &[String]) -> String {
    let mut counts = BTreeMap::<&str, usize>::new();
    for row in rows { *counts.entry(row.label.as_deref().unwrap()).or_default() += 1; }
    labels.iter().map(|label| format!("{label} {}", counts.get(label.as_str()).unwrap_or(&0))).collect::<Vec<_>>().join(" ")
}
fn evaluation_lines(pairs: &[(String, String)], labels: &[String]) -> Vec<String> {
    let mut matrix = vec![vec![0usize; labels.len()]; labels.len()];
    for (truth, predicted) in pairs { matrix[labels.binary_search(truth).unwrap()][labels.binary_search(predicted).unwrap()] += 1; }
    let mut lines = vec![format!("true\\predicted {}", labels.join(" "))];
    for (j, label) in labels.iter().enumerate() { lines.push(format!("{label} {}", matrix[j].iter().map(usize::to_string).collect::<Vec<_>>().join(" "))); }
    let mut totals = [0.0; 3]; let mut valued = [0usize; 3];
    for (j, label) in labels.iter().enumerate() {
        let hits = matrix[j][j]; let predicted: usize = matrix.iter().map(|row| row[j]).sum(); let actual: usize = matrix[j].iter().sum();
        for (p, (a, b)) in [(hits, predicted), (hits, actual), (2 * hits, predicted + actual)].iter().copied().enumerate() {
            if b > 0 { totals[p] += a as f64 / b as f64; valued[p] += 1; }
        }
        lines.push(format!("class {label} precision {} recall {} f1 {} support {actual}", fraction(hits, predicted), fraction(hits, actual), fraction(2 * hits, predicted + actual)));
    }
    let averages: Vec<_> = (0..3).map(|j| if valued[j] == 0 { "-".to_owned() } else { real(totals[j] / valued[j] as f64) }).collect();
    lines.push(format!("macro precision {} recall {} f1 {}", averages[0], averages[1], averages[2])); lines
}
fn reliability_lines(pairs: &[(&Prediction, &str)], bounds: &[f64]) -> Vec<String> {
    let lowers: Vec<_> = std::iter::once(0.0).chain(bounds.iter().copied()).collect();
    let mut counts = vec![0usize; lowers.len()]; let mut hits = counts.clone(); let mut shares = vec![0.0; lowers.len()];
    for &(prediction, truth) in pairs {
        let j = bounds.iter().filter(|&&bound| bound <= prediction.share).count();
        counts[j] += 1; if prediction.label == truth { hits[j] += 1; } shares[j] += prediction.share;
    }
    lowers.iter().enumerate().map(|(j, &lower)| {
        let mut line = format!("bin {} rows {}", fixed(lower, 2), counts[j]);
        if counts[j] > 0 { line.push_str(&format!(" correct {} share {}", ratio(hits[j], counts[j]), real(shares[j] / counts[j] as f64))); } line
    }).collect()
}

struct ClassifierSpace {
    model: Model,
    distances: BTreeMap<String, BTreeMap<String, f64>>,
}
impl ClassifierSpace {
    fn new(model: &Model, train: &Rows, test: &Rows) -> Self {
        let scaling = Scaling::fit(train, &model.scaling); let features: Vec<_> = (0..train[0].values.len()).collect();
        let references: Vec<_> = train.iter().map(|row| scaling.transform(&row.values, &features)).collect();
        let distances = train.iter().chain(test).map(|query| {
            let vector = scaling.transform(&query.values, &features);
            let gaps = train.iter().zip(&references).map(|(row, reference)| (row.id.clone(), distance(&vector, reference, &model.metric))).collect();
            (query.id.clone(), gaps)
        }).collect();
        Self { model: model.clone(), distances }
    }
    fn order(&self, query: &Row, rows: &Rows) -> Vec<Neighbor> {
        let gaps = &self.distances[&query.id];
        sort_neighbors(rows.iter().map(|row| Neighbor { gap: gaps[&row.id], row: row.clone() }).collect())
    }
    fn vote(&self, query: &Row, rows: &Rows, k: usize) -> Prediction { Prediction::from_order(&self.order(query, rows), k, &self.model.weighting, false) }
    fn nearest_label(&self, query: &Row, rows: &Rows) -> String { self.order(query, rows)[0].row.label.as_ref().unwrap().clone() }
}
type Removals = Vec<(Rc<Row>, Prediction)>;
fn wilson_editing(space: &ClassifierSpace, rows: &Rows, k: usize) -> (Rows, Vec<Removals>) {
    let mut current = rows.clone(); let mut passes = Vec::new();
    loop {
        let mut removals = Vec::new();
        for row in &current {
            let others = current.iter().filter(|other| other.id != row.id).cloned().collect(); let prediction = space.vote(row, &others, k);
            if Some(prediction.label.as_str()) != row.label.as_deref() { removals.push((row.clone(), prediction)); }
        }
        if removals.is_empty() { passes.push(removals); return (current, passes); }
        let removed: BTreeSet<_> = removals.iter().map(|(row, _)| row.id.clone()).collect();
        current.retain(|row| !removed.contains(&row.id)); passes.push(removals);
    }
}
fn hart_condensing(space: &ClassifierSpace, rows: &Rows) -> (Rows, usize) {
    let mut store = vec![rows[0].clone()]; let mut stored = BTreeSet::from([rows[0].id.clone()]); let mut scans = 0;
    loop {
        scans += 1; let mut added = false;
        for row in rows {
            if !stored.contains(&row.id) && Some(space.nearest_label(row, &store).as_str()) != row.label.as_deref() {
                store.push(row.clone()); stored.insert(row.id.clone()); added = true;
            }
        }
        if !added { return (id_order(&store), scans); }
    }
}

struct Experiment {
    feature_names: Vec<String>,
    features: Vec<usize>,
    train: Rows,
    test: Rows,
    settings: Settings,
    labels: Vec<String>,
    labelled: Rows,
    targeted: Rows,
    grid: Vec<Model>,
    folds: Vec<Vec<usize>>,
    results: Vec<CrossValidation>,
    classifier: usize,
    regressor: usize,
    test_predictions: Vec<Prediction>,
    test_estimates: Vec<f64>,
}
impl Experiment {
    fn new(feature_names: Vec<String>, train: Rows, test: Rows, settings: Settings) -> Self {
        let features: Vec<_> = (0..feature_names.len()).collect();
        let labels = train.iter().map(|row| row.label.as_ref().unwrap().clone()).collect::<BTreeSet<_>>().into_iter().collect();
        let labelled = test.iter().filter(|row| row.label.is_some()).cloned().collect(); let targeted = test.iter().filter(|row| row.target.is_some()).cloned().collect();
        let mut grid = Vec::new();
        for &k in &settings.k_values { for metric in &settings.metrics { for weighting in &settings.weightings { for scaling in &settings.scalings {
            grid.push(Model { k, metric: metric.clone(), weighting: weighting.clone(), scaling: scaling.clone() });
        } } } }
        let folds = stratified_folds(&train, settings.folds); let results = cross_validate(&grid, &train, settings.folds, &features);
        let classifier = best_classifier(&results); let regressor = best_regressor(&results);
        let test_predictions = predict_rows(&results[classifier].model, &train, &test, &features);
        let test_estimates = predict_rows(&results[regressor].model, &train, &test, &features).into_iter().map(|p| p.estimate).collect();
        Self { feature_names, features, train, test, settings, labels, labelled, targeted, grid, folds, results, classifier, regressor, test_predictions, test_estimates }
    }
    fn classifier(&self) -> &CrossValidation { &self.results[self.classifier] }
    fn regressor(&self) -> &CrossValidation { &self.results[self.regressor] }
    fn names(&self, features: &[usize]) -> String { features.iter().map(|&j| self.feature_names[j].as_str()).collect::<Vec<_>>().join(" ") }
    fn train_ratio(&self, count: usize) -> String { ratio(count, self.train.len()) }
    fn classifier_summary(&self, result: &CrossValidation) -> String { format!("{} correct {} rmse {}", result.model.notation(), self.train_ratio(result.correct), real(result.rmse)) }
    fn regressor_summary(&self, result: &CrossValidation) -> String { format!("{} rmse {} correct {}", result.model.notation(), real(result.rmse), self.train_ratio(result.correct)) }
    fn choose(&self, indices: &[usize], classifier: bool) -> &CrossValidation {
        let mut best = indices[0];
        for &index in &indices[1..] {
            let better = if classifier { self.results[index].correct > self.results[best].correct } else { four_decimal(self.results[index].rmse) < four_decimal(self.results[best].rmse) };
            if better { best = index; }
        }
        &self.results[best]
    }
    fn grid_table(&self) -> Vec<String> {
        let mut lines = vec!["k,metric,weighting,scaling,correct,accuracy,rmse".to_owned()];
        for result in &self.results {
            let m = &result.model;
            lines.push(format!("{},{},{},{},{},{},{}", m.k, m.metric, m.weighting, m.scaling, result.correct, real(result.correct as f64 / self.train.len() as f64), real(result.rmse)));
        } lines
    }
    fn prediction_table(&self) -> Vec<String> {
        let mut lines = vec!["id,label,vote_share,estimate".to_owned()];
        for (j, row) in self.test.iter().enumerate() { let p = &self.test_predictions[j]; lines.push(format!("{},{},{},{}", row.id, p.label, real(p.share), real(self.test_estimates[j]))); } lines
    }
    fn data_part(&self) -> Vec<String> {
        vec![format!("data train {} test {} labelled {} targets {} features {} classes {}", self.train.len(), self.test.len(), self.labelled.len(), self.targeted.len(), self.features.len(), self.labels.len()), format!("classes {}", label_counts(&self.train, &self.labels))]
    }
    fn scaling_part(&self, method: &str) -> Vec<String> {
        let scaling = Scaling::fit(&self.train, method); let mut lines = vec![format!("scaling {method}")];
        for (j, name) in self.feature_names.iter().enumerate() { lines.push(format!("{name} center {} scale {}", fixed(scaling.centers[j], 6), fixed(scaling.scales[j], 6))); } lines
    }
    fn folds_part(&self) -> Vec<String> {
        let mut lines = vec![format!("folds {}", self.settings.folds)];
        for (j, fold) in self.folds.iter().enumerate() {
            let rows: Rows = fold.iter().map(|&index| self.train[index].clone()).collect(); lines.push(format!("fold {} size {} {}", j + 1, rows.len(), label_counts(&rows, &self.labels)));
        } lines
    }
    fn top_part(&self, accuracy: bool) -> Vec<String> {
        let mut ranking: Vec<_> = (0..self.results.len()).collect();
        ranking.sort_by(|&a, &b| {
            let comparison = if accuracy { self.results[b].correct.cmp(&self.results[a].correct) } else { four_decimal(self.results[a].rmse).partial_cmp(&four_decimal(self.results[b].rmse)).unwrap() };
            comparison.then(a.cmp(&b))
        });
        let mut lines = vec![format!("top {} by {}", self.settings.top, if accuracy { "accuracy" } else { "rmse" })];
        for (j, &index) in ranking.iter().take(self.settings.top).enumerate() { lines.push(format!("{} {}", j + 1, if accuracy { self.classifier_summary(&self.results[index]) } else { self.regressor_summary(&self.results[index]) })); } lines
    }
    fn best_per_parts(&self) -> Vec<Vec<String>> {
        let items = [("k", self.settings.k_values.iter().map(usize::to_string).collect()), ("metric", self.settings.metrics.clone()), ("weighting", self.settings.weightings.clone()), ("scaling", self.settings.scalings.clone())];
        let mut parts = Vec::new();
        for (item, values) in items {
            let mut lines = vec![format!("best per {item}")];
            for value in values {
                let indices: Vec<_> = self.results.iter().enumerate().filter(|(_, r)| match item {
                    "k" => r.model.k.to_string() == value, "metric" => r.model.metric == value, "weighting" => r.model.weighting == value, _ => r.model.scaling == value,
                }).map(|(j, _)| j).collect();
                let cl = self.choose(&indices, true); let reg = self.choose(&indices, false);
                lines.push(format!("{item}={value} classifier {} accuracy {} regressor {} rmse {}", cl.model.notation(), real(cl.correct as f64 / self.train.len() as f64), reg.model.notation(), real(reg.rmse)));
            } parts.push(lines);
        } parts
    }
    fn model_fold_parts(&self) -> Vec<Vec<String>> {
        let mut cl = vec!["classifier folds".to_owned()]; let mut reg = vec!["regressor folds".to_owned()];
        for (j, fold) in self.folds.iter().enumerate() {
            let correct = fold.iter().filter(|&&index| self.classifier().hits[index]).count();
            let errors: Vec<_> = fold.iter().map(|&index| self.regressor().predictions[index].estimate - self.train[index].target.unwrap()).collect();
            cl.push(format!("fold {} correct {}", j + 1, ratio(correct, fold.len()))); reg.push(format!("fold {} size {} rmse {}", j + 1, fold.len(), real(rmse(&errors))));
        } vec![cl, reg]
    }
    fn mcnemar_part(&self) -> Vec<String> {
        let mut lines = vec!["mcnemar".to_owned()];
        for metric in &self.settings.metrics {
            let indices: Vec<_> = self.results.iter().enumerate().filter(|(_, r)| r.model.metric == *metric).map(|(j, _)| j).collect(); let comparison = self.choose(&indices, true);
            let mut b = 0usize; let mut c = 0usize;
            for (&selected, &compared) in self.classifier().hits.iter().zip(&comparison.hits) { if selected && !compared { b += 1; } else if compared && !selected { c += 1; } }
            let disagreements = b + c; let difference = b.abs_diff(c).saturating_sub(1); let u = difference * difference;
            lines.push(format!("{} b {b} c {c} statistic {} significant {}", comparison.model.notation(), if disagreements == 0 { "0/1 0.0000".to_owned() } else { fraction(u, disagreements) }, if 1000 * u > 3841 * disagreements { "yes" } else { "no" }));
        } lines
    }
    fn leave_one_out_parts(&self) -> Vec<Vec<String>> {
        let model = &self.classifier().model;
        let mut by_k: BTreeMap<usize, Vec<Prediction>> = self.settings.k_values.iter().map(|&k| (k, Vec::new())).collect(); let mut estimates = Vec::new();
        for (index, row) in self.train.iter().enumerate() {
            let others = training_rows(&self.train, &[index]); let query = vec![row.clone()];
            let orders = neighbor_orders(&others, &query, &model.scaling, &model.metric, &self.features);
            for &k in &self.settings.k_values { by_k.get_mut(&k).unwrap().push(Prediction::from_order(&orders[0], k, &model.weighting, false)); }
            estimates.push(predict_rows(&self.regressor().model, &others, &query, &self.features)[0].estimate);
        }
        let predictions = &by_k[&model.k]; let mut errors: Vec<_> = self.train.iter().zip(predictions).filter(|(row, p)| row.label.as_deref() != Some(p.label.as_str())).collect();
        errors.sort_by(|(a, _), (b, _)| a.id.cmp(&b.id));
        let mut class_errors = BTreeMap::<&str, usize>::new(); for (row, _) in &errors { *class_errors.entry(row.label.as_deref().unwrap()).or_default() += 1; }
        let listing = self.labels.iter().map(|label| format!("{label} {}", class_errors.get(label.as_str()).unwrap_or(&0))).collect::<Vec<_>>().join(" ");
        let mut cl = vec![format!("leave_one_out classifier {}", model.notation()), format!("errors {}", self.train_ratio(errors.len())), format!("class_errors {listing}")];
        for (row, p) in errors { cl.push(format!("{} true {} predicted {} share {}", row.id, row.label.as_deref().unwrap(), p.label, real(p.share))); }
        let residuals: Vec<_> = estimates.iter().zip(&self.train).map(|(&estimate, row)| estimate - row.target.unwrap()).collect();
        let mut ranking: Vec<_> = (0..self.train.len()).collect();
        ranking.sort_by(|&a, &b| four_decimal(residuals[b].abs()).partial_cmp(&four_decimal(residuals[a].abs())).unwrap().then_with(|| self.train[a].id.cmp(&self.train[b].id)));
        let mut reg = vec![format!("leave_one_out regressor {}", self.regressor().model.notation()), format!("rmse {} mae {}", real(rmse(&residuals)), real(mae(&residuals))), format!("largest {} residuals", self.settings.top)];
        for &j in ranking.iter().take(self.settings.top) { let row = &self.train[j]; reg.push(format!("{} target {} estimate {} residual {}", row.id, real(row.target.unwrap()), real(estimates[j]), real(residuals[j]))); }
        let mut by = vec![format!("leave_one_out by k metric={} weighting={} scaling={}", model.metric, model.weighting, model.scaling)];
        for &k in &self.settings.k_values {
            let predictions = &by_k[&k]; let errors: Vec<_> = predictions.iter().zip(&self.train).map(|(p, row)| p.estimate - row.target.unwrap()).collect();
            by.push(format!("k={k} correct {} rmse {}", self.train_ratio(correct_count(predictions, &self.train)), real(rmse(&errors))));
        } vec![cl, reg, by]
    }
    fn nested_part(&self) -> Vec<String> {
        let mut lines = vec![format!("nested_cross_validation folds {}", self.settings.folds)]; let mut estimates = vec![0.0; self.train.len()]; let mut total = 0;
        for (j, fold) in self.folds.iter().enumerate() {
            let inner = training_rows(&self.train, fold); let queries: Rows = fold.iter().map(|&index| self.train[index].clone()).collect();
            let results = cross_validate(&self.grid, &inner, self.settings.folds, &self.features); let cl = &results[best_classifier(&results)]; let reg = &results[best_regressor(&results)];
            let correct = correct_count(&predict_rows(&cl.model, &inner, &queries, &self.features), &queries); total += correct;
            let predictions = predict_rows(&reg.model, &inner, &queries, &self.features); let mut errors = Vec::new();
            for (&index, p) in fold.iter().zip(predictions) { estimates[index] = p.estimate; errors.push(p.estimate - self.train[index].target.unwrap()); }
            lines.push(format!("fold {} classifier {} inner {} outer {}", j + 1, cl.model.notation(), real(cl.correct as f64 / inner.len() as f64), ratio(correct, fold.len())));
            lines.push(format!("fold {} regressor {} inner {} outer {}", j + 1, reg.model.notation(), real(reg.rmse), real(rmse(&errors))));
        }
        let errors: Vec<_> = estimates.iter().zip(&self.train).map(|(&estimate, row)| estimate - row.target.unwrap()).collect();
        lines.push(format!("nested accuracy {} rmse {}", self.train_ratio(total), real(rmse(&errors)))); lines
    }
    fn feature_part(&self) -> Vec<String> {
        let model = &self.classifier().model; let mut current = self.features.clone(); let mut selected = current.clone(); let mut selected_correct = self.classifier().correct; let mut step = 0;
        let mut lines = vec![format!("feature_selection {}", model.notation()), format!("start features {} correct {}", self.names(&current), self.train_ratio(selected_correct))];
        while current.len() >= 3 {
            step += 1; let mut candidates = Vec::new(); let mut removed = current[0]; let mut correct = None;
            for &feature in &current {
                let remaining: Vec<_> = current.iter().copied().filter(|&other| other != feature).collect();
                let result = cross_validate(std::slice::from_ref(model), &self.train, self.settings.folds, &remaining).remove(0);
                candidates.push(format!("{} {}", self.feature_names[feature], result.correct));
                if correct.is_none_or(|best| result.correct > best) { correct = Some(result.correct); removed = feature; }
            }
            let correct = correct.unwrap(); current.retain(|&other| other != removed);
            lines.push(format!("step {step} remove {} correct {} candidates {}", self.feature_names[removed], self.train_ratio(correct), candidates.join(" ")));
            if correct >= selected_correct { selected = current.clone(); selected_correct = correct; }
        }
        let predictions = predict_rows(model, &self.train, &self.labelled, &selected);
        lines.push(format!("selected features {} correct {}", self.names(&selected), self.train_ratio(selected_correct)));
        lines.push(format!("selected test {}", ratio(correct_count(&predictions, &self.labelled), self.labelled.len()))); lines
    }
    fn uncertain_part(&self) -> Vec<String> {
        let margins: Vec<_> = self.test_predictions.iter().map(|p| p.share - p.runner_share).collect(); let mut ranking: Vec<_> = (0..self.test.len()).collect();
        ranking.sort_by(|&a, &b| four_decimal(margins[a]).partial_cmp(&four_decimal(margins[b])).unwrap().then(a.cmp(&b)));
        let mut lines = vec![format!("uncertain {} test rows", self.settings.top)];
        for &j in ranking.iter().take(self.settings.top) {
            let row = &self.test[j]; let p = &self.test_predictions[j];
            lines.push(format!("{} predicted {} share {} runner_up {} share {} margin {} true {}", row.id, p.label, real(p.share), p.runner.as_deref().unwrap_or("-"), real(p.runner_share), real(margins[j]), row.label.as_deref().unwrap_or("-")));
        } lines
    }
    fn regression_part(&self) -> Vec<String> {
        let mut errors = Vec::new(); let mut targets = Vec::new(); let mut class_errors = BTreeMap::<&str, Vec<f64>>::new();
        for (j, row) in self.test.iter().enumerate() {
            if let Some(target) = row.target {
                let error = self.test_estimates[j] - target; errors.push(error); targets.push(target);
                if let Some(label) = row.label.as_deref() { class_errors.entry(label).or_default().push(error); }
            }
        }
        let mut lines = vec![format!("test regression {}", self.regressor().model.notation()), format!("targets {} rmse {} mae {} r2 {}", errors.len(), real(rmse(&errors)), real(mae(&errors)), real(r_squared(&errors, &targets)))];
        for label in &self.labels {
            let errors = class_errors.get(label.as_str()).map_or(&[][..], Vec::as_slice);
            lines.push(format!("class {label} targets {} rmse {}", errors.len(), if errors.is_empty() { "-".to_owned() } else { real(rmse(errors)) }));
        } lines
    }
    fn misclassified_part(&self) -> Vec<String> {
        let mut lines = vec!["misclassified test rows".to_owned()]; let mut count = 0;
        for (row, p) in self.test.iter().zip(&self.test_predictions) {
            if row.label.is_none() || row.label.as_deref() == Some(p.label.as_str()) { continue; }
            count += 1; lines.push(format!("{} true {} predicted {} share {}", row.id, row.label.as_deref().unwrap(), p.label, real(p.share)));
            for neighbor in &p.neighbors { lines.push(format!("  {} {} {}", neighbor.row.id, neighbor.row.label.as_deref().unwrap(), real(neighbor.gap))); }
        } lines.push(format!("count {count}")); lines
    }
    fn metrics_report(&self) -> Vec<String> {
        let mut parts = vec![self.data_part()]; for method in &self.settings.scalings { parts.push(self.scaling_part(method)); }
        parts.push(self.folds_part()); parts.push(vec![format!("grid {}", self.grid.len()), format!("best_classifier {}", self.classifier_summary(self.classifier())), format!("best_regressor {}", self.regressor_summary(self.regressor()))]);
        parts.push(self.top_part(true)); parts.push(self.top_part(false)); parts.extend(self.best_per_parts()); parts.extend(self.model_fold_parts());
        let pairs: Vec<_> = self.train.iter().zip(&self.classifier().predictions).map(|(row, p)| (row.label.as_ref().unwrap().clone(), p.label.clone())).collect();
        let shares: Vec<_> = self.train.iter().zip(&self.classifier().predictions).map(|(row, p)| (p, row.label.as_deref().unwrap())).collect();
        let mut evaluation = vec!["cross_validation classes".to_owned()]; evaluation.extend(evaluation_lines(&pairs, &self.labels)); parts.push(evaluation);
        let mut reliability = vec!["cross_validation reliability".to_owned()]; reliability.extend(reliability_lines(&shares, &self.settings.bins)); parts.push(reliability);
        parts.push(self.mcnemar_part()); parts.extend(self.leave_one_out_parts()); parts.push(self.nested_part()); parts.push(self.feature_part());
        let pairs: Vec<_> = self.test.iter().zip(&self.test_predictions).filter_map(|(row, p)| row.label.as_ref().map(|label| (label.clone(), p.label.clone()))).collect();
        let shares: Vec<_> = self.test.iter().zip(&self.test_predictions).filter_map(|(row, p)| row.label.as_deref().map(|label| (p, label))).collect();
        let correct = pairs.iter().filter(|(truth, predicted)| truth == predicted).count();
        let mut evaluation = vec![format!("test classification {}", self.classifier().model.notation()), format!("labelled {} correct {}", pairs.len(), ratio(correct, pairs.len()))]; evaluation.extend(evaluation_lines(&pairs, &self.labels)); parts.push(evaluation);
        let mut reliability = vec!["test reliability".to_owned()]; reliability.extend(reliability_lines(&shares, &self.settings.bins)); parts.push(reliability);
        parts.push(self.uncertain_part()); parts.push(self.regression_part()); parts.push(self.misclassified_part()); join_parts(parts)
    }
    fn learning_curve_table(&self) -> Vec<String> {
        let mut lines = vec!["n,train_size,correct,accuracy,rmse".to_owned()];
        for &limit in &self.settings.curve {
            let mut taken = BTreeMap::<&str, usize>::new(); let mut rows = Vec::new();
            for row in &self.train {
                let count = taken.entry(row.label.as_deref().unwrap()).or_default(); if *count < limit { *count += 1; rows.push(row.clone()); }
            }
            let correct = correct_count(&predict_rows(&self.classifier().model, &rows, &self.labelled, &self.features), &self.labelled);
            let predictions = predict_rows(&self.regressor().model, &rows, &self.targeted, &self.features);
            let errors: Vec<_> = predictions.iter().zip(&self.targeted).map(|(p, row)| p.estimate - row.target.unwrap()).collect();
            lines.push(format!("{limit},{},{},{},{}", rows.len(), correct, real(correct as f64 / self.labelled.len() as f64), real(rmse(&errors))));
        } lines
    }
    fn prototype_line(&self, space: &ClassifierSpace, name: &str, rows: &Rows) -> String {
        let mut knn = 0; let mut nearest = 0;
        for row in &self.labelled {
            if Some(space.vote(row, rows, self.classifier().model.k).label.as_str()) == row.label.as_deref() { knn += 1; }
            if Some(space.nearest_label(row, rows).as_str()) == row.label.as_deref() { nearest += 1; }
        }
        format!("set {name} size {} {} knn {} 1nn {}", rows.len(), label_counts(rows, &self.labels), ratio(knn, self.labelled.len()), ratio(nearest, self.labelled.len()))
    }
    fn borders_part(&self, space: &ClassifierSpace, ordered: &Rows) -> Vec<String> {
        let mut lines = vec!["borders".to_owned()]; let mut total = 0;
        for label in &self.labels {
            let members: Rows = ordered.iter().filter(|row| row.label.as_ref() == Some(label)).cloned().collect();
            let mut borders = 0; let mut same_total = 0.0; let mut other_total = 0.0;
            for row in &members {
                let others = ordered.iter().filter(|other| other.id != row.id).cloned().collect(); let order = space.order(row, &others);
                if order[0].row.label.as_ref() != Some(label) { borders += 1; }
                same_total += order.iter().find(|neighbor| neighbor.row.label.as_ref() == Some(label)).unwrap().gap;
                other_total += order.iter().find(|neighbor| neighbor.row.label.as_ref() != Some(label)).unwrap().gap;
            }
            total += borders; lines.push(format!("class {label} size {} border {borders} same {} other {}", members.len(), real(same_total / members.len() as f64), real(other_total / members.len() as f64)));
        } lines.push(format!("border total {}", self.train_ratio(total))); lines
    }
    fn hubs_part(&self) -> Vec<String> {
        let mut occurrences: BTreeMap<&str, usize> = self.train.iter().map(|row| (row.id.as_str(), 0)).collect();
        for p in &self.test_predictions { for neighbor in &p.neighbors { *occurrences.get_mut(neighbor.row.id.as_str()).unwrap() += 1; } }
        let mut ranked = self.train.clone(); ranked.sort_by(|a, b| occurrences[b.id.as_str()].cmp(&occurrences[a.id.as_str()]).then_with(|| a.id.cmp(&b.id)));
        let mut lines = vec![format!("hubs k={} queries {}", self.classifier().model.k, self.test.len())];
        for row in ranked.iter().take(self.settings.top) { lines.push(format!("{} {} {}", row.id, row.label.as_deref().unwrap(), occurrences[row.id.as_str()])); }
        lines.push(format!("anti_hubs {}", occurrences.values().filter(|&&count| count == 0).count())); lines
    }
    fn prototypes_report(&self) -> Vec<String> {
        let space = ClassifierSpace::new(&self.classifier().model, &self.train, &self.test); let ordered = id_order(&self.train);
        let (edited, passes) = wilson_editing(&space, &ordered, self.settings.edit_k); let (condensed, scans) = hart_condensing(&space, &ordered); let (edited_condensed, edited_scans) = hart_condensing(&space, &edited);
        let mut editing = vec![format!("editing k={}", self.settings.edit_k)];
        for (j, removed) in passes.iter().enumerate() {
            editing.push(format!("pass {} removed {}", j + 1, removed.len()));
            for (row, p) in removed { editing.push(format!("  {} true {} predicted {} share {}", row.id, row.label.as_deref().unwrap(), p.label, real(p.share))); }
        }
        editing.push(format!("edited size {} removed {}", edited.len(), self.train.len() - edited.len()));
        let sets = [("original", &ordered), ("edited", &edited), ("condensed", &condensed), ("edited_condensed", &edited_condensed)];
        let set_lines = sets.iter().map(|(name, rows)| self.prototype_line(&space, name, rows)).collect();
        let ids = |name: &str, rows: &Rows| {
            let mut lines = vec![format!("prototypes {name}")];
            lines.extend(rows.chunks(10).map(|chunk| chunk.iter().map(|row| row.id.as_str()).collect::<Vec<_>>().join(" "))); lines
        };
        join_parts(vec![vec![format!("space {}", self.classifier().model.notation())], editing, vec![format!("condensing original scans {scans} size {}", condensed.len()), format!("condensing edited scans {edited_scans} size {}", edited_condensed.len())], set_lines, ids("condensed", &condensed), ids("edited_condensed", &edited_condensed), self.borders_part(&space, &ordered), self.hubs_part()])
    }
}

fn main() {
    let (feature_names, train) = read_rows("train.csv"); let (_, test) = read_rows("test.csv"); let experiment = Experiment::new(feature_names, train, test, Settings::read());
    fs::create_dir_all("output").unwrap();
    write_lines("cv_grid.csv", experiment.grid_table()); write_lines("predictions.csv", experiment.prediction_table()); write_lines("metrics.txt", experiment.metrics_report());
    write_lines("learning_curve.csv", experiment.learning_curve_table()); write_lines("prototypes.txt", experiment.prototypes_report());
}
