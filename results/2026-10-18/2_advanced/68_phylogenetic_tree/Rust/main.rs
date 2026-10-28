mod alignment;
mod distances;
mod tree_building;
mod parsimony;
mod tree_io;

use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use tree_building::Tree;
use tree_io::{real, symbols, newick};

struct Params { model: String, outgroup: String, replicates: usize, seed: i64, missing: usize, saturated: f64, exhaustive: Vec<String>, low: usize }
fn params() -> Params {
    let input = fs::read_to_string("input/params.txt").unwrap();
    let lines: Vec<Vec<_>> = input.lines().map(|l| l.split_whitespace().collect()).collect();
    Params { model: lines[0][1].to_owned(), outgroup: lines[1][1].to_owned(), replicates: lines[2][1].parse().unwrap(),
        seed: lines[3][1].parse().unwrap(), missing: lines[4][1].parse().unwrap(), saturated: lines[5][1].parse().unwrap(),
        exhaustive: lines[6][1..].iter().map(|s| (*s).to_owned()).collect(), low: lines[7][1].parse().unwrap() }
}
fn bme(tree: &Tree, matrix: &[Vec<f64>]) -> f64 {
    let leaves = tree.leaves(); let mut sum = 0.0;
    for (i, &a) in leaves.iter().enumerate() { for &b in &leaves[i+1..] { sum += matrix[a][b]/(1u64<<(tree.path(a, b).0-1)) as f64; } }
    sum
}
fn star(taxa: &[usize], count: usize) -> Tree {
    let mut tree = Tree::empty(count); let root = tree.node();
    for &taxon in taxa { tree.connect(root, taxon, 0.0); } tree
}
struct Addition { taxon: usize, mask: u32, score: usize, ties: usize }
struct Stepwise { tree: Tree, initial: usize, additions: Vec<Addition>, evaluated: usize }
fn stepwise(taxa: &[usize], sequences: &[Vec<u8>], outgroup: usize, names: &[String]) -> Stepwise {
    let mut tree = star(&taxa[..3], names.len());
    let initial = parsimony::score(&tree, sequences, outgroup, names);
    let mut additions = Vec::new(); let mut evaluated = 0;
    for &taxon in &taxa[3..] {
        let mut best = usize::MAX; let mut chosen = None; let mut ties = 0;
        for (mask, a, b) in parsimony::branches(&tree, outgroup, names, false) {
            let candidate = parsimony::insert(&tree, (a, b), taxon);
            let score = parsimony::score(&candidate, sequences, outgroup, names); evaluated += 1;
            if score < best { best = score; chosen = Some((mask, candidate)); ties = 1; }
            else if score == best { ties += 1; }
        }
        let (mask, next) = chosen.unwrap(); tree = next; additions.push(Addition { taxon, mask, score: best, ties });
    }
    Stepwise { tree, initial, additions, evaluated }
}
struct Hill { tree: Tree, moves: Vec<(u32, usize, f64)>, evaluated: usize }
fn hill<F: Fn(&Tree) -> f64>(start: &Tree, objective: F, outgroup: usize, names: &[String]) -> Hill {
    let mut tree = start.clone(); let mut value = objective(&tree); let mut moves = Vec::new(); let mut evaluated = 0;
    loop {
        let mut improvement = None;
        'branches: for (mask, parent, child) in parsimony::branches(&tree, outgroup, names, true) {
            for swap in 1..=2 {
                let candidate = parsimony::nni(&tree, parent, child, swap, outgroup, names);
                let next = objective(&candidate); evaluated += 1;
                if next < value { improvement = Some((candidate, mask, swap, next)); break 'branches; }
            }
        }
        if let Some((candidate, mask, swap, next)) = improvement { tree = candidate; value = next; moves.push((mask, swap, next)); }
        else { break; }
    }
    Hill { tree, moves, evaluated }
}
fn consensus(taxa: &[usize], clades: &BTreeSet<u32>, outgroup: usize, count: usize) -> Tree {
    let mut tree = Tree::empty(count); let root = tree.node(); tree.connect(root, outgroup, 0.0);
    let ingroup = taxa.iter().filter(|&&i| i != outgroup).fold(0u32, |m, &i| m|(1<<i));
    fn add(tree: &mut Tree, parent: usize, mask: u32, clades: &BTreeSet<u32>, count: usize) {
        let children: Vec<_> = clades.iter().copied().filter(|&c| c != mask && c&mask == c && !clades.iter().any(|&d| d != mask && d != c && d&mask == d && c&d == c)).collect();
        let covered = children.iter().fold(0u32, |m, &c| m|c);
        for child in children { let node = tree.node(); tree.connect(parent, node, 0.0); add(tree, node, child, clades, count); }
        for taxon in 0..count { if mask&(1<<taxon) != 0 && covered&(1<<taxon) == 0 { tree.connect(parent, taxon, 0.0); } }
    }
    add(&mut tree, root, ingroup, clades, count); tree
}
fn likelihood(tree: &Tree, sequences: &[Vec<u8>], outgroup: usize, names: &[String]) -> Vec<f64> {
    let rooted = tree.root(outgroup, names);
    (0..sequences[0].len()).map(|column| {
        let mut partial = vec![[0.0; 4]; tree.adjacency.len()];
        for &node in &rooted.postorder {
            if node < tree.taxa_count {
                let set = alignment::base_set(sequences[node][column]).unwrap();
                for base in 0..4 { partial[node][base] = if set&(1<<base) != 0 { 1.0 } else { 0.0 }; }
            } else {
                partial[node] = [1.0; 4];
                for &child in &rooted.children[node] {
                    let length = tree.adjacency[node][&child]; let e = (-(4.0*length)/3.0).exp();
                    for x in 0..4 {
                        let mut sum = 0.0;
                        for y in 0..4 {
                            let probability = if x == y { 1.0/4.0+(3.0/4.0)*e } else { 1.0/4.0-(1.0/4.0)*e };
                            sum += probability*partial[child][y];
                        }
                        partial[node][x] *= sum;
                    }
                }
            }
        }
        (0..4).map(|x| (1.0/4.0)*partial[rooted.root][x]).sum::<f64>().ln()
    }).collect()
}
fn rf(a: &BTreeSet<u32>, b: &BTreeSet<u32>) -> usize { a.symmetric_difference(b).count() }
fn quartets(splits: &BTreeSet<u32>, n: usize) -> Vec<usize> {
    let mut result = Vec::new();
    for a in 0..n { for b in a+1..n { for c in b+1..n { for d in c+1..n {
        let mut topology = 0;
        for (i, (x, y, z, w)) in [(a, b, c, d), (a, c, b, d), (a, d, b, c)].iter().copied().enumerate() {
            let first = (1<<x)|(1<<y); let second = (1<<z)|(1<<w);
            if splits.iter().any(|&mask| (mask&first == first && mask&second == 0) || (mask&second == second && mask&first == 0)) { topology = i+1; break; }
        }
        result.push(topology);
    } } } }
    result
}
fn matrix_lines(matrix: &[Vec<f64>], names: &[String]) -> Vec<String> {
    let width = names.iter().map(String::len).max().unwrap();
    names.iter().enumerate().map(|(i, name)| format!("{:<width$} {}", name, matrix[i].iter().map(|&v| real(v, 5)).collect::<Vec<_>>().join(" "), width=width)).collect()
}
fn symbol_order(masks: impl IntoIterator<Item=u32>, count: usize) -> Vec<u32> {
    let mut masks: Vec<_> = masks.into_iter().collect(); masks.sort_by_key(|&mask| symbols(mask, count)); masks
}

fn main() {
    let params = params();
    let records = alignment::read(); let record_count = records.len(); let columns = records[0].sequence.len();
    let mut seen = BTreeSet::new(); let mut accepted = Vec::new(); let mut rejected = Vec::new();
    for record in records {
        let duplicate = !seen.insert(record.name.clone());
        let reason = if duplicate { Some("duplicate name".to_owned()) }
            else if let Some((i, &c)) = record.sequence.iter().enumerate().find(|(_, c)| alignment::base_set(**c).is_none()) {
                Some(format!("invalid character {} at column {}", c as char, i+1))
            } else if record.sequence.len() != columns { Some(format!("length mismatch {}", record.sequence.len())) }
            else {
                let missing = record.sequence.iter().filter(|&&c| c == b'N' || c == b'-').count();
                if 100*missing > params.missing*columns { Some(format!("too many missing {}", missing)) } else { None }
            };
        if let Some(reason) = reason { rejected.push(format!("REJECT line {} {} {}", record.line, record.name, reason)); } else { accepted.push(record); }
    }
    let n = accepted.len(); let names: Vec<_> = accepted.iter().map(|r| r.name.clone()).collect();
    let sequences: Vec<_> = accepted.iter().map(|r| r.sequence.clone()).collect();
    let outgroup = names.iter().position(|name| name == &params.outgroup).unwrap();
    let taxa: Vec<_> = (0..n).collect(); let ingroup: Vec<_> = taxa.iter().copied().filter(|&i| i != outgroup).collect();
    let ingroup_mask = ingroup.iter().fold(0u32, |m, &i| m|(1<<i));
    let mut summary = vec![format!("INPUT records {} accepted {} rejected {} columns {}", record_count, n, rejected.len(), columns)]; summary.extend(rejected);
    let mut composition = [0; 4];
    for (i, record) in accepted.iter().enumerate() {
        let bases = record.sequence.iter().filter(|&&c| alignment::base(c)).count();
        let missing = record.sequence.iter().filter(|&&c| c == b'N' || c == b'-').count();
        let unique = (0..columns).filter(|&c| alignment::base(record.sequence[c]) && (0..n).any(|j| j != i && alignment::base(sequences[j][c]))
            && (0..n).all(|j| j == i || sequences[j][c] != record.sequence[c])).count();
        let gc = record.sequence.iter().filter(|&&c| c == b'C' || c == b'G').count();
        for &c in &record.sequence { if alignment::base(c) { composition[alignment::base_set(c).unwrap().trailing_zeros() as usize] += 1; } }
        summary.push(format!("TAXON {} bases {} ambiguous {} missing {} unique {} gc {}", record.name, bases, columns-bases-missing, missing, unique, real(gc as f64/bases as f64, 4)));
    }
    let [constant, variable, informative, gapped, empty] = alignment::classify(&accepted);
    let (patterns, pattern_counts) = alignment::patterns(&accepted);
    summary.push(format!("COLUMNS constant {} variable {} informative {} gapped {} empty {}", constant, variable, informative, gapped, empty));
    summary.push(format!("PATTERNS {}", pattern_counts.len()));
    let total: usize = composition.iter().sum(); summary.push(format!("COMPOSITION A {} C {} G {} T {}", real(composition[0] as f64/total as f64, 4), real(composition[1] as f64/total as f64, 4), real(composition[2] as f64/total as f64, 4), real(composition[3] as f64/total as f64, 4)));
    let weights = vec![1; columns];
    let models = ["P", "JC", "K2P"]; let main_model = models.iter().position(|&m| m == params.model).unwrap();
    let matrices: Vec<_> = models.iter().map(|model| distances::matrix(&accepted, &weights, model, params.saturated)).collect();
    let nj: Vec<_> = matrices.iter().map(|matrix| tree_building::nj(matrix, &taxa)).collect();
    let main_matrix = &matrices[main_model]; let main_nj = &nj[main_model];
    let main_splits = main_nj.splits(outgroup, &names);
    let mut distance_lines = Vec::new(); let mut totals = [0; 3];
    for i in 0..n { for j in i+1..n {
        let count = distances::tally(&sequences[i], &sequences[j], &weights); totals[0] += count.sites; totals[1] += count.transitions; totals[2] += count.transversions;
        distance_lines.push(format!("PAIR {} {} sites {} transitions {} transversions {}", names[i], names[j], count.sites, count.transitions, count.transversions));
    } }
    distance_lines.push(format!("TOTAL sites {} transitions {} transversions {}", totals[0], totals[1], totals[2]));
    for (model, &name) in models.iter().enumerate() {
        distance_lines.push(String::new()); distance_lines.push(format!("MODEL {}", name)); distance_lines.extend(matrix_lines(&matrices[model], &names));
        for i in 0..n { for j in i+1..n {
            let count = distances::tally(&sequences[i], &sequences[j], &weights);
            if distances::corrected(count, name, params.saturated).1 { distance_lines.push(format!("SATURATED {} {} sites {}", names[i], names[j], count.sites)); }
        } }
    }
    distance_lines.push(String::new()); distance_lines.push(format!("PATRISTIC NJ_{}", params.model)); distance_lines.extend(matrix_lines(&main_nj.patristic(), &names));
    let me = hill(main_nj, |tree| bme(tree, main_matrix), outgroup, &names);
    distance_lines.extend([String::new(), format!("ME start NJ_{} length {}", params.model, real(bme(main_nj, main_matrix), 5))]);
    for &(mask, swap, value) in &me.moves { distance_lines.push(format!("NNI edge {} swap {} length {}", symbols(mask, n), swap, real(value, 5))); }
    distance_lines.push(format!("ME moves {} evaluated {} length {}", me.moves.len(), me.evaluated, real(bme(&me.tree, main_matrix), 5)));
    let ordered: Vec<_> = std::iter::once(outgroup).chain(ingroup.iter().copied()).collect();
    let addition = stepwise(&ordered, &sequences, outgroup, &names);
    let mp = hill(&addition.tree, |tree| parsimony::score(tree, &sequences, outgroup, &names) as f64, outgroup, &names);
    let mut mp_tree = mp.tree.clone();
    let (ancestors, branch_changes, mp_columns) = parsimony::reconstruct(&mut mp_tree, &sequences, outgroup, &names);
    let mp_score: usize = mp_columns.iter().sum();
    let mut minimum_columns = Vec::new(); let mut maximum_columns = Vec::new();
    for c in 0..columns {
        let sets: Vec<_> = sequences.iter().map(|s| alignment::base_set(s[c]).unwrap()).collect();
        minimum_columns.push((1u8..16).filter(|&set| sets.iter().all(|s| set&s != 0)).map(u8::count_ones).min().unwrap() as usize-1);
        maximum_columns.push([1, 2, 4, 8].iter().map(|&base| sets.iter().filter(|&&s| s&base == 0).count()).min().unwrap());
    }
    let minimum: usize = minimum_columns.iter().sum(); let maximum: usize = maximum_columns.iter().sum();
    let mut parsimony_lines = vec![format!("BOUNDS minimum {} maximum {}", minimum, maximum)];
    let score_line = |method: &str, score: usize| format!("TREE {} score {} ci {} ri {}", method, score, real(minimum as f64/score as f64, 4), real((maximum-score) as f64/(maximum-minimum) as f64, 4));
    for i in 0..3 { parsimony_lines.push(score_line(&format!("NJ_{}", models[i]), parsimony::score(&nj[i], &sequences, outgroup, &names))); }
    parsimony_lines.push(format!("START {} {} {} score {}", names[ordered[0]], names[ordered[1]], names[ordered[2]], addition.initial));
    for a in &addition.additions { parsimony_lines.push(format!("ADD {} edge {} score {} ties {}", names[a.taxon], symbols(a.mask, n), a.score, a.ties)); }
    parsimony_lines.push(format!("STEPWISE score {} evaluated {}", parsimony::score(&addition.tree, &sequences, outgroup, &names), addition.evaluated));
    for &(mask, swap, score) in &mp.moves { parsimony_lines.push(format!("NNI edge {} swap {} score {}", symbols(mask, n), swap, score as usize)); }
    parsimony_lines.push(format!("SEARCH moves {} evaluated {} score {}", mp.moves.len(), mp.evaluated, mp_score));
    parsimony_lines.push(score_line("MP", mp_score)); parsimony_lines.push(format!("MP {}", newick(&mp_tree, outgroup, &names, true, None)));
    for changes in 0..=*mp_columns.iter().max().unwrap() { parsimony_lines.push(format!("CHANGES {} columns {}", changes, mp_columns.iter().filter(|&&v| v == changes).count())); }
    parsimony_lines.push(format!("HOMOPLASY columns {} extra {}", mp_columns.iter().zip(&minimum_columns).filter(|(a, b)| a > b).count(), mp_score-minimum));
    for mask in symbol_order(ancestors.keys().copied(), n) { parsimony_lines.push(format!("ANCESTOR {} {}", symbols(mask, n), ancestors[&mask])); }
    let exhaustive_taxa: Vec<_> = std::iter::once(outgroup).chain(ingroup.iter().copied().filter(|&i| params.exhaustive.contains(&names[i]))).collect();
    let mut exhaustive = vec![star(&exhaustive_taxa[..3], n)];
    for &taxon in &exhaustive_taxa[3..] {
        let mut next = Vec::new();
        for tree in &exhaustive { for (_, a, b) in parsimony::branches(tree, outgroup, &names, false) { next.push(parsimony::insert(tree, (a, b), taxon)); } }
        exhaustive = next;
    }
    let exhaustive_scores: Vec<_> = exhaustive.iter().map(|tree| parsimony::score(tree, &sequences, outgroup, &names)).collect();
    let exhaustive_bme: Vec<_> = exhaustive.iter().map(|tree| bme(tree, main_matrix)).collect();
    let exhaustive_splits: Vec<_> = exhaustive.iter().map(|tree| tree.splits(outgroup, &names)).collect();
    let best_score = *exhaustive_scores.iter().min().unwrap();
    let mut optimal: Vec<_> = (0..exhaustive.len()).filter(|&i| exhaustive_scores[i] == best_score).collect();
    optimal.sort_by_key(|&i| newick(&exhaustive[i], outgroup, &names, false, None));
    let common: BTreeSet<_> = exhaustive_splits[optimal[0]].iter().copied().filter(|c| optimal.iter().all(|&i| exhaustive_splits[i].contains(c))).collect();
    let strict = consensus(&exhaustive_taxa, &common, outgroup, n);
    let mut bme_order: Vec<_> = (0..exhaustive.len()).collect();
    bme_order.sort_by(|&a, &b| exhaustive_bme[a].total_cmp(&exhaustive_bme[b]).then_with(|| newick(&exhaustive[a], outgroup, &names, false, None).cmp(&newick(&exhaustive[b], outgroup, &names, false, None))));
    distance_lines.push(format!("EXHAUSTIVE taxa {} trees {} best {} second {}", exhaustive_taxa.len(), exhaustive.len(), real(exhaustive_bme[bme_order[0]], 5), real(exhaustive_bme[bme_order[1]], 5)));
    distance_lines.push(format!("BEST {} parsimony {}", newick(&exhaustive[bme_order[0]], outgroup, &names, false, None), exhaustive_scores[bme_order[0]]));
    parsimony_lines.extend([String::new(), format!("EXHAUSTIVE taxa {} trees {} best {} optimal {}", exhaustive_taxa.len(), exhaustive.len(), best_score, optimal.len())]);
    let mut score_counts = BTreeMap::<usize, usize>::new(); for &score in &exhaustive_scores { *score_counts.entry(score).or_default() += 1; }
    for (score, count) in score_counts { parsimony_lines.push(format!("SCORE {} trees {}", score, count)); }
    for &i in &optimal { parsimony_lines.push(format!("OPTIMAL {} bme {}", newick(&exhaustive[i], outgroup, &names, false, None), real(exhaustive_bme[i], 5))); }
    parsimony_lines.push(format!("STRICT {}", newick(&strict, outgroup, &names, false, None)));
    let heuristic_addition = stepwise(&exhaustive_taxa, &sequences, outgroup, &names);
    let heuristic = hill(&heuristic_addition.tree, |tree| parsimony::score(tree, &sequences, outgroup, &names) as f64, outgroup, &names);
    let heuristic_score = parsimony::score(&heuristic.tree, &sequences, outgroup, &names);
    parsimony_lines.push(format!("HEURISTIC score {} optimal {}", heuristic_score, if heuristic_score == best_score { "yes" } else { "no" }));
    let likelihoods: Vec<_> = nj.iter().map(|tree| likelihood(tree, &sequences, outgroup, &names)).collect();
    let mut likelihood_lines = vec![format!("LIKELIHOOD columns {} patterns {}", columns, pattern_counts.len())];
    for i in 0..3 { let value: f64 = likelihoods[i].iter().sum(); likelihood_lines.push(format!("TREE NJ_{} loglik {} per_site {}", models[i], real(value, 4), real(value/columns as f64, 4))); }
    for (a, b) in [(0, 1), (0, 2), (1, 2)] {
        let delta: Vec<_> = likelihoods[a].iter().zip(&likelihoods[b]).map(|(a, b)| a-b).collect();
        let difference: f64 = delta.iter().sum(); let mean = difference/columns as f64;
        let se = (columns as f64/(columns-1) as f64*delta.iter().map(|d| (d-mean)*(d-mean)).sum::<f64>()).sqrt();
        likelihood_lines.push(format!("KH NJ_{} NJ_{} difference {} se {} z {}", models[a], models[b], real(difference, 4), real(se, 4), real(difference/se, 4)));
    }
    likelihood_lines.push(format!("LOWEST NJ_{} sites {}", params.model, params.low));
    let mut low: Vec<_> = (0..columns).collect();
    low.sort_by(|&a, &b| real(likelihoods[main_model][a], 4).parse::<f64>().unwrap().total_cmp(&real(likelihoods[main_model][b], 4).parse::<f64>().unwrap()).then(a.cmp(&b)));
    let rooted = main_nj.root(outgroup, &names);
    for &c in low.iter().take(params.low) { likelihood_lines.push(format!("SITE {} loglik {} changes {} pattern {}", c+1, real(likelihoods[main_model][c], 4), parsimony::provisional(main_nj, &rooted, &sequences, c, outgroup).1, patterns[c])); }
    let mut bootstrap = vec![format!("BOOTSTRAP model {} replicates {} seed {}", params.model, params.replicates, params.seed)];
    let mut support = BTreeMap::<u32, usize>::new(); let mut state = params.seed; let mut identical = 0;
    for replicate in 1..=params.replicates {
        let mut weights = vec![0; columns];
        for _ in 0..columns { state = state*48271%2147483647; weights[state as usize%columns] += 1; }
        let matrix = distances::matrix(&accepted, &weights, &params.model, params.saturated);
        let tree = tree_building::nj(&matrix, &taxa); let splits = tree.splits(outgroup, &names); let distance = rf(&splits, &main_splits);
        identical += usize::from(distance == 0); for clade in splits { *support.entry(clade).or_default() += 1; }
        bootstrap.push(format!("REPLICATE {} distinct {} rf {}", replicate, weights.iter().filter(|&&w| w > 0).count(), distance));
    }
    bootstrap.push(format!("IDENTICAL {}", identical));
    for mask in symbol_order(main_splits.iter().copied(), n) { bootstrap.push(format!("SUPPORT {} {}", symbols(mask, n), support.get(&mask).copied().unwrap_or(0))); }
    let mut supported: Vec<_> = support.keys().copied().collect(); supported.sort_by_key(|&mask| (std::cmp::Reverse(support[&mask]), symbols(mask, n)));
    for mask in supported { bootstrap.push(format!("SPLIT {} {}", symbols(mask, n), support[&mask])); }
    let majority: BTreeSet<_> = support.iter().filter(|(_, &count)| 2*count > params.replicates).map(|(&mask, _)| mask).collect();
    let consensus = consensus(&taxa, &majority, outgroup, n);
    bootstrap.push(format!("CONSENSUS {}", newick(&consensus, outgroup, &names, false, Some(&support))));
    for &removed in &ingroup {
        let taxa: Vec<_> = taxa.iter().copied().filter(|&i| i != removed).collect(); let tree = tree_building::nj(main_matrix, &taxa);
        let projected: BTreeSet<_> = main_splits.iter().map(|&mask| mask&!(1<<removed)).filter(|mask| mask.count_ones() >= 2 && mask.count_ones() <= (n-3) as u32).collect();
        bootstrap.push(format!("JACKKNIFE {} rf {}", names[removed], rf(&tree.splits(outgroup, &names), &projected)));
    }
    let trees = [&nj[0], &nj[1], &nj[2], &me.tree, &mp_tree, &consensus]; let methods = ["NJ_P", "NJ_JC", "NJ_K2P", "ME", "MP", "CONSENSUS"];
    let splits: Vec<_> = trees.iter().map(|tree| tree.splits(outgroup, &names)).collect();
    let newicks: Vec<_> = trees.iter().enumerate().map(|(i, tree)| format!("{} {}", methods[i], newick(tree, outgroup, &names, i < 3 || i == 4, if i == 5 { Some(&support) } else { None }))).collect();
    let mut cladograms = Vec::new();
    for (i, tree) in trees.iter().enumerate() { if i > 0 { cladograms.push(String::new()); } cladograms.push(format!("TREE {}", methods[i])); cladograms.extend(tree_io::cladogram(tree, outgroup, &names, &support)); }
    let mut rates = Vec::new(); let mut rejected_rate = 0;
    for (a, &i) in ingroup.iter().enumerate() { for &j in &ingroup[a+1..] {
        let (mut first, mut second) = (0i64, 0i64);
        for c in 0..columns {
            let (a, b, o) = (sequences[i][c], sequences[j][c], sequences[outgroup][c]);
            if alignment::base(a) && alignment::base(b) && alignment::base(o) && a != b { first += i64::from(b == o); second += i64::from(a == o); }
        }
        let square = (first-second)*(first-second); let reject = 1000*square > 3841*(first+second); rejected_rate += usize::from(reject);
        rates.push(format!("RRT {} {} m1 {} m2 {} chi2 {} {}", names[i], names[j], first, second, if first+second == 0 { "-".to_owned() } else { real(square as f64/(first+second) as f64, 4) }, if reject { "reject" } else { "ok" }));
    } }
    let mut clock = vec![format!("RELATIVE_RATE outgroup {} pairs {} rejected {}", names[outgroup], rates.len(), rejected_rate)]; clock.extend(rates);
    let tips: Vec<_> = ingroup.iter().map(|&taxon| main_nj.path(rooted.root, taxon).1).collect();
    let mean = tips.iter().sum::<f64>()/tips.len() as f64; let sd = (tips.iter().map(|x| (x-mean)*(x-mean)).sum::<f64>()/(tips.len()-1) as f64).sqrt();
    clock.push(format!("ROOT_TO_TIP NJ_{} mean {} sd {} cv {}", params.model, real(mean, 5), real(sd, 5), real(sd/mean, 4)));
    for (i, &taxon) in ingroup.iter().enumerate() { clock.push(format!("TIP {} {}", names[taxon], real(tips[i], 5))); }
    let mut comparison = Vec::new();
    for i in 0..6 {
        let supported = splits[i].iter().filter(|mask| 2*support.get(mask).copied().unwrap_or(0) > params.replicates).count();
        let score = if i == 5 { "-".to_owned() } else { parsimony::score(trees[i], &sequences, outgroup, &names).to_string() };
        let bme_value = if i == 5 { "-".to_owned() } else { real(bme(trees[i], main_matrix), 5) };
        let length = if i < 3 { real(trees[i].adjacency.iter().enumerate().map(|(a, row)| row.iter().filter(|&(b, _)| a < *b).map(|(_, &length)| length).sum::<f64>()).sum(), 5) }
            else if i == 4 { real(mp_score as f64/columns as f64, 5) } else { "-".to_owned() };
        let (negative, error, likelihood) = if i < 3 {
            let patristic = nj[i].patristic(); let mut error = 0.0;
            for a in 0..n { for b in a+1..n { let residual = matrices[i][a][b]-patristic[a][b]; error += residual*residual; } }
            (nj[i].negative.to_string(), real(error, 6), real(likelihoods[i].iter().sum(), 4))
        } else { ("-".to_owned(), "-".to_owned(), "-".to_owned()) };
        comparison.push(format!("TREE {} splits {} supported {} parsimony {} bme {} length {} negative {} sse {} loglik {}", methods[i], splits[i].len(), supported, score, bme_value, length, negative, error, likelihood));
    }
    comparison.push(format!("RF {}", methods.join(" ")));
    for i in 0..6 { comparison.push(format!("{} {}", methods[i], (0..6).map(|j| rf(&splits[i], &splits[j]).to_string()).collect::<Vec<_>>().join(" "))); }
    let quartets: Vec<_> = splits.iter().map(|split| quartets(split, n)).collect();
    comparison.push(format!("QUARTET {}", methods.join(" ")));
    for i in 0..6 { comparison.push(format!("{} {}", methods[i], (0..6).map(|j| quartets[i].iter().zip(&quartets[j]).filter(|(a, b)| a != b).count().to_string()).collect::<Vec<_>>().join(" "))); }
    let clades: BTreeSet<_> = splits.iter().flat_map(|s| s.iter().copied()).collect();
    let main_lengths: BTreeMap<_, _> = parsimony::branches(main_nj, outgroup, &names, false).iter().map(|&(mask, a, b)| (mask, main_nj.adjacency[a][&b])).collect();
    for mask in symbol_order(clades.iter().copied(), n) {
        let marks: String = splits.iter().map(|s| if s.contains(&mask) { '+' } else { '-' }).collect();
        comparison.push(format!("CLADE {} support {} trees {} length {} changes {}", symbols(mask, n), support.get(&mask).copied().unwrap_or(0), marks,
            main_lengths.get(&mask).map_or_else(|| "-".to_owned(), |&v| real(v, 5)), branch_changes.get(&mask).map_or_else(|| "-".to_owned(), usize::to_string)));
    }
    let exhaustive_ingroup = exhaustive_taxa.iter().filter(|&&i| i != outgroup).fold(0u32, |m, &i| m|(1<<i));
    let mut hypotheses = Vec::new();
    for line in fs::read_to_string("input/clades.txt").unwrap().lines() {
        let words: Vec<_> = line.split_whitespace().collect(); let name = words[0]; let mut mask = 0u32; let mut unknown = None;
        for &word in &words[1..] { if let Some(i) = names.iter().position(|n| n == word) { mask |= 1<<i; } else { unknown = Some(word); break; } }
        if let Some(unknown) = unknown { hypotheses.push(format!("INVALID {} unknown taxon {}", name, unknown)); continue; }
        if mask&(1<<outgroup) != 0 { hypotheses.push(format!("INVALID {} contains outgroup", name)); continue; }
        hypotheses.push(format!("CLADE {} taxa {} support {}", name, mask.count_ones(), support.get(&mask).copied().unwrap_or(0)));
        for i in 0..6 {
            let common = splits[i].iter().copied().chain(std::iter::once(ingroup_mask)).filter(|&c| c&mask == mask).min_by_key(|c| c.count_ones()).unwrap();
            let intruders: Vec<_> = (0..n).filter(|&k| common&(1<<k) != 0 && mask&(1<<k) == 0).map(|k| names[k].clone()).collect();
            hypotheses.push(format!("TEST {} {} monophyletic {} mrca {} intruders {}", name, methods[i], if common == mask { "yes" } else { "no" }, common.count_ones(), if intruders.is_empty() { "-".to_owned() } else { intruders.join(",") }));
        }
        let subset = mask&exhaustive_ingroup;
        if subset.count_ones() < 2 || subset.count_ones() >= exhaustive_ingroup.count_ones() { hypotheses.push(format!("SUBSET {} untestable", name)); }
        else {
            let mut scores = [usize::MAX; 2]; let mut lengths = [f64::INFINITY; 2];
            for i in 0..exhaustive.len() { let category = usize::from(!exhaustive_splits[i].contains(&subset)); scores[category] = scores[category].min(exhaustive_scores[i]); lengths[category] = lengths[category].min(exhaustive_bme[i]); }
            hypotheses.push(format!("SUBSET {} taxa {} with {} without {} bme_with {} bme_without {}", name, subset.count_ones(), scores[0], scores[1], real(lengths[0], 5), real(lengths[1], 5)));
        }
    }
    for (file, lines) in [("summary.txt", summary), ("distances.txt", distance_lines), ("trees.nwk", newicks), ("cladograms.txt", cladograms),
        ("parsimony.txt", parsimony_lines), ("likelihood.txt", likelihood_lines), ("bootstrap.txt", bootstrap), ("clock.txt", clock), ("comparison.txt", comparison), ("hypotheses.txt", hypotheses)] { tree_io::write(file, &lines); }
}
