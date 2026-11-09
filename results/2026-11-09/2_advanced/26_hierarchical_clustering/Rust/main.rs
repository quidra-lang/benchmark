mod dataset;
mod distances;
mod agglomerative;
mod dendrogram;
mod validation;

use std::collections::BTreeSet;
use std::io;
use dataset::{Observation, Settings, read_observations, read_settings, write_lines};
use distances::{sequential_sum, squared_distance, feature_statistics, standardize, distance_matrix, DISTANCE_TYPES};
use agglomerative::{Linkage, Merge, agglomerate, minimum_spanning_tree};
use dendrogram::{ordered_children, leaf_order, column, dendrogram_rows};
use validation::{Fraction, correlation, contingency_table, adjusted_rand_index, silhouette_values};

fn real(value: f64) -> String {
    let text = format!("{value:.4}");
    if text == "-0.0000" { "0.0000".to_owned() } else { text }
}
fn optional_real(value: Option<f64>) -> String { value.map_or_else(|| "-".to_owned(), real) }
fn reals(values: impl IntoIterator<Item = f64>) -> String { values.into_iter().map(real).collect::<Vec<_>>().join(" ") }
fn integers<T: ToString>(values: &[T]) -> String { values.iter().map(ToString::to_string).collect::<Vec<_>>().join(" ") }
fn four_digit(value: f64) -> f64 { real(value).parse().unwrap() }
fn ari_text(value: Fraction) -> String { format!("{}/{} {}", value.numerator, value.denominator, real(value.value())) }
fn pair_values(matrix: &[Vec<f64>]) -> Vec<f64> {
    let mut values = Vec::new();
    for i in 0..matrix.len() { for j in i + 1..matrix.len() { values.push(matrix[i][j]); } }
    values
}
fn histogram_bin(value: f64, maximum: f64) -> usize { 9.min((10.0 * value / maximum).floor() as usize) }
fn centroid(vectors: &[Vec<f64>]) -> Vec<f64> {
    (0..vectors[0].len()).map(|f| sequential_sum(vectors.iter().map(|vector| vector[f])) / vectors.len() as f64).collect()
}
fn cluster_members(partition: &[usize], groups: usize) -> Vec<Vec<usize>> {
    let mut members = vec![Vec::new(); groups];
    for (i, &number) in partition.iter().enumerate() { members[number - 1].push(i); }
    members
}
fn majority_class(row: &[i64]) -> usize {
    let mut best = 0;
    for t in 1..row.len() { if row[t] > row[best] { best = t; } }
    best
}
fn join_parts(parts: Vec<Vec<String>>) -> Vec<String> {
    let mut lines = Vec::new();
    for part in parts { if !lines.is_empty() { lines.push(String::new()); } lines.extend(part); }
    lines
}
fn partition_ari(first: &[usize], second: &[usize]) -> Fraction {
    let xs: Vec<usize> = first.iter().map(|&value| value - 1).collect();
    let ys: Vec<usize> = second.iter().map(|&value| value - 1).collect();
    adjusted_rand_index(&contingency_table(&xs, &ys, *first.iter().max().unwrap(), *second.iter().max().unwrap()))
}

struct Minstd { state: i64 }
impl Minstd {
    fn draw(&mut self) -> i64 { self.state = 48271 * self.state % 2147483647; self.state }
}

struct Tree {
    merges: Vec<Merge>,
    n: usize,
    children: Vec<(usize, usize)>,
    order: Vec<usize>,
    members: Vec<Vec<usize>>,
    depths: Vec<usize>,
    subtree_heights: Vec<f64>,
}
impl Tree {
    fn new(merges: Vec<Merge>, n: usize) -> Self {
        let children = ordered_children(&merges, n);
        let order = leaf_order(&children, n);
        let mut members: Vec<Vec<usize>> = (0..n).map(|u| vec![u]).collect();
        let mut depths = vec![0; n];
        let mut maxima = vec![0.0f64; n];
        let mut subtree_heights = Vec::new();
        for merge in &merges {
            let mut group = members[merge.a].clone();
            group.extend_from_slice(&members[merge.b]);
            members.push(group);
            depths.push(1 + depths[merge.a].max(depths[merge.b]));
            let maximum = merge.height.max(maxima[merge.a]).max(maxima[merge.b]);
            maxima.push(maximum);
            subtree_heights.push(maximum);
        }
        Self { merges, n, children, order, members, depths, subtree_heights }
    }
    fn root(&self) -> usize { 2 * self.n - 2 }
    fn height(&self, node: usize) -> f64 { if node < self.n { 0.0 } else { self.merges[node - self.n].height } }
    fn heights(&self) -> Vec<f64> { self.merges.iter().map(|merge| merge.height).collect() }
    fn partition(&self, selected: &[bool]) -> Vec<usize> {
        let mut owner: Vec<usize> = (0..self.n).collect();
        for (step, &chosen) in selected.iter().enumerate() {
            if chosen { for &u in &self.members[self.n + step] { owner[u] = self.n + step; } }
        }
        let mut numbers = vec![0; 2 * self.n - 1];
        let mut groups = 0;
        for &u in &self.order { if numbers[owner[u]] == 0 { groups += 1; numbers[owner[u]] = groups; } }
        owner.iter().map(|&node| numbers[node]).collect()
    }
    fn cut_at_height(&self, height: f64) -> Vec<usize> { self.partition(&self.subtree_heights.iter().map(|&value| value <= height).collect::<Vec<_>>()) }
    fn cut_into(&self, k: usize) -> Vec<usize> { self.partition(&(0..self.n - 1).map(|step| step < self.n - k).collect::<Vec<_>>()) }
    fn cophenetic(&self) -> Vec<Vec<f64>> {
        let mut matrix = vec![vec![0.0; self.n]; self.n];
        for merge in &self.merges {
            for &i in &self.members[merge.a] { for &j in &self.members[merge.b] { matrix[i][j] = merge.height; matrix[j][i] = merge.height; } }
        }
        matrix
    }
    fn joining_heights(&self) -> Vec<f64> {
        let mut heights = vec![0.0; self.n];
        for merge in &self.merges { for child in [merge.a, merge.b] { if child < self.n { heights[child] = merge.height; } } }
        heights
    }
    fn height_sequence(&self, step: usize, depth: usize) -> Vec<f64> {
        if depth == 0 { return Vec::new(); }
        let merge = &self.merges[step];
        let mut values = vec![merge.height];
        for child in [merge.a, merge.b] { if child >= self.n { values.extend(self.height_sequence(child - self.n, depth - 1)); } }
        values
    }
    fn newick(&self, node: usize, ids: &[String]) -> String {
        if node < self.n { return ids[node].clone(); }
        let (upper, lower) = self.children[node - self.n];
        let height = self.height(node);
        format!("({}:{},{}:{})", self.newick(upper, ids), real(height - self.height(upper)), self.newick(lower, ids), real(height - self.height(lower)))
    }
}

struct Evaluation {
    partition: Vec<usize>, sizes: Vec<usize>, silhouette: Option<f64>, dunn: Option<f64>, wss: f64, ch: Option<f64>, ari: Fraction,
}
impl Evaluation {
    fn text(&self) -> String {
        format!("sizes {} silhouette {} dunn {} wss {} ch {} ari {}", integers(&self.sizes), optional_real(self.silhouette), optional_real(self.dunn), real(self.wss), optional_real(self.ch), ari_text(self.ari))
    }
}
struct LinkageResult {
    method: Linkage, tree: Tree, cophenetic: Vec<f64>, correlation: f64,
    height_cuts: Vec<Evaluation>, count_cuts: Vec<Evaluation>, label_partition: Vec<usize>,
}

struct Study {
    features: Vec<String>, settings: Settings, n: usize, ids: Vec<String>, labels: Vec<String>, classes: Vec<String>, targets: Vec<usize>,
    raw: Vec<Vec<f64>>, means: Vec<f64>, deviations: Vec<f64>, vectors: Vec<Vec<f64>>, delta: Vec<Vec<f64>>,
    pairs: Vec<f64>, distance_max: f64, neighbors: Vec<usize>, results: Vec<LinkageResult>, chosen: usize, position: usize,
}
impl Study {
    fn new(features: Vec<String>, observations: Vec<Observation>, settings: Settings) -> Self {
        let n = observations.len();
        let ids = observations.iter().map(|row| row.id.clone()).collect();
        let labels: Vec<String> = observations.iter().map(|row| row.label.clone()).collect();
        let classes: Vec<String> = labels.iter().cloned().collect::<BTreeSet<_>>().into_iter().collect();
        let targets = labels.iter().map(|label| classes.binary_search(label).unwrap()).collect();
        let raw: Vec<Vec<f64>> = observations.into_iter().map(|row| row.values).collect();
        let (means, deviations) = feature_statistics(&raw);
        let vectors = if settings.standardize { standardize(&raw, &means, &deviations) } else { raw.clone() };
        let delta = distance_matrix(&vectors, settings.distance);
        let pairs = pair_values(&delta);
        let distance_max = pairs.iter().copied().fold(f64::NEG_INFINITY, f64::max);
        let mut neighbors = Vec::new();
        for i in 0..n {
            let mut best = if i == 0 { 1 } else { 0 };
            for j in 0..n { if j != i && delta[i][j] < delta[i][best] { best = j; } }
            neighbors.push(best);
        }
        let mut study = Self { features, settings, n, ids, labels, classes, targets, raw, means, deviations, vectors, delta, pairs, distance_max, neighbors, results: Vec::new(), chosen: 0, position: 0 };
        study.results = study.settings.linkages.iter().map(|&method| study.analyse_linkage(method)).collect();
        for r in 0..study.results.len() {
            for k in 0..study.settings.cut_counts.len() {
                if study.results[r].count_cuts[k].ari.greater(study.results[study.chosen].count_cuts[study.position].ari) { study.chosen = r; study.position = k; }
            }
        }
        study
    }
    fn chosen(&self) -> &LinkageResult { &self.results[self.chosen] }
    fn selected_cut(&self) -> &Evaluation { &self.chosen().count_cuts[self.position] }
    fn selected(&self) -> &[usize] { &self.selected_cut().partition }
    fn kappa(&self) -> usize { self.settings.cut_counts[self.position] }
    fn members(&self) -> Vec<Vec<usize>> { cluster_members(self.selected(), self.kappa()) }
    fn class_table(&self, partition: &[usize]) -> Vec<Vec<i64>> {
        let rows: Vec<usize> = partition.iter().map(|&number| number - 1).collect();
        contingency_table(&rows, &self.targets, *partition.iter().max().unwrap(), self.classes.len())
    }
    fn label_ari(&self, partition: &[usize]) -> Fraction { adjusted_rand_index(&self.class_table(partition)) }
    fn match_count(&self, partition: &[usize]) -> i64 { self.class_table(partition).iter().map(|row| row.iter().max().unwrap()).sum() }
    fn mean_silhouette(&self, partition: &[usize], delta: &[Vec<f64>]) -> Option<f64> {
        let groups = *partition.iter().max().unwrap();
        if groups < 2 { None } else { Some(sequential_sum(silhouette_values(partition, groups, delta)) / partition.len() as f64) }
    }
    fn centroids(&self, partition: &[usize]) -> Vec<Vec<f64>> {
        cluster_members(partition, *partition.iter().max().unwrap()).iter().map(|group| centroid(&group.iter().map(|&i| self.vectors[i].clone()).collect::<Vec<_>>())).collect()
    }
    fn within_sum(&self, partition: &[usize]) -> f64 {
        let centers = self.centroids(partition);
        sequential_sum(partition.iter().enumerate().map(|(i, &number)| squared_distance(&self.vectors[i], &centers[number - 1])))
    }
    fn evaluate(&self, partition: Vec<usize>) -> Evaluation {
        let groups = *partition.iter().max().unwrap();
        let members = cluster_members(&partition, groups);
        let sizes: Vec<usize> = members.iter().map(Vec::len).collect();
        let wss = self.within_sum(&partition);
        let mut diameter = 0.0f64;
        let mut separation = f64::INFINITY;
        for i in 0..self.n { for j in i + 1..self.n {
            if partition[i] == partition[j] { diameter = diameter.max(self.delta[i][j]); }
            else { separation = separation.min(self.delta[i][j]); }
        } }
        let dunn = if groups >= 2 && diameter > 0.0 { Some(separation / diameter) } else { None };
        let ch = if groups >= 2 && groups < self.n {
            let overall = centroid(&self.vectors);
            let centers = self.centroids(&partition);
            let bss = sequential_sum(sizes.iter().zip(&centers).map(|(&size, center)| size as f64 * squared_distance(center, &overall)));
            Some((bss / (groups - 1) as f64) / (wss / (self.n - groups) as f64))
        } else { None };
        let silhouette = self.mean_silhouette(&partition, &self.delta);
        let ari = self.label_ari(&partition);
        Evaluation { partition, sizes, silhouette, dunn, wss, ch, ari }
    }
    fn analyse_linkage(&self, method: Linkage) -> LinkageResult {
        let tree = Tree::new(agglomerate(&self.delta, method), self.n);
        let cophenetic = pair_values(&tree.cophenetic());
        let correlation = correlation(&self.pairs, &cophenetic);
        let height_cuts = self.settings.cut_heights.iter().map(|&height| self.evaluate(tree.cut_at_height(height))).collect();
        let count_cuts = self.settings.cut_counts.iter().map(|&k| self.evaluate(tree.cut_into(k))).collect();
        let label_partition = tree.cut_into(self.classes.len());
        LinkageResult { method, tree, cophenetic, correlation, height_cuts, count_cuts, label_partition }
    }
    fn linkage_table(&self) -> Vec<String> {
        let mut lines = vec!["method,step,a,b,height,size".to_owned()];
        for result in &self.results { for (step, merge) in result.tree.merges.iter().enumerate() {
            lines.push(format!("{},{},{},{},{},{}", result.method.name(), step + 1, merge.a, merge.b, real(merge.height), merge.size));
        } }
        lines
    }
    fn clusters_table(&self) -> Vec<String> {
        let mut header = vec!["id".to_owned(), "label".to_owned()];
        for result in &self.results {
            for j in 1..=self.settings.cut_heights.len() { header.push(format!("{}_h{j}", result.method.name())); }
            for k in &self.settings.cut_counts { header.push(format!("{}_k{k}", result.method.name())); }
        }
        let mut lines = vec![header.join(",")];
        for i in 0..self.n {
            let mut fields = vec![self.ids[i].clone(), self.labels[i].clone()];
            for result in &self.results { for cut in result.height_cuts.iter().chain(&result.count_cuts) { fields.push(cut.partition[i].to_string()); } }
            lines.push(fields.join(","));
        }
        lines
    }
    fn dendrogram_report(&self) -> Vec<String> {
        let mut parts = Vec::new();
        for result in &self.results {
            let tree = &result.tree;
            let maximum = tree.heights().into_iter().fold(f64::NEG_INFINITY, f64::max);
            let cuts: Vec<usize> = self.settings.cut_heights.iter().map(|&height| column(height, maximum, self.settings.width)).collect();
            let mut lines = vec![format!("dendrogram {} height_max {} width {}", result.method.name(), real(maximum), self.settings.width)];
            lines.extend(dendrogram_rows(&tree.merges, &tree.children, &tree.order, &self.ids, &self.labels, maximum, &cuts, self.settings.width));
            for (&height, &x) in self.settings.cut_heights.iter().zip(&cuts) { lines.push(format!("cut {} column {}", real(height), if x <= self.settings.width { x.to_string() } else { "-".to_owned() })); }
            parts.push(lines);
        }
        join_parts(parts)
    }
    fn trees_report(&self) -> Vec<String> { self.results.iter().map(|result| format!("{} {};", result.method.name(), result.tree.newick(result.tree.root(), &self.ids))).collect() }
    fn pair_text(&self, pair: (usize, usize)) -> String { format!("{} {} {}", real(self.delta[pair.0][pair.1]), self.ids[pair.0], self.ids[pair.1]) }
    fn data_part(&self) -> Vec<String> {
        let mut lines = vec![format!("data n {} features {} classes {} distance {} standardize {}", self.n, self.features.len(), self.classes.len(), self.settings.distance.name(), if self.settings.standardize { "yes" } else { "no" })];
        for f in 0..self.features.len() { lines.push(format!("feature {} mean {} sd {}", self.features[f], real(self.means[f]), real(self.deviations[f]))); }
        let (mut smallest, mut largest) = ((0, 1), (0, 1));
        for i in 0..self.n { for j in i + 1..self.n {
            if self.delta[i][j] < self.delta[smallest.0][smallest.1] { smallest = (i, j); }
            if self.delta[i][j] > self.delta[largest.0][largest.1] { largest = (i, j); }
        } }
        lines.push(format!("distances pairs {} min {} max {} mean {}", self.pairs.len(), self.pair_text(smallest), self.pair_text(largest), real(sequential_sum(self.pairs.iter().copied()) / self.pairs.len() as f64)));
        let nearest_mean = sequential_sum((0..self.n).map(|i| self.delta[i][self.neighbors[i]])) / self.n as f64;
        let reciprocal = (0..self.n).filter(|&i| i < self.neighbors[i] && self.neighbors[self.neighbors[i]] == i).count();
        lines.push(format!("nearest_neighbors mean {} reciprocal_pairs {reciprocal}", real(nearest_mean)));
        lines.push("labels ".to_owned() + &self.evaluate(self.targets.iter().map(|&target| target + 1).collect()).text());
        lines
    }
    fn correlation_part(&self) -> Vec<String> {
        let columns: Vec<Vec<f64>> = (0..self.features.len()).map(|f| self.raw.iter().map(|row| row[f]).collect()).collect();
        let mut lines = vec!["correlation ".to_owned() + &self.features.join(" ")];
        for (f, first) in columns.iter().enumerate() { lines.push(format!("{} {}", self.features[f], reals(columns.iter().map(|second| correlation(first, second))))); }
        lines
    }
    fn histogram_part(&self) -> Vec<String> {
        let mut counts = vec![0usize; 10];
        for &value in &self.pairs { counts[histogram_bin(value, self.distance_max)] += 1; }
        let highest = *counts.iter().max().unwrap();
        let mut lines = vec!["histogram".to_owned()];
        for (b, &count) in counts.iter().enumerate() {
            let mut line = format!("{} {} {count}", real(b as f64 * self.distance_max / 10.0), real((b + 1) as f64 * self.distance_max / 10.0));
            let length = count * 50 / highest;
            if length > 0 { line.push(' '); line.push_str(&"#".repeat(length)); }
            lines.push(line);
        }
        lines
    }
    fn inconsistency_line(&self, tree: &Tree, step: usize) -> String {
        let sequence = tree.height_sequence(step, self.settings.inconsistency_depth);
        let size = sequence.len();
        let mean = sequential_sum(sequence.iter().copied()) / size as f64;
        let deviation = if size == 1 { 0.0 } else { (sequential_sum(sequence.iter().map(|&value| (value - mean) * (value - mean))) / (size - 1) as f64).sqrt() };
        let coefficient = if size == 1 { 0.0 } else { (tree.merges[step].height - mean) / deviation };
        format!("step {} height {} mean {} sd {} count {size} coefficient {}", step + 1, real(tree.merges[step].height), real(mean), real(deviation), real(coefficient))
    }
    fn linkage_part(&self, result: &LinkageResult) -> Vec<String> {
        let tree = &result.tree;
        let heights = tree.heights();
        let leaf_path = sequential_sum(tree.order.windows(2).map(|pair| self.delta[pair[0]][pair[1]]));
        let inversions: Vec<usize> = (1..self.n - 1).filter(|&step| heights[step] < heights[step - 1]).collect();
        let minimum = heights.iter().copied().fold(f64::INFINITY, f64::min);
        let maximum = heights.iter().copied().fold(f64::NEG_INFINITY, f64::max);
        let mut lines = vec![format!("linkage {}", result.method.name()), format!("cophenetic {} leaf_path {}", real(result.correlation), real(leaf_path)), format!("heights min {} max {} inversions {}", real(minimum), real(maximum), inversions.len())];
        for step in inversions { lines.push(format!("inversion step {} height {} previous {}", step + 1, real(heights[step]), real(heights[step - 1]))); }
        let mut ordered = tree.subtree_heights.clone();
        ordered.sort_by(f64::total_cmp);
        let gaps: Vec<f64> = (2..=self.settings.gap_max_k).map(|k| ordered[self.n - k] - ordered[self.n - k - 1]).collect();
        let mut suggested = 2;
        for k in 3..=self.settings.gap_max_k { if four_digit(gaps[k - 2]) > four_digit(gaps[suggested - 2]) { suggested = k; } }
        lines.push("gaps ".to_owned() + &reals(gaps));
        lines.push(format!("suggested_k {suggested}"));
        let joining = tree.joining_heights();
        let mut late: Vec<usize> = (0..self.n).collect();
        late.sort_by(|&a, &b| joining[b].total_cmp(&joining[a]).then(a.cmp(&b)));
        lines.push("late_joiners ".to_owned() + &late[..self.settings.list_size].iter().map(|&i| format!("{}:{}", self.ids[i], real(joining[i]))).collect::<Vec<_>>().join(" "));
        let mut kinds = [0; 3];
        for merge in &tree.merges { let leaves = usize::from(merge.a < self.n) + usize::from(merge.b < self.n); kinds[2 - leaves] += 1; }
        lines.push(format!("merges leaf_leaf {} leaf_cluster {} cluster_cluster {} depth {}", kinds[0], kinds[1], kinds[2], tree.depths[tree.root()]));
        let matches = self.match_count(&result.label_partition);
        lines.push(format!("label_cut k {} purity {matches}/{} {}", self.classes.len(), self.n, real(matches as f64 / self.n as f64)));
        lines.push(format!("inconsistency depth {}", self.settings.inconsistency_depth_text));
        for step in self.n - self.settings.inconsistency_count - 1..self.n - 1 { lines.push(self.inconsistency_line(tree, step)); }
        for (&height, cut) in self.settings.cut_heights.iter().zip(&result.height_cuts) { lines.push(format!("cut height {} clusters {} {}", real(height), cut.sizes.len(), cut.text())); }
        for (&k, cut) in self.settings.cut_counts.iter().zip(&result.count_cuts) { lines.push(format!("cut k {k} {}", cut.text())); }
        lines
    }
    fn mst_part(&self, single: &LinkageResult) -> Vec<String> {
        let edges = minimum_spanning_tree(&self.delta);
        let total = sequential_sum(edges.iter().map(|edge| edge.weight));
        let mut weights: Vec<f64> = edges.iter().map(|edge| edge.weight).collect();
        weights.sort_by(f64::total_cmp);
        let heights_match = weights.iter().zip(&single.tree.merges).all(|(&weight, merge)| (weight - merge.height).abs() <= 0.000000001);
        let mut linked = vec![vec![false; self.n]; self.n];
        for edge in &edges { linked[edge.parent][edge.child] = true; linked[edge.child][edge.parent] = true; }
        let nn_edges = (0..self.n).filter(|&i| linked[i][self.neighbors[i]]).count();
        let mut lines = vec![format!("mst total {} heights {} nn_edges {nn_edges}/{}", real(total), if heights_match { "match" } else { "mismatch" }, self.n)];
        let mut ordered: Vec<usize> = (0..edges.len()).collect();
        ordered.sort_by(|&a, &b| edges[a].weight.total_cmp(&edges[b].weight).then(a.cmp(&b)));
        for (&k, cut) in self.settings.cut_counts.iter().zip(&single.count_cuts) {
            let mut components: Vec<usize> = (0..self.n).collect();
            for &number in &ordered[..self.n - k] {
                let edge = &edges[number];
                let old = components[edge.child];
                let new = components[edge.parent];
                for value in &mut components { if *value == old { *value = new; } }
            }
            let mut agrees = true;
            for i in 0..self.n { for j in i + 1..self.n { if (components[i] == components[j]) != (cut.partition[i] == cut.partition[j]) { agrees = false; } } }
            lines.push(format!("mst partition k {k} {}", if agrees { "match" } else { "mismatch" }));
        }
        lines
    }
    fn compare_part(&self) -> Vec<String> {
        let mut lines = vec![format!("compare linkage {} k {}", self.settings.compare_linkage.name(), self.classes.len())];
        for kind in DISTANCE_TYPES {
            let delta = distance_matrix(&self.vectors, kind);
            let tree = Tree::new(agglomerate(&delta, self.settings.compare_linkage), self.n);
            let cophenetic = correlation(&pair_values(&delta), &pair_values(&tree.cophenetic()));
            let partition = tree.cut_into(self.classes.len());
            lines.push(format!("metric {} cophenetic {} silhouette {} ari {}", kind.name(), real(cophenetic), optional_real(self.mean_silhouette(&partition, &delta)), ari_text(self.label_ari(&partition))));
        }
        lines
    }
    fn cophenetic_part(&self) -> Vec<String> {
        let mut lines = vec!["cophenetic_matrix".to_owned(), "linkage ".to_owned() + &self.settings.linkages.iter().map(|method| method.name()).collect::<Vec<_>>().join(" ")];
        for first in &self.results { lines.push(format!("{} {}", first.method.name(), reals(self.results.iter().map(|second| correlation(&first.cophenetic, &second.cophenetic))))); }
        lines
    }
    fn agreement_part(&self) -> Vec<String> {
        let mut lines = vec![format!("agreement k {}", self.classes.len()), "linkage ".to_owned() + &self.settings.linkages.iter().map(|method| method.name()).collect::<Vec<_>>().join(" ")];
        for first in &self.results { lines.push(format!("{} {}", first.method.name(), reals(self.results.iter().map(|second| partition_ari(&first.label_partition, &second.label_partition).value())))); }
        lines
    }
    fn summary_part(&self) -> Vec<String> {
        let mut ranking: Vec<usize> = (0..self.results.len()).collect();
        ranking.sort_by(|&a, &b| four_digit(self.results[b].correlation).total_cmp(&four_digit(self.results[a].correlation)).then(a.cmp(&b)));
        let mut lines = vec!["summary".to_owned(), "cophenetic_ranking ".to_owned() + &ranking.iter().map(|&r| self.results[r].method.name()).collect::<Vec<_>>().join(" ")];
        for (position, &k) in self.settings.cut_counts.iter().enumerate() {
            let mut best = 0;
            for r in 1..self.results.len() { if self.results[r].count_cuts[position].ari.greater(self.results[best].count_cuts[position].ari) { best = r; } }
            lines.push(format!("best_ari k {k} {} {}", self.results[best].method.name(), ari_text(self.results[best].count_cuts[position].ari)));
        }
        for result in &self.results {
            let mut best = 0;
            for position in 1..self.settings.cut_counts.len() { if four_digit(result.count_cuts[position].silhouette.unwrap()) > four_digit(result.count_cuts[best].silhouette.unwrap()) { best = position; } }
            lines.push(format!("best_silhouette {} k {} {}", result.method.name(), self.settings.cut_counts[best], optional_real(result.count_cuts[best].silhouette)));
        }
        lines.push(format!("selected {} k {}", self.chosen().method.name(), self.kappa()));
        lines
    }
    fn validation_report(&self) -> Vec<String> {
        let mut parts = vec![self.data_part(), self.correlation_part(), self.histogram_part()];
        for result in &self.results { parts.push(self.linkage_part(result)); }
        if let Some(single) = self.results.iter().find(|result| result.method == Linkage::Single) { parts.push(self.mst_part(single)); }
        parts.extend([self.compare_part(), self.cophenetic_part(), self.agreement_part(), self.summary_part()]);
        join_parts(parts)
    }
    fn separation(&self, first: &[usize], second: &[usize]) -> f64 {
        let mut best = f64::INFINITY;
        for &i in first { for &j in second { best = best.min(self.delta[i][j]); } }
        best
    }
    fn selection_part(&self) -> Vec<String> {
        let kappa = self.kappa();
        let members = self.members();
        let table = self.class_table(self.selected());
        let silhouettes = silhouette_values(self.selected(), kappa, &self.delta);
        let mut lines = vec![format!("selected linkage {} k {kappa} ari {} silhouette {}", self.chosen().method.name(), ari_text(self.selected_cut().ari), optional_real(self.selected_cut().silhouette))];
        for (g, group) in members.iter().enumerate() {
            let size = group.len();
            let silhouette = sequential_sum(group.iter().map(|&i| silhouettes[i])) / size as f64;
            let majority = majority_class(&table[g]);
            let count = table[g][majority];
            let means: Vec<f64> = (0..self.features.len()).map(|f| sequential_sum(group.iter().map(|&i| self.raw[i][f])) / size as f64).collect();
            let mut medoid = group[0];
            let mut medoid_sum = f64::INFINITY;
            for &i in group {
                let total = sequential_sum(group.iter().map(|&j| self.delta[i][j]));
                if total < medoid_sum { medoid = i; medoid_sum = total; }
            }
            let mut widest: Option<(usize, usize)> = None;
            for (position, &i) in group.iter().enumerate() { for &j in &group[position + 1..] {
                if widest.map_or(true, |(a, b)| self.delta[i][j] > self.delta[a][b]) { widest = Some((i, j)); }
            } }
            let diameter = widest.map_or_else(|| "0.0000 - -".to_owned(), |pair| self.pair_text(pair));
            let mut nearest = 0;
            let mut separation = f64::INFINITY;
            for (h, other) in members.iter().enumerate() { if h != g {
                let value = self.separation(group, other);
                if value < separation { nearest = h; separation = value; }
            } }
            lines.push(format!("cluster {} size {size} silhouette {} majority {} purity {count}/{size} {}", g + 1, real(silhouette), self.classes[majority], real(count as f64 / size as f64)));
            lines.push("  mean ".to_owned() + &reals(means));
            lines.push(format!("  medoid {} diameter {diameter} nearest {} separation {}", self.ids[medoid], nearest + 1, real(separation)));
        }
        lines
    }
    fn centroid_part(&self) -> Vec<String> {
        let centers = self.centroids(self.selected());
        let mut lines = vec!["centroid_distances".to_owned()];
        for (g, first) in centers.iter().enumerate() { lines.push(format!("{} {}", g + 1, reals(centers.iter().map(|second| squared_distance(first, second).sqrt())))); }
        lines
    }
    fn profile_part(&self) -> Vec<String> {
        let width = self.features.iter().map(String::len).max().unwrap();
        let mut lines = vec!["profile_bars".to_owned()];
        for (g, group) in self.members().iter().enumerate() {
            lines.push(format!("cluster {}", g + 1));
            for (f, name) in self.features.iter().enumerate() {
                let zeta = sequential_sum(group.iter().map(|&i| (self.raw[i][f] - self.means[f]) / self.deviations[f])) / group.len() as f64;
                let bar = "#".repeat(10.min((zeta.abs() * 4.0).floor() as usize));
                let (left, right) = if zeta < 0.0 { (format!("{bar:>10}"), " ".repeat(10)) } else { (" ".repeat(10), format!("{bar:<10}")) };
                lines.push(format!("{name:<width$} {left}|{right} {}", real(zeta)));
            }
        }
        lines
    }
    fn contingency_part(&self) -> Vec<String> {
        let table = self.class_table(self.selected());
        let mut lines = vec!["contingency".to_owned(), format!("cluster {} total", self.classes.join(" "))];
        for (g, row) in table.iter().enumerate() { lines.push(format!("{} {} {}", g + 1, integers(row), row.iter().sum::<i64>())); }
        let totals: Vec<i64> = (0..self.classes.len()).map(|t| table.iter().map(|row| row[t]).sum()).collect();
        lines.push(format!("total {} {}", integers(&totals), self.n));
        let matches = self.match_count(self.selected());
        lines.push(format!("purity {matches}/{} {}", self.n, real(matches as f64 / self.n as f64)));
        lines
    }
    fn misplaced_part(&self) -> Vec<String> {
        let table = self.class_table(self.selected());
        let majority: Vec<usize> = table.iter().map(|row| majority_class(row)).collect();
        let mut lines = vec!["misplaced".to_owned()];
        let mut count = 0;
        for (i, &number) in self.selected().iter().enumerate() {
            if self.targets[i] != majority[number - 1] {
                count += 1;
                lines.push(format!("{} label {} cluster {number} majority {}", self.ids[i], self.labels[i], self.classes[majority[number - 1]]));
            }
        }
        lines.push(format!("count {count}"));
        lines
    }
    fn weakest_part(&self) -> Vec<String> {
        let silhouettes = silhouette_values(self.selected(), self.kappa(), &self.delta);
        let mut order: Vec<usize> = (0..self.n).collect();
        order.sort_by(|&a, &b| silhouettes[a].total_cmp(&silhouettes[b]).then(a.cmp(&b)));
        let mut lines = vec!["weakest".to_owned()];
        for &i in &order[..self.settings.list_size] { lines.push(format!("{} label {} cluster {} silhouette {}", self.ids[i], self.labels[i], self.selected()[i], real(silhouettes[i]))); }
        lines
    }
    fn feature_part(&self) -> Vec<String> {
        let members = self.members();
        let mut ratios = Vec::new();
        for f in 0..self.features.len() {
            let overall = sequential_sum(self.vectors.iter().map(|vector| vector[f])) / self.n as f64;
            let means: Vec<f64> = members.iter().map(|group| sequential_sum(group.iter().map(|&i| self.vectors[i][f])) / group.len() as f64).collect();
            let between = sequential_sum(members.iter().zip(&means).map(|(group, &mean)| group.len() as f64 * (mean - overall) * (mean - overall)));
            let within = sequential_sum(self.selected().iter().enumerate().map(|(i, &number)| (self.vectors[i][f] - means[number - 1]) * (self.vectors[i][f] - means[number - 1])));
            ratios.push((between / (self.kappa() - 1) as f64) / (within / (self.n - self.kappa()) as f64));
        }
        let mut ranking: Vec<usize> = (0..ratios.len()).collect();
        ranking.sort_by(|&a, &b| four_digit(ratios[b]).total_cmp(&four_digit(ratios[a])).then(a.cmp(&b)));
        let mut lines = vec!["features".to_owned()];
        for (rank, &f) in ranking.iter().enumerate() { lines.push(format!("{} {} f_ratio {}", rank + 1, self.features[f], real(ratios[f]))); }
        lines
    }
    fn class_counts(&self, tree: &Tree, node: usize) -> String {
        let mut counts = vec![0; self.classes.len()];
        for &i in &tree.members[node] { counts[self.targets[i]] += 1; }
        counts.iter().map(ToString::to_string).collect::<Vec<_>>().join("/")
    }
    fn top_merges_part(&self) -> Vec<String> {
        let tree = &self.chosen().tree;
        let mut lines = vec!["top_merges".to_owned()];
        for step in self.n - self.settings.inconsistency_count - 1..self.n - 1 {
            let merge = &tree.merges[step];
            lines.push(format!("step {} height {} a {} {} {} b {} {} {}", step + 1, real(merge.height), merge.a, tree.members[merge.a].len(), self.class_counts(tree, merge.a), merge.b, tree.members[merge.b].len(), self.class_counts(tree, merge.b)));
        }
        lines
    }
    fn drop_feature_part(&self) -> Vec<String> {
        let mut lines = vec!["drop_feature".to_owned()];
        for (f, name) in self.features.iter().enumerate() {
            let reduced: Vec<Vec<f64>> = self.vectors.iter().map(|vector| vector.iter().enumerate().filter_map(|(j, &value)| if j == f { None } else { Some(value) }).collect()).collect();
            let delta = distance_matrix(&reduced, self.settings.distance);
            let partition = Tree::new(agglomerate(&delta, self.chosen().method), self.n).cut_into(self.kappa());
            lines.push(format!("{name} ari_selected {} ari_labels {}", ari_text(partition_ari(&partition, self.selected())), ari_text(self.label_ari(&partition))));
        }
        lines
    }
    fn refinement_part(&self) -> Vec<String> {
        let limit = self.settings.refine_iterations;
        let mut centers = self.centroids(self.selected());
        let mut previous = self.selected().to_vec();
        let mut iterations = limit;
        for t in 1..=limit {
            let assignment: Vec<usize> = self.vectors.iter().map(|vector| {
                let mut best = 0;
                let mut distance = squared_distance(vector, &centers[0]);
                for g in 1..centers.len() { let value = squared_distance(vector, &centers[g]); if value < distance { best = g; distance = value; } }
                best + 1
            }).collect();
            if assignment == previous { iterations = t; break; }
            for (g, group) in cluster_members(&assignment, self.kappa()).iter().enumerate() {
                if !group.is_empty() { centers[g] = centroid(&group.iter().map(|&i| self.vectors[i].clone()).collect::<Vec<_>>()); }
            }
            previous = assignment;
        }
        let changed = self.selected().iter().zip(&previous).filter(|(before, after)| before != after).count();
        let sizes: Vec<usize> = cluster_members(&previous, self.kappa()).iter().map(Vec::len).collect();
        vec![format!("refinement max_iterations {limit}"), format!("iterations {iterations} changed {changed} wss {} -> {}", real(self.within_sum(self.selected())), real(self.within_sum(&previous))), format!("sizes {} silhouette {}", integers(&sizes), optional_real(self.mean_silhouette(&previous, &self.delta))), format!("ari_selected {} ari_labels {}", ari_text(partition_ari(&previous, self.selected())), ari_text(self.label_ari(&previous)))]
    }
    fn jaccard(&self, partition: &[usize], restricted: &[usize]) -> Vec<f64> {
        let rows: Vec<usize> = restricted.iter().map(|&number| number - 1).collect();
        let columns: Vec<usize> = partition.iter().map(|&number| number - 1).collect();
        let table = contingency_table(&rows, &columns, self.kappa(), *partition.iter().max().unwrap());
        let totals: Vec<i64> = (0..table[0].len()).map(|h| table.iter().map(|row| row[h]).sum()).collect();
        table.iter().map(|row| {
            let size: i64 = row.iter().sum();
            let mut best = Fraction { numerator: 0, denominator: 1 };
            if size > 0 { for (h, &common) in row.iter().enumerate() {
                let candidate = Fraction { numerator: common, denominator: size + totals[h] - common };
                if candidate.greater(best) { best = candidate; }
            } }
            best.value()
        }).collect()
    }
    fn stability_part(&self) -> Vec<String> {
        let settings = &self.settings;
        let mut generator = Minstd { state: settings.seed };
        let size = self.n * settings.percent / 100;
        let mut aris = Vec::new();
        let mut jaccards = Vec::new();
        let mut lines = vec![format!("stability replicates {} percent {} seed {}", settings.replicates, settings.percent, settings.seed)];
        for b in 1..=settings.replicates {
            let mut array: Vec<usize> = (0..self.n).collect();
            for t in 0..size { let j = t + (generator.draw() % (self.n - t) as i64) as usize; array.swap(t, j); }
            let mut sample = array[..size].to_vec();
            sample.sort_unstable();
            let delta: Vec<Vec<f64>> = sample.iter().map(|&u| sample.iter().map(|&w| self.delta[u][w]).collect()).collect();
            let partition = Tree::new(agglomerate(&delta, self.chosen().method), size).cut_into(self.kappa());
            let restricted: Vec<usize> = sample.iter().map(|&u| self.selected()[u]).collect();
            let ari = partition_ari(&partition, &restricted);
            let jaccard = self.jaccard(&partition, &restricted);
            lines.push(format!("replicate {b} size {size} ari {} jaccard {}", ari_text(ari), reals(jaccard.iter().copied())));
            aris.push(ari.value());
            jaccards.push(jaccard);
        }
        lines.push(format!("mean_ari {}", real(sequential_sum(aris) / settings.replicates as f64)));
        lines.push("mean_jaccard ".to_owned() + &reals((0..self.kappa()).map(|g| sequential_sum(jaccards.iter().map(|values| values[g])) / settings.replicates as f64)));
        lines
    }
    fn distance_map_part(&self) -> Vec<String> {
        let order = &self.chosen().tree.order;
        let frame = "+".to_owned() + &"-".repeat(self.n) + "+";
        let mut lines = vec![format!("distance_map {}", self.chosen().method.name()), frame.clone()];
        let shades = b"@%#*+=-:. ";
        for &u in order {
            let cells: String = order.iter().map(|&w| shades[histogram_bin(self.delta[u][w], self.distance_max)] as char).collect();
            lines.push(format!("|{cells}|"));
        }
        lines.push(frame);
        lines
    }
    fn profiles_report(&self) -> Vec<String> {
        join_parts(vec![self.selection_part(), self.centroid_part(), self.profile_part(), self.contingency_part(), self.misplaced_part(), self.weakest_part(), self.feature_part(), self.top_merges_part(), self.drop_feature_part(), self.refinement_part(), self.stability_part(), self.distance_map_part()])
    }
}

fn main() -> io::Result<()> {
    let (features, observations) = read_observations()?;
    let settings = read_settings()?;
    let study = Study::new(features, observations, settings);
    std::fs::create_dir_all("output")?;
    write_lines("linkage.csv", &study.linkage_table())?;
    write_lines("clusters.csv", &study.clusters_table())?;
    write_lines("dendrogram.txt", &study.dendrogram_report())?;
    write_lines("trees.txt", &study.trees_report())?;
    write_lines("validation.txt", &study.validation_report())?;
    write_lines("profiles.txt", &study.profiles_report())?;
    Ok(())
}
