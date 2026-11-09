use std::collections::{
    BTreeMap,
    BTreeSet
};
use crate::tac_parser::{
    Function,
    Instruction,
    Operand,
    Line
};
use crate::cfg::{
    Graph,
    Loop
};
pub fn fold(instruction: &Instruction) -> Option<Option<Instruction>> {
    if instruction.kind != "bin" && instruction.kind != "if" {
        return None;
    }
    let a = instruction.a.as_ref().unwrap();
    let b = instruction.b.as_ref().unwrap();
    if let (Some(a), Some(b)) = (a.constant(), b.constant()) {
        if (instruction.operation == "/" || instruction.operation == "%") && b == 0 {
            return None;
        }
        let value = crate::tac_parser::operation(&instruction.operation, a, b);
        if instruction.kind == "if" {
            if value == 0 {
                return Some(None);
            }
            let mut jump = Instruction::new("goto");
            jump.target = instruction.target.clone();
            return Some(Some(jump));
        }
        if !(-2147483648..=2147483647).contains(&value) {
            return None;
        }
        return Some(Some(Instruction::copy(instruction.destination.clone().unwrap(), Operand::Constant(value))));
    }
    if instruction.kind != "bin" {
        return None;
    }
    let value = match instruction.operation.as_str() {
        "+" if a.constant() == Some(0) => Some(b.clone()),
        "+" | "-" if b.constant() == Some(0) => Some(a.clone()),
        "*" if a.constant() == Some(1) => Some(b.clone()),
        "*" | "/" if b.constant() == Some(1) => Some(a.clone()),
        "*" if a.constant() == Some(0) || b.constant() == Some(0) => Some(Operand::Constant(0)),
        _ => None
    };
    value.map(|value| Some(Instruction::copy(instruction.destination.clone().unwrap(), value)))
}
pub fn rewrite(function: &mut Function, replacements: &BTreeMap<usize, Vec<Instruction>>) {
    let mut code = Vec::new();
    let mut number = 0;
    for line in &function.code {
        match line {
            Line::Label(_) => code.push(line.clone()),
            Line::Instruction(instruction) => {
                if let Some(replacement) = replacements.get(&number) {
                    code.extend(replacement.iter().cloned().map(Line::Instruction));
                } else {
                    code.push(Line::Instruction(instruction.clone()));
                }
                number += 1;
            }
        }
    }
    function.code = code;
}
pub fn temporary(function: &mut Function) -> String {
    function.temporary += 1;
    format!("_t{}", function.temporary)
}
pub fn cse_rewrite(instruction: &Instruction, temporary: &str, source: bool) -> Vec<Instruction> {
    let destination = instruction.destination.clone().unwrap();
    let copy = Instruction::copy(destination, Operand::Variable(temporary.into()));
    if source {
        let mut calculation = instruction.clone();
        calculation.destination = Some(temporary.into());
        vec![calculation, copy]
    } else {
        vec![copy]
    }
}
pub fn hoist(function: &mut Function, graph: &Graph, natural_loop: &Loop, moved: &[usize]) -> String {
    let header = natural_loop.header;
    let outside: Vec<usize> = graph.blocks[header].predecessors.iter().copied().filter(|p| !natural_loop.blocks.contains(p)).collect();
    let preheader = if header != 0 && outside.len() == 1 && graph.blocks[outside[0]].successors == vec![header] {
        Some(outside[0])
    } else {
        None
    };
    let mut positions = Vec::new();
    for (i, line) in function.code.iter().enumerate() {
        if matches!(line, Line::Instruction(_)) {
            positions.push(i);
        }
    }
    let instructions = function.instructions();
    let moving: BTreeSet<usize> = moved.iter().copied().collect();
    let mut insertion = Vec::new();
    let position;
    let target;
    if let Some(preheader) = preheader {
        let last = graph.blocks[preheader].last;
        position = positions[last] + if instructions[last].kind == "goto" || instructions[last].kind == "if" {
            0
        } else {
            1
        };
        target = format!("B{}", preheader + 1);
    } else {
        function.preheader += 1;
        let label = format!("_p{}", function.preheader);
        target = format!("new {}", label);
        insertion.push(Line::Label(label.clone()));
        let mut first = positions[graph.blocks[header].first];
        while first > 0 && matches!(function.code[first - 1], Line::Label(_)) {
            first -= 1;
        }
        position = first;
        for &p in &outside {
            let index = graph.blocks[p].last;
            if (instructions[index].kind == "goto" || instructions[index].kind == "if") && graph.blocks[header].labels.contains(&instructions[index].target) {
                if let Line::Instruction(instruction) = &mut function.code[positions[index]] {
                    instruction.target = label.clone();
                }
            }
        }
    }
    insertion.extend(moved.iter().map(|&i| Line::Instruction(instructions[i].clone())));
    let mut code = Vec::new();
    let mut number = 0;
    for (i, line) in function.code.iter().enumerate() {
        if i == position {
            code.extend(insertion.iter().cloned());
        }
        match line {
            Line::Label(_) => code.push(line.clone()),
            Line::Instruction(_) => {
                if !moving.contains(&number) {
                    code.push(line.clone());
                }
                number += 1;
            }
        }
    }
    if position == function.code.len() {
        code.extend(insertion);
    }
    function.code = code;
    target
}
pub fn unreachable(function: &mut Function, graph: &Graph) -> Vec<String> {
    let mut records = Vec::new();
    for b in 0..graph.blocks.len() {
        if !graph.reachable.contains(&b) {
            records.push(format!("remove block B{}", b + 1));
        }
    }
    let mut code = Vec::new();
    let mut number = 0;
    let mut labels = Vec::new();
    for line in &function.code {
        match line {
            Line::Label(_) => labels.push(line.clone()),
            Line::Instruction(_) => {
                if graph.reachable.contains(&graph.owners[number]) {
                    code.append(&mut labels);
                    code.push(line.clone());
                } else {
                    labels.clear();
                }
                number += 1;
            }
        }
    }
    let mut delete = BTreeSet::new();
    let mut number = 0;
    for (i, line) in code.iter().enumerate() {
        if let Line::Instruction(instruction) = line {
            number += 1;
            if instruction.kind == "goto" || instruction.kind == "if" {
                let following: Vec<String> = code[i + 1..].iter().take_while(|l| matches!(l, Line::Label(_))).filter_map(|l| if let Line::Label(label) = l {
                    Some(label.clone())
                } else {
                    None
                }).collect();
                if following.contains(&instruction.target) {
                    delete.insert(i);
                    records.push(format!("remove jump #{}", number));
                }
            }
        }
    }
    code = code.into_iter().enumerate().filter_map(|(i, l)| if delete.contains(&i) {
        None
    } else {
        Some(l)
    }).collect();
    let targets: BTreeSet<String> = code.iter().filter_map(|l| if let Line::Instruction(instruction) = l {
        if instruction.kind == "goto" || instruction.kind == "if" {
            Some(instruction.target.clone())
        } else {
            None
        }
    } else {
        None
    }).collect();
    code.retain(|line| if let Line::Label(label) = line {
        if !targets.contains(label) {
            records.push(format!("remove label {}", label));
            false
        } else {
            true
        }
    } else {
        true
    });
    function.code = code;
    records
}
