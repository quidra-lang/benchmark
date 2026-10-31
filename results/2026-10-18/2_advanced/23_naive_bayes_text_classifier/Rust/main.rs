mod tokenizer;
mod vocabulary;
mod naive_bayes;
mod rocchio;
mod evaluation;

use std::collections::{BTreeMap, HashMap, HashSet};
use std::{fs, io};
use evaluation::{Evaluation, fraction_text, proportion_text, real_text, rounded};
use naive_bayes::{NaiveBayes, Prediction, TrainingCounts, NB_NAMES, smoothed_log};
use rocchio::Rocchio;
use tokenizer::Tokens;
use vocabulary::{Vocabulary, first_occurrences};

const MODELS: [&str; 5] = ["multinomial", "bernoulli", "complement", "rocchio", "vote"];
const PAIRS: [(usize, usize); 6] = [(0, 1), (0, 2), (0, 3), (1, 2), (1, 3), (2, 3)];
const FOLDS: usize = 5;

fn read_lines(name: &str) -> io::Result<Vec<String>> { Ok(fs::read_to_string(format!("input/{name}"))?.lines().map(str::to_owned).collect()) }
fn write_lines(name: &str, lines: &[String]) -> io::Result<()> { fs::write(format!("output/{name}"), lines.join("\n") + "\n") }
fn join_parts(parts: Vec<Vec<String>>) -> Vec<String> { parts.iter().map(|part| part.join("\n")).collect::<Vec<_>>().join("\n\n").split('\n').map(str::to_owned).collect() }
fn hundredths(text: &str) -> i64 { let (a, b) = text.split_once('.').unwrap(); a.parse::<i64>().unwrap() * 100 + b.parse::<i64>().unwrap() }
fn hundredths_text(value: i64) -> String { format!("{}.{:02}", value / 100, value % 100) }
fn prop(n: usize, d: usize) -> String { proportion_text(n as i64, d as i64) }
fn class_counts_text(names: &[String], counts: &[usize]) -> String { names.iter().zip(counts).map(|(name, count)| format!("{name} {count}")).collect::<Vec<_>>().join(" ") }
fn ranked_ratios(mut entries: Vec<(i64, i64, usize)>) -> Vec<(i64, i64, usize)> {
    entries.sort_by(|a, b| (b.0 * a.1).cmp(&(a.0 * b.1)).then(a.2.cmp(&b.2)));
    entries
}
fn majority_vote(labels: &[usize], class_count: usize) -> Prediction {
    let mut votes = vec![0; class_count];
    for &label in labels { votes[label] += 1; }
    let mut winner = labels[0];
    for &label in labels { if votes[label] > votes[winner] { winner = label; } }
    Prediction { label: winner, score: votes[winner] as f64 / labels.len() as f64, ranking: Vec::new(), scores: Vec::new(), probabilities: Vec::new(), normalizer: 0.0, margin: 0.0 }
}

struct Settings {
    alphas: Vec<i64>, min_df: i64, features: usize, bigrams: bool, top: usize,
    curve: Vec<usize>, sizes: Vec<usize>, thresholds: Vec<i64>, lengths: Vec<usize>,
    iterations: usize, weight: i64, resamples: usize, seed: i64,
}
impl Settings {
    fn new(lines: &[String]) -> Self {
        let mut values = HashMap::new();
        for line in lines { let fields: Vec<&str> = line.split(' ').collect(); values.insert(fields[0], fields[1..].to_vec()); }
        Self {
            alphas: values["ALPHAS"].iter().map(|value| hundredths(value)).collect(),
            min_df: values["MIN_DF"][0].parse().unwrap(), features: values["FEATURES"][0].parse().unwrap(),
            bigrams: values["BIGRAMS"][0] == "yes", top: values["TOP"][0].parse().unwrap(),
            curve: values["CURVE"].iter().map(|v| v.parse().unwrap()).collect(),
            sizes: values["SIZES"].iter().map(|v| v.parse().unwrap()).collect(),
            thresholds: values["THRESHOLDS"].iter().map(|v| hundredths(v)).collect(),
            lengths: values["LENGTHS"].iter().map(|v| v.parse().unwrap()).collect(),
            iterations: values["EM_ITERATIONS"][0].parse().unwrap(), weight: hundredths(values["EM_WEIGHT"][0]),
            resamples: values["BOOTSTRAP"][0].parse().unwrap(), seed: values["BOOTSTRAP"][1].parse().unwrap(),
        }
    }
}
struct Document { name: String, label: Option<usize>, tokens: Tokens }
struct FoldSummary { train: usize, validate: usize, candidates: usize, vocabulary: usize }
struct CrossValidationRun { predictions: Vec<usize>, evaluation: Evaluation, fold_correct: Vec<usize> }
impl CrossValidationRun {
    fn new(predictions: Vec<usize>, truths: &[usize], classes: usize) -> Self {
        let mut fold_correct = vec![0; FOLDS];
        for (index, (&truth, &predicted)) in truths.iter().zip(&predictions).enumerate() { if truth == predicted { fold_correct[index % FOLDS] += 1; } }
        let evaluation = Evaluation::new(classes, truths, &predictions);
        Self { predictions, evaluation, fold_correct }
    }
}
struct Training { bigrams: bool, vocabulary: Vocabulary, counts: TrainingCounts, rocchio: Rocchio, models: Vec<NaiveBayes> }
impl Training {
    fn new(documents: &[&Document], bigrams: bool, classes: usize, min_df: i64, size: usize) -> Self {
        let sequences: Vec<&[String]> = documents.iter().map(|document| document.tokens.terms(bigrams)).collect();
        let labels: Vec<usize> = documents.iter().map(|document| document.label.unwrap()).collect();
        let vocabulary = Vocabulary::new(&sequences, &labels, classes, min_df, size);
        let encoded: Vec<Vec<usize>> = sequences.iter().map(|sequence| vocabulary.encode(sequence)).collect();
        let counts = TrainingCounts::new(&encoded, &labels, classes, vocabulary.size());
        let rocchio = Rocchio::new(&encoded, &labels, classes, &vocabulary.frequencies);
        Self { bigrams, vocabulary, counts, rocchio, models: Vec::new() }
    }
    fn train(&mut self, alphas: &[i64; 3]) { self.models = (0..3).map(|kind| NaiveBayes::train(kind, &self.counts, alphas[kind])).collect(); }
    fn encode(&self, document: &Document) -> Vec<usize> { self.vocabulary.encode(document.tokens.terms(self.bigrams)) }
    fn classify(&self, model: usize, sequence: &[usize]) -> Prediction { if model == 3 { self.rocchio.predict(sequence) } else { self.models[model].predict(sequence) } }
}
struct Experiment {
    settings: Settings, classes: Vec<String>, training: Vec<Document>, tests: Vec<Document>, unlabelled: Vec<Document>,
    labelled: Vec<usize>, truths: Vec<usize>, folds: Vec<FoldSummary>, cv_runs: Vec<Vec<CrossValidationRun>>,
    selected_positions: [usize; 3], selected: [i64; 3], final_training: Training,
    test_sequences: Vec<Vec<usize>>, predictions: Vec<Vec<Prediction>>, correct: Vec<Vec<bool>>,
}
impl Experiment {
    fn new() -> io::Result<Self> {
        let settings = Settings::new(&read_lines("params.txt")?);
        let stopwords: HashSet<String> = read_lines("stopwords.txt")?.into_iter().collect();
        let rows = read_lines("train.txt")?;
        let mut classes: Vec<String> = rows.iter().map(|line| line.split_once('\t').unwrap().0.to_owned()).collect();
        classes.sort(); classes.dedup();
        let positions: HashMap<String, usize> = classes.iter().enumerate().map(|(i, name)| (name.clone(), i)).collect();
        let training: Vec<Document> = rows.iter().enumerate().map(|(index, line)| {
            let (label, text) = line.split_once('\t').unwrap();
            Document { name: (index + 1).to_string(), label: Some(positions[label]), tokens: Tokens::new(text, &stopwords) }
        }).collect();
        let tests: Vec<Document> = read_lines("test.txt")?.iter().map(|line| {
            let fields: Vec<&str> = line.splitn(3, '\t').collect();
            Document { name: fields[0].to_owned(), label: positions.get(fields[1]).copied(), tokens: Tokens::new(fields[2], &stopwords) }
        }).collect();
        let unlabelled: Vec<Document> = read_lines("unlabelled.txt")?.iter().enumerate().map(|(i, text)| Document { name: (i + 1).to_string(), label: None, tokens: Tokens::new(text, &stopwords) }).collect();
        let labelled: Vec<usize> = (0..tests.len()).filter(|&i| tests[i].label.is_some()).collect();
        let truths: Vec<usize> = labelled.iter().map(|&i| tests[i].label.unwrap()).collect();
        let training_truths: Vec<usize> = training.iter().map(|document| document.label.unwrap()).collect();
        let mut nb_predictions = vec![vec![vec![0; training.len()]; settings.alphas.len()]; 3];
        let mut rocchio_predictions = vec![0; training.len()];
        let mut folds = Vec::new();
        for fold in 0..FOLDS {
            let members: Vec<&Document> = training.iter().enumerate().filter(|(i, _)| i % FOLDS != fold).map(|(_, document)| document).collect();
            let held_out: Vec<usize> = (0..training.len()).filter(|i| i % FOLDS == fold).collect();
            let fitted = Training::new(&members, settings.bigrams, classes.len(), settings.min_df, settings.features);
            folds.push(FoldSummary { train: members.len(), validate: held_out.len(), candidates: fitted.vocabulary.candidate_count, vocabulary: fitted.vocabulary.size() });
            let sequences: Vec<Vec<usize>> = held_out.iter().map(|&i| fitted.encode(&training[i])).collect();
            for kind in 0..3 {
                for (a, &alpha) in settings.alphas.iter().enumerate() {
                    let model = NaiveBayes::train(kind, &fitted.counts, alpha);
                    for (&index, sequence) in held_out.iter().zip(&sequences) { nb_predictions[kind][a][index] = model.predict(sequence).label; }
                }
            }
            for (&index, sequence) in held_out.iter().zip(&sequences) { rocchio_predictions[index] = fitted.rocchio.predict(sequence).label; }
        }
        let mut cv_runs: Vec<Vec<CrossValidationRun>> = nb_predictions.into_iter().map(|runs| runs.into_iter().map(|labels| CrossValidationRun::new(labels, &training_truths, classes.len())).collect()).collect();
        cv_runs.push(vec![CrossValidationRun::new(rocchio_predictions, &training_truths, classes.len())]);
        let mut selected_positions = [0; 3];
        for kind in 0..3 {
            for a in 1..settings.alphas.len() {
                if rounded(cv_runs[kind][a].evaluation.macro_f1) > rounded(cv_runs[kind][selected_positions[kind]].evaluation.macro_f1) { selected_positions[kind] = a; }
            }
        }
        let selected = std::array::from_fn(|kind| settings.alphas[selected_positions[kind]]);
        let mut final_training = Training::new(&training.iter().collect::<Vec<_>>(), settings.bigrams, classes.len(), settings.min_df, settings.features);
        final_training.train(&selected);
        let test_sequences: Vec<Vec<usize>> = tests.iter().map(|document| final_training.encode(document)).collect();
        let mut predictions: Vec<Vec<Prediction>> = (0..4).map(|model| test_sequences.iter().map(|sequence| final_training.classify(model, sequence)).collect()).collect();
        let votes = (0..tests.len()).map(|index| majority_vote(&(0..4).map(|model| predictions[model][index].label).collect::<Vec<_>>(), classes.len())).collect();
        predictions.push(votes);
        let correct = (0..5).map(|model| labelled.iter().map(|&index| Some(predictions[model][index].label) == tests[index].label).collect()).collect();
        Ok(Self { settings, classes, training, tests, unlabelled, labelled, truths, folds, cv_runs, selected_positions, selected, final_training, test_sequences, predictions, correct })
    }
    fn alpha_text(&self, model: usize) -> String { if model < 3 { hundredths_text(self.selected[model]) } else { "-".to_owned() } }
    fn selected_run(&self, model: usize) -> &CrossValidationRun { &self.cv_runs[model][if model < 3 { self.selected_positions[model] } else { 0 }] }
    fn trained(&self, documents: &[&Document], bigrams: bool, size: usize) -> Training {
        let mut fitted = Training::new(documents, bigrams, self.classes.len(), self.settings.min_df, size);
        fitted.train(&self.selected);
        fitted
    }
    fn test_evaluations(&self, fitted: &Training) -> Vec<Evaluation> {
        let sequences: Vec<Vec<usize>> = self.labelled.iter().map(|&i| fitted.encode(&self.tests[i])).collect();
        (0..4).map(|model| Evaluation::new(self.classes.len(), &self.truths, &sequences.iter().map(|sequence| fitted.classify(model, sequence).label).collect::<Vec<_>>())).collect()
    }
    fn vocabulary_lines(&self) -> Vec<String> {
        let vocabulary = &self.final_training.vocabulary;
        let mut lines = vec![format!("documents {} terms {} candidates {} vocabulary {}", self.training.len(), vocabulary.term_count, vocabulary.candidate_count, vocabulary.size())];
        for (index, entry) in vocabulary.ranking.iter().enumerate() { lines.push(format!("{} {} {} {} {}", index + 1, entry.term, entry.frequency, real_text(entry.score), self.classes[entry.best_class])); }
        lines
    }
    fn cv_lines(&self) -> Vec<String> {
        let mut lines = vec!["model,alpha,correct,accuracy,macro_f1,selected".to_owned()];
        for kind in 0..3 { for (position, &alpha) in self.settings.alphas.iter().enumerate() { lines.push(format!("{},{},{},{}", NB_NAMES[kind], hundredths_text(alpha), self.cv_runs[kind][position].evaluation.fields(), if alpha == self.selected[kind] { "yes" } else { "no" })); } }
        lines.push(format!("rocchio,-,{},yes", self.cv_runs[3][0].evaluation.fields()));
        lines
    }
    fn prediction_lines(&self) -> Vec<String> {
        let mut lines = vec!["id,model,label,score".to_owned()];
        for (index, document) in self.tests.iter().enumerate() { for model in 0..5 { let prediction = &self.predictions[model][index]; lines.push(format!("{},{},{},{}", document.name, MODELS[model], self.classes[prediction.label], real_text(prediction.score))); } }
        lines
    }
    fn curve_lines(&self) -> Vec<String> {
        let mut lines = vec!["size,vocabulary,model,correct,accuracy,macro_f1".to_owned()];
        for &size in &self.settings.curve {
            let fitted = self.trained(&self.training[..size].iter().collect::<Vec<_>>(), self.settings.bigrams, self.settings.features);
            for (model, evaluation) in self.test_evaluations(&fitted).iter().enumerate() { lines.push(format!("{size},{},{},{}", fitted.vocabulary.size(), MODELS[model], evaluation.fields())); }
        }
        lines
    }
    fn feature_lines(&self) -> Vec<String> {
        let mut lines = vec!["terms,features,vocabulary,model,correct,accuracy,macro_f1".to_owned()];
        for (kind, bigrams) in [("unigrams", false), ("bigrams", true)] {
            for &size in &self.settings.sizes {
                let fitted = self.trained(&self.training.iter().collect::<Vec<_>>(), bigrams, size);
                for (model, evaluation) in self.test_evaluations(&fitted).iter().enumerate() { lines.push(format!("{kind},{size},{},{},{}", fitted.vocabulary.size(), MODELS[model], evaluation.fields())); }
            }
        }
        lines
    }
    fn data_part(&self) -> Vec<String> {
        let vocabulary = &self.final_training.vocabulary;
        let mut lines = vec![format!("documents train {} test {} labelled {} unlabelled {} classes {}", self.training.len(), self.tests.len(), self.labelled.len(), self.unlabelled.len(), self.classes.len())];
        let mut train_counts = vec![0; self.classes.len()];
        let mut test_counts = train_counts.clone();
        for document in &self.training { train_counts[document.label.unwrap()] += 1; }
        for &truth in &self.truths { test_counts[truth] += 1; }
        for (label, name) in self.classes.iter().enumerate() { lines.push(format!("class {name} train {} test {}", train_counts[label], test_counts[label])); }
        let (mut raw, mut stopwords, mut short, mut kept, mut bigrams) = (0, 0, 0, 0, 0);
        let mut terms = HashSet::new();
        for document in &self.training {
            let tokens = &document.tokens;
            raw += tokens.raw_count; stopwords += tokens.stopword_count; short += tokens.short_count; kept += tokens.words.len();
            if self.settings.bigrams { bigrams += tokens.bigrams.len(); }
            terms.extend(tokens.terms(self.settings.bigrams).iter().cloned());
        }
        let distinct_bigrams = terms.iter().filter(|term| term.contains('_')).count();
        lines.push(format!("train_tokens raw {raw} stopwords {stopwords} short {short} unigrams {kept} bigrams {bigrams}"));
        lines.push(format!("train_terms unigrams {} bigrams {distinct_bigrams} candidates {} vocabulary {}", terms.len() - distinct_bigrams, vocabulary.candidate_count, vocabulary.size()));
        let total: usize = self.tests.iter().map(|document| document.tokens.terms(self.settings.bigrams).len()).sum();
        let in_vocabulary: usize = self.test_sequences.iter().map(Vec::len).sum();
        lines.push(format!("test_terms total {total} in_vocabulary {in_vocabulary}"));
        let mut occurrences = BTreeMap::<String, usize>::new();
        for document in &self.tests { for word in &document.tokens.words { if !vocabulary.index.contains_key(word) { *occurrences.entry(word.clone()).or_default() += 1; } } }
        let mut ranked: Vec<(String, usize)> = occurrences.into_iter().collect();
        ranked.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
        let mut fields = vec!["test_oov".to_owned()];
        fields.extend(ranked.iter().take(self.settings.top).map(|(word, count)| format!("{word} {count}")));
        lines.push(fields.join(" "));
        lines
    }
    fn folds_part(&self) -> Vec<String> {
        let mut lines = vec![format!("folds {FOLDS}")];
        for (i, summary) in self.folds.iter().enumerate() { lines.push(format!("fold {} train {} validate {} candidates {} vocabulary {}", i + 1, summary.train, summary.validate, summary.candidates, summary.vocabulary)); }
        lines
    }
    fn selection_part(&self) -> Vec<String> {
        let mut lines = vec!["selection".to_owned()];
        for model in 0..4 {
            let run = self.selected_run(model);
            lines.push(format!("{} alpha {} correct {} macro_f1 {} folds {}", MODELS[model], self.alpha_text(model), proportion_text(run.evaluation.correct, run.evaluation.total), real_text(run.evaluation.macro_f1), run.fold_correct.iter().map(ToString::to_string).collect::<Vec<_>>().join(" ")));
        }
        lines
    }
    fn cross_validation_part(&self, model: usize) -> Vec<String> {
        let mut lines = vec![format!("cross_validation {} alpha {}", MODELS[model], self.alpha_text(model))];
        lines.extend(self.selected_run(model).evaluation.lines(&self.classes));
        lines
    }
    fn test_part(&self, model: usize) -> Vec<String> {
        let predicted: Vec<usize> = self.labelled.iter().map(|&index| self.predictions[model][index].label).collect();
        let evaluation = Evaluation::new(self.classes.len(), &self.truths, &predicted);
        let mut lines = vec![format!("test {} alpha {}", MODELS[model], self.alpha_text(model)), format!("labelled {} correct {}", self.labelled.len(), proportion_text(evaluation.correct, evaluation.total))];
        if model < 4 {
            let top_two = self.labelled.iter().zip(&self.truths).filter(|pair| self.predictions[model][*pair.0].ranking[..2].contains(pair.1)).count();
            lines.push(format!("top2 {}", prop(top_two, self.labelled.len())));
        }
        lines.extend(evaluation.lines(&self.classes));
        lines
    }
    fn probability_part(&self, model: usize) -> Vec<String> {
        let thresholds = &self.settings.thresholds;
        let limits: Vec<f64> = thresholds.iter().map(|&value| value as f64 / 100.0).collect();
        let mut rows = vec![0; limits.len() + 1];
        let mut hits = rows.clone();
        let mut sums = vec![0.0; rows.len()];
        let mut accepted = vec![0; limits.len()];
        let mut accepted_hits = accepted.clone();
        let (mut loss, mut brier) = (0.0, 0.0);
        for (position, &index) in self.labelled.iter().enumerate() {
            let prediction = &self.predictions[model][index];
            let truth = self.truths[position];
            let gap = prediction.scores[truth] - prediction.scores[prediction.label];
            loss += prediction.normalizer.ln() - gap;
            let mut squares = 0.0;
            for (label, &probability) in prediction.probabilities.iter().enumerate() { let difference = probability - if label == truth { 1.0 } else { 0.0 }; squares += difference * difference; }
            brier += squares;
            let bucket = limits.iter().filter(|&&limit| prediction.score >= limit).count();
            rows[bucket] += 1; sums[bucket] += prediction.score;
            if self.correct[model][position] { hits[bucket] += 1; }
            for (t, &limit) in limits.iter().enumerate() {
                if prediction.score >= limit { accepted[t] += 1; if self.correct[model][position] { accepted_hits[t] += 1; } }
            }
        }
        let count = self.labelled.len();
        let mut lines = vec![format!("probability {} alpha {}", MODELS[model], self.alpha_text(model)), format!("log_loss {} brier {}", real_text(loss / count as f64), real_text(brier / count as f64))];
        for (bucket, bound) in std::iter::once(&0i64).chain(thresholds).enumerate() {
            let mut line = format!("bin {} rows {}", hundredths_text(*bound), rows[bucket]);
            if rows[bucket] > 0 { line += &format!(" correct {} mean {}", prop(hits[bucket], rows[bucket]), real_text(sums[bucket] / rows[bucket] as f64)); }
            lines.push(line);
        }
        for (t, &threshold) in thresholds.iter().enumerate() { lines.push(format!("threshold {} covered {} correct {}", hundredths_text(threshold), prop(accepted[t], count), if accepted[t] > 0 { prop(accepted_hits[t], accepted[t]) } else { "-".to_owned() })); }
        lines
    }
    fn lengths_part(&self) -> Vec<String> {
        let mut rows = vec![0; self.settings.lengths.len() + 1];
        let mut hits = vec![rows.clone(); 5];
        for (position, &index) in self.labelled.iter().enumerate() {
            let bucket = self.settings.lengths.iter().filter(|&&bound| self.test_sequences[index].len() >= bound).count();
            rows[bucket] += 1;
            for model in 0..5 { if self.correct[model][position] { hits[model][bucket] += 1; } }
        }
        let mut lines = vec!["lengths".to_owned()];
        for (bucket, bound) in std::iter::once(&0usize).chain(&self.settings.lengths).enumerate() {
            let mut line = format!("length {bound} rows {}", rows[bucket]);
            if rows[bucket] > 0 { for model in 0..5 { line += &format!(" {} {}", MODELS[model], prop(hits[model][bucket], rows[bucket])); } }
            lines.push(line);
        }
        lines
    }
    fn comparison_part(&self) -> Vec<String> {
        let mut lines = vec!["comparison".to_owned()];
        for (first, second) in PAIRS {
            let agree = self.predictions[first].iter().zip(&self.predictions[second]).filter(|(a, b)| a.label == b.label).count();
            let b = self.correct[first].iter().zip(&self.correct[second]).filter(|(a, b)| **a && !**b).count() as i64;
            let c = self.correct[first].iter().zip(&self.correct[second]).filter(|(a, b)| **b && !**a).count() as i64;
            let difference = ((b - c).abs() - 1).max(0);
            let statistic = if b + c == 0 { fraction_text(0, 1) } else { fraction_text(difference * difference, b + c) };
            lines.push(format!("{} {} agree {} b {b} c {c} statistic {statistic}", MODELS[first], MODELS[second], prop(agree, self.tests.len())));
        }
        let mut errors = [0; 5];
        for position in 0..self.labelled.len() { errors[(0..4).filter(|&model| !self.correct[model][position]).count()] += 1; }
        lines.push(format!("errors {}", errors.iter().enumerate().map(|(wrong, count)| format!("{wrong} {count}")).collect::<Vec<_>>().join(" ")));
        lines
    }
    fn bootstrap_part(&self) -> Vec<String> {
        let count = self.labelled.len();
        let mut state = self.settings.seed;
        let mut totals = vec![Vec::<usize>::new(); 5];
        for _ in 0..self.settings.resamples {
            let chosen: Vec<usize> = (0..count).map(|_| { state = 48271 * state % 2147483647; state as usize % count }).collect();
            for model in 0..5 { totals[model].push(chosen.iter().filter(|&&position| self.correct[model][position]).count()); }
        }
        let rank = self.settings.resamples / 40;
        let mut lines = vec![format!("bootstrap resamples {} seed {}", self.settings.resamples, self.settings.seed)];
        for model in 0..5 {
            let mut ordered = totals[model].clone(); ordered.sort();
            let sum: usize = ordered.iter().sum();
            let mean = sum as f64 / (self.settings.resamples * count) as f64;
            lines.push(format!("{} mean {} low {} high {}", MODELS[model], real_text(mean), prop(ordered[rank], count), prop(ordered[ordered.len() - 1 - rank], count)));
        }
        for (first, second) in PAIRS {
            let (mut wins, mut ties, mut losses) = (0, 0, 0);
            for (one, other) in totals[first].iter().zip(&totals[second]) { if one > other { wins += 1; } else if one == other { ties += 1; } else { losses += 1; } }
            lines.push(format!("pair {} {} wins {wins} ties {ties} losses {losses}", MODELS[first], MODELS[second]));
        }
        lines
    }
    fn hard_part(&self) -> Vec<String> {
        let mut hard = Vec::new();
        let mut counts = vec![0; self.classes.len()];
        for (index, document) in self.training.iter().enumerate() {
            let predicted: Vec<usize> = (0..4).map(|model| self.selected_run(model).predictions[index]).collect();
            if predicted.iter().all(|label| Some(*label) != document.label) { counts[document.label.unwrap()] += 1; hard.push((document, predicted)); }
        }
        let mut lines = vec![format!("hard_documents {} {}", hard.len(), class_counts_text(&self.classes, &counts))];
        for (document, predicted) in hard.iter().take(self.settings.top) { lines.push(format!("{} true {} predicted {}", document.name, self.classes[document.label.unwrap()], predicted.iter().map(|&label| self.classes[label].clone()).collect::<Vec<_>>().join(" "))); }
        lines
    }
    fn uncertain_part(&self) -> Vec<String> {
        let mut order: Vec<usize> = (0..self.tests.len()).collect();
        order.sort_by_key(|&index| (rounded(self.predictions[0][index].margin), index));
        order.truncate(self.settings.top);
        let mut lines = vec![format!("uncertain multinomial {}", order.len())];
        for index in order {
            let document = &self.tests[index]; let prediction = &self.predictions[0][index];
            let truth = document.label.map(|label| self.classes[label].as_str()).unwrap_or("?");
            lines.push(format!("{} predicted {} runner_up {} margin {} posterior {} true {truth}", document.name, self.classes[prediction.label], self.classes[prediction.ranking[1]], real_text(prediction.margin), real_text(prediction.score)));
        }
        lines
    }
    fn misclassified_part(&self) -> Vec<String> {
        let indices: Vec<usize> = self.labelled.iter().copied().filter(|&index| Some(self.predictions[0][index].label) != self.tests[index].label).collect();
        let mut lines = vec![format!("misclassified multinomial {}", indices.len())];
        let counts = &self.final_training.counts;
        let weights = &self.final_training.models[0].weights;
        let alpha = self.selected[0];
        for index in indices {
            let document = &self.tests[index]; let prediction = &self.predictions[0][index];
            let truth = document.label.unwrap(); let predicted = prediction.label;
            lines.push(format!("{} true {} predicted {} posterior {}", document.name, self.classes[truth], self.classes[predicted], real_text(prediction.score)));
            let sequence = &self.test_sequences[index];
            let entries = first_occurrences(sequence).iter().map(|&term| (100 * counts.occurrences[predicted][term] + alpha, 100 * counts.occurrences[truth][term] + alpha, term)).collect();
            for (_, _, term) in ranked_ratios(entries).into_iter().take(3) {
                let frequency = sequence.iter().filter(|&&value| value == term).count();
                lines.push(format!("  {} count {frequency} evidence {}", self.final_training.vocabulary.terms[term], real_text(weights[predicted][term] - weights[truth][term])));
            }
        }
        lines
    }
    fn maximization(&self, posteriors: &[Prediction], sequences: &[Vec<usize>]) -> NaiveBayes {
        let counts = &self.final_training.counts;
        let share_weight = self.settings.weight as f64 / 100.0;
        let mut occurrences: Vec<Vec<f64>> = counts.occurrences.iter().map(|row| row.iter().map(|&value| value as f64).collect()).collect();
        let mut documents: Vec<f64> = counts.documents.iter().map(|&value| value as f64).collect();
        for (posterior, sequence) in posteriors.iter().zip(sequences) {
            let mut frequencies = vec![0; counts.vocabulary_size];
            for &term in sequence { frequencies[term] += 1; }
            let terms = first_occurrences(sequence);
            for label in 0..self.classes.len() {
                let share = share_weight * posterior.probabilities[label];
                documents[label] += share;
                for &term in &terms { occurrences[label][term] += share * frequencies[term] as f64; }
            }
        }
        let alpha = self.selected[0] as f64;
        let mut weights = Vec::new();
        for row in occurrences {
            let mut total = 0.0;
            for &value in &row { total += value; }
            weights.push(row.iter().map(|value| ((100.0 * value + alpha) / (100.0 * total + alpha * counts.vocabulary_size as f64)).ln()).collect());
        }
        let scale = self.training.len() as f64 + (self.settings.weight * self.unlabelled.len() as i64) as f64 / 100.0;
        let priors = documents.iter().map(|value| (value / scale).ln()).collect();
        NaiveBayes { kind: 0, priors, base: vec![0.0; self.classes.len()], weights }
    }
    fn semi_supervised_part(&self) -> Vec<String> {
        let sequences: Vec<Vec<usize>> = self.unlabelled.iter().map(|document| self.final_training.encode(document)).collect();
        let mut model = self.final_training.models[0].clone();
        let mut previous: Option<Vec<usize>> = None;
        let mut lines = vec![format!("semi_supervised multinomial alpha {} weight {} unlabelled {}", self.alpha_text(0), hundredths_text(self.settings.weight), self.unlabelled.len())];
        for iteration in 0..=self.settings.iterations {
            let posteriors: Vec<Prediction> = sequences.iter().map(|sequence| model.predict(sequence)).collect();
            let assignments: Vec<usize> = posteriors.iter().map(|posterior| posterior.label).collect();
            let predicted: Vec<usize> = self.labelled.iter().map(|&index| model.predict(&self.test_sequences[index]).label).collect();
            let evaluation = Evaluation::new(self.classes.len(), &self.truths, &predicted);
            let changed = previous.as_ref().map(|old| old.iter().zip(&assignments).filter(|(a, b)| a != b).count().to_string()).unwrap_or_else(|| "-".to_owned());
            let mut assigned = vec![0; self.classes.len()];
            for &label in &assignments { assigned[label] += 1; }
            lines.push(format!("iteration {iteration} correct {} macro_f1 {} changed {changed} assigned {}", proportion_text(evaluation.correct, evaluation.total), real_text(evaluation.macro_f1), class_counts_text(&self.classes, &assigned)));
            if iteration < self.settings.iterations { model = self.maximization(&posteriors, &sequences); }
            previous = Some(assignments);
        }
        lines
    }
    fn metrics_parts(&self) -> Vec<Vec<String>> {
        let mut parts = vec![self.data_part(), self.folds_part(), self.selection_part()];
        parts.extend((0..4).map(|model| self.cross_validation_part(model)));
        parts.extend((0..5).map(|model| self.test_part(model)));
        parts.extend((0..3).map(|model| self.probability_part(model)));
        parts.extend([self.lengths_part(), self.comparison_part(), self.bootstrap_part(), self.hard_part(), self.uncertain_part(), self.misclassified_part(), self.semi_supervised_part()]);
        parts
    }
    fn top_feature_parts(&self) -> Vec<Vec<String>> {
        let counts = &self.final_training.counts;
        let size = counts.vocabulary_size;
        let mut parts = Vec::new();
        for kind in 0..2 {
            let alpha = self.selected[kind];
            let (table, totals, overall, outcomes) = if kind == 0 { (&counts.occurrences, &counts.totals, counts.total, size) } else { (&counts.containing, &counts.documents, counts.document_total, 2) };
            let term_totals: Vec<i64> = (0..size).map(|term| table.iter().map(|row| row[term]).sum()).collect();
            parts.push(vec![format!("model {} alpha {} vocabulary {size} top {}", MODELS[kind], hundredths_text(alpha), self.settings.top)]);
            for (label, name) in self.classes.iter().enumerate() {
                let total = totals[label]; let other = overall - total;
                let mut lines = vec![format!("class {name} total {total} other {other}")];
                let entries = (0..size).map(|term| (100 * table[label][term] + alpha, 100 * (term_totals[term] - table[label][term]) + alpha, term)).collect();
                for (rank, (_, _, term)) in ranked_ratios(entries).into_iter().take(self.settings.top).enumerate() {
                    let count = table[label][term]; let other_count = term_totals[term] - count;
                    let odds = smoothed_log(count, total, alpha, outcomes) - smoothed_log(other_count, other, alpha, outcomes);
                    lines.push(format!("{} {} {count} {other_count} {}", rank + 1, self.final_training.vocabulary.terms[term], real_text(odds)));
                }
                parts.push(lines);
            }
        }
        parts
    }
}
fn main() -> io::Result<()> {
    let experiment = Experiment::new()?;
    fs::create_dir_all("output")?;
    write_lines("vocabulary.txt", &experiment.vocabulary_lines())?;
    write_lines("cv_results.csv", &experiment.cv_lines())?;
    write_lines("predictions.csv", &experiment.prediction_lines())?;
    write_lines("learning_curve.csv", &experiment.curve_lines())?;
    write_lines("feature_study.csv", &experiment.feature_lines())?;
    write_lines("metrics.txt", &join_parts(experiment.metrics_parts()))?;
    write_lines("top_features.txt", &join_parts(experiment.top_feature_parts()))
}
