use std::collections::BTreeSet;
use std::rc::Rc;
use crate::dataset::{Attribute, Row};
use crate::tree_builder::Tree;

pub fn real_text(value: f64, places: usize) -> String {
    let text = format!("{value:.places$}");
    if text.starts_with('-') && text[1..].chars().all(|c| c == '0' || c == '.') { text[1..].to_owned() } else { text }
}
pub fn ratio_text(numerator: i64, denominator: i64) -> String {
    if denominator == 0 { "0/0 -".to_owned() }
    else { format!("{numerator}/{denominator} {}", real_text(numerator as f64 / denominator as f64, 4)) }
}
pub fn fraction_text(mut numerator: i64, mut denominator: i64, places: usize) -> String {
    if denominator == 0 { return "- -".to_owned(); }
    let (mut a, mut b) = (numerator.abs(), denominator);
    while b != 0 { (a, b) = (b, a % b); }
    numerator /= a;
    denominator /= a;
    format!("{numerator}/{denominator} {}", real_text(numerator as f64 / denominator as f64, places))
}

#[derive(Clone, Copy, PartialEq)]
pub enum Method { Primary, Surrogate, Default }
impl Method {
    pub fn index(self) -> usize { match self { Self::Primary => 0, Self::Surrogate => 1, Self::Default => 2 } }
    pub fn mark(self) -> &'static str { match self { Self::Primary => "", Self::Surrogate => " [surrogate]", Self::Default => " [default]" } }
}
pub struct Route { pub path: Vec<usize>, pub methods: Vec<Method> }

#[derive(Clone)]
pub struct PrunedTree { pub tree: Rc<Tree>, pub cut: BTreeSet<usize> }
impl PrunedTree {
    pub fn new(tree: Rc<Tree>) -> Self { Self { tree, cut: BTreeSet::new() } }
    pub fn is_leaf(&self, index: usize) -> bool { self.tree.nodes[index].split.is_none() || self.cut.contains(&index) }
    pub fn preorder(&self, start: usize) -> Vec<usize> {
        let mut nodes = Vec::new();
        let mut pending = vec![start];
        while let Some(index) = pending.pop() {
            nodes.push(index);
            if !self.is_leaf(index) { let [left, right] = self.tree.nodes[index].children.unwrap(); pending.push(right); pending.push(left); }
        }
        nodes
    }
    pub fn leaves(&self, start: usize) -> Vec<usize> { self.preorder(start).into_iter().filter(|&i| self.is_leaf(i)).collect() }
    pub fn internal_nodes(&self) -> Vec<usize> { self.preorder(0).into_iter().filter(|&i| !self.is_leaf(i)).collect() }
    pub fn depth(&self) -> usize { self.leaves(0).iter().map(|&i| self.tree.nodes[i].depth).max().unwrap() }
    pub fn training_errors(&self) -> i64 { self.leaves(0).iter().map(|&i| self.tree.nodes[i].errors).sum() }
    pub fn route(&self, row: &Row, attributes: &[Attribute]) -> Route {
        let mut index = 0;
        let mut path = vec![index];
        let mut methods = Vec::new();
        while !self.is_leaf(index) {
            let node = &self.tree.nodes[index];
            let split = node.split.unwrap();
            let mut direction = (node.default_left, Method::Default);
            if let Some(value) = row.values[split.attribute] { direction = (split.goes_left(value, attributes), Method::Primary); }
            else {
                for surrogate in &node.surrogates {
                    if let Some(value) = row.values[surrogate.split.attribute] {
                        direction = (surrogate.split.goes_left(value, attributes) == surrogate.forward, Method::Surrogate);
                        break;
                    }
                }
            }
            index = node.children.unwrap()[if direction.0 { 0 } else { 1 }];
            path.push(index);
            methods.push(direction.1);
        }
        Route { path, methods }
    }
    pub fn leaf_of(&self, row: &Row, attributes: &[Attribute]) -> usize { *self.route(row, attributes).path.last().unwrap() }
    pub fn predict(&self, row: &Row, attributes: &[Attribute]) -> usize { self.tree.nodes[self.leaf_of(row, attributes)].prediction }
    pub fn correct_count(&self, rows: &[Row], attributes: &[Attribute]) -> i64 { rows.iter().filter(|row| self.predict(row, attributes) == row.label).count() as i64 }
    pub fn limited(&self, depth: usize) -> Self {
        let cut = self.internal_nodes().into_iter().filter(|&i| self.tree.nodes[i].depth == depth).collect();
        Self { tree: self.tree.clone(), cut }
    }
}

pub fn classification_lines(title: &str, classes: &[String], rows: &[Row], predictions: &[usize]) -> Vec<String> {
    let mut matrix = vec![vec![0i64; classes.len()]; classes.len()];
    for (row, &predicted) in rows.iter().zip(predictions) { matrix[row.label][predicted] += 1; }
    let correct: i64 = (0..classes.len()).map(|i| matrix[i][i]).sum();
    let total = rows.len() as i64;
    let mut lines = vec![format!("confusion {title} correct {correct}/{total} accuracy {}", fraction_text(correct, total, 4)),
        format!("actual\\predicted {}", classes.join(" "))];
    for (name, counts) in classes.iter().zip(&matrix) { lines.push(format!("{name} {}", counts.iter().map(i64::to_string).collect::<Vec<_>>().join(" "))); }
    let mut f1_sum = 0.0;
    let mut f1_count = 0;
    for (index, name) in classes.iter().enumerate() {
        let hits = matrix[index][index];
        let predicted: i64 = matrix.iter().map(|counts| counts[index]).sum();
        let support: i64 = matrix[index].iter().sum();
        if predicted + support > 0 { f1_sum += 2.0 * hits as f64 / (predicted + support) as f64; f1_count += 1; }
        lines.push(format!("class {name} precision {} recall {} f1 {} support {support}",
            fraction_text(hits, predicted, 4), fraction_text(hits, support, 4), fraction_text(2 * hits, predicted + support, 4)));
    }
    lines.push(format!("macro_f1 {}", real_text(f1_sum / f1_count as f64, 4)));
    lines
}
