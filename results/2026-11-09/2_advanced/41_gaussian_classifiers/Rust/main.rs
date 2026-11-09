mod dataset;
mod evaluation;
mod gaussian_models;
mod linalg;
mod plot;

use dataset::{Input, Row};
use evaluation::{evaluate, mcnemar, Evaluation, Random};
use gaussian_models::{first_max, first_min, Model, Prediction};
use linalg::{backward, cholesky, forward, jacobi, log_determinant, quadratic, sum, Matrix};
use plot::{fraction, frame, ratio, real};
use std::collections::BTreeSet;
use std::fs;

const MODELS: [&str; 3] = ["NB", "LDA", "QDA"];

fn scalar(input: &Input, key: &str) -> f64 { input.params[key][0].parse().unwrap() }
fn integer(input: &Input, key: &str) -> usize { input.params[key][0].parse().unwrap() }
fn reals(values: &[f64]) -> String { values.iter().map(|&v| real(v)).collect::<Vec<_>>().join(" ") }
fn counts(values: &[usize]) -> String { values.iter().map(usize::to_string).collect::<Vec<_>>().join(" ") }
fn feature_names(input: &Input, features: &[usize]) -> String { features.iter().map(|&f| input.features[f].clone()).collect::<Vec<_>>().join(" ") }

fn part(lines: &mut Vec<String>, block: Vec<String>) {
    if !lines.is_empty() { lines.push(String::new()); }
    lines.extend(block);
}

fn train(input: &Input, rows: &[Row], features: &[usize], kind: usize, epsilon: f64, gamma: f64, prior: &str) -> Model {
    Model::train(rows, features, input.classes.len(), kind, epsilon, gamma, prior)
}

fn main_model(input: &Input, rows: &[Row], features: &[usize], kind: usize) -> Model {
    train(input, rows, features, kind, scalar(input, "VAR_SMOOTHING"), scalar(input, "QDA_GAMMA"), &input.params["PRIOR"][0])
}

fn predict_rows(input: &Input, model: &Model, rows: &[Row]) -> Vec<Prediction> { rows.iter().map(|row| model.row(row, &input.costs)).collect() }
fn predicted(predictions: &[Prediction]) -> Vec<usize> { predictions.iter().map(|p| p.class).collect() }
fn correct(rows: &[Row], predictions: &[usize]) -> usize { rows.iter().zip(predictions).filter(|(row, p)| row.class == **p).count() }

struct CrossValidation {
    predictions: Vec<usize>,
    folds: Vec<usize>,
    correct: usize,
}

fn cross_validate(input: &Input, features: &[usize], kind: usize, epsilon: f64, gamma: f64) -> CrossValidation {
    let fold_count = integer(input, "CV_FOLDS");
    let mut predictions = vec![0; input.train.len()];
    let mut folds = Vec::new();
    for fold in 0..fold_count {
        let rows: Vec<_> = input.train.iter().filter(|row| row.id as usize % fold_count != fold).cloned().collect();
        let model = train(input, &rows, features, kind, epsilon, gamma, &input.params["PRIOR"][0]);
        let mut fold_correct = 0;
        for (i, row) in input.train.iter().enumerate().filter(|(_, row)| row.id as usize % fold_count == fold) {
            predictions[i] = model.row(row, &input.costs).class;
            fold_correct += usize::from(predictions[i] == row.class);
        }
        folds.push(fold_correct);
    }
    let correct = folds.iter().sum();
    CrossValidation { predictions, folds, correct }
}

fn cv(input: &Input, features: &[usize], kind: usize) -> CrossValidation {
    cross_validate(input, features, kind, scalar(input, "VAR_SMOOTHING"), scalar(input, "QDA_GAMMA"))
}

fn models_report(input: &Input, models: &[Model]) -> Vec<String> {
    let statistics = &models[0].statistics;
    let d = input.features.len();
    let mut lines = vec![format!("features {}", input.features.join(" ")), format!("classes {}", input.classes.join(" ")), format!("prior_mode {}", input.params["PRIOR"][0])];
    for k in 0..input.classes.len() {
        lines.push(format!("class {} letter {} count {} prior {} mean {}", input.classes[k], input.classes[k].as_bytes()[0].to_ascii_uppercase() as char, statistics.counts[k], real(statistics.priors[k]), reals(&statistics.means[k])));
    }
    let maximum = statistics.variances.iter().copied().fold(f64::NEG_INFINITY, f64::max);
    let epsilon = scalar(input, "VAR_SMOOTHING");
    let mut block = vec!["model NB".into(), format!("smoothing epsilon {} max_variance {} added {}", real(epsilon), real(maximum), real(epsilon * maximum))];
    for k in 0..input.classes.len() {
        block.push(format!("class {} variance {} log_det {}", input.classes[k], reals(&(0..d).map(|j| models[0].covariance[k][j][j]).collect::<Vec<_>>()), real(models[0].log_determinants[k])));
    }
    part(&mut lines, block);
    let lda = &models[1];
    let mut block = vec!["model LDA".into(), format!("log_det {}", real(lda.log_determinants[0]))];
    block.extend(lda.covariance[0].iter().map(|row| format!("  {}", reals(row))));
    for k in 0..input.classes.len() {
        let coef = backward(&lda.lower[0], &forward(&lda.lower[0], &statistics.means[k]));
        let intercept = statistics.priors[k].ln() - sum(statistics.means[k].iter().zip(&coef).map(|(&m, &c)| m * c)) / 2.0;
        block.push(format!("class {} intercept {} coef {}", input.classes[k], real(intercept), reals(&coef)));
    }
    part(&mut lines, block);
    let qda = &models[2];
    let mut block = vec![format!("model QDA gamma {}", real(scalar(input, "QDA_GAMMA")))];
    for k in 0..input.classes.len() {
        let (mut eigenvalues, _, _) = jacobi(&qda.covariance[k]);
        eigenvalues.sort_by(|a, b| b.total_cmp(a));
        block.push(format!("class {} log_det {} eigenvalues {} condition {}", input.classes[k], real(qda.log_determinants[k]), reals(&eigenvalues), real(eigenvalues[0] / eigenvalues[d - 1])));
        block.extend(qda.covariance[k].iter().map(|row| format!("  {}", reals(row))));
    }
    part(&mut lines, block);
    let mut block = vec!["separation".into()];
    for a in 0..input.classes.len() {
        for b in a + 1..input.classes.len() {
            let difference: Vec<_> = statistics.means[a].iter().zip(&statistics.means[b]).map(|(&a, &b)| a - b).collect();
            let average: Matrix = (0..d).map(|i| (0..d).map(|j| (qda.covariance[a][i][j] + qda.covariance[b][i][j]) / 2.0).collect()).collect();
            let lower = cholesky(&average);
            let bhattacharyya = quadratic(&lower, &difference) / 8.0 + (log_determinant(&lower) - (qda.log_determinants[a] + qda.log_determinants[b]) / 2.0) / 2.0;
            block.push(format!("{} {} mahalanobis {} bhattacharyya {}", input.classes[a], input.classes[b], real(quadratic(&lda.lower[0], &difference).sqrt()), real(bhattacharyya)));
        }
    }
    part(&mut lines, block);
    let theta = scalar(input, "OUTLIER_THRESHOLD");
    let mut outliers: Vec<_> = input.train.iter().enumerate().filter_map(|(i, row)| {
        let q = qda.row(row, &input.costs).distances[row.class];
        (q > theta).then_some((i, q))
    }).collect();
    outliers.sort_by(|a, b| b.1.total_cmp(&a.1).then(a.0.cmp(&b.0)));
    let mut block = vec![format!("outliers threshold {}", real(theta))];
    for &(i, q) in &outliers { block.push(format!("{} {} q {}", input.train[i].id, input.classes[input.train[i].class], real(q))); }
    block.push(format!("count {}", outliers.len()));
    part(&mut lines, block);
    lines
}

fn confusion_lines(input: &Input, evaluation: &Evaluation) -> Vec<String> {
    input.classes.iter().zip(&evaluation.confusion).map(|(class, row)| format!("confusion {} {}", class, counts(row))).collect()
}

fn mcnemar_lines(rows: &[Row], predictions: &[Vec<usize>], names: &[&str]) -> Vec<String> {
    let mut lines = Vec::new();
    for a in 0..predictions.len() {
        for b in a + 1..predictions.len() {
            let (b01, b10, chi) = mcnemar(rows, &predictions[a], &predictions[b]);
            lines.push(format!("{} {} b01 {} b10 {} chi2 {} significant {}", names[a], names[b], b01, b10, real(chi), if chi > 3.841 { "yes" } else { "no" }));
        }
    }
    lines
}

fn evaluation_report(input: &Input, predictions: &[Vec<Prediction>]) -> Vec<String> {
    let n = input.train.len();
    let m = input.test.len();
    let all: Vec<_> = (0..input.features.len()).collect();
    let mut lines = vec![format!("test rows {m}")];
    let classes = input.classes.len();
    let mut predicted_classes: Vec<_> = predictions.iter().map(|p| predicted(p)).collect();
    for kind in 0..3 {
        let evaluation = evaluate(&input.test, &predicted_classes[kind], classes);
        let mut block = vec![format!("model {}", MODELS[kind])];
        block.extend(confusion_lines(input, &evaluation));
        block.extend([format!("accuracy {}", fraction(evaluation.accuracy)), format!("balanced_accuracy {}", fraction(evaluation.balanced)), format!("kappa {}", fraction(evaluation.kappa))]);
        for k in 0..classes {
            block.push(format!("class {} support {} recall {} precision {} f1 {}", input.classes[k], evaluation.support[k], ratio(evaluation.confusion[k][k], evaluation.support[k]), ratio(evaluation.confusion[k][k], evaluation.predicted[k]), ratio(2 * evaluation.confusion[k][k], evaluation.support[k] + evaluation.predicted[k])));
        }
        let log_loss = -sum(input.test.iter().zip(&predictions[kind]).map(|(row, prediction)| prediction.log_posterior[row.class])) / m as f64;
        block.extend([format!("macro_f1 {}", real(evaluation.macro_f1)), format!("log_loss {}", real(log_loss)), format!("errors {}", m - evaluation.correct)]);
        for (row, prediction) in input.test.iter().zip(&predictions[kind]).filter(|(row, p)| row.class != p.class) {
            block.push(format!("error {} actual {} predicted {} confidence {}", row.id, input.classes[row.class], input.classes[prediction.class], real(prediction.confidence)));
        }
        let mut edges: Vec<_> = input.params["CALIBRATION_EDGES"].iter().map(|e| e.parse::<f64>().unwrap()).collect();
        edges.insert(0, 0.0);
        edges.push(1.0);
        let mut ece = 0.0;
        for bin in 0..edges.len() - 1 {
            let included: Vec<_> = predictions[kind].iter().enumerate().filter(|(_, p)| p.confidence >= edges[bin] && (p.confidence < edges[bin + 1] || bin == edges.len() - 2)).collect();
            let confidence = sum(included.iter().map(|(_, p)| p.confidence));
            let correct = included.iter().filter(|(i, p)| p.class == input.test[*i].class).count();
            ece += (correct as f64 - confidence).abs();
            block.push(format!("bin {} {} count {} confidence {} accuracy {}", real(edges[bin]), real(edges[bin + 1]), included.len(), if included.is_empty() { "-".into() } else { real(confidence / included.len() as f64) }, ratio(correct, included.len())));
        }
        block.push(format!("ece {}", real(ece / m as f64)));
        for threshold in &input.params["REJECT_THRESHOLDS"] {
            let threshold: f64 = threshold.parse().unwrap();
            let accepted: Vec<_> = predictions[kind].iter().enumerate().filter(|(_, p)| p.confidence >= threshold).collect();
            let correct = accepted.iter().filter(|(i, p)| p.class == input.test[*i].class).count();
            block.push(format!("reject {} accepted {} coverage {} accuracy {}", real(threshold), accepted.len(), ratio(accepted.len(), m), ratio(correct, accepted.len())));
        }
        part(&mut lines, block);
    }
    let ensemble: Vec<_> = (0..m).map(|i| first_max(&(0..classes).map(|k| sum((0..3).map(|kind| predictions[kind][i].posterior[k])) / 3.0).collect::<Vec<_>>())).collect();
    let ensemble_evaluation = evaluate(&input.test, &ensemble, classes);
    part(&mut lines, vec!["ensemble soft_vote".into(), format!("accuracy {} balanced_accuracy {} kappa {}", fraction(ensemble_evaluation.accuracy), fraction(ensemble_evaluation.balanced), fraction(ensemble_evaluation.kappa))]);
    predicted_classes.push(ensemble);
    let mut block = vec!["mcnemar test".into()];
    block.extend(mcnemar_lines(&input.test, &predicted_classes, &["NB", "LDA", "QDA", "ENSEMBLE"]));
    part(&mut lines, block);
    let mut block = vec!["costs".into()];
    for kind in 0..3 {
        let argmax = sum(input.test.iter().zip(&predictions[kind]).map(|(row, p)| input.costs[row.class][p.class]));
        let decision = sum(input.test.iter().zip(&predictions[kind]).map(|(row, p)| input.costs[row.class][p.decision]));
        let changed = predictions[kind].iter().filter(|p| p.class != p.decision).count();
        let correct = input.test.iter().zip(&predictions[kind]).filter(|(row, p)| row.class == p.decision).count();
        block.push(format!("{} argmax_total {} decision_total {} changed {} decision_accuracy {}", MODELS[kind], real(argmax), real(decision), changed, ratio(correct, m)));
    }
    part(&mut lines, block);
    let theta = scalar(input, "OUTLIER_THRESHOLD");
    let mut novel: Vec<_> = predictions[2].iter().enumerate().filter_map(|(i, p)| {
        let nearest = first_min(&p.distances);
        (p.distances[nearest] > theta).then_some((i, nearest, p.distances[nearest]))
    }).collect();
    novel.sort_by(|a, b| b.2.total_cmp(&a.2).then(a.0.cmp(&b.0)));
    let mut block = vec![format!("novelty threshold {}", real(theta))];
    block.extend(novel.iter().map(|&(i, nearest, q)| format!("{} nearest {} q {}", input.test[i].id, input.classes[nearest], real(q))));
    block.push(format!("count {}", novel.len()));
    part(&mut lines, block);
    let repetitions = integer(input, "BOOTSTRAP");
    let seed: i64 = input.params["BOOTSTRAP"][1].parse().unwrap();
    let mut random = Random(seed);
    let mut samples = vec![Vec::new(); 3];
    for _ in 0..repetitions {
        let mut counts = [0; 3];
        for _ in 0..m {
            let i = random.next() as usize % m;
            for kind in 0..3 { counts[kind] += usize::from(predicted_classes[kind][i] == input.test[i].class); }
        }
        for kind in 0..3 { samples[kind].push(counts[kind]); }
    }
    let mut block = vec![format!("bootstrap resamples {repetitions} seed {seed}")];
    for kind in 0..3 {
        let mut sorted = samples[kind].clone();
        sorted.sort_unstable();
        block.push(format!("{} mean {} interval {} {}", MODELS[kind], real(samples[kind].iter().sum::<usize>() as f64 / repetitions as f64 / m as f64), ratio(sorted[repetitions / 40], m), ratio(sorted[repetitions - 1 - repetitions / 40], m)));
    }
    for a in 0..3 {
        for b in a + 1..3 {
            let wins = samples[a].iter().zip(&samples[b]).filter(|(a, b)| a > b).count();
            let ties = samples[a].iter().zip(&samples[b]).filter(|(a, b)| a == b).count();
            block.push(format!("{} {} wins {} ties {} losses {}", MODELS[a], MODELS[b], wins, ties, repetitions - wins - ties));
        }
    }
    part(&mut lines, block);
    let alternative = if input.params["PRIOR"][0] == "empirical" { "uniform" } else { "empirical" };
    let mut block = vec![format!("prior_sensitivity alternative {alternative}")];
    for kind in 0..3 {
        let model = train(input, &input.train, &all, kind, scalar(input, "VAR_SMOOTHING"), scalar(input, "QDA_GAMMA"), alternative);
        let p = predicted(&predict_rows(input, &model, &input.test));
        let evaluation = evaluate(&input.test, &p, classes);
        let changed = p.iter().zip(&predicted_classes[kind]).filter(|(a, b)| a != b).count();
        block.push(format!("{} accuracy {} balanced_accuracy {} changed {}", MODELS[kind], fraction(evaluation.accuracy), fraction(evaluation.balanced), changed));
    }
    part(&mut lines, block);
    let mut block = vec!["learning_curve".into()];
    for size in &input.params["CURVE"] {
        let size: usize = size.parse().unwrap();
        let mut counts = vec![0; classes];
        let rows: Vec<_> = input.train.iter().filter(|row| { counts[row.class] += 1; counts[row.class] <= size }).cloned().collect();
        let accuracies: Vec<_> = (0..3).map(|kind| {
            let model = main_model(input, &rows, &all, kind);
            ratio(correct(&input.test, &predicted(&predict_rows(input, &model, &input.test))), m)
        }).collect();
        block.push(format!("size {} rows {} NB {} LDA {} QDA {}", size, rows.len(), accuracies[0], accuracies[1], accuracies[2]));
    }
    part(&mut lines, block);
    let mut block = vec![format!("cross_validation folds {}", integer(input, "CV_FOLDS")), format!("fold_sizes {}", counts(&(0..integer(input, "CV_FOLDS")).map(|fold| input.train.iter().filter(|row| row.id as usize % integer(input, "CV_FOLDS") == fold).count()).collect::<Vec<_>>()))];
    let mut candidates = Vec::new();
    for (subset_index, (name, features)) in input.subsets.iter().enumerate() {
        block.push(format!("subset {} features {}", name, feature_names(input, features)));
        for kind in 0..3 {
            let result = cv(input, features, kind);
            block.push(format!("  {} fold_correct {} correct {} accuracy {}", MODELS[kind], counts(&result.folds), result.correct, ratio(result.correct, n)));
            candidates.push((result.correct, features.len(), subset_index, kind));
        }
    }
    let &(best_count, _, subset_index, kind) = candidates.iter().min_by_key(|&&(count, size, subset, kind)| (-(count as i64), size, subset, kind)).unwrap();
    let (name, features) = &input.subsets[subset_index];
    let model = main_model(input, &input.train, features, kind);
    let test_correct = correct(&input.test, &predicted(&predict_rows(input, &model, &input.test)));
    block.extend([format!("best subset {} model {} correct {} accuracy {}", name, MODELS[kind], best_count, ratio(best_count, n)), format!("refit_test correct {} accuracy {}", test_correct, ratio(test_correct, m))]);
    part(&mut lines, block);
    let cross_validation: Vec<_> = (0..3).map(|kind| cv(input, &all, kind).predictions).collect();
    let mut block = vec!["mcnemar cross_validation".into()];
    block.extend(mcnemar_lines(&input.train, &cross_validation, &MODELS));
    part(&mut lines, block);
    for kind in 0..3 {
        let evaluation = evaluate(&input.train, &cross_validation[kind], classes);
        let mut block = vec![format!("cv_confusion model {}", MODELS[kind])];
        block.extend(confusion_lines(input, &evaluation));
        block.push(format!("balanced_accuracy {} kappa {}", fraction(evaluation.balanced), fraction(evaluation.kappa)));
        part(&mut lines, block);
    }
    let mut block = vec!["leave_one_out".into()];
    for kind in 0..3 {
        let mut correct = 0;
        for i in 0..n {
            let rows: Vec<_> = input.train.iter().enumerate().filter(|(j, _)| i != *j).map(|(_, row)| row.clone()).collect();
            let model = main_model(input, &rows, &all, kind);
            correct += usize::from(model.row(&input.train[i], &input.costs).class == input.train[i].class);
        }
        block.push(format!("{} correct {} accuracy {}", MODELS[kind], correct, ratio(correct, n)));
    }
    part(&mut lines, block);
    for kind in 0..3 {
        let mut selected = Vec::new();
        let mut best_step = 0;
        let mut best_count = 0;
        let mut block = vec![format!("forward_selection model {}", MODELS[kind])];
        for step in 0..all.len() {
            let mut candidate: Option<(usize, usize)> = None;
            for &feature in &all {
                if selected.contains(&feature) { continue; }
                let mut features = selected.clone();
                features.push(feature);
                let count = cv(input, &features, kind).correct;
                if candidate.is_none_or(|(_, best)| count > best) { candidate = Some((feature, count)); }
            }
            let (feature, count) = candidate.unwrap();
            selected.push(feature);
            block.push(format!("step {} add {} correct {} accuracy {}", step + 1, input.features[feature], count, ratio(count, n)));
            if step == 0 || count > best_count { best_step = step; best_count = count; }
        }
        block.push(format!("best_step {} features {}", best_step + 1, feature_names(input, &selected[..=best_step])));
        part(&mut lines, block);
    }
    for (kind, key, heading) in [(0, "SMOOTHING_GRID", "nb_smoothing_path"), (2, "GAMMA_GRID", "qda_gamma_path")] {
        let mut block = vec![heading.into()];
        let mut selected = 0;
        let mut best_count = 0;
        for (i, value) in input.params[key].iter().enumerate() {
            let value: f64 = value.parse().unwrap();
            let count = cross_validate(input, &all, kind, if kind == 0 { value } else { scalar(input, "VAR_SMOOTHING") }, if kind == 2 { value } else { scalar(input, "QDA_GAMMA") }).correct;
            block.push(format!("value {} correct {} accuracy {}", real(value), count, ratio(count, n)));
            if count >= best_count { selected = i; best_count = count; }
        }
        let value: f64 = input.params[key][selected].parse().unwrap();
        let model = train(input, &input.train, &all, kind, if kind == 0 { value } else { scalar(input, "VAR_SMOOTHING") }, if kind == 2 { value } else { scalar(input, "QDA_GAMMA") }, &input.params["PRIOR"][0]);
        let correct = correct(&input.test, &predicted(&predict_rows(input, &model, &input.test)));
        block.push(format!("best {} test correct {} accuracy {}", real(value), correct, ratio(correct, m)));
        part(&mut lines, block);
    }
    lines
}

fn place(canvas: &mut [Vec<u8>], row: usize, column: usize, letter: u8) {
    canvas[row][column] = if canvas[row][column] == b' ' || canvas[row][column] == letter { letter } else { b'*' };
}

fn boundaries(input: &Input) -> Vec<String> {
    let width = integer(input, "MAP_SIZE");
    let height: usize = input.params["MAP_SIZE"][1].parse().unwrap();
    let mut lines = Vec::new();
    for &[fx, fy] in &input.pairs {
        let features = [fx, fy];
        let xmin = input.train.iter().map(|r| r.values[fx]).fold(f64::INFINITY, f64::min);
        let xmax = input.train.iter().map(|r| r.values[fx]).fold(f64::NEG_INFINITY, f64::max);
        let ymin = input.train.iter().map(|r| r.values[fy]).fold(f64::INFINITY, f64::min);
        let ymax = input.train.iter().map(|r| r.values[fy]).fold(f64::NEG_INFINITY, f64::max);
        let dx = (xmax - xmin) / (width - 1) as f64;
        let dy = (ymax - ymin) / (height - 1) as f64;
        let models: Vec<_> = (0..3).map(|kind| main_model(input, &input.train, &features, kind)).collect();
        let mut maps = vec![vec![vec![0; width]; height]; 3];
        let mut uncertainty = vec![vec![b' '; width]; height];
        let mut block = vec![format!("pair {} {}", input.features[fx], input.features[fy]), format!("x {} {} {} y {} {} {} grid {}x{}", input.features[fx], real(xmin), real(xmax), input.features[fy], real(ymin), real(ymax), width, height)];
        for kind in 0..3 {
            for r in 0..height {
                for c in 0..width {
                    let prediction = models[kind].predict(&[xmin + c as f64 * dx, ymax - r as f64 * dy], &input.costs);
                    maps[kind][r][c] = input.classes[prediction.class].as_bytes()[0].to_ascii_uppercase();
                    if kind == 2 {
                        let u = (1.0 - prediction.confidence) / (1.0 - 1.0 / input.classes.len() as f64);
                        uncertainty[r][c] = b" .:-=+*#%@"[(10.0 * u).floor().min(9.0) as usize];
                    }
                }
            }
            let p = predicted(&predict_rows(input, &models[kind], &input.train));
            let cv = cv(input, &features, kind);
            block.push(format!("model {} train_accuracy {} cv_accuracy {}", MODELS[kind], ratio(correct(&input.train, &p), input.train.len()), ratio(cv.correct, input.train.len())));
            block.extend(frame(&maps[kind]));
            let cells = input.classes.iter().map(|class| {
                let letter = class.as_bytes()[0].to_ascii_uppercase();
                format!("{} {}", letter as char, maps[kind].iter().flatten().filter(|&&cell| cell == letter).count())
            }).collect::<Vec<_>>().join(" ");
            block.push(format!("cells {cells}"));
        }
        let agreement: Vec<Vec<_>> = (0..height).map(|r| (0..width).map(|c| {
            let distinct = maps.iter().map(|map| map[r][c]).collect::<BTreeSet<_>>().len();
            if distinct == 1 { b'.' } else { b'0' + distinct as u8 }
        }).collect()).collect();
        block.push("agreement".into());
        block.extend(frame(&agreement));
        block.push(format!("disagreement_cells {}", agreement.iter().flatten().filter(|&&cell| cell != b'.').count()));
        block.push("uncertainty QDA".into());
        block.extend(frame(&uncertainty));
        let mut points = vec![vec![b' '; width]; height];
        for row in &input.train {
            let column = plot::cell(row.values[fx], xmin, xmax, width);
            let r = height - 1 - plot::cell(row.values[fy], ymin, ymax, height);
            place(&mut points, r, column, input.classes[row.class].as_bytes()[0]);
        }
        block.push("points".into());
        block.extend(frame(&points));
        part(&mut lines, block);
    }
    lines
}

fn projection(input: &Input, models: &[Model]) -> Vec<String> {
    let stats = &models[0].statistics;
    let d = input.features.len();
    let classes = input.classes.len();
    let sw: Matrix = (0..d).map(|a| (0..d).map(|b| sum((0..classes).map(|k| stats.scatter[k][a][b]))).collect()).collect();
    let sb: Matrix = (0..d).map(|a| (0..d).map(|b| sum((0..classes).map(|k| stats.counts[k] as f64 * (stats.means[k][a] - stats.center[a]) * (stats.means[k][b] - stats.center[b])))).collect()).collect();
    let f: Vec<_> = (0..d).map(|j| (sb[j][j] / (classes - 1) as f64) / (sw[j][j] / (input.train.len() - classes) as f64)).collect();
    let mut feature_order: Vec<_> = (0..d).collect();
    feature_order.sort_by(|&a, &b| f[b].total_cmp(&f[a]).then(a.cmp(&b)));
    let mut lines = vec!["univariate".into()];
    for (rank, &j) in feature_order.iter().enumerate() { lines.push(format!("rank {} {} f {} between {} within {}", rank + 1, input.features[j], real(f[j]), real(sb[j][j]), real(sw[j][j]))); }
    let lower = cholesky(&sw);
    let mut y = vec![vec![0.0; d]; d];
    for j in 0..d {
        let column = forward(&lower, &(0..d).map(|i| sb[i][j]).collect::<Vec<_>>());
        for i in 0..d { y[i][j] = column[i]; }
    }
    let mut z = vec![vec![0.0; d]; d];
    for i in 0..d {
        let column = forward(&lower, &y[i]);
        for k in 0..d { z[k][i] = column[k]; }
    }
    let symmetric: Matrix = (0..d).map(|a| (0..d).map(|b| (z[a][b] + z[b][a]) / 2.0).collect()).collect();
    let (eigenvalues, eigenvectors, sweeps) = jacobi(&symmetric);
    let mut order: Vec<_> = (0..d).collect();
    order.sort_by(|&a, &b| eigenvalues[b].total_cmp(&eigenvalues[a]).then(a.cmp(&b)));
    let total = sum(eigenvalues.iter().copied());
    let mut directions = Vec::new();
    for &eigenvalue in order.iter().take(2) {
        let vector: Vec<_> = (0..d).map(|j| eigenvectors[j][eigenvalue]).collect();
        let mut direction = backward(&lower, &vector);
        let norm = sum(direction.iter().map(|v| v * v)).sqrt();
        for v in &mut direction { *v /= norm; }
        let greatest = first_max(&direction.iter().map(|v| v.abs()).collect::<Vec<_>>());
        if direction[greatest] < 0.0 { for v in &mut direction { *v = -*v; } }
        directions.push(direction);
    }
    let project = |values: &[f64]| -> Vec<f64> {
        directions.iter().map(|direction| sum(direction.iter().enumerate().map(|(j, &v)| v * (values[j] - stats.center[j])))).collect()
    };
    let projected_train: Vec<_> = input.train.iter().map(|row| project(&row.values)).collect();
    let projected_test: Vec<_> = input.test.iter().map(|row| project(&row.values)).collect();
    let centroids: Vec<_> = stats.means.iter().map(|mean| project(mean)).collect();
    let mut block = vec![format!("fisher features {}", input.features.join(" ")), format!("center {}", reals(&stats.center)), format!("sweeps {sweeps}"), format!("eigenvalues {}", reals(&order.iter().map(|&i| eigenvalues[i]).collect::<Vec<_>>())), format!("ratios {}", reals(&order.iter().map(|&i| eigenvalues[i] / total).collect::<Vec<_>>()))];
    for (i, direction) in directions.iter().enumerate() {
        block.push(format!("direction {} {}", i + 1, reals(direction)));
        block.push(format!("standardized {} {}", i + 1, reals(&(0..d).map(|j| direction[j] * models[1].covariance[0][j][j].sqrt()).collect::<Vec<_>>())));
    }
    for k in 0..classes {
        let spread: Vec<_> = (0..2).map(|t| (sum(input.train.iter().enumerate().filter(|(_, row)| row.class == k).map(|(i, _)| {
            let difference = projected_train[i][t] - centroids[k][t];
            difference * difference
        })) / stats.counts[k] as f64).sqrt()).collect();
        block.push(format!("centroid {} {} spread {}", input.classes[k], reals(&centroids[k]), reals(&spread)));
    }
    for dimensions in 1..=2 {
        let nearest = |points: &[Vec<f64>]| points.iter().map(|point| first_min(&centroids.iter().map(|centroid| sum((0..dimensions).map(|t| { let difference = point[t] - centroid[t]; difference * difference }))).collect::<Vec<_>>())).collect::<Vec<_>>();
        block.push(format!("nearest_centroid dims {} train {} test {}", dimensions, ratio(correct(&input.train, &nearest(&projected_train)), input.train.len()), ratio(correct(&input.test, &nearest(&projected_test)), input.test.len())));
    }
    part(&mut lines, block);
    let low1 = projected_train.iter().map(|z| z[0]).fold(f64::INFINITY, f64::min);
    let high1 = projected_train.iter().map(|z| z[0]).fold(f64::NEG_INFINITY, f64::max);
    let low2 = projected_train.iter().map(|z| z[1]).fold(f64::INFINITY, f64::min);
    let high2 = projected_train.iter().map(|z| z[1]).fold(f64::NEG_INFINITY, f64::max);
    let width = integer(input, "PLOT_SIZE");
    let height: usize = input.params["PLOT_SIZE"][1].parse().unwrap();
    let mut canvas = vec![vec![b' '; width]; height];
    for (row, point) in input.train.iter().zip(&projected_train) { place(&mut canvas, height - 1 - plot::cell(point[1], low2, high2, height), plot::cell(point[0], low1, high1, width), input.classes[row.class].as_bytes()[0]); }
    for (k, point) in centroids.iter().enumerate() { canvas[height - 1 - plot::cell(point[1], low2, high2, height)][plot::cell(point[0], low1, high1, width)] = input.classes[k].as_bytes()[0].to_ascii_uppercase(); }
    let mut block = vec![format!("plot x {} {} y {} {} size {}x{}", real(low1), real(high1), real(low2), real(high2), width, height)];
    block.extend(frame(&canvas));
    part(&mut lines, block);
    lines
}

fn main() {
    let input = dataset::read();
    let all: Vec<_> = (0..input.features.len()).collect();
    let models: Vec<_> = (0..3).map(|kind| main_model(&input, &input.train, &all, kind)).collect();
    let predictions: Vec<_> = models.iter().map(|model| predict_rows(&input, model, &input.test)).collect();
    let mut csv = vec![format!("id,model,actual,predicted,decision,{}", input.classes.join(","))];
    for (i, row) in input.test.iter().enumerate() {
        for kind in 0..3 {
            let prediction = &predictions[kind][i];
            csv.push(format!("{},{},{},{},{},{}", row.id, MODELS[kind], input.classes[row.class], input.classes[prediction.class], input.classes[prediction.decision], prediction.posterior.iter().map(|&p| real(p)).collect::<Vec<_>>().join(",")));
        }
    }
    fs::create_dir_all("output").unwrap();
    plot::write("models.txt", &models_report(&input, &models));
    plot::write("predictions.csv", &csv);
    plot::write("evaluation.txt", &evaluation_report(&input, &predictions));
    plot::write("boundaries.txt", &boundaries(&input));
    plot::write("projection.txt", &projection(&input, &models));
}
