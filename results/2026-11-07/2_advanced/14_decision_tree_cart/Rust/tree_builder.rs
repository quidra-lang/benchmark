use std::collections::BTreeSet;
use std::rc::Rc;
use crate::dataset::{Attribute, Row, Settings};
use crate::impurity::{Fraction, class_counts, error_count, evaluation_value, improves, majority};

pub fn half_text(value: i64) -> String { format!("{}.{}", value / 2, 5 * (value % 2)) }

#[derive(Clone, Copy)]
pub struct Split { pub attribute: usize, pub point: i64 }
impl Split {
    pub fn goes_left(self, value: i64, attributes: &[Attribute]) -> bool {
        if attributes[self.attribute].integer { 2 * value <= self.point } else { value == self.point }
    }
    pub fn condition(self, left: bool, attributes: &[Attribute]) -> String {
        let attribute = &attributes[self.attribute];
        if attribute.integer {
            format!("{} {} {}", attribute.name, if left { "<=" } else { ">" }, half_text(self.point))
        } else {
            format!("{} {} {}", attribute.name, if left { "=" } else { "!=" }, attribute.values[self.point as usize])
        }
    }
}

#[derive(Clone)]
pub struct Surrogate { pub split: Split, pub forward: bool, pub score: i64 }
pub struct Candidate { pub split: Split, pub left: Vec<i64>, pub right: Vec<i64> }
impl Candidate {
    pub fn value(&self) -> Fraction { evaluation_value(&self.left, &self.right) }
    pub fn left_size(&self) -> i64 { self.left.iter().sum() }
    pub fn right_size(&self) -> i64 { self.right.iter().sum() }
}

pub struct Node {
    pub number: usize,
    pub depth: usize,
    pub counts: Vec<i64>,
    pub size: i64,
    pub prediction: usize,
    pub errors: i64,
    pub split: Option<Split>,
    pub surrogates: Vec<Surrogate>,
    pub default_left: bool,
    pub children: Option<[usize; 2]>,
}
pub struct Tree { pub nodes: Vec<Node> }

pub fn candidates(attribute: usize, attributes: &[Attribute], rows: &[Row], labels: &[usize], classes: usize) -> Vec<Candidate> {
    let values: BTreeSet<_> = rows.iter().map(|row| row.values[attribute].unwrap()).collect();
    if values.len() < 2 { return Vec::new(); }
    let ordered: Vec<_> = values.into_iter().collect();
    let points = if attributes[attribute].integer {
        ordered.windows(2).map(|pair| pair[0] + pair[1]).collect::<Vec<_>>()
    } else { ordered };
    let mut result = Vec::new();
    for point in points {
        let split = Split { attribute, point };
        let mut left = vec![0; classes];
        let mut right = vec![0; classes];
        for (row, &label) in rows.iter().zip(labels) {
            if split.goes_left(row.values[attribute].unwrap(), attributes) { left[label] += 1; }
            else { right[label] += 1; }
        }
        result.push(Candidate { split, left, right });
    }
    result
}

pub struct TreeBuilder<'a> { pub attributes: &'a [Attribute], pub classes: usize, pub settings: &'a Settings }
impl TreeBuilder<'_> {
    pub fn best_split(&self, rows: &[Row], attributes: &[usize]) -> Option<Candidate> {
        let labels: Vec<_> = rows.iter().map(|row| row.label).collect();
        let mut best: Option<Candidate> = None;
        for &attribute in attributes {
            for candidate in candidates(attribute, self.attributes, rows, &labels, self.classes) {
                if candidate.left_size() < self.settings.min_leaf as i64 || candidate.right_size() < self.settings.min_leaf as i64 { continue; }
                if best.as_ref().is_none_or(|current| candidate.value().compare(current.value()).is_gt()) { best = Some(candidate); }
            }
        }
        best
    }

    fn surrogates(&self, rows: &[Row], primary: Split) -> Vec<Surrogate> {
        let labels: Vec<_> = rows.iter().map(|row| if primary.goes_left(row.values[primary.attribute].unwrap(), self.attributes) { 0 } else { 1 }).collect();
        let left = labels.iter().filter(|&&label| label == 0).count() as i64;
        let size = rows.len() as i64;
        let baseline = left.max(size - left);
        let mut selected = Vec::new();
        for attribute in 0..self.attributes.len() {
            if attribute == primary.attribute { continue; }
            let mut best: Option<Surrogate> = None;
            for candidate in candidates(attribute, self.attributes, rows, &labels, 2) {
                let agreement = candidate.left[0] + candidate.right[1];
                let forward = agreement >= size - agreement;
                let score = agreement.max(size - agreement);
                if best.as_ref().is_none_or(|current| score > current.score) {
                    best = Some(Surrogate { split: candidate.split, forward, score });
                }
            }
            if let Some(best) = best { if best.score > baseline { selected.push(best); } }
        }
        selected.sort_by_key(|surrogate| (std::cmp::Reverse(surrogate.score), surrogate.split.attribute));
        selected.truncate(self.settings.max_surrogates);
        selected
    }

    pub fn grow(&self, rows: &[Row]) -> Rc<Tree> {
        let mut tree = Tree { nodes: Vec::new() };
        self.grow_node(rows, 1, 0, &mut tree);
        Rc::new(tree)
    }

    fn grow_node(&self, rows: &[Row], number: usize, depth: usize, tree: &mut Tree) -> usize {
        let counts = class_counts(rows, self.classes);
        let prediction = majority(&counts);
        let index = tree.nodes.len();
        let pure = counts[prediction] == rows.len() as i64;
        let errors = error_count(&counts);
        tree.nodes.push(Node { number, depth, counts, size: rows.len() as i64, prediction, errors,
            split: None, surrogates: Vec::new(), default_left: true, children: None });
        if pure || depth == self.settings.max_depth || rows.len() < self.settings.min_split { return index; }
        let attributes: Vec<_> = (0..self.attributes.len()).collect();
        let Some(best) = self.best_split(rows, &attributes) else { return index; };
        if !improves(best.value(), &tree.nodes[index].counts) { return index; }
        let split = best.split;
        let (left, right): (Vec<_>, Vec<_>) = rows.iter().cloned().partition(|row| split.goes_left(row.values[split.attribute].unwrap(), self.attributes));
        tree.nodes[index].split = Some(split);
        tree.nodes[index].surrogates = self.surrogates(rows, split);
        tree.nodes[index].default_left = left.len() >= right.len();
        let left_child = self.grow_node(&left, number * 2, depth + 1, tree);
        let right_child = self.grow_node(&right, number * 2 + 1, depth + 1, tree);
        tree.nodes[index].children = Some([left_child, right_child]);
        index
    }
}
