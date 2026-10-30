use std::collections::BTreeSet;
use crate::tac_parser::{
    Instruction,
    Function,
    Expression,
    Operand
};
use crate::cfg::Graph;
pub type Definitions = BTreeSet<(String, usize)>;
pub type Copies = BTreeSet<(String, String)>;
pub struct Flow<T: Ord> {
    pub input: Vec<BTreeSet<T>>,
    pub output: Vec<BTreeSet<T>>,
    pub iterations: usize
}
pub struct Analysis {
    pub reaching: Flow<(String, usize)>,
    pub live: Flow<String>,
    pub available: Flow<Expression>,
    pub copies: Flow<(String, String)>,
    pub before_definitions: Vec<Definitions>,
    pub before_expressions: Vec<BTreeSet<Expression>>,
    pub before_copies: Vec<Copies>,
    pub live_before: Vec<BTreeSet<String>>,
    pub live_after: Vec<BTreeSet<String>>
}
pub fn reaching_transfer(set: &mut Definitions, instruction: &Instruction, number: usize) {
    if let Some(destination) = &instruction.destination {
        set.retain(|d| d.0 != *destination);
        set.insert((destination.clone(), number));
    }
}
pub fn live_transfer(set: &mut BTreeSet<String>, instruction: &Instruction) {
    if let Some(destination) = &instruction.destination {
        set.remove(destination);
    }
    set.extend(instruction.used());
}
fn expression_transfer(set: &mut BTreeSet<Expression>, instruction: &Instruction) {
    if let Some(expression) = instruction.expression() {
        set.insert(expression);
    }
    if instruction.kind == "store" {
        set.retain(|e| e.kind != "load" || e.operation != instruction.array);
    }
    if instruction.kind == "call" {
        set.retain(|e| e.kind != "load");
    }
    if let Some(destination) = &instruction.destination {
        set.retain(|e| !e.uses(destination));
    }
}
fn copy_transfer(set: &mut Copies, instruction: &Instruction) {
    if let Some(destination) = &instruction.destination {
        set.retain(|e| e.0 != *destination && e.1 != *destination);
        if instruction.kind == "copy" {
            if let Some(Operand::Variable(source)) = &instruction.a {
                if source != destination {
                    set.insert((destination.clone(), source.clone()));
                }
            }
        }
    }
}
fn forward<T: Ord + Clone, F: Fn(&mut BTreeSet<T>, &Instruction, usize)>(function: &Function, graph: &Graph, universe: BTreeSet<T>, parameter_definitions: Option<BTreeSet<T>>, transfer: F) -> Flow<T> {
    let instructions = function.instructions();
    let mut input = vec![BTreeSet::new(); graph.blocks.len()];
    let mut output = vec![universe.clone(); graph.blocks.len()];
    let mut iterations = 0;
    loop {
        iterations += 1;
        let mut changed = false;
        for &b in &graph.order {
            let mut set = if parameter_definitions.is_some() {
                BTreeSet::new()
            } else if b == 0 {
                BTreeSet::new()
            } else {
                universe.clone()
            };
            for &p in &graph.blocks[b].predecessors {
                if graph.reachable.contains(&p) {
                    if parameter_definitions.is_some() {
                        set.extend(output[p].iter().cloned());
                    } else if b != 0 {
                        set = set.intersection(&output[p]).cloned().collect();
                    }
                }
            }
            if b == 0 {
                if let Some(parameters) = &parameter_definitions {
                    set.extend(parameters.iter().cloned());
                }
            }
            input[b] = set.clone();
            for i in graph.blocks[b].first..=graph.blocks[b].last {
                transfer(&mut set, &instructions[i], i + 1);
            }
            if output[b] != set {
                output[b] = set;
                changed = true;
            }
        }
        if !changed {
            break;
        }
    }
    Flow {
        input,
        output,
        iterations
    }
}
pub fn analyze(function: &Function, graph: &Graph) -> Analysis {
    let instructions = function.instructions();
    let mut universe = BTreeSet::new();
    let mut copies = Copies::new();
    for (i, instruction) in instructions.iter().enumerate() {
        if !graph.reachable.contains(&graph.owners[i]) {
            continue;
        }
        if let Some(expression) = instruction.expression() {
            universe.insert(expression);
        }
        if instruction.kind == "copy" {
            if let (Some(destination), Some(Operand::Variable(source))) = (&instruction.destination, &instruction.a) {
                if destination != source {
                    copies.insert((destination.clone(), source.clone()));
                }
            }
        }
    }
    let reaching = forward(function, graph, Definitions::new(), Some(function.parameters.iter().map(|p| (p.clone(), 0)).collect()), reaching_transfer);
    let available = forward(function, graph, universe, None, |s, i, _| expression_transfer(s, i));
    let copies = forward(function, graph, copies, None, |s, i, _| copy_transfer(s, i));
    let mut input = vec![BTreeSet::new(); graph.blocks.len()];
    let mut output = input.clone();
    let mut iterations = 0;
    loop {
        iterations += 1;
        let mut changed = false;
        for &b in &graph.postorder {
            let mut set = BTreeSet::new();
            for &s in &graph.blocks[b].successors {
                set.extend(input[s].iter().cloned());
            }
            output[b] = set.clone();
            for i in (graph.blocks[b].first..=graph.blocks[b].last).rev() {
                live_transfer(&mut set, &instructions[i]);
            }
            if set != input[b] {
                input[b] = set;
                changed = true;
            }
        }
        if !changed {
            break;
        }
    }
    let live = Flow {
        input,
        output,
        iterations
    };
    let mut before_definitions = vec![Definitions::new(); instructions.len()];
    let mut before_expressions = vec![BTreeSet::new(); instructions.len()];
    let mut before_copies = vec![Copies::new(); instructions.len()];
    let mut live_before = vec![BTreeSet::new(); instructions.len()];
    let mut live_after = live_before.clone();
    for &b in &graph.reachable {
        let mut definitions = reaching.input[b].clone();
        let mut expressions = available.input[b].clone();
        let mut cs = copies.input[b].clone();
        for i in graph.blocks[b].first..=graph.blocks[b].last {
            before_definitions[i] = definitions.clone();
            before_expressions[i] = expressions.clone();
            before_copies[i] = cs.clone();
            reaching_transfer(&mut definitions, &instructions[i], i + 1);
            expression_transfer(&mut expressions, &instructions[i]);
            copy_transfer(&mut cs, &instructions[i]);
        }
        let mut lives = live.output[b].clone();
        for i in (graph.blocks[b].first..=graph.blocks[b].last).rev() {
            live_after[i] = lives.clone();
            live_transfer(&mut lives, &instructions[i]);
            live_before[i] = lives.clone();
        }
    }
    Analysis {
        reaching,
        live,
        available,
        copies,
        before_definitions,
        before_expressions,
        before_copies,
        live_before,
        live_after
    }
}
