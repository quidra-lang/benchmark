use crate::Formula;
use std::collections::BTreeSet;

pub struct Simplified {
    pub clauses: Vec<Vec<i64>>,
    pub fixed: Vec<i8>,
    pub counts: [usize; 7],
    pub removed: [Vec<usize>; 4],
    pub conflict: Option<usize>,
    pub pure: bool,
}

impl Simplified {
    pub fn removed_count(&self) -> usize { self.counts[0] + self.counts[3] + self.counts[4] + self.counts[6] }
    pub fn active(&self) -> Vec<usize> { (1..self.fixed.len()).filter(|&x| self.fixed[x] == 0).collect() }
}

pub fn simplify(formula: &Formula, pure: bool) -> Simplified {
    let mut result = Simplified { clauses: Vec::new(), fixed: vec![0; formula.variables + 1], counts: [0; 7], removed: std::array::from_fn(|_| Vec::new()), conflict: None, pure };
    let mut working: Vec<(usize, Vec<i64>)> = Vec::new();
    for (index, clause) in formula.clauses.iter().enumerate() {
        let literals: BTreeSet<_> = clause.iter().copied().collect();
        if literals.iter().any(|literal| literals.contains(&-literal)) {
            result.counts[0] += 1;
            result.removed[0].push(index + 1);
        } else {
            let mut seen = BTreeSet::new();
            let normalized: Vec<_> = clause.iter().copied().filter(|literal| seen.insert(*literal)).collect();
            result.counts[1] += clause.len() - normalized.len();
            working.push((index + 1, normalized));
        }
    }
    loop {
        if let Some((number, _)) = working.iter().find(|(_, clause)| clause.is_empty()) { result.conflict = Some(*number); break; }
        let literal = working.iter().find(|(_, clause)| clause.len() == 1).map(|(_, clause)| clause[0]);
        let Some(literal) = literal else { break; };
        result.fixed[literal.unsigned_abs() as usize] = if literal > 0 { 1 } else { -1 };
        result.counts[2] += 1;
        working.retain_mut(|(number, clause)| {
            if clause.contains(&literal) {
                result.counts[3] += 1;
                result.removed[1].push(*number);
                false
            } else { clause.retain(|&l| l != -literal); true }
        });
    }
    if result.conflict.is_none() {
        let removed: Vec<_> = working.iter().enumerate().map(|(b, (_, clause_b))| {
            working.iter().enumerate().any(|(a, (_, clause_a))| a != b && (clause_a.len() < clause_b.len() || a < b) && clause_a.iter().all(|literal| clause_b.contains(literal)))
        }).collect();
        working = working.into_iter().enumerate().filter_map(|(i, (number, clause))| {
            if removed[i] { result.counts[4] += 1; result.removed[2].push(number); None } else { Some((number, clause)) }
        }).collect();
        if pure {
            loop {
                let literals: BTreeSet<_> = working.iter().flat_map(|(_, clause)| clause.iter().copied()).collect();
                let pure: BTreeSet<_> = literals.iter().copied().filter(|literal| !literals.contains(&-literal)).collect();
                if pure.is_empty() { break; }
                for &literal in &pure { result.fixed[literal.unsigned_abs() as usize] = if literal > 0 { 1 } else { -1 }; }
                result.counts[5] += pure.len();
                working.retain(|(number, clause)| {
                    if clause.iter().any(|literal| pure.contains(literal)) {
                        result.counts[6] += 1;
                        result.removed[3].push(*number);
                        false
                    } else { true }
                });
            }
        }
    }
    result.clauses = working.into_iter().map(|(_, clause)| clause).collect();
    for numbers in &mut result.removed { numbers.sort_unstable(); }
    result
}
