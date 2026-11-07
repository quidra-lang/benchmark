mod dataset;
mod impurity;
mod tree_builder;
mod pruning;
mod evaluation;

use std::collections::{BTreeMap, BTreeSet};
use std::{fs, io};
use dataset::{Attribute, Dataset, Row, load_dataset};
use evaluation::{Method, PrunedTree, classification_lines, fraction_text, ratio_text, real_text};
use impurity::{Fraction, class_counts, impurity_decrease, majority, square_sum};
use pruning::{Decision, SequenceTree, cost_complexity_sequence, reduced_error_pruning};
use tree_builder::{Split, TreeBuilder, half_text};

struct Minstd { state: i64 }
impl Minstd {
    fn draw(&mut self) -> i64 { self.state = 48271 * self.state % 2147483647; self.state }
}

#[derive(Clone)]
struct Condition {
    attribute: usize,
    lower: Option<i64>,
    upper: Option<i64>,
    equal: Option<i64>,
    excluded: BTreeSet<i64>,
}
impl Condition {
    fn new(attribute: usize) -> Self { Self { attribute, lower: None, upper: None, equal: None, excluded: BTreeSet::new() } }
    fn add(&mut self, split: Split, left: bool, attributes: &[Attribute]) {
        if attributes[self.attribute].integer {
            if left { self.upper = Some(self.upper.map_or(split.point, |bound| bound.min(split.point))); }
            else { self.lower = Some(self.lower.map_or(split.point, |bound| bound.max(split.point))); }
        } else if left { self.equal = Some(split.point); }
        else { self.excluded.insert(split.point); }
    }
    fn text(&self, attributes: &[Attribute]) -> String {
        let attribute = &attributes[self.attribute];
        if attribute.integer {
            match (self.lower, self.upper) {
                (Some(low), Some(high)) => format!("{} < {} <= {}", half_text(low), attribute.name, half_text(high)),
                (Some(low), None) => format!("{} > {}", attribute.name, half_text(low)),
                (None, Some(high)) => format!("{} <= {}", attribute.name, half_text(high)),
                _ => unreachable!(),
            }
        } else if let Some(value) = self.equal { format!("{} = {}", attribute.name, attribute.values[value as usize]) }
        else {
            let names: Vec<_> = self.excluded.iter().map(|&value| attribute.values[value as usize].as_str()).collect();
            if names.len() == 1 { format!("{} != {}", attribute.name, names[0]) }
            else { format!("{} not in {{{}}}", attribute.name, names.join(",")) }
        }
    }
    fn holds(&self, row: &Row, attributes: &[Attribute]) -> bool {
        let Some(value) = row.values[self.attribute] else { return false; };
        if attributes[self.attribute].integer {
            self.lower.is_none_or(|low| 2 * value > low) && self.upper.is_none_or(|high| 2 * value <= high)
        } else if let Some(equal) = self.equal { value == equal }
        else { !self.excluded.contains(&value) }
    }
}

struct Rule { number: usize, leaf: usize, conditions: Vec<Condition>, general: Vec<Condition>, removed: Vec<usize> }
struct DepthResult { depth: usize, tree: PrunedTree, cv_correct: i64 }
struct Bag { tree: PrunedTree, distinct: usize, out_of_bag: usize, correct: i64 }

fn counts_text(counts: &[i64]) -> String { counts.iter().map(i64::to_string).collect::<Vec<_>>().join(" ") }
fn join_sections(sections: Vec<Vec<String>>) -> Vec<String> {
    let mut lines = Vec::new();
    for section in sections { if !lines.is_empty() { lines.push(String::new()); } lines.extend(section); }
    lines
}
fn conditions_text(conditions: &[Condition], attributes: &[Attribute]) -> String {
    if conditions.is_empty() { "true".to_owned() }
    else { conditions.iter().map(|condition| condition.text(attributes)).collect::<Vec<_>>().join(" and ") }
}
fn coverage(conditions: &[Condition], rows: &[Row], label: usize, attributes: &[Attribute]) -> (i64, i64) {
    let mut hits = 0;
    let mut covered = 0;
    for row in rows {
        if conditions.iter().all(|condition| condition.holds(row, attributes)) {
            covered += 1;
            if row.label == label { hits += 1; }
        }
    }
    (hits, covered)
}
fn laplace(conditions: &[Condition], rows: &[Row], label: usize, attributes: &[Attribute], classes: usize) -> Fraction {
    let (hits, covered) = coverage(conditions, rows, label, attributes);
    Fraction { numerator: hits + 1, denominator: covered + classes as i64 }
}
fn generalize(conditions: &[Condition], rows: &[Row], label: usize, attributes: &[Attribute], classes: usize) -> (Vec<Condition>, Vec<usize>) {
    let mut current = conditions.to_vec();
    let mut removed = Vec::new();
    while !current.is_empty() {
        let estimate = laplace(&current, rows, label, attributes, classes);
        let mut best: Option<(Fraction, usize)> = None;
        for index in 0..current.len() {
            let mut trial = current.clone();
            trial.remove(index);
            let value = laplace(&trial, rows, label, attributes, classes);
            if best.is_none_or(|(previous, _)| value.compare(previous).is_gt()) { best = Some((value, index)); }
        }
        let (value, index) = best.unwrap();
        if estimate.compare(value).is_gt() { break; }
        removed.push(current.remove(index).attribute);
    }
    (current, removed)
}

struct Analysis<'a> {
    data: &'a Dataset,
    builder: TreeBuilder<'a>,
    grown: PrunedTree,
    pruned: PrunedTree,
    decisions: Vec<Decision>,
    rules: Vec<Rule>,
    bounds: Vec<usize>,
    fold_trees: Vec<PrunedTree>,
    depths: Vec<DepthResult>,
    selected_depth: usize,
    sequence: Vec<SequenceTree>,
    selected_index: usize,
    bags: Vec<Bag>,
    oob_votes: Vec<Vec<i64>>,
    test_votes: Vec<Vec<i64>>,
    predictions: BTreeMap<&'static str, Vec<usize>>,
}
impl<'a> Analysis<'a> {
    fn new(data: &'a Dataset) -> Self {
        let builder = TreeBuilder { attributes: &data.attributes, classes: data.classes.len(), settings: &data.settings };
        let grown = PrunedTree::new(builder.grow(&data.train));
        let (pruned, decisions) = reduced_error_pruning(grown.tree.clone(), &data.validation, &data.attributes);
        let mut result = Self { data, builder, grown, pruned, decisions, rules: Vec::new(), bounds: Vec::new(), fold_trees: Vec::new(),
            depths: Vec::new(), selected_depth: 0, sequence: Vec::new(), selected_index: 0, bags: Vec::new(),
            oob_votes: vec![vec![0; data.classes.len()]; data.train.len()], test_votes: vec![vec![0; data.classes.len()]; data.test.len()], predictions: BTreeMap::new() };
        result.collect_rules(0, &[]);
        result.bounds = (0..=data.settings.folds).map(|fold| fold * data.train.len() / data.settings.folds).collect();
        for fold in 0..data.settings.folds {
            let training: Vec<_> = data.train.iter().enumerate().filter(|(index, _)| *index < result.bounds[fold] || *index >= result.bounds[fold + 1]).map(|(_, row)| row.clone()).collect();
            result.fold_trees.push(PrunedTree::new(result.builder.grow(&training)));
        }
        for depth in 0..=data.settings.max_depth {
            let cv_correct = result.fold_trees.iter().enumerate().map(|(fold, tree)| tree.limited(depth).correct_count(&data.train[result.bounds[fold]..result.bounds[fold + 1]], &data.attributes)).sum();
            result.depths.push(DepthResult { depth, tree: result.grown.limited(depth), cv_correct });
            if cv_correct > result.depths[result.selected_depth].cv_correct { result.selected_depth = depth; }
        }
        result.sequence = cost_complexity_sequence(result.grown.tree.clone());
        for index in 0..result.sequence.len() {
            if result.validation_errors(&result.sequence[index].tree) <= result.validation_errors(&result.sequence[result.selected_index].tree) { result.selected_index = index; }
        }
        result.bagging();
        for (name, tree) in [("grown", &result.grown), ("pruned", &result.pruned), ("depth", &result.depths[result.selected_depth].tree), ("cost_complexity", &result.sequence[result.selected_index].tree)] {
            result.predictions.insert(name, data.test.iter().map(|row| tree.predict(row, &data.attributes)).collect());
        }
        result.predictions.insert("bagging", result.test_votes.iter().map(|votes| majority(votes)).collect());
        result
    }

    fn accuracy(&self, tree: &PrunedTree, rows: &[Row]) -> String { ratio_text(tree.correct_count(rows, &self.data.attributes), rows.len() as i64) }
    fn validation_errors(&self, tree: &PrunedTree) -> i64 { self.data.validation.len() as i64 - tree.correct_count(&self.data.validation, &self.data.attributes) }

    fn collect_rules(&mut self, index: usize, steps: &[(Split, bool)]) {
        if self.pruned.is_leaf(index) {
            let mut conditions = Vec::new();
            for attribute in 0..self.data.attributes.len() {
                let related: Vec<_> = steps.iter().filter(|(split, _)| split.attribute == attribute).collect();
                if related.is_empty() { continue; }
                let mut condition = Condition::new(attribute);
                for &&(split, left) in &related { condition.add(split, left, &self.data.attributes); }
                conditions.push(condition);
            }
            let label = self.pruned.tree.nodes[index].prediction;
            let (general, removed) = generalize(&conditions, &self.data.validation, label, &self.data.attributes, self.data.classes.len());
            self.rules.push(Rule { number: self.rules.len() + 1, leaf: index, conditions, general, removed });
            return;
        }
        let node = &self.pruned.tree.nodes[index];
        let split = node.split.unwrap();
        let [left, right] = node.children.unwrap();
        let mut next = steps.to_vec();
        next.push((split, true));
        self.collect_rules(left, &next);
        *next.last_mut().unwrap() = (split, false);
        self.collect_rules(right, &next);
    }

    fn bagging(&mut self) {
        let mut generator = Minstd { state: self.data.settings.bag_seed };
        let size = self.data.train.len();
        for _ in 0..self.data.settings.bag_trees {
            let indices: Vec<_> = (0..size).map(|_| (generator.draw() % size as i64) as usize).collect();
            let sample: Vec<_> = indices.iter().map(|&index| self.data.train[index].clone()).collect();
            let tree = PrunedTree::new(self.builder.grow(&sample));
            let sampled: BTreeSet<_> = indices.into_iter().collect();
            let mut correct = 0;
            for index in 0..size {
                if sampled.contains(&index) { continue; }
                let row = &self.data.train[index];
                let prediction = tree.predict(row, &self.data.attributes);
                self.oob_votes[index][prediction] += 1;
                if prediction == row.label { correct += 1; }
            }
            for (index, row) in self.data.test.iter().enumerate() { self.test_votes[index][tree.predict(row, &self.data.attributes)] += 1; }
            self.bags.push(Bag { tree, distinct: sampled.len(), out_of_bag: size - sampled.len(), correct });
        }
    }

    fn node_lines(&self, tree: &PrunedTree, index: usize, condition: String, lines: &mut Vec<String>) {
        let node = &tree.tree.nodes[index];
        let mut line = format!("{}{} {condition} n {} counts {}", "  ".repeat(node.depth), node.number, node.size, counts_text(&node.counts));
        if tree.is_leaf(index) { line.push_str(&format!(" leaf {}", self.data.classes[node.prediction])); }
        lines.push(line);
        if !tree.is_leaf(index) {
            let split = node.split.unwrap();
            let [left, right] = node.children.unwrap();
            self.node_lines(tree, left, split.condition(true, &self.data.attributes), lines);
            self.node_lines(tree, right, split.condition(false, &self.data.attributes), lines);
        }
    }
    fn tree_lines(&self, tree: &PrunedTree) -> Vec<String> {
        let mut lines = Vec::new();
        self.node_lines(tree, 0, "root".to_owned(), &mut lines);
        lines.push(String::new());
        let nodes = tree.preorder(0);
        let leaves = tree.leaves(0);
        let depth = tree.depth();
        lines.push(format!("nodes {} leaves {} depth {depth} errors {}", nodes.len(), leaves.len(), ratio_text(tree.training_errors(), self.data.train.len() as i64)));
        for level in 0..=depth {
            let level_nodes = nodes.iter().filter(|&&index| tree.tree.nodes[index].depth == level).count();
            let selected: Vec<_> = leaves.iter().map(|&index| &tree.tree.nodes[index]).filter(|node| node.depth == level).collect();
            let rows: i64 = selected.iter().map(|node| node.size).sum();
            let errors: i64 = selected.iter().map(|node| node.errors).sum();
            lines.push(format!("level {level} nodes {level_nodes} leaves {} rows {rows} errors {errors}", selected.len()));
        }
        lines
    }
    fn tree_file(&self) -> Vec<String> {
        let counts = &self.grown.tree.nodes[0].counts;
        let size = self.data.train.len() as i64;
        let mut found: Vec<_> = (0..self.data.attributes.len()).filter_map(|attribute| self.builder.best_split(&self.data.train, &[attribute])).collect();
        found.sort_by(|a, b| b.value().compare(a.value()).then_with(|| a.split.attribute.cmp(&b.split.attribute)));
        let mut candidates = vec![format!("root candidates n {size} counts {}", counts_text(counts))];
        for (index, candidate) in found.iter().enumerate() {
            let gain = candidate.value().real() / size as f64 - square_sum(counts) as f64 / (size * size) as f64;
            candidates.push(format!("{} {} left {} right {} gain {}", index + 1, candidate.split.condition(true, &self.data.attributes), candidate.left_size(), candidate.right_size(), real_text(gain, 6)));
        }
        let mut surrogates = vec!["surrogates".to_owned()];
        for index in self.grown.internal_nodes() {
            let node = &self.grown.tree.nodes[index];
            let listed: Vec<_> = node.surrogates.iter().map(|surrogate| format!("{} {} {}/{}", surrogate.split.condition(true, &self.data.attributes), if surrogate.forward { "left" } else { "right" }, surrogate.score, node.size)).collect();
            surrogates.push(format!("node {} split {} default {} surrogates {}", node.number, node.split.unwrap().condition(true, &self.data.attributes), if node.default_left { "left" } else { "right" }, if listed.is_empty() { "none".to_owned() } else { listed.join(" ; ") }));
        }
        join_sections(vec![candidates, self.tree_lines(&self.grown), surrogates])
    }
    fn pruned_tree_file(&self) -> Vec<String> {
        let mut lines = vec![format!("reduced_error_pruning validation {}", self.data.validation.len())];
        for decision in &self.decisions {
            let node = &self.grown.tree.nodes[decision.node];
            lines.push(format!("node {} depth {} rows {} leaf {} subtree {} {}", node.number, node.depth, decision.rows, decision.leaf_error, decision.subtree_error, if decision.pruned { "pruned" } else { "kept" }));
        }
        let pruned = self.decisions.iter().filter(|decision| decision.pruned).count();
        lines.push(format!("examined {} pruned {pruned} kept {}", self.decisions.len(), self.decisions.len() - pruned));
        join_sections(vec![lines, self.tree_lines(&self.pruned)])
    }
    fn predictions_file(&self) -> Vec<String> {
        let mut lines = vec!["id,predicted,actual,grown,leaf,path,missing".to_owned()];
        for row in &self.data.test {
            let route = self.pruned.route(row, &self.data.attributes);
            let leaf = &self.pruned.tree.nodes[*route.path.last().unwrap()];
            let path = route.path.iter().map(|&index| self.pruned.tree.nodes[index].number.to_string()).collect::<Vec<_>>().join("-");
            lines.push(format!("{},{},{},{},{},{path},{}", row.id, self.data.classes[leaf.prediction], self.data.classes[row.label], self.data.classes[self.grown.predict(row, &self.data.attributes)], leaf.number, route.methods.iter().filter(|&&method| method != Method::Primary).count()));
        }
        lines
    }
    fn rules_file(&self) -> Vec<String> {
        let mut rules = vec![format!("rules {}", self.rules.len())];
        let mut generalized = vec![format!("generalized {}", self.rules.len())];
        for rule in &self.rules {
            let leaf = &self.pruned.tree.nodes[rule.leaf];
            let reached: Vec<_> = self.data.test.iter().filter(|row| self.pruned.leaf_of(row, &self.data.attributes) == rule.leaf).collect();
            let hits = reached.iter().filter(|row| row.label == leaf.prediction).count() as i64;
            rules.push(format!("rule {} node {} if {} then {} train {} test {}", rule.number, leaf.number, conditions_text(&rule.conditions, &self.data.attributes), self.data.classes[leaf.prediction], ratio_text(leaf.counts[leaf.prediction], leaf.size), ratio_text(hits, reached.len() as i64)));
            let (hits, covered) = coverage(&rule.general, &self.data.validation, leaf.prediction, &self.data.attributes);
            let (test_hits, test_covered) = coverage(&rule.general, &self.data.test, leaf.prediction, &self.data.attributes);
            let removed = if rule.removed.is_empty() { "none".to_owned() } else { rule.removed.iter().map(|&index| self.data.attributes[index].name.as_str()).collect::<Vec<_>>().join(",") };
            generalized.push(format!("general {} if {} then {} removed {removed} laplace {} validation {hits}/{covered} test {test_hits}/{test_covered}", rule.number, conditions_text(&rule.general, &self.data.attributes), self.data.classes[leaf.prediction], fraction_text(hits + 1, covered + self.data.classes.len() as i64, 4)));
        }
        let wrong: Vec<_> = self.data.test.iter().filter(|row| self.pruned.predict(row, &self.data.attributes) != row.label).collect();
        let mut explanations = vec![format!("misclassified {}", wrong.len())];
        for row in wrong {
            let route = self.pruned.route(row, &self.data.attributes);
            let leaf_index = *route.path.last().unwrap();
            let leaf = &self.pruned.tree.nodes[leaf_index];
            let rule = self.rules.iter().find(|rule| rule.leaf == leaf_index).unwrap();
            let mut parts = Vec::new();
            for (index, pair) in route.path.windows(2).enumerate() {
                let node = &self.pruned.tree.nodes[pair[0]];
                parts.push(node.split.unwrap().condition(node.children.unwrap()[0] == pair[1], &self.data.attributes) + route.methods[index].mark());
            }
            let explanation = if parts.is_empty() { "root".to_owned() } else { parts.join("; ") };
            explanations.push(format!("{} actual {} predicted {} rule {} path {explanation}", row.id, self.data.classes[row.label], self.data.classes[leaf.prediction], rule.number));
        }
        join_sections(vec![rules, generalized, explanations])
    }

    fn data_lines(&self) -> Vec<String> {
        let data = self.data;
        let train = class_counts(&data.train, data.classes.len());
        let validation = class_counts(&data.validation, data.classes.len());
        let test = class_counts(&data.test, data.classes.len());
        let mut lines = vec![format!("data train {} validation {} test {} attributes {} classes {} target {}", data.train.len(), data.validation.len(), data.test.len(), data.attributes.len(), data.classes.len(), data.target)];
        for index in 0..data.classes.len() { lines.push(format!("class {} train {} validation {} test {}", data.classes[index], train[index], validation[index], test[index])); }
        let validation_missing: usize = data.validation.iter().map(Row::missing_count).sum();
        let test_missing: usize = data.test.iter().map(Row::missing_count).sum();
        lines.push(format!("missing validation {validation_missing} test {test_missing}"));
        for (index, attribute) in data.attributes.iter().enumerate() {
            lines.push(format!("missing {} validation {} test {}", attribute.name, data.validation.iter().filter(|row| row.values[index].is_none()).count(), data.test.iter().filter(|row| row.values[index].is_none()).count()));
        }
        lines
    }
    fn summary_line(&self, name: &str, tree: &PrunedTree) -> String {
        format!("{name} nodes {} leaves {} depth {} train {} validation {} test {}", tree.preorder(0).len(), tree.leaves(0).len(), tree.depth(), self.accuracy(tree, &self.data.train), self.accuracy(tree, &self.data.validation), self.accuracy(tree, &self.data.test))
    }
    fn model_evaluation(&self, name: &str) -> Vec<String> { classification_lines(&format!("{name} test"), &self.data.classes, &self.data.test, &self.predictions[name]) }
    fn routing_lines(&self) -> Vec<String> {
        let mut tallies = vec![[0usize; 3]; self.pruned.tree.nodes.len()];
        for row in &self.data.test {
            let route = self.pruned.route(row, &self.data.attributes);
            for (&index, method) in route.path.iter().zip(route.methods) { tallies[index][method.index()] += 1; }
        }
        let mut lines = vec!["routing pruned test".to_owned()];
        for index in self.pruned.internal_nodes() {
            let counts = tallies[index];
            lines.push(format!("node {} rows {} primary {} surrogate {} default {}", self.pruned.tree.nodes[index].number, counts.iter().sum::<usize>(), counts[0], counts[1], counts[2]));
        }
        for (name, complete) in [("complete", true), ("incomplete", false)] {
            let rows: Vec<_> = self.data.test.iter().filter(|row| (row.missing_count() == 0) == complete).cloned().collect();
            lines.push(format!("{name} rows {} correct {}", rows.len(), self.accuracy(&self.pruned, &rows)));
        }
        lines
    }
    fn cross_validation_lines(&self) -> Vec<String> {
        let mut lines = vec![format!("cross_validation folds {}", self.data.settings.folds)];
        let mut total = 0;
        for (fold, tree) in self.fold_trees.iter().enumerate() {
            let rows = &self.data.train[self.bounds[fold]..self.bounds[fold + 1]];
            let correct = tree.correct_count(rows, &self.data.attributes);
            total += correct;
            lines.push(format!("fold {} rows {}-{} leaves {} correct {}", fold + 1, self.bounds[fold] + 1, self.bounds[fold + 1], tree.leaves(0).len(), ratio_text(correct, rows.len() as i64)));
        }
        lines.push(format!("cv accuracy {}", ratio_text(total, self.data.train.len() as i64)));
        lines
    }
    fn depth_lines(&self) -> Vec<String> {
        let mut lines = vec!["depth_selection".to_owned()];
        for result in &self.depths {
            lines.push(format!("depth {} leaves {} cv {} train {} validation {} test {}", result.depth, result.tree.leaves(0).len(), ratio_text(result.cv_correct, self.data.train.len() as i64), self.accuracy(&result.tree, &self.data.train), self.accuracy(&result.tree, &self.data.validation), self.accuracy(&result.tree, &self.data.test)));
        }
        let selected = &self.depths[self.selected_depth];
        lines.push(format!("selected depth {} leaves {} test {}", selected.depth, selected.tree.leaves(0).len(), self.accuracy(&selected.tree, &self.data.test)));
        lines
    }
    fn cost_lines(&self) -> Vec<String> {
        let mut lines = vec!["cost_complexity".to_owned()];
        for (index, step) in self.sequence.iter().enumerate() {
            lines.push(format!("subtree {index} alpha {} leaves {} train_errors {} validation_errors {}", fraction_text(step.alpha.numerator, step.alpha.denominator * self.data.train.len() as i64, 6), step.tree.leaves(0).len(), step.tree.training_errors(), self.validation_errors(&step.tree)));
        }
        let tree = &self.sequence[self.selected_index].tree;
        lines.push(format!("selected subtree {} leaves {} test {}", self.selected_index, tree.leaves(0).len(), self.accuracy(tree, &self.data.test)));
        lines
    }
    fn bagging_lines(&self) -> Vec<String> {
        let settings = &self.data.settings;
        let mut lines = vec![format!("bagging trees {} seed {}", settings.bag_trees, settings.bag_seed)];
        for (index, bag) in self.bags.iter().enumerate() { lines.push(format!("bag {} distinct {} leaves {} oob {}", index + 1, bag.distinct, bag.tree.leaves(0).len(), ratio_text(bag.correct, bag.out_of_bag as i64))); }
        let mut voted = 0;
        let mut hits = 0;
        for (row, votes) in self.data.train.iter().zip(&self.oob_votes) {
            if votes.iter().sum::<i64>() > 0 { voted += 1; if majority(votes) == row.label { hits += 1; } }
        }
        lines.push(format!("oob accuracy {} unvoted {}", ratio_text(hits, voted), self.data.train.len() as i64 - voted));
        lines.extend(self.model_evaluation("bagging"));
        lines
    }
    fn mcnemar_lines(&self) -> Vec<String> {
        let mut lines = vec!["mcnemar pruned test".to_owned()];
        for name in ["grown", "depth", "cost_complexity", "bagging"] {
            let mut b = 0i64;
            let mut c = 0i64;
            for (index, row) in self.data.test.iter().enumerate() {
                let first = self.predictions["pruned"][index] == row.label;
                let second = self.predictions[name][index] == row.label;
                if first && !second { b += 1; }
                if second && !first { c += 1; }
            }
            let value = ((b - c).abs() - 1).max(0);
            let squared = value * value;
            let statistic = if b + c == 0 { "0/1 0.0000".to_owned() } else { fraction_text(squared, b + c, 4) };
            lines.push(format!("versus {name} b {b} c {c} statistic {statistic} significant {}", if 1000 * squared > 3841 * (b + c) { "yes" } else { "no" }));
        }
        lines
    }
    fn scores(&self, model: &str) -> Vec<Vec<Fraction>> {
        if model == "bagging" { return self.test_votes.iter().map(|votes| votes.iter().map(|&count| Fraction { numerator: count, denominator: self.data.settings.bag_trees as i64 }).collect()).collect(); }
        let tree = if model == "grown" { &self.grown } else { &self.pruned };
        self.data.test.iter().map(|row| { let leaf = &tree.tree.nodes[tree.leaf_of(row, &self.data.attributes)]; leaf.counts.iter().map(|&count| Fraction { numerator: count, denominator: leaf.size }).collect() }).collect()
    }
    fn auc_lines(&self) -> Vec<String> {
        let mut lines = Vec::new();
        for model in ["grown", "pruned", "bagging"] {
            let scores = self.scores(model);
            let mut parts = vec!["auc".to_owned(), model.to_owned()];
            let mut sum = 0.0;
            let mut count = 0;
            for (label, name) in self.data.classes.iter().enumerate() {
                let positives: Vec<_> = self.data.test.iter().enumerate().filter(|(_, row)| row.label == label).map(|(index, _)| scores[index][label]).collect();
                let negatives: Vec<_> = self.data.test.iter().enumerate().filter(|(_, row)| row.label != label).map(|(index, _)| scores[index][label]).collect();
                let mut wins = 0;
                for &first in &positives { for &second in &negatives { wins += match first.compare(second) { std::cmp::Ordering::Greater => 2, std::cmp::Ordering::Equal => 1, _ => 0 }; } }
                let pairs = 2 * positives.len() as i64 * negatives.len() as i64;
                parts.push(name.clone());
                parts.push(fraction_text(wins, pairs, 4));
                if pairs > 0 { sum += wins as f64 / pairs as f64; count += 1; }
            }
            parts.push("macro".to_owned());
            parts.push(if count == 0 { "-".to_owned() } else { real_text(sum / count as f64, 4) });
            lines.push(parts.join(" "));
        }
        lines
    }
    fn learning_lines(&self) -> Vec<String> {
        let mut lines = vec!["learning_curve".to_owned()];
        for &size in &self.data.settings.curve {
            let grown = PrunedTree::new(self.builder.grow(&self.data.train[..size]));
            let (pruned, _) = reduced_error_pruning(grown.tree.clone(), &self.data.validation, &self.data.attributes);
            lines.push(format!("size {size} grown leaves {} test {} pruned leaves {} test {}", grown.leaves(0).len(), self.accuracy(&grown, &self.data.test), pruned.leaves(0).len(), self.accuracy(&pruned, &self.data.test)));
        }
        lines
    }
    fn evaluation_file(&self) -> Vec<String> {
        join_sections(vec![self.data_lines(), vec![self.summary_line("grown", &self.grown), self.summary_line("pruned", &self.pruned)], self.model_evaluation("grown"), self.model_evaluation("pruned"), self.routing_lines(), self.cross_validation_lines(), self.depth_lines(), self.cost_lines(), self.bagging_lines(), self.mcnemar_lines(), self.auc_lines(), self.learning_lines()])
    }
    fn impurity_lines(&self, title: &str, tree: &PrunedTree) -> Vec<String> {
        let mut importance = vec![0.0; self.data.attributes.len()];
        let mut splits = vec![0; importance.len()];
        for index in tree.internal_nodes() {
            let node = &tree.tree.nodes[index];
            let [left, right] = node.children.unwrap();
            let attribute = node.split.unwrap().attribute;
            importance[attribute] += impurity_decrease(&node.counts, &tree.tree.nodes[left].counts, &tree.tree.nodes[right].counts);
            splits[attribute] += 1;
        }
        let total: f64 = importance.iter().sum();
        let shares: Vec<_> = importance.iter().map(|value| if total == 0.0 { 0.0 } else { value / total }).collect();
        let mut order: Vec<_> = (0..importance.len()).collect();
        order.sort_by_key(|&index| (std::cmp::Reverse((shares[index] * 10000.0).round() as i64), index));
        let mut lines = vec![format!("impurity {title}")];
        for (rank, index) in order.into_iter().enumerate() { lines.push(format!("{} {} decrease {} share {} splits {}", rank + 1, self.data.attributes[index].name, real_text(importance[index] / self.data.train.len() as f64, 4), real_text(shares[index], 4), splits[index])); }
        lines
    }
    fn permutation_lines(&self) -> Vec<String> {
        let settings = &self.data.settings;
        let mut generator = Minstd { state: settings.permutation_seed };
        let base = self.pruned.correct_count(&self.data.test, &self.data.attributes);
        let mut results = Vec::new();
        for attribute in 0..self.data.attributes.len() {
            let mut counts = Vec::new();
            for _ in 0..settings.repeats {
                let mut values: Vec<_> = self.data.test.iter().map(|row| row.values[attribute]).collect();
                for position in (2..=values.len()).rev() { let other = (generator.draw() % position as i64) as usize; values.swap(position - 1, other); }
                let rows: Vec<_> = self.data.test.iter().zip(values).map(|(row, value)| { let mut changed = row.clone(); changed.values[attribute] = value; changed }).collect();
                counts.push(self.pruned.correct_count(&rows, &self.data.attributes));
            }
            let drop = settings.repeats as i64 * base - counts.iter().sum::<i64>();
            results.push((attribute, counts, drop));
        }
        results.sort_by_key(|(attribute, _, drop)| (std::cmp::Reverse(*drop), *attribute));
        let mut lines = vec![format!("permutation pruned test repeats {} seed {} base {}", settings.repeats, settings.permutation_seed, ratio_text(base, self.data.test.len() as i64))];
        for (rank, (attribute, counts, drop)) in results.into_iter().enumerate() { lines.push(format!("{} {} correct {} drop {}", rank + 1, self.data.attributes[attribute].name, counts_text(&counts), fraction_text(drop, (settings.repeats * self.data.test.len()) as i64, 4))); }
        lines
    }
    fn importance_file(&self) -> Vec<String> { join_sections(vec![self.impurity_lines("grown", &self.grown), self.impurity_lines("pruned", &self.pruned), self.permutation_lines()]) }
}

fn main() -> io::Result<()> {
    let data = load_dataset("input")?;
    let analysis = Analysis::new(&data);
    fs::create_dir_all("output")?;
    for (name, lines) in [("tree.txt", analysis.tree_file()), ("pruned_tree.txt", analysis.pruned_tree_file()), ("predictions.csv", analysis.predictions_file()), ("rules.txt", analysis.rules_file()), ("evaluation.txt", analysis.evaluation_file()), ("importance.txt", analysis.importance_file())] {
        fs::write(format!("output/{name}"), lines.join("\n") + "\n")?;
    }
    Ok(())
}
