#[derive(Clone, Default)]
pub struct Statistics {
    pub decisions: usize,
    pub propagations: usize,
    pub conflicts: usize,
    pub max_depth: usize,
}

impl Statistics {
    pub fn add(&mut self, other: &Self) {
        self.decisions += other.decisions;
        self.propagations += other.propagations;
        self.conflicts += other.conflicts;
        self.max_depth = self.max_depth.max(other.max_depth);
    }
}

pub struct Round {
    clauses: Vec<Vec<i64>>,
    watches: Vec<Vec<usize>>,
    values: Vec<i8>,
    trail: Vec<(i64, u8)>,
    propagation: usize,
    pub statistics: Statistics,
    pub events: Vec<String>,
}

fn index(literal: i64) -> usize { 2 * (literal.unsigned_abs() as usize - 1) + usize::from(literal < 0) }

impl Round {
    pub fn new(variables: usize, clauses: &[Vec<i64>]) -> Self {
        let mut round = Self { clauses: clauses.to_vec(), watches: vec![Vec::new(); variables * 2], values: vec![0; variables + 1], trail: Vec::new(), propagation: 0, statistics: Statistics::default(), events: Vec::new() };
        for (number, clause) in clauses.iter().enumerate().filter(|(_, clause)| clause.len() >= 2) {
            round.watches[index(clause[0])].push(number);
            round.watches[index(clause[1])].push(number);
        }
        round
    }

    fn value(&self, literal: i64) -> i8 {
        let value = self.values[literal.unsigned_abs() as usize];
        if literal > 0 { value } else { -value }
    }

    fn assign(&mut self, literal: i64, kind: u8) {
        self.values[literal.unsigned_abs() as usize] = if literal > 0 { 1 } else { -1 };
        self.trail.push((literal, kind));
        self.events.push(format!("{}{literal}", kind as char));
        if kind == b'P' { self.statistics.propagations += 1; }
        if kind == b'D' {
            self.statistics.decisions += 1;
            let depth = self.trail.iter().filter(|(_, kind)| *kind != b'P').count();
            self.statistics.max_depth = self.statistics.max_depth.max(depth);
        }
    }

    fn conflict(&mut self) {
        self.statistics.conflicts += 1;
        self.events.push("C".into());
    }

    fn propagate(&mut self) -> bool {
        while self.propagation < self.trail.len() {
            let false_literal = -self.trail[self.propagation].0;
            self.propagation += 1;
            let list = index(false_literal);
            let mut position = 0;
            while position < self.watches[list].len() {
                let clause_index = self.watches[list][position];
                if self.clauses[clause_index][0] == false_literal { self.clauses[clause_index].swap(0, 1); }
                let first = self.clauses[clause_index][0];
                if self.value(first) == 1 { position += 1; continue; }
                let replacement = (2..self.clauses[clause_index].len()).find(|&i| self.value(self.clauses[clause_index][i]) != -1);
                if let Some(replacement) = replacement {
                    self.clauses[clause_index].swap(1, replacement);
                    let new_literal = self.clauses[clause_index][1];
                    self.watches[list].remove(position);
                    self.watches[index(new_literal)].push(clause_index);
                } else {
                    if self.value(first) == -1 { self.conflict(); return false; }
                    self.assign(first, b'P');
                    position += 1;
                }
            }
        }
        true
    }

    fn decision(&self) -> Option<i64> {
        let mut counts = vec![0_usize; self.watches.len()];
        for clause in &self.clauses {
            if clause.iter().any(|&literal| self.value(literal) == 1) { continue; }
            for &literal in clause { if self.value(literal) == 0 { counts[index(literal)] += 1; } }
        }
        let mut best = None;
        for variable in 1..self.values.len() {
            for literal in [variable as i64, -(variable as i64)] {
                if counts[index(literal)] > best.map_or(0, |literal| counts[index(literal)]) { best = Some(literal); }
            }
        }
        best
    }

    fn backtrack(&mut self) -> bool {
        while let Some((literal, kind)) = self.trail.pop() {
            self.values[literal.unsigned_abs() as usize] = 0;
            if kind == b'D' {
                self.propagation = self.trail.len();
                self.assign(-literal, b'F');
                return true;
            }
        }
        false
    }

    pub fn search(&mut self) -> Option<Vec<bool>> {
        for i in 0..self.clauses.len() {
            if self.clauses[i].is_empty() { self.conflict(); return None; }
            if self.clauses[i].len() == 1 {
                let literal = self.clauses[i][0];
                if self.value(literal) == -1 { self.conflict(); return None; }
                if self.value(literal) == 0 { self.assign(literal, b'P'); }
            }
        }
        loop {
            if !self.propagate() {
                if !self.backtrack() { return None; }
            } else if let Some(literal) = self.decision() { self.assign(literal, b'D'); }
            else { return Some(self.values.iter().map(|&value| value == 1).collect()); }
        }
    }
}
