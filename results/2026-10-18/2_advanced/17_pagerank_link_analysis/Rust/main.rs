mod graph_io;
mod components;
mod pagerank;
mod hits;
mod report;

use std::cmp::Reverse;
use std::collections::{BTreeMap, BTreeSet};
use std::{fs, io};
use components::{bfs_distances, reachable, strong_components, weak_components};
use graph_io::{LinkRecord, Page, Query, Settings, read_links, read_pages, read_queries, read_settings};
use hits::hits;
use pagerank::{PageRankResult, WeightedEdges, power_iteration};
use report::{fixed, fraction, scaled, write_lines};

type Link = (usize, usize);
const REGIONS: [&str; 7] = ["CORE", "IN", "OUT", "TUBE", "IN_TENDRIL", "OUT_TENDRIL", "OTHER"];
const QUANTITIES: [&str; 7] = ["in_degree", "pagerank", "cheirank", "authority", "hub", "trustrank", "harmonic"];

fn total(values: impl IntoIterator<Item = f64>) -> f64 {
    let mut result = 0.0;
    for value in values { result += value; }
    result
}

fn joined_blocks(blocks: Vec<Vec<String>>) -> Vec<String> {
    let mut lines = Vec::new();
    for block in blocks {
        if !lines.is_empty() { lines.push(String::new()); }
        lines.extend(block);
    }
    lines
}

fn rank_order(values: &[f64]) -> Vec<usize> {
    let mut order: Vec<_> = (0..values.len()).collect();
    order.sort_by_key(|&node| (Reverse(scaled(values[node], 6)), node));
    order
}

fn positions(order: &[usize]) -> Vec<usize> {
    let mut ranks = vec![0; order.len()];
    for (position, &node) in order.iter().enumerate() { ranks[node] = position + 1; }
    ranks
}

fn top_list(values: &[f64], limit: usize) -> Vec<usize> {
    rank_order(values).into_iter().filter(|&node| scaled(values[node], 6) > 0).take(limit).collect()
}

fn ranked_counts(counts: &[usize], limit: usize) -> Vec<usize> {
    let mut nodes: Vec<_> = (0..counts.len()).filter(|&node| counts[node] > 0).collect();
    nodes.sort_by_key(|&node| (Reverse(counts[node]), node));
    nodes.truncate(limit);
    nodes
}

fn distribution(values: &[usize]) -> Vec<(usize, usize)> {
    let mut counts = BTreeMap::new();
    for &value in values { *counts.entry(value).or_insert(0) += 1; }
    counts.into_iter().collect()
}

fn run_pagerank(edges: &[Vec<(usize, usize)>], teleport: &[usize], damping: f64, settings: &Settings) -> PageRankResult {
    power_iteration(edges, teleport, damping, settings.iterations, settings.tolerance)
}

fn classify_links(records: &[LinkRecord], index: &BTreeMap<i32, usize>) -> (Vec<Link>, Vec<(usize, &'static str)>) {
    let mut accepted = BTreeSet::new();
    let mut ignored = Vec::new();
    for (number, record) in records.iter().enumerate() {
        let (Some(&source), Some(&target)) = (index.get(&record.source), index.get(&record.target)) else {
            ignored.push((number, "unknown"));
            continue;
        };
        if source == target { ignored.push((number, "self")); }
        else if !accepted.insert((source, target)) { ignored.push((number, "duplicate")); }
    }
    (accepted.into_iter().collect(), ignored)
}

struct Graph {
    pages: Vec<Page>,
    links: Vec<Link>,
    link_set: BTreeSet<Link>,
    successors: Vec<Vec<usize>>,
    predecessors: Vec<Vec<usize>>,
}

impl Graph {
    fn new(pages: Vec<Page>, mut links: Vec<Link>) -> Self {
        links.sort_unstable();
        let mut successors = vec![Vec::new(); pages.len()];
        let mut predecessors = vec![Vec::new(); pages.len()];
        for &(source, target) in &links { successors[source].push(target); predecessors[target].push(source); }
        let link_set = links.iter().copied().collect();
        Self { pages, links, link_set, successors, predecessors }
    }
    fn count(&self) -> usize { self.pages.len() }
    fn host(&self, node: usize) -> &str { &self.pages[node].host }
    fn intra_host(&self, source: usize, target: usize) -> bool { self.host(source) == self.host(target) }
    fn inter_host_links(&self, links: &[Link]) -> Vec<Link> {
        links.iter().copied().filter(|&(source, target)| !self.intra_host(source, target)).collect()
    }
    fn dangling(&self) -> Vec<usize> { (0..self.count()).filter(|&node| self.successors[node].is_empty()).collect() }
    fn ident(&self, node: usize) -> i32 { self.pages[node].ident }
    fn forward_edges(&self) -> WeightedEdges {
        self.predecessors.iter().map(|nodes| nodes.iter().map(|&source| (source, 1)).collect()).collect()
    }
    fn reverse_edges(&self) -> WeightedEdges {
        self.successors.iter().map(|nodes| nodes.iter().map(|&target| (target, 1)).collect()).collect()
    }
    fn ids(&self, nodes: &[usize]) -> String {
        nodes.iter().map(|&node| self.ident(node).to_string()).collect::<Vec<_>>().join(" ")
    }
    fn describe(&self, position: usize, node: usize, values: &str) -> String {
        let page = &self.pages[node];
        format!("{position} {} {values} {} {}", page.ident, page.host, page.title)
    }
}

fn kcore_numbers(neighbors: &[Vec<usize>]) -> Vec<usize> {
    let mut remaining: Vec<_> = neighbors.iter().map(Vec::len).collect();
    let mut removed = vec![false; neighbors.len()];
    let mut core = vec![0; neighbors.len()];
    let mut level = 0;
    let mut left = neighbors.len();
    while left > 0 {
        let candidate = (0..neighbors.len()).find(|&node| !removed[node] && remaining[node] <= level);
        let Some(node) = candidate else { level += 1; continue; };
        removed[node] = true;
        core[node] = level;
        left -= 1;
        for &neighbor in &neighbors[node] { if !removed[neighbor] { remaining[neighbor] -= 1; } }
    }
    core
}

struct Undirected {
    edge_count: usize,
    closed: usize,
    possible: usize,
    eligible: usize,
    average_clustering: f64,
    kcore: Vec<usize>,
    degeneracy: usize,
    weak_count: usize,
    weak_largest: usize,
}

impl Undirected {
    fn new(graph: &Graph) -> Self {
        let mut adjacent = vec![BTreeSet::new(); graph.count()];
        for &(source, target) in &graph.links { adjacent[source].insert(target); adjacent[target].insert(source); }
        let neighbors: Vec<Vec<_>> = adjacent.iter().map(|group| group.iter().copied().collect()).collect();
        let edge_count = neighbors.iter().map(Vec::len).sum::<usize>() / 2;
        let (mut closed, mut possible, mut eligible) = (0, 0, 0);
        let mut local_sum = 0.0;
        for group in &neighbors {
            if group.len() < 2 { continue; }
            let mut closed_pairs = 0;
            for (position, &first) in group.iter().enumerate() {
                for &second in &group[position + 1..] { if adjacent[first].contains(&second) { closed_pairs += 1; } }
            }
            let pairs = group.len() * (group.len() - 1) / 2;
            closed += closed_pairs;
            possible += pairs;
            eligible += 1;
            local_sum += closed_pairs as f64 / pairs as f64;
        }
        let kcore = kcore_numbers(&neighbors);
        let degeneracy = *kcore.iter().max().unwrap();
        let labels = weak_components(&neighbors);
        let weak_count = *labels.iter().max().unwrap() + 1;
        let mut sizes = vec![0; weak_count];
        for label in labels { sizes[label] += 1; }
        let weak_largest = *sizes.iter().max().unwrap();
        Self { edge_count, closed, possible, eligible, average_clustering: local_sum / eligible as f64,
            kcore, degeneracy, weak_count, weak_largest }
    }
}

fn longest_path(count: usize, edges: &BTreeSet<Link>) -> usize {
    let mut successors = vec![Vec::new(); count];
    let mut pending = vec![0; count];
    for &(source, target) in edges { successors[source].push(target); pending[target] += 1; }
    let mut length = vec![0; count];
    let mut ready: Vec<_> = (0..count).filter(|&node| pending[node] == 0).collect();
    while let Some(node) = ready.pop() {
        for &target in &successors[node] {
            length[target] = length[target].max(length[node] + 1);
            pending[target] -= 1;
            if pending[target] == 0 { ready.push(target); }
        }
    }
    *length.iter().max().unwrap()
}

struct ComponentTable {
    groups: Vec<Vec<usize>>,
    label: Vec<usize>,
    incoming: Vec<usize>,
    outgoing: Vec<usize>,
    edge_count: usize,
    depth: usize,
    core: usize,
    singletons: usize,
}

impl ComponentTable {
    fn new(graph: &Graph) -> Self {
        let mut groups = strong_components(&graph.successors);
        for group in &mut groups { group.sort_unstable(); }
        groups.sort_by_key(|group| group[0]);
        let mut label = vec![0; graph.count()];
        for (number, group) in groups.iter().enumerate() { for &node in group { label[node] = number; } }
        let mut incoming = vec![0; groups.len()];
        let mut outgoing = vec![0; groups.len()];
        let mut edges = BTreeSet::new();
        for &(source, target) in &graph.links {
            let (first, second) = (label[source], label[target]);
            if first != second { outgoing[first] += 1; incoming[second] += 1; edges.insert((first, second)); }
        }
        let mut core = 0;
        for (number, group) in groups.iter().enumerate() { if group.len() > groups[core].len() { core = number; } }
        let singletons = groups.iter().filter(|group| group.len() == 1).count();
        let depth = longest_path(groups.len(), &edges);
        Self { groups, label, incoming, outgoing, edge_count: edges.len(), depth, core, singletons }
    }
}

fn bowtie_regions(graph: &Graph, core_pages: &[usize]) -> Vec<usize> {
    let forward = reachable(&graph.successors, core_pages);
    let backward = reachable(&graph.predecessors, core_pages);
    let mut in_core = vec![false; graph.count()];
    for &node in core_pages { in_core[node] = true; }
    let mut regions = vec![6; graph.count()];
    for node in 0..graph.count() {
        if in_core[node] { regions[node] = 0; }
        else if backward[node] { regions[node] = 1; }
        else if forward[node] { regions[node] = 2; }
    }
    let in_pages: Vec<_> = (0..graph.count()).filter(|&node| regions[node] == 1).collect();
    let out_pages: Vec<_> = (0..graph.count()).filter(|&node| regions[node] == 2).collect();
    let from_in = reachable(&graph.successors, &in_pages);
    let to_out = reachable(&graph.predecessors, &out_pages);
    for node in 0..graph.count() {
        if in_core[node] || backward[node] || forward[node] { continue; }
        if from_in[node] && to_out[node] { regions[node] = 3; }
        else if from_in[node] { regions[node] = 4; }
        else if to_out[node] { regions[node] = 5; }
    }
    regions
}

struct DistanceStats {
    pairs: usize,
    total: usize,
    diameter: usize,
    diameter_pair: Link,
    histogram: Vec<usize>,
    harmonic: Vec<f64>,
}

impl DistanceStats {
    fn new(graph: &Graph) -> Self {
        let mut result = Self { pairs: 0, total: 0, diameter: 0, diameter_pair: (0, 0),
            histogram: vec![0; graph.count()], harmonic: vec![0.0; graph.count()] };
        for source in 0..graph.count() {
            let distance = bfs_distances(&graph.successors, &[source]);
            for (target, &steps) in distance.iter().enumerate() {
                if target == source || steps < 0 { continue; }
                let steps = steps as usize;
                result.pairs += 1;
                result.total += steps;
                result.histogram[steps] += 1;
                result.harmonic[target] += 1.0 / steps as f64;
                if steps > result.diameter { result.diameter = steps; result.diameter_pair = (source, target); }
            }
        }
        result
    }
    fn effective_diameter(&self) -> usize {
        let mut reached = 0;
        for steps in 1..=self.diameter {
            reached += self.histogram[steps];
            if 10 * reached >= 9 * self.pairs { return steps; }
        }
        self.diameter
    }
}

struct PageScores {
    pagerank_run: PageRankResult,
    cheirank_run: PageRankResult,
    trustrank_run: PageRankResult,
    order: Vec<usize>,
    rank: Vec<usize>,
    cheirank_rank: Vec<usize>,
    trust_ratio: Vec<f64>,
    trust_distance: Vec<i32>,
    authority: Vec<f64>,
    hub: Vec<f64>,
    harmonic: Vec<f64>,
}

impl PageScores {
    fn new(graph: &Graph, settings: &Settings, trusted: &[usize], harmonic: Vec<f64>) -> Self {
        let everyone: Vec<_> = (0..graph.count()).collect();
        let pagerank_run = run_pagerank(&graph.forward_edges(), &everyone, settings.damping, settings);
        let cheirank_run = run_pagerank(&graph.reverse_edges(), &everyone, settings.damping, settings);
        let trustrank_run = run_pagerank(&graph.forward_edges(), trusted, settings.damping, settings);
        let order = rank_order(&pagerank_run.values);
        let rank = positions(&order);
        let cheirank_rank = positions(&rank_order(&cheirank_run.values));
        let trust_ratio = trustrank_run.values.iter().zip(&pagerank_run.values).map(|(trust, score)| trust / score).collect();
        let trust_distance = bfs_distances(&graph.successors, trusted);
        let (authority, hub) = hits(graph.count(), &everyone, &graph.inter_host_links(&graph.links), settings.hits_iterations);
        Self { pagerank_run, cheirank_run, trustrank_run, order, rank, cheirank_rank,
            trust_ratio, trust_distance, authority, hub, harmonic }
    }
    fn contribution(&self, graph: &Graph, source: usize, damping: f64) -> f64 {
        (damping * self.pagerank_run.values[source]) / graph.successors[source].len() as f64
    }
    fn representative(&self, nodes: &[usize]) -> usize { *nodes.iter().min_by_key(|&&node| self.rank[node]).unwrap() }
}

fn kendall(first: &[i64], second: &[i64]) -> String {
    let mut concordant = 0;
    let mut discordant = 0;
    for i in 0..first.len() {
        for j in i + 1..first.len() {
            let dx = first[i] - first[j];
            let dy = second[i] - second[j];
            if dx == 0 || dy == 0 { continue; }
            if (dx > 0) == (dy > 0) { concordant += 1; } else { discordant += 1; }
        }
    }
    fraction(concordant - discordant, (first.len() * (first.len() - 1) / 2) as i64)
}

struct SweepResult {
    damping: f64,
    run: PageRankResult,
    overlap: usize,
    footrule: usize,
    correlation: String,
    shift: usize,
    shift_rank: usize,
    top: Vec<usize>,
}

impl SweepResult {
    fn new(damping: f64, graph: &Graph, scores: &PageScores, settings: &Settings) -> Self {
        let everyone: Vec<_> = (0..graph.count()).collect();
        let run = run_pagerank(&graph.forward_edges(), &everyone, damping, settings);
        let order = rank_order(&run.values);
        let rank = positions(&order);
        let overlap = (0..graph.count()).filter(|&node| rank[node] <= settings.top_k && scores.rank[node] <= settings.top_k).count();
        let footrule = (0..graph.count()).map(|node| rank[node].abs_diff(scores.rank[node])).sum();
        let correlation = kendall(&scores.pagerank_run.values.iter().map(|&v| scaled(v, 6)).collect::<Vec<_>>(),
            &run.values.iter().map(|&v| scaled(v, 6)).collect::<Vec<_>>());
        let mut shift = 0;
        for node in 0..graph.count() {
            if rank[node].abs_diff(scores.rank[node]) > rank[shift].abs_diff(scores.rank[shift]) { shift = node; }
        }
        let top = order.into_iter().take(settings.top_k).collect();
        Self { damping, run, overlap, footrule, correlation, shift, shift_rank: rank[shift], top }
    }
}

struct SpamReport {
    suspects: Vec<usize>,
    hosts: Vec<String>,
    removed: usize,
    run: Option<PageRankResult>,
    rank: Vec<usize>,
}

impl SpamReport {
    fn new(graph: &Graph, scores: &PageScores, settings: &Settings) -> Self {
        let suspects: Vec<_> = scores.order.iter().copied().take(settings.spam_top)
            .filter(|&node| scaled(scores.trust_ratio[node], 4) as f64 / 10000.0 < settings.spam_threshold).collect();
        let hosts: Vec<_> = suspects.iter().map(|&node| graph.host(node).to_owned()).collect::<BTreeSet<_>>().into_iter().collect();
        let mut result = Self { suspects, hosts, removed: 0, run: None, rank: Vec::new() };
        if !result.suspects.is_empty() {
            let kept: Vec<_> = graph.links.iter().copied().filter(|&(source, target)|
                !(graph.intra_host(source, target) && result.hosts.iter().any(|host| host == graph.host(source)))).collect();
            result.removed = graph.links.len() - kept.len();
            let demoted = Graph::new(graph.pages.clone(), kept);
            let everyone: Vec<_> = (0..graph.count()).collect();
            let run = run_pagerank(&demoted.forward_edges(), &everyone, settings.damping, settings);
            result.rank = positions(&rank_order(&run.values));
            result.run = Some(run);
        }
        result
    }
}

fn salsa_scores(count: usize, links: &[Link]) -> Vec<f64> {
    let mut degree = vec![0; count];
    let mut targets = vec![Vec::new(); count];
    for &(source, target) in links { degree[target] += 1; targets[source].push(target); }
    let mut neighbors = vec![Vec::new(); count];
    for group in targets {
        for pair in group.windows(2) { neighbors[pair[0]].push(pair[1]); neighbors[pair[1]].push(pair[0]); }
    }
    let labels = weak_components(&neighbors);
    let side: Vec<_> = (0..count).filter(|&node| degree[node] > 0).collect();
    let mut size = vec![0; count];
    let mut mass = vec![0; count];
    for &node in &side { size[labels[node]] += 1; mass[labels[node]] += degree[node]; }
    let mut scores = vec![0.0; count];
    for &node in &side {
        let label = labels[node];
        scores[node] = (size[label] * degree[node]) as f64 / (side.len() * mass[label]) as f64;
    }
    scores
}

struct SubgraphScores {
    authority: Vec<f64>,
    hub: Vec<f64>,
    salsa_authority: Vec<f64>,
    salsa_hub: Vec<f64>,
    authority_top: Vec<usize>,
    hub_top: Vec<usize>,
    salsa_authority_top: Vec<usize>,
    salsa_hub_top: Vec<usize>,
    authority_overlap: usize,
    hub_overlap: usize,
    authority_hosts: usize,
    cited: usize,
    cocitation: Vec<usize>,
    related: Vec<usize>,
    citing: usize,
    coupling: Vec<usize>,
    similar: Vec<usize>,
}

impl SubgraphScores {
    fn new(graph: &Graph, base: &[usize], subgraph: &[Link], settings: &Settings) -> Self {
        let (authority, hub) = hits(graph.count(), base, subgraph, settings.hits_iterations);
        let salsa_authority = salsa_scores(graph.count(), subgraph);
        let reversed: Vec<_> = subgraph.iter().map(|&(source, target)| (target, source)).collect();
        let salsa_hub = salsa_scores(graph.count(), &reversed);
        let authority_top = top_list(&authority, settings.top_k);
        let hub_top = top_list(&hub, settings.top_k);
        let salsa_authority_top = top_list(&salsa_authority, settings.top_k);
        let salsa_hub_top = top_list(&salsa_hub, settings.top_k);
        let authority_overlap = authority_top.iter().filter(|node| salsa_authority_top.contains(node)).count();
        let hub_overlap = hub_top.iter().filter(|node| salsa_hub_top.contains(node)).count();
        let authority_hosts = authority_top.iter().map(|&node| graph.host(node)).collect::<BTreeSet<_>>().len();
        let cited = authority_top[0];
        let mut cocitation = vec![0; graph.count()];
        for &citing in &graph.predecessors[cited] {
            for &target in &graph.successors[citing] { if target != cited { cocitation[target] += 1; } }
        }
        let related = ranked_counts(&cocitation, settings.top_k);
        let citing = hub_top[0];
        let mut coupling = vec![0; graph.count()];
        for &target in &graph.successors[citing] {
            for &source in &graph.predecessors[target] { if source != citing { coupling[source] += 1; } }
        }
        let similar = ranked_counts(&coupling, settings.top_k);
        Self { authority, hub, salsa_authority, salsa_hub, authority_top, hub_top, salsa_authority_top,
            salsa_hub_top, authority_overlap, hub_overlap, authority_hosts, cited, cocitation, related, citing, coupling, similar }
    }
}

struct QueryResult {
    matches: Vec<usize>,
    root_size: usize,
    base_size: usize,
    subgraph: Vec<Link>,
    dropped: usize,
    personalized: PageRankResult,
    reach: usize,
    seed_mass: f64,
    personalized_top: Vec<usize>,
    global_overlap: usize,
    subgraph_scores: Option<SubgraphScores>,
}

impl QueryResult {
    fn new(query: &Query, graph: &Graph, scores: &PageScores, settings: &Settings, index: &BTreeMap<i32, usize>) -> Self {
        let include: Vec<_> = query.words.iter().filter(|word| !word.starts_with('-')).collect();
        let exclude: Vec<_> = query.words.iter().filter_map(|word| word.strip_prefix('-')).collect();
        let matches: Vec<_> = scores.order.iter().copied().filter(|&node| {
            let words = &graph.pages[node].words;
            include.iter().all(|word| words.iter().any(|own| own == *word))
                && exclude.iter().all(|&word| !words.iter().any(|own| own.as_str() == word))
        }).collect();
        let root: Vec<_> = matches.iter().copied().take(settings.root_limit).collect();
        let mut in_base = vec![false; graph.count()];
        for &node in &root {
            in_base[node] = true;
            for &neighbor in graph.successors[node].iter().take(settings.neighbor_limit) { in_base[neighbor] = true; }
            for &neighbor in graph.predecessors[node].iter().take(settings.neighbor_limit) { in_base[neighbor] = true; }
        }
        let base: Vec<_> = (0..graph.count()).filter(|&node| in_base[node]).collect();
        let inside: Vec<_> = graph.links.iter().copied().filter(|&(source, target)| in_base[source] && in_base[target]).collect();
        let subgraph = graph.inter_host_links(&inside);
        let dropped = inside.len() - subgraph.len();
        let mut seeds: Vec<_> = query.seeds.iter().map(|ident| index[ident]).collect();
        seeds.sort_unstable();
        let personalized = run_pagerank(&graph.forward_edges(), &seeds, settings.damping, settings);
        let reach = reachable(&graph.successors, &seeds).iter().filter(|&&value| value).count();
        let seed_mass = total(seeds.iter().map(|&node| personalized.values[node]));
        let personalized_top = top_list(&personalized.values, settings.top_k);
        let global_overlap = personalized_top.iter().filter(|&&node| scores.rank[node] <= settings.top_k).count();
        let subgraph_scores = if subgraph.is_empty() { None } else { Some(SubgraphScores::new(graph, &base, &subgraph, settings)) };
        Self { matches, root_size: root.len(), base_size: base.len(), subgraph, dropped, personalized,
            reach, seed_mass, personalized_top, global_overlap, subgraph_scores }
    }
}

struct HostGraph {
    names: Vec<String>,
    members: Vec<Vec<usize>>,
    weight: Vec<Vec<usize>>,
    internal: Vec<usize>,
    outgoing: Vec<usize>,
    incoming: Vec<usize>,
    edges: Vec<Link>,
    reciprocal: usize,
    component_count: usize,
    largest: usize,
    run: PageRankResult,
    rank: Vec<usize>,
    heavy: Vec<Link>,
}

impl HostGraph {
    fn new(graph: &Graph, settings: &Settings) -> Self {
        let names: Vec<_> = graph.pages.iter().map(|page| page.host.clone()).collect::<BTreeSet<_>>().into_iter().collect();
        let count = names.len();
        let index: BTreeMap<_, _> = names.iter().enumerate().map(|(number, name)| (name.as_str(), number)).collect();
        let of_page: Vec<_> = graph.pages.iter().map(|page| index[page.host.as_str()]).collect();
        let mut members = vec![Vec::new(); count];
        for (node, &host) in of_page.iter().enumerate() { members[host].push(node); }
        let mut weight = vec![vec![0; count]; count];
        let mut internal = vec![0; count];
        let mut outgoing = vec![0; count];
        let mut incoming = vec![0; count];
        for &(source, target) in &graph.links {
            let (first, second) = (of_page[source], of_page[target]);
            if first == second { internal[first] += 1; }
            else { weight[first][second] += 1; outgoing[first] += 1; incoming[second] += 1; }
        }
        let mut edges = Vec::new();
        let mut adjacency = vec![Vec::new(); count];
        let mut in_edges = vec![Vec::new(); count];
        for first in 0..count {
            for second in 0..count {
                if weight[first][second] > 0 {
                    edges.push((first, second));
                    adjacency[first].push(second);
                    in_edges[second].push((first, weight[first][second]));
                }
            }
        }
        let reciprocal = edges.iter().filter(|&&(first, second)| weight[second][first] > 0).count();
        let components = strong_components(&adjacency);
        let component_count = components.len();
        let largest = components.iter().map(Vec::len).max().unwrap();
        let everyone: Vec<_> = (0..count).collect();
        let run = run_pagerank(&in_edges, &everyone, settings.damping, settings);
        let rank = positions(&rank_order(&run.values));
        let mut heavy = edges.clone();
        heavy.sort_by_key(|&(first, second)| (Reverse(weight[first][second]), first, second));
        heavy.truncate(settings.top_k);
        Self { names, members, weight, internal, outgoing, incoming, edges, reciprocal,
            component_count, largest, run, rank, heavy }
    }
}

fn append_ids(prefix: String, graph: &Graph, nodes: &[usize]) -> String {
    if nodes.is_empty() { prefix } else { format!("{prefix} {}", graph.ids(nodes)) }
}

fn graph_stats_lines(graph: &Graph, records: &[LinkRecord], ignored: &[(usize, &str)],
    undirected: &Undirected, table: &ComponentTable, regions: &[usize], distances: &DistanceStats,
    scores: &PageScores, hosts: &HostGraph) -> Vec<String> {
    let intra = graph.links.iter().filter(|&&(source, target)| graph.intra_host(source, target)).count();
    let reciprocal = graph.links.iter().filter(|&&(source, target)| graph.link_set.contains(&(target, source))).count();
    let indegrees: Vec<_> = graph.predecessors.iter().map(Vec::len).collect();
    let outdegrees: Vec<_> = graph.successors.iter().map(Vec::len).collect();
    let no_in: Vec<_> = (0..graph.count()).filter(|&node| indegrees[node] == 0).collect();
    let max_in = *indegrees.iter().max().unwrap();
    let max_out = *outdegrees.iter().max().unwrap();
    let max_in_pages: Vec<_> = (0..graph.count()).filter(|&node| indegrees[node] == max_in).collect();
    let max_out_pages: Vec<_> = (0..graph.count()).filter(|&node| outdegrees[node] == max_out).collect();
    let dangling = graph.dangling();
    let mut lines = vec![format!("pages {}", graph.count()), format!("hosts {}", hosts.names.len()),
        format!("link_rows {}", records.len()), format!("links {}", graph.links.len())];
    for reason in ["unknown", "self", "duplicate"] {
        lines.push(format!("ignored_{reason} {}", ignored.iter().filter(|(_, own)| *own == reason).count()));
    }
    for &(number, reason) in ignored {
        let record = &records[number];
        lines.push(format!("ignored line {} {},{} {reason}", record.line, record.source, record.target));
    }
    lines.extend([format!("intra_host_links {intra}"), format!("inter_host_links {}", graph.links.len() - intra),
        format!("mean_degree {}", fixed(graph.links.len() as f64 / graph.count() as f64, 4)),
        format!("reciprocity {}", fraction(reciprocal as i64, graph.links.len() as i64)),
        append_ids(format!("dangling {}", dangling.len()), graph, &dangling),
        append_ids(format!("no_in_links {}", no_in.len()), graph, &no_in),
        append_ids(format!("max_in_degree {max_in} pages"), graph, &max_in_pages),
        append_ids(format!("max_out_degree {max_out} pages"), graph, &max_out_pages)]);
    for (name, degrees) in [("in_degree", &indegrees), ("out_degree", &outdegrees)] {
        lines.extend([String::new(), format!("{name}_distribution")]);
        for (value, count) in distribution(degrees) { lines.push(format!("{value} {count}")); }
    }
    let degeneracy_pages = undirected.kcore.iter().filter(|&&value| value == undirected.degeneracy).count();
    lines.extend([String::new(), format!("undirected_links {}", undirected.edge_count),
        format!("transitivity {}", fraction(undirected.closed as i64, undirected.possible as i64)),
        format!("average_clustering {} pages {}", fixed(undirected.average_clustering, 4), undirected.eligible),
        format!("degeneracy {} pages {degeneracy_pages}", undirected.degeneracy), "core_distribution".to_owned()]);
    for (value, count) in distribution(&undirected.kcore) { lines.push(format!("{value} {count}")); }
    lines.extend([String::new(), format!("strong_components {} largest {} singletons {} condensation_links {}",
        table.groups.len(), table.groups[table.core].len(), table.singletons, table.edge_count),
        format!("weak_components {} largest {}", undirected.weak_count, undirected.weak_largest),
        format!("condensation_depth {}", table.depth)]);
    for (number, group) in table.groups.iter().enumerate() {
        if group.len() < 2 { continue; }
        let mass = total(group.iter().map(|&node| scores.pagerank_run.values[node]));
        let suffix = if table.outgoing[number] == 0 { " sink" } else { "" };
        lines.push(format!("scc {} size {} min {} incoming {} outgoing {} pagerank {}{suffix}", number + 1,
            group.len(), graph.ident(group[0]), table.incoming[number], table.outgoing[number], fixed(mass, 6)));
    }
    lines.extend([String::new(), format!("bowtie core_scc {}", table.core + 1)]);
    for (region, name) in REGIONS.iter().enumerate() {
        let members: Vec<_> = (0..graph.count()).filter(|&node| regions[node] == region).collect();
        let mass = total(members.iter().map(|&node| scores.pagerank_run.values[node]));
        let mut text = format!("{name} {} pagerank {}", members.len(), fixed(mass, 6));
        if !members.is_empty() { text += &format!(" top {}", graph.ident(scores.representative(&members))); }
        if !members.is_empty() && members.len() <= 10 { text += &format!(" pages {}", graph.ids(&members)); }
        lines.push(text);
    }
    let mut counts = [[0; 7]; 7];
    for &(source, target) in &graph.links { counts[regions[source]][regions[target]] += 1; }
    lines.push("region_links".to_owned());
    for first in 0..7 { for second in 0..7 {
        if counts[first][second] > 0 { lines.push(format!("{} {} {}", REGIONS[first], REGIONS[second], counts[first][second])); }
    } }
    let (source, target) = distances.diameter_pair;
    lines.extend([String::new(), "distances".to_owned(), format!("reachable_pairs {}", distances.pairs),
        format!("average {}", fraction(distances.total as i64, distances.pairs as i64)),
        format!("diameter {} from {} to {}", distances.diameter, graph.ident(source), graph.ident(target)),
        format!("effective_diameter {}", distances.effective_diameter())]);
    for steps in 1..=distances.diameter { lines.push(format!("{steps} {}", distances.histogram[steps])); }
    lines
}

fn pagerank_csv_lines(graph: &Graph, table: &ComponentTable, regions: &[usize], undirected: &Undirected, scores: &PageScores) -> Vec<String> {
    let mut lines = vec!["id,in_degree,out_degree,scc,region,kcore,harmonic,pagerank,pagerank_rank,cheirank,cheirank_rank,authority,hub,trustrank,trust_ratio,trust_distance".to_owned()];
    for node in 0..graph.count() {
        lines.push(format!("{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{}", graph.ident(node),
            graph.predecessors[node].len(), graph.successors[node].len(), table.label[node] + 1, REGIONS[regions[node]],
            undirected.kcore[node], fixed(scores.harmonic[node], 6), fixed(scores.pagerank_run.values[node], 6), scores.rank[node],
            fixed(scores.cheirank_run.values[node], 6), scores.cheirank_rank[node], fixed(scores.authority[node], 6),
            fixed(scores.hub[node], 6), fixed(scores.trustrank_run.values[node], 6), fixed(scores.trust_ratio[node], 4), scores.trust_distance[node]));
    }
    lines
}

fn rank_lines(graph: &Graph, nodes: &[usize], values: &[f64]) -> Vec<String> {
    nodes.iter().enumerate().map(|(position, &node)| graph.describe(position + 1, node, &fixed(values[node], 6))).collect()
}

fn score_block(name: &str, graph: &Graph, values: &[f64], limit: usize) -> Vec<String> {
    let mut lines = vec![format!("{name} top {limit}")];
    lines.extend(rank_lines(graph, &top_list(values, limit), values));
    lines
}

fn rankings_lines(graph: &Graph, scores: &PageScores, undirected: &Undirected, sweeps: &[SweepResult],
    spam: &SpamReport, hosts: &HostGraph, settings: &Settings) -> Vec<String> {
    let limit = settings.top_k;
    let mut pagerank = score_block("pagerank", graph, &scores.pagerank_run.values, limit);
    let mass = total(graph.dangling().iter().map(|&node| scores.pagerank_run.values[node]));
    pagerank.push(format!("dangling_mass {}", fixed(mass, 6)));
    for node in top_list(&scores.pagerank_run.values, limit) {
        let mut contributors = graph.predecessors[node].clone();
        contributors.sort_by_key(|&source| (Reverse(scaled(scores.contribution(graph, source, settings.damping), 6)), source));
        let mut parts = vec!["contributors".to_owned(), graph.ident(node).to_string()];
        for source in contributors.into_iter().take(3) {
            parts.extend([graph.ident(source).to_string(), fixed(scores.contribution(graph, source, settings.damping), 6)]);
        }
        pagerank.push(parts.join(" "));
    }
    let mut blocks = vec![pagerank];
    for (name, values) in [("cheirank", &scores.cheirank_run.values), ("authority", &scores.authority),
        ("hub", &scores.hub), ("trustrank", &scores.trustrank_run.values), ("harmonic", &scores.harmonic)] {
        blocks.push(score_block(name, graph, values, limit));
    }
    let mut series: Vec<Vec<i64>> = vec![graph.predecessors.iter().map(|sources| sources.len() as i64).collect()];
    for values in [&scores.pagerank_run.values, &scores.cheirank_run.values, &scores.authority, &scores.hub,
        &scores.trustrank_run.values, &scores.harmonic] {
        series.push(values.iter().map(|&value| scaled(value, 6)).collect());
    }
    let mut correlations = vec!["correlation".to_owned()];
    for first in 0..7 { for second in first + 1..7 {
        correlations.push(format!("{} {} {}", QUANTITIES[first], QUANTITIES[second], kendall(&series[first], &series[second])));
    } }
    blocks.push(correlations);
    let mut sweep_lines = vec!["damping_sweep".to_owned()];
    for sweep in sweeps {
        sweep_lines.push(format!("damping {} overlap {} footrule {} kendall {} largest_shift {} {} {}",
            fixed(sweep.damping, 4), sweep.overlap, sweep.footrule, sweep.correlation,
            graph.ident(sweep.shift), scores.rank[sweep.shift], sweep.shift_rank));
        sweep_lines.push(append_ids("top".to_owned(), graph, &sweep.top));
    }
    blocks.push(sweep_lines);
    let mut spam_lines = vec![format!("spam top {} threshold {}", settings.spam_top, fixed(settings.spam_threshold, 4))];
    for &node in &spam.suspects {
        spam_lines.push(format!("suspect {} rank {} pagerank {} trustrank {} trust_ratio {} trust_distance {} kcore {} {}",
            graph.ident(node), scores.rank[node], fixed(scores.pagerank_run.values[node], 6), fixed(scores.trustrank_run.values[node], 6),
            fixed(scores.trust_ratio[node], 4), scores.trust_distance[node], undirected.kcore[node], graph.host(node)));
    }
    spam_lines.extend([format!("count {}", spam.suspects.len()), "trust_by_distance".to_owned()]);
    let mut distances: Vec<_> = scores.trust_distance.iter().copied().filter(|&value| value >= 0).collect::<BTreeSet<_>>().into_iter().collect();
    if scores.trust_distance.contains(&-1) { distances.push(-1); }
    for distance in distances {
        let members: Vec<_> = (0..graph.count()).filter(|&node| scores.trust_distance[node] == distance).collect();
        let label = if distance == -1 { "unreachable".to_owned() } else { distance.to_string() };
        spam_lines.push(format!("{label} pages {} trustrank {} pagerank {}", members.len(),
            fixed(total(members.iter().map(|&node| scores.trustrank_run.values[node])), 6),
            fixed(total(members.iter().map(|&node| scores.pagerank_run.values[node])), 6)));
    }
    blocks.push(spam_lines);
    let mut demotion = vec!["demotion none".to_owned()];
    if let Some(run) = &spam.run {
        demotion = vec![format!("demotion hosts {} removed_links {}", spam.hosts.join(" "), spam.removed)];
        for (position, node) in top_list(&run.values, limit).into_iter().enumerate() {
            demotion.push(graph.describe(position + 1, node, &format!("{} was {}", fixed(run.values[node], 6), scores.rank[node])));
        }
        for &node in &spam.suspects { demotion.push(format!("suspect {} before {} after {}", graph.ident(node), scores.rank[node], spam.rank[node])); }
    }
    blocks.push(demotion);
    let mut host_lines = vec![format!("host_graph hosts {} links {} reciprocal {} strong_components {} largest {}",
        hosts.names.len(), hosts.edges.len(), hosts.reciprocal, hosts.component_count, hosts.largest), format!("host_links top {limit}")];
    for &(first, second) in &hosts.heavy { host_lines.push(format!("{} {} {}", hosts.names[first], hosts.names[second], hosts.weight[first][second])); }
    blocks.push(host_lines);
    joined_blocks(blocks)
}

fn convergence_block(heading: String, run: &PageRankResult) -> Vec<String> {
    let mut lines = vec![String::new(), heading];
    for step in (10..=run.changes.len()).step_by(10) { lines.push(format!("iteration {step} l1 {}", fixed(run.changes[step - 1], 10))); }
    lines.push(format!("converged_at {}", run.converged_at.map(|step| step.to_string()).unwrap_or_else(|| "none".to_owned())));
    lines
}

fn convergence_lines(scores: &PageScores, sweeps: &[SweepResult], spam: &SpamReport, queries: &[Query],
    results: &[QueryResult], hosts: &HostGraph, settings: &Settings) -> Vec<String> {
    let damping = fixed(settings.damping, 4);
    let mut lines = vec![format!("iterations {} tolerance {}", settings.iterations, fixed(settings.tolerance, 10))];
    lines.extend(convergence_block(format!("pagerank damping {damping}"), &scores.pagerank_run));
    lines.extend(convergence_block(format!("cheirank damping {damping}"), &scores.cheirank_run));
    lines.extend(convergence_block(format!("trustrank damping {damping} seeds {}", settings.trusted.len()), &scores.trustrank_run));
    for sweep in sweeps { lines.extend(convergence_block(format!("sweep damping {}", fixed(sweep.damping, 4)), &sweep.run)); }
    if let Some(run) = &spam.run { lines.extend(convergence_block(format!("demoted damping {damping}"), run)); }
    for (query, result) in queries.iter().zip(results) {
        lines.extend(convergence_block(format!("personalized query {} damping {damping}", query.number), &result.personalized));
    }
    lines.extend(convergence_block(format!("host_pagerank damping {damping} hosts {}", hosts.names.len()), &hosts.run));
    lines
}

fn query_block(graph: &Graph, scores: &PageScores, query: &Query, result: &QueryResult, limit: usize) -> Vec<String> {
    let seeds = query.seeds.iter().map(i32::to_string).collect::<Vec<_>>().join(" ");
    let mut lines = vec![format!("query {} words {} seeds {seeds}", query.number, query.words.join(" ")),
        format!("matched {} root {} base {} links {} dropped_intra_host {}", result.matches.len(), result.root_size,
            result.base_size, result.subgraph.len(), result.dropped), "results".to_owned()];
    let matches: Vec<_> = result.matches.iter().copied().take(limit).collect();
    lines.extend(rank_lines(graph, &matches, &scores.pagerank_run.values));
    lines.push(format!("personalized reach {} seed_mass {}", result.reach, fixed(result.seed_mass, 6)));
    lines.extend(rank_lines(graph, &result.personalized_top, &result.personalized.values));
    lines.push(format!("overlap_with_global {}", result.global_overlap));
    let Some(sub) = &result.subgraph_scores else { lines.push("hits none".to_owned()); return lines; };
    for (heading, nodes, values) in [("hits authorities", &sub.authority_top, &sub.authority),
        ("hits hubs", &sub.hub_top, &sub.hub), ("salsa authorities", &sub.salsa_authority_top, &sub.salsa_authority),
        ("salsa hubs", &sub.salsa_hub_top, &sub.salsa_hub)] {
        lines.push(heading.to_owned());
        lines.extend(rank_lines(graph, nodes, values));
    }
    lines.push(format!("hits_salsa_overlap authorities {} hubs {} authority_hosts {}", sub.authority_overlap, sub.hub_overlap, sub.authority_hosts));
    lines.push(format!("related_to {} citing {}", graph.ident(sub.cited), graph.predecessors[sub.cited].len()));
    for (position, &node) in sub.related.iter().enumerate() { lines.push(graph.describe(position + 1, node, &sub.cocitation[node].to_string())); }
    lines.push(format!("coupled_to {} cited {}", graph.ident(sub.citing), graph.successors[sub.citing].len()));
    for (position, &node) in sub.similar.iter().enumerate() { lines.push(graph.describe(position + 1, node, &sub.coupling[node].to_string())); }
    lines
}

fn hosts_csv_lines(graph: &Graph, regions: &[usize], scores: &PageScores, hosts: &HostGraph) -> Vec<String> {
    let mut lines = vec!["host,pages,core_pages,internal_links,internal_density,outgoing_links,incoming_links,dangling_pages,page_score_sum,top_page,score,rank".to_owned()];
    for (number, name) in hosts.names.iter().enumerate() {
        let members = &hosts.members[number];
        let size = members.len();
        let density = if size >= 2 { hosts.internal[number] as f64 / (size * (size - 1)) as f64 } else { 0.0 };
        let core = members.iter().filter(|&&node| regions[node] == 0).count();
        let dangling = members.iter().filter(|&&node| graph.successors[node].is_empty()).count();
        let mass = total(members.iter().map(|&node| scores.pagerank_run.values[node]));
        lines.push(format!("{name},{size},{core},{},{},{},{},{dangling},{},{},{},{}", hosts.internal[number], fixed(density, 4),
            hosts.outgoing[number], hosts.incoming[number], fixed(mass, 6), graph.ident(scores.representative(members)),
            fixed(hosts.run.values[number], 6), hosts.rank[number]));
    }
    lines
}

fn main() -> io::Result<()> {
    let mut pages = read_pages("input/pages.csv")?;
    let records = read_links("input/links.csv")?;
    let queries = read_queries("input/queries.txt")?;
    let settings = read_settings("input/params.txt")?;
    pages.sort_by_key(|page| page.ident);
    let index: BTreeMap<_, _> = pages.iter().enumerate().map(|(node, page)| (page.ident, node)).collect();
    let (accepted, ignored) = classify_links(&records, &index);
    let graph = Graph::new(pages, accepted);
    let undirected = Undirected::new(&graph);
    let table = ComponentTable::new(&graph);
    let regions = bowtie_regions(&graph, &table.groups[table.core]);
    let distances = DistanceStats::new(&graph);
    let mut trusted: Vec<_> = settings.trusted.iter().map(|ident| index[ident]).collect();
    trusted.sort_unstable();
    let scores = PageScores::new(&graph, &settings, &trusted, distances.harmonic.clone());
    let sweeps: Vec<_> = settings.sweep.iter().map(|&damping| SweepResult::new(damping, &graph, &scores, &settings)).collect();
    let spam = SpamReport::new(&graph, &scores, &settings);
    let results: Vec<_> = queries.iter().map(|query| QueryResult::new(query, &graph, &scores, &settings, &index)).collect();
    let hosts = HostGraph::new(&graph, &settings);
    let query_blocks = queries.iter().zip(&results).map(|(query, result)| query_block(&graph, &scores, query, result, settings.top_k)).collect();
    let outputs = [
        ("graph_stats.txt", graph_stats_lines(&graph, &records, &ignored, &undirected, &table, &regions, &distances, &scores, &hosts)),
        ("pagerank.csv", pagerank_csv_lines(&graph, &table, &regions, &undirected, &scores)),
        ("rankings.txt", rankings_lines(&graph, &scores, &undirected, &sweeps, &spam, &hosts, &settings)),
        ("convergence.txt", convergence_lines(&scores, &sweeps, &spam, &queries, &results, &hosts, &settings)),
        ("queries.txt", joined_blocks(query_blocks)), ("hosts.csv", hosts_csv_lines(&graph, &regions, &scores, &hosts)),
    ];
    fs::create_dir_all("output")?;
    for (name, lines) in outputs { write_lines(&format!("output/{name}"), &lines)?; }
    Ok(())
}
