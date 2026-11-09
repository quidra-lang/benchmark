use std::collections::{BTreeMap, HashMap, HashSet};

pub fn first_occurrences(sequence: &[usize]) -> Vec<usize> {
    let mut seen = HashSet::new();
    sequence.iter().copied().filter(|term| seen.insert(*term)).collect()
}
pub struct RankedTerm { pub term: String, pub frequency: i64, pub score: f64, pub best_class: usize }
pub struct Vocabulary {
    pub term_count: usize,
    pub candidate_count: usize,
    pub ranking: Vec<RankedTerm>,
    pub terms: Vec<String>,
    pub index: HashMap<String, usize>,
    pub frequencies: Vec<i64>,
}
impl Vocabulary {
    pub fn new(sequences: &[&[String]], labels: &[usize], class_count: usize, min_df: i64, size: usize) -> Self {
        let mut counts = BTreeMap::<String, Vec<i64>>::new();
        let mut class_sizes = vec![0i64; class_count];
        for (sequence, &label) in sequences.iter().zip(labels) {
            class_sizes[label] += 1;
            for term in sequence.iter().collect::<HashSet<_>>() {
                counts.entry(term.to_string()).or_insert_with(|| vec![0; class_count])[label] += 1;
            }
        }
        let term_count = counts.len();
        let total = sequences.len() as i64;
        let mut ranking = Vec::new();
        for (term, row) in counts {
            let frequency: i64 = row.iter().sum();
            if frequency < min_df { continue; }
            let mut best_class = 0;
            let mut best_score = -1.0;
            for label in 0..class_count {
                let a = row[label];
                let b = frequency - a;
                let c = class_sizes[label] - a;
                let e = total - class_sizes[label] - b;
                let difference = a * e - b * c;
                let numerator = total * difference * difference;
                let denominator = frequency * (total - frequency) * class_sizes[label] * (total - class_sizes[label]);
                let score = if denominator == 0 { 0.0 } else { numerator as f64 / denominator as f64 };
                if score > best_score { best_score = score; best_class = label; }
            }
            ranking.push(RankedTerm { term, frequency, score: best_score, best_class });
        }
        let candidate_count = ranking.len();
        ranking.sort_by(|a, b| b.score.total_cmp(&a.score).then_with(|| a.term.cmp(&b.term)));
        if size > 0 && ranking.len() > size { ranking.truncate(size); }
        let mut terms: Vec<String> = ranking.iter().map(|entry| entry.term.clone()).collect();
        terms.sort();
        let index: HashMap<String, usize> = terms.iter().enumerate().map(|(i, term)| (term.clone(), i)).collect();
        let mut frequencies = vec![0; terms.len()];
        for entry in &ranking { frequencies[index[&entry.term]] = entry.frequency; }
        Self { term_count, candidate_count, ranking, terms, index, frequencies }
    }
    pub fn size(&self) -> usize { self.terms.len() }
    pub fn encode(&self, sequence: &[String]) -> Vec<usize> { sequence.iter().filter_map(|term| self.index.get(term).copied()).collect() }
}
