mod cnf_io;
mod dpll;
mod encoders;
mod preprocess;
mod report;

use dpll::{Round, Statistics};
use preprocess::Simplified;
use report::{frequencies, items, numbers};
use std::collections::{BTreeMap, BTreeSet};
use std::fs;

pub struct Formula {
    variables: usize,
    clauses: Vec<Vec<i64>>,
}

struct Graph {
    vertices: usize,
    edges: Vec<(usize, usize)>,
    error: Option<String>,
}

fn read_graphs() -> BTreeMap<String, Graph> {
    let text = fs::read_to_string("input/graphs.txt").unwrap();
    let lines: Vec<_> = text.lines().collect();
    let mut graphs = BTreeMap::new();
    let mut i = 0;
    while i < lines.len() {
        if lines[i].is_empty() || lines[i].starts_with('#') { i += 1; continue; }
        let header: Vec<_> = lines[i].split(' ').collect();
        let name = header[1].to_string();
        let vertices = header[2].parse().unwrap();
        let mut graph = Graph { vertices, edges: Vec::new(), error: None };
        let mut edges = BTreeSet::new();
        i += 1;
        while lines[i] != "END" {
            if graph.error.is_none() {
                let tokens: Vec<_> = lines[i].split(' ').collect();
                let error = if tokens.len() != 2 || tokens.iter().any(|token| cnf_io::number(token).is_none()) { Some("bad edge line") }
                else {
                    let a = cnf_io::number(tokens[0]).unwrap();
                    let b = cnf_io::number(tokens[1]).unwrap();
                    if a < 1 || a > vertices || b < 1 || b > vertices { Some("vertex out of range") }
                    else if a == b { Some("self loop") }
                    else if !edges.insert((a.min(b), a.max(b))) { Some("duplicate edge") }
                    else { None }
                };
                if let Some(error) = error { graph.error = Some(format!("{error} at line {}", i + 1)); }
            }
            i += 1;
        }
        graph.edges = edges.into_iter().collect();
        graphs.insert(name, graph);
        i += 1;
    }
    graphs
}

struct Job {
    command: String,
    arguments: Vec<String>,
    limit: usize,
}

fn validate(line: &str, graphs: &BTreeMap<String, Graph>) -> Result<Job, String> {
    let tokens: Vec<_> = line.split(' ').collect();
    let command = tokens[0];
    let kinds: &[&str] = match command {
        "SOLVE" | "CORE" => &["file"], "ENUM" => &["file", "limit"], "QUEENS" => &["small", "limit"],
        "PIGEON" => &["small", "small", "limit"], "COLOR" => &["graph", "colors", "limit"], "CHROMATIC" => &["graph", "colors"],
        _ => return Err(format!("unknown command {command}")),
    };
    if tokens.len() != kinds.len() + 1 { return Err("wrong argument count".into()); }
    for (&kind, &token) in kinds.iter().zip(&tokens[1..]) {
        match kind {
            "file" => {
                let valid = token.strip_suffix(".cnf").is_some_and(|name| (1..=20).contains(&name.len()) && name.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'_'));
                if !valid { return Err(format!("bad file name {token}")); }
            }
            "graph" => {
                let graph = graphs.get(token).ok_or_else(|| format!("unknown graph {token}"))?;
                if let Some(reason) = &graph.error { return Err(format!("invalid graph {token}: {reason}")); }
            }
            _ => {
                let value = cnf_io::number(token).ok_or_else(|| format!("bad number {token}"))?;
                let maximum = match kind { "small" => 8, "colors" => 6, _ => 200 };
                if !(1..=maximum).contains(&value) { return Err(format!("out of range {token}")); }
            }
        }
    }
    let limit = if ["SOLVE", "CORE", "CHROMATIC"].contains(&command) { 1 } else { tokens.last().unwrap().parse().unwrap() };
    Ok(Job { command: command.into(), arguments: tokens[1..].iter().map(|s| s.to_string()).collect(), limit })
}

struct Solution {
    simplified: Simplified,
    models: Vec<Vec<bool>>,
    rounds: usize,
    stop: &'static str,
    statistics: Statistics,
    trace: Vec<String>,
}

impl Solution {
    fn status(&self) -> &'static str { if self.models.is_empty() { "UNSAT" } else { "SAT" } }
}

fn solve(formula: &Formula, limit: usize) -> Solution {
    let simplified = preprocess::simplify(formula, limit == 1);
    let mut result = Solution { simplified, models: Vec::new(), rounds: 0, stop: "preprocess", statistics: Statistics::default(), trace: Vec::new() };
    if result.simplified.conflict.is_some() { return result; }
    let active = result.simplified.active();
    let mut blocking = Vec::new();
    while result.models.len() < limit {
        let mut clauses = result.simplified.clauses.clone();
        clauses.extend(blocking.clone());
        let mut round = Round::new(formula.variables, &clauses);
        let model = round.search();
        result.rounds += 1;
        result.statistics.add(&round.statistics);
        if result.rounds == 1 { result.trace = round.events; }
        let Some(mut model) = model else { result.stop = "all"; return result; };
        for (variable, &value) in result.simplified.fixed.iter().enumerate().skip(1) {
            if value != 0 { model[variable] = value == 1; }
        }
        blocking.push(active.iter().map(|&x| if model[x] { -(x as i64) } else { x as i64 }).collect::<Vec<_>>());
        result.models.push(model);
    }
    result.stop = "limit";
    result
}

fn satisfied(clause: &[i64], model: &[bool]) -> bool {
    clause.iter().any(|&literal| model[literal.unsigned_abs() as usize] == (literal > 0))
}

fn analysis(formula: &Formula, solution: &Solution, all: bool) -> Vec<String> {
    if solution.models.is_empty() { return Vec::new(); }
    let mut verification = None;
    for (i, model) in solution.models.iter().enumerate() {
        if let Some(j) = formula.clauses.iter().position(|clause| !satisfied(clause, model)) { verification = Some((i + 1, j + 1)); break; }
    }
    let first = &solution.models[0];
    let true_literals = frequencies(formula.clauses.iter().map(|clause| clause.iter().filter(|&&literal| first[literal.unsigned_abs() as usize] == (literal > 0)).count()));
    let verify = match verification {
        Some((model, clause)) => format!("verify failed model={model} clause={clause}"),
        None => format!("verify ok models={} clauses={} true_literals={}", solution.models.len(), formula.clauses.len(), true_literals),
    };
    let flips: Vec<_> = (1..=formula.variables).filter(|&x| {
        let mut flipped = first.clone();
        flipped[x] = !flipped[x];
        formula.clauses.iter().all(|clause| satisfied(clause, &flipped))
    }).collect();
    let mut lines = vec![verify, format!("flips safe={} variables={}", flips.len(), numbers(flips.iter().map(|&x| x as i64)))];
    if all && solution.models.len() >= 2 {
        let mut distances = Vec::new();
        for i in 0..solution.models.len() {
            for j in i + 1..solution.models.len() { distances.push((1..=formula.variables).filter(|&x| solution.models[i][x] != solution.models[j][x]).count()); }
        }
        lines.push(format!("diversity pairs={} min_distance={} max_distance={}", distances.len(), distances.iter().min().unwrap(), distances.iter().max().unwrap()));
    }
    if all && solution.stop == "all" {
        let backbone: Vec<_> = (1..=formula.variables).filter(|&x| solution.models.iter().all(|model| model[x] == first[x])).map(|x| if first[x] { x as i64 } else { -(x as i64) }).collect();
        lines.push(format!("backbone size={} literals={}", backbone.len(), numbers(backbone)));
    }
    lines
}

fn formula_line(formula: &Formula) -> String {
    format!("formula variables={} clauses={} literals={} lengths={}", formula.variables, formula.clauses.len(), formula.clauses.iter().map(Vec::len).sum::<usize>(), frequencies(formula.clauses.iter().map(Vec::len)))
}

fn preprocess_lines(simplified: &Simplified) -> Vec<String> {
    let c = simplified.counts;
    let mut lines = vec![format!("preprocess pure={} tautologies={} duplicate_literals={} unit_fixed={} unit_removed={} subsumed={} pure_fixed={} pure_removed={} removed={}", if simplified.pure { "on" } else { "off" }, c[0], c[1], c[2], c[3], c[4], c[5], c[6], simplified.removed_count()),
        format!("removed_clauses tautology={} unit={} subsumed={} pure={}", numbers(simplified.removed[0].iter().map(|&n| n as i64)), numbers(simplified.removed[1].iter().map(|&n| n as i64)), numbers(simplified.removed[2].iter().map(|&n| n as i64)), numbers(simplified.removed[3].iter().map(|&n| n as i64)))];
    if let Some(clause) = simplified.conflict { lines.push(format!("simplified empty_clause={clause}")); }
    else {
        let fixed: Vec<_> = (1..simplified.fixed.len()).filter(|&x| simplified.fixed[x] != 0).map(|x| x as i64 * i64::from(simplified.fixed[x])).collect();
        lines.push(format!("simplified clauses={} literals={} lengths={} fixed={} active={}", simplified.clauses.len(), simplified.clauses.iter().map(Vec::len).sum::<usize>(), frequencies(simplified.clauses.iter().map(Vec::len)), fixed.len(), simplified.active().len()));
        lines.push(format!("fixed literals={}", numbers(fixed)));
    }
    lines
}

fn search_line(statistics: &Statistics) -> String {
    format!("search {}", items(&[("decisions", statistics.decisions.to_string()), ("propagations", statistics.propagations.to_string()), ("conflicts", statistics.conflicts.to_string()), ("max_depth", statistics.max_depth.to_string())]))
}

fn core_line(formula: &Formula) -> String {
    let mut included = vec![true; formula.clauses.len()];
    let (mut decisions, mut conflicts) = (0, 0);
    for i in 0..formula.clauses.len() {
        let reduced = Formula { variables: formula.variables, clauses: formula.clauses.iter().enumerate().filter(|(j, _)| *j != i && included[*j]).map(|(_, clause)| clause.clone()).collect() };
        let result = solve(&reduced, 1);
        decisions += result.statistics.decisions;
        conflicts += result.statistics.conflicts;
        if result.models.is_empty() { included[i] = false; }
    }
    let clauses: Vec<_> = included.iter().enumerate().filter(|(_, include)| **include).map(|(i, _)| i as i64 + 1).collect();
    format!("core size={} decisions={} conflicts={} clauses={}", clauses.len(), decisions, conflicts, numbers(clauses))
}

fn greedy_coloring(graph: &Graph) -> (Vec<usize>, usize) {
    let mut degrees = vec![0; graph.vertices + 1];
    for &(a, b) in &graph.edges { degrees[a] += 1; degrees[b] += 1; }
    let mut vertices: Vec<_> = (1..=graph.vertices).collect();
    vertices.sort_by_key(|&x| (-(degrees[x] as i64), x));
    let mut colors = vec![0; graph.vertices + 1];
    for vertex in vertices {
        let neighboring: BTreeSet<_> = graph.edges.iter().filter_map(|&(a, b)| {
            if a == vertex { Some(colors[b]) } else if b == vertex { Some(colors[a]) } else { None }
        }).collect();
        colors[vertex] = (1..).find(|color| !neighboring.contains(color)).unwrap();
    }
    (colors[1..].to_vec(), *degrees.iter().max().unwrap())
}

fn graph_line(graph: &Graph) -> String {
    let (colors, maximum_degree) = greedy_coloring(graph);
    format!("graph vertices={} edges={} max_degree={} greedy={}", graph.vertices, graph.edges.len(), maximum_degree, colors.iter().max().unwrap())
}

fn queen_canonical(columns: &[usize]) -> (Vec<usize>, usize) {
    let n = columns.len();
    let mut boards = vec![vec![0; n]; 8];
    for (row, &column) in columns.iter().enumerate() {
        let r = row + 1;
        let c = column;
        let transforms = [(r, c), (c, n + 1 - r), (n + 1 - r, n + 1 - c), (n + 1 - c, r), (r, n + 1 - c), (n + 1 - r, c), (c, r), (n + 1 - c, n + 1 - r)];
        for (board, &(r, c)) in boards.iter_mut().zip(&transforms) { board[r - 1] = c; }
    }
    let distinct: BTreeSet<_> = boards.into_iter().collect();
    (distinct.first().unwrap().clone(), distinct.len())
}

fn color_canonical(colors: &[usize]) -> Vec<usize> {
    let mut mapping = BTreeMap::new();
    colors.iter().map(|color| {
        let next = mapping.len() + 1;
        *mapping.entry(*color).or_insert(next)
    }).collect()
}

struct Class {
    canonical: Vec<usize>,
    orbit: usize,
    found: usize,
    first: usize,
}

fn board_lines(number: usize, job: &Job, graphs: &BTreeMap<String, Graph>, solution: &Solution, colors: usize) -> Vec<String> {
    let command = job.command.as_str();
    let mut classes: Vec<Class> = Vec::new();
    let mut lines = Vec::new();
    let (rows, width) = if command == "QUEENS" {
        let n = job.arguments[0].parse().unwrap();
        lines.push(format!("QUEENS job={number} n={n}"));
        (n, n)
    } else if command == "PIGEON" {
        let pigeons = job.arguments[0].parse().unwrap();
        let holes = job.arguments[1].parse().unwrap();
        lines.push(format!("PIGEON job={number} pigeons={pigeons} holes={holes}"));
        (pigeons, holes)
    } else {
        let graph = &graphs[&job.arguments[0]];
        let (greedy, _) = greedy_coloring(graph);
        lines.push(format!("{} job={} graph={} vertices={} edges={} colors={}", command, number, job.arguments[0], graph.vertices, graph.edges.len(), colors));
        lines.push(format!("greedy used={} colors={}", greedy.iter().max().unwrap(), numbers(greedy.iter().map(|&c| c as i64))));
        (graph.vertices, colors)
    };
    for (i, model) in solution.models.iter().enumerate() {
        let positions = encoders::positions(model, rows, width);
        let list = numbers(positions.iter().map(|&position| position as i64));
        if command == "PIGEON" {
            let empty = numbers((1..=width).filter(|hole| !positions.contains(hole)).map(|hole| hole as i64));
            lines.push(format!("assignment {} holes={} empty={}", i + 1, list, empty));
            continue;
        }
        let (canonical, orbit) = if command == "QUEENS" { queen_canonical(&positions) } else { (color_canonical(&positions), 0) };
        let existing = classes.iter().position(|class| class.canonical == canonical);
        let index = existing.unwrap_or_else(|| {
            classes.push(Class { canonical, orbit, found: 0, first: i + 1 });
            classes.len() - 1
        });
        classes[index].found += 1;
        if command == "QUEENS" {
            lines.push(format!("solution {} columns={} class={}", i + 1, list, index + 1));
            if existing.is_none() { lines.extend(report::board(&positions)); }
        } else {
            let used = positions.iter().copied().collect::<BTreeSet<_>>().len();
            let sizes = numbers((1..=width).map(|color| positions.iter().filter(|&&c| c == color).count() as i64));
            lines.push(format!("coloring {} colors={} used={} sizes={} class={}", i + 1, list, used, sizes, index + 1));
        }
    }
    if command == "PIGEON" {
        let expected = if rows > width { 0 } else { (0..rows).fold(1, |product, i| product * (width - i)) };
        lines.push(format!("summary assignments={} stop={} expected={}", solution.models.len(), solution.stop, expected));
    } else {
        for (i, class) in classes.iter().enumerate() {
            let orbit = if command == "QUEENS" { format!(" orbit={}", class.orbit) } else { String::new() };
            lines.push(format!("class {}{} found={} first={} canonical={}", i + 1, orbit, class.found, class.first, numbers(class.canonical.iter().map(|&v| v as i64))));
        }
        lines.push(format!("summary {}={} stop={} classes={}", if command == "QUEENS" { "solutions" } else { "colorings" }, solution.models.len(), solution.stop, classes.len()));
    }
    lines
}

struct JobStatistics {
    number: usize,
    command: String,
    status: &'static str,
    variables: usize,
    clauses: usize,
    removed: usize,
    search: Statistics,
    models: usize,
    rounds: usize,
}

fn summary(jobs: usize, statistics: &[JobStatistics]) -> Vec<String> {
    let sat = statistics.iter().filter(|s| s.status == "SAT").count();
    let mut lines = vec![format!("SUMMARY jobs={} sat={} unsat={} error={}", jobs, sat, statistics.len() - sat, jobs - statistics.len()),
        format!("totals models={} rounds={} decisions={} propagations={} conflicts={} removed_clauses={}", statistics.iter().map(|s| s.models).sum::<usize>(), statistics.iter().map(|s| s.rounds).sum::<usize>(), statistics.iter().map(|s| s.search.decisions).sum::<usize>(), statistics.iter().map(|s| s.search.propagations).sum::<usize>(), statistics.iter().map(|s| s.search.conflicts).sum::<usize>(), statistics.iter().map(|s| s.removed).sum::<usize>())];
    for command in ["SOLVE", "ENUM", "CORE", "QUEENS", "PIGEON", "COLOR", "CHROMATIC"] {
        let included: Vec<_> = statistics.iter().filter(|s| s.command == command).collect();
        if included.is_empty() { continue; }
        let sat = included.iter().filter(|s| s.status == "SAT").count();
        lines.push(format!("command {} jobs={} sat={} unsat={} decisions={} propagations={} conflicts={}", command, included.len(), sat, included.len() - sat, included.iter().map(|s| s.search.decisions).sum::<usize>(), included.iter().map(|s| s.search.propagations).sum::<usize>(), included.iter().map(|s| s.search.conflicts).sum::<usize>()));
    }
    if !statistics.is_empty() {
        for (name, metric) in [("hardest", "conflicts"), ("deepest", "max_depth"), ("busiest", "propagations")] {
            let value = |s: &JobStatistics| match metric { "conflicts" => s.search.conflicts, "max_depth" => s.search.max_depth, _ => s.search.propagations };
            let mut selected = &statistics[0];
            for candidate in statistics { if value(candidate) > value(selected) { selected = candidate; } }
            lines.push(format!("{name} job={} {metric}={}", selected.number, value(selected)));
        }
    }
    lines
}

fn main() {
    let graphs = read_graphs();
    let text = fs::read_to_string("input/jobs.txt").unwrap();
    let jobs: Vec<_> = text.lines().filter(|line| !line.is_empty() && !line.starts_with('#')).collect();
    let mut result_paragraphs = Vec::new();
    let mut model_paragraphs = Vec::new();
    let mut board_paragraphs = Vec::new();
    let mut statistics = Vec::new();
    for (index, &line) in jobs.iter().enumerate() {
        let number = index + 1;
        let heading = format!("JOB {number} {line}");
        let mut lines = vec![heading.clone()];
        let job = match validate(line, &graphs) {
            Ok(job) => job,
            Err(error) => { lines.push(format!("error {error}")); result_paragraphs.push(lines); continue; }
        };
        let command = job.command.as_str();
        let (formula, solution, colors, removed, rounds, search) = if command == "CHROMATIC" {
            let graph = &graphs[&job.arguments[0]];
            lines.push(graph_line(graph));
            let maximum: usize = job.arguments[1].parse().unwrap();
            let mut attempts = Vec::new();
            let mut accumulated = Statistics::default();
            let (mut total_removed, mut total_rounds) = (0, 0);
            for colors in 1..=maximum {
                let formula = encoders::coloring(graph.vertices, &graph.edges, colors);
                let solution = solve(&formula, 1);
                lines.push(format!("attempt k={} clauses={} removed={} result={} stop={} decisions={} propagations={} conflicts={} max_depth={}", colors, formula.clauses.len(), solution.simplified.removed_count(), solution.status(), solution.stop, solution.statistics.decisions, solution.statistics.propagations, solution.statistics.conflicts, solution.statistics.max_depth));
                accumulated.add(&solution.statistics);
                total_removed += solution.simplified.removed_count();
                total_rounds += solution.rounds;
                let sat = !solution.models.is_empty();
                attempts.push((formula, solution, colors));
                if sat { break; }
            }
            let count = attempts.len();
            let (formula, solution, colors) = attempts.pop().unwrap();
            lines.push(format!("result {} chromatic={} attempts={}", solution.status(), if solution.models.is_empty() { "-".into() } else { colors.to_string() }, count));
            lines.push(search_line(&accumulated));
            lines.extend(analysis(&formula, &solution, false));
            (formula, solution, colors, total_removed, total_rounds, accumulated)
        } else {
            let prepared = match command {
                "SOLVE" | "ENUM" | "CORE" => cnf_io::read(&job.arguments[0]),
                "QUEENS" => Ok(encoders::queens(job.arguments[0].parse().unwrap())),
                "PIGEON" => Ok(encoders::pigeon(job.arguments[0].parse().unwrap(), job.arguments[1].parse().unwrap())),
                "COLOR" => {
                    let graph = &graphs[&job.arguments[0]];
                    Ok(encoders::coloring(graph.vertices, &graph.edges, job.arguments[1].parse().unwrap()))
                }
                _ => unreachable!(),
            };
            let formula = match prepared {
                Ok(formula) => formula,
                Err(error) => { lines.push(format!("error {error}")); result_paragraphs.push(lines); continue; }
            };
            if command == "COLOR" { lines.push(graph_line(&graphs[&job.arguments[0]])); }
            let solution = solve(&formula, job.limit);
            lines.push(formula_line(&formula));
            lines.extend(preprocess_lines(&solution.simplified));
            lines.push(format!("result {} models={} rounds={} stop={}", solution.status(), solution.models.len(), solution.rounds, solution.stop));
            lines.push(search_line(&solution.statistics));
            if solution.rounds > 0 {
                let trace = if solution.trace.is_empty() { "-".into() } else { solution.trace.iter().take(12).cloned().collect::<Vec<_>>().join(" ") };
                let rest = if solution.trace.len() > 12 { format!(" +{}", solution.trace.len() - 12) } else { String::new() };
                lines.push(format!("trace {trace}{rest}"));
            }
            lines.extend(analysis(&formula, &solution, true));
            if command == "CORE" && solution.models.is_empty() { lines.push(core_line(&formula)); }
            let removed = solution.simplified.removed_count();
            let rounds = solution.rounds;
            let search = solution.statistics.clone();
            let colors = if command == "COLOR" { job.arguments[1].parse().unwrap() } else { 0 };
            (formula, solution, colors, removed, rounds, search)
        };
        if !solution.models.is_empty() {
            let mut model_lines = vec![heading];
            for (i, model) in solution.models.iter().enumerate() { model_lines.push(format!("model {}", i + 1)); model_lines.extend(cnf_io::model_lines(model)); }
            model_paragraphs.push(model_lines);
        }
        if ["QUEENS", "PIGEON", "COLOR", "CHROMATIC"].contains(&command) { board_paragraphs.push(board_lines(number, &job, &graphs, &solution, colors)); }
        statistics.push(JobStatistics { number, command: job.command.clone(), status: solution.status(), variables: formula.variables, clauses: formula.clauses.len(), removed, search, models: solution.models.len(), rounds });
        result_paragraphs.push(lines);
    }
    result_paragraphs.push(summary(jobs.len(), &statistics));
    let mut csv = vec!["job,command,status,variables,clauses,removed_clauses,decisions,propagations,conflicts,max_depth,models,rounds".into()];
    for s in &statistics {
        csv.push(format!("{},{},{},{},{},{},{},{},{},{},{},{}", s.number, s.command, s.status, s.variables, s.clauses, s.removed, s.search.decisions, s.search.propagations, s.search.conflicts, s.search.max_depth, s.models, s.rounds));
    }
    fs::create_dir_all("output").unwrap();
    report::paragraphs("results.txt", &result_paragraphs);
    report::paragraphs("models.txt", &model_paragraphs);
    report::paragraphs("boards.txt", &board_paragraphs);
    report::lines("stats.csv", &csv);
}
