mod dataset;
mod kernels;
mod smo;
mod multiclass;
mod evaluation;

use dataset::{Example, Settings};
use kernels::{Kernel, Kind};
use smo::Model;
use evaluation::{real, ratio, sign};

struct FoldResult { training: usize, test: usize, correct: usize, support: usize, passes: usize, steps: usize, converged: bool }
struct CrossValidation { folds: Vec<FoldResult>, values: Vec<f64>, correct: usize }

fn cross_validation(data: &[Example], kernel: &Kernel, matrix: &[Vec<f64>], c: f64, params: &Settings) -> CrossValidation {
    let mut result = CrossValidation { folds: Vec::new(), values: vec![0.0; data.len()], correct: 0 };
    for fold in 0..params.folds {
        let (training, test) = evaluation::folds(data.len(), params.folds, fold);
        let points: Vec<_> = training.iter().map(|&i| data[i].point).collect();
        let labels: Vec<_> = training.iter().map(|&i| data[i].label as f64).collect();
        let q: Vec<Vec<_>> = training.iter().map(|&i| training.iter().map(|&j| matrix[i][j]).collect()).collect();
        let model = smo::train(&points, &labels, &q, c, params);
        let mut correct = 0;
        for &i in &test {
            result.values[i] = model.decision(kernel, data[i].point);
            correct += usize::from(sign(result.values[i]) == data[i].label);
        }
        result.correct += correct;
        result.folds.push(FoldResult { training: training.len(), test: test.len(), correct, support: model.support().0,
            passes: model.passes.len(), steps: model.steps, converged: model.converged });
    }
    result
}

fn yes(value: bool) -> &'static str { if value { "yes" } else { "no" } }
fn run_info(model: &Model) -> String { format!("passes {} steps {} converged {}", model.passes.len(), model.steps, yes(model.converged)) }
fn sv_info(model: &Model) -> String {
    let (total, bound, free) = model.support();
    format!("support_vectors {} bound {} free {}", total, bound, free)
}
fn values(model: &Model, kernel: &Kernel, data: &[Example]) -> Vec<f64> { data.iter().map(|e| model.decision(kernel, e.point)).collect() }
fn weights(model: &Model) -> [f64; 2] {
    let mut result = [0.0; 2];
    for i in 0..model.alpha.len() {
        result[0] += model.alpha[i]*model.labels[i]*model.points[i][0];
        result[1] += model.alpha[i]*model.labels[i]*model.points[i][1];
    }
    result
}

fn model_report(model: &Model, kernel: &Kernel, matrix: &[Vec<f64>], train: &[Example], test: &[Example], params: &Settings) -> Vec<String> {
    let (n, m) = (train.len(), test.len());
    let f = values(model, kernel, train);
    let predicted = values(model, kernel, test);
    let (q, dual) = smo::objective(&model.alpha, &model.labels, matrix);
    let mut sy = 0.0;
    let mut sg = 0.0;
    for i in 0..n { for j in 0..n { sy += model.labels[i]*model.labels[j]*matrix[i][j]; sg += matrix[i][j]*matrix[i][j]; } }
    let equality: f64 = model.alpha.iter().zip(&model.labels).map(|(a, y)| a*y).sum();
    let norm = q.sqrt();
    let xi: Vec<_> = (0..n).map(|i| 0.0_f64.max(1.0-model.labels[i]*f[i])).collect();
    let primal = q/2.0+model.c*xi.iter().sum::<f64>();
    let mut violations = Vec::new();
    let mut classes = [[0; 2]; 2];
    for i in 0..n {
        let r = model.labels[i]*f[i]-1.0;
        violations.push(if model.alpha[i] == 0.0 { 0.0_f64.max(-r) }
            else if model.alpha[i] == model.c { 0.0_f64.max(r) } else { r.abs() });
        if model.alpha[i] > 0.0 {
            classes[usize::from(model.labels[i] < 0.0)][usize::from(model.alpha[i] < model.c)] += 1;
        }
    }
    let radius = (0..n).map(|i| matrix[i][i]).fold(f64::NEG_INFINITY, f64::max)
        - matrix.iter().flatten().copied().fold(f64::INFINITY, f64::min);
    let estimated = (0..n).filter(|&i| 2.0*model.alpha[i]*radius+xi[i] >= 1.0).count();
    let [tp, fp, tn, fn_count] = evaluation::binary(test, &predicted);
    let train_correct = evaluation::correct(train, &f);
    let mut lines = vec![format!("model {}", kernel.name), format!("kernel {}", kernel.description()),
        format!("C {}", real(model.c, 4)), format!("alignment {}", real(sy/(n as f64*sg.sqrt()), 6)),
        format!("passes {} full {} nonbound {} converged {}", model.passes.len(), model.full, model.nonbound, yes(model.converged)),
        format!("examined {} steps {}", model.examined, model.steps),
        format!("choice heuristic {} nonbound_loop {} full_loop {}", model.choices[0], model.choices[1], model.choices[2]),
        format!("clipping none {} lower {} upper {}", model.clipping[0], model.clipping[1], model.clipping[2]),
        sv_info(model), format!("b {}", real(model.b, 6)), format!("equality {}", real(equality, 6))];
    if matches!(kernel.kind, Kind::Linear) {
        let w = weights(model);
        lines.push(format!("w {} {}", real(w[0], 6), real(w[1], 6)));
    }
    lines.extend([
        format!("sv_by_class positive bound {} free {} negative bound {} free {}", classes[0][0], classes[0][1], classes[1][0], classes[1][1]),
        format!("norm {} margin {}", real(norm, 6), real(2.0/norm, 6)),
        format!("dual_objective {}", real(dual, 6)), format!("primal_objective {}", real(primal, 6)),
        format!("duality_gap {}", real(primal-dual, 6)),
        format!("kkt_violations {} max {}", violations.iter().filter(|&&v| v > params.tolerance).count(), real(violations.iter().copied().fold(0.0, f64::max), 6)),
        format!("xi_alpha radius {} errors {}/{} accuracy {}", real(radius, 6), estimated, n, ratio(n-estimated, n)),
        format!("train correct {}/{} accuracy {}", train_correct, n, ratio(train_correct, n)),
        format!("test correct {}/{} accuracy {} tp {} fp {} tn {} fn {}", tp+tn, m, ratio(tp+tn, m), tp, fp, tn, fn_count),
        format!("test precision {} recall {} f1 {} auc {}", ratio(tp, tp+fp), ratio(tp, tp+fn_count), ratio(2*tp, 2*tp+fp+fn_count), real(evaluation::auc(test, &predicted), 4)),
        format!("test inside_margin {}", predicted.iter().filter(|&&v| v.abs() < 1.0).count()),
    ]);
    let mean = |label| {
        let mut sum = 0.0;
        let mut count = 0;
        for (e, &v) in test.iter().zip(&predicted) { if e.label == label { sum += v; count += 1; } }
        sum/count as f64
    };
    lines.push(format!("test mean_decision positive {} negative {}", real(mean(1), 4), real(mean(-1), 4)));
    for i in 0..n {
        if model.alpha[i] > 0.0 { lines.push(format!("sv {} y {} alpha {} f {} {}", train[i].id, train[i].label,
            real(model.alpha[i], 6), real(f[i], 4), if model.alpha[i] == model.c { "bound" } else { "free" })); }
    }
    lines
}

fn probability(v: f64, a: f64, b: f64) -> f64 { 1.0/(1.0+(a*v+b).exp()) }

fn calibration(cv: &[f64], train: &[Example], test_values: &[f64], test: &[Example], kernel: &Kernel, c: f64, iterations: usize) -> (f64, f64, Vec<f64>, Vec<String>) {
    let positive = train.iter().filter(|e| e.label == 1).count();
    let negative = train.len()-positive;
    let target: Vec<_> = train.iter().map(|e| if e.label == 1 { (positive+1) as f64/(positive+2) as f64 } else { 1.0/(negative+2) as f64 }).collect();
    let (mut a, mut b) = (0.0, ((negative+1) as f64/(positive+1) as f64).ln());
    let nll = |a, b| {
        let mut sum = 0.0;
        for i in 0..cv.len() {
            let p = probability(cv[i], a, b);
            sum += target[i]*p.ln()+(1.0-target[i])*(1.0-p).ln();
        }
        -sum
    };
    let mut lines = vec![format!("calibration {} C {} positives {} negatives {}", kernel.name, real(c, 4), positive, negative),
        format!("start A {} B {} nll {}", real(a, 6), real(b, 6), real(nll(a, b), 6))];
    for iteration in 1..=iterations {
        let (mut g1, mut g2, mut h11, mut h21, mut h22) = (0.0, 0.0, 0.0, 0.0, 0.0);
        for i in 0..cv.len() {
            let p = probability(cv[i], a, b);
            g1 += cv[i]*(target[i]-p);
            g2 += target[i]-p;
            h11 += cv[i]*cv[i]*p*(1.0-p);
            h21 += cv[i]*p*(1.0-p);
            h22 += p*(1.0-p);
        }
        let det = h11*h22-h21*h21;
        a -= (h22*g1-h21*g2)/det;
        b -= (h11*g2-h21*g1)/det;
        lines.push(format!("iteration {} A {} B {} nll {}", iteration, real(a, 6), real(b, 6), real(nll(a, b), 6)));
    }
    let probabilities: Vec<_> = test_values.iter().map(|&v| probability(v, a, b)).collect();
    let mut loss = 0.0;
    let mut brier = 0.0;
    let mut bins = [(0usize, 0usize, 0.0); 5];
    for (e, &p) in test.iter().zip(&probabilities) {
        loss += if e.label == 1 { p.ln() } else { (1.0-p).ln() };
        let error = p-if e.label == 1 { 1.0 } else { 0.0 };
        brier += error*error;
        let bin = ((p*5.0).floor() as usize).min(4);
        bins[bin].0 += 1;
        bins[bin].1 += usize::from(e.label == 1);
        bins[bin].2 += p;
    }
    lines.push(format!("test log_loss {} brier {}", real(-loss/test.len() as f64, 6), real(brier/test.len() as f64, 6)));
    for (i, &(count, positives, sum)) in bins.iter().enumerate() {
        lines.push(format!("bin {} count {} mean_probability {} positive_rate {}", ["0.0-0.2", "0.2-0.4", "0.4-0.6", "0.6-0.8", "0.8-1.0"][i],
            count, if count == 0 { "-".to_owned() } else { real(sum/count as f64, 4) }, ratio(positives, count)));
    }
    let mut closest: Vec<_> = (0..test.len()).collect();
    closest.sort_by(|&i, &j| test_values[i].abs().total_cmp(&test_values[j].abs()).then(i.cmp(&j)));
    for &i in closest.iter().take(5) { lines.push(format!("closest {} label {} decision {} probability {}", test[i].id, test[i].label,
        real(test_values[i], 4), real(probabilities[i], 4))); }
    (a, b, probabilities, lines)
}

fn psi(w: [f64; 3], point: [f64; 2]) -> f64 { w[0]*point[0]+w[1]*point[1]+w[2] }

fn pegasos(train: &[Example], test: &[Example], params: &Settings, kernel: &Kernel, model: &Model) -> ([f64; 3], Vec<f64>, Vec<String>) {
    let mut state = params.seed;
    let mut w = [0.0; 3];
    let mut sum = [0.0; 3];
    let mut updates = 0;
    let mut lines = vec![format!("pegasos lambda {} iterations {} seed {}", real(params.lambda, 4), params.iterations, params.seed)];
    for t in 1..=params.iterations {
        state = 48271*state%2147483647;
        let e = &train[state as usize%train.len()];
        let eta = 1.0/(params.lambda*t as f64);
        let sigma = 1.0-eta*params.lambda;
        let update = e.label as f64*psi(w, e.point) < 1.0;
        if update { updates += 1; }
        let x = [e.point[0], e.point[1], 1.0];
        for k in 0..3 {
            w[k] = if update { sigma*w[k]+eta*e.label as f64*x[k] } else { sigma*w[k] };
            sum[k] += w[k];
        }
        if t%(params.iterations/10) == 0 {
            let v: Vec<_> = train.iter().map(|e| psi(w, e.point)).collect();
            let xi: f64 = train.iter().zip(&v).map(|(e, &v)| 0.0_f64.max(1.0-e.label as f64*v)).sum();
            let objective = params.lambda/2.0*(w[0]*w[0]+w[1]*w[1]+w[2]*w[2])+xi/train.len() as f64;
            lines.push(format!("checkpoint {} objective {} train {}/{}", t, real(objective, 6), evaluation::correct(train, &v), train.len()));
        }
    }
    let average = sum.map(|v| v/params.iterations as f64);
    let train_values: Vec<_> = train.iter().map(|e| psi(w, e.point)).collect();
    let test_values: Vec<_> = test.iter().map(|e| psi(w, e.point)).collect();
    let average_values: Vec<_> = test.iter().map(|e| psi(average, e.point)).collect();
    let train_correct = evaluation::correct(train, &train_values);
    let test_correct = evaluation::correct(test, &test_values);
    let v = weights(model);
    let cosine = (w[0]*v[0]+w[1]*v[1])/((w[0]*w[0]+w[1]*w[1]).sqrt()*(v[0]*v[0]+v[1]*v[1]).sqrt());
    let agree = test.iter().zip(&test_values).filter(|(e, p)| sign(**p) == sign(model.decision(kernel, e.point))).count();
    lines.extend([
        format!("updates {}", updates), format!("w {} {} bias {}", real(w[0], 6), real(w[1], 6), real(w[2], 6)),
        format!("train correct {}/{} accuracy {}", train_correct, train.len(), ratio(train_correct, train.len())),
        format!("test correct {}/{} accuracy {}", test_correct, test.len(), ratio(test_correct, test.len())),
        format!("average w {} {} bias {} test correct {}/{}", real(average[0], 6), real(average[1], 6), real(average[2], 6), evaluation::correct(test, &average_values), test.len()),
        format!("compare {} cosine {} test_agreement {}/{}", kernel.name, real(cosine, 6), agree, test.len()),
    ]);
    (w, test_values, lines)
}

fn multi_report(models: &multiclass::Models, train: &[Example], test: &[Example], kernel: &Kernel, params: &Settings) -> Vec<String> {
    let mut lines = vec![format!("multiclass kernel {} C {} classes 3 train {} test {}", kernel.name, real(params.multi_c, 4), train.len(), test.len()), "ovr".to_owned()];
    for (k, model) in models.rest.iter().enumerate() {
        let positive = model.labels.iter().filter(|&&y| y == 1.0).count();
        let correct = test.iter().filter(|e| sign(model.decision(kernel, e.point)) == if e.label == k as i32+1 { 1 } else { -1 }).count();
        lines.push(format!("model {}-rest examples {} positives {} {} b {} {} test {}/{}", k+1, train.len(), positive,
            sv_info(model), real(model.b, 6), run_info(model), correct, test.len()));
    }
    lines.push("ovo".to_owned());
    for (i, (a, b)) in [(1, 2), (1, 3), (2, 3)].iter().copied().enumerate() {
        let model = &models.pairs[i];
        let relevant: Vec<_> = test.iter().filter(|e| e.label == a || e.label == b).collect();
        let correct = relevant.iter().filter(|e| sign(model.decision(kernel, e.point)) == if e.label == a { 1 } else { -1 }).count();
        let positive = model.labels.iter().filter(|&&y| y == 1.0).count();
        lines.push(format!("model {}-{} examples {} positives {} {} b {} {} test {}/{}", a, b, model.points.len(), positive,
            sv_info(model), real(model.b, 6), run_info(model), correct, relevant.len()));
    }
    lines.push("predictions".to_owned());
    let predictions: Vec<_> = test.iter().map(|e| models.classify(kernel, e.point)).collect();
    for (e, p) in test.iter().zip(&predictions) {
        lines.push(format!("{} class {} ovr {} pred {} ovo {} votes {} {} {} pred {}", e.id, e.label,
            p.rest_values.iter().map(|&v| real(v, 4)).collect::<Vec<_>>().join(" "), p.rest,
            p.pair_values.iter().map(|&v| real(v, 4)).collect::<Vec<_>>().join(" "), p.votes[0], p.votes[1], p.votes[2], p.one));
    }
    for (name, data) in [("train", train), ("test", test)] {
        let predictions: Vec<_> = data.iter().map(|e| models.classify(kernel, e.point)).collect();
        let rest = data.iter().zip(&predictions).filter(|(e, p)| e.label as usize == p.rest).count();
        let one = data.iter().zip(&predictions).filter(|(e, p)| e.label as usize == p.one).count();
        let agree = predictions.iter().filter(|p| p.rest == p.one).count();
        let ties = predictions.iter().filter(|p| p.tie).count();
        lines.push(format!("{} ovr {}/{} {} ovo {}/{} {} agreement {}/{} vote_ties {}", name, rest, data.len(),
            ratio(rest, data.len()), one, data.len(), ratio(one, data.len()), agree, data.len(), ties));
    }
    for rest in [true, false] {
        lines.push(format!("confusion {}", if rest { "ovr" } else { "ovo" }));
        let actual: Vec<_> = test.iter().map(|e| e.label as usize).collect();
        let predicted: Vec<_> = predictions.iter().map(|p| if rest { p.rest } else { p.one }).collect();
        let confusion = evaluation::confusion(&actual, &predicted);
        for row in confusion { lines.push(row.iter().map(usize::to_string).collect::<Vec<_>>().join(" ")); }
        for k in 0..3 {
            lines.push(format!("class {} precision {} recall {}", k+1,
                ratio(confusion[k][k], (0..3).map(|i| confusion[i][k]).sum()), ratio(confusion[k][k], confusion[k].iter().sum())));
        }
    }
    lines
}

fn framed(cells: &[u8], width: usize) -> Vec<String> {
    let frame = format!("+{}+", "-".repeat(width));
    let mut lines = vec![frame.clone()];
    for row in cells.chunks(width) { lines.push(format!("|{}|", String::from_utf8(row.to_vec()).unwrap())); }
    lines.push(frame);
    lines
}

fn plots(models: &[Model], selected: usize, params: &Settings, train: &[Example], multi_train: &[Example], multi: &multiclass::Models, multi_kernel: &Kernel, a: f64, b: f64) -> Vec<String> {
    let kernel = &params.kernels[selected];
    let model = &models[selected];
    let (width, height) = (params.width, params.height);
    let dx = (params.x[1]-params.x[0])/width as f64;
    let dy = (params.y[1]-params.y[0])/height as f64;
    let centers: Vec<_> = (0..height).flat_map(|r| (0..width).map(move |c|
        [params.x[0]+(c as f64+0.5)*dx, params.y[1]-(r as f64+0.5)*dy])).collect();
    let point_cell = |point: [f64; 2]| {
        let c = ((point[0]-params.x[0])/dx).floor() as i64;
        let r = ((params.y[1]-point[1])/dy).floor() as i64;
        if c >= 0 && c < width as i64 && r >= 0 && r < height as i64 { Some(r as usize*width+c as usize) } else { None }
    };
    let grid_values: Vec<Vec<_>> = models.iter().zip(&params.kernels).map(|(m, k)| centers.iter().map(|&p| m.decision(k, p)).collect()).collect();
    let mut binary: Vec<_> = grid_values[selected].iter().map(|&v| if v >= 1.0 { b'+' } else if v > 0.0 { b'.' } else if v > -1.0 { b'-' } else { b' ' }).collect();
    let mut assigned: Vec<Option<usize>> = vec![None; width*height];
    let mut outside = 0;
    for (i, e) in train.iter().enumerate() {
        if let Some(cell) = point_cell(e.point) {
            if assigned[cell].map_or(true, |j| model.alpha[i] > 0.0 && model.alpha[j] == 0.0) { assigned[cell] = Some(i); }
        } else { outside += 1; }
    }
    for (cell, &example) in assigned.iter().enumerate() {
        if let Some(i) = example { binary[cell] = match (train[i].label, model.alpha[i] > 0.0) {
            (1, true) => b'X', (1, false) => b'x', (-1, true) => b'O', _ => b'o',
        }; }
    }
    let mut lines = vec![format!("binary {} C {}", kernel.name, real(model.c, 4)),
        format!("x {} {} y {} {} grid {}x{}", real(params.x[0], 4), real(params.x[1], 4), real(params.y[0], 4), real(params.y[1], 4), width, height)];
    lines.extend(framed(&binary, width));
    let count = |cells: &[u8], symbol| cells.iter().filter(|&&c| c == symbol).count();
    lines.push(format!("cells outer_positive {} inner_positive {} inner_negative {} outer_negative {} points {} outside {}",
        count(&binary, b'+'), count(&binary, b'.'), count(&binary, b'-'), count(&binary, b' '), assigned.iter().flatten().count(), outside));
    lines.push(String::new());
    lines.push(format!("probability {} A {} B {}", kernel.name, real(a, 6), real(b, 6)));
    let probability_cells: Vec<_> = grid_values[selected].iter().map(|&v| b'0'+((probability(v, a, b)*10.0).floor() as u8).min(9)).collect();
    lines.extend(framed(&probability_cells, width));
    lines.push(format!("levels {}", (b'0'..=b'9').map(|d| count(&probability_cells, d).to_string()).collect::<Vec<_>>().join(" ")));
    lines.push(String::new());
    lines.push("grid_agreement".to_owned());
    for i in 0..models.len() { for j in i+1..models.len() {
        let agree = grid_values[i].iter().zip(&grid_values[j]).filter(|(x, y)| sign(**x) == sign(**y)).count();
        lines.push(format!("{} {} {}/{} positive {} {}", params.kernels[i].name, params.kernels[j].name, agree, width*height,
            grid_values[i].iter().filter(|&&v| v > 0.0).count(), grid_values[j].iter().filter(|&&v| v > 0.0).count()));
    } }
    lines.push(String::new());
    lines.push(format!("multiclass {} C {}", multi_kernel.name, real(params.multi_c, 4)));
    let mut cells: Vec<_> = centers.iter().map(|&point| {
        let p = multi.classify(multi_kernel, point);
        if p.rest != p.one { b'?' } else { [b' ', b'.', b':'][p.rest-1] }
    }).collect();
    let mut assigned = vec![None; width*height];
    let mut outside = 0;
    for (i, e) in multi_train.iter().enumerate() {
        if let Some(cell) = point_cell(e.point) { if assigned[cell].is_none() { assigned[cell] = Some(i); } }
        else { outside += 1; }
    }
    for (cell, &example) in assigned.iter().enumerate() { if let Some(i) = example { cells[cell] = b'0'+multi_train[i].label as u8; } }
    lines.extend(framed(&cells, width));
    lines.push(format!("cells class1 {} class2 {} class3 {} disagree {} points {} outside {}", count(&cells, b' '), count(&cells, b'.'),
        count(&cells, b':'), count(&cells, b'?'), assigned.iter().flatten().count(), outside));
    lines
}

fn main() {
    let train = dataset::binary("input/train.csv");
    let test = dataset::binary("input/test.csv");
    let (multi_train, multi_test) = dataset::multiclass();
    let params = dataset::settings();
    let points: Vec<_> = train.iter().map(|e| e.point).collect();
    let labels: Vec<_> = train.iter().map(|e| e.label as f64).collect();
    let matrices: Vec<_> = params.kernels.iter().map(|k| k.matrix(&points)).collect();
    let grid: Vec<Vec<_>> = params.kernels.iter().enumerate().map(|(i, k)| params.candidates.iter()
        .map(|&c| cross_validation(&train, k, &matrices[i], c, &params)).collect()).collect();
    let best: Vec<_> = grid.iter().map(|rows| (0..rows.len()).min_by_key(|&c| (std::cmp::Reverse(rows[c].correct), c)).unwrap()).collect();
    let selected = (0..params.kernels.len()).min_by(|&a, &b| grid[b][best[b]].correct.cmp(&grid[a][best[a]].correct)
        .then(params.candidates[best[a]].total_cmp(&params.candidates[best[b]])).then(a.cmp(&b))).unwrap();
    let selected_c = params.candidates[best[selected]];
    let models: Vec<_> = params.kernels.iter().enumerate().map(|(i, _)| smo::train(&points, &labels, &matrices[i], params.candidates[best[i]], &params)).collect();
    let test_values: Vec<_> = models.iter().zip(&params.kernels).map(|(m, k)| values(m, k, &test)).collect();
    let mut lines = vec![format!("cross_validation folds {} examples {}", params.folds, train.len())];
    let mut cv_csv = vec![format!("kernel,C,{},correct,accuracy,support_vectors,passes,steps",
        (1..=params.folds).map(|f| format!("fold{}", f)).collect::<Vec<_>>().join(","))];
    for (i, kernel) in params.kernels.iter().enumerate() {
        let c = best[i];
        lines.push(format!("best {} C {} correct {}/{} accuracy {}", kernel.name, real(params.candidates[c], 4), grid[i][c].correct, train.len(), ratio(grid[i][c].correct, train.len())));
        for (j, &c) in params.candidates.iter().enumerate() {
            let cv = &grid[i][j];
            cv_csv.push(format!("{},{},{},{},{},{},{},{}", kernel.name, real(c, 4),
                cv.folds.iter().map(|f| f.correct.to_string()).collect::<Vec<_>>().join(","), cv.correct,
                ratio(cv.correct, train.len()), cv.folds.iter().map(|f| f.support).sum::<usize>(),
                cv.folds.iter().map(|f| f.passes).sum::<usize>(), cv.folds.iter().map(|f| f.steps).sum::<usize>()));
        }
    }
    lines.push(format!("selected {} C {}", params.kernels[selected].name, real(selected_c, 4)));
    lines.push("ranking".to_owned());
    let mut ranking: Vec<_> = (0..params.kernels.len()).flat_map(|i| (0..params.candidates.len()).map(move |j| (i, j))).collect();
    ranking.sort_by(|&(i, c), &(j, d)| grid[j][d].correct.cmp(&grid[i][c].correct)
        .then(params.candidates[c].total_cmp(&params.candidates[d])).then(i.cmp(&j)));
    for (rank, &(i, c)) in ranking.iter().enumerate() {
        lines.push(format!("{} {} C {} correct {}/{}", rank+1, params.kernels[i].name, real(params.candidates[c], 4), grid[i][c].correct, train.len()));
    }
    lines.push(format!("cv_detail {} C {}", params.kernels[selected].name, real(selected_c, 4)));
    for (i, fold) in grid[selected][best[selected]].folds.iter().enumerate() {
        lines.push(format!("fold {} train {} test {} correct {} support_vectors {} passes {} steps {} converged {}", i+1,
            fold.training, fold.test, fold.correct, fold.support, fold.passes, fold.steps, yes(fold.converged)));
    }
    for (i, model) in models.iter().enumerate() {
        lines.push(String::new());
        lines.extend(model_report(model, &params.kernels[i], &matrices[i], &train, &test, &params));
    }
    lines.push(String::new());
    lines.push(format!("training_log {}", params.kernels[selected].name));
    let mut i = 0;
    let passes = &models[selected].passes;
    while i < passes.len() {
        if passes[i].full {
            let dual = smo::objective(passes[i].alpha.as_ref().unwrap(), &labels, &matrices[selected]).1;
            lines.push(format!("pass {} full examined {} changed {} dual_objective {}", i+1, passes[i].examined, passes[i].changed, real(dual, 6)));
            i += 1;
        } else {
            let first = i;
            let (mut examined, mut changed) = (0, 0);
            while i < passes.len() && !passes[i].full { examined += passes[i].examined; changed += passes[i].changed; i += 1; }
            lines.push(format!("passes {}-{} nonbound examined {} changed {}", first+1, i, examined, changed));
        }
    }
    lines.push(String::new());
    lines.push(format!("c_path {}", params.kernels[selected].name));
    for &c in &params.candidates {
        let model = smo::train(&points, &labels, &matrices[selected], c, &params);
        lines.push(format!("C {} {} dual_objective {} train {}/{} test {}/{} {}", real(c, 4), sv_info(&model),
            real(smo::objective(&model.alpha, &labels, &matrices[selected]).1, 6),
            evaluation::correct(&train, &values(&model, &params.kernels[selected], &train)), train.len(),
            evaluation::correct(&test, &values(&model, &params.kernels[selected], &test)), test.len(), run_info(&model)));
    }
    lines.push(String::new());
    lines.push(format!("learning_curve {} C {}", params.kernels[selected].name, real(selected_c, 4)));
    for &fraction in &params.fractions {
        let size = train.len()*fraction/100;
        let matrix: Vec<_> = matrices[selected][..size].iter().map(|row| row[..size].to_vec()).collect();
        let model = smo::train(&points[..size], &labels[..size], &matrix, selected_c, &params);
        lines.push(format!("size {} support_vectors {} train {}/{} test {}/{} {}", size, model.support().0,
            evaluation::correct(&train[..size], &values(&model, &params.kernels[selected], &train[..size])), size,
            evaluation::correct(&test, &values(&model, &params.kernels[selected], &test)), test.len(), run_info(&model)));
    }
    let (a, b, probabilities, calibration) = calibration(&grid[selected][best[selected]].values, &train,
        &test_values[selected], &test, &params.kernels[selected], selected_c, params.newton);
    lines.push(String::new());
    lines.extend(calibration);
    let linear = params.kernels.iter().position(|k| matches!(k.kind, Kind::Linear)).unwrap();
    let (_, pegasos_values, pegasos) = pegasos(&train, &test, &params, &params.kernels[linear], &models[linear]);
    lines.push(String::new());
    lines.extend(pegasos);
    lines.push(String::new());
    lines.push("mcnemar".to_owned());
    let mut names: Vec<_> = params.kernels.iter().map(|k| k.name.clone()).collect();
    names.push("pegasos".to_owned());
    let mut comparisons = test_values.clone();
    comparisons.push(pegasos_values.clone());
    for i in 0..comparisons.len() { for j in i+1..comparisons.len() {
        let (mut first, mut second) = (0i64, 0i64);
        for (e, (&a, &b)) in test.iter().zip(comparisons[i].iter().zip(&comparisons[j])) {
            let (x, y) = (sign(a) == e.label, sign(b) == e.label);
            if x && !y { first += 1; }
            if y && !x { second += 1; }
        }
        let difference = (first-second).abs()-1;
        let chi = if first+second == 0 { "-".to_owned() } else { real((difference*difference) as f64/(first+second) as f64, 4) };
        lines.push(format!("{} {} only_first {} only_second {} chi2 {}", names[i], names[j], first, second, chi));
    } }
    let mut predictions = vec![format!("id,label,{},pegasos,predicted,probability", params.kernels.iter().map(|k| k.name.as_str()).collect::<Vec<_>>().join(","))];
    for (i, e) in test.iter().enumerate() {
        predictions.push(format!("{},{},{},{},{},{}", e.id, e.label,
            test_values.iter().map(|v| real(v[i], 4)).collect::<Vec<_>>().join(","), real(pegasos_values[i], 4), sign(test_values[selected][i]), real(probabilities[i], 4)));
    }
    let multi_kernel = params.kernels.iter().find(|k| k.name == params.multi_kernel).unwrap();
    let multi = multiclass::train(&multi_train, multi_kernel, &params);
    let multiclass_lines = multi_report(&multi, &multi_train, &multi_test, multi_kernel, &params);
    let plot = plots(&models, selected, &params, &train, &multi_train, &multi, multi_kernel, a, b);
    for (file, output) in [("model.txt", lines), ("cv_grid.csv", cv_csv), ("predictions.csv", predictions),
        ("multiclass.txt", multiclass_lines), ("decision_plot.txt", plot)] { evaluation::write(file, &output); }
}
