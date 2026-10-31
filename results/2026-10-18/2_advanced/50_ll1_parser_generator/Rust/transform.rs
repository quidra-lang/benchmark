use crate::grammar_parser::{Grammar, nonterminal, notation};
use std::collections::{BTreeSet, VecDeque};

fn fresh(grammar: &Grammar, name: &str) -> String {
    let mut result = name.to_owned();
    loop {
        result.insert(result.len() - 1, '\'');
        if !grammar.rules.contains_key(&result) { return result; }
    }
}

fn reaches(grammar: &Grammar, start: &str, target: &str) -> bool {
    let mut queue = VecDeque::from([start.to_owned()]);
    let mut seen = BTreeSet::from([start.to_owned()]);
    while let Some(name) = queue.pop_front() {
        for rhs in &grammar.rules[&name] {
            if let Some(first) = rhs.first() {
                if first == target { return true; }
                if nonterminal(first) && seen.insert(first.clone()) { queue.push_back(first.clone()); }
            }
        }
    }
    false
}

pub fn eliminate(grammar: &Grammar) -> (Grammar, Vec<String>) {
    let mut result = grammar.clone();
    let mut log = Vec::new();
    for (i, a) in grammar.order.iter().enumerate() {
        for b in &grammar.order[..i] {
            if result.rules[a].iter().any(|r| r.first() == Some(b)) && reaches(&result, b, a) {
                let mut replacements = Vec::new();
                for rhs in &result.rules[a] {
                    if rhs.first() == Some(b) {
                        for delta in &result.rules[b] {
                            let mut alternative = delta.clone();
                            alternative.extend(rhs[1..].iter().cloned());
                            if !replacements.contains(&alternative) { replacements.push(alternative); }
                        }
                    } else if !replacements.contains(rhs) { replacements.push(rhs.clone()); }
                }
                result.rules.insert(a.clone(), replacements);
                log.push(format!("substitute {} into {}", b, a));
            }
        }
        let mut alternatives = result.rules[a].clone();
        if alternatives.iter().any(|r| r.len() == 1 && r[0] == *a) {
            alternatives.retain(|r| !(r.len() == 1 && r[0] == *a));
            log.push(format!("remove cycle {} -> {}", a, a));
        }
        if alternatives.iter().any(|r| r.first() == Some(a)) {
            let new = fresh(&result, a);
            let mut ordinary = Vec::new();
            let mut recursive = Vec::new();
            for rhs in alternatives {
                if rhs.first() == Some(a) {
                    let mut suffix = rhs[1..].to_vec();
                    suffix.push(new.clone());
                    recursive.push(suffix);
                } else {
                    let mut rhs = rhs;
                    rhs.push(new.clone());
                    ordinary.push(rhs);
                }
            }
            recursive.push(Vec::new());
            result.rules.insert(a.clone(), ordinary);
            result.rules.insert(new.clone(), recursive);
            let position = result.order.iter().position(|x| x == a).unwrap();
            result.order.insert(position + 1, new.clone());
            log.push(format!("eliminate left recursion in {} with {}", a, new));
        } else { result.rules.insert(a.clone(), alternatives); }
    }
    (result, log)
}

pub fn factor(grammar: &Grammar) -> (Grammar, Vec<String>) {
    let mut result = grammar.clone();
    let mut log = Vec::new();
    let mut i = 0;
    while i < result.order.len() {
        let a = result.order[i].clone();
        let original = result.rules[&a].clone();
        let mut alternatives = Vec::new();
        let mut grouped = BTreeSet::new();
        let mut created = Vec::new();
        for rhs in &original {
            if rhs.is_empty() { alternatives.push(rhs.clone()); continue; }
            if !grouped.insert(rhs[0].clone()) { continue; }
            let group: Vec<&Vec<String>> = original.iter().filter(|r| r.first() == rhs.first()).collect();
            if group.len() == 1 { alternatives.push(rhs.clone()); continue; }
            let mut length = rhs.len();
            for other in &group { length = length.min(rhs.iter().zip(other.iter()).take_while(|(x, y)| x == y).count()); }
            let new = fresh(&result, &a);
            let mut prefix = rhs[..length].to_vec();
            prefix.push(new.clone());
            alternatives.push(prefix);
            result.rules.insert(new.clone(), group.iter().map(|r| r[length..].to_vec()).collect());
            created.push(new.clone());
            log.push(format!("left factor {} on {} with {}", a, notation(&rhs[..length]), new));
        }
        result.rules.insert(a, alternatives);
        result.order.splice(i + 1..i + 1, created);
        i += 1;
    }
    (result, log)
}
