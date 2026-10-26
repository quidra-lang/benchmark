mod transactions;
mod features;
mod kmeans;
mod validation;
mod profiles;
mod report;

use std::cmp::Reverse;
use std::collections::BTreeMap;
use std::{fs, io};
use features::{Customer, FEATURE_NAMES, Point, SQRT_FEATURES, correlation, eligible_customers, mean, ordered_sum, sample_sd, standardization, standardize};
use kmeans::{LloydResult, cluster_center, cluster_centers, cluster_sizes, lloyd, mean_point, squared_distance, sse};
use profiles::{Rule, original_scale, read_rules, rule_number};
use report::{amount, four_decimal, real, reals, write_lines};
use transactions::{Order, Params, TransactionData, group_orders, orders_by_customer, read_params, read_transactions};
use validation::adjusted_rand_index;

struct Minstd { state: i64 }
impl Minstd {
    fn draw(&mut self) -> i64 {
        self.state = 48271 * self.state % 2147483647;
        self.state
    }
}

fn nearest_gaps(points: &[Point], chosen: &[usize]) -> Vec<f64> {
    points.iter().map(|point| chosen.iter().map(|&index| squared_distance(point, &points[index])).fold(f64::INFINITY, f64::min)).collect()
}

fn maximin(points: &[Point], k: usize, run: usize) -> Vec<usize> {
    let center = mean_point(points);
    let spread: Vec<_> = points.iter().map(|point| squared_distance(point, &center)).collect();
    let mut order: Vec<_> = (0..points.len()).collect();
    order.sort_by(|&first, &second| spread[first].total_cmp(&spread[second]).then(first.cmp(&second)));
    let mut chosen = vec![order[run - 1]];
    while chosen.len() < k {
        let gaps = nearest_gaps(points, &chosen);
        let mut best = 0;
        for index in 1..points.len() { if gaps[index] > gaps[best] { best = index; } }
        chosen.push(best);
    }
    chosen
}

fn initial_seeds(method: &str, points: &[Point], k: usize, run: usize, generator: &mut Minstd) -> Vec<usize> {
    if method == "maximin" { return maximin(points, k, run); }
    let mut chosen = Vec::new();
    if method == "forgy" {
        while chosen.len() < k {
            let index = (generator.draw() % points.len() as i64) as usize;
            if !chosen.contains(&index) { chosen.push(index); }
        }
        return chosen;
    }
    chosen.push((generator.draw() % points.len() as i64) as usize);
    while chosen.len() < k {
        let gaps = nearest_gaps(points, &chosen);
        let threshold = (generator.draw() as f64 / 2147483647.0) * ordered_sum(&gaps);
        let mut total = 0.0;
        let mut next = None;
        for (index, &gap) in gaps.iter().enumerate() {
            total += gap;
            if total > threshold { next = Some(index); break; }
        }
        chosen.push(next.unwrap_or_else(|| gaps.iter().rposition(|&gap| gap > 0.0).unwrap()));
    }
    chosen
}

struct Improvement {
    labels: Vec<usize>,
    passes: usize,
    transfers: usize,
    sse: f64,
}

fn improve(points: &[Point], original: &[usize], k: usize, maximum: usize) -> Improvement {
    let mut labels = original.to_vec();
    let mut sizes = cluster_sizes(&labels, k);
    let mut centers = cluster_centers(points, &labels, k);
    let mut passes = 0;
    let mut transfers = 0;
    let mut moved = true;
    while moved && passes < maximum {
        moved = false;
        passes += 1;
        for (index, point) in points.iter().enumerate() {
            let own = labels[index];
            if sizes[own] == 1 { continue; }
            let removal = (sizes[own] as f64 / (sizes[own] - 1) as f64) * squared_distance(point, &centers[own]);
            let mut target = None;
            let mut target_cost = 0.0;
            for cluster in 0..k {
                if cluster == own { continue; }
                let cost = (sizes[cluster] as f64 / (sizes[cluster] + 1) as f64) * squared_distance(point, &centers[cluster]);
                if target.is_none() || cost < target_cost { target = Some(cluster); target_cost = cost; }
            }
            if target_cost < removal {
                let target = target.unwrap();
                labels[index] = target;
                sizes[own] -= 1;
                sizes[target] += 1;
                centers[own] = cluster_center(points, &labels, own);
                centers[target] = cluster_center(points, &labels, target);
                transfers += 1;
                moved = true;
            }
        }
    }
    let refined = sse(points, &labels, &cluster_centers(points, &labels, k));
    Improvement { labels, passes, transfers, sse: refined }
}

struct Run {
    method: String,
    number: usize,
    seeds: Vec<usize>,
    lloyd: LloydResult,
    lloyd_sse: f64,
    improved: Improvement,
}
impl Run {
    fn new(method: String, number: usize, seeds: Vec<usize>, points: &[Point], maximum: usize) -> Self {
        let initial: Vec<_> = seeds.iter().map(|&index| points[index].clone()).collect();
        let lloyd = lloyd(points, &initial, maximum);
        let lloyd_sse = sse(points, &lloyd.labels, &lloyd.centers);
        let improved = improve(points, &lloyd.labels, seeds.len(), maximum);
        Self { method, number, seeds, lloyd, lloyd_sse, improved }
    }
}

struct Solution {
    k: usize,
    members: Vec<Vec<usize>>,
    sizes: Vec<usize>,
    labels: Vec<usize>,
    centers: Vec<Point>,
    sse: f64,
}
impl Solution {
    fn new(points: &[Point], original: &[usize], k: usize) -> Self {
        let mut members: Vec<Vec<_>> = (0..k).map(|cluster| (0..original.len()).filter(|&index| original[index] == cluster).collect()).collect();
        members.sort_by_key(|group| (Reverse(group.len()), group[0]));
        let sizes = members.iter().map(Vec::len).collect();
        let mut labels = vec![0; original.len()];
        for (cluster, group) in members.iter().enumerate() { for &index in group { labels[index] = cluster; } }
        let centers = cluster_centers(points, &labels, k);
        let within = sse(points, &labels, &centers);
        Self { k, members, sizes, labels, centers, sse: within }
    }
}

struct Candidate {
    k: usize,
    runs: Vec<Run>,
    method_bests: Vec<usize>,
    best: usize,
    solution: Solution,
    silhouettes: Vec<f64>,
    silhouette: f64,
    harabasz: f64,
    bouldin: f64,
    elbow: f64,
    hartigan: Option<f64>,
    rule_numbers: Vec<usize>,
    names: Vec<String>,
}

fn rfm_scores(customers: &[Customer]) -> Vec<[usize; 3]> {
    customers.iter().map(|customer| {
        let older = customers.iter().filter(|other| other.recency > customer.recency).count();
        let fewer = customers.iter().filter(|other| other.frequency < customer.frequency).count();
        let smaller = customers.iter().filter(|other| other.spend < customer.spend).count();
        [older, fewer, smaller].map(|rank| 1 + 5 * rank / customers.len())
    }).collect()
}
fn gini(spends: &[i64]) -> f64 {
    let mut ordered = spends.to_vec();
    ordered.sort_unstable();
    let count = spends.len() as i64;
    let total: i64 = ordered.iter().sum();
    let weighted: i64 = ordered.iter().enumerate().map(|(index, &spend)| (index as i64 + 1) * spend).sum();
    (2 * weighted - (count + 1) * total) as f64 / (count * total) as f64
}
fn lower_median<T: PartialOrd + Clone>(values: &[T]) -> T {
    let mut ordered = values.to_vec();
    ordered.sort_by(|first, second| first.partial_cmp(second).unwrap());
    ordered[(ordered.len() - 1) / 2].clone()
}
fn category_totals(customers: &[&Customer]) -> BTreeMap<String, i64> {
    let mut totals = BTreeMap::new();
    for customer in customers { for (category, &spend) in &customer.category_spend { *totals.entry(category.clone()).or_insert(0) += spend; } }
    totals
}
fn category_ranking(totals: &BTreeMap<String, i64>) -> Vec<String> {
    let mut categories: Vec<_> = totals.keys().filter(|category| totals[*category] > 0).cloned().collect();
    categories.sort_by(|first, second| totals[second].cmp(&totals[first]).then(first.cmp(second)));
    categories
}
fn yes_no(value: bool) -> &'static str { if value { "yes" } else { "no" } }
fn integers(values: &[usize]) -> String { values.iter().map(usize::to_string).collect::<Vec<_>>().join(" ") }
fn join_blocks(blocks: Vec<Vec<String>>) -> Vec<String> {
    let mut lines = Vec::new();
    for block in blocks { if !lines.is_empty() { lines.push(String::new()); } lines.extend(block); }
    lines
}

struct Analysis {
    params: Params,
    data: TransactionData,
    rules: Vec<Rule>,
    generator: Minstd,
    reference_orders: Vec<Order>,
    customer_orders: BTreeMap<String, Vec<Order>>,
    customers: Vec<Customer>,
    means: Point,
    sds: Point,
    points: Vec<Point>,
    candidates: Vec<Candidate>,
    votes: Vec<(&'static str, usize)>,
    selected: usize,
    final_votes: usize,
    distances: Vec<f64>,
    others: Vec<(usize, f64)>,
    scores: Vec<[usize; 3]>,
    codes: Vec<String>,
    total_spend: i64,
    overall_categories: BTreeMap<String, i64>,
    segment_spends: Vec<i64>,
    segment_categories: Vec<BTreeMap<String, i64>>,
    rankings: Vec<Vec<String>>,
    segment_sse: Vec<f64>,
    jaccards: Vec<Vec<f64>>,
}

impl Analysis {
    fn new(params: Params, data: TransactionData, rules: Vec<Rule>) -> Self {
        let generator = Minstd { state: params.seed };
        let reference_orders = group_orders(&data.valid_rows, 1, params.reference_day);
        let customer_orders = orders_by_customer(&reference_orders);
        let customers = eligible_customers(&reference_orders, params.reference_day);
        let transformed: Vec<_> = customers.iter().map(Customer::transformed).collect();
        let (means, sds) = standardization(&transformed);
        let points = transformed.iter().map(|values| standardize(values, &means, &sds)).collect();
        Self { params, data, rules, generator, reference_orders, customer_orders, customers, means, sds, points,
            candidates: Vec::new(), votes: Vec::new(), selected: 0, final_votes: 0, distances: Vec::new(), others: Vec::new(),
            scores: Vec::new(), codes: Vec::new(), total_spend: 0, overall_categories: BTreeMap::new(), segment_spends: Vec::new(),
            segment_categories: Vec::new(), rankings: Vec::new(), segment_sse: Vec::new(), jaccards: Vec::new() }
    }
    fn final_candidate(&self) -> &Candidate { &self.candidates[self.selected] }
    fn ids(&self, numbers: &[usize]) -> String { numbers.iter().map(|&number| self.customers[number].id.as_str()).collect::<Vec<_>>().join(" ") }
    fn search(&mut self, k: usize) -> Candidate {
        let mut runs: Vec<Run> = Vec::new();
        let mut method_bests = Vec::new();
        for method in &self.params.methods {
            let start = runs.len();
            let mut best = start;
            for number in 1..=self.params.restarts {
                let seeds = initial_seeds(method, &self.points, k, number, &mut self.generator);
                let run = Run::new(method.clone(), number, seeds, &self.points, self.params.max_iterations);
                let index = runs.len();
                runs.push(run);
                if four_decimal(runs[index].improved.sse) < four_decimal(runs[best].improved.sse) { best = index; }
            }
            method_bests.push(best);
        }
        let mut best = method_bests[0];
        for &index in &method_bests[1..] { if four_decimal(runs[index].improved.sse) < four_decimal(runs[best].improved.sse) { best = index; } }
        let solution = Solution::new(&self.points, &runs[best].improved.labels, k);
        Candidate { k, runs, method_bests, best, solution, silhouettes: Vec::new(), silhouette: 0.0, harabasz: 0.0,
            bouldin: 0.0, elbow: 0.0, hartigan: None, rule_numbers: Vec::new(), names: Vec::new() }
    }
    fn analyze(&mut self) {
        for k in self.params.k_min..=self.params.k_max { let candidate = self.search(k); self.candidates.push(candidate); }
        let table = validation::distance_table(&self.points);
        let first = self.candidates[0].solution.sse;
        let last = self.candidates.last().unwrap().solution.sse;
        for index in 0..self.candidates.len() {
            let next = self.candidates.get(index + 1).map(|candidate| candidate.solution.sse);
            let candidate = &mut self.candidates[index];
            let solution = &candidate.solution;
            candidate.silhouettes = validation::silhouettes(&table, &solution.labels, &solution.sizes);
            candidate.silhouette = ordered_sum(&candidate.silhouettes) / self.customers.len() as f64;
            candidate.harabasz = validation::calinski_harabasz(&self.points, &solution.centers, &solution.sizes, solution.sse);
            candidate.bouldin = validation::davies_bouldin(&self.points, &solution.labels, &solution.centers, &solution.sizes);
            candidate.elbow = validation::elbow(candidate.k, self.params.k_min, self.params.k_max, solution.sse, first, last);
            candidate.hartigan = next.map(|next| validation::hartigan(solution.sse, next, self.customers.len(), candidate.k));
            for center in &solution.centers {
                let number = rule_number(&self.rules, center);
                let repeats = candidate.rule_numbers.iter().filter(|&&previous| previous == number).count();
                candidate.rule_numbers.push(number);
                let name = self.rules[number].name.clone();
                candidate.names.push(if repeats == 0 { name } else { format!("{name}_{}", repeats + 1) });
            }
        }
        self.choose_k();
        self.describe_final();
        self.subsample_jaccards();
    }
    fn choose_k(&mut self) {
        let mut elbow = 1;
        let mut silhouette = 0;
        let mut harabasz = 0;
        let mut bouldin = 0;
        for index in 0..self.candidates.len() {
            let candidate = &self.candidates[index];
            if index > 0 && index + 1 < self.candidates.len() && four_decimal(candidate.elbow) > four_decimal(self.candidates[elbow].elbow) { elbow = index; }
            if four_decimal(candidate.silhouette) > four_decimal(self.candidates[silhouette].silhouette) { silhouette = index; }
            if four_decimal(candidate.harabasz) > four_decimal(self.candidates[harabasz].harabasz) { harabasz = index; }
            if four_decimal(candidate.bouldin) < four_decimal(self.candidates[bouldin].bouldin) { bouldin = index; }
        }
        let hartigan = self.candidates.iter().position(|candidate| candidate.hartigan.is_some_and(|value| value <= 10.0)).unwrap_or(self.candidates.len() - 1);
        self.votes = vec![("elbow", elbow), ("silhouette", silhouette), ("calinski_harabasz", harabasz), ("davies_bouldin", bouldin), ("hartigan", hartigan)];
        let mut counts = vec![0; self.candidates.len()];
        for &(_, index) in &self.votes { counts[index] += 1; }
        for index in 1..self.candidates.len() {
            if counts[index] > counts[self.selected] || (counts[index] == counts[self.selected] && four_decimal(self.candidates[index].silhouette) > four_decimal(self.candidates[self.selected].silhouette)) { self.selected = index; }
        }
        self.final_votes = counts[self.selected];
    }
    fn describe_final(&mut self) {
        let candidate = &self.candidates[self.selected];
        let solution = &candidate.solution;
        for (point, &label) in self.points.iter().zip(&solution.labels) {
            let squared: Vec<_> = solution.centers.iter().map(|center| squared_distance(point, center)).collect();
            let other = (0..solution.k).filter(|&cluster| cluster != label).min_by(|&a, &b| squared[a].total_cmp(&squared[b]).then(a.cmp(&b))).unwrap();
            self.distances.push(squared[label].sqrt());
            self.others.push((other, squared[other].sqrt()));
        }
        self.scores = rfm_scores(&self.customers);
        self.codes = self.scores.iter().map(|scores| scores.iter().map(usize::to_string).collect::<String>()).collect();
        self.total_spend = self.customers.iter().map(|customer| customer.spend).sum();
        self.overall_categories = category_totals(&self.customers.iter().collect::<Vec<_>>());
        for (segment, members) in solution.members.iter().enumerate() {
            let customers: Vec<_> = members.iter().map(|&index| &self.customers[index]).collect();
            self.segment_spends.push(customers.iter().map(|customer| customer.spend).sum());
            let totals = category_totals(&customers);
            self.rankings.push(category_ranking(&totals));
            self.segment_categories.push(totals);
            let mut within = 0.0;
            for &index in members { within += squared_distance(&self.points[index], &solution.centers[segment]); }
            self.segment_sse.push(within);
        }
    }
    fn subsample_jaccards(&mut self) {
        let solution = &self.candidates[self.selected].solution;
        let size = self.customers.len() * self.params.subsample_percent / 100;
        self.jaccards = vec![Vec::new(); solution.k];
        for _ in 0..self.params.subsamples {
            let mut order: Vec<_> = (0..self.customers.len()).collect();
            for index in 0..size {
                let other = index + (self.generator.draw() % (self.customers.len() - index) as i64) as usize;
                order.swap(index, other);
            }
            let mut sample = order[..size].to_vec();
            sample.sort_unstable();
            let points: Vec<_> = sample.iter().map(|&number| self.points[number].clone()).collect();
            let result = lloyd(&points, &solution.centers, self.params.max_iterations);
            for segment in 0..solution.k {
                let mut best: f64 = 0.0;
                for cluster in 0..solution.k {
                    let mut both = 0;
                    let mut either = 0;
                    for (&number, &label) in sample.iter().zip(&result.labels) {
                        let member = solution.labels[number] == segment;
                        if member && label == cluster { both += 1; }
                        if member || label == cluster { either += 1; }
                    }
                    if either > 0 { best = best.max(both as f64 / either as f64); }
                }
                self.jaccards[segment].push(best);
            }
        }
    }
    fn recommendation(&self, number: usize) -> &str {
        let label = self.final_candidate().solution.labels[number];
        for category in &self.rankings[label] { if self.customers[number].category_spend.get(category).copied().unwrap_or(0) <= 0 { return category; } }
        "-"
    }
    fn features_lines(&self) -> Vec<String> {
        let mut lines = vec!["customer,recency,frequency,monetary,basket,categories,tenure,z_recency,z_frequency,z_monetary,z_basket,z_categories,z_tenure".to_owned()];
        for (customer, point) in self.customers.iter().zip(&self.points) {
            let mut fields = vec![customer.id.clone(), customer.recency.to_string(), customer.frequency.to_string(), amount(customer.spend), real(customer.basket), customer.categories.to_string(), customer.tenure.to_string()];
            fields.extend(point.iter().map(|&value| real(value)));
            lines.push(fields.join(","));
        }
        lines
    }
    fn run_summary(&self, run: &Run) -> String { format!("{} restart {} sse {}", run.method, run.number, real(run.improved.sse)) }
    fn runs_lines(&self) -> Vec<String> {
        let blocks = self.candidates.iter().map(|candidate| {
            let mut lines = vec![format!("k {}", candidate.k)];
            for run in &candidate.runs {
                lines.push(format!("run {} {} seeds {} iterations {} converged {} reseeds {} sse {} passes {} transfers {} refined {}",
                    run.method, run.number, self.ids(&run.seeds), run.lloyd.iterations, yes_no(run.lloyd.converged), run.lloyd.reseeds, real(run.lloyd_sse), run.improved.passes, run.improved.transfers, real(run.improved.sse)));
            }
            for &index in &candidate.method_bests { lines.push(format!("best {}", self.run_summary(&candidate.runs[index]))); }
            lines.push(format!("chosen {}", self.run_summary(&candidate.runs[candidate.best])));
            lines.push(format!("sizes {}", integers(&candidate.solution.sizes)));
            lines
        }).collect();
        join_blocks(blocks)
    }
    fn selection_lines(&self) -> Vec<String> {
        let mut indices = vec!["indices".to_owned()];
        let mut names = vec!["segments".to_owned()];
        let mut stability = vec!["stability".to_owned()];
        for (position, candidate) in self.candidates.iter().enumerate() {
            indices.push(format!("k={} sse {} elbow {} silhouette {} calinski_harabasz {} davies_bouldin {} hartigan {}", candidate.k, real(candidate.solution.sse), real(candidate.elbow), real(candidate.silhouette), real(candidate.harabasz), real(candidate.bouldin), candidate.hartigan.map(real).unwrap_or_else(|| "-".to_owned())));
            let segments = candidate.names.iter().zip(&candidate.solution.sizes).map(|(name, size)| format!("{name}:{size}")).collect::<Vec<_>>().join(" ");
            names.push(format!("k={} {segments}", candidate.k));
            let mut parts = vec![format!("k={}", candidate.k)];
            for (index, &first) in candidate.method_bests.iter().enumerate() {
                for &second in &candidate.method_bests[index + 1..] {
                    let a = &candidate.runs[first]; let b = &candidate.runs[second];
                    parts.push(format!("{}:{} {}", a.method, b.method, real(adjusted_rand_index(&a.improved.labels, &b.improved.labels))));
                }
            }
            parts.push("final".to_owned());
            for &index in &candidate.method_bests {
                let run = &candidate.runs[index];
                parts.push(format!("{} {}", run.method, real(adjusted_rand_index(&run.improved.labels, &candidate.solution.labels))));
            }
            if let Some(next) = self.candidates.get(position + 1) { parts.push(format!("next {}", real(adjusted_rand_index(&candidate.solution.labels, &next.solution.labels)))); }
            else { parts.push("next -".to_owned()); }
            stability.push(parts.join(" "));
        }
        let mut votes = vec!["votes".to_owned()];
        votes.extend(self.votes.iter().map(|&(criterion, index)| format!("{criterion} k={}", self.candidates[index].k)));
        votes.push(format!("chosen k={} votes {}", self.final_candidate().k, self.final_votes));
        join_blocks(vec![indices, votes, names, stability])
    }
    fn segments_lines(&self) -> Vec<String> {
        let candidate = self.final_candidate();
        let mut lines = vec!["customer,segment,name,distance,other,other_distance,silhouette,recommend".to_owned()];
        for (index, customer) in self.customers.iter().enumerate() {
            let label = candidate.solution.labels[index];
            let (other, distance) = self.others[index];
            lines.push(format!("{},{},{},{},{},{},{},{}", customer.id, label + 1, candidate.names[label], real(self.distances[index]), other + 1, real(distance), real(candidate.silhouettes[index]), self.recommendation(index)));
        }
        lines
    }
    fn related(&self, members: &[usize], k: usize) -> String {
        if k < self.params.k_min || k > self.params.k_max { return format!("k={k} -"); }
        let labels = &self.candidates[k - self.params.k_min].solution.labels;
        let mut counts = vec![0; k];
        for &number in members { counts[labels[number]] += 1; }
        let mut best = 0;
        for index in 1..k { if counts[index] > counts[best] { best = index; } }
        format!("k={k} segment {} shared {}", best + 1, counts[best])
    }
    fn segment_profile(&self, segment: usize) -> Vec<String> {
        let candidate = self.final_candidate();
        let solution = &candidate.solution;
        let members = &solution.members[segment];
        let customers: Vec<_> = members.iter().map(|&index| &self.customers[index]).collect();
        let size = members.len();
        let center = &solution.centers[segment];
        let spend = self.segment_spends[segment];
        let mut lines = vec![format!("segment {} {} rule {} size {size} share {} revenue {} revenue_share {}", segment + 1, candidate.names[segment], candidate.rule_numbers[segment] + 1, real(size as f64 / self.customers.len() as f64), amount(spend), real(spend as f64 / self.total_spend as f64)), format!("  center {}", reals(center))];
        let values = original_scale(center, &self.means, &self.sds);
        lines.push(format!("  value {}", FEATURE_NAMES.iter().zip(values).map(|(name, value)| format!("{name} {}", real(value))).collect::<Vec<_>>().join(" ")));
        let mut feature_order: Vec<_> = (0..6).collect();
        feature_order.sort_by(|&first, &second| center[second].abs().total_cmp(&center[first].abs()).then(first.cmp(&second)));
        let traits = feature_order[..2].iter().map(|&feature| format!("{}_{}", if center[feature] > 0.0 { "high" } else { "low" }, FEATURE_NAMES[feature])).collect::<Vec<_>>().join(" ");
        lines.push(format!("  traits {traits}"));
        lines.push(format!("  median recency {} frequency {} monetary {} basket {} categories {} tenure {}",
            lower_median(&customers.iter().map(|c| c.recency).collect::<Vec<_>>()), lower_median(&customers.iter().map(|c| c.frequency).collect::<Vec<_>>()),
            amount(lower_median(&customers.iter().map(|c| c.spend).collect::<Vec<_>>())), real(lower_median(&customers.iter().map(|c| c.basket).collect::<Vec<_>>())),
            lower_median(&customers.iter().map(|c| c.categories).collect::<Vec<_>>()), lower_median(&customers.iter().map(|c| c.tenure).collect::<Vec<_>>())));
        lines.push(format!("  related {} {}", self.related(members, solution.k - 1), self.related(members, solution.k + 1)));
        let mut top = members.clone();
        top.sort_by_key(|&number| (Reverse(self.customers[number].spend), number));
        let mut top_parts = vec!["  top_customers".to_owned()];
        for &number in top.iter().take(self.params.top_customers) { top_parts.push(self.customers[number].id.clone()); top_parts.push(amount(self.customers[number].spend)); }
        lines.push(top_parts.join(" "));
        let mut gaps = Vec::new();
        let mut overdue = 0;
        let mut bins = vec![0; self.params.order_bins.len() + 1];
        let mut gross = 0;
        let mut returned = 0;
        let mut cancelled = 0;
        for customer in &customers {
            if customer.frequency >= 2 {
                let active_days = customer.tenure - customer.recency;
                let intervals = customer.frequency - 1;
                gaps.push(active_days as f64 / intervals as f64);
                if customer.recency * intervals as i64 > self.params.overdue_factor * active_days { overdue += 1; }
            }
            for order in &customer.orders { bins[self.params.order_bins.iter().filter(|&&bound| order.net >= bound * 100).count()] += 1; }
            for order in &self.customer_orders[&customer.id] {
                if order.net <= 0 { cancelled += 1; }
                for row in &order.rows { if row.amount > 0 { gross += row.amount; } else { returned -= row.amount; } }
            }
        }
        let mean_gap = if gaps.is_empty() { "-".to_owned() } else { real(mean(&gaps)) };
        lines.push(format!("  cadence customers {} mean_gap {mean_gap} overdue {overdue}", gaps.len()));
        lines.push(format!("  order_sizes {}", integers(&bins)));
        lines.push(format!("  sse {} share {}", real(self.segment_sse[segment]), real(self.segment_sse[segment] / solution.sse)));
        lines.push(format!("  gini {}", real(gini(&customers.iter().map(|customer| customer.spend).collect::<Vec<_>>()))));
        lines.push(format!("  returns rate {} returned {} cancelled {cancelled}", real(returned as f64 / gross as f64), amount(returned)));
        let silhouettes: Vec<_> = members.iter().map(|&number| candidate.silhouettes[number]).collect();
        lines.push(format!("  silhouette {} negative {}", real(mean(&silhouettes)), silhouettes.iter().filter(|&&value| value < 0.0).count()));
        let score_means: Vec<_> = (0..3).map(|column| members.iter().map(|&number| self.scores[number][column]).sum::<usize>() as f64 / size as f64).collect();
        let mut codes = BTreeMap::new();
        for &number in members { *codes.entry(self.codes[number].as_str()).or_insert(0usize) += 1; }
        let (&mode, &count) = codes.iter().min_by_key(|(code, count)| (Reverse(**count), **code)).unwrap();
        lines.push(format!("  rfm r {} f {} m {} mode {mode} {count}", real(score_means[0]), real(score_means[1]), real(score_means[2])));
        let mut category_parts = vec!["  categories".to_owned()];
        for category in self.rankings[segment].iter().take(self.params.top_categories) {
            let share = self.segment_categories[segment][category] as f64 / spend as f64;
            let lift = share / (self.overall_categories[category] as f64 / self.total_spend as f64);
            category_parts.extend([category.clone(), real(share), real(lift)]);
        }
        lines.push(category_parts.join(" "));
        let outliers = if size < 2 { Vec::new() } else {
            let distances: Vec<_> = members.iter().map(|&number| self.distances[number]).collect();
            let limit = mean(&distances) + self.params.outlier_sd * sample_sd(&distances);
            members.iter().copied().filter(|&number| self.distances[number] > limit).collect::<Vec<_>>()
        };
        let mut outlier_parts = vec!["  outliers".to_owned(), outliers.len().to_string()];
        outlier_parts.extend(outliers.iter().map(|&number| self.customers[number].id.clone()));
        lines.push(outlier_parts.join(" "));
        lines
    }
    fn profiles_lines(&self) -> Vec<String> {
        let candidate = self.final_candidate();
        let solution = &candidate.solution;
        let k = solution.k;
        let numbers = integers(&(1..=k).collect::<Vec<_>>());
        let all_spends: Vec<_> = self.customers.iter().map(|customer| customer.spend).collect();
        let mut blocks = vec![vec![format!("segments k={k} customers {} revenue {} gini {}", self.customers.len(), amount(self.total_spend), real(gini(&all_spends)))]];
        for segment in 0..k { blocks.push(self.segment_profile(segment)); }
        let mut mix = vec![format!("category_mix {numbers}")];
        for category in self.overall_categories.keys() {
            let shares: Vec<_> = self.segment_categories.iter().zip(&self.segment_spends).map(|(totals, &spend)| totals.get(category).copied().unwrap_or(0) as f64 / spend as f64).collect();
            mix.push(format!("{category} {}", reals(&shares)));
        }
        blocks.push(mix);
        let mut recency = vec![format!("rfm_recency {numbers}")];
        for score in (1..=5).rev() {
            let mut counts = vec![0; k];
            for (number, scores) in self.scores.iter().enumerate() { if scores[0] == score { counts[solution.labels[number]] += 1; } }
            recency.push(format!("r={score} {}", integers(&counts)));
        }
        recency.push(format!("ari rfm_codes {}", real(adjusted_rand_index(&self.codes, &solution.labels))));
        blocks.push(recency);
        let mut distances = vec!["center_distances".to_owned()];
        for (index, center) in solution.centers.iter().enumerate() {
            let values: Vec<_> = solution.centers.iter().map(|other| squared_distance(center, other).sqrt()).collect();
            distances.push(format!("{} {}", index + 1, reals(&values)));
        }
        blocks.push(distances);
        join_blocks(blocks)
    }
    fn robustness_lines(&self) -> Vec<String> {
        let candidate = self.final_candidate();
        let solution = &candidate.solution;
        let k = solution.k;
        let size = self.customers.len() * self.params.subsample_percent / 100;
        let mut subsamples = vec![format!("subsamples {} size {size}", self.params.subsamples)];
        for (segment, values) in self.jaccards.iter().enumerate() {
            let minimum = values.iter().copied().fold(f64::INFINITY, f64::min);
            subsamples.push(format!("segment {} {} mean_jaccard {} min_jaccard {}", segment + 1, candidate.names[segment], real(mean(values)), real(minimum)));
        }
        let mut ablation = vec!["ablation".to_owned()];
        for (feature, name) in FEATURE_NAMES.iter().enumerate() {
            let points: Vec<Point> = self.points.iter().map(|point| point.iter().enumerate().filter_map(|(index, &value)| (index != feature).then_some(value)).collect()).collect();
            let seeds = maximin(&points, k, 1);
            let run = Run::new("maximin".to_owned(), 1, seeds.clone(), &points, self.params.max_iterations);
            let index = adjusted_rand_index(&run.improved.labels, &solution.labels);
            ablation.push(format!("without {name} seeds {} iterations {} converged {} transfers {} sse {} ari {}", self.ids(&seeds), run.lloyd.iterations, yes_no(run.lloyd.converged), run.improved.transfers, real(run.improved.sse), real(index)));
        }
        let members = &solution.members[0];
        let points: Vec<_> = members.iter().map(|&number| self.points[number].clone()).collect();
        let seeds = maximin(&points, 2, 1);
        let run = Run::new("maximin".to_owned(), 1, seeds.clone(), &points, self.params.max_iterations);
        let parts = Solution::new(&points, &run.improved.labels, 2);
        let ids: Vec<_> = seeds.iter().map(|&index| members[index]).collect();
        let before = self.segment_sse[0];
        let after = run.improved.sse;
        let mut drilldown = vec![format!("drilldown segment 1 {} size {} seeds {} iterations {} converged {} transfers {}", candidate.names[0], members.len(), self.ids(&ids), run.lloyd.iterations, yes_no(run.lloyd.converged), run.improved.transfers), format!("sse before {} after {} gain {}", real(before), real(after), real(before - after))];
        for part in 0..2 { drilldown.push(format!("part {} size {} center {}", part + 1, parts.sizes[part], reals(&parts.centers[part]))); }
        join_blocks(vec![subsamples, ablation, drilldown])
    }
    fn period_lines(&self) -> Vec<String> {
        let solution = &self.final_candidate().solution;
        let mut lines = vec![format!("periods {} days {}", self.params.periods, self.params.period_days)];
        for period in 1..=self.params.periods {
            let first = self.params.reference_day - period as i64 * self.params.period_days + 1;
            let last = self.params.reference_day - (period - 1) as i64 * self.params.period_days;
            let mut revenue = vec![0; solution.k];
            let mut active = vec![0; solution.k];
            let mut acquired = vec![0; solution.k];
            for (customer, &label) in self.customers.iter().zip(&solution.labels) {
                let nets: Vec<_> = customer.orders.iter().filter(|order| first <= order.day && order.day <= last).map(|order| order.net).collect();
                if !nets.is_empty() { revenue[label] += nets.iter().sum::<i64>(); active[label] += 1; }
                let first_purchase = self.params.reference_day - customer.tenure;
                if first <= first_purchase && first_purchase <= last { acquired[label] += 1; }
            }
            lines.push(format!("period {period} days {first} {last} revenue {} active {} acquired {}", revenue.iter().map(|&value| amount(value)).collect::<Vec<_>>().join(" "), integers(&active), integers(&acquired)));
        }
        lines
    }
    fn migration_lines(&self) -> Vec<String> {
        let solution = &self.final_candidate().solution;
        let orders = group_orders(&self.data.valid_rows, 1, self.params.snapshot_day);
        let snapshot = eligible_customers(&orders, self.params.snapshot_day);
        let mut segments = BTreeMap::new();
        for customer in &snapshot {
            let point = standardize(&customer.transformed(), &self.means, &self.sds);
            let label = kmeans::assign(&[point], &solution.centers).0[0];
            segments.insert(customer.id.as_str(), label);
        }
        let mut table = vec![vec![0; solution.k]; solution.k + 1];
        let mut moved = Vec::new();
        let mut stayed = 0;
        let mut new = 0;
        for (customer, &label) in self.customers.iter().zip(&solution.labels) {
            if let Some(&origin) = segments.get(customer.id.as_str()) {
                table[origin][label] += 1;
                if origin == label { stayed += 1; } else { moved.push(format!("{} {} {}", customer.id, origin + 1, label + 1)); }
            } else { table[solution.k][label] += 1; new += 1; }
        }
        let lost = snapshot.iter().filter(|customer| self.customers.binary_search_by(|current| current.id.cmp(&customer.id)).is_err()).count();
        let mut lines = vec![format!("migration day {} customers {}", self.params.snapshot_day, snapshot.len()), format!("from\\to {}", integers(&(1..=solution.k).collect::<Vec<_>>()))];
        for (origin, counts) in table.iter().enumerate() { let name = if origin == solution.k { "none".to_owned() } else { (origin + 1).to_string() }; lines.push(format!("{name} {}", integers(counts))); }
        lines.push("moved_customers".to_owned());
        let moved_count = moved.len();
        lines.extend(moved);
        lines.push(format!("stayed {stayed} moved {moved_count} new {new} lost {lost}"));
        lines
    }
    fn outcome_lines(&self) -> Vec<String> {
        let candidate = self.final_candidate();
        let solution = &candidate.solution;
        let first = self.params.reference_day + 1;
        let last = self.params.reference_day + self.params.outcome_days;
        let valid: Vec<_> = group_orders(&self.data.valid_rows, first, last).into_iter().filter(|order| order.net > 0).collect();
        let purchases = orders_by_customer(&valid);
        let mut lines = vec![format!("outcome days {first} {last}")];
        for (segment, members) in solution.members.iter().enumerate() {
            let mut buyers = 0;
            let mut spend = 0;
            for &number in members {
                if let Some(orders) = purchases.get(&self.customers[number].id) { buyers += 1; spend += orders.iter().map(|order| order.net).sum::<i64>(); }
            }
            lines.push(format!("segment {} {} size {} buyers {buyers} rate {} revenue {} per_customer {}", segment + 1, candidate.names[segment], members.len(), real(buyers as f64 / members.len() as f64), amount(spend), real((spend as f64 / 100.0) / members.len() as f64)));
        }
        let outsiders: Vec<_> = purchases.iter().filter(|(id, _)| self.customers.binary_search_by(|customer| customer.id.as_str().cmp(id.as_str())).is_err()).collect();
        let outsider_spend: i64 = outsiders.iter().flat_map(|(_, orders)| orders.iter()).map(|order| order.net).sum();
        lines.push(format!("unsegmented buyers {} revenue {}", outsiders.len(), amount(outsider_spend)));
        lines
    }
    fn tracking_lines(&self) -> Vec<String> { join_blocks(vec![self.period_lines(), self.migration_lines(), self.outcome_lines()]) }
    fn summary_lines(&self) -> Vec<String> {
        let used: Vec<_> = self.data.valid_rows.iter().filter(|row| row.day <= self.params.reference_day).collect();
        let returns = used.iter().filter(|row| row.amount < 0).count();
        let later = self.data.valid_rows.iter().filter(|row| row.day > self.params.reference_day).count();
        let valid = self.reference_orders.iter().filter(|order| order.net > 0).count();
        let excluded: Vec<_> = self.data.customers.iter().filter(|id| self.customers.binary_search_by(|customer| customer.id.cmp(id)).is_err()).cloned().collect();
        let data = vec![format!("rows {} duplicates {} zero {} used {} returns {returns} later {later}", self.data.row_count, self.data.duplicates, self.data.free, used.len()), format!("orders {} valid {valid} cancelled {}", self.reference_orders.len(), self.reference_orders.len() - valid), format!("customers {} clustered {} excluded {}", self.data.customers.len(), self.customers.len(), excluded.len()), format!("excluded_ids {}", if excluded.is_empty() { "-".to_owned() } else { excluded.join(" ") })];
        let categories: Vec<_> = self.overall_categories.iter().map(|(category, &spend)| {
            let buyers = self.customers.iter().filter(|customer| customer.category_spend.get(category).copied().unwrap_or(0) > 0).count();
            format!("category {category} revenue {} share {} customers {buyers}", amount(spend), real(spend as f64 / self.total_spend as f64))
        }).collect();
        let raw: Vec<_> = self.customers.iter().map(Customer::values).collect();
        let mut features = Vec::new();
        for (index, name) in FEATURE_NAMES.iter().enumerate() {
            let column: Vec<_> = raw.iter().map(|values| values[index]).collect();
            features.push(format!("feature {name} transform {} raw_mean {} raw_sd {} mean {} sd {}", if SQRT_FEATURES[index] { "sqrt" } else { "none" }, real(mean(&column)), real(sample_sd(&column)), real(self.means[index]), real(self.sds[index])));
        }
        let mut correlations = vec![format!("correlation {}", FEATURE_NAMES.join(" "))];
        for (first, name) in FEATURE_NAMES.iter().enumerate() {
            let values: Vec<_> = (0..6).map(|second| correlation(&self.points, first, second)).collect();
            correlations.push(format!("{name} {}", reals(&values)));
        }
        join_blocks(vec![data, categories, features, correlations])
    }
}

fn main() -> io::Result<()> {
    let params = read_params("input/params.txt")?;
    let data = read_transactions("input/transactions.csv")?;
    let rules = read_rules("input/segment_rules.txt")?;
    let mut analysis = Analysis::new(params, data, rules);
    analysis.analyze();
    fs::create_dir_all("output")?;
    for (name, lines) in [("features.csv", analysis.features_lines()), ("runs.txt", analysis.runs_lines()),
        ("selection.txt", analysis.selection_lines()), ("segments.csv", analysis.segments_lines()),
        ("profiles.txt", analysis.profiles_lines()), ("robustness.txt", analysis.robustness_lines()),
        ("tracking.txt", analysis.tracking_lines()), ("summary.txt", analysis.summary_lines())] {
        write_lines(&format!("output/{name}"), &lines)?;
    }
    Ok(())
}
