use crate::naive_bayes::Prediction;

fn length(vector: &[f64]) -> f64 {
    let mut total = 0.0;
    for &value in vector { total += value * value; }
    total.sqrt()
}
pub struct Rocchio { idf: Vec<f64>, centroids: Vec<Vec<f64>>, lengths: Vec<f64> }
impl Rocchio {
    pub fn new(sequences: &[Vec<usize>], labels: &[usize], class_count: usize, frequencies: &[i64]) -> Self {
        let idf: Vec<f64> = frequencies.iter().map(|&frequency| (sequences.len() as f64 / frequency as f64).ln()).collect();
        let mut result = Self { idf, centroids: vec![vec![0.0; frequencies.len()]; class_count], lengths: Vec::new() };
        let mut documents = vec![0; class_count];
        for (sequence, &label) in sequences.iter().zip(labels) {
            documents[label] += 1;
            let vector = result.vector(sequence);
            let norm = length(&vector);
            if norm > 0.0 { for (term, value) in vector.iter().enumerate() { result.centroids[label][term] += value / norm; } }
        }
        for label in 0..class_count { for value in &mut result.centroids[label] { *value /= documents[label] as f64; } }
        result.lengths = result.centroids.iter().map(|row| length(row)).collect();
        result
    }
    fn vector(&self, sequence: &[usize]) -> Vec<f64> {
        let mut frequencies = vec![0i64; self.idf.len()];
        for &term in sequence { frequencies[term] += 1; }
        frequencies.iter().zip(&self.idf).map(|(&count, &idf)| count as f64 * idf).collect()
    }
    pub fn predict(&self, sequence: &[usize]) -> Prediction {
        let vector = self.vector(sequence);
        let norm = length(&vector);
        let mut similarities = Vec::new();
        for (centroid, &centroid_norm) in self.centroids.iter().zip(&self.lengths) {
            let mut product = 0.0;
            if norm > 0.0 && centroid_norm > 0.0 {
                for (value, center) in vector.iter().zip(centroid) { product += value * center; }
                similarities.push(product / (norm * centroid_norm));
            } else { similarities.push(0.0); }
        }
        let mut ranking: Vec<usize> = (0..similarities.len()).collect();
        ranking.sort_by(|&a, &b| similarities[b].total_cmp(&similarities[a]).then(a.cmp(&b)));
        let label = ranking[0];
        Prediction { label, score: similarities[label], ranking, scores: similarities, probabilities: Vec::new(), normalizer: 0.0, margin: 0.0 }
    }
}
