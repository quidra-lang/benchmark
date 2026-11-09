use crate::grammar_parser::{Grammar, nonterminal};
use std::collections::{BTreeMap, BTreeSet};

pub struct Sets {
    pub nullable: BTreeSet<String>,
    pub first: BTreeMap<String, BTreeSet<String>>,
    pub follow: BTreeMap<String, BTreeSet<String>>,
    pub passes: [usize; 3],
}

impl Sets {
    pub fn sequence(&self, symbols: &[String]) -> (BTreeSet<String>, bool) {
        let mut result = BTreeSet::new();
        for symbol in symbols {
            if !nonterminal(symbol) { result.insert(symbol.clone()); return (result, false); }
            result.extend(self.first[symbol].iter().cloned());
            if !self.nullable.contains(symbol) { return (result, false); }
        }
        (result, true)
    }
}

pub fn compute(grammar: &Grammar) -> Sets {
    let empty: BTreeMap<String, BTreeSet<String>> = grammar.order.iter().map(|a| (a.clone(), BTreeSet::new())).collect();
    let mut sets = Sets { nullable: BTreeSet::new(), first: empty.clone(), follow: empty, passes: [0; 3] };
    loop {
        sets.passes[0] += 1;
        let mut changed = false;
        for a in &grammar.order {
            if !sets.nullable.contains(a) && grammar.rules[a].iter().any(|r| r.iter().all(|s| nonterminal(s) && sets.nullable.contains(s))) {
                sets.nullable.insert(a.clone());
                changed = true;
            }
        }
        if !changed { break; }
    }
    loop {
        sets.passes[1] += 1;
        let mut changed = false;
        for a in &grammar.order {
            for rhs in &grammar.rules[a] {
                let values = sets.sequence(rhs).0;
                let target = sets.first.get_mut(a).unwrap();
                for value in values { changed |= target.insert(value); }
            }
        }
        if !changed { break; }
    }
    sets.follow.get_mut(&grammar.start).unwrap().insert("$".into());
    loop {
        sets.passes[2] += 1;
        let mut changed = false;
        for a in &grammar.order {
            for rhs in &grammar.rules[a] {
                for (k, symbol) in rhs.iter().enumerate() {
                    if nonterminal(symbol) {
                        let (mut values, nullable) = sets.sequence(&rhs[k + 1..]);
                        if nullable { values.extend(sets.follow[a].iter().cloned()); }
                        let target = sets.follow.get_mut(symbol).unwrap();
                        for value in values { changed |= target.insert(value); }
                    }
                }
            }
        }
        if !changed { break; }
    }
    sets
}
