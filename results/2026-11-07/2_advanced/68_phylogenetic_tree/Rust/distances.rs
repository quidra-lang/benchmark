use crate::alignment::{self, Record};

#[derive(Clone, Copy)]
pub struct Counts { pub sites: usize, pub transitions: usize, pub transversions: usize }
pub fn tally(a: &[u8], b: &[u8], weights: &[usize]) -> Counts {
    let mut count = Counts { sites: 0, transitions: 0, transversions: 0 };
    for c in 0..a.len() {
        if !alignment::base(a[c]) || !alignment::base(b[c]) { continue; }
        count.sites += weights[c];
        if a[c] != b[c] {
            if matches!((a[c], b[c]), (b'A', b'G') | (b'G', b'A') | (b'C', b'T') | (b'T', b'C')) { count.transitions += weights[c]; }
            else { count.transversions += weights[c]; }
        }
    }
    count
}
pub fn corrected(count: Counts, model: &str, saturated_distance: f64) -> (f64, bool) {
    let (n, s, v) = (count.sites, count.transitions, count.transversions);
    let saturated = n == 0 || (model == "JC" && 4*(s+v) >= 3*n) || (model == "K2P" && (2*s+v >= n || 2*v >= n));
    if saturated { return (saturated_distance, true); }
    let (n, s, v) = (n as f64, s as f64, v as f64);
    let distance = match model { "P" => (s+v)/n, "JC" => -(3.0/4.0)*(1.0-4.0*(s+v)/(3.0*n)).ln(),
        _ => -(1.0/2.0)*(1.0-2.0*s/n-v/n).ln()-(1.0/4.0)*(1.0-2.0*v/n).ln() };
    (distance, false)
}
pub fn matrix(records: &[Record], weights: &[usize], model: &str, saturated: f64) -> Vec<Vec<f64>> {
    let n = records.len(); let mut matrix = vec![vec![0.0; n]; n];
    for i in 0..n { for j in i+1..n {
        let value = corrected(tally(&records[i].sequence, &records[j].sequence, weights), model, saturated).0;
        matrix[i][j] = value; matrix[j][i] = value;
    } }
    matrix
}
