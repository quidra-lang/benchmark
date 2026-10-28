mod dataset;
mod layers;
mod network;
mod optimizers;
mod evaluation;

use std::fs;
use dataset::{Generator, Image, Run, Settings};
use network::{Network, Forward};
use evaluation::{real, ratio, prediction};

struct Evaluation { loss: f64, correct: usize, results: Vec<Forward>, predictions: Vec<usize> }

fn evaluate(net: &Network, theta: &[f64], data: &[Image]) -> Evaluation {
    let results: Vec<_> = data.iter().map(|image| net.forward(theta, &image.input, image.label)).collect();
    let predictions: Vec<_> = results.iter().map(|f| prediction(&f.scores)).collect();
    let correct = data.iter().zip(&predictions).filter(|(i, p)| i.label == **p).count();
    Evaluation { loss: results.iter().map(|f| f.loss).sum::<f64>()/data.len() as f64, correct, results, predictions }
}

fn mean_gradient(net: &Network, theta: &[f64], data: &[Image], order: &[usize]) -> Vec<f64> {
    let mut result = vec![0.0; theta.len()];
    for &i in order {
        let forward = net.forward(theta, &data[i].input, data[i].label);
        let gradient = net.gradients(theta, &forward).0;
        for p in 0..result.len() { result[p] += gradient[p]; }
    }
    for value in &mut result { *value /= order.len() as f64; }
    result
}

fn check_gradient(net: &Network, data: &[Image], params: &Settings) -> Vec<String> {
    let mut order: Vec<_> = (0..data.len()).collect();
    Generator { state: params.seed }.shuffle(&mut order);
    order.truncate(params.batch.min(data.len()));
    let gradient = mean_gradient(net, &net.initial, data, &order);
    let mut theta = net.initial.clone();
    let mut counts = vec![(0, 0); net.layers.len()];
    let mut passed = true;
    let mut checked = 0;
    let loss = |theta: &[f64]| order.iter().map(|&i| net.forward(theta, &data[i].input, data[i].label).loss).sum::<f64>()/order.len() as f64;
    for p in (0..theta.len()).step_by(params.stride) {
        let original = theta[p];
        theta[p] = original+0.00001;
        let plus = loss(&theta);
        theta[p] = original-0.00001;
        let minus = loss(&theta);
        theta[p] = original;
        let numeric = (plus-minus)/(2.0*0.00001);
        let error = (gradient[p]-numeric).abs()/1.0_f64.max(gradient[p].abs()+numeric.abs());
        passed &= error < 0.000001;
        checked += 1;
        for (l, layer) in net.layers.iter().enumerate() {
            if p >= layer.weights && p < layer.biases { counts[l].0 += 1; }
            else if p >= layer.biases && p < layer.biases+layer.units { counts[l].1 += 1; }
        }
    }
    let mut lines = vec![format!("network {}", net.name), format!("parameters {}", theta.len()),
        format!("batch {}", order.iter().map(|&i| data[i].id.as_str()).collect::<Vec<_>>().join(" "))];
    for (l, &(weights, biases)) in counts.iter().enumerate() { lines.push(format!("layer {} weights {} biases {}", l+1, weights, biases)); }
    lines.push(format!("checked {}", checked));
    lines.push(format!("result {}", if passed { "PASS" } else { "FAIL" }));
    lines
}

struct Epoch {
    eta: f64,
    magnitude: f64,
    train_loss: f64,
    train_correct: usize,
    val_loss: f64,
    val_correct: usize,
    improved: bool,
    status: Vec<bool>,
}

struct Trained {
    theta: Vec<f64>,
    best: usize,
    best_loss: f64,
    best_correct: usize,
    epochs: Vec<Epoch>,
    updates: usize,
    stop: &'static str,
}

fn train(net: &Network, run: &Run, data: &[Image], validation: &[Image], params: &Settings) -> Trained {
    let mut theta = net.initial.clone();
    let mut optimizer = optimizers::State::new(theta.len());
    let mut generator = Generator { state: params.seed };
    let mut order: Vec<_> = (0..data.len()).collect();
    let mut result = Trained { theta: theta.clone(), best: 0, best_loss: f64::INFINITY, best_correct: 0,
        epochs: Vec::new(), updates: 0, stop: "max_epochs" };
    let mut wait = 0;
    for epoch in 1..=params.epochs {
        let eta = optimizers::learning_rate(run, epoch, params.step, params.gamma);
        generator.shuffle(&mut order);
        let mut magnitude = 0.0;
        let mut batches = 0;
        for batch in order.chunks(params.batch) {
            let mut gradient = mean_gradient(net, &theta, data, batch);
            for &p in &net.weight_indices { gradient[p] += run.decay*theta[p]; }
            magnitude += gradient.iter().map(|g| g*g).sum::<f64>().sqrt();
            batches += 1;
            optimizer.update(&mut theta, &gradient, run, eta);
            result.updates += 1;
        }
        let training = evaluate(net, &theta, data);
        let valid = evaluate(net, &theta, validation);
        let improved = epoch == 1 || valid.loss < result.best_loss;
        if improved {
            result.best = epoch;
            result.best_loss = valid.loss;
            result.best_correct = valid.correct;
            result.theta = theta.clone();
            wait = 0;
        } else { wait += 1; }
        let status = data.iter().zip(&training.predictions).map(|(image, &p)| image.label == p).collect();
        result.epochs.push(Epoch { eta, magnitude: magnitude/batches as f64,
            train_loss: training.loss, train_correct: training.correct, val_loss: valid.loss,
            val_correct: valid.correct, improved, status });
        if wait >= params.patience { result.stop = "early"; break; }
    }
    result
}

fn noisy(test: &[Image], rate: usize, seed: i64) -> (Vec<Image>, usize) {
    let mut generator = Generator { state: seed };
    let mut result = test.to_vec();
    let mut flipped = 0;
    for image in &mut result {
        for p in 0..image.pixels.len() {
            if generator.next() as usize%100 < rate {
                image.pixels[p] = if image.pixels[p] == b'1' { b'0' } else { b'1' };
                image.input[p] = 1.0-image.input[p];
                flipped += 1;
            }
        }
    }
    (result, flipped)
}

fn run_report(net: &Network, run: &Run, trained: &Trained, test: &[Image], validation: &[Image], result: &Evaluation,
              params: &Settings, noises: &[(Vec<Image>, usize)]) -> Vec<String> {
    let classes = net.classes();
    let mut lines = vec![format!("run {} network {} optimizer {}", run.name, net.name, run.optimizer),
        format!("epochs {} best_epoch {} stop {} updates {}", trained.epochs.len(), trained.best, trained.stop, trained.updates),
        format!("best_val_loss {} best_val_acc {} correct {}/{}", real(trained.best_loss, 6), ratio(trained.best_correct, validation.len()), trained.best_correct, validation.len()),
        format!("test_loss {} test_acc {} correct {}/{}", real(result.loss, 6), ratio(result.correct, test.len()), result.correct, test.len())];
    let top2 = test.iter().zip(&result.results).filter(|(image, f)| {
        let p = prediction(&f.scores);
        image.label == p || image.label == evaluation::second(&f.scores, p)
    }).count();
    lines.push(format!("top2_acc {} correct {}/{}", ratio(top2, test.len()), top2, test.len()));
    let mean_confidence = |correct: bool| {
        let mut sum = 0.0;
        let mut count = 0;
        for (i, image) in test.iter().enumerate() {
            if (result.predictions[i] == image.label) == correct {
                sum += result.results[i].scores[result.predictions[i]];
                count += 1;
            }
        }
        if count == 0 { "-".to_owned() } else { real(sum/count as f64, 4) }
    };
    lines.push(format!("confidence correct {} wrong {}", mean_confidence(true), mean_confidence(false)));
    let mut forgetting = Vec::new();
    let mut never = 0;
    for i in 0..trained.epochs[0].status.len() {
        forgetting.push(trained.epochs.windows(2).filter(|pair| pair[0].status[i] && !pair[1].status[i]).count());
        never += usize::from(trained.epochs.iter().all(|e| !e.status[i]));
    }
    lines.push(format!("forgetting events {} rows {} never_learned {}", forgetting.iter().sum::<usize>(), forgetting.iter().filter(|&&n| n > 0).count(), never));
    let mut norms = Vec::new();
    let mut changes = Vec::new();
    for layer in &net.layers {
        norms.push(real(trained.theta[layer.weights..layer.biases].iter().map(|w| w*w).sum::<f64>().sqrt(), 4));
        changes.push(real((layer.weights..layer.biases).map(|p| { let d = trained.theta[p]-net.initial[p]; d*d }).sum::<f64>().sqrt(), 4));
    }
    lines.push(format!("weight_norms {}", norms.join(" ")));
    lines.push(format!("weight_changes {}", changes.join(" ")));
    lines.push("curve".to_owned());
    let maximum = trained.epochs.iter().map(|e| e.train_loss.max(e.val_loss)).fold(0.0, f64::max);
    for (i, e) in trained.epochs.iter().enumerate() {
        let mut row = vec![b' '; 40];
        let ct = (39.0*e.train_loss/maximum+0.5).floor() as usize;
        let cv = (39.0*e.val_loss/maximum+0.5).floor() as usize;
        row[ct] = b't';
        row[cv] = if ct == cv { b'*' } else { b'v' };
        lines.push(format!("{:2} |{}|{}", i+1, String::from_utf8(row).unwrap(), if i+1 == trained.best { " best" } else { "" }));
    }
    let actual: Vec<_> = test.iter().map(|e| e.label).collect();
    let confusion = evaluation::confusion(&actual, &result.predictions, classes);
    lines.push("confusion".to_owned());
    for (k, row) in confusion.iter().enumerate() { lines.push(format!("{}: {}", k, row.iter().map(usize::to_string).collect::<Vec<_>>().join(" "))); }
    for k in 0..classes {
        let (support, predicted, precision, recall, f1) = evaluation::class_values(&confusion, k);
        lines.push(format!("class {} support {} predicted {} precision {} recall {} f1 {}", k, support, predicted, precision, recall, f1));
    }
    lines.push("calibration".to_owned());
    let mut bins = vec![(0usize, 0usize, 0.0); params.bins];
    for (i, image) in test.iter().enumerate() {
        let confidence = result.results[i].scores[result.predictions[i]];
        let bin = ((confidence*params.bins as f64).floor() as usize).min(params.bins-1);
        bins[bin].0 += 1;
        bins[bin].1 += usize::from(result.predictions[i] == image.label);
        bins[bin].2 += confidence;
    }
    let mut ece = 0.0;
    for (bin, &(count, correct, sum)) in bins.iter().enumerate() {
        let confidence = if count == 0 { "-".to_owned() } else { real(sum/count as f64, 4) };
        if count > 0 { ece += count as f64/test.len() as f64*(correct as f64/count as f64-sum/count as f64).abs(); }
        lines.push(format!("bin {} {} {} count {} accuracy {} confidence {}", bin+1, real(bin as f64/params.bins as f64, 2),
            real((bin+1) as f64/params.bins as f64, 2), count, ratio(correct, count), confidence));
    }
    lines.push(format!("ece {}", real(ece, 4)));
    for (l, layer) in net.layers[..net.layers.len()-1].iter().enumerate() {
        lines.push(format!("hidden {} {} units {}", l+1, layer.kind, layer.units));
        let mut means = vec![vec![0.0; layer.units]; classes];
        let mut counts = vec![0; classes];
        let mut zeros = vec![0; layer.units];
        for (i, image) in test.iter().enumerate() {
            counts[image.label] += 1;
            for j in 0..layer.units {
                let value = result.results[i].activations[l+1][j];
                means[image.label][j] += value;
                zeros[j] += usize::from(value == 0.0);
            }
        }
        for k in 0..classes {
            if counts[k] > 0 { for value in &mut means[k] { *value /= counts[k] as f64; } }
            lines.push(format!("class {} mean {}", k, if counts[k] == 0 { "-".to_owned() }
                else { means[k].iter().map(|&v| real(v, 4)).collect::<Vec<_>>().join(" ") }));
        }
        let preferred: Vec<_> = (0..layer.units).map(|j| {
            let mut best = (0..classes).find(|&k| counts[k] > 0).unwrap();
            for k in best+1..classes { if counts[k] > 0 && means[k][j] > means[best][j] { best = k; } }
            best.to_string()
        }).collect();
        lines.push(format!("preferred {}", preferred.join(" ")));
        if layer.kind == "RELU" { lines.push(format!("zero_counts {}", zeros.iter().map(usize::to_string).collect::<Vec<_>>().join(" "))); }
    }
    lines.push("pruning".to_owned());
    let mut order = net.weight_indices.clone();
    order.sort_by(|&a, &b| trained.theta[a].abs().total_cmp(&trained.theta[b].abs()).then(a.cmp(&b)));
    for &q in &params.prune {
        let removed = q*order.len()/100;
        let mut theta = trained.theta.clone();
        for &p in &order[..removed] { theta[p] = 0.0; }
        let e = evaluate(net, &theta, test);
        lines.push(format!("prune {} removed {} correct {} test_acc {} test_loss {}", q, removed, e.correct, ratio(e.correct, test.len()), real(e.loss, 6)));
    }
    lines.push("noise".to_owned());
    for (i, &rate) in params.noise.iter().enumerate() {
        let e = evaluate(net, &trained.theta, &noises[i].0);
        lines.push(format!("noise {} correct {} test_acc {}", rate, e.correct, ratio(e.correct, test.len())));
    }
    let ids: Vec<_> = test.iter().enumerate().filter(|(i, e)| result.predictions[*i] != e.label).map(|(_, e)| e.id.as_str()).collect();
    lines.push(format!("misclassified {}{}", ids.len(), if ids.is_empty() { String::new() } else { format!(" {}", ids.join(" ")) }));
    lines
}

fn main() {
    let all_train = dataset::images("input/train.csv");
    let test = dataset::images("input/test.csv");
    let (width, height, networks) = dataset::networks();
    let params = dataset::settings();
    let training_count = all_train.len()-all_train.len()/5;
    let (training, validation) = all_train.split_at(training_count);
    let classes = networks[0].classes();
    let mut gradient_check = Vec::new();
    for net in &networks {
        if !gradient_check.is_empty() { gradient_check.push(String::new()); }
        gradient_check.extend(check_gradient(net, training, &params));
    }
    let indices: Vec<_> = params.runs.iter().map(|run| networks.iter().position(|n| n.name == run.network).unwrap()).collect();
    let trained: Vec<_> = params.runs.iter().enumerate().map(|(i, run)| train(&networks[indices[i]], run, training, validation, &params)).collect();
    let results: Vec<_> = trained.iter().enumerate().map(|(i, t)| evaluate(&networks[indices[i]], &t.theta, &test)).collect();
    let noises: Vec<_> = params.noise.iter().map(|&rate| noisy(&test, rate, params.seed)).collect();
    let mut log = vec!["run,epoch,lr,grad_norm,train_loss,train_acc,val_loss,val_acc,improved".to_owned()];
    let mut final_weights = Vec::new();
    let mut predictions = vec!["run,id,label,predicted,confidence".to_owned()];
    for (i, run) in params.runs.iter().enumerate() {
        let net = &networks[indices[i]];
        let t = &trained[i];
        for (epoch, e) in t.epochs.iter().enumerate() {
            log.push(format!("{},{},{},{},{},{},{},{},{}", run.name, epoch+1, real(e.eta, 6), real(e.magnitude, 4),
                real(e.train_loss, 6), ratio(e.train_correct, training.len()), real(e.val_loss, 6), ratio(e.val_correct, validation.len()), usize::from(e.improved)));
        }
        if i > 0 { final_weights.push(String::new()); }
        final_weights.push(format!("RUN {} NETWORK {} EPOCH {}", run.name, net.name, t.best));
        for (l, layer) in net.layers.iter().enumerate() {
            final_weights.push(format!("LAYER {} {} {}", l+1, layer.units, layer.inputs));
            for j in 0..layer.units {
                final_weights.push(format!("W {}", t.theta[layer.weights+j*layer.inputs..layer.weights+(j+1)*layer.inputs].iter().map(|&v| real(v, 4)).collect::<Vec<_>>().join(" ")));
            }
            final_weights.push(format!("B {}", t.theta[layer.biases..layer.biases+layer.units].iter().map(|&v| real(v, 4)).collect::<Vec<_>>().join(" ")));
        }
        for (j, image) in test.iter().enumerate() {
            let p = results[i].predictions[j];
            predictions.push(format!("{},{},{},{},{}", run.name, image.id, image.label, p, real(results[i].results[j].scores[p], 4)));
        }
    }
    let mut lines = vec!["data".to_owned(), format!("train {} validation {} test {} pixels {}", training.len(), validation.len(), test.len(), width*height)];
    let mut mean_maps = Vec::new();
    for k in 0..classes {
        let images: Vec<_> = training.iter().filter(|e| e.label == k).collect();
        let ink = images.iter().map(|e| e.pixels.iter().filter(|&&b| b == b'1').count()).sum();
        lines.push(format!("class {} train {} validation {} test {} ink {}", k, images.len(), validation.iter().filter(|e| e.label == k).count(),
            test.iter().filter(|e| e.label == k).count(), ratio(ink, images.len())));
        mean_maps.push((0..width*height).map(|p| if images.is_empty() { 0 } else {
            (10*images.iter().filter(|e| e.pixels[p] == b'1').count()/images.len()).min(9)
        }).collect());
    }
    let labels = (0..classes).map(|k| k.to_string()).collect::<Vec<_>>().join(" ");
    lines.push(format!("mean_images {}", labels));
    lines.extend(evaluation::maps(&mean_maps, width, height));
    lines.push(String::new());
    for (i, run) in params.runs.iter().enumerate() {
        lines.extend(run_report(&networks[indices[i]], run, &trained[i], &test, validation, &results[i], &params, &noises));
        lines.push(String::new());
    }
    let mut ranking: Vec<_> = (0..params.runs.len()).collect();
    ranking.sort_by(|&a, &b| results[b].correct.cmp(&results[a].correct).then(trained[a].best_loss.total_cmp(&trained[b].best_loss)).then(a.cmp(&b)));
    let top = ranking[0];
    lines.push("comparison".to_owned());
    for (rank, &i) in ranking.iter().enumerate() {
        lines.push(format!("rank {} {} correct {} test_acc {} best_val_loss {} test_loss {} best_epoch {} epochs {} updates {}", rank+1,
            params.runs[i].name, results[i].correct, ratio(results[i].correct, test.len()), real(trained[i].best_loss, 6), real(results[i].loss, 6),
            trained[i].best, trained[i].epochs.len(), trained[i].updates));
    }
    lines.push("agreement".to_owned());
    for (i, run) in params.runs.iter().enumerate() {
        let counts: Vec<_> = results.iter().map(|r| r.predictions.iter().zip(&results[i].predictions).filter(|(a, b)| a == b).count().to_string()).collect();
        lines.push(format!("{} {}", run.name, counts.join(" ")));
    }
    lines.push(format!("mcnemar {}", params.runs[top].name));
    for &i in &ranking[1..] {
        let (mut b, mut c) = (0usize, 0usize);
        for (j, image) in test.iter().enumerate() {
            let (x, y) = (results[top].predictions[j] == image.label, results[i].predictions[j] == image.label);
            b += usize::from(x && !y);
            c += usize::from(y && !x);
        }
        let d = b.abs_diff(c).saturating_sub(1);
        let numerator = d*d;
        let chi = if b+c == 0 { "0.0000".to_owned() } else { ratio(numerator, b+c) };
        lines.push(format!("vs {} b {} c {} chi2 {} significant {}", params.runs[i].name, b, c, chi,
            if numerator*1000 > 3841*(b+c) { "yes" } else { "no" }));
    }
    let mut ensemble = Vec::new();
    let (mut ensemble_correct, mut fixed, mut broken) = (0, 0, 0);
    for (j, image) in test.iter().enumerate() {
        let mut votes = vec![0; classes];
        for r in &results { votes[r.predictions[j]] += 1; }
        let maximum = *votes.iter().max().unwrap();
        let p = ranking.iter().map(|&i| results[i].predictions[j]).find(|&p| votes[p] == maximum).unwrap();
        ensemble.push(p);
        let (right, top_right) = (p == image.label, results[top].predictions[j] == image.label);
        ensemble_correct += usize::from(right);
        fixed += usize::from(right && !top_right);
        broken += usize::from(top_right && !right);
    }
    lines.push(format!("ensemble correct {}/{} test_acc {} fixed {} broken {}", ensemble_correct, test.len(), ratio(ensemble_correct, test.len()), fixed, broken));
    let soft: Vec<_> = indices.iter().enumerate().filter(|(_, n)| networks[**n].softmax()).map(|(i, _)| i).collect();
    if soft.is_empty() { lines.push("soft_ensemble none".to_owned()); }
    else {
        let correct = test.iter().enumerate().filter(|(j, image)| {
            let mut scores = vec![0.0; classes];
            for &i in &soft { for k in 0..classes { scores[k] += results[i].results[*j].scores[k]; } }
            for v in &mut scores { *v /= soft.len() as f64; }
            prediction(&scores) == image.label
        }).count();
        lines.push(format!("soft_ensemble runs {} correct {}/{} test_acc {}", soft.len(), correct, test.len(), ratio(correct, test.len())));
    }
    for (i, &rate) in params.noise.iter().enumerate() { lines.push(format!("noise {} flipped {}", rate, noises[i].1)); }
    let mut pairs = Vec::new();
    for y in 0..classes { for p in 0..classes {
        if y == p { continue; }
        let count = results.iter().map(|r| test.iter().enumerate().filter(|(j, image)| image.label == y && r.predictions[*j] == p).count()).sum::<usize>();
        if count > 0 { pairs.push((count, y, p)); }
    } }
    pairs.sort_by_key(|&(count, y, p)| (std::cmp::Reverse(count), y, p));
    lines.push("confused_pairs".to_owned());
    for &(count, y, p) in pairs.iter().take(5) { lines.push(format!("{} as {} count {}", y, p, count)); }
    lines.push(String::new());
    lines.push(format!("saliency {}", params.runs[top].name));
    lines.push(format!("classes {}", labels));
    let net = &networks[indices[top]];
    let mut saliency = vec![vec![0.0; width*height]; classes];
    let mut counts = vec![0; classes];
    for (j, image) in test.iter().enumerate() {
        let gradient = net.gradients(&trained[top].theta, &results[top].results[j]).1;
        counts[image.label] += 1;
        for p in 0..width*height { saliency[image.label][p] += gradient[p].abs(); }
    }
    let saliency_maps: Vec<Vec<_>> = saliency.iter_mut().enumerate().map(|(k, values)| {
        if counts[k] > 0 { for v in values.iter_mut() { *v /= counts[k] as f64; } }
        let maximum = values.iter().copied().fold(0.0, f64::max);
        values.iter().map(|&v| if maximum == 0.0 { 0 } else { ((10.0*v/maximum).floor() as usize).min(9) }).collect()
    }).collect();
    lines.extend(evaluation::maps(&saliency_maps, width, height));
    lines.push(String::new());
    lines.push(format!("hardest_training_examples {}", params.runs[top].name));
    let training_evaluation = evaluate(net, &trained[top].theta, training);
    let mut hardest: Vec<_> = (0..training.len()).collect();
    hardest.sort_by(|&a, &b| training_evaluation.results[b].loss.total_cmp(&training_evaluation.results[a].loss).then(a.cmp(&b)));
    for &i in hardest.iter().take(5) {
        lines.push(format!("{} label {} predicted {} loss {}", training[i].id, training[i].label, training_evaluation.predictions[i], real(training_evaluation.results[i].loss, 6)));
    }
    lines.push(String::new());
    lines.push(format!("misclassified_examples {}", params.runs[top].name));
    for (j, image) in test.iter().enumerate() {
        let predicted = results[top].predictions[j];
        if predicted == image.label { continue; }
        lines.push(format!("{} label {} predicted {} confidence {} true_score {} runs {} ensemble {}", image.id, image.label, predicted,
            real(results[top].results[j].scores[predicted], 4), real(results[top].results[j].scores[image.label], 4),
            results.iter().map(|r| r.predictions[j].to_string()).collect::<Vec<_>>().join(" "), ensemble[j]));
        let (nearest, distance) = all_train.iter().enumerate().map(|(i, e)| (i, e.pixels.iter().zip(&image.pixels).filter(|(a, b)| a != b).count()))
            .min_by_key(|&(i, d)| (d, i)).unwrap();
        lines.push(format!("nearest {} label {} distance {}", all_train[nearest].id, all_train[nearest].label, distance));
        lines.extend(evaluation::image(&image.pixels, width));
    }
    fs::create_dir_all("output").unwrap();
    for (file, lines) in [("gradient_check.txt", gradient_check), ("training_log.csv", log), ("final_weights.txt", final_weights),
        ("predictions.csv", predictions), ("evaluation.txt", lines)] { fs::write(format!("output/{}", file), lines.join("\n")+"\n").unwrap(); }
}
