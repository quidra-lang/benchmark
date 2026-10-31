use crate::vocabulary::first_occurrences;

pub const NB_NAMES: [&str; 3] = ["multinomial", "bernoulli", "complement"];
pub struct TrainingCounts {
    pub class_count: usize,
    pub vocabulary_size: usize,
    pub document_total: i64,
    pub documents: Vec<i64>,
    pub occurrences: Vec<Vec<i64>>,
    pub containing: Vec<Vec<i64>>,
    pub totals: Vec<i64>,
    pub total: i64,
    pub term_totals: Vec<i64>,
}
impl TrainingCounts {
    pub fn new(sequences: &[Vec<usize>], labels: &[usize], class_count: usize, vocabulary_size: usize) -> Self {
        let mut documents = vec![0; class_count];
        let mut occurrences = vec![vec![0; vocabulary_size]; class_count];
        let mut containing = occurrences.clone();
        for (sequence, &label) in sequences.iter().zip(labels) {
            documents[label] += 1;
            for &term in sequence { occurrences[label][term] += 1; }
            for term in first_occurrences(sequence) { containing[label][term] += 1; }
        }
        let totals: Vec<i64> = occurrences.iter().map(|row| row.iter().sum()).collect();
        let total = totals.iter().sum();
        let term_totals = (0..vocabulary_size).map(|term| occurrences.iter().map(|row| row[term]).sum()).collect();
        Self { class_count, vocabulary_size, document_total: sequences.len() as i64, documents, occurrences, containing, totals, total, term_totals }
    }
}
#[derive(Clone)]
pub struct Prediction {
    pub label: usize,
    pub score: f64,
    pub ranking: Vec<usize>,
    pub scores: Vec<f64>,
    pub probabilities: Vec<f64>,
    pub normalizer: f64,
    pub margin: f64,
}
impl Prediction {
    pub fn posterior(scores: Vec<f64>) -> Self {
        let mut ranking: Vec<usize> = (0..scores.len()).collect();
        ranking.sort_by(|&a, &b| scores[b].total_cmp(&scores[a]).then(a.cmp(&b)));
        let label = ranking[0];
        let margin = scores[label] - scores[ranking[1]];
        let exponentials: Vec<f64> = scores.iter().map(|score| (score - scores[label]).exp()).collect();
        let mut normalizer = 0.0;
        for &value in &exponentials { normalizer += value; }
        let probabilities: Vec<f64> = exponentials.iter().map(|value| value / normalizer).collect();
        Self { label, score: probabilities[label], ranking, scores, probabilities, normalizer, margin }
    }
}
pub fn smoothed_log(count: i64, total: i64, alpha: i64, outcomes: usize) -> f64 {
    ((100 * count + alpha) as f64 / (100 * total + alpha * outcomes as i64) as f64).ln()
}
#[derive(Clone)]
pub struct NaiveBayes { pub kind: usize, pub priors: Vec<f64>, pub base: Vec<f64>, pub weights: Vec<Vec<f64>> }
impl NaiveBayes {
    pub fn train(kind: usize, counts: &TrainingCounts, alpha: i64) -> Self {
        let priors = counts.documents.iter().map(|&n| (n as f64 / counts.document_total as f64).ln()).collect();
        let mut base = vec![0.0; counts.class_count];
        let mut weights = vec![vec![0.0; counts.vocabulary_size]; counts.class_count];
        for label in 0..counts.class_count {
            for term in 0..counts.vocabulary_size {
                weights[label][term] = match kind {
                    0 => smoothed_log(counts.occurrences[label][term], counts.totals[label], alpha, counts.vocabulary_size),
                    1 => {
                        let present = smoothed_log(counts.containing[label][term], counts.documents[label], alpha, 2);
                        let absent = smoothed_log(counts.documents[label] - counts.containing[label][term], counts.documents[label], alpha, 2);
                        base[label] += absent;
                        present - absent
                    }
                    _ => -smoothed_log(counts.term_totals[term] - counts.occurrences[label][term], counts.total - counts.totals[label], alpha, counts.vocabulary_size),
                };
            }
        }
        Self { kind, priors, base, weights }
    }
    pub fn predict(&self, sequence: &[usize]) -> Prediction {
        let terms = if self.kind == 1 { first_occurrences(sequence) } else { sequence.to_vec() };
        let mut scores = Vec::new();
        for label in 0..self.priors.len() {
            let mut score = self.base[label];
            for &term in &terms { score += self.weights[label][term]; }
            scores.push(score + self.priors[label]);
        }
        Prediction::posterior(scores)
    }
}
