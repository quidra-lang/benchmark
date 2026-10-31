mod tac_parser;
mod cfg;
mod dataflow;
mod optimizations;
mod regalloc;
use std::collections::{
    BTreeMap,
    BTreeSet
};
use std::fs;
use tac_parser::{
    Program,
    Function,
    Line,
    Instruction,
    Operand,
    Expression
};
use cfg::Graph;
use dataflow::Analysis;
const PASSES: [&str;
6] = ["constprop", "copyprop", "cse", "dce", "licm", "unreachable"];
const KINDS: [&str;
11] = ["copy", "bin", "load", "store", "goto", "if", "param", "call", "return", "read", "print"];
fn list(values: impl IntoIterator<Item = String>) -> String {
    let values: Vec<String> = values.into_iter().collect();
    if values.is_empty() {
        "-".into()
    } else {
        values.join(",")
    }
}
fn block_list(values: impl IntoIterator<Item = usize>) -> String {
    list(values.into_iter().map(|b| format!("B{}", b + 1)))
}
fn numbers(values: impl IntoIterator<Item = usize>) -> String {
    list(values.into_iter().map(|n| format!("#{}", n + 1)))
}
fn constant(instructions: &[Instruction], definitions: &dataflow::Definitions, variable: &str) -> Option<i64> {
    let definitions: Vec<usize> = definitions.iter().filter(|d| d.0 == variable).map(|d| d.1).collect();
    if definitions.is_empty() || definitions.contains(&0) {
        return None;
    }
    let mut value = None;
    for number in definitions {
        let instruction = &instructions[number - 1];
        if instruction.kind != "copy" {
            return None;
        }
        let current = instruction.a.as_ref()?.constant()?;
        if value.map_or(false, |v| v != current) {
            return None;
        }
        value = Some(current);
    }
    value
}
fn propagate(function: &mut Function, graph: &Graph, analysis: &Analysis, constants: bool) -> (usize, Vec<String>) {
    let instructions = function.instructions();
    let mut replacements = BTreeMap::new();
    let mut records = Vec::new();
    for (i, instruction) in instructions.iter().enumerate() {
        if !graph.reachable.contains(&graph.owners[i]) {
            continue;
        }
        let mut instruction = instruction.clone();
        for operand in instruction.operands_mut() {
            if let Operand::Variable(variable) = operand.clone() {
                let replacement = if constants {
                    constant(&instructions, &analysis.before_definitions[i], &variable).map(Operand::Constant)
                } else {
                    analysis.before_copies[i].iter().find(|p| p.0 == variable).map(|p| Operand::Variable(p.1.clone()))
                };
                if let Some(replacement) = replacement {
                    records.push(format!("#{}: {} -> {}", i + 1, variable, replacement.text()));
                    *operand = replacement;
                }
            }
        }
        if constants {
            if let Some(folded) = optimizations::fold(&instruction) {
                if let Some(folded) = folded {
                    records.push(format!("#{}: fold {}", i + 1, folded.text()));
                    replacements.insert(i, vec![folded]);
                }
                else {
                    records.push(format!("#{}: delete {}", i + 1, instruction.text()));
                    replacements.insert(i, Vec::new());
                }
                continue;
            }
        }
        replacements.insert(i, vec![instruction]);
    }
    optimizations::rewrite(function, &replacements);
    (records.len(), records)
}
fn cse(function: &mut Function, graph: &Graph, analysis: &Analysis) -> (usize, Vec<String>) {
    let instructions = function.instructions();
    let mut groups: BTreeMap<Expression,
    Vec<usize>> = BTreeMap::new();
    for (i, instruction) in instructions.iter().enumerate() {
        if graph.reachable.contains(&graph.owners[i]) {
            if let Some(expression) = instruction.expression() {
                if analysis.before_expressions[i].contains(&expression) {
                    groups.entry(expression).or_default().push(i);
                }
            }
        }
    }
    let mut groups: Vec<_> = groups.into_iter().collect();
    groups.sort_by_key(|g| g.1[0]);
    let mut replacements = BTreeMap::new();
    let mut records = Vec::new();
    let mut count = 0;
    for (expression, candidates) in groups {
        let mut sources = BTreeSet::new();
        for &candidate in &candidates {
            let block = graph.owners[candidate];
            let first = graph.blocks[block].first;
            if let Some(source) = (first..candidate).rev().find(|&i| instructions[i].expression().as_ref() == Some(&expression)) {
                sources.insert(source);
                continue;
            }
            let mut pending: Vec<usize> = graph.blocks[block].predecessors.iter().copied().filter(|p| graph.reachable.contains(p)).collect();
            let mut seen = BTreeSet::new();
            while let Some(block) = pending.pop() {
                if !seen.insert(block) {
                    continue;
                }
                if let Some(source) = (graph.blocks[block].first..=graph.blocks[block].last).rev().find(|&i| instructions[i].expression().as_ref() == Some(&expression)) {
                    sources.insert(source);
                }
                else {
                    pending.extend(graph.blocks[block].predecessors.iter().copied().filter(|p| graph.reachable.contains(p)));
                }
            }
        }
        for candidate in &candidates {
            sources.remove(candidate);
        }
        let temporary = optimizations::temporary(function);
        for &source in &sources {
            replacements.insert(source, optimizations::cse_rewrite(&instructions[source], &temporary, true));
        }
        for &candidate in &candidates {
            replacements.insert(candidate, optimizations::cse_rewrite(&instructions[candidate], &temporary, false));
        }
        records.push(format!("{}: {} sources={} replaced={}", expression.text(), temporary, numbers(sources.iter().copied()), numbers(candidates.iter().copied())));
        count += candidates.len();
    }
    optimizations::rewrite(function, &replacements);
    (count, records)
}
fn dce(function: &mut Function, graph: &Graph, analysis: &Analysis) -> (usize, Vec<String>) {
    let instructions = function.instructions();
    let mut replacements = BTreeMap::new();
    let mut records = BTreeMap::new();
    for &b in &graph.reachable {
        let mut live = analysis.live.output[b].clone();
        for i in (graph.blocks[b].first..=graph.blocks[b].last).rev() {
            let instruction = &instructions[i];
            let destination = instruction.destination.as_ref();
            let self_copy = instruction.kind == "copy" && destination.map(String::as_str) == instruction.a.as_ref().and_then(Operand::variable);
            let dead = ["copy", "bin", "load"].contains(&instruction.kind) && destination.map_or(false, |d| !live.contains(d));
            if self_copy || dead {
                replacements.insert(i, Vec::new());
                records.insert(i, format!("#{}: delete {}", i + 1, instruction.text()));
                continue;
            }
            let mut instruction = instruction.clone();
            if instruction.kind == "call" && destination.map_or(false, |d| !live.contains(d)) {
                records.insert(i, format!("#{}: unused result {}", i + 1, instruction.text()));
                instruction.destination = None;
                replacements.insert(i, vec![instruction.clone()]);
            }
            dataflow::live_transfer(&mut live, &instruction);
        }
    }
    optimizations::rewrite(function, &replacements);
    (records.len(), records.into_iter().map(|e| e.1).collect())
}
fn licm(function: &mut Function, graph: &Graph, analysis: &Analysis) -> (usize, Vec<String>) {
    let instructions = function.instructions();
    let mut loops: Vec<_> = graph.loops.iter().collect();
    loops.sort_by_key(|l| (l.blocks.len(), l.header));
    for natural_loop in loops {
        let inside = |number: usize| number != 0 && natural_loop.blocks.contains(&graph.owners[number - 1]);
        let indices: Vec<usize> = (0..instructions.len()).filter(|&i| natural_loop.blocks.contains(&graph.owners[i])).collect();
        let mut marked = BTreeSet::new();
        let mut mark_order = Vec::new();
        loop {
            let mut changed = false;
            for &i in &indices {
                let instruction = &instructions[i];
                if marked.contains(&i) || !["copy", "bin", "load"].contains(&instruction.kind) {
                    continue;
                }
                if instruction.kind == "load" && indices.iter().any(|&j| instructions[j].kind == "call" || (instructions[j].kind == "store" && instructions[j].array == instruction.array)) {
                    continue;
                }
                let invariant = instruction.used().iter().all(|variable| {
                    let definitions: Vec<usize> = analysis.before_definitions[i].iter().filter(|d| d.0 == *variable).map(|d| d.1).collect();
                    definitions.iter().all(|&n| !inside(n)) || (definitions.len() == 1 && inside(definitions[0]) && marked.contains(&(definitions[0] - 1)))
                });
                if invariant {
                    marked.insert(i);
                    mark_order.push(i);
                    changed = true;
                }
            }
            if !changed {
                break;
            }
        }
        let mut moved = Vec::new();
        let mut moved_set = BTreeSet::new();
        for i in mark_order {
            let instruction = &instructions[i];
            let destination = instruction.destination.as_ref().unwrap();
            if indices.iter().filter(|&&j| instructions[j].destination.as_ref() == Some(destination)).count() != 1 || analysis.live.input[natural_loop.header].contains(destination) {
                continue;
            }
            let block = graph.owners[i];
            let dominates_exits = natural_loop.exits.iter().all(|exit| graph.dominators[*exit].contains(&block));
            let dangerous = instruction.kind == "load" || (instruction.kind == "bin" && (instruction.operation == "/" || instruction.operation == "%") && instruction.b.as_ref().and_then(Operand::constant).map_or(true, |n| n == 0));
            let safe = !dangerous && natural_loop.outside.iter().all(|&b| !analysis.live.input[b].contains(destination));
            if !dominates_exits && !safe {
                continue;
            }
            if !instruction.used().iter().all(|variable| analysis.before_definitions[i].iter().filter(|d| d.0 == *variable && inside(d.1)).all(|d| moved_set.contains(&(d.1 - 1)))) {
                continue;
            }
            moved.push(i);
            moved_set.insert(i);
        }
        if !moved.is_empty() {
            let target = optimizations::hoist(function, graph, natural_loop, &moved);
            return (moved.len(), vec![format!("B{}: hoist {} to {}", natural_loop.header + 1, numbers(moved), target)]);
        }
    }
    (0, Vec::new())
}
fn pass(name: &str, function: &mut Function) -> (usize, Vec<String>) {
    let graph = cfg::build(function);
    let analysis = dataflow::analyze(function, &graph);
    match name {
        "constprop" => propagate(function, &graph, &analysis, true),
        "copyprop" => propagate(function, &graph, &analysis, false),
        "cse" => cse(function, &graph, &analysis),
        "dce" => dce(function, &graph, &analysis),
        "licm" => licm(function, &graph, &analysis),
        _ => {
            let records = optimizations::unreachable(function, &graph);
            (records.len(), records)
        }
    }
}
struct Calls {
    edges: Vec<Vec<usize>>,
    reachable: BTreeSet<usize>
}
fn reach(start: usize, edges: &[Vec<usize>]) -> BTreeSet<usize> {
    let mut pending = vec![start];
    let mut seen = BTreeSet::new();
    while let Some(i) = pending.pop() {
        if seen.insert(i) {
            pending.extend(edges[i].iter().copied());
        }
    }
    seen
}
fn call_graph(program: &Program) -> Calls {
    let indices: BTreeMap<String,
    usize> = program.functions.iter().enumerate().map(|(i, f)| (f.name.clone(), i)).collect();
    let edges: Vec<Vec<usize>> = program.functions.iter().map(|f| {
        let mut callees = BTreeSet::new();
        for instruction in f.instructions() {
            if instruction.kind == "call" {
                callees.insert(indices[&instruction.function]);
            }
        }
        callees.into_iter().collect()
    }).collect();
    let reachable = reach(indices["main"], &edges);
    Calls {
        edges,
        reachable
    }
}
fn graph_report(program: &Program, graph: &Calls, label: &str, output: &mut Vec<String>) {
    output.push(format!("== call graph ({}) ==", label));
    for (i, function) in program.functions.iter().enumerate() {
        let recursive = graph.edges[i].iter().any(|&j| reach(j, &graph.edges).contains(&i));
        output.push(format!("{} -> {}{}", function.name, list(graph.edges[i].iter().map(|&j| program.functions[j].name.clone())), if recursive {
            " (recursive)"
        } else {
            ""
        }));
    }
    output.push(format!("unreachable functions: {}", list(program.functions.iter().enumerate().filter(|e| !graph.reachable.contains(&e.0)).map(|e| e.1.name.clone()))));
}
fn definition_list(definitions: &dataflow::Definitions) -> String {
    let mut definitions: Vec<_> = definitions.iter().collect();
    definitions.sort_by(|a, b| a.1.cmp(&b.1).then_with(|| a.0.cmp(&b.0)));
    list(definitions.into_iter().map(|(v, n)| format!("{}:{}", v, n)))
}
fn dominator_tree(block: usize, depth: usize, graph: &Graph, output: &mut Vec<String>) {
    output.push(format!("{}B{}", " ".repeat(depth * 2), block + 1));
    for b in 0..graph.blocks.len() {
        if graph.idom[b] == Some(block) {
            dominator_tree(b, depth + 1, graph, output);
        }
    }
}
fn analysis_report(function: &Function, label: &str, output: &mut Vec<String>) {
    let graph = cfg::build(function);
    let analysis = dataflow::analyze(function, &graph);
    output.push(format!("== {} ({}) ==", function.name, label));
    output.push("code:".into());
    let mut number = 0;
    for line in &function.code {
        match line {
            Line::Label(label) => output.push(format!("{}:", label)),
            Line::Instruction(instruction) => {
                let mut text = format!("  #{} {}", number + 1, instruction.text());
                if graph.reachable.contains(&graph.owners[number]) {
                    let mut used = BTreeSet::new();
                    let mut chains = Vec::new();
                    for variable in instruction.used() {
                        if used.insert(variable.clone()) {
                            let mut definitions: Vec<usize> = analysis.before_definitions[number].iter().filter(|d| d.0 == variable).map(|d| d.1).collect();
                            definitions.sort();
                            chains.push(format!("{}:{}", variable, list(definitions.into_iter().map(|n| n.to_string()))));
                        }
                    }
                    if !chains.is_empty() {
                        text.push_str(&format!(" | {}", chains.join(" ")));
                    }
                }
                output.push(text);
                number += 1;
            }
        }
    }
    output.push(format!("blocks: {}", graph.blocks.len()));
    for (b, block) in graph.blocks.iter().enumerate() {
        output.push(format!("B{} {}-{} labels={} preds={} succs={}", b + 1, block.first + 1, block.last + 1, list(block.labels.iter().cloned()), block_list(block.predecessors.iter().copied()), block_list(block.successors.iter().copied())));
    }
    output.push(format!("unreachable: {}", block_list((0..graph.blocks.len()).filter(|b| !graph.reachable.contains(b)))));
    output.push(format!("order: {}", block_list(graph.order.iter().copied())));
    output.push("dominators:".into());
    for &b in &graph.reachable {
        output.push(format!("B{} idom={} dom={}", b + 1, graph.idom[b].map_or("-".into(), |p| format!("B{}", p + 1)), block_list(graph.dominators[b].iter().copied())));
    }
    output.push("dominator tree:".into());
    dominator_tree(0, 0, &graph, output);
    output.push(format!("loops: {}", graph.loops.len()));
    for natural_loop in &graph.loops {
        output.push(format!("header=B{} latches={} depth={} blocks={} exits={}", natural_loop.header + 1, block_list(natural_loop.latches.iter().copied()), natural_loop.depth, block_list(natural_loop.blocks.iter().copied()), block_list(natural_loop.exits.iter().copied())));
    }
    output.push(format!("reaching definitions: iterations={}", analysis.reaching.iterations));
    for &b in &graph.reachable {
        output.push(format!("B{} in={} out={}", b + 1, definition_list(&analysis.reaching.input[b]), definition_list(&analysis.reaching.output[b])));
    }
    output.push(format!("liveness: iterations={}", analysis.live.iterations));
    for &b in &graph.reachable {
        output.push(format!("B{} in={} out={}", b + 1, list(analysis.live.input[b].iter().cloned()), list(analysis.live.output[b].iter().cloned())));
    }
    output.push(format!("available expressions: iterations={}", analysis.available.iterations));
    for &b in &graph.reachable {
        let strings = |set: &BTreeSet<Expression>| {
            let mut strings: Vec<String> = set.iter().map(Expression::text).collect();
            strings.sort();
            list(strings)
        };
        output.push(format!("B{} in={} out={}", b + 1, strings(&analysis.available.input[b]), strings(&analysis.available.output[b])));
    }
}
fn allocate(function: &Function, registers: usize, output: &mut Vec<String>) -> Function {
    let graph = cfg::build(function);
    let analysis = dataflow::analyze(function, &graph);
    let allocation = regalloc::allocate(function, &graph, &analysis, registers);
    let mut allocated = function.clone();
    let mut moves = 0;
    let rewrite = |name: &str| allocation.registers.get(name).copied().flatten().map_or(name.to_string(), |r| format!("R{}", r));
    for parameter in &mut allocated.parameters {
        *parameter = rewrite(parameter);
    }
    for line in &mut allocated.code {
        if let Line::Instruction(instruction) = line {
            if let Some(destination) = &mut instruction.destination {
                *destination = rewrite(destination);
            }
            for operand in instruction.operands_mut() {
                if let Operand::Variable(name) = operand {
                    *name = rewrite(name);
                }
            }
        }
    }
    allocated.code.retain(|line| {
        if let Line::Instruction(instruction) = line {
            if instruction.kind == "copy" && instruction.destination.as_deref() == instruction.a.as_ref().and_then(Operand::variable) {
                moves += 1;
                return false;
            }
        }
        true
    });
    let spilled: BTreeSet<String> = allocation.registers.iter().filter(|e| e.1.is_none()).map(|e| e.0.clone()).collect();
    let mut spill_uses = 0;
    let mut spill_defs = function.parameters.iter().filter(|p| spilled.contains(*p)).count();
    for instruction in function.instructions() {
        spill_uses += instruction.used().iter().filter(|v| spilled.contains(*v)).count();
        if instruction.destination.as_ref().map_or(false, |d| spilled.contains(d)) {
            spill_defs += 1;
        }
    }
    let pressure = (0..graph.owners.len()).filter(|&i| graph.reachable.contains(&graph.owners[i])).flat_map(|i| [analysis.live_before[i].len(), analysis.live_after[i].len()].to_vec()).max().unwrap_or(0);
    let used: BTreeSet<usize> = allocation.registers.values().copied().flatten().collect();
    output.push(format!("== {} ==", function.name));
    output.push(format!("nodes={} edges={} registers={}", allocation.neighbors.len(), allocation.neighbors.values().map(BTreeSet::len).sum::<usize>() / 2, registers));
    for (node, neighbors) in &allocation.neighbors {
        output.push(format!("{} degree={} cost={} neighbors={}", node, neighbors.len(), allocation.costs[node], list(neighbors.iter().cloned())));
    }
    output.push(format!("simplify: {}", list(allocation.order.iter().cloned())));
    output.push(format!("potential spills: {}", list(allocation.potentials.iter().map(|(name, degree)| format!("{}({}/{})", name, allocation.costs[name], degree)))));
    for (name, assigned) in &allocation.registers {
        output.push(format!("{} -> {}", name, assigned.map_or("spill".into(), |r| format!("R{}", r))));
    }
    output.push(format!("summary: pressure={} used={} spilled={} moves={} spill_uses={} spill_defs={}", pressure, used.len(), spilled.len(), moves, spill_uses, spill_defs));
    output.extend(allocated.text());
    allocated
}
struct Execution<'a> {
    program: &'a Program,
    arrays: BTreeMap<String,
    Vec<i64>>,
    input: &'a [i64],
    position: usize,
    output: Vec<i64>,
    steps: BTreeMap<String,
    usize>,
    calls: BTreeMap<String,
    usize>,
    kinds: BTreeMap<&'static str,
    usize>
}
impl<'a> Execution<'a> {
    fn new(program: &'a Program, input: &'a [i64]) -> Self {
        Self {
            program,
            arrays: program.arrays.iter().map(|(a, n)| (a.clone(), vec![0; *n])).collect(),
            input,
            position: 0,
            output: Vec::new(),
            steps: BTreeMap::new(),
            calls: BTreeMap::new(),
            kinds: KINDS.iter().map(|&k| (k, 0)).collect()
        }
    }
    fn value(operand: &Operand, values: &BTreeMap<String, i64>) -> i64 {
        match operand {
            Operand::Constant(n) => *n,
            Operand::Variable(name) => values[name]
        }
    }
    fn call(&mut self, name: &str, arguments: Vec<i64>) -> Option<i64> {
        *self.calls.entry(name.into()).or_insert(0) += 1;
        let function = self.program.functions.iter().find(|f| f.name == name).unwrap().clone();
        let instructions = function.instructions();
        let labels = tac_parser::labels(&function);
        let mut values: BTreeMap<String,
        i64> = function.parameters.iter().cloned().zip(arguments).collect();
        let mut pushed = Vec::new();
        let mut pc = 0;
        loop {
            let instruction = &instructions[pc];
            *self.steps.entry(name.into()).or_insert(0) += 1;
            *self.kinds.get_mut(instruction.kind).unwrap() += 1;
            let mut next = pc + 1;
            let a = instruction.a.as_ref().map(|a| Self::value(a, &values));
            let b = instruction.b.as_ref().map(|b| Self::value(b, &values));
            let mut result = None;
            match instruction.kind {
                "copy" => result = a,
                "bin" => result = Some(tac_parser::operation(&instruction.operation, a.unwrap(), b.unwrap())),
                "load" => result = Some(self.arrays[&instruction.array][a.unwrap() as usize]),
                "store" => self.arrays.get_mut(&instruction.array).unwrap()[a.unwrap() as usize] = b.unwrap(),
                "goto" => next = labels[&instruction.target],
                "if" => if tac_parser::operation(&instruction.operation, a.unwrap(), b.unwrap()) != 0 {
                    next = labels[&instruction.target];
                },
                "param" => pushed.push(a.unwrap()),
                "call" => {
                    let arguments = pushed.split_off(pushed.len() - instruction.count);
                    result = self.call(&instruction.function, arguments);
                },
                "return" => return a,
                "read" => {
                    result = Some(self.input[self.position]);
                    self.position += 1;
                },
                "print" => self.output.push(a.unwrap()),
                _ => unreachable!()
            }
            if let (Some(destination), Some(value)) = (&instruction.destination, result) {
                values.insert(destination.clone(), value);
            }
            pc = next;
        }
    }
}
fn kind_counts(program: &Program) -> BTreeMap<&'static str, usize> {
    let mut counts: BTreeMap<&str,
    usize> = KINDS.iter().map(|&k| (k, 0)).collect();
    for function in &program.functions {
        for instruction in function.instructions() {
            *counts.get_mut(instruction.kind).unwrap() += 1;
        }
    }
    counts
}
fn write(name: &str, lines: &[String]) {
    fs::create_dir_all("output").unwrap();
    fs::write(format!("output/{}", name), if lines.is_empty() {
        String::new()
    } else {
        lines.join("\n") + "\n"
    }).unwrap();
}
fn main() {
    let original = tac_parser::parse(&fs::read_to_string("input/program.tac").unwrap());
    let parameters = fs::read_to_string("input/params.txt").unwrap();
    let settings: Vec<Vec<&str>> = parameters.lines().map(|l| l.split(' ').collect()).collect();
    let registers = settings[0][1].parse().unwrap();
    let enabled: Vec<&str> = PASSES.iter().copied().filter(|p| settings[1][1..].contains(p)).collect();
    let rounds: usize = settings[2][1].parse().unwrap();
    let mut optimized = original.clone();
    let mut passes = Vec::new();
    let mut totals: BTreeMap<&str,
    usize> = enabled.iter().map(|&p| (p, 0)).collect();
    for function in &mut optimized.functions {
        let before = function.instructions().len();
        passes.push(format!("== {} ==", function.name));
        let mut performed = 0;
        for round in 1..=rounds {
            performed = round;
            let mut changes = Vec::new();
            let mut records = Vec::new();
            let mut changed = false;
            for &name in &enabled {
                let (count, entries) = pass(name, function);
                changed |= count > 0;
                changes.push(format!("{}={}", name, count));
                *totals.get_mut(name).unwrap() += count;
                for entry in entries {
                    records.push(format!("  {} {}", name, entry));
                }
            }
            passes.push(format!("round {}: {}", round, changes.join(" ")));
            passes.extend(records);
            if !changed {
                break;
            }
        }
        passes.push(format!("result: rounds={} instructions={}->{}", performed, before, function.instructions().len()));
    }
    let optimized_graph = call_graph(&optimized);
    let mut analysis = Vec::new();
    graph_report(&original, &call_graph(&original), "original", &mut analysis);
    for function in &original.functions {
        analysis_report(function, "original", &mut analysis);
    }
    graph_report(&optimized, &optimized_graph, "optimized", &mut analysis);
    let removed = if enabled.contains(&"unreachable") {
        optimized.functions.iter().enumerate().filter(|e| !optimized_graph.reachable.contains(&e.0)).map(|e| e.1.name.clone()).collect::<Vec<_>>()
    } else {
        Vec::new()
    };
    optimized.functions.retain(|f| !removed.contains(&f.name));
    for function in &optimized.functions {
        analysis_report(function, "optimized", &mut analysis);
    }
    passes.push("== program ==".into());
    passes.push(format!("removed functions: {}", list(removed)));
    passes.push("== total ==".into());
    passes.push(enabled.iter().map(|p| format!("{}={}", p, totals[p])).collect::<Vec<_>>().join(" "));
    let mut regalloc = Vec::new();
    let allocated = Program {
        arrays: optimized.arrays.clone(),
        functions: optimized.functions.iter().map(|f| allocate(f, registers, &mut regalloc)).collect()
    };
    let input = fs::read_to_string("input/input.txt").unwrap();
    let runs: Vec<Vec<i64>> = input.lines().skip(1).map(|l| l.split_whitespace().skip(1).map(|v| v.parse().unwrap()).collect()).collect();
    let programs = [&original, &optimized, &allocated];
    let labels = ["original", "optimized", "allocated"];
    let mut comparison = Vec::new();
    let mut same = 0;
    let mut total_steps = [0usize; 3];
    let mut profile_steps: Vec<BTreeMap<String,
    usize>> = vec![BTreeMap::new(); 3];
    let mut profile_calls: BTreeMap<String,
    usize> = BTreeMap::new();
    let mut dynamic: Vec<BTreeMap<&str,
    usize>> = (0..3).map(|_| KINDS.iter().map(|&k| (k, 0)).collect()).collect();
    for (i, input) in runs.iter().enumerate() {
        comparison.push(format!("run {}: inputs={}", i + 1, input.len()));
        let mut outputs = Vec::new();
        for p in 0..3 {
            let mut execution = Execution::new(programs[p], input);
            execution.call("main", Vec::new());
            let steps: usize = execution.steps.values().sum();
            let calls: usize = execution.calls.values().sum();
            comparison.push(format!("  {}: steps={} calls={} output={}", labels[p], steps, calls, list(execution.output.iter().map(ToString::to_string))));
            outputs.push(execution.output);
            total_steps[p] += steps;
            for (name, steps) in execution.steps {
                *profile_steps[p].entry(name).or_insert(0) += steps;
            }
            if p == 0 {
                for (name, count) in execution.calls {
                    *profile_calls.entry(name).or_insert(0) += count;
                }
            }
            for (kind, count) in execution.kinds {
                *dynamic[p].get_mut(kind).unwrap() += count;
            }
        }
        let equal = outputs[0] == outputs[1] && outputs[0] == outputs[2];
        if equal {
            same += 1;
        }
        comparison.push(format!("  result: {}", if equal {
            "same"
        } else {
            "different"
        }));
    }
    comparison.push("== profile ==".into());
    for function in &original.functions {
        let name = &function.name;
        comparison.push(format!("{}: calls={} original={} optimized={} allocated={}", name, profile_calls.get(name).unwrap_or(&0), profile_steps[0].get(name).unwrap_or(&0), profile_steps[1].get(name).unwrap_or(&0), profile_steps[2].get(name).unwrap_or(&0)));
    }
    let before = kind_counts(&original);
    let after = kind_counts(&optimized);
    comparison.push("== summary ==".into());
    comparison.push(format!("runs={} same={} different={}", runs.len(), same, runs.len() - same));
    comparison.push(format!("instructions: original={} optimized={}", before.values().sum::<usize>(), after.values().sum::<usize>()));
    comparison.push(format!("kinds: {}", KINDS.iter().map(|k| format!("{}={}->{}", k, before[k], after[k])).collect::<Vec<_>>().join(" ")));
    comparison.push(format!("steps: original={} optimized={} allocated={}", total_steps[0], total_steps[1], total_steps[2]));
    for p in 0..3 {
        comparison.push(format!("dynamic {}: {}", labels[p], KINDS.iter().map(|k| format!("{}={}", k, dynamic[p][k])).collect::<Vec<_>>().join(" ")));
    }
    write("optimized.tac", &optimized.text());
    write("analysis.txt", &analysis);
    write("passes.txt", &passes);
    write("regalloc.txt", &regalloc);
    write("comparison.txt", &comparison);
}
