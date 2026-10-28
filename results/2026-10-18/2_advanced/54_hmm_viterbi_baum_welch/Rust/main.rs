mod model_io;
mod inference;
mod training;
mod evaluation;
mod sampler;

use model_io::{Model, Observation, real, fixed};
use evaluation::{Confusion, fraction};
use inference::Decoding;
use std::{collections::BTreeSet, io};

struct Params {
    iterations: usize,
    pseudocount: f64,
    smoothing: Vec<String>,
    folds: usize,
    minimum_sequence: usize,
    missing_percent: usize,
    state: usize,
    gap: usize,
    minimum_segment: usize,
    motif: [usize; 2],
    rich: BTreeSet<usize>,
    rich_percent: i64,
    motif_percent: i64,
    confidence: f64,
    boundary: usize,
    posterior_seed: i64,
    posterior_samples: usize,
    sample_seed: i64,
    sample_count: usize,
    sample_length: usize,
}

impl Params {
    fn read(input: &model_io::Input) -> Self {
        let q = &input.params;
        let integer = |i: usize| q[i][0].parse::<usize>().unwrap();
        let decimal = |i: usize| q[i][0].parse::<f64>().unwrap();
        let symbol = |s: &str| input.symbols.iter().position(|&c| c == s.chars().next().unwrap()).unwrap();
        Self {
            iterations: integer(0), pseudocount: decimal(1), smoothing: q[2].clone(), folds: integer(3), minimum_sequence: integer(4), missing_percent: integer(5),
            state: input.states.iter().position(|&c| c == q[6][0].chars().next().unwrap()).unwrap(), gap: integer(7), minimum_segment: integer(8),
            motif: [symbol(&q[9][0]), symbol(&q[9][1])], rich: q[10].iter().map(|s| symbol(s)).collect(), rich_percent: integer(11) as i64,
            motif_percent: integer(12) as i64, confidence: decimal(13), boundary: integer(14), posterior_seed: q[15][0].parse().unwrap(),
            posterior_samples: integer(16), sample_seed: q[17][0].parse().unwrap(), sample_count: integer(18), sample_length: integer(19),
        }
    }
}

#[derive(Clone)]
struct Record {
    name: String,
    role: String,
    observation: Observation,
    truth: Vec<usize>,
}

fn validate(raw: &[model_io::RawRecord], file: &str, symbols: &[char], states: &[char], missing: char, params: &Params) -> (Vec<Record>, Vec<String>) {
    let mut names = BTreeSet::new();
    let mut records = Vec::new();
    let mut rejected = Vec::new();
    for r in raw {
        let text: Vec<char> = r.text.to_ascii_uppercase().chars().collect();
        let labels: Vec<char> = r.labels.as_ref().map_or(Vec::new(), |s| s.chars().collect());
        let error = if !names.insert(r.name.clone()) { Some("duplicate name".into()) }
            else if let Some(i) = text.iter().position(|&c| c != missing && !symbols.contains(&c)) { Some(format!("invalid symbol {} at position {}", text[i], i + 1)) }
            else if let Some(i) = labels.iter().position(|c| !states.contains(c)) { Some(format!("invalid label {} at position {}", labels[i], i + 1)) }
            else if r.labels.is_some() && text.len() != labels.len() { Some(format!("length mismatch {} {}", text.len(), labels.len())) }
            else if text.len() < params.minimum_sequence { Some(format!("too short {}", text.len())) }
            else {
                let count = text.iter().filter(|&&c| c == missing).count();
                if 100 * count > params.missing_percent * text.len() { Some(format!("too many missing {}", count)) } else { None }
            };
        if let Some(error) = error {
            rejected.push(format!("REJECT {} line {} {} {}", file, r.line, r.name, error));
        } else {
            records.push(Record { name: r.name.clone(), role: r.role.clone(), observation: text.iter().map(|c| symbols.iter().position(|s| s == c)).collect(),
                truth: labels.iter().map(|c| states.iter().position(|s| s == c).unwrap()).collect() });
        }
    }
    (records, rejected)
}

fn segments(path: &[usize], params: &Params) -> Vec<(usize, usize)> {
    let mut merged: Vec<(usize, usize)> = Vec::new();
    for (start, end, state) in evaluation::runs(path) {
        if state != params.state { continue; }
        if let Some(previous) = merged.last_mut() {
            if start - previous.1 - 1 <= params.gap { previous.1 = end; continue; }
        }
        merged.push((start, end));
    }
    merged.into_iter().filter(|&(s, e)| e - s + 1 >= params.minimum_segment).collect()
}

struct Composition {
    rich: Option<f64>,
    motif: Option<f64>,
    island: bool,
}

fn composition(observation: &Observation, (start, end): (usize, usize), params: &Params) -> Composition {
    let (mut n, mut rich, mut q, mut first, mut second) = (0i64, 0i64, 0i64, 0i64, 0i64);
    for i in start..=end {
        if let Some(c) = observation[i] {
            n += 1;
            if params.rich.contains(&c) { rich += 1; }
            if c == params.motif[0] { first += 1; }
            if c == params.motif[1] { second += 1; }
        }
        if i < end && observation[i] == Some(params.motif[0]) && observation[i + 1] == Some(params.motif[1]) { q += 1; }
    }
    let product = first * second;
    Composition { rich: if n == 0 { None } else { Some(rich as f64 / n as f64) }, motif: if product == 0 { None } else { Some((q * n) as f64 / product as f64) },
        island: product > 0 && 100 * rich >= params.rich_percent * n && 100 * q * n >= params.motif_percent * product }
}

fn path_text(path: &[usize], names: &[char]) -> String {
    path.iter().map(|&i| names[i]).collect()
}

fn correct(first: &[usize], second: &[usize]) -> usize {
    first.iter().zip(second).filter(|(a, b)| a == b).count()
}

fn pairs(records: &[Record]) -> Vec<(Observation, Vec<usize>)> {
    records.iter().map(|r| (r.observation.clone(), r.truth.clone())).collect()
}

fn paths<'a>(decode: &'a Decoding, decoder: usize) -> &'a [usize] {
    if decoder == 0 { &decode.viterbi.path } else { &decode.posterior }
}

fn evaluation_block(model: &Model, decoder: usize, records: &[Record], decodings: &[Decoding], states: &[char], params: &Params) -> (Vec<String>, usize) {
    let mut matrix = vec![vec![0; states.len()]; states.len()];
    let (mut predicted_regions, mut true_regions, mut matched_predicted, mut matched_true) = (0, 0, 0, 0);
    let (mut predicted_boundaries, mut true_boundaries, mut matched_pb, mut matched_tb) = (0, 0, 0, 0);
    let mut calibration = [(0usize, 0usize); 10];
    let mut counts = Vec::new();
    for (r, decode) in records.iter().zip(decodings) {
        let path = paths(decode, decoder);
        evaluation::accumulate(&mut matrix, &r.truth, path);
        counts.push(correct(&r.truth, path));
        let predicted = segments(path, params);
        let truth: Vec<(usize, usize)> = evaluation::runs(&r.truth).iter().filter(|r| r.2 == params.state).map(|r| (r.0, r.1)).collect();
        predicted_regions += predicted.len();
        true_regions += truth.len();
        matched_predicted += predicted.iter().filter(|&&p| truth.iter().any(|&t| evaluation::overlap(p, t))).count();
        matched_true += truth.iter().filter(|&&t| predicted.iter().any(|&p| evaluation::overlap(p, t))).count();
        let pb = evaluation::boundaries(path);
        let tb = evaluation::boundaries(&r.truth);
        predicted_boundaries += pb.len();
        true_boundaries += tb.len();
        matched_pb += evaluation::matched(&pb, &tb, params.boundary);
        matched_tb += evaluation::matched(&tb, &pb, params.boundary);
        if decoder == 1 {
            for i in 0..path.len() {
                let bin = ((10.0 * decode.confidence[i]).floor() as usize).min(9);
                calibration[bin].0 += 1;
                if path[i] == r.truth[i] { calibration[bin].1 += 1; }
            }
        }
    }
    let mut lines = vec![format!("EVALUATION {} {}", model.name, if decoder == 0 { "VITERBI" } else { "POSTERIOR" })];
    lines.extend(evaluation::metrics(&matrix, states));
    lines.push(format!("REGIONS {} predicted {} true {} precision {} recall {}", states[params.state], predicted_regions, true_regions,
        fraction(matched_predicted as i64, predicted_regions as i64), fraction(matched_true as i64, true_regions as i64)));
    lines.push(format!("BOUNDARIES predicted {} true {} precision {} recall {}", predicted_boundaries, true_boundaries,
        fraction(matched_pb as i64, predicted_boundaries as i64), fraction(matched_tb as i64, true_boundaries as i64)));
    if decoder == 1 {
        for (bin, &(count, correct)) in calibration.iter().enumerate() {
            if count == 0 { continue; }
            let range = if bin == 9 { "0.9-1.0".into() } else { format!("0.{}-0.{}", bin, bin + 1) };
            lines.push(format!("CALIBRATION {} positions {} correct {} accuracy {}", range, count, correct, fraction(correct as i64, count as i64)));
        }
    }
    for (r, &count) in records.iter().zip(&counts) { lines.push(format!("RECORD {} length {} correct {}", r.name, r.observation.len(), count)); }
    (lines, counts.iter().sum())
}

fn stationary(model: &Model) -> Vec<f64> {
    let k = model.initial.len();
    let mut work = vec![vec![0.0; k + 1]; k];
    for j in 0..k - 1 {
        for i in 0..k { work[j][i] = model.transition[i][j] - if i == j { 1.0 } else { 0.0 }; }
    }
    for i in 0..k { work[k - 1][i] = 1.0; }
    work[k - 1][k] = 1.0;
    for column in 0..k {
        let pivot = (column..k).max_by(|&i, &j| work[i][column].abs().partial_cmp(&work[j][column].abs()).unwrap()).unwrap();
        work.swap(column, pivot);
        let scale = work[column][column];
        for j in 0..=k { work[column][j] /= scale; }
        for i in 0..k {
            if i == column { continue; }
            let factor = work[i][column];
            for j in 0..=k { let correction = factor * work[column][j]; work[i][j] -= correction; }
        }
    }
    work.iter().map(|r| r[k]).collect()
}

fn occupancy(paths: &[Vec<usize>], k: usize) -> (Vec<usize>, Vec<usize>, usize) {
    let mut positions = vec![0; k];
    let mut runs = vec![0; k];
    let mut total = 0;
    for path in paths {
        for &i in path { positions[i] += 1; total += 1; }
        for (_, _, i) in evaluation::runs(path) { runs[i] += 1; }
    }
    (positions, runs, total)
}

fn alignment(matrix: &Confusion) -> (Vec<usize>, i64) {
    fn visit(path: &mut Vec<usize>, matrix: &Confusion, best: &mut (Vec<usize>, i64)) {
        if path.len() == matrix.len() {
            let count = path.iter().enumerate().map(|(j, &i)| matrix[i][j]).sum();
            if best.0.is_empty() || count > best.1 { *best = (path.clone(), count); }
            return;
        }
        for i in 0..matrix.len() { if !path.contains(&i) { path.push(i); visit(path, matrix, best); path.pop(); } }
    }
    let mut best = (Vec::new(), 0);
    visit(&mut Vec::new(), matrix, &mut best);
    best
}

fn mean(numerator: usize, denominator: usize) -> String {
    if denominator == 0 { "-".into() } else { real(numerator as f64 / denominator as f64) }
}

fn main() -> io::Result<()> {
    let input = model_io::read()?;
    let params = Params::read(&input);
    let states = &input.states;
    let symbols = &input.symbols;
    let k = states.len();
    let m = symbols.len();
    let (unlabeled, mut rejected) = validate(&input.unlabeled, "sequences.txt", symbols, states, input.missing, &params);
    let unlabeled_rejected = rejected.len();
    let (labeled, labeled_errors) = validate(&input.labeled, "labeled.txt", symbols, states, input.missing, &params);
    let labeled_rejected = labeled_errors.len();
    rejected.extend(labeled_errors);
    let train: Vec<Record> = labeled.iter().filter(|r| r.role == "TRAIN").cloned().collect();
    let test: Vec<Record> = labeled.iter().filter(|r| r.role == "TEST").cloned().collect();
    let sequences: Vec<Observation> = unlabeled.iter().map(|r| r.observation.clone()).collect();
    let heldout: Vec<Observation> = train.iter().chain(&test).map(|r| r.observation.clone()).collect();
    let test_observations: Vec<Observation> = test.iter().map(|r| r.observation.clone()).collect();
    let mut bw_models = vec![input.model.clone()];
    let mut bw_loglik = vec![training::total_loglik(&input.model, &sequences)];
    let mut bw_heldout = vec![training::total_loglik(&input.model, &heldout)];
    let mut log_trace = vec!["iteration,loglik,heldout,change,max_change,status".into(), format!("0,{},{},,,", real(bw_loglik[0]), real(bw_heldout[0]))];
    let mut violations = 0;
    for iteration in 1..=params.iterations {
        let previous = bw_models.last().unwrap();
        let next = training::baum_step(previous, &sequences, params.pseudocount);
        let probabilities = |model: &Model| model.initial.iter().copied().chain(model.transition.iter().flat_map(|r| r.iter().copied()))
            .chain(model.emission.iter().flat_map(|r| r.iter().copied())).collect::<Vec<_>>();
        let maximum_change = probabilities(previous).iter().zip(probabilities(&next)).map(|(a, b)| (a - b).abs()).fold(0.0, f64::max);
        let likelihood = training::total_loglik(&next, &sequences);
        let heldout = training::total_loglik(&next, &heldout);
        let before = *bw_loglik.last().unwrap();
        let violation = likelihood < before - 0.000001 * before.abs();
        if violation { violations += 1; }
        log_trace.push(format!("{},{},{},{},{},{}", iteration, real(likelihood), real(heldout), real(likelihood - before), fixed(maximum_change, 6), if violation { "violation" } else { "ok" }));
        bw_loglik.push(likelihood);
        bw_heldout.push(heldout);
        bw_models.push(next);
    }
    let mut vt = input.model.clone();
    let mut vt_paths: Vec<Vec<usize>> = sequences.iter().map(|s| inference::viterbi(&vt, s).path).collect();
    let vt_logprob = sequences.iter().map(|s| inference::viterbi(&vt, s).logprob).sum::<f64>();
    let mut vt_trace = vec!["iteration,logprob,loglik,changed".into(), format!("0,{},{},", real(vt_logprob), real(bw_loglik[0]))];
    let mut vt_iterations = 0;
    let mut converged = false;
    for iteration in 1..=params.iterations {
        let pairs: Vec<(Observation, Vec<usize>)> = sequences.iter().cloned().zip(vt_paths.iter().cloned()).collect();
        vt = training::count(&pairs, k, m, params.pseudocount, "VITERBI_TRAINING");
        let decodings: Vec<inference::Viterbi> = sequences.iter().map(|s| inference::viterbi(&vt, s)).collect();
        let changed: usize = decodings.iter().zip(&vt_paths).map(|(d, previous)| d.path.len() - correct(&d.path, previous)).sum();
        let logprob: f64 = decodings.iter().map(|d| d.logprob).sum();
        vt_trace.push(format!("{},{},{},{}", iteration, real(logprob), real(training::total_loglik(&vt, &sequences)), changed));
        vt_paths = decodings.into_iter().map(|d| d.path).collect();
        vt_iterations = iteration;
        if changed == 0 { converged = true; break; }
    }
    let mut cv_counts = Vec::new();
    let mut cv_fold_counts = Vec::new();
    let mut cv_matrices = Vec::new();
    let training_positions: usize = train.iter().map(|r| r.observation.len()).sum();
    let test_positions: usize = test.iter().map(|r| r.observation.len()).sum();
    for smoothing in &params.smoothing {
        let alpha = smoothing.parse().unwrap();
        let mut matrix = vec![vec![0; k]; k];
        let mut folds = Vec::new();
        for fold in 0..params.folds {
            let records: Vec<Record> = train.iter().enumerate().filter(|(i, _)| i % params.folds != fold).map(|(_, r)| r.clone()).collect();
            let model = training::count(&pairs(&records), k, m, alpha, "SUPERVISED");
            let mut count = 0;
            for (i, r) in train.iter().enumerate() {
                if i % params.folds == fold {
                    let path = inference::viterbi(&model, &r.observation).path;
                    count += correct(&r.truth, &path);
                    evaluation::accumulate(&mut matrix, &r.truth, &path);
                }
            }
            folds.push(count);
        }
        cv_counts.push(folds.iter().sum::<usize>());
        cv_fold_counts.push(folds);
        cv_matrices.push(matrix);
    }
    let mut selected = 0;
    for i in 1..cv_counts.len() { if cv_counts[i] > cv_counts[selected] { selected = i; } }
    let smoothing: f64 = params.smoothing[selected].parse().unwrap();
    let supervised = training::count(&pairs(&train), k, m, smoothing, "SUPERVISED");
    let bw = bw_models.last().unwrap().clone();
    let models = vec![input.model.clone(), bw, vt, supervised];
    let decodings: Vec<Vec<Decoding>> = models.iter().map(|model| test.iter().map(|r| inference::decode(model, &r.observation)).collect()).collect();
    let mut evaluation_lines = Vec::new();
    let mut test_correct = vec![[0usize; 2]; models.len()];
    for (i, model) in models.iter().enumerate() {
        for decoder in 0..2 {
            if !evaluation_lines.is_empty() { evaluation_lines.push(String::new()); }
            let (lines, count) = evaluation_block(model, decoder, &test, &decodings[i], states, &params);
            evaluation_lines.extend(lines);
            test_correct[i][decoder] = count;
        }
    }
    evaluation_lines.extend([String::new(), format!("CROSS_VALIDATION folds {}", params.folds)]);
    for (i, candidate) in params.smoothing.iter().enumerate() {
        evaluation_lines.push(format!("SMOOTHING {} positions {} correct {} accuracy {}", candidate, training_positions, cv_counts[i], fraction(cv_counts[i] as i64, training_positions as i64)));
    }
    evaluation_lines.push(format!("SELECTED {}", params.smoothing[selected]));
    for fold in 0..params.folds {
        let records: Vec<&Record> = train.iter().enumerate().filter(|(i, _)| i % params.folds == fold).map(|(_, r)| r).collect();
        let positions: usize = records.iter().map(|r| r.observation.len()).sum();
        evaluation_lines.push(format!("FOLD {} records {} positions {} correct {} accuracy {}", fold + 1, records.len(), positions, cv_fold_counts[selected][fold], fraction(cv_fold_counts[selected][fold] as i64, positions as i64)));
    }
    evaluation_lines.extend(evaluation::metrics(&cv_matrices[selected], states));
    evaluation_lines.extend([String::new(), "LEARNING_CURVE".into()]);
    for r in 1..=train.len() {
        let model = training::count(&pairs(&train[..r]), k, m, smoothing, "SUPERVISED");
        let count: usize = test.iter().map(|r| correct(&r.truth, &inference::viterbi(&model, &r.observation).path)).sum();
        evaluation_lines.push(format!("RECORDS {} correct {} accuracy {}", r, count, fraction(count as i64, test_positions as i64)));
    }
    let mut posterior_generator = sampler::Generator(params.posterior_seed);
    let mut decoding_lines = Vec::new();
    let mut segment_lines = vec!["sequence,decoder,start,end,length,mean_posterior,support,rich_fraction,motif_ratio,island".into()];
    for record in &unlabeled {
        let decode = inference::decode(&models[1], &record.observation);
        let samples: Vec<Vec<usize>> = (0..params.posterior_samples).map(|_| sampler::posterior(&models[1], &decode.fb, &mut posterior_generator)).collect();
        let expected = samples.iter().map(|p| segments(p, &params).len()).sum::<usize>() as f64 / params.posterior_samples as f64;
        let confident: String = decode.posterior.iter().enumerate().map(|(t, &i)| if decode.confidence[t] < params.confidence { '.' } else { states[i] }).collect();
        let imputed: String = record.observation.iter().enumerate().map(|(t, &observed)| {
            if let Some(c) = observed { symbols[c] } else {
                let probabilities: Vec<f64> = (0..m).map(|c| (0..k).map(|i| decode.fb.gamma[t][i] * models[1].emission[i][c]).sum()).collect();
                symbols[inference::maximum(&probabilities)].to_ascii_lowercase()
            }
        }).collect();
        decoding_lines.extend([format!("SEQUENCE {} length {} loglik {} viterbi {} differences {} uncertain {} expected_segments {}", record.name, record.observation.len(), real(decode.fb.loglik), real(decode.viterbi.logprob),
            record.observation.len() - correct(&decode.viterbi.path, &decode.posterior), decode.confidence.iter().filter(|&&c| c < params.confidence).count(), real(expected)),
            format!("VITERBI {}", path_text(&decode.viterbi.path, states)), format!("POSTERIOR {}", path_text(&decode.posterior, states)), format!("CONFIDENT {}", confident), format!("IMPUTED {}", imputed)]);
        for decoder in 0..2 {
            for segment in segments(paths(&decode, decoder), &params) {
                let (start, end) = segment;
                let length = end - start + 1;
                let posterior = (start..=end).map(|t| decode.fb.gamma[t][params.state]).sum::<f64>() / length as f64;
                let support = samples.iter().filter(|p| 2 * p[start..=end].iter().filter(|&&i| i == params.state).count() > length).count();
                let composition = composition(&record.observation, segment, &params);
                segment_lines.push(format!("{},{},{},{},{},{},{},{},{},{}", record.name, if decoder == 0 { "viterbi" } else { "posterior" }, start + 1, end + 1, length, real(posterior), support,
                    composition.rich.map_or("-".into(), real), composition.motif.map_or("-".into(), real), if composition.island { "yes" } else { "no" }));
            }
        }
    }
    let mut sample_generator = sampler::Generator(params.sample_seed);
    let mut sample_lines = Vec::new();
    let mut synthetic_correct = [0; 2];
    for sample in 1..=params.sample_count {
        let (observation, path) = sampler::synthetic(&models[1], params.sample_length, &mut sample_generator);
        let decode = inference::decode(&models[1], &observation);
        let a = correct(&path, &decode.viterbi.path);
        let b = correct(&path, &decode.posterior);
        synthetic_correct[0] += a;
        synthetic_correct[1] += b;
        sample_lines.extend([format!("SAMPLE {} loglik {} viterbi {} viterbi_correct {} posterior_correct {}", sample, real(decode.fb.loglik), real(decode.viterbi.logprob), a, b),
            format!("STATES {}", path_text(&path, states)), format!("SYMBOLS {}", observation.iter().map(|c| symbols[c.unwrap()]).collect::<String>()),
            format!("VITERBI {}", path_text(&decode.viterbi.path, states)), format!("POSTERIOR {}", path_text(&decode.posterior, states))]);
    }
    let sample_positions = params.sample_count * params.sample_length;
    sample_lines.push(format!("TOTAL positions {} viterbi_accuracy {} posterior_accuracy {}", sample_positions, fraction(synthetic_correct[0] as i64, sample_positions as i64), fraction(synthetic_correct[1] as i64, sample_positions as i64)));
    let total_positions: usize = sequences.iter().map(Vec::len).sum();
    let missing_positions = sequences.iter().flat_map(|s| s.iter()).filter(|s| s.is_none()).count();
    let labeled_positions: usize = labeled.iter().map(|r| r.observation.len()).sum();
    let labeled_missing = labeled.iter().flat_map(|r| r.observation.iter()).filter(|s| s.is_none()).count();
    let mut report = vec!["INPUT".into(), format!("SEQUENCES accepted {} rejected {} positions {} missing {}", unlabeled.len(), unlabeled_rejected, total_positions, missing_positions),
        format!("LABELED train {} test {} rejected {} positions {} missing {}", train.len(), test.len(), labeled_rejected, labeled_positions, labeled_missing)];
    report.extend(rejected);
    let mut symbol_counts = vec![0usize; m];
    for sequence in &sequences { for &symbol in sequence { if let Some(c) = symbol { symbol_counts[c] += 1; } } }
    report.push(format!("COMPOSITION {}", (0..m).map(|c| format!("{} {}", symbols[c], real(symbol_counts[c] as f64 / (total_positions - missing_positions) as f64))).collect::<Vec<_>>().join(" ")));
    for (role, records) in [("TRAIN", &train), ("TEST", &test)] {
        let paths: Vec<Vec<usize>> = records.iter().map(|r| r.truth.clone()).collect();
        let (counts, runs, total) = occupancy(&paths, k);
        for i in 0..k { report.push(format!("TRUTH {} {} occupancy {} mean_run {}", role, states[i], real(counts[i] as f64 / total as f64), mean(counts[i], runs[i]))); }
    }
    let unlabeled_decodings: Vec<Vec<Decoding>> = models.iter().map(|model| sequences.iter().map(|s| inference::decode(model, s)).collect()).collect();
    let mut preferences = [0usize; 4];
    for r in 0..unlabeled.len() {
        let likelihoods: Vec<f64> = unlabeled_decodings.iter().map(|d| d[r].fb.loglik).collect();
        preferences[inference::maximum(&likelihoods)] += 1;
    }
    let best_heldout = inference::maximum(&bw_heldout);
    report.extend([String::new(), format!("TRAINING BAUM_WELCH iterations {} initial_loglik {} final_loglik {} violations {} best_heldout_iteration {}", params.iterations, real(bw_loglik[0]), real(*bw_loglik.last().unwrap()), violations, best_heldout),
        format!("TRAINING VITERBI_TRAINING iterations {} converged {}", vt_iterations, if converged { "yes" } else { "no" }), format!("TRAINING SUPERVISED smoothing {}", params.smoothing[selected]),
        format!("PREFERENCE INITIAL {} BAUM_WELCH {} VITERBI_TRAINING {} SUPERVISED {}", preferences[0], preferences[1], preferences[2], preferences[3])]);
    for a in 0..models.len() {
        for b in a + 1..models.len() {
            let count: usize = unlabeled_decodings[a].iter().zip(&unlabeled_decodings[b]).map(|(x, y)| correct(&x.viterbi.path, &y.viterbi.path)).sum();
            report.push(format!("AGREEMENT {} {} {}", models[a].name, models[b].name, fraction(count as i64, total_positions as i64)));
        }
    }
    for decoder in 0..2 {
        let mut best = 0;
        for i in 1..models.len() { if test_correct[i][decoder] > test_correct[best][decoder] { best = i; } }
        report.push(format!("BEST {} {} accuracy {}", if decoder == 0 { "VITERBI" } else { "POSTERIOR" }, models[best].name, fraction(test_correct[best][decoder] as i64, test_positions as i64)));
    }
    for (j, model) in models.iter().enumerate() {
        let likelihood: f64 = unlabeled_decodings[j].iter().map(|d| d.fb.loglik).sum();
        let model_paths: Vec<Vec<usize>> = unlabeled_decodings[j].iter().map(|d| d.viterbi.path.clone()).collect();
        let (counts, runs, total) = occupancy(&model_paths, k);
        let mut segment_count = 0;
        let mut segment_length = 0;
        let mut islands = 0;
        for (path, observation) in model_paths.iter().zip(&sequences) {
            for segment in segments(path, &params) { segment_count += 1; segment_length += segment.1 - segment.0 + 1; if composition(observation, segment, &params).island { islands += 1; } }
        }
        let mut matrix = vec![vec![0; k]; k];
        for record in &train { evaluation::accumulate(&mut matrix, &record.truth, &inference::viterbi(model, &record.observation).path); }
        let (permutation, agreement) = alignment(&matrix);
        let stationary = stationary(model);
        report.extend([String::new(), format!("MODEL {}", model.name), format!("LOGLIK unlabeled {} per_symbol {} test {}", real(likelihood), real(likelihood / (total_positions - missing_positions) as f64), real(training::total_loglik(model, &test_observations))),
            format!("SEGMENTS count {} mean_length {} islands {}", segment_count, mean(segment_length, segment_count), islands),
            format!("ALIGNMENT {} agreement {}", (0..k).map(|i| format!("{}={}", states[i], states[permutation[i]])).collect::<Vec<_>>().join(" "), fraction(agreement, training_positions as i64))]);
        for i in 0..k { report.push(format!("STATE {} stationary {} duration {} occupancy {} mean_run {}", states[i], real(stationary[i]), real(1.0 / (1.0 - model.transition[i][i])), real(counts[i] as f64 / total as f64), mean(counts[i], runs[i]))); }
    }
    let mut model_lines = Vec::new();
    for model in &models[1..] { if !model_lines.is_empty() { model_lines.push(String::new()); } model_lines.extend(model_io::format(model, states, symbols, input.missing)); }
    for (name, lines) in [("trained_model.txt", model_lines), ("loglik_trace.csv", log_trace), ("viterbi_trace.csv", vt_trace), ("decodings.txt", decoding_lines),
        ("segments.csv", segment_lines), ("samples.txt", sample_lines), ("evaluation.txt", evaluation_lines), ("report.txt", report)] { model_io::write(name, &lines)?; }
    Ok(())
}
