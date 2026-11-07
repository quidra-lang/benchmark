mod dataset;
mod gaussian;
mod em;
mod kmeans;
mod report;

use gaussian::{Component, Point};
use report::{real, fixed, optional, rounded};
use std::{collections::BTreeSet, io};

fn maximum(values: &[f64]) -> usize {
    let mut best = 0;
    for j in 1..values.len() { if values[j] > values[best] { best = j; } }
    best
}

fn assignment(responsibilities: &[Vec<f64>]) -> Vec<usize> {
    responsibilities.iter().map(|r| maximum(r)).collect()
}

fn sizes(assignment: &[usize], k: usize) -> Vec<usize> {
    let mut result = vec![0; k];
    for &j in assignment { result[j] += 1; }
    result
}

fn integers(values: &[usize]) -> String {
    values.iter().map(ToString::to_string).collect::<Vec<_>>().join(" ")
}

fn components(values: &[usize]) -> String {
    values.iter().map(|j| (j + 1).to_string()).collect::<Vec<_>>().join(" ")
}

fn reals(values: &[f64]) -> String {
    values.iter().map(|&v| real(v)).collect::<Vec<_>>().join(" ")
}

fn entropy(values: &[f64]) -> f64 {
    -values.iter().map(|&r| if r == 0.0 { 0.0 } else { r * r.ln() }).sum::<f64>()
}

fn parameter_count(k: usize, kind: &str) -> usize {
    match kind { "FULL" => 6 * k - 1, "TIED" => 3 * k + 2, "DIAG" => 5 * k - 1, "SPHERICAL" => 4 * k - 1, _ => unreachable!() }
}

fn settled(trace: &[f64], tolerance: f64) -> usize {
    let last = *trace.last().unwrap();
    (0..trace.len()).find(|&t| trace[t..].iter().all(|v| (v - last).abs() <= tolerance)).unwrap()
}

struct Model {
    k: usize,
    kind: usize,
    parameters: usize,
    fit: em::Fit,
    assignment: Vec<usize>,
    entropy: f64,
    criteria: [f64; 3],
    settled: usize,
    violations: Vec<usize>,
}

fn model(points: &[Point], initial: &[Component], kind: usize, params: &dataset::Params) -> Model {
    let fit = em::fit(points, initial, &params.types[kind], params.iterations, params.regularization);
    let k = initial.len();
    let parameters = parameter_count(k, &params.types[kind]);
    let assigned = assignment(&fit.responsibilities);
    let entropy: f64 = fit.responsibilities.iter().map(|r| entropy(r)).sum();
    let likelihood = *fit.trace.last().unwrap();
    let bic = -2.0 * likelihood + parameters as f64 * (points.len() as f64).ln();
    let aic = -2.0 * likelihood + 2.0 * parameters as f64;
    let settled = settled(&fit.trace, params.tolerance);
    let violations = (1..fit.trace.len()).filter(|&t| fit.trace[t] < fit.trace[t - 1] - 0.000001 * fit.trace[t - 1].abs()).collect();
    Model { k, kind, parameters, fit, assignment: assigned, entropy, criteria: [bic, aic, bic + 2.0 * entropy], settled, violations }
}

fn ranking(models: &[Model], criterion: usize) -> Vec<usize> {
    let mut order: Vec<usize> = (0..models.len()).collect();
    order.sort_by_key(|&j| (rounded(models[j].criteria[criterion]), models[j].parameters, models[j].k, models[j].kind));
    order
}

fn contingency(first: &[usize], second: &[usize], a: usize, b: usize) -> Vec<Vec<usize>> {
    let mut table = vec![vec![0; b]; a];
    for (&i, &j) in first.iter().zip(second) { table[i][j] += 1; }
    table
}

fn ari(table: &[Vec<usize>]) -> String {
    let choose = |m: i64| m * (m - 1) / 2;
    let n = table.iter().map(|r| r.iter().sum::<usize>()).sum::<usize>() as i64;
    let z = choose(n);
    let s: i64 = table.iter().flat_map(|r| r.iter()).map(|&c| choose(c as i64)).sum();
    let a: i64 = table.iter().map(|r| choose(r.iter().sum::<usize>() as i64)).sum();
    let b: i64 = (0..table[0].len()).map(|j| choose(table.iter().map(|r| r[j]).sum::<usize>() as i64)).sum();
    let mut numerator = 2 * (z * s - a * b);
    let mut denominator = z * (a + b) - 2 * a * b;
    if denominator == 0 { numerator = 1; denominator = 1; }
    if denominator < 0 { numerator = -numerator; denominator = -denominator; }
    let (mut x, mut y) = (numerator.abs(), denominator);
    while y != 0 { let remainder = x % y; x = y; y = remainder; }
    numerator /= x;
    denominator /= x;
    format!("{}/{} {}", numerator, denominator, real(numerator as f64 / denominator as f64))
}

struct Indices {
    silhouette: Option<f64>,
    per_cluster: Vec<Option<f64>>,
    ch: Option<f64>,
    db: Option<f64>,
}

fn indices(points: &[Point], assigned: &[usize], k: usize) -> Indices {
    let groups: Vec<Vec<usize>> = (0..k).map(|j| (0..points.len()).filter(|&i| assigned[i] == j).collect()).collect();
    let nonempty: Vec<usize> = (0..k).filter(|&j| !groups[j].is_empty()).collect();
    let g = nonempty.len();
    if g < 2 { return Indices { silhouette: None, per_cluster: vec![None; k], ch: None, db: None }; }
    let mut silhouettes = vec![0.0; points.len()];
    for i in 0..points.len() {
        let own = assigned[i];
        if groups[own].len() == 1 { continue; }
        let a = groups[own].iter().filter(|&&j| j != i).map(|&j| kmeans::distance(points[i], points[j])).sum::<f64>() / (groups[own].len() - 1) as f64;
        let b = nonempty.iter().filter(|&&j| j != own).map(|&j| groups[j].iter().map(|&v| kmeans::distance(points[i], points[v])).sum::<f64>() / groups[j].len() as f64).fold(f64::INFINITY, f64::min);
        silhouettes[i] = (b - a) / a.max(b);
    }
    let silhouette = Some(silhouettes.iter().sum::<f64>() / points.len() as f64);
    let per_cluster = groups.iter().map(|group| if group.is_empty() { None } else { Some(group.iter().map(|&i| silhouettes[i]).sum::<f64>() / group.len() as f64) }).collect();
    let center = (points.iter().map(|p| p.0).sum::<f64>() / points.len() as f64, points.iter().map(|p| p.1).sum::<f64>() / points.len() as f64);
    let centers: Vec<Point> = groups.iter().map(|group| {
        if group.is_empty() { (0.0, 0.0) } else { (group.iter().map(|&i| points[i].0).sum::<f64>() / group.len() as f64,
            group.iter().map(|&i| points[i].1).sum::<f64>() / group.len() as f64) }
    }).collect();
    let bt = nonempty.iter().map(|&j| groups[j].len() as f64 * kmeans::squared(centers[j], center)).sum::<f64>();
    let wt = points.iter().enumerate().map(|(i, &p)| kmeans::squared(p, centers[assigned[i]])).sum::<f64>();
    let ch = Some((bt / (g - 1) as f64) / (wt / (points.len() - g) as f64));
    let scatter: Vec<f64> = groups.iter().enumerate().map(|(j, group)| {
        if group.is_empty() { 0.0 } else { group.iter().map(|&i| kmeans::distance(points[i], centers[j])).sum::<f64>() / group.len() as f64 }
    }).collect();
    let db = Some(nonempty.iter().map(|&j| nonempty.iter().filter(|&&v| v != j)
        .map(|&v| (scatter[j] + scatter[v]) / kmeans::distance(centers[j], centers[v])).fold(f64::NEG_INFINITY, f64::max)).sum::<f64>() / g as f64);
    Indices { silhouette, per_cluster, ch, db }
}

fn matching(table: &[Vec<usize>]) -> (Vec<usize>, usize) {
    fn visit(prefix: &mut Vec<usize>, table: &[Vec<usize>], best: &mut (Vec<usize>, usize)) {
        if prefix.len() == table.len() {
            let count = prefix.iter().enumerate().map(|(j, &i)| table[i][j]).sum();
            if best.0.is_empty() || count > best.1 { *best = (prefix.clone(), count); }
            return;
        }
        for i in 0..table.len() { if !prefix.contains(&i) { prefix.push(i); visit(prefix, table, best); prefix.pop(); } }
    }
    let mut best = (Vec::new(), 0);
    visit(&mut Vec::new(), table, &mut best);
    best
}

fn merge_entropy(responsibilities: &[Vec<f64>], clusters: &[Vec<usize>]) -> (f64, Vec<usize>) {
    let mut total = 0.0;
    let mut counts = vec![0; clusters.len()];
    for row in responsibilities {
        let values: Vec<f64> = clusters.iter().map(|c| c.iter().map(|&j| row[j]).sum()).collect();
        total += entropy(&values);
        counts[maximum(&values)] += 1;
    }
    (total, counts)
}

fn cluster_name(cluster: &[usize]) -> String {
    cluster.iter().map(|j| (j + 1).to_string()).collect::<Vec<_>>().join("+")
}

fn merging(model: &Model) -> Vec<String> {
    let mut clusters: Vec<Vec<usize>> = (0..model.k).map(|j| vec![j]).collect();
    let mut lines = vec!["merging".into(), format!("start entropy {}", real(merge_entropy(&model.fit.responsibilities, &clusters).0))];
    for step in 1..model.k {
        let mut best: Option<(i64, usize, usize, Vec<Vec<usize>>, f64, Vec<usize>)> = None;
        for a in 0..clusters.len() - 1 {
            for b in a + 1..clusters.len() {
                let mut merged = clusters.clone();
                let removed = merged.remove(b);
                merged[a].extend(removed);
                merged[a].sort();
                let (entropy, sizes) = merge_entropy(&model.fit.responsibilities, &merged);
                let key = (rounded(entropy), a, b);
                if best.as_ref().map_or(true, |old| key < (old.0, old.1, old.2)) { best = Some((key.0, a, b, merged, entropy, sizes)); }
            }
        }
        let (_, a, b, merged, entropy, sizes) = best.unwrap();
        lines.push(format!("step {} merge {} {} entropy {} sizes {}", step, cluster_name(&clusters[a]), cluster_name(&clusters[b]), real(entropy), integers(&sizes)));
        clusters = merged;
    }
    lines
}

fn maps(points: &[Point], model: &Model, params: &dataset::Params) -> Vec<String> {
    let (w, h) = params.size;
    let sx = (params.x.1 - params.x.0) / w as f64;
    let sy = (params.y.1 - params.y.0) / h as f64;
    let centers: Vec<Point> = (0..h).flat_map(|r| (0..w).map(move |c| (params.x.0 + (c as f64 + 0.5) * sx, params.y.1 - (r as f64 + 0.5) * sy))).collect();
    let logs: Vec<Vec<f64>> = centers.iter().map(|&p| model.fit.components.iter().map(|c| gaussian::log_density(p, c)).collect()).collect();
    let density: Vec<f64> = logs.iter().map(|row| row.iter().map(|l| l.exp()).sum()).collect();
    let maximum_density = density.iter().copied().fold(0.0, f64::max);
    let mass = density.iter().sum::<f64>() * sx * sy;
    let levels: Vec<usize> = density.iter().map(|&f| ((10.0 * f / maximum_density).floor() as usize).min(9)).collect();
    let characters: Vec<char> = " .:-=+*#%@".chars().collect();
    let mut density_map: Vec<Vec<char>> = levels.chunks(w).map(|row| row.iter().map(|&l| characters[l]).collect()).collect();
    let cell = |p: Point| {
        let c = ((p.0 - params.x.0) / sx).floor() as i64;
        let r = ((params.y.1 - p.1) / sy).floor() as i64;
        if c >= 0 && r >= 0 && c < w as i64 && r < h as i64 { Some((r as usize, c as usize)) } else { None }
    };
    for (j, component) in model.fit.components.iter().enumerate() { if let Some((r, c)) = cell(component.mean) { density_map[r][c] = (b'1' + j as u8) as char; } }
    let region_map: Vec<Vec<char>> = logs.chunks(w).map(|rows| rows.iter().map(|row| (b'1' + maximum(row) as u8) as char).collect()).collect();
    let responsibilities = em::expectation(&centers, &model.fit.components).0;
    let uncertainty: Vec<Vec<char>> = responsibilities.chunks(w).map(|rows| rows.iter().map(|row| {
        if model.k == 1 { ' ' } else { characters[((10.0 * entropy(row) / (model.k as f64).ln()).floor() as i64).max(0).min(9) as usize] }
    }).collect()).collect();
    let mut point_map = vec![vec![' '; w]; h];
    for r in 0..h {
        for c in 0..w {
            let contour = model.fit.components.iter().any(|component| {
                if gaussian::mahalanobis(centers[r * w + c], component.mean, component.covariance) > 4.0 { return false; }
                [(-1i64, 0i64), (1, 0), (0, -1), (0, 1)].iter().any(|&(dx, dy)| {
                    let (x, y) = (c as i64 + dx, r as i64 + dy);
                    x >= 0 && y >= 0 && x < w as i64 && y < h as i64
                        && gaussian::mahalanobis(centers[y as usize * w + x as usize], component.mean, component.covariance) > 4.0
                })
            });
            if contour { point_map[r][c] = '.'; }
        }
    }
    let mut contained = vec![vec![BTreeSet::new(); w]; h];
    let mut outside = 0;
    for (i, &point) in points.iter().enumerate() {
        if let Some((r, c)) = cell(point) { contained[r][c].insert(model.assignment[i]); } else { outside += 1; }
    }
    for r in 0..h {
        for c in 0..w {
            if contained[r][c].len() == 1 { point_map[r][c] = (b'1' + *contained[r][c].iter().next().unwrap() as u8) as char; }
            else if contained[r][c].len() > 1 { point_map[r][c] = '*'; }
        }
    }
    let mut lines = vec![format!("density K={} type={}", model.k, params.types[model.kind]), format!("x {} {} y {} {} grid {}x{}", real(params.x.0), real(params.x.1), real(params.y.0), real(params.y.1), w, h),
        format!("max_density {} mass_in_map {}", fixed(maximum_density, 6), real(mass))];
    lines.extend(report::frame(&density_map));
    for level in 0..10 { lines.push(format!("level {} \"{}\" from {} cells {}", level, characters[level], fixed(level as f64 * maximum_density / 10.0, 6), levels.iter().filter(|&&l| l == level).count())); }
    for (label, grid) in [("regions", region_map), ("uncertainty", uncertainty), ("points", point_map)] {
        lines.extend([String::new(), label.into()]);
        lines.extend(report::frame(&grid));
    }
    lines.push(format!("outside {}", outside));
    lines
}

fn main() -> io::Result<()> {
    let input = dataset::read()?;
    let points = &input.points;
    let params = &input.params;
    let n = points.len();
    let mut models = Vec::new();
    let mut partitions = Vec::new();
    for &k in &params.ks {
        for kind in 0..params.types.len() { models.push(model(points, &input.initial[&k], kind, params)); }
        let initial: Vec<Point> = input.initial[&k].iter().map(|c| c.mean).collect();
        partitions.push(kmeans::fit(points, &initial, params.kmeans_iterations));
    }
    let orders: Vec<Vec<usize>> = (0..3).map(|criterion| ranking(&models, criterion)).collect();
    let selected_index = orders[0][0];
    let selected = &models[selected_index];
    let k = selected.k;
    let km_index = params.ks.iter().position(|&v| v == k).unwrap();
    let km = &partitions[km_index];
    let best_per_k: Vec<usize> = params.ks.iter().map(|&k| *orders[0].iter().find(|&&i| models[i].k == k).unwrap()).collect();
    let ranks: Vec<Vec<usize>> = orders.iter().map(|order| {
        let mut ranks = vec![0; models.len()];
        for (rank, &i) in order.iter().enumerate() { ranks[i] = rank + 1; }
        ranks
    }).collect();
    let mut model_lines = Vec::new();
    let mut trace = vec!["K,type,iteration,loglik".into()];
    for (i, model) in models.iter().enumerate() {
        if i > 0 { model_lines.push(String::new()); }
        let fit = &model.fit;
        let mut largest = 1;
        for t in 2..fit.trace.len() { if fit.trace[t] - fit.trace[t - 1] > fit.trace[largest] - fit.trace[largest - 1] { largest = t; } }
        model_lines.extend([format!("model K={} type={}", model.k, params.types[model.kind]), format!("parameters {}", model.parameters), format!("loglik {}", real(*fit.trace.last().unwrap())),
            format!("bic {}", real(model.criteria[0])), format!("aic {}", real(model.criteria[1])), format!("icl {}", real(model.criteria[2])), format!("mean_entropy {}", real(model.entropy / n as f64)),
            format!("settled_at {}", model.settled), format!("largest_increase iteration {} value {}", largest, real(fit.trace[largest] - fit.trace[largest - 1])),
            format!("violations {}", model.violations.len()), format!("sizes {}", integers(&sizes(&model.assignment, model.k)))]);
        for (j, component) in fit.components.iter().enumerate() {
            let ellipse = gaussian::ellipse(component.covariance);
            model_lines.push(format!("component {} weight {} mean {} {} cov {} axes {} {} angle {}", j + 1, real(component.weight), real(component.mean.0), real(component.mean.1),
                reals(&component.covariance), real(ellipse.eigenvalues[0].sqrt()), real(ellipse.eigenvalues[1].sqrt()), real(ellipse.angle)));
        }
        for (t, &likelihood) in fit.trace.iter().enumerate() { trace.push(format!("{},{},{},{}", model.k, params.types[model.kind], t, real(likelihood))); }
    }
    let mut parts: Vec<Vec<String>> = Vec::new();
    let mut lines = vec!["ranking by bic".into(), "rank K type parameters loglik bic delta_bic aic aic_rank icl icl_rank".into()];
    for (rank, &i) in orders[0].iter().enumerate() {
        let m = &models[i];
        let delta = (rounded(m.criteria[0]) - rounded(selected.criteria[0])) as f64 / 10000.0;
        lines.push(format!("{} {} {} {} {} {} {} {} {} {} {}", rank + 1, m.k, params.types[m.kind], m.parameters, real(*m.fit.trace.last().unwrap()), real(m.criteria[0]), real(delta),
            real(m.criteria[1]), ranks[1][i], real(m.criteria[2]), ranks[2][i]));
    }
    lines.extend([format!("selected K={} type={}", k, params.types[selected.kind]), format!("best_aic K={} type={}", models[orders[1][0]].k, params.types[models[orders[1][0]].kind]),
        format!("best_icl K={} type={}", models[orders[2][0]].k, params.types[models[orders[2][0]].kind])]);
    parts.push(lines);
    let mut lines = vec!["best K per type".into()];
    for kind in 0..params.types.len() {
        let best: Vec<usize> = orders.iter().map(|order| models[*order.iter().find(|&&i| models[i].kind == kind).unwrap()].k).collect();
        lines.push(format!("{} bic {} aic {} icl {}", params.types[kind], best[0], best[1], best[2]));
    }
    parts.push(lines);
    for (i, &model_index) in best_per_k.iter().enumerate() {
        let model = &models[model_index];
        let km = &partitions[i];
        let a = indices(points, &model.assignment, model.k);
        let b = indices(points, &km.assignment, model.k);
        let table = contingency(&model.assignment, &km.assignment, model.k, model.k);
        let mut lines = vec![format!("K={} type={} bic {}", model.k, params.types[model.kind], real(model.criteria[0])),
            format!("  kmeans iterations {} inertia {}", km.iterations, real(km.inertia)), format!("  ari {}", ari(&table)),
            format!("  silhouette gmm {} kmeans {}", optional(a.silhouette), optional(b.silhouette)), format!("  calinski_harabasz gmm {} kmeans {}", optional(a.ch), optional(b.ch)),
            format!("  davies_bouldin gmm {} kmeans {}", optional(a.db), optional(b.db))];
        if i > 0 {
            let previous = &models[best_per_k[i - 1]];
            let table = contingency(&previous.assignment, &model.assignment, previous.k, model.k);
            let mut parents = Vec::new();
            let mut shared = Vec::new();
            for j in 0..model.k {
                let counts: Vec<usize> = table.iter().map(|r| r[j]).collect();
                let winner = (0..previous.k).min_by_key(|&a| (std::cmp::Reverse(counts[a]), a)).unwrap();
                parents.push(if counts[winner] == 0 { "-".into() } else { (winner + 1).to_string() });
                shared.push(counts[winner]);
            }
            lines.push(format!("  parents K={} {} shared {}", previous.k, parents.join(" "), integers(&shared)));
        }
        parts.push(lines);
    }
    let mut lines = vec!["violations".into()];
    for model in &models {
        for &t in &model.violations { lines.push(format!("K={} type={} iteration {} previous {} current {}", model.k, params.types[model.kind], t, real(model.fit.trace[t - 1]), real(model.fit.trace[t]))); }
    }
    if lines.len() == 1 { lines.push("none".into()); }
    parts.push(lines);
    let selected_indices = indices(points, &selected.assignment, k);
    let counts = sizes(&selected.assignment, k);
    let mut lines = vec!["selected components".into()];
    for (j, component) in selected.fit.components.iter().enumerate() {
        let ellipse = gaussian::ellipse(component.covariance);
        let eigen = ellipse.eigenvalues;
        let q: Vec<f64> = points.iter().map(|&p| gaussian::mahalanobis(p, component.mean, component.covariance)).collect();
        let owned: Vec<usize> = (0..n).filter(|&i| selected.assignment[i] == j).collect();
        let mut observed = vec![0; params.edges.len() + 1];
        for &i in &owned { let bin = params.edges.iter().filter(|&&edge| q[i].sqrt() >= edge).count(); observed[bin] += 1; }
        let mut expected = Vec::new();
        for bin in 0..=params.edges.len() {
            let lower = if bin == 0 { 0.0 } else { params.edges[bin - 1] };
            let upper_probability = if bin == params.edges.len() { 0.0 } else { (-params.edges[bin] * params.edges[bin] / 2.0).exp() };
            expected.push(counts[j] as f64 * ((-lower * lower / 2.0).exp() - upper_probability));
        }
        let chi2 = observed.iter().zip(&expected).map(|(&o, &e)| (o as f64 - e) * (o as f64 - e) / e).sum::<f64>();
        lines.extend([format!("component {} weight {} size {} soft_size {} mean {} {}", j + 1, real(component.weight), counts[j],
            real(selected.fit.responsibilities.iter().map(|r| r[j]).sum()), real(component.mean.0), real(component.mean.1)),
            format!("  cov {} corr {}", reals(&component.covariance), real(component.covariance[1] / (component.covariance[0] * component.covariance[2]).sqrt())),
            format!("  eigen {} direction {} {} angle {}", reals(&eigen), real(ellipse.direction.0), real(ellipse.direction.1), real(ellipse.angle)),
            format!("  axes_1sigma {} {} axes_2sigma {} {}", real(eigen[0].sqrt()), real(eigen[1].sqrt()), real(2.0 * eigen[0].sqrt()), real(2.0 * eigen[1].sqrt())),
            format!("  inside_1sigma {} inside_2sigma {} area_1sigma {}", owned.iter().filter(|&&i| q[i] <= 1.0).count(), owned.iter().filter(|&&i| q[i] <= 4.0).count(),
                real(std::f64::consts::PI * (eigen[0] * eigen[1]).sqrt())), format!("  silhouette {}", optional(selected_indices.per_cluster[j])),
            format!("  gof observed {} expected {} chi2 {}", integers(&observed), reals(&expected), real(chi2))]);
    }
    parts.push(lines);
    let mut lines = vec!["overlap".into()];
    for a in 0..k {
        for b in a + 1..k {
            let distance = gaussian::bhattacharyya(&selected.fit.components[a], &selected.fit.components[b]);
            let shared: f64 = selected.fit.responsibilities.iter().map(|r| r[a] * r[b]).sum();
            lines.push(format!("{}-{} bhattacharyya {} coefficient {} shared {}", a + 1, b + 1, real(distance), real((-distance).exp()), real(shared)));
        }
    }
    if k == 1 { lines.push("none".into()); }
    parts.push(lines);
    parts.push(merging(selected));
    let table = contingency(&selected.assignment, &km.assignment, k, k);
    let (permutation, agreement) = matching(&table);
    let mut lines = vec![format!("kmeans K={}", k), format!("iterations {}", km.iterations), format!("inertia {}", real(km.inertia)), format!("sizes {}", integers(&sizes(&km.assignment, k)))];
    for j in 0..k { lines.push(format!("center {} {} {}", j + 1, real(km.centers[j].0), real(km.centers[j].1))); }
    lines.push("contingency".into());
    lines.extend(table.iter().map(|r| integers(r)));
    lines.extend([format!("ari {}", ari(&table)), format!("matching {}", components(&permutation)), format!("agreement {}/{} {}", agreement, n, real(agreement as f64 / n as f64))]);
    let mut disagreements = 0;
    for i in 0..n {
        if permutation[km.assignment[i]] != selected.assignment[i] {
            disagreements += 1;
            lines.push(format!("disagree {} gmm {} kmeans {} max {}", input.ids[i], selected.assignment[i] + 1, km.assignment[i] + 1, real(selected.fit.responsibilities[i][selected.assignment[i]])));
        }
    }
    lines.push(format!("disagreements {}", disagreements));
    parts.push(lines);
    let mut initial = Vec::new();
    for j in 0..k {
        let selected_points: Vec<Point> = points.iter().enumerate().filter(|(i, _)| km.assignment[*i] == j).map(|(_, &p)| p).collect();
        let center = km.centers[j];
        let count = selected_points.len() as f64;
        let a = selected_points.iter().map(|p| (p.0 - center.0) * (p.0 - center.0)).sum::<f64>() / count + params.regularization;
        let b = selected_points.iter().map(|p| (p.0 - center.0) * (p.1 - center.1)).sum::<f64>() / count;
        let c = selected_points.iter().map(|p| (p.1 - center.1) * (p.1 - center.1)).sum::<f64>() / count + params.regularization;
        initial.push(Component { weight: count / n as f64, mean: center, covariance: [a, b, c] });
    }
    let refit = model(points, &initial, selected.kind, params);
    parts.push(vec![format!("refit_from_kmeans K={} type={}", k, params.types[selected.kind]), format!("loglik {} bic {} settled_at {}", real(*refit.fit.trace.last().unwrap()), real(refit.criteria[0]), refit.settled),
        format!("sizes {}", integers(&sizes(&refit.assignment, k))), format!("ari_vs_selected {}", ari(&contingency(&selected.assignment, &refit.assignment, k, k)))]);
    let mut lines = vec![format!("cross_validation K={} type={} folds {}", k, params.types[selected.kind], params.folds)];
    let mut test_scores = Vec::new();
    for fold in 0..params.folds {
        let train: Vec<Point> = points.iter().enumerate().filter(|(i, _)| i % params.folds != fold).map(|(_, &p)| p).collect();
        let test: Vec<Point> = points.iter().enumerate().filter(|(i, _)| i % params.folds == fold).map(|(_, &p)| p).collect();
        let fit = em::fit(&train, &input.initial[&k], &params.types[selected.kind], params.iterations, params.regularization);
        let training = *fit.trace.last().unwrap() / train.len() as f64;
        let testing = em::expectation(&test, &fit.components).1.iter().sum::<f64>() / test.len() as f64;
        test_scores.push(testing);
        lines.push(format!("fold {} train {} test {} train_loglik {} test_loglik {}", fold + 1, train.len(), test.len(), real(training), real(testing)));
    }
    lines.push(format!("mean_test_loglik {}", real(test_scores.iter().sum::<f64>() / params.folds as f64)));
    parts.push(lines);
    let maxima: Vec<f64> = selected.fit.responsibilities.iter().map(|r| r[maximum(r)]).collect();
    let mut uncertain: Vec<usize> = (0..n).filter(|&i| maxima[i] < params.uncertain).collect();
    uncertain.sort_by_key(|&i| (rounded(maxima[i]), i));
    let mut lines = vec![format!("uncertain threshold {}", real(params.uncertain))];
    for &i in &uncertain { lines.push(format!("{} component {} max {} responsibilities {}", input.ids[i], selected.assignment[i] + 1, real(maxima[i]), reals(&selected.fit.responsibilities[i]))); }
    lines.push(format!("count {}", uncertain.len()));
    parts.push(lines);
    let mut outliers: Vec<usize> = (0..n).filter(|&i| selected.fit.log_density[i] < params.low_density).collect();
    outliers.sort_by_key(|&i| (rounded(selected.fit.log_density[i]), i));
    let mut lines = vec![format!("outliers threshold {}", real(params.low_density))];
    for &i in &outliers {
        let component = &selected.fit.components[selected.assignment[i]];
        lines.push(format!("{} component {} log_density {} q {}", input.ids[i], selected.assignment[i] + 1, real(selected.fit.log_density[i]), real(gaussian::mahalanobis(points[i], component.mean, component.covariance))));
    }
    lines.push(format!("count {}", outliers.len()));
    parts.push(lines);
    let mut selection_lines = Vec::new();
    for (i, part) in parts.into_iter().enumerate() {
        if i > 0 { selection_lines.push(String::new()); }
        selection_lines.extend(part);
    }
    let mut assignments = vec!["id,component,max_responsibility,log_density,kmeans_cluster".into()];
    for i in 0..n { assignments.push(format!("{},{},{},{},{}", input.ids[i], selected.assignment[i] + 1, real(maxima[i]), real(selected.fit.log_density[i]), km.assignment[i] + 1)); }
    report::write("models.txt", &model_lines)?;
    report::write("loglik_trace.csv", &trace)?;
    report::write("assignments.csv", &assignments)?;
    report::write("selection.txt", &selection_lines)?;
    report::write("density_map.txt", &maps(points, selected, params))?;
    Ok(())
}
