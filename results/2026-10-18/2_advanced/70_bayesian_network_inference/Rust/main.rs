mod network_io;
mod learning;
mod factors;
mod elimination;
mod sampling;
use std::collections::{ BTreeMap, BTreeSet, VecDeque };
use std::fs;
use network_io::Input;
use factors::Factor;
use elimination::Plan;
fn real(value: f64) -> String {
    let text = format!("{:.4}", value);
    if text == "-0.0000" {
        "0.0000".to_owned()
    } else {
        text
    }
}
fn yes(value: bool) -> &'static str {
    if value {
        "yes"
    } else {
        "no"
    }
}
fn closure(start: &[usize], graph: &[Vec<usize>]) -> Vec<usize> {
    let mut seen: BTreeSet<_> = start.iter().copied().collect();
    let mut queue = start.to_vec();
    while let Some(v) = queue.pop() {
        for &next in &graph[v] {
            if seen.insert(next) {
                queue.push(next);
            }
        }
    }
    seen.into_iter().collect()
}
fn project(state: &[usize], variables: &[usize]) -> Vec<usize> {
    variables.iter().map(|&v| state[v]).collect()
}
struct Engine<'a> {
    input: &'a Input,
    cards: Vec<usize>,
    parents: Vec<Vec<usize>>,
    children: Vec<Vec<usize>>,
    topological: Vec<usize>,
    cpts: Vec<Vec<Vec<f64>>>,
}
struct Posterior {
    relevant: Vec<usize>,
    eliminate: Vec<usize>,
    minfill: Plan,
    given: Plan,
    variables: Vec<usize>,
    probabilities: Vec<f64>,
    marginals: Vec<Vec<f64>>,
    evidence: f64
}
impl<'a> Engine<'a> {
    fn new(input: &'a Input) -> Self {
        let n = input.variables.len();
        let cards: Vec<_> = input.variables.iter().map(|v| v.states.len()).collect();
        let parents: Vec<_> = input.variables.iter().map(|v| v.parents.clone()).collect();
        let mut children = vec![Vec::new(); n];
        for (child, ps) in parents.iter().enumerate() {
            for &parent in ps {
                children[parent].push(child);
            }
        }
        let mut topological = Vec::new();
        while topological.len() < n {
            let next = (0..n).find(|v| !topological.contains(v) && parents[*v].iter().all(|p| topological.contains(p))).unwrap();
            topological.push(next);
        }
        let cpts = (0..n).map(|v| {
            if input.params.learned[v] {
                learning::learned(&learning::counts(v, &parents[v], &cards, &input.samples), input.params.pseudocount)
            } else {
                input.variables[v].given.clone().unwrap()
            }
        }).collect();
        Self {
            input,
            cards,
            parents,
            children,
            topological,
            cpts
        }
    }
    fn names(&self, variables: &[usize]) -> String {
        if variables.is_empty() {
            "-".to_owned()
        } else {
            variables.iter().map(|&v| self.input.variables[v].name.as_str()).collect::<Vec<_>>().join(" ")
        }
    }
    fn variable(&self, name: &str) -> usize {
        self.input.variables.iter().position(|v| v.name == name).unwrap()
    }
    fn evidence(&self, words: &[&str]) -> Vec<(usize, usize)> {
        words.iter().map(|word| {
            let (v, s) = word.split_once('=').unwrap();
            let variable = self.variable(v);
            (variable, self.input.variables[variable].states.iter().position(|state| state == s).unwrap())
        }).collect()
    }
    fn initial(&self, relevant: &[usize], evidence: &[(usize, usize)]) -> Vec<Factor> {
        relevant.iter().map(|&v| Factor::cpt(v, &self.parents[v], &self.cpts[v], &self.cards).reduce(evidence, &self.cards)).collect()
    }
    fn plans(&self, initial: &[Factor], eliminate: &[usize]) -> (Plan, Plan) {
        (elimination::plan(initial, eliminate, &self.cards, true, &self.input.params.order), elimination::plan(initial, eliminate, &self.cards, false, &self.input.params.order))
    }
    fn infer(&self, query: &[usize], evidence: &[(usize, usize)]) -> Posterior {
        let relevant = closure(&query.iter().copied().chain(evidence.iter().map(|e| e.0)).collect::<Vec<_>>(), &self.parents);
        let initial = self.initial(&relevant, evidence);
        let eliminate: Vec<_> = relevant.iter().copied().filter(|v| !query.contains(v) && !evidence.iter().any(|e| e.0 == *v)).collect();
        let (minfill, given) = self.plans(&initial, &eliminate);
        let used = if self.input.params.minfill {
            &minfill
        } else {
            &given
        };
        let result = elimination::execute(&initial, used, false, &self.cards).factor;
        let total: f64 = result.values.iter().sum();
        let probabilities: Vec<_> = result.values.iter().map(|p| p/total).collect();
        let mut marginals: Vec<_> = self.cards.iter().map(|&k| vec![0.0; k]).collect();
        for (index, &probability) in probabilities.iter().enumerate() {
            let state = factors::assignment(index, &result.variables, &self.cards);
            for &v in query {
                marginals[v][state[v]] += probability;
            }
        }
        Posterior {
            relevant,
            eliminate,
            minfill,
            given,
            variables: result.variables,
            probabilities,
            marginals,
            evidence: total
        }
    }
    fn joint(&self, state: &[usize], relevant: &[usize]) -> f64 {
        let mut probability = 1.0;
        for &v in relevant {
            probability *= self.cpts[v][learning::combination(&self.parents[v], state, &self.cards)][state[v]];
        }
        probability
    }
    fn spouses(&self, v: usize) -> Vec<usize> {
        self.children[v].iter().flat_map(|&c| self.parents[c].iter().copied()).filter(|&p| p != v && !self.parents[v].contains(&p) && !self.children[v].contains(&p)).collect::<BTreeSet<_>>().into_iter().collect()
    }
    fn blanket(&self, v: usize) -> Vec<usize> {
        self.parents[v].iter().chain(&self.children[v]).copied().chain(self.spouses(v)).collect::<BTreeSet<_>>().into_iter().collect()
    }
    fn reachable(&self, x: &[usize], z: &[usize]) -> Vec<usize> {
        let ancestors = closure(z, &self.parents);
        let mut seen = BTreeSet::new();
        let mut queue = VecDeque::new();
        for &v in x {
            seen.insert((v, false));
            queue.push_back((v, false));
        }
        while let Some((v, down)) = queue.pop_front() {
            let mut positions = Vec::new();
            if !down && !z.contains(&v) {
                positions.extend(self.parents[v].iter().map(|&p| (p, false)));
                positions.extend(self.children[v].iter().map(|&c| (c, true)));
            } else if down {
                if !z.contains(&v) {
                    positions.extend(self.children[v].iter().map(|&c| (c, true)));
                }
                if ancestors.contains(&v) {
                    positions.extend(self.parents[v].iter().map(|&p| (p, false)));
                }
            }
            for position in positions {
                if seen.insert(position) {
                    queue.push_back(position);
                }
            }
        }
        seen.iter().map(|&(v, _)| v).filter(|v| !z.contains(v) && !x.contains(v)).collect::<BTreeSet<_>>().into_iter().collect()
    }
    fn path(&self, start: usize, target: usize, ignored: Option<(usize, usize)>) -> Option<Vec<usize>> {
        let mut parents = vec![None; self.cards.len()];
        parents[start] = Some(start);
        let mut queue = VecDeque::from([start]);
        while let Some(v) = queue.pop_front() {
            for &child in &self.children[v] {
                if ignored == Some((v, child)) || parents[child].is_some() {
                    continue;
                }
                parents[child] = Some(v);
                if child == target {
                    let mut path = vec![target];
                    while *path.last().unwrap() != start {
                        path.push(parents[*path.last().unwrap()].unwrap());
                    }
                    path.reverse();
                    return Some(path);
                }
                queue.push_back(child);
            }
        }
        None
    }
    fn family(&self, v: usize, parents: &[usize]) -> f64 {
        learning::score(v, parents, &self.cards, &self.input.samples, self.input.params.pseudocount)
    }
    fn marginal_line(&self, keyword: &str, v: usize, marginal: &[f64]) -> String {
        format!("{} {} {}", keyword, self.input.variables[v].name, self.input.variables[v].states.iter().enumerate().map(|(s, name)| format!("{} {}", name, real(marginal[s]))).collect::<Vec<_>>().join(" "))
    }
}
fn plan_lines(engine: &Engine<'_>, plan: &Plan, name: &str) -> Vec<String> {
    let mut lines = vec![format!("order {}", name)];
    for step in &plan.steps {
        lines.push(format!("step {} fill {} scope {} entries {}", engine.input.variables[step.variable].name, step.fill, engine.names(&step.variables), step.size));
    }
    lines.push(format!("cost max {} total {}", plan.maximum, plan.total));
    lines
}
fn elimination_lines(engine: &Engine<'_>, query: usize, line: &str, relevant: &[usize], eliminate: &[usize], minfill: &Plan, given: &Plan, agree: bool, count: usize, enumeration: &str) -> Vec<String> {
    let pruned: Vec<_> = (0..engine.cards.len()).filter(|v| !relevant.contains(v)).collect();
    let mut lines = vec![format!("query {} {}", query, line), format!("relevant {}", engine.names(relevant)), format!("pruned {}", engine.names(&pruned)), format!("eliminate {}", engine.names(eliminate))];
    lines.extend(plan_lines(engine, minfill, "minfill"));
    lines.extend(plan_lines(engine, given, "given"));
    lines.extend([format!("used {}", if engine.input.params.minfill {
        "minfill"
    } else {
        "given"
    }), format!("orders_agree {}", yes(agree)), format!("enumeration {} {}", count, enumeration)]);
    lines
}
fn add_block(output: &mut Vec<String>, block: Vec<String>) {
    if !output.is_empty() {
        output.push(String::new());
    }
    output.extend(block);
}
fn agree_probabilities(a: &[f64], za: f64, b: &[f64], zb: f64) -> bool {
    (za.ln()-zb.ln()).abs() <= 0.000000001 && a.iter().zip(b).all(|(a, b)| (a-b).abs() <= 0.000000001)
}
fn parse_query<'a>(engine: &Engine<'_>, words: &[&'a str]) -> (Vec<usize>, Vec<(usize, usize)>) {
    let bar = words.iter().position(|&w| w == "|");
    let query = words[..bar.unwrap_or(words.len())].iter().map(|w| engine.variable(w)).collect();
    let evidence = bar.map_or_else(Vec::new, |i| engine.evidence(&words[i+1..]));
    (query, evidence)
}
fn canonical(words: &[&str], engine: &Engine<'_>) -> Vec<usize> {
    words.iter().map(|name| engine.variable(name)).collect::<BTreeSet<_>>().into_iter().collect()
}
fn main() {
    let input = network_io::read();
    let engine = Engine::new(&input);
    let n = input.variables.len();
    let all: Vec<_> = (0..n).collect();
    let initial = engine.initial(&all, &[]);
    let (full_minfill, full_given) = engine.plans(&initial, &all);
    let mut cpts = Vec::new();
    let mut log_likelihood = 0.0;
    let mut parameters = 0;
    for v in 0..n {
        if v > 0 {
            cpts.push(String::new());
        }
        let variable = &input.variables[v];
        let counts = learning::counts(v, &engine.parents[v], &engine.cards, &input.samples);
        let ll = learning::log_likelihood(&counts, &engine.cpts[v]);
        let d = learning::parameters(v, &engine.parents[v], &engine.cards);
        log_likelihood += ll;
        parameters += d;
        cpts.extend([format!("variable {} source {}", variable.name, if input.params.learned[v] {
            "LEARNED"
        } else {
            "GIVEN"
        }), format!("states {}", variable.states.join(" ")), format!("parents {}", engine.names(&variable.parents))]);
        for row in 0..counts.len() {
            let state = factors::assignment(row, &variable.parents, &engine.cards);
            let combination = if variable.parents.is_empty() {
                "-".to_owned()
            } else {
                variable.parents.iter().map(|&p| format!("{}={}", input.variables[p].name, input.variables[p].states[state[p]])).collect::<Vec<_>>().join(" ")
            };
            cpts.push(format!("row {} counts {} probs {}", combination, counts[row].iter().map(usize::to_string).collect::<Vec<_>>().join(" "), engine.cpts[v][row].iter().map(|&p| real(p)).collect::<Vec<_>>().join(" ")));
        }
        cpts.push(format!("loglik {} parameters {} bic {}", real(ll), d, real(ll-d as f64*(input.samples.len() as f64).ln()/2.0)));
        let marginal = engine.infer(&[v], &[]).marginals[v].clone();
        let frequencies: Vec<_> = (0..engine.cards[v]).map(|s| input.samples.iter().filter(|sample| sample[v] == s).count() as f64/input.samples.len() as f64).collect();
        cpts.push(format!("marginal model {} data {}", marginal.iter().map(|&p| real(p)).collect::<Vec<_>>().join(" "), frequencies.iter().map(|&p| real(p)).collect::<Vec<_>>().join(" ")));
        if input.params.learned[v] {
            let difference = variable.given.as_ref().map_or_else(|| "-".to_owned(), |given| real(given.iter().flatten().zip(engine.cpts[v].iter().flatten()).map(|(a, b)| (a-b).abs()).fold(0.0, f64::max)));
            cpts.push(format!("given_difference {}", difference));
        }
    }
    cpts.push(String::new());
    cpts.push(format!("network samples {} pseudocount {} loglik {} parameters {} bic {}", input.samples.len(), real(input.params.pseudocount), real(log_likelihood), parameters, real(log_likelihood-parameters as f64*(input.samples.len() as f64).ln()/2.0)));
    let mut moral = BTreeSet::new();
    for v in 0..n {
        let family: Vec<_> = engine.parents[v].iter().copied().chain(std::iter::once(v)).collect();
        for &a in &family {
            for &b in &family {
                if a < b {
                    moral.insert((a, b));
                }
            }
        }
    }
    let width = |plan: &Plan| plan.steps.iter().map(|s| s.variables.len()).max().unwrap()-1;
    let mut structure = vec![format!("variables {} edges {}", n, engine.parents.iter().map(Vec::len).sum::<usize>()), format!("topological_order {}", engine.names(&engine.topological)), format!("roots {}", engine.names(&(0..n).filter(|&v| engine.parents[v].is_empty()).collect::<Vec<_>>())), format!("leaves {}", engine.names(&(0..n).filter(|&v| engine.children[v].is_empty()).collect::<Vec<_>>())), format!("moral_edges {} width minfill {} given {}", moral.len(), width(&full_minfill), width(&full_given))];
    let mut depth = vec![0; n];
    for &v in &engine.topological {
        if !engine.parents[v].is_empty() {
            depth[v] = engine.parents[v].iter().map(|&p| depth[p]).max().unwrap()+1;
        }
    }
    for v in 0..n {
        structure.push(format!("variable {} states {} parents {} children {} depth {} ancestors {} descendants {} blanket {}", input.variables[v].name, engine.cards[v], engine.parents[v].len(), engine.children[v].len(), depth[v], closure(&[v], &engine.parents).len()-1, closure(&[v], &engine.children).len()-1, engine.blanket(v).len()));
    }
    let mut answers = Vec::new();
    let mut elimination_output = Vec::new();
    let mut sampling_csv = vec!["query,samples,variable,state,estimate,exact,abs_error".to_owned()];
    let mut generator = sampling::Generator {
        state: input.params.seed
    };
    for (number, line) in input.queries.iter().enumerate() {
        let number = number+1;
        let words: Vec<_> = line.split_whitespace().collect();
        let header = format!("query {} {}", number, line);
        match words[0] {
            "QUERY" => {
                let (query, evidence) = parse_query(&engine, &words[1..]);
                let posterior = engine.infer(&query, &evidence);
                let mut block = vec![header, format!("log_evidence {}", real(posterior.evidence.ln()))];
                if !evidence.is_empty() {
                    let conflict = evidence.iter().map(|&e| engine.infer(&[], &[e]).evidence.ln()).sum::<f64>()-posterior.evidence.ln();
                    block.push(format!("conflict {}", real(conflict)));
                }
                if query.len() >= 2 {
                    for (index, &probability) in posterior.probabilities.iter().enumerate() {
                        let state = factors::assignment(index, &posterior.variables, &engine.cards);
                        let assignment = posterior.variables.iter().map(|&v| format!("{}={}", input.variables[v].name, input.variables[v].states[state[v]])).collect::<Vec<_>>().join(" ");
                        block.push(format!("joint {} {}", assignment, real(probability)));
                    }
                }
                for &v in &query {
                    block.push(engine.marginal_line("marginal", v, &posterior.marginals[v]));
                }
                for (dropped, &(v, s)) in evidence.iter().enumerate() {
                    let reduced: Vec<_> = evidence.iter().enumerate().filter(|(i, _)| *i != dropped).map(|(_, &e)| e).collect();
                    let without = engine.infer(&query, &reduced);
                    let shift = query.iter().flat_map(|&q| posterior.marginals[q].iter().zip(&without.marginals[q]).map(|(a, b)| (a-b).abs())).fold(0.0, f64::max);
                    block.push(format!("drop {}={} shift {}", input.variables[v].name, input.variables[v].states[s], real(shift)));
                }
                add_block(&mut answers, block);
                let initial = engine.initial(&posterior.relevant, &evidence);
                let min_result = elimination::execute(&initial, &posterior.minfill, false, &engine.cards).factor;
                let given_result = elimination::execute(&initial, &posterior.given, false, &engine.cards).factor;
                let z1: f64 = min_result.values.iter().sum();
                let z2: f64 = given_result.values.iter().sum();
                let p1: Vec<_> = min_result.values.iter().map(|p| p/z1).collect();
                let p2: Vec<_> = given_result.values.iter().map(|p| p/z2).collect();
                let agree = agree_probabilities(&p1, z1, &p2, z2);
                let unknown: Vec<_> = posterior.relevant.iter().copied().filter(|v| !evidence.iter().any(|e| e.0 == *v)).collect();
                let count = factors::count(&unknown, &engine.cards);
                let enumeration = if count > input.params.limit {
                    "skipped"
                } else {
                    let mut values = vec![0.0; posterior.probabilities.len()];
                    for index in 0..count {
                        let mut state = factors::assignment(index, &unknown, &engine.cards);
                        for &(v, s) in &evidence {
                            state[v] = s;
                        }
                        let qindex = posterior.variables.iter().fold(0, |i, &v| i*engine.cards[v]+state[v]);
                        values[qindex] += engine.joint(&state, &posterior.relevant);
                    }
                    let total: f64 = values.iter().sum();
                    let normalized: Vec<_> = values.iter().map(|p| p/total).collect();
                    if agree_probabilities(&posterior.probabilities, posterior.evidence, &normalized, total) {
                        "agree"
                    } else {
                        "disagree"
                    }
                };
                add_block(&mut elimination_output, elimination_lines(&engine, number, line, &posterior.relevant, &posterior.eliminate, &posterior.minfill, &posterior.given, agree, count, enumeration));
            }
            "MPE" => {
                let evidence = engine.evidence(&words[1..]);
                let initial = engine.initial(&all, &evidence);
                let eliminate: Vec<_> = all.iter().copied().filter(|v| !evidence.iter().any(|e| e.0 == *v)).collect();
                let (minfill, given) = engine.plans(&initial, &eliminate);
                let min_result = elimination::execute(&initial, &minfill, true, &engine.cards);
                let given_result = elimination::execute(&initial, &given, true, &engine.cards);
                let min_state = elimination::traceback(&min_result, &evidence, &engine.cards);
                let given_state = elimination::traceback(&given_result, &evidence, &engine.cards);
                let (used, state) = if input.params.minfill {
                    (&min_result, &min_state)
                } else {
                    (&given_result, &given_state)
                };
                let maximum = used.factor.values[0];
                let probability = if evidence.is_empty() {
                    1.0
                } else {
                    engine.infer(&[], &evidence).evidence
                };
                let assignment = (0..n).map(|v| format!("{}={}", input.variables[v].name, input.variables[v].states[state[v]])).collect::<Vec<_>>().join(" ");
                let mut block = vec![header, format!("assignment {}", assignment), format!("log_joint {}", real(maximum.ln())), format!("log_evidence {}", real(probability.ln())), format!("posterior {}", real(maximum/probability))];
                for &v in &eliminate {
                    let remaining: Vec<_> = eliminate.iter().copied().filter(|&u| u != v).collect();
                    let (m, g) = engine.plans(&initial, &remaining);
                    let plan = if input.params.minfill {
                        &m
                    } else {
                        &g
                    };
                    let marginal = elimination::execute(&initial, plan, true, &engine.cards).factor;
                    let second = (0..engine.cards[v]).filter(|&s| s != state[v]).min_by(|&a, &b| marginal.values[b].total_cmp(&marginal.values[a]).then(a.cmp(&b))).unwrap();
                    block.push(format!("margin {} {} {}", input.variables[v].name, input.variables[v].states[second], real(maximum.ln()-marginal.values[second].ln())));
                }
                add_block(&mut answers, block);
                let agree = min_state == given_state && (min_result.factor.values[0].ln()-given_result.factor.values[0].ln()).abs() <= 0.000000001;
                let count = factors::count(&eliminate, &engine.cards);
                let enumeration = if count > input.params.limit {
                    "skipped"
                } else {
                    let mut best = f64::NEG_INFINITY;
                    let mut best_state = Vec::new();
                    for index in 0..count {
                        let mut state = factors::assignment(index, &eliminate, &engine.cards);
                        for &(v, s) in &evidence {
                            state[v] = s;
                        }
                        let probability = engine.joint(&state, &all);
                        if probability > best {
                            best = probability;
                            best_state = state;
                        }
                    }
                    if best_state == *state && (best.ln()-maximum.ln()).abs() <= 0.000000001 {
                        "agree"
                    } else {
                        "disagree"
                    }
                };
                add_block(&mut elimination_output, elimination_lines(&engine, number, line, &all, &eliminate, &minfill, &given, agree, count, enumeration));
            }
            "SAMPLE" => {
                let counts = words.iter().position(|&w| w == "COUNTS").unwrap();
                let (query, evidence) = parse_query(&engine, &words[1..counts]);
                let counts: Vec<usize> = words[counts+1..].iter().map(|s| s.parse().unwrap()).collect();
                let exact = engine.infer(&query, &evidence);
                let mut block = vec![header];
                for &v in &query {
                    block.push(engine.marginal_line("exact", v, &exact.marginals[v]));
                }
                let mut sums: Vec<_> = engine.cards.iter().map(|&k| vec![0.0; k]).collect();
                let (mut weight, mut squared) = (0.0, 0.0);
                for i in 1..=*counts.last().unwrap() {
                    let (state, w) = sampling::weighted(&mut generator, &engine.topological, &engine.parents, &engine.cards, &engine.cpts, &evidence);
                    weight += w;
                    squared += w*w;
                    for &v in &query {
                        sums[v][state[v]] += w;
                    }
                    if counts.contains(&i) {
                        let mut maximum: f64 = 0.0;
                        for &v in &query {
                            for s in 0..engine.cards[v] {
                                let estimate = sums[v][s]/weight;
                                let error = (estimate-exact.marginals[v][s]).abs();
                                maximum = maximum.max(error);
                                sampling_csv.push(format!("{},{},{},{},{},{},{}", number, i, input.variables[v].name, input.variables[v].states[s], real(estimate), real(exact.marginals[v][s]), real(error)));
                            }
                        }
                        block.push(format!("after {} weight {} ess {} max_error {}", i, real(weight), real(weight*weight/squared), real(maximum)));
                    }
                }
                add_block(&mut answers, block);
            }
            "PREDICT" => {
                let v = engine.variable(words[1]);
                let mut confusion = vec![vec![0usize; engine.cards[v]]; engine.cards[v]];
                let mut loss = 0.0;
                for sample in &input.samples {
                    let mut assignment = sample.clone();
                    let mut values = Vec::new();
                    for s in 0..engine.cards[v] {
                        assignment[v] = s;
                        let mut probability = engine.cpts[v][learning::combination(&engine.parents[v], &assignment, &engine.cards)][s];
                        for &c in &engine.children[v] {
                            probability *= engine.cpts[c][learning::combination(&engine.parents[c], &assignment, &engine.cards)][sample[c]];
                        }
                        values.push(probability);
                    }
                    let total: f64 = values.iter().sum();
                    let prediction = (0..values.len()).min_by(|&a, &b| values[b].total_cmp(&values[a]).then(a.cmp(&b))).unwrap();
                    confusion[sample[v]][prediction] += 1;
                    loss += (values[sample[v]]/total).ln();
                }
                let correct: usize = (0..engine.cards[v]).map(|s| confusion[s][s]).sum();
                let mut block = vec![header, format!("blanket {}", engine.names(&engine.blanket(v))), format!("accuracy {}/{} {}", correct, input.samples.len(), real(correct as f64/input.samples.len() as f64)), format!("log_loss {}", real(-loss/input.samples.len() as f64)), format!("predicted {}", input.variables[v].states.join(" "))];
                for s in 0..engine.cards[v] {
                    block.push(format!("actual {} {}", input.variables[v].states[s], confusion[s].iter().map(usize::to_string).collect::<Vec<_>>().join(" ")));
                }
                add_block(&mut answers, block);
            }
            "DSEP" => {
                let groups: Vec<_> = words[1..].split(|word| *word == "|").map(|g| canonical(g, &engine)).collect();
                let (x, y) = (&groups[0], &groups[1]);
                let z = groups.get(2).cloned().unwrap_or_default();
                let reachable = engine.reachable(x, &z);
                let separated = y.iter().all(|v| !reachable.contains(v));
                let w: Vec<_> = x.iter().chain(y).chain(&z).copied().collect::<BTreeSet<_>>().into_iter().collect();
                let xz: Vec<_> = x.iter().chain(&z).copied().collect::<BTreeSet<_>>().into_iter().collect();
                let yz: Vec<_> = y.iter().chain(&z).copied().collect::<BTreeSet<_>>().into_iter().collect();
                let mut full = BTreeMap::<Vec<usize>, usize>::new();
                let mut cxz = BTreeMap::<Vec<usize>, usize>::new();
                let mut cyz = BTreeMap::<Vec<usize>, usize>::new();
                let mut cz = BTreeMap::<Vec<usize>, usize>::new();
                for sample in &input.samples {
                    *full.entry(project(sample, &w)).or_default() += 1;
                    *cxz.entry(project(sample, &xz)).or_default() += 1;
                    *cyz.entry(project(sample, &yz)).or_default() += 1;
                    *cz.entry(project(sample, &z)).or_default() += 1;
                }
                let mut cmi = 0.0;
                for (values, count) in full {
                    let mut state = vec![0; n];
                    for (&v, &s) in w.iter().zip(&values) {
                        state[v] = s;
                    }
                    let nz = cz[&project(&state, &z)];
                    let nxz = cxz[&project(&state, &xz)];
                    let nyz = cyz[&project(&state, &yz)];
                    cmi += count as f64/input.samples.len() as f64*((count*nz) as f64/(nxz*nyz) as f64).ln();
                }
                let df = (factors::count(x, &engine.cards)-1)*(factors::count(y, &engine.cards)-1)*factors::count(&z, &engine.cards);
                add_block(&mut structure, vec![header, format!("result {}", if separated {
                    "separated"
                } else {
                    "connected"
                }), format!("reachable {}", engine.names(&reachable)), format!("data cmi {} g2 {} df {}", real(cmi), real(2.0*input.samples.len() as f64*cmi), df)]);
            }
            "BLANKET" => {
                let v = engine.variable(words[1]);
                let blanket = engine.blanket(v);
                let rest: Vec<_> = all.iter().copied().filter(|&u| u != v && !blanket.contains(&u)).collect();
                let reachable = engine.reachable(&[v], &blanket);
                let separated = rest.iter().all(|v| !reachable.contains(v));
                add_block(&mut structure, vec![header, format!("parents {}", engine.names(&engine.parents[v])), format!("children {}", engine.names(&engine.children[v])), format!("spouses {}", engine.names(&engine.spouses(v))), format!("blanket {}", engine.names(&blanket)), format!("rest {}", engine.names(&rest)), format!("rest_separated {}", yes(separated))]);
            }
            _ => {
                let (x, y) = (engine.variable(words[2]), engine.variable(words[3]));
                let exists = engine.parents[y].contains(&x);
                let operation = words[1];
                let mut block = vec![header];
                if operation == "ADD" && exists {
                    block.push("result exists".to_owned());
                } else if operation != "ADD" && !exists {
                    block.push("result missing".to_owned());
                } else {
                    let path = if operation == "ADD" {
                        engine.path(y, x, None)
                    } else if operation == "REVERSE" {
                        engine.path(x, y, Some((x, y)))
                    } else {
                        None
                    };
                    if let Some(path) = path {
                        let cycle: Vec<_> = std::iter::once(if operation == "ADD" {
                            x
                        } else {
                            y
                        }).chain(path).collect();
                        block.push(format!("result cycle {}", cycle.iter().map(|&v| input.variables[v].name.as_str()).collect::<Vec<_>>().join(" -> ")));
                    } else {
                        block.push("result ok".to_owned());
                        let before_y = engine.family(y, &engine.parents[y]);
                        let mut parents_y = engine.parents[y].clone();
                        if operation == "ADD" {
                            parents_y.push(x);
                        } else {
                            parents_y.retain(|&v| v != x);
                        }
                        let after_y = engine.family(y, &parents_y);
                        let mut change = after_y-before_y;
                        block.push(format!("family {} before {} after {}", input.variables[y].name, real(before_y), real(after_y)));
                        if operation == "REVERSE" {
                            let before_x = engine.family(x, &engine.parents[x]);
                            let mut parents_x = engine.parents[x].clone();
                            parents_x.push(y);
                            let after_x = engine.family(x, &parents_x);
                            change += after_x-before_x;
                            block.push(format!("family {} before {} after {}", input.variables[x].name, real(before_x), real(after_x)));
                        }
                        block.push(format!("delta {} {}", real(change), if change > 0.0 {
                            "improves"
                        } else {
                            "worsens"
                        }));
                    }
                }
                add_block(&mut structure, block);
            }
        }
    }
    fs::create_dir_all("output").unwrap();
    for (file, lines) in [("cpts.txt", cpts), ("structure.txt", structure), ("answers.txt", answers), ("elimination.txt", elimination_output), ("sampling.csv", sampling_csv)] {
        let contents = if lines.is_empty() {
            String::new()
        } else {
            lines.join("\n")+"\n"
        };
        fs::write(format!("output/{}", file), contents).unwrap();
    }
}
