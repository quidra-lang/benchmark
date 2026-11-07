use crate::{grammar_parser::{Grammar, nonterminal}, first_follow::Sets};
use std::collections::{BTreeMap, BTreeSet};

pub struct Production {
    pub lhs: String,
    pub rhs: Vec<String>,
}

pub struct Table {
    pub productions: Vec<Production>,
    pub reasons: Vec<BTreeMap<String, bool>>,
    pub cells: BTreeMap<(String, String), Vec<usize>>,
    pub terminals: Vec<String>,
}

impl Table {
    pub fn build(grammar: &Grammar, sets: &Sets) -> Self {
        let productions: Vec<Production> = grammar.order.iter().flat_map(|a| grammar.rules[a].iter().map(move |rhs| Production { lhs: a.clone(), rhs: rhs.clone() })).collect();
        let terminals: Vec<String> = productions.iter().flat_map(|p| p.rhs.iter().filter(|s| !nonterminal(s)).cloned()).collect::<BTreeSet<_>>().into_iter().collect();
        let mut reasons = Vec::new();
        let mut cells: BTreeMap<(String, String), Vec<usize>> = BTreeMap::new();
        for (i, p) in productions.iter().enumerate() {
            let (first, nullable) = sets.sequence(&p.rhs);
            let mut why: BTreeMap<String, bool> = first.into_iter().map(|t| (t, true)).collect();
            if nullable { for t in &sets.follow[&p.lhs] { why.entry(t.clone()).or_insert(false); } }
            for t in why.keys() { cells.entry((p.lhs.clone(), t.clone())).or_default().push(i); }
            reasons.push(why);
        }
        Self { productions, reasons, cells, terminals }
    }

    pub fn chosen(&self, lhs: &str, terminal: &str) -> Option<usize> {
        self.cells.get(&(lhs.into(), terminal.into())).map(|cell| *cell.iter().find(|&&p| self.reasons[p][terminal]).unwrap_or(&cell[0]))
    }

    pub fn conflicts(&self) -> usize {
        self.cells.values().filter(|v| v.len() > 1).count()
    }

    pub fn conflict_kind(&self, terminal: &str, cell: &[usize]) -> &'static str {
        let first = cell.iter().filter(|&&p| self.reasons[p][terminal]).count();
        if first == cell.len() { "FIRST/FIRST" } else if first == 0 { "FOLLOW/FOLLOW" } else { "FIRST/FOLLOW" }
    }
}
