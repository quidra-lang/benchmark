use std::collections::BTreeSet;
use std::rc::Rc;
use crate::dataset::{Attribute, Row};
use crate::evaluation::PrunedTree;
use crate::impurity::Fraction;
use crate::tree_builder::Tree;

pub struct Decision { pub node: usize, pub rows: usize, pub leaf_error: i64, pub subtree_error: i64, pub pruned: bool }
pub struct SequenceTree { pub alpha: Fraction, pub tree: PrunedTree }

fn decide(index: usize, tree: &Tree, reached: &[Vec<usize>], rows: &[Row], decisions: &mut Vec<Decision>, cut: &mut BTreeSet<usize>) -> i64 {
    let node = &tree.nodes[index];
    let leaf_error = reached[index].iter().filter(|&&row| rows[row].label != node.prediction).count() as i64;
    let Some([left, right]) = node.children else { return leaf_error; };
    let subtree_error = decide(left, tree, reached, rows, decisions, cut) + decide(right, tree, reached, rows, decisions, cut);
    let pruned = leaf_error <= subtree_error;
    decisions.push(Decision { node: index, rows: reached[index].len(), leaf_error, subtree_error, pruned });
    if pruned { cut.insert(index); leaf_error } else { subtree_error }
}

pub fn reduced_error_pruning(tree: Rc<Tree>, rows: &[Row], attributes: &[Attribute]) -> (PrunedTree, Vec<Decision>) {
    let mut pruned = PrunedTree::new(tree);
    let mut reached = vec![Vec::new(); pruned.tree.nodes.len()];
    for (index, row) in rows.iter().enumerate() { for node in pruned.route(row, attributes).path { reached[node].push(index); } }
    let mut decisions = Vec::new();
    decide(0, &pruned.tree, &reached, rows, &mut decisions, &mut pruned.cut);
    (pruned, decisions)
}

pub fn cost_complexity_sequence(root: Rc<Tree>) -> Vec<SequenceTree> {
    let mut tree = PrunedTree::new(root);
    let mut sequence = vec![SequenceTree { alpha: Fraction { numerator: 0, denominator: 1 }, tree: tree.clone() }];
    while !tree.is_leaf(0) {
        let mut alpha: Option<Fraction> = None;
        let mut weakest = BTreeSet::new();
        for index in tree.internal_nodes() {
            let leaves = tree.leaves(index);
            let errors: i64 = leaves.iter().map(|&leaf| tree.tree.nodes[leaf].errors).sum();
            let strength = Fraction { numerator: tree.tree.nodes[index].errors - errors, denominator: leaves.len() as i64 - 1 };
            if alpha.is_none_or(|value| strength.compare(value).is_lt()) { alpha = Some(strength); weakest.clear(); weakest.insert(index); }
            else if strength.compare(alpha.unwrap()).is_eq() { weakest.insert(index); }
        }
        tree.cut.extend(weakest);
        sequence.push(SequenceTree { alpha: alpha.unwrap(), tree: tree.clone() });
    }
    sequence
}
