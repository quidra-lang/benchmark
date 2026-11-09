use std::collections::BTreeMap;
use crate::{alignment, tree_building::{Tree, Rooted}};

pub fn merge(a: u8, b: u8) -> (u8, usize) { if a&b != 0 { (a&b, 0) } else { (a|b, 1) } }
pub fn provisional(tree: &Tree, rooted: &Rooted, sequences: &[Vec<u8>], column: usize, outgroup: usize) -> (Vec<u8>, usize) {
    let mut sets = vec![0; tree.adjacency.len()]; let mut changes = 0;
    for &node in &rooted.postorder {
        if node < tree.taxa_count { sets[node] = alignment::base_set(sequences[node][column]).unwrap(); }
        else {
            let children: Vec<_> = rooted.children[node].iter().copied().filter(|&child| node != rooted.root || child != outgroup).collect();
            let (set, extra) = merge(sets[children[0]], sets[children[1]]); sets[node] = set; changes += extra;
        }
    }
    changes += merge(sets[rooted.root], sets[outgroup]).1;
    (sets, changes)
}
pub fn score(tree: &Tree, sequences: &[Vec<u8>], outgroup: usize, names: &[String]) -> usize {
    let rooted = tree.root(outgroup, names);
    (0..sequences[0].len()).map(|column| provisional(tree, &rooted, sequences, column, outgroup).1).sum()
}
pub fn branches(tree: &Tree, outgroup: usize, names: &[String], internal: bool) -> Vec<(u32, usize, usize)> {
    let rooted = tree.root(outgroup, names); let mut branches = Vec::new();
    for (child, parent) in rooted.parent.iter().enumerate() {
        if let Some(parent) = parent {
            if internal && (child < tree.taxa_count || *parent < tree.taxa_count) { continue; }
            branches.push((if child == outgroup { rooted.ingroup } else { rooted.masks[child] }, *parent, child));
        }
    }
    branches.sort_by_key(|b| b.0); branches
}
pub fn insert(tree: &Tree, edge: (usize, usize), taxon: usize) -> Tree {
    let mut result = tree.clone(); let node = result.node(); result.disconnect(edge.0, edge.1);
    result.connect(edge.0, node, 0.0); result.connect(node, edge.1, 0.0); result.connect(node, taxon, 0.0); result
}
pub fn nni(tree: &Tree, parent: usize, child: usize, swap: usize, outgroup: usize, names: &[String]) -> Tree {
    let rooted = tree.root(outgroup, names);
    let mut below = rooted.children[child].clone(); below.sort_by_key(|&node| rooted.masks[node]);
    let sibling = rooted.children[parent].iter().copied().find(|&node| node != child && node != outgroup).unwrap();
    let chosen = below[swap-1]; let mut result = tree.clone();
    result.disconnect(parent, sibling); result.disconnect(child, chosen);
    result.connect(parent, chosen, 0.0); result.connect(child, sibling, 0.0); result
}

pub fn reconstruct(tree: &mut Tree, sequences: &[Vec<u8>], outgroup: usize, names: &[String]) -> (BTreeMap<u32, String>, BTreeMap<u32, usize>, Vec<usize>) {
    let rooted = tree.root(outgroup, names); let n = tree.adjacency.len();
    let mut ancestors = BTreeMap::<u32, String>::new();
    let mut branch_changes = BTreeMap::<u32, usize>::new(); let mut counts = Vec::new();
    let mut changes = vec![0; n];
    let first = |set: u8| 1u8<<set.trailing_zeros();
    for column in 0..sequences[0].len() {
        let (sets, count) = provisional(tree, &rooted, sequences, column, outgroup); counts.push(count);
        let common = first(merge(sets[rooted.root], sets[outgroup]).0);
        let mut states = vec![0; n];
        states[rooted.root] = if common&sets[rooted.root] != 0 { common } else { first(sets[rooted.root]) };
        states[outgroup] = if common&sets[outgroup] != 0 { common } else { first(sets[outgroup]) };
        let mut stack = vec![rooted.root];
        while let Some(parent) = stack.pop() {
            for &child in &rooted.children[parent] {
                if child != outgroup { states[child] = if states[parent]&sets[child] != 0 { states[parent] } else { first(sets[child]) }; }
                changes[child] += usize::from(states[parent] != states[child]); stack.push(child);
            }
        }
        for node in tree.taxa_count..n {
            if tree.adjacency[node].is_empty() { continue; }
            ancestors.entry(rooted.masks[node]).or_default().push(b"ACGT"[states[node].trailing_zeros() as usize] as char);
        }
    }
    for (mask, parent, child) in branches(tree, outgroup, names, false) {
        branch_changes.insert(mask, changes[child]); tree.connect(parent, child, changes[child] as f64/sequences[0].len() as f64);
    }
    (ancestors, branch_changes, counts)
}
