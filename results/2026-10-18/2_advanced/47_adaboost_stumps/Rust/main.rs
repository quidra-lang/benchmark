mod dataset;
mod stumps;
mod adaboost;
mod variants;
mod evaluation;

use adaboost::{Model, Round};
use dataset::{Params, Row};
use evaluation::{fixed, real, ratio, prediction};
use std::io;

struct Generator(i64);

impl Generator {
    fn draw(&mut self) -> i64 {
        self.0 = 48271 * self.0 % 2147483647;
        self.0
    }
}

fn train(rows: &[Row], variant: &str, params: &Params) -> Model {
    if variant == "discrete" {
        adaboost::discrete(rows, params.rounds, 1.0, None)
    } else {
        variants::train(rows, variant, params)
    }
}

fn score(rounds: &[Round], x: &[f64]) -> f64 {
    rounds.iter().map(|r| r.stump.output(x)).sum()
}

fn scores(rounds: &[Round], rows: &[Row]) -> Vec<f64> {
    rows.iter().map(|r| score(rounds, &r.values)).collect()
}

fn magnitude(rounds: &[Round]) -> f64 {
    rounds.iter().map(|r| r.stump.magnitude()).sum()
}

fn errors(rows: &[Row], scores: &[f64]) -> usize {
    rows.iter().zip(scores).filter(|(r, f)| r.label != prediction(**f)).count()
}

fn loss(rows: &[Row], scores: &[f64], logit: bool) -> f64 {
    rows.iter().zip(scores).map(|(r, &f)| {
        if logit { (1.0 + (-2.0 * r.label as f64 * f).exp()).ln() }
        else { (-r.label as f64 * f).exp() }
    }).sum::<f64>() / rows.len() as f64
}

fn margins(rounds: &[Round], rows: &[Row]) -> Vec<f64> {
    let total = magnitude(rounds);
    rows.iter().map(|r| r.label as f64 * score(rounds, &r.values) / total).collect()
}

fn minimum(values: &[usize]) -> usize {
    let mut winner = 0;
    for i in 1..values.len() {
        if values[i] < values[winner] { winner = i; }
    }
    winner
}

fn descending(values: &[f64]) -> Vec<usize> {
    let mut order: Vec<usize> = (0..values.len()).collect();
    order.sort_by(|&a, &b| values[b].partial_cmp(&values[a]).unwrap().then(a.cmp(&b)));
    order
}

fn ints(values: &[usize]) -> String {
    values.iter().map(ToString::to_string).collect::<Vec<_>>().join(" ")
}

fn reals(values: &[f64]) -> String {
    values.iter().map(|&v| real(v)).collect::<Vec<_>>().join(" ")
}

fn metrics(kind: &str, variant: &str, rounds: usize, rows: &[Row], values: &[f64]) -> String {
    let (mut tp, mut fp, mut tn, mut fn_count) = (0usize, 0usize, 0usize, 0usize);
    for (row, &value) in rows.iter().zip(values) {
        match (row.label, prediction(value)) {
            (1, 1) => tp += 1,
            (-1, 1) => fp += 1,
            (-1, -1) => tn += 1,
            _ => fn_count += 1,
        }
    }
    format!("{} {} rounds {} correct {}/{} accuracy {} tp {} fp {} tn {} fn {} precision {} recall {} f1 {} auc {} loss {}",
        kind, variant, rounds, tp + tn, rows.len(), ratio(tp + tn, rows.len()), tp, fp, tn, fn_count,
        ratio(tp, tp + fp), ratio(tp, tp + fn_count), ratio(2 * tp, 2 * tp + fp + fn_count),
        evaluation::auc(rows, values), real(loss(rows, values, variant == "logit")))
}

struct CrossValidation {
    models: Vec<Model>,
    errors: Vec<usize>,
    fold_errors: Vec<Vec<usize>>,
    selected: usize,
    scores: Vec<f64>,
}

fn cross_validation(rows: &[Row], params: &Params) -> CrossValidation {
    let mut models = Vec::new();
    let mut total = vec![0; params.rounds];
    let mut fold_errors = Vec::new();
    for fold in 0..params.folds {
        let validation: Vec<usize> = (0..rows.len()).filter(|&i| i % params.folds == fold).collect();
        let n = rows.len() - validation.len();
        let weights: Vec<f64> = (0..rows.len()).map(|i| if i % params.folds == fold { 0.0 } else { 1.0 / n as f64 }).collect();
        let model = adaboost::discrete(rows, params.rounds, 1.0, Some(weights));
        let values: Vec<usize> = (1..=params.rounds).map(|t| {
            let prefix = &model.rounds[..t.min(model.rounds.len())];
            validation.iter().filter(|&&i| prediction(score(prefix, &rows[i].values)) != rows[i].label).count()
        }).collect();
        for t in 0..params.rounds { total[t] += values[t]; }
        fold_errors.push(values);
        models.push(model);
    }
    let selected = minimum(&total) + 1;
    let scores = rows.iter().enumerate().map(|(i, r)| {
        let model = &models[i % params.folds];
        score(&model.rounds[..selected.min(model.rounds.len())], &r.values)
    }).collect();
    CrossValidation { models, errors: total, fold_errors, selected, scores }
}

fn ensemble(variant: &str, model: &Model, names: &[String], rows: &[Row], params: &Params, cv: &CrossValidation) -> Vec<String> {
    let mut header = format!("variant {} rounds {} stop {}", variant, model.rounds.len(), model.stop);
    if variant == "real" {
        header += &format!(" bins {} smoothing {} convergence {}", params.bins, real(params.smoothing), fixed(params.convergence, 6));
    }
    if variant == "logit" { header += &format!(" clip {}", real(params.clip)); }
    let mut lines = vec![header];
    if variant == "real" {
        for j in 0..names.len() { lines.push(format!("cuts {} {}", names[j], reals(&model.cuts[j]))); }
    }
    for (index, r) in model.rounds.iter().enumerate() {
        let t = index + 1;
        let prefix = format!("round {} feature {}", t, names[r.stump.feature]);
        match variant {
            "discrete" => {
                lines.push(format!("{} threshold {} polarity {} error {} alpha {} z {} bound {}", prefix,
                    real(r.stump.thresholds[0]), r.polarity, real(r.error), real(r.alpha), real(r.z), real(r.bound)));
                let order = descending(&r.weights);
                let ess = 1.0 / r.weights.iter().map(|w| w * w).sum::<f64>();
                lines.push(format!("weights {} max {} id {} ess {}", t, fixed(r.weights[order[0]], 6), rows[order[0]].id, real(ess)));
            }
            "real" => lines.push(format!("{} z {} bound {} values {}", prefix, real(r.z), real(r.bound), reals(&r.stump.values))),
            _ => {
                let mut line = format!("{} threshold {} left {} right {} error {}", prefix,
                    real(r.stump.thresholds[0]), real(r.stump.values[0]), real(r.stump.values[1]), real(r.error));
                if variant == "logit" { line += &format!(" loss {}", real(r.loss)); }
                lines.push(line);
            }
        }
    }
    if variant == "discrete" {
        lines.push(format!("cv folds {} selected {} errors {}/{}", params.folds, cv.selected, cv.errors[cv.selected - 1], rows.len()));
        for fold in 0..params.folds {
            let validation = (0..rows.len()).filter(|i| i % params.folds == fold).count();
            lines.push(format!("fold {} train {} validation {} rounds {} stop {} selected {}/{} final {}/{}", fold + 1,
                rows.len() - validation, validation, cv.models[fold].rounds.len(), cv.models[fold].stop,
                cv.fold_errors[fold][cv.selected - 1], validation, cv.fold_errors[fold][params.rounds - 1], validation));
        }
        lines.push(format!("cv_errors {}", ints(&cv.errors)));
    }
    lines
}

fn importance(rounds: &[Round], d: usize, samme: bool) -> (Vec<f64>, Vec<usize>, Vec<usize>) {
    let mut values = vec![0.0; d];
    let mut counts = vec![0; d];
    for round in rounds {
        values[round.stump.feature] += if samme { round.alpha } else { round.stump.magnitude() };
        counts[round.stump.feature] += 1;
    }
    let order = descending(&values);
    (values, counts, order)
}

fn importance_lines(rounds: &[Round], names: &[String], samme: bool) -> Vec<String> {
    let (values, counts, order) = importance(rounds, names.len(), samme);
    let total: f64 = values.iter().sum();
    order.iter().enumerate().map(|(rank, &j)| format!("{} {} score {} share {} rounds {}", rank + 1,
        names[j], real(values[j]), real(values[j] / total), counts[j])).collect()
}

fn margin_report(variant: &str, rounds: &[Round], train: &[Row], test: &[Row], names: &[String], params: &Params,
    generator: &mut Generator) -> Vec<String> {
    let train_margins = margins(rounds, train);
    let test_margins = margins(rounds, test);
    let mut lines = vec![format!("variant {} rounds {} scale {}", variant, rounds.len(), real(magnitude(rounds))),
        format!("train min {} mean {}", real(train_margins.iter().copied().fold(f64::INFINITY, f64::min)),
            real(train_margins.iter().sum::<f64>() / train.len() as f64))];
    for &theta in &params.margins {
        let count = evaluation::below(&train_margins, theta);
        lines.push(format!("train le {} {}/{} {}", real(theta), count, train.len(), ratio(count, train.len())));
    }
    let mut histogram = vec![0; 20];
    for &margin in &train_margins { histogram[(((margin + 1.0) * 10.0).floor() as usize).min(19)] += 1; }
    lines.push(format!("histogram {}", ints(&histogram)));
    let mut hardest: Vec<usize> = (0..train.len()).collect();
    hardest.sort_by(|&a, &b| train_margins[a].partial_cmp(&train_margins[b]).unwrap().then(a.cmp(&b)));
    for &i in hardest.iter().take(5) {
        lines.push(format!("hardest {} label {} margin {}", train[i].id, train[i].label, real(train_margins[i])));
    }
    lines.push(format!("test min {} mean {}", real(test_margins.iter().copied().fold(f64::INFINITY, f64::min)),
        real(test_margins.iter().sum::<f64>() / test.len() as f64)));
    for &theta in &params.margins {
        let count = evaluation::below(&test_margins, theta);
        lines.push(format!("test le {} {}/{} {}", real(theta), count, test.len(), ratio(count, test.len())));
    }
    for &theta in &params.margins {
        let indices: Vec<usize> = (0..test.len()).filter(|&i| test_margins[i].abs() > theta).collect();
        let correct = indices.iter().filter(|&&i| prediction(score(rounds, &test[i].values)) == test[i].label).count();
        lines.push(format!("test confident {} {}/{} correct {}/{} {}", real(theta), indices.len(), test.len(), correct, indices.len(), ratio(correct, indices.len())));
    }
    lines.push("importance".into());
    lines.extend(importance_lines(rounds, names, false));
    let base = test.len() - errors(test, &scores(rounds, test));
    lines.push(format!("permutation repeats {} base {}/{}", params.permutations, base, test.len()));
    let mut drops = Vec::new();
    let mut bounds = Vec::new();
    for j in 0..names.len() {
        let mut counts = Vec::new();
        for _ in 0..params.permutations {
            let mut order: Vec<usize> = (0..test.len()).collect();
            for i in (1..test.len()).rev() {
                let k = generator.draw() as usize % (i + 1);
                order.swap(i, k);
            }
            let correct = (0..test.len()).filter(|&i| {
                let mut values = test[i].values.clone();
                values[j] = test[order[i]].values[j];
                prediction(score(rounds, &values)) == test[i].label
            }).count();
            counts.push(correct);
        }
        let drop = counts.iter().map(|&c| base as i64 - c as i64).sum::<i64>();
        drops.push(drop as f64);
        bounds.push((*counts.iter().min().unwrap(), *counts.iter().max().unwrap()));
    }
    for (rank, &j) in descending(&drops).iter().enumerate() {
        lines.push(format!("{} {} drop {} min {}/{} max {}/{}", rank + 1, names[j],
            real(drops[j] / (params.permutations * test.len()) as f64), bounds[j].0, test.len(), bounds[j].1, test.len()));
    }
    lines
}

fn shape_report(variant: &str, rounds: &[Round], names: &[String]) -> Vec<String> {
    let mut lines = vec![format!("variant {} rounds {}", variant, rounds.len())];
    for j in 0..names.len() {
        let selected: Vec<&Round> = rounds.iter().filter(|r| r.stump.feature == j).collect();
        let mut cuts: Vec<f64> = selected.iter().flat_map(|r| r.stump.thresholds.iter().copied()).collect();
        cuts.sort_by(|a, b| a.partial_cmp(b).unwrap());
        cuts.dedup();
        let values: Vec<f64> = (0..=cuts.len()).map(|h| selected.iter().map(|r| {
            let bin = if h == 0 { 0 } else { r.stump.thresholds.iter().filter(|&&t| t <= cuts[h - 1]).count() };
            r.stump.values[bin]
        }).sum()).collect();
        let range = values.iter().copied().fold(f64::NEG_INFINITY, f64::max) - values.iter().copied().fold(f64::INFINITY, f64::min);
        lines.push(format!("feature {} rounds {} cuts {} range {}", names[j], selected.len(), cuts.len(), real(range)));
        for h in 0..=cuts.len() {
            let lower = if h == 0 { "-inf".into() } else { real(cuts[h - 1]) };
            let upper = if h == cuts.len() { "inf".into() } else { real(cuts[h]) };
            lines.push(format!("interval {} {} value {}", lower, upper, real(values[h])));
        }
    }
    lines
}

fn class_scores(rounds: &[Round], values: &[f64], classes: usize) -> Vec<f64> {
    let mut output = vec![0.0; classes];
    for r in rounds { output[r.stump.output(values) as usize - 1] += r.alpha; }
    output
}

fn best_class(values: &[f64]) -> usize {
    let mut winner = 0;
    for j in 1..values.len() {
        if values[j] > values[winner] { winner = j; }
    }
    winner + 1
}

fn class_errors(rows: &[Row], predictions: &[usize]) -> usize {
    rows.iter().zip(predictions).filter(|(r, p)| r.label as usize != **p).count()
}

fn class_result(rows: &[Row], predictions: &[usize], kind: &str, classes: usize) -> Vec<String> {
    let count = class_errors(rows, predictions);
    let mut lines = vec![format!("{} errors {}/{} rate {}", kind, count, rows.len(), ratio(count, rows.len()))];
    if kind == "test" {
        let table = evaluation::confusion(rows, predictions, classes);
        lines.push("confusion".into());
        lines.extend(table.iter().map(|r| ints(r)));
        for k in 0..classes {
            lines.push(format!("class {} precision {} recall {}", k + 1, ratio(table[k][k], table.iter().map(|r| r[k]).sum()),
                ratio(table[k][k], table[k].iter().sum())));
        }
    }
    lines
}

fn multiclass(train: &[Row], test: &[Row], names: &[String], params: &Params) -> (Vec<String>, Vec<String>) {
    let classes = params.classes;
    let model = adaboost::samme(train, params.samme_rounds, classes);
    let mut lines = vec![format!("samme classes {} train {} test {} rounds {} stop {}", classes, train.len(), test.len(), model.rounds.len(), model.stop)];
    for (t, r) in model.rounds.iter().enumerate() {
        lines.push(format!("round {} feature {} threshold {} left {} right {} error {} alpha {}", t + 1, names[r.stump.feature],
            real(r.stump.thresholds[0]), r.stump.values[0] as usize, r.stump.values[1] as usize, real(r.error), real(r.alpha)));
    }
    let train_predictions: Vec<usize> = train.iter().map(|r| best_class(&class_scores(&model.rounds, &r.values, classes))).collect();
    let test_scores: Vec<Vec<f64>> = test.iter().map(|r| class_scores(&model.rounds, &r.values, classes)).collect();
    let test_predictions: Vec<usize> = test_scores.iter().map(|v| best_class(v)).collect();
    lines.extend(class_result(train, &train_predictions, "train", classes));
    lines.extend(class_result(test, &test_predictions, "test", classes));
    lines.push("importance".into());
    lines.extend(importance_lines(&model.rounds, names, true));
    lines.extend([String::new(), format!("ovr classes {} rounds {}", classes, params.samme_rounds)]);
    let mut ovr = Vec::new();
    for class in 1..=classes {
        let relabel = |rows: &[Row]| rows.iter().map(|r| {
            let mut row = r.clone();
            row.label = if r.label as usize == class { 1 } else { -1 };
            row
        }).collect::<Vec<_>>();
        let binary_train = relabel(train);
        let binary_test = relabel(test);
        let binary = adaboost::discrete(&binary_train, params.samme_rounds, 1.0, None);
        lines.push(format!("class {} rounds {} stop {} positives {} train_errors {}/{} test_errors {}/{}", class, binary.rounds.len(), binary.stop,
            train.iter().filter(|r| r.label as usize == class).count(), errors(&binary_train, &scores(&binary.rounds, &binary_train)), train.len(),
            errors(&binary_test, &scores(&binary.rounds, &binary_test)), test.len()));
        ovr.push(binary);
    }
    let predict_ovr = |rows: &[Row]| rows.iter().map(|r| best_class(&ovr.iter().map(|m| score(&m.rounds, &r.values)).collect::<Vec<_>>())).collect::<Vec<_>>();
    let ovr_train = predict_ovr(train);
    let ovr_test = predict_ovr(test);
    lines.extend(class_result(train, &ovr_train, "train", classes));
    lines.extend(class_result(test, &ovr_test, "test", classes));
    lines.extend([format!("agreement {}/{}", test_predictions.iter().zip(&ovr_test).filter(|(a, b)| a == b).count(), test.len()),
        String::new(), "predictions".into()]);
    for i in 0..test.len() {
        lines.push(format!("{} class {} samme {} ovr {} scores {}", test[i].id, test[i].label, test_predictions[i], ovr_test[i], reals(&test_scores[i])));
    }
    let mut curve = Vec::new();
    for t in 1..=model.rounds.len() {
        let predict = |rows: &[Row]| rows.iter().map(|r| best_class(&class_scores(&model.rounds[..t], &r.values, classes))).collect::<Vec<_>>();
        curve.push(format!("samme,{},{},{},-,-,-", t, ratio(class_errors(train, &predict(train)), train.len()), ratio(class_errors(test, &predict(test)), test.len())));
    }
    (lines, curve)
}

fn experiment_result(model: &Model, train: &[Row], test: &[Row]) -> String {
    format!("rounds {} stop {} train_errors {}/{} test_errors {}/{}", model.rounds.len(), model.stop,
        errors(train, &scores(&model.rounds, train)), train.len(), errors(test, &scores(&model.rounds, test)), test.len())
}

fn test_minimum(model: &Model, rows: &[Row]) -> (usize, usize) {
    let values: Vec<usize> = (1..=model.rounds.len()).map(|t| errors(rows, &scores(&model.rounds[..t], rows))).collect();
    let i = minimum(&values);
    (values[i], i + 1)
}

fn experiments(train_rows: &[Row], test: &[Row], names: &[String], params: &Params, selected: usize, discrete: &[Round]) -> Vec<String> {
    let mut lines = Vec::new();
    let n = train_rows.len();
    for &q in &params.sizes {
        let s = n * q / 100;
        let rows = &train_rows[..s];
        lines.push(format!("size {} rows {}", q, s));
        for variant in &params.variants {
            let model = train(rows, variant, params);
            lines.push(format!("{} {}", variant, experiment_result(&model, rows, test)));
        }
    }
    for &nu in &params.shrinkage {
        let model = adaboost::discrete(train_rows, params.rounds, nu, None);
        let (count, t) = test_minimum(&model, test);
        lines.push(format!("shrinkage {} {} test_min {}/{} at {}", real(nu), experiment_result(&model, train_rows, test), count, test.len(), t));
    }
    let (_, _, order) = importance(discrete, names.len(), false);
    for k in 1..=names.len() {
        let mut features = order[..k].to_vec();
        features.sort();
        let restrict = |rows: &[Row]| rows.iter().map(|r| Row { id: r.id.clone(), values: features.iter().map(|&j| r.values[j]).collect(), label: r.label }).collect::<Vec<_>>();
        let rows = restrict(train_rows);
        let test_rows = restrict(test);
        let model = adaboost::discrete(&rows, selected, 1.0, None);
        lines.push(format!("top {} features {} rounds {} train_errors {}/{} test_errors {}/{}", k,
            features.iter().map(|&j| names[j].as_str()).collect::<Vec<_>>().join(" "), model.rounds.len(),
            errors(&rows, &scores(&model.rounds, &rows)), n, errors(&test_rows, &scores(&model.rounds, &test_rows)), test.len()));
    }
    for &q in &params.noise {
        let f = n * q / 100;
        let mut generator = Generator(params.noise_seed);
        let mut order: Vec<usize> = (0..n).collect();
        for i in 0..f {
            let j = generator.draw() as usize % (n - i) + i;
            order.swap(i, j);
        }
        let mut flipped = vec![false; n];
        let mut rows = train_rows.to_vec();
        for &i in &order[..f] { flipped[i] = true; rows[i].label = -rows[i].label; }
        lines.push(format!("noise {} flipped {}", q, f));
        for variant in &params.variants {
            let model = train(&rows, variant, params);
            let (count, t) = test_minimum(&model, test);
            let weights = &model.rounds.last().unwrap().weights;
            let weight: f64 = (0..n).filter(|&i| flipped[i]).map(|i| weights[i]).sum();
            lines.push(format!("{} {} test_min {}/{} at {} flipped_weight {}", variant, experiment_result(&model, &rows, test), count, test.len(), t, real(weight)));
        }
    }
    lines
}

fn main() -> io::Result<()> {
    let data = dataset::read()?;
    let params = &data.params;
    let train_rows = &data.train;
    let test = &data.test;
    let names = &data.names;
    let (n, m, d) = (train_rows.len(), test.len(), names.len());
    let cv = cross_validation(train_rows, params);
    let models: Vec<Model> = params.variants.iter().map(|v| train(train_rows, v, params)).collect();
    let final_rounds: Vec<&[Round]> = models.iter().zip(&params.variants).map(|(model, variant)| {
        let count = if variant == "discrete" { cv.selected.min(model.rounds.len()) } else { model.rounds.len() };
        &model.rounds[..count]
    }).collect();
    let train_scores: Vec<Vec<f64>> = final_rounds.iter().map(|r| scores(r, train_rows)).collect();
    let test_scores: Vec<Vec<f64>> = final_rounds.iter().map(|r| scores(r, test)).collect();
    let scales: Vec<f64> = final_rounds.iter().map(|r| magnitude(r)).collect();
    let mut ensembles = Vec::new();
    let mut curves = vec!["variant,round,train_error,test_error,train_loss,test_loss,min_margin".into()];
    let mut curve_counts = Vec::new();
    let mut margin_lines = Vec::new();
    let mut shapes = Vec::new();
    let mut permutation_generator = Generator(params.permutation_seed);
    for (v, variant) in params.variants.iter().enumerate() {
        if v > 0 { ensembles.push(String::new()); margin_lines.push(String::new()); shapes.push(String::new()); }
        ensembles.extend(ensemble(variant, &models[v], names, train_rows, params, &cv));
        let (mut train_counts, mut test_counts) = (Vec::new(), Vec::new());
        for t in 1..=models[v].rounds.len() {
            let rounds = &models[v].rounds[..t];
            let a = scores(rounds, train_rows);
            let b = scores(rounds, test);
            let (ea, eb) = (errors(train_rows, &a), errors(test, &b));
            train_counts.push(ea);
            test_counts.push(eb);
            let min_margin = margins(rounds, train_rows).iter().copied().fold(f64::INFINITY, f64::min);
            curves.push(format!("{},{},{},{},{},{},{}", variant, t, ratio(ea, n), ratio(eb, m), real(loss(train_rows, &a, variant == "logit")),
                real(loss(test, &b, variant == "logit")), real(min_margin)));
        }
        curve_counts.push((train_counts, test_counts));
        margin_lines.extend(margin_report(variant, final_rounds[v], train_rows, test, names, params, &mut permutation_generator));
        shapes.extend(shape_report(variant, final_rounds[v], names));
    }
    let (samme_lines, samme_curve) = multiclass(&data.multi_train, &data.multi_test, &data.multi_names, params);
    curves.extend(samme_curve);
    let mut prediction_lines = vec![format!("id,variant,score,label,{}", names.join(","))];
    for i in 0..m {
        for (v, variant) in params.variants.iter().enumerate() {
            let contributions: Vec<f64> = (0..d).map(|j| final_rounds[v].iter().filter(|r| r.stump.feature == j).map(|r| r.stump.output(&test[i].values)).sum()).collect();
            prediction_lines.push(format!("{},{},{},{},{}", test[i].id, variant, real(test_scores[v][i]), prediction(test_scores[v][i]),
                contributions.iter().map(|&x| real(x)).collect::<Vec<_>>().join(",")));
        }
    }
    let mut roc = vec!["variant,threshold,tp,fp".into()];
    for (v, variant) in params.variants.iter().enumerate() {
        let mut distinct = test_scores[v].clone();
        distinct.sort_by(|a, b| b.partial_cmp(a).unwrap());
        distinct.dedup();
        for threshold in distinct {
            let tp = (0..m).filter(|&i| test_scores[v][i] >= threshold && test[i].label == 1).count();
            let fp = (0..m).filter(|&i| test_scores[v][i] >= threshold && test[i].label == -1).count();
            roc.push(format!("{},{},{},{}", variant, real(threshold), tp, fp));
        }
    }
    let mut summary = vec![format!("data train {} test {} features {} positives {} {}", n, m, d,
        train_rows.iter().filter(|r| r.label == 1).count(), test.iter().filter(|r| r.label == 1).count())];
    for j in 0..d {
        let stats = |rows: &[Row]| {
            let mut values: Vec<f64> = rows.iter().map(|r| r.values[j]).collect();
            let mean = values.iter().sum::<f64>() / rows.len() as f64;
            values.sort_by(|a, b| a.partial_cmp(b).unwrap());
            values.dedup();
            format!("{} {} {} {}", real(values[0]), real(*values.last().unwrap()), real(mean), values.len())
        };
        summary.push(format!("feature {} train {} test {}", names[j], stats(train_rows), stats(test)));
    }
    summary.extend([format!("cv selected {} errors {}/{} rate {}", cv.selected, cv.errors[cv.selected - 1], n, ratio(cv.errors[cv.selected - 1], n)),
        metrics("oof", "discrete", cv.selected, train_rows, &cv.scores)]);
    for (v, variant) in params.variants.iter().enumerate() {
        summary.push(metrics("train", variant, final_rounds[v].len(), train_rows, &train_scores[v]));
        summary.push(metrics("test", variant, final_rounds[v].len(), test, &test_scores[v]));
    }
    let committee = |values: &[Vec<f64>], count: usize| (0..count).map(|i|
        (0..params.variants.len()).map(|v| values[v][i] / scales[v]).sum::<f64>()).collect::<Vec<_>>();
    let total_rounds: usize = final_rounds.iter().map(|r| r.len()).sum();
    summary.push(metrics("train", "committee", total_rounds, train_rows, &committee(&train_scores, n)));
    summary.push(metrics("test", "committee", total_rounds, test, &committee(&test_scores, m)));
    for (v, variant) in params.variants.iter().enumerate() {
        let (a, b) = &curve_counts[v];
        let (ta, tb) = (minimum(a), minimum(b));
        summary.push(format!("curve {} rounds {} train_min {}/{} at {} test_min {}/{} at {}", variant, models[v].rounds.len(), a[ta], n, ta + 1, b[tb], m, tb + 1));
    }
    let all_wrong: Vec<&str> = (0..m).filter(|&i| test_scores.iter().all(|s| prediction(s[i]) != test[i].label)).map(|i| test[i].id.as_str()).collect();
    summary.push(if all_wrong.is_empty() { "all_wrong 0".into() } else { format!("all_wrong {} {}", all_wrong.len(), all_wrong.join(" ")) });
    summary.push("agreement".into());
    for a in 0..params.variants.len() {
        for b in a + 1..params.variants.len() {
            let agree = (0..m).filter(|&i| prediction(test_scores[a][i]) == prediction(test_scores[b][i])).count();
            let first = (0..m).filter(|&i| prediction(test_scores[a][i]) == test[i].label && prediction(test_scores[b][i]) != test[i].label).count();
            let second = (0..m).filter(|&i| prediction(test_scores[b][i]) == test[i].label && prediction(test_scores[a][i]) != test[i].label).count();
            let delta = (first as i64 - second as i64).abs() - 1;
            summary.push(format!("{} {} agree {}/{} only_first {} only_second {} chi2 {}", params.variants[a], params.variants[b], agree, m, first, second,
                ratio((delta * delta) as usize, first + second)));
        }
    }
    summary.push(format!("bootstrap samples {} seed {}", params.bootstrap, params.bootstrap_seed));
    let mut generator = Generator(params.bootstrap_seed);
    let mut bootstrap = vec![Vec::new(); params.variants.len()];
    for _ in 0..params.bootstrap {
        let sample: Vec<usize> = (0..m).map(|_| generator.draw() as usize % m).collect();
        for v in 0..params.variants.len() {
            bootstrap[v].push(sample.iter().filter(|&&i| prediction(test_scores[v][i]) == test[i].label).count());
        }
    }
    let g = params.bootstrap / 40;
    for (v, variant) in params.variants.iter().enumerate() {
        let mut ordered = bootstrap[v].clone();
        ordered.sort();
        summary.push(format!("{} mean {} low {} high {}", variant, ratio(bootstrap[v].iter().sum(), params.bootstrap * m),
            ratio(ordered[g], m), ratio(ordered[params.bootstrap - g - 1], m)));
    }
    for a in 0..params.variants.len() {
        for b in a + 1..params.variants.len() {
            let first = (0..params.bootstrap).filter(|&i| bootstrap[a][i] > bootstrap[b][i]).count();
            let ties = (0..params.bootstrap).filter(|&i| bootstrap[a][i] == bootstrap[b][i]).count();
            summary.push(format!("{} {} first {} tie {} second {}", params.variants[a], params.variants[b], first, ties, params.bootstrap - first - ties));
        }
    }
    for (v, variant) in params.variants.iter().enumerate() {
        let probabilities: Vec<f64> = test_scores[v].iter().map(|f| 1.0 / (1.0 + (-2.0 * f).exp())).collect();
        let brier = (0..m).map(|i| {
            let y = if test[i].label == 1 { 1.0 } else { 0.0 };
            (probabilities[i] - y) * (probabilities[i] - y)
        }).sum::<f64>() / m as f64;
        summary.push(format!("calibration {} brier {}", variant, real(brier)));
        for (bin, range) in ["0.0-0.2", "0.2-0.4", "0.4-0.6", "0.6-0.8", "0.8-1.0"].iter().enumerate() {
            let indices: Vec<usize> = (0..m).filter(|&i| ((probabilities[i] * 5.0).floor() as usize).min(4) == bin).collect();
            let mean = if indices.is_empty() { "-".into() } else { real(indices.iter().map(|&i| probabilities[i]).sum::<f64>() / indices.len() as f64) };
            summary.push(format!("bin {} count {} mean {} positives {}", range, indices.len(), mean, indices.iter().filter(|&&i| test[i].label == 1).count()));
        }
    }
    let discrete = params.variants.iter().position(|v| v == "discrete").unwrap();
    let experiment_lines = experiments(train_rows, test, names, params, cv.selected, final_rounds[discrete]);
    for (name, lines) in [("ensemble.txt", ensembles), ("error_curve.csv", curves), ("predictions.csv", prediction_lines),
        ("roc.csv", roc), ("margins.txt", margin_lines), ("shapes.txt", shapes), ("samme.txt", samme_lines),
        ("summary.txt", summary), ("experiments.txt", experiment_lines)] {
        evaluation::write(name, &lines)?;
    }
    Ok(())
}
