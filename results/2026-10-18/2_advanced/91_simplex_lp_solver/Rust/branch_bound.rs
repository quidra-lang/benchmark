use crate::{Model, Bounds, LpResult, solve_lp};
use crate::rational::Fraction as F;
struct Node { bounds: Bounds, depth: usize, parent: Option<usize>, branch: String, value: Option<F> }
pub struct Outcome {
    pub status: &'static str, pub root: LpResult, pub solution: Option<Vec<F>>, pub objective: Option<F>,
    pub nodes: usize, pub phase1: usize, pub phase2: usize, pub drives: usize, pub lines: Vec<String>
}
impl Outcome { pub fn pivots(&self) -> usize { self.phase1 + self.phase2 + self.drives } }
pub fn solve(model: &Model, limit: usize, level: usize, log: &mut Vec<String>) -> Outcome {
    let mut stack = vec![Node { bounds: model.bounds.clone(), depth: 0, parent: None, branch: "root".into(), value: None }];
    let mut root = None;
    let (mut solution, mut objective) = (None, None);
    let (mut nodes, mut incumbents, mut pruned, mut infeasible, mut p1, mut p2, mut drives) = (0, 0, 0, 0, 0, 0, 0);
    let mut lines = vec![format!("MODEL {} {} integers {} node_limit {}", model.name, if model.maximize { "maximize" } else { "minimize" }, model.integer.iter().filter(|&&v| v).count(), limit)];
    let mut status = "INFEASIBLE";
    let better = |a: F, b: F| if model.maximize { a > b } else { a < b };
    while !stack.is_empty() {
        if nodes == limit { status = "NODE_LIMIT"; break; }
        let node = stack.pop().unwrap(); nodes += 1;
        let result = solve_lp(model, &node.bounds, nodes, level, log);
        p1 += result.phase1; p2 += result.phase2; drives += result.drives;
        if nodes == 1 { root = Some(result.clone()); }
        let outcome;
        if result.status == "INFEASIBLE" { infeasible += 1; outcome = "infeasible".into(); }
        else if result.status == "UNBOUNDED" { status = "UNBOUNDED"; outcome = "unbounded".into(); }
        else if objective.map_or(false, |best| !better(result.value, best)) { pruned += 1; outcome = "pruned".into(); }
        else if let Some(j) = (0..model.names.len()).find(|&j| model.integer[j] && result.solution[j].d != 1) {
            let value = result.solution[j];
            let lower = F::integer(value.floor()); let upper = F::integer(value.ceil());
            outcome = format!("branch {} {}", model.names[j], value);
            let mut ceil_bounds = node.bounds.clone(); ceil_bounds[j].0 = Some(upper);
            stack.push(Node { bounds: ceil_bounds, depth: node.depth + 1, parent: Some(nodes), branch: format!("{}>={}", model.names[j], upper), value: Some(result.value) });
            let mut floor_bounds = node.bounds.clone(); floor_bounds[j].1 = Some(lower);
            stack.push(Node { bounds: floor_bounds, depth: node.depth + 1, parent: Some(nodes), branch: format!("{}<={}", model.names[j], lower), value: Some(result.value) });
        } else {
            incumbents += 1; objective = Some(result.value); solution = Some(result.solution.clone()); outcome = "incumbent".into();
        }
        lines.push(format!("NODE {} depth {} parent {} branch {} lp {} pivots {} action {}", nodes, node.depth, node.parent.map_or_else(|| "-".into(), |v| v.to_string()), node.branch, if result.status == "OPTIMAL" { result.value.to_string() } else { result.status.to_ascii_lowercase() }, result.pivots(), outcome));
        if status == "UNBOUNDED" { break; }
    }
    if status != "NODE_LIMIT" && status != "UNBOUNDED" { status = if objective.is_some() { "OPTIMAL" } else { "INFEASIBLE" }; }
    let mut bound = objective;
    if status == "NODE_LIMIT" {
        for node in stack.iter().rev() {
            let value = node.value.unwrap();
            lines.push(format!("OPEN parent {} branch {} bound {}", node.parent.unwrap(), node.branch, value));
            if bound.map_or(true, |old| better(value, old)) { bound = Some(value); }
        }
    }
    lines.push(format!("RESULT {} objective {} nodes {} incumbents {} pruned {} infeasible {} open {} bound {}", status, objective.map_or_else(|| "-".into(), |v| v.to_string()), nodes, incumbents, pruned, infeasible, stack.len(), bound.map_or_else(|| "-".into(), |v| v.to_string())));
    Outcome { status, root: root.unwrap(), solution, objective, nodes, phase1: p1, phase2: p2, drives, lines }
}
