pub fn combination(parents: &[usize], assignment: &[usize], cards: &[usize]) -> usize {
    parents.iter().fold(0, |row, &p| row*cards[p]+assignment[p])
}
pub fn counts(variable: usize, parents: &[usize], cards: &[usize], samples: &[Vec<usize>]) -> Vec<Vec<usize>> {
    let rows = parents.iter().map(|&p| cards[p]).product();
    let mut counts = vec![vec![0; cards[variable]]; rows];
    for sample in samples {
        counts[combination(parents, sample, cards)][sample[variable]] += 1;
    }
    counts
}
pub fn learned(counts: &[Vec<usize>], alpha: f64) -> Vec<Vec<f64>> {
    counts.iter().map(|row| {
        let total: f64 = row.iter().map(|&n| n as f64+alpha).sum();
        row.iter().map(|&n| (n as f64+alpha)/total).collect()
    }).collect()
}
pub fn log_likelihood(counts: &[Vec<usize>], cpt: &[Vec<f64>]) -> f64 {
    let mut ll = 0.0;
    for (r, row) in counts.iter().enumerate() {
        for (s, &count) in row.iter().enumerate() {
            if count > 0 {
                ll += count as f64*cpt[r][s].ln();
            }
        }
    }
    ll
}
pub fn parameters(variable: usize, parents: &[usize], cards: &[usize]) -> usize {
    (cards[variable]-1)*parents.iter().map(|&p| cards[p]).product::<usize>()
}
pub fn score(variable: usize, parents: &[usize], cards: &[usize], samples: &[Vec<usize>], alpha: f64) -> f64 {
    let mut parents = parents.to_vec();
    parents.sort_unstable();
    let counts = counts(variable, &parents, cards, samples);
    let cpt = learned(&counts, alpha);
    log_likelihood(&counts, &cpt)-parameters(variable, &parents, cards) as f64*(samples.len() as f64).ln()/2.0
}
