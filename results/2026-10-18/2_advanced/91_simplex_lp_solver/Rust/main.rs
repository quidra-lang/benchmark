mod rational;
mod lp_parser;
mod tableau;
mod simplex;
mod branch_bound;
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use rational::Fraction as F;
pub type Bounds = Vec<(Option<F>, Option<F>)>;
pub struct Model {
    pub name: String, pub maximize: bool, pub names: Vec<String>, pub c: Vec<F>, pub a: Vec<Vec<F>>,
    pub rhs: Vec<F>, pub comparisons: Vec<String>, pub row_names: Vec<String>, pub bounds: Bounds, pub integer: Vec<bool>
}
fn content(name: &str, parsed: &lp_parser::Parsed) -> Result<Model, (usize, String)> {
    let mut names = Vec::new();
    for (name, _) in parsed.objective.iter().chain(parsed.constraints.iter().flat_map(|c| c.terms.iter())) {
        if !names.contains(name) { names.push(name.clone()); }
    }
    let index: BTreeMap<_, _> = names.iter().enumerate().map(|(i, name)| (name.clone(), i)).collect();
    let coefficients = |terms: &lp_parser::Terms| {
        let mut values = vec![F::zero(); names.len()];
        for (name, value) in terms { values[index[name]] = values[index[name]] + *value; }
        values
    };
    let c = coefficients(&parsed.objective);
    let a = parsed.constraints.iter().map(|c| coefficients(&c.terms)).collect();
    let mut seen = BTreeSet::new();
    for constraint in &parsed.constraints {
        if !seen.insert(constraint.name.clone()) { return Err((constraint.line, format!("duplicate constraint {}", constraint.name))); }
    }
    let mut bounds = vec![(Some(F::zero()), None); names.len()];
    let mut integer = vec![false; names.len()];
    for bound in &parsed.bounds {
        let i = *index.get(&bound.name).ok_or_else(|| (bound.line, format!("unknown variable {}", bound.name)))?;
        if let Some(lower) = bound.lower { bounds[i].0 = lower; }
        if let Some(upper) = bound.upper { bounds[i].1 = upper; }
        if let (Some(lower), Some(upper)) = bounds[i] {
            if lower > upper { return Err((bound.line, format!("inconsistent bounds {}", bound.name))); }
        }
    }
    for (line, declarations) in &parsed.integers {
        for name in declarations {
            let i = *index.get(name).ok_or_else(|| (*line, format!("unknown variable {}", name)))?;
            integer[i] = true;
            bounds[i].0 = bounds[i].0.map(|value| F::integer(value.ceil()));
            bounds[i].1 = bounds[i].1.map(|value| F::integer(value.floor()));
            if let (Some(lower), Some(upper)) = bounds[i] {
                if lower > upper { return Err((*line, format!("inconsistent bounds {}", name))); }
            }
        }
    }
    for (line, declarations) in &parsed.binaries {
        for name in declarations {
            let i = *index.get(name).ok_or_else(|| (*line, format!("unknown variable {}", name)))?;
            integer[i] = true;
            bounds[i] = (Some(F::zero()), Some(F::integer(1)));
        }
    }
    Ok(Model { name: name.into(), maximize: parsed.maximize, names, c, a, rhs: parsed.constraints.iter().map(|c| c.rhs).collect(), comparisons: parsed.constraints.iter().map(|c| c.comparison.clone()).collect(), row_names: parsed.constraints.iter().map(|c| c.name.clone()).collect(), bounds, integer })
}
#[derive(Clone)]
struct Substitution { kind: &'static str, offset: F, columns: Vec<(usize, F)> }
#[derive(Clone)]
struct Standard {
    columns: Vec<String>, rows: Vec<String>, signs: Vec<F>, initial: Vec<usize>, slacks: Vec<Option<usize>>,
    artificial: BTreeSet<usize>, phase1: Vec<F>, phase2: Vec<F>, constant: F, sign: F,
    substitutions: Vec<Substitution>, upper_rows: Vec<Option<usize>>
}
fn standard(model: &Model, bounds: &Bounds) -> (Standard, tableau::Tableau) {
    let mut columns = Vec::new();
    let mut substitutions = Vec::new();
    let mut costs = Vec::new();
    for j in 0..model.names.len() {
        let (lower, upper) = bounds[j];
        let mut parts = Vec::new();
        let (kind, offset) = if let Some(lower) = lower {
            parts.push((columns.len(), F::integer(1)));
            columns.push(model.names[j].clone()); costs.push(model.c[j]); ("shift", lower)
        } else if let Some(upper) = upper {
            parts.push((columns.len(), F::integer(-1)));
            columns.push(format!("{}'", model.names[j])); costs.push(-model.c[j]); ("reflect", upper)
        } else {
            parts.push((columns.len(), F::integer(1)));
            columns.push(format!("{}+", model.names[j])); costs.push(model.c[j]);
            parts.push((columns.len(), F::integer(-1)));
            columns.push(format!("{}-", model.names[j])); costs.push(-model.c[j]); ("split", F::zero())
        };
        substitutions.push(Substitution { kind, offset, columns: parts });
    }
    let variable_columns = columns.len();
    let mut rows = model.row_names.clone();
    let mut comparisons = model.comparisons.clone();
    let mut coefficients = Vec::new();
    let mut beta = Vec::new();
    for i in 0..model.a.len() {
        let mut row = vec![F::zero(); variable_columns];
        let mut rhs = model.rhs[i];
        for j in 0..model.names.len() {
            rhs = rhs - model.a[i][j] * substitutions[j].offset;
            for &(k, direction) in &substitutions[j].columns { row[k] = direction * model.a[i][j]; }
        }
        coefficients.push(row); beta.push(rhs);
    }
    let mut upper_rows = vec![None; model.names.len()];
    for j in 0..model.names.len() {
        if substitutions[j].kind == "shift" {
            if let Some(upper) = bounds[j].1 {
                upper_rows[j] = Some(rows.len()); rows.push(format!("{}.ub", model.names[j])); comparisons.push("<=".into());
                let mut row = vec![F::zero(); variable_columns]; row[substitutions[j].columns[0].0] = F::integer(1);
                coefficients.push(row); beta.push(upper - substitutions[j].offset);
            }
        }
    }
    let mut signs = vec![F::integer(1); rows.len()];
    for i in 0..rows.len() {
        if beta[i] < F::zero() {
            signs[i] = F::integer(-1); beta[i] = -beta[i];
            for value in &mut coefficients[i] { *value = -*value; }
            comparisons[i] = match comparisons[i].as_str() { "<=" => ">=", ">=" => "<=", _ => "=" }.into();
        }
    }
    let mut initial = vec![usize::MAX; rows.len()];
    let mut slacks = vec![None; rows.len()];
    for i in 0..rows.len() {
        if comparisons[i] != "=" {
            let k = columns.len(); columns.push(format!("s:{}", rows[i])); costs.push(F::zero());
            for row in &mut coefficients { row.push(F::zero()); }
            coefficients[i][k] = if comparisons[i] == "<=" { F::integer(1) } else { F::integer(-1) };
            slacks[i] = Some(k);
            if comparisons[i] == "<=" { initial[i] = k; }
        }
    }
    let mut artificial = BTreeSet::new();
    for i in 0..rows.len() {
        if comparisons[i] != "<=" {
            let k = columns.len(); columns.push(format!("a:{}", rows[i])); costs.push(F::zero());
            for row in &mut coefficients { row.push(F::zero()); }
            coefficients[i][k] = F::integer(1); initial[i] = k; artificial.insert(k);
        }
    }
    let sign = F::integer(if model.maximize { -1 } else { 1 });
    let constant = (0..model.names.len()).fold(F::zero(), |sum, j| sum + model.c[j] * substitutions[j].offset);
    let phase1 = (0..columns.len()).map(|k| F::integer(if artificial.contains(&k) { 1 } else { 0 })).collect();
    let phase2 = costs.iter().map(|&value| sign * value).collect();
    let tableau = tableau::Tableau { t: coefficients, beta, basis: initial.clone() };
    (Standard { columns, rows, signs, initial, slacks, artificial, phase1, phase2, constant, sign, substitutions, upper_rows }, tableau)
}
#[derive(Clone)]
pub struct LpResult {
    standard: Standard, tableau: tableau::Tableau, pub status: &'static str, pub value: F, pub solution: Vec<F>,
    pub phase1: usize, pub phase2: usize, pub drives: usize, infeasibility: F, multipliers: Vec<F>, ray: Vec<F>, rate: F
}
impl LpResult { pub fn pivots(&self) -> usize { self.phase1 + self.phase2 + self.drives } }
fn recover(standard: &Standard, columns: &[F], offset: bool) -> Vec<F> {
    standard.substitutions.iter().map(|value| value.columns.iter().fold(if offset { value.offset } else { F::zero() }, |sum, &(k, direction)| sum + direction * columns[k])).collect()
}
pub fn solve_lp(model: &Model, bounds: &Bounds, node: usize, level: usize, log: &mut Vec<String>) -> LpResult {
    let (s, mut t) = standard(model, bounds);
    log.push(format!("SOLVE node {} rows {} columns {} artificials {}", node, s.rows.len(), s.columns.len(), s.artificial.len()));
    if level >= 1 {
        for (j, value) in s.substitutions.iter().enumerate() {
            let mut line = format!("MAP {} {}", model.names[j], value.kind);
            if value.kind != "split" {
                line.push_str(&format!(" {}", value.offset));
                if value.kind == "shift" { if let Some(upper) = bounds[j].1 { line.push_str(&format!(" upper {}", upper)); } }
            }
            log.push(line);
        }
        for (i, &sign) in s.signs.iter().enumerate() { if sign < F::zero() { log.push(format!("FLIP {}", s.rows[i])); } }
    }
    let (mut phase1, mut phase2, mut drives, mut redundant) = (0, 0, 0, 0);
    let (mut status, mut infeasibility, mut unbounded) = ("OPTIMAL", F::zero(), None);
    if !s.artificial.is_empty() {
        if level >= 1 { log.push("PHASE 1".into()); }
        if level >= 2 { log.extend(t.display("phase 1 start", &s.columns, &s.rows, &s.phase1, F::zero(), F::integer(1))); }
        let candidates: Vec<_> = (0..s.columns.len()).collect();
        phase1 = simplex::phase(&mut t, &s.phase1, &candidates, &s.columns, &s.rows, F::zero(), F::integer(1), level, log).0;
        infeasibility = t.value(&s.phase1);
        if level >= 1 { log.push(format!("PHASE 1 END objective {} iterations {}", infeasibility, phase1)); }
        if infeasibility > F::zero() {
            status = "INFEASIBLE";
            if level >= 2 { log.extend(t.display("final", &s.columns, &s.rows, &s.phase1, F::zero(), F::integer(1))); }
        } else {
            for i in 0..s.rows.len() {
                if !s.artificial.contains(&t.basis[i]) { continue; }
                let enter = (0..s.columns.len()).find(|k| !s.artificial.contains(k) && t.t[i][*k] != F::zero());
                if let Some(k) = enter {
                    if level >= 1 { log.push(format!("DRIVE row {} enter {} leave {}", s.rows[i], s.columns[k], s.columns[t.basis[i]])); }
                    t.pivot(i, k); drives += 1;
                } else {
                    redundant += 1;
                    if level >= 1 { log.push(format!("REDUNDANT row {}", s.rows[i])); }
                }
            }
        }
    }
    if status != "INFEASIBLE" {
        if level >= 1 { log.push("PHASE 2".into()); }
        if level >= 2 { log.extend(t.display("phase 2 start", &s.columns, &s.rows, &s.phase2, s.constant, s.sign)); }
        let candidates: Vec<_> = (0..s.columns.len()).filter(|k| !s.artificial.contains(k)).collect();
        let (count, column) = simplex::phase(&mut t, &s.phase2, &candidates, &s.columns, &s.rows, s.constant, s.sign, level, log);
        phase2 = count; unbounded = column;
        if let Some(k) = column {
            status = "UNBOUNDED";
            if level >= 1 { log.push(format!("UNBOUNDED enter {}", s.columns[k])); }
        }
        if level >= 1 { log.push(format!("PHASE 2 END objective {} iterations {}", s.constant + s.sign * t.value(&s.phase2), phase2)); }
        if level >= 2 { log.extend(t.display("final", &s.columns, &s.rows, &s.phase2, s.constant, s.sign)); }
    }
    let value = s.constant + s.sign * t.value(&s.phase2);
    let mut column_values = vec![F::zero(); s.columns.len()];
    for i in 0..s.rows.len() { column_values[t.basis[i]] = t.beta[i]; }
    let solution = recover(&s, &column_values, true);
    let multipliers = if status == "INFEASIBLE" {
        let reduced = t.reduced(&s.phase1);
        s.initial.iter().enumerate().map(|(i, &k)| s.signs[i] * (s.phase1[k] - reduced[k])).collect()
    } else { Vec::new() };
    let mut ray = Vec::new();
    let mut rate = F::zero();
    if let Some(q) = unbounded {
        let mut direction = vec![F::zero(); s.columns.len()]; direction[q] = F::integer(1);
        for i in 0..s.rows.len() { direction[t.basis[i]] = -t.t[i][q]; }
        ray = recover(&s, &direction, false);
        rate = model.c.iter().zip(&ray).fold(F::zero(), |sum, (&c, &d)| sum + c * d);
    }
    log.push(format!("RESULT {} objective {} phase1 {} phase2 {} drives {} redundant {}", status, if status == "OPTIMAL" { value.to_string() } else { "-".into() }, phase1, phase2, drives, redundant));
    LpResult { standard: s, tableau: t, status, value, solution, phase1, phase2, drives, infeasibility, multipliers, ray, rate }
}

fn interval(value: F, lower: Option<F>, upper: Option<F>) -> (String, String) {
    (lower.map_or_else(|| "-inf".into(), |v| (value + v).to_string()), upper.map_or_else(|| "inf".into(), |v| (value + v).to_string()))
}
fn sensitivity(model: &Model, result: &LpResult) -> Vec<String> {
    let s = &result.standard;
    let t = &result.tableau;
    let reduced_columns = t.reduced(&s.phase2);
    let basic: BTreeSet<_> = t.basis.iter().copied().collect();
    let nonbasic: Vec<_> = (0..s.columns.len()).filter(|k| !basic.contains(k) && !s.artificial.contains(k)).collect();
    let prices: Vec<_> = (0..model.a.len()).map(|i| -s.sign * s.signs[i] * reduced_columns[s.initial[i]]).collect();
    let reduced: Vec<_> = (0..model.names.len()).map(|j| model.c[j] - (0..model.a.len()).fold(F::zero(), |sum, i| sum + prices[i] * model.a[i][j])).collect();
    let objective = (0..model.a.len()).fold(F::zero(), |sum, i| sum + prices[i] * model.rhs[i]) + (0..model.names.len()).fold(F::zero(), |sum, j| sum + reduced[j] * result.solution[j]);
    let mut lines = vec![
        format!("MODEL {} {} objective {}", model.name, if model.integer.iter().any(|&v| v) { "relaxation" } else { "lp" }, result.value),
        format!("BASIS {}", t.basis.iter().map(|&k| s.columns[k].clone()).collect::<Vec<_>>().join(" ")),
        format!("DEGENERACY primal {} dual {}", (0..s.rows.len()).filter(|&i| !s.artificial.contains(&t.basis[i]) && t.beta[i] == F::zero()).count(), nonbasic.iter().filter(|&&k| reduced_columns[k] == F::zero()).count()),
        format!("DUAL objective {}", objective)
    ];
    for i in 0..model.a.len() {
        let column = s.initial[i];
        let rho: Vec<_> = (0..s.rows.len()).map(|j| s.signs[i] * t.t[j][column]).collect();
        let (mut lower, mut upper) = (None, None);
        let fixed = (0..s.rows.len()).any(|j| rho[j] != F::zero() && s.artificial.contains(&t.basis[j]));
        let ends = if fixed { (model.rhs[i].to_string(), model.rhs[i].to_string()) } else {
            for j in 0..s.rows.len() {
                if rho[j] > F::zero() { let value = -t.beta[j] / rho[j]; lower = Some(lower.map_or(value, |old: F| old.max(value))); }
                else if rho[j] < F::zero() { let value = -t.beta[j] / rho[j]; upper = Some(upper.map_or(value, |old: F| old.min(value))); }
            }
            interval(model.rhs[i], lower, upper)
        };
        lines.push(format!("CONSTRAINT {} price {} rhs {} range {} {}", model.row_names[i], prices[i], model.rhs[i], ends.0, ends.1));
    }
    for j in 0..model.names.len() {
        let variable = &s.substitutions[j];
        let status = if variable.kind == "split" {
            if variable.columns.iter().all(|(k, _)| !basic.contains(k)) { "zero" } else { "basic" }
        } else if !basic.contains(&variable.columns[0].0) {
            if variable.kind == "shift" { "lower" } else { "upper" }
        } else if variable.kind == "shift" && s.upper_rows[j].map_or(false, |i| !basic.contains(&s.slacks[i].unwrap())) { "upper" } else { "basic" };
        let mut h = vec![F::zero(); s.columns.len()];
        for &(k, direction) in &variable.columns { h[k] = s.sign * direction; }
        let eta = t.reduced(&h);
        let (mut lower, mut upper) = (None, None);
        for &k in &nonbasic {
            if eta[k] > F::zero() { let value = -reduced_columns[k] / eta[k]; lower = Some(lower.map_or(value, |old: F| old.max(value))); }
            else if eta[k] < F::zero() { let value = -reduced_columns[k] / eta[k]; upper = Some(upper.map_or(value, |old: F| old.min(value))); }
        }
        let (lower, upper) = interval(model.c[j], lower, upper);
        lines.push(format!("VARIABLE {} {} value {} reduced {} cost {} range {} {}", model.names[j], status, result.solution[j], reduced[j], model.c[j], lower, upper));
    }
    lines
}
fn statistics(model: &Model) -> String {
    let matrix: Vec<_> = model.a.iter().flat_map(|r| r.iter().copied()).filter(|v| *v != F::zero()).map(F::abs).collect();
    let objective: Vec<_> = model.c.iter().copied().filter(|v| *v != F::zero()).map(F::abs).collect();
    let rhs: Vec<_> = model.rhs.iter().copied().filter(|v| *v != F::zero()).map(F::abs).collect();
    let bounds: Vec<_> = model.bounds.iter().flat_map(|&(a, b)| [a, b].iter().copied().flatten().collect::<Vec<_>>()).filter(|v| *v != F::zero()).map(F::abs).collect();
    let range = |values: &[F]| if values.is_empty() { "- -".into() } else { format!("{} {}", values.iter().min().unwrap(), values.iter().max().unwrap()) };
    format!("STATS nonzeros {} matrix {} objective {} rhs {} bounds {}", matrix.len(), range(&matrix), range(&objective), range(&rhs), range(&bounds))
}
fn write(name: &str, lines: &[String]) {
    fs::create_dir_all("output").unwrap();
    fs::write(format!("output/{}", name), if lines.is_empty() { String::new() } else { lines.join("\n") + "\n" }).unwrap();
}
fn main() {
    let blocks = lp_parser::read();
    let params = lp_parser::params();
    let (mut iterations, mut solutions, mut sensitivity_lines, mut tree) = (Vec::new(), Vec::new(), Vec::new(), Vec::new());
    let mut csv = vec!["model,status,objective,approx,relaxation,nodes,pivots".into()];
    let mut statuses = [0usize; 5];
    let mut totals = [0usize; 4];
    let (mut analyzed, mut integer_models, mut integer_nodes, mut limits) = (0, 0, 0, 0);
    for block in &blocks {
        let model = if let Some(error) = &block.error { Err(error.clone()) } else { content(&block.name, block.parsed.as_ref().unwrap()) };
        let model = match model {
            Ok(model) => model,
            Err((line, message)) => {
                statuses[4] += 1; iterations.push(format!("MODEL {} error", block.name));
                solutions.push(format!("MODEL {}", block.name)); solutions.push(format!("STATUS ERROR line {} {}", line, message));
                sensitivity_lines.push(format!("MODEL {} skipped ERROR", block.name)); csv.push(format!("{},ERROR,-,-,-,0,0", block.name)); continue;
            }
        };
        let integer = model.integer.iter().any(|&value| value);
        let level = params.levels.get(&model.name).copied().unwrap_or(params.level);
        let limit = params.limits.get(&model.name).copied().unwrap_or(params.limit);
        iterations.push(format!("MODEL {} level {}", model.name, level));
        let outcome = if integer { branch_bound::solve(&model, limit, level, &mut iterations) } else {
            let root = solve_lp(&model, &model.bounds, 1, level, &mut iterations);
            branch_bound::Outcome { status: root.status, solution: if root.status == "OPTIMAL" { Some(root.solution.clone()) } else { None }, objective: if root.status == "OPTIMAL" { Some(root.value) } else { None }, nodes: 1, phase1: root.phase1, phase2: root.phase2, drives: root.drives, root, lines: Vec::new() }
        };
        let root = &outcome.root;
        let status = outcome.status;
        statuses[match status { "OPTIMAL" => 0, "INFEASIBLE" => 1, "UNBOUNDED" => 2, _ => 3 }] += 1;
        totals[0] += outcome.nodes; totals[1] += outcome.phase1; totals[2] += outcome.phase2; totals[3] += outcome.drives;
        if integer { integer_models += 1; integer_nodes += outcome.nodes; limits += if status == "NODE_LIMIT" { 1 } else { 0 }; tree.extend(outcome.lines.clone()); }
        solutions.push(format!("MODEL {} {} variables {} constraints {} integers {}", model.name, if model.maximize { "maximize" } else { "minimize" }, model.names.len(), model.a.len(), model.integer.iter().filter(|&&v| v).count()));
        solutions.push(statistics(&model)); solutions.push(format!("STATUS {}", status));
        if let Some(value) = outcome.objective { solutions.push(format!("OBJECTIVE {} approx {}", value, value.approximate())); }
        if integer && root.status == "OPTIMAL" { solutions.push(format!("RELAXATION {} approx {}", root.value, root.value.approximate())); }
        if root.status == "INFEASIBLE" {
            solutions.push(format!("INFEASIBILITY {}", root.infeasibility));
            for (i, multiplier) in root.multipliers.iter().enumerate() { solutions.push(format!("FARKAS {} {}", root.standard.rows[i], multiplier)); }
        }
        if outcome.solution.is_some() || status == "UNBOUNDED" {
            for (j, value) in outcome.solution.as_ref().unwrap_or(&root.solution).iter().enumerate() { solutions.push(format!("VALUE {} {}", model.names[j], value)); }
        }
        if status == "UNBOUNDED" {
            for (j, value) in root.ray.iter().enumerate() { solutions.push(format!("RAY {} {}", model.names[j], value)); }
            solutions.push(format!("RATE {}", root.rate));
        }
        if let Some(values) = &outcome.solution {
            for i in 0..model.a.len() {
                let value = model.a[i].iter().zip(values).fold(F::zero(), |sum, (&a, &x)| sum + a * x);
                let margin = if model.comparisons[i] == "<=" { model.rhs[i] - value } else { value - model.rhs[i] };
                solutions.push(format!("ROW {} {} {}", model.row_names[i], value, margin));
            }
        }
        if integer { solutions.push(format!("NODES {}", outcome.nodes)); }
        solutions.push(format!("PIVOTS {}", outcome.pivots()));
        if root.status == "OPTIMAL" { analyzed += 1; sensitivity_lines.extend(sensitivity(&model, root)); }
        else { sensitivity_lines.push(format!("MODEL {} skipped {}", model.name, root.status)); }
        csv.push(format!("{},{},{},{},{},{},{}", model.name, status, outcome.objective.map_or_else(|| "-".into(), |v| v.to_string()), outcome.objective.map_or_else(|| "-".into(), F::approximate), if root.status == "OPTIMAL" { root.value.to_string() } else { "-".into() }, outcome.nodes, outcome.pivots()));
    }
    iterations.push(format!("TOTAL solves {} phase1 {} phase2 {} drives {} pivots {}", totals[0], totals[1], totals[2], totals[3], totals[1] + totals[2] + totals[3]));
    solutions.push(format!("SUMMARY models {} optimal {} infeasible {} unbounded {} node_limit {} error {}", blocks.len(), statuses[0], statuses[1], statuses[2], statuses[3], statuses[4]));
    sensitivity_lines.push(format!("SUMMARY analyzed {} skipped {}", analyzed, blocks.len() - analyzed));
    tree.push(format!("SUMMARY models {} nodes {} node_limit {}", integer_models, integer_nodes, limits));
    write("iterations.txt", &iterations); write("solutions.txt", &solutions); write("sensitivity.txt", &sensitivity_lines); write("bnb_tree.txt", &tree); write("summary.csv", &csv);
}
