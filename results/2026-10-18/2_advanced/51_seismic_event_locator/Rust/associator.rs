use crate::picker::Pick;
use std::collections::BTreeSet;

pub fn associate(picks: &[Pick], window: i64, minimum: usize) -> Vec<Vec<usize>> {
    let mut assigned = vec![false; picks.len()];
    let mut candidates = Vec::new();
    for p in 0..picks.len() {
        if assigned[p] { continue; }
        let mut stations = BTreeSet::new();
        let mut selected = Vec::new();
        for q in p..picks.len() {
            if picks[q].sample > picks[p].sample + window { break; }
            if !assigned[q] && stations.insert(picks[q].station) { selected.push(q); }
        }
        if selected.len() >= minimum {
            for &q in &selected { assigned[q] = true; }
            candidates.push(selected);
        }
    }
    candidates
}
