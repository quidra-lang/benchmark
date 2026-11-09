use std::collections::{BTreeMap, HashSet};

pub type Groups = BTreeMap<String, HashSet<String>>;

pub fn wildcard(element: &str) -> bool { matches!(element, "*" | "#") || element.starts_with('@') }

fn fits(element: &str, word: &str, groups: &Groups) -> bool {
    if element == "#" { true }
    else if let Some(group) = element.strip_prefix('@') { groups.get(group).is_some_and(|members| members.contains(word)) }
    else { element == word }
}

pub fn match_pattern(pattern: &[String], words: &[String], groups: &Groups) -> Option<Vec<Vec<String>>> {
    fn search(pattern: &[String], words: &[String], groups: &Groups, position: usize, start: usize, bindings: &mut Vec<Vec<String>>) -> bool {
        if position == pattern.len() { return start == words.len(); }
        let element = &pattern[position];
        let ends: Vec<usize> = if element == "*" { (start..=words.len()).collect() }
            else if start < words.len() && fits(element, &words[start], groups) { vec![start + 1] }
            else { Vec::new() };
        for end in ends {
            if wildcard(element) { bindings.push(words[start..end].to_vec()); }
            if search(pattern, words, groups, position + 1, end, bindings) { return true; }
            if wildcard(element) { bindings.pop(); }
        }
        false
    }
    let mut bindings = Vec::new();
    search(pattern, words, groups, 0, 0, &mut bindings).then_some(bindings)
}

pub fn pattern_covers(earlier: &[String], later: &[String], groups: &Groups) -> bool {
    fn covers(element: &str, other: &str, groups: &Groups) -> bool {
        if element == "#" { other != "*" }
        else if let Some(group) = element.strip_prefix('@') {
            let members = &groups[group];
            if let Some(name) = other.strip_prefix('@') { groups[name].is_subset(members) }
            else { members.contains(other) }
        } else { element == other }
    }
    fn search(earlier: &[String], later: &[String], groups: &Groups, position: usize, start: usize) -> bool {
        if position == earlier.len() { return start == later.len(); }
        if earlier[position] == "*" {
            (start..=later.len()).any(|end| search(earlier, later, groups, position + 1, end))
        } else {
            start < later.len() && covers(&earlier[position], &later[start], groups) && search(earlier, later, groups, position + 1, start + 1)
        }
    }
    search(earlier, later, groups, 0, 0)
}
