mod lexer;
mod parser;
mod semantic;
mod codegen;
mod vm;
use std::collections::{
    BTreeMap,
    BTreeSet,
    VecDeque
};
use std::fs;
use lexer::Position;
use parser::{
    Program,
    Top,
    Type,
    Statement,
    StmtKind,
    Expression,
    ExprKind
};
use semantic::{
    Analysis,
    SymbolKind
};
use codegen::{
    Instruction,
    Unit
};
const RULES: [&str;
7] = ["const-jump", "not-compare", "not-jump", "invert-branch", "thread", "jump-next", "unreachable"];
fn reachable(start: usize, calls: &BTreeMap<usize, BTreeSet<usize>>) -> BTreeSet<usize> {
    let mut result = BTreeSet::new();
    let mut pending = vec![start];
    while let Some(id) = pending.pop() {
        if result.insert(id) {
            if let Some(next) = calls.get(&id) {
                pending.extend(next.iter().copied());
            }
        }
    }
    result
}
fn unreachable_warnings(statement: &Statement, warnings: &mut Vec<(Position, String)>) {
    match &statement.kind {
        StmtKind::Block(statements, _) => {
            if let Some(index) = statements.iter().position(|s| !semantic::completes(s)) {
                if index + 1 < statements.len() {
                    warnings.push((statements[index + 1].position, "unreachable statement".into()));
                }
            }
            for statement in statements {
                unreachable_warnings(statement, warnings);
            }
        },
        StmtKind::If(_, yes, no) => {
            unreachable_warnings(yes, warnings);
            if let Some(no) = no {
                unreachable_warnings(no, warnings);
            }
        },
        StmtKind::While(_, body) => unreachable_warnings(body, warnings),
        StmtKind::For(init, _, update, body) => {
            if let Some(init) = init {
                unreachable_warnings(init, warnings);
            }
            if let Some(update) = update {
                unreachable_warnings(update, warnings);
            }
            unreachable_warnings(body, warnings);
        },
        _ => ()
    }
}
fn warnings(program: &Program, analysis: &Analysis, live: &BTreeSet<usize>) -> Vec<(Position, String)> {
    let mut warnings = Vec::new();
    for (id, symbol) in analysis.symbols.iter().enumerate() {
        match &symbol.kind {
            SymbolKind::Function(_) if !live.contains(&id) => warnings.push((symbol.position, format!("function '{}' is never called", symbol.name))),
            SymbolKind::Function(_) => (),
            SymbolKind::Parameter if symbol.reads == 0 => warnings.push((symbol.position, format!("unused parameter '{}'", symbol.name))),
            _ if symbol.reads == 0 => warnings.push((symbol.position, format!("unused variable '{}'", symbol.name))),
            _ => ()
        }
    }
    for top in &program.declarations {
        if let Top::Function(function) = top {
            unreachable_warnings(&function.body, &mut warnings);
        }
    }
    warnings.sort_by_key(|w| w.0);
    warnings
}
fn literal(expression: &Expression) -> Option<(i64, Type)> {
    if let ExprKind::Literal(value, ty) = expression.kind {
        Some((value, ty))
    } else {
        None
    }
}
fn integer(value: i64) -> bool {
    (-2147483648..=2147483647).contains(&value)
}
fn fold_expression(expression: &mut Expression, folds: &mut usize) {
    let mut replacement = None;
    match &mut expression.kind {
        ExprKind::Array(_, index) => fold_expression(index, folds),
        ExprKind::Call(_, arguments) => for argument in arguments {
            fold_expression(argument, folds);
        },
        ExprKind::Unary(operator, child) => {
            fold_expression(child, folds);
            if let Some((value, ty)) = literal(child) {
                let value = if operator == "!" {
                    Some(if value == 0 {
                        1
                    } else {
                        0
                    })
                } else if integer(-value) {
                    Some(-value)
                } else {
                    None
                };
                if let Some(value) = value {
                    replacement = Some(Expression {
                        position: expression.position,
                        kind: ExprKind::Literal(value, ty),
                        symbol: None,
                        ty: Some(ty)
                    });
                }
            }
        },
        ExprKind::Binary(operator, left, right) => {
            fold_expression(left, folds);
            fold_expression(right, folds);
            let a = literal(left);
            let b = literal(right);
            let op = operator.as_str();
            if let (Some((a, _)), Some((b, _))) = (a, b) {
                let value = match op {
                    "+" => Some(a + b),
                    "-" => Some(a - b),
                    "*" => Some(a * b),
                    "/" if b != 0 => Some(a / b),
                    "%" if b != 0 => Some(a % b),
                    "<" => Some(if a < b {
                        1
                    } else {
                        0
                    }),
                    "<=" => Some(if a <= b {
                        1
                    } else {
                        0
                    }),
                    ">" => Some(if a > b {
                        1
                    } else {
                        0
                    }),
                    ">=" => Some(if a >= b {
                        1
                    } else {
                        0
                    }),
                    "==" => Some(if a == b {
                        1
                    } else {
                        0
                    }),
                    "!=" => Some(if a != b {
                        1
                    } else {
                        0
                    }),
                    "&&" => Some(if a != 0 && b != 0 {
                        1
                    } else {
                        0
                    }),
                    "||" => Some(if a != 0 || b != 0 {
                        1
                    } else {
                        0
                    }),
                    _ => None
                };
                if let Some(value) = value.filter(|&value| integer(value)) {
                    let ty = expression.ty.unwrap();
                    replacement = Some(Expression {
                        position: expression.position,
                        kind: ExprKind::Literal(value, ty),
                        symbol: None,
                        ty: Some(ty)
                    });
                }
            }
            if replacement.is_none() {
                if (op == "&&" && a == Some((0, Type::Bool))) || (op == "||" && a == Some((1, Type::Bool))) {
                    replacement = Some(Expression {
                        position: expression.position,
                        kind: ExprKind::Literal(if op == "&&" {
                            0
                        } else {
                            1
                        }, Type::Bool),
                        symbol: None,
                        ty: Some(Type::Bool)
                    });
                } else if (op == "&&" && a == Some((1, Type::Bool))) || (op == "||" && a == Some((0, Type::Bool))) || (op == "+" && a == Some((0, Type::Int))) || (op == "*" && a == Some((1, Type::Int))) {
                    replacement = Some((**right).clone());
                } else if ((op == "+" || op == "-") && b == Some((0, Type::Int))) || ((op == "*" || op == "/") && b == Some((1, Type::Int))) || (op == "&&" && b == Some((1, Type::Bool))) || (op == "||" && b == Some((0, Type::Bool))) {
                    replacement = Some((**left).clone());
                }
            }
        },
        _ => ()
    }
    if let Some(replacement) = replacement {
        *expression = replacement;
        *folds += 1;
    }
}
fn fold_statement(statement: &mut Statement, folds: &mut usize) {
    let mut replacement = None;
    match &mut statement.kind {
        StmtKind::Block(statements, _) => for statement in statements {
            fold_statement(statement, folds);
        },
        StmtKind::Declaration(declaration) => if let Some(value) = &mut declaration.initializer {
            fold_expression(value, folds);
        },
        StmtKind::Assignment(_, index, value, _) => {
            if let Some(index) = index {
                fold_expression(index, folds);
            }
            fold_expression(value, folds);
        },
        StmtKind::Call(expression) => fold_expression(expression, folds),
        StmtKind::Print(values) => for value in values {
            fold_expression(value, folds);
        },
        StmtKind::Return(value) => if let Some(value) = value {
            fold_expression(value, folds);
        },
        StmtKind::If(condition, yes, no) => {
            fold_expression(condition, folds);
            if let Some((value, Type::Bool)) = literal(condition) {
                if value != 0 {
                    fold_statement(yes, folds);
                    replacement = Some((**yes).clone());
                }
                else if let Some(no) = no {
                    fold_statement(no, folds);
                    replacement = Some((**no).clone());
                }
                else {
                    replacement = Some(Statement {
                        position: statement.position,
                        kind: StmtKind::Empty
                    });
                }
            } else {
                fold_statement(yes, folds);
                if let Some(no) = no {
                    fold_statement(no, folds);
                }
            }
        },
        StmtKind::While(condition, body) => {
            fold_expression(condition, folds);
            if literal(condition) == Some((0, Type::Bool)) {
                replacement = Some(Statement {
                    position: statement.position,
                    kind: StmtKind::Empty
                });
            }
            else {
                fold_statement(body, folds);
            }
        },
        StmtKind::For(init, condition, update, body) => {
            if let Some(init) = init {
                fold_statement(init, folds);
            }
            if let Some(condition) = condition {
                fold_expression(condition, folds);
            }
            if let Some(update) = update {
                fold_statement(update, folds);
            }
            fold_statement(body, folds);
        },
        _ => ()
    }
    if let Some(replacement) = replacement {
        *statement = replacement;
        *folds += 1;
    }
}
fn jumps(op: &str, value: i64) -> bool {
    (op == "JUMPF" && value == 0) || (op == "JUMPT" && value != 0)
}
fn inverse(op: &str) -> &'static str {
    if op == "JUMPF" {
        "JUMPT"
    } else {
        "JUMPF"
    }
}
fn negation(op: &str) -> Option<&'static str> {
    match op {
        "LT" => Some("GE"),
        "LE" => Some("GT"),
        "GT" => Some("LE"),
        "GE" => Some("LT"),
        "EQ" => Some("NE"),
        "NE" => Some("EQ"),
        _ => None
    }
}
fn delete(code: &mut Vec<Instruction>, index: usize) {
    code.remove(index);
    for instruction in code {
        if instruction.jump() && instruction.operands[0] > index as i64 {
            instruction.operands[0] -= 1;
        }
    }
}
fn peephole(code: &mut Vec<Instruction>, counts: &mut [usize;
7]) {
    loop {
        let targets: BTreeSet<usize> = code.iter().filter(|i| i.jump()).map(|i| i.operands[0] as usize).collect();
        let mut changed = false;
        for index in 0..code.len() {
            let a = code[index].clone();
            let b = code.get(index + 1).cloned();
            let free = b.is_some() && !targets.contains(&(index + 1));
            let mut applied = None;
            if free {
                let b = b.as_ref().unwrap();
                if a.op == "PUSH" && b.conditional() {
                    if jumps(&b.op, a.operands[0]) {
                        code[index] = Instruction::new("JUMP", b.operands.clone(), b.position);
                        delete(code, index + 1);
                    }
                    else {
                        delete(code, index + 1);
                        delete(code, index);
                    }
                    applied = Some(0);
                } else if b.op == "NOT" && negation(&a.op).is_some() {
                    code[index].op = negation(&a.op).unwrap().into();
                    delete(code, index + 1);
                    applied = Some(1);
                } else if a.op == "NOT" && b.conditional() {
                    code[index] = Instruction::new(inverse(&b.op), b.operands.clone(), b.position);
                    delete(code, index + 1);
                    applied = Some(2);
                } else if a.conditional() && a.operands[0] == (index + 2) as i64 && b.op == "JUMP" {
                    code[index] = Instruction::new(inverse(&a.op), b.operands.clone(), a.position);
                    delete(code, index + 1);
                    applied = Some(3);
                }
            }
            if applied.is_none() && a.jump() {
                let target = a.operands[0] as usize;
                if target < code.len() {
                    let t = &code[target];
                    let mut new_target = None;
                    if t.op == "JUMP" {
                        new_target = Some(t.operands[0]);
                    }
                    else if t.op == "PUSH" && target + 1 < code.len() && code[target + 1].conditional() {
                        let branch = &code[target + 1];
                        new_target = Some(if jumps(&branch.op, t.operands[0]) {
                            branch.operands[0]
                        } else {
                            (target + 2) as i64
                        });
                    }
                    if let Some(new_target) = new_target.filter(|&new_target| new_target != target as i64) {
                        code[index].operands[0] = new_target;
                        applied = Some(4);
                    }
                }
            }
            if applied.is_none() && a.jump() && a.operands[0] == (index + 1) as i64 {
                if a.op == "JUMP" {
                    delete(code, index);
                } else {
                    code[index] = Instruction::new("POP", vec![], a.position);
                }
                applied = Some(5);
            }
            if applied.is_none() && a.transfer() && free {
                delete(code, index + 1);
                applied = Some(6);
            }
            if let Some(rule) = applied {
                counts[rule] += 1;
                changed = true;
                break;
            }
        }
        if !changed {
            break;
        }
    }
}
struct Block {
    first: usize,
    last: usize,
    successors: Vec<usize>
}
fn successors(code: &[Instruction], index: usize) -> Vec<usize> {
    let instruction = &code[index];
    let mut next = Vec::new();
    if !instruction.transfer() && index + 1 < code.len() {
        next.push(index + 1);
    }
    if instruction.jump() {
        let target = instruction.operands[0] as usize;
        if target < code.len() && !next.contains(&target) {
            next.push(target);
        }
    }
    next
}
fn blocks(code: &[Instruction]) -> Vec<Block> {
    let mut leaders = BTreeSet::new();
    leaders.insert(0);
    for (index, instruction) in code.iter().enumerate() {
        if instruction.jump() {
            let target = instruction.operands[0] as usize;
            if target < code.len() {
                leaders.insert(target);
            }
        }
        if (instruction.jump() || instruction.transfer()) && index + 1 < code.len() {
            leaders.insert(index + 1);
        }
    }
    let leaders: Vec<usize> = leaders.into_iter().collect();
    let mut result = Vec::new();
    for (i, &first) in leaders.iter().enumerate() {
        let last = if i + 1 < leaders.len() {
            leaders[i + 1] - 1
        } else {
            code.len() - 1
        };
        let next = successors(code, last).into_iter().map(|n| leaders.binary_search(&n).unwrap()).collect();
        result.push(Block {
            first,
            last,
            successors: next
        });
    }
    result
}
fn stack_depth(code: &[Instruction], analysis: &Analysis) -> i64 {
    let mut depths = vec![None; code.len()];
    depths[0] = Some(0i64);
    let mut queue = VecDeque::from(vec![0usize]);
    let mut maximum = 0;
    while let Some(index) = queue.pop_front() {
        let instruction = &code[index];
        let effect = match instruction.op.as_str() {
            "PUSH" | "LOADG" | "LOADL" | "READ" => 1,
            "POP" | "STOREG" | "STOREL" | "JUMPF" | "JUMPT" | "RETV" | "ADD" | "SUB" | "MUL" | "DIV" | "MOD" | "LT" | "LE" | "GT" | "GE" | "EQ" | "NE" => -1,
            "STOREA" => -2,
            "PRINT" => -instruction.operands[0],
            "CALL" => -instruction.operands[1] + if analysis.symbols[instruction.callee.unwrap()].ty == Type::Void {
                0
            } else {
                1
            },
            _ => 0
        };
        let after = depths[index].unwrap() + effect;
        maximum = maximum.max(after);
        for next in successors(code, index) {
            if depths[next].is_none() {
                depths[next] = Some(after);
                queue.push_back(next);
            }
        }
    }
    maximum
}
fn recursive(id: usize, analysis: &Analysis) -> bool {
    analysis.calls.get(&id).map_or(false, |next| next.iter().any(|&next| reachable(next, &analysis.calls).contains(&id)))
}
fn display(lines: &[(usize, String)], position: Position, output: &mut Vec<String>) {
    let line = &lines.iter().find(|line| line.0 == position.line).unwrap().1;
    output.push(format!("  {}", line));
    output.push(format!("{}^", " ".repeat(position.column + 1)));
}
fn join_numbers<T: ToString>(values: impl IntoIterator<Item = T>, empty: &str) -> String {
    let values: Vec<String> = values.into_iter().map(|v| v.to_string()).collect();
    if values.is_empty() {
        empty.into()
    } else {
        values.join(" ")
    }
}
fn disassemble(units: &[Unit], code: &[Instruction], starts: &[usize], label: &str, output: &mut Vec<String>) {
    output.push(format!("{} peephole: {} instructions", label, code.len()));
    for (index, unit) in units.iter().enumerate() {
        output.push(format!("{}:", unit.name));
        for offset in 0..unit.code.len() {
            let pc = starts[index] + offset;
            output.push(format!("{:5}  {}", pc, code[pc].spelling()));
        }
    }
}
fn listing(analysis: &Analysis, generated: &codegen::Generated, before: &[Unit], after: &[Unit], output: &mut Vec<String>) {
    let (old_code, old_starts, _) = codegen::arrange(before);
    let (code, starts, _) = codegen::arrange(after);
    if analysis.globals.is_empty() {
        output.push("globals: none".into());
    }
    else {
        output.push("globals:".into());
        for &id in &analysis.globals {
            let symbol = &analysis.symbols[id];
            let ty = if let SymbolKind::Global(Some(n)) = symbol.kind {
                format!("int[{}]", n)
            } else {
                symbol.ty.text().into()
            };
            output.push(format!("  {} {} {}", generated.addresses[&id], symbol.name, ty));
        }
    }
    output.push("functions:".into());
    for (index, unit) in after.iter().enumerate() {
        let signature = unit.function.map_or(String::new(), |id| {
            let symbol = &analysis.symbols[id];
            let parameters = if let SymbolKind::Function(parameters) = &symbol.kind {
                parameters.iter().map(|ty| ty.text()).collect::<Vec<_>>().join(",")
            } else {
                unreachable!()
            };
            format!(" {}({})", symbol.ty.text(), parameters)
        });
        let callees = unit.function.map_or("main".into(), |id| {
            let mut names: Vec<String> = analysis.calls.get(&id).into_iter().flat_map(|set| set.iter()).map(|&id| analysis.symbols[id].name.clone()).collect();
            names.sort();
            if names.is_empty() {
                "-".into()
            } else {
                names.join(",")
            }
        });
        output.push(format!("  {}{} address={}->{} size={}->{} slots={} stack={} blocks={} calls={}{}", unit.name, signature, old_starts[index], starts[index], before[index].code.len(), unit.code.len(), unit.slots.len(), stack_depth(&unit.code, analysis), blocks(&unit.code).len(), callees, if unit.function.map_or(false, |id| recursive(id, analysis)) {
            " recursive"
        } else {
            ""
        }));
        for (slot, &id) in unit.slots.iter().enumerate() {
            let symbol = &analysis.symbols[id];
            output.push(format!("    slot {} {} {}", slot, symbol.name, symbol.ty.text()));
        }
    }
    output.push("references:".into());
    for &id in analysis.globals.iter().chain(analysis.functions.iter()) {
        let symbol = &analysis.symbols[id];
        let lines: BTreeSet<usize> = symbol.references.iter().map(|p| p.line).collect();
        output.push(format!("  {} defined {} used {}", symbol.name, symbol.position.line, join_numbers(lines, "-")));
    }
    disassemble(before, &old_code, &old_starts, "before", output);
    disassemble(after, &code, &starts, "after", output);
    output.push("control flow:".into());
    for (index, unit) in after.iter().enumerate() {
        output.push(format!("  {}", unit.name));
        for (number, block) in blocks(&unit.code).iter().enumerate() {
            let next = if block.successors.is_empty() {
                String::new()
            } else {
                format!(" -> {}", block.successors.iter().map(|s| format!("B{}", s)).collect::<Vec<_>>().join(" "))
            };
            output.push(format!("    B{} {}-{}{}", number, starts[index] + block.first, starts[index] + block.last, next));
        }
    }
}
fn statistics(units: &[Unit], code: &[Instruction], owners: &[usize], run: &vm::Run, output: &mut Vec<String>) {
    let mut opcodes: BTreeMap<String,
    usize> = BTreeMap::new();
    let mut lines: BTreeMap<usize,
    usize> = BTreeMap::new();
    let mut executed = vec![0; units.len()];
    for (pc, instruction) in code.iter().enumerate() {
        *opcodes.entry(instruction.op.clone()).or_insert(0) += run.counts[pc];
        *lines.entry(instruction.position.line).or_insert(0) += run.counts[pc];
        executed[owners[pc]] += run.counts[pc];
    }
    output.push("opcodes:".into());
    let mut opcodes: Vec<_> = opcodes.into_iter().filter(|e| e.1 > 0).collect();
    opcodes.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
    for (name, count) in opcodes {
        output.push(format!("  {} {}", name, count));
    }
    output.push("functions:".into());
    let mut functions: Vec<usize> = (1..units.len()).collect();
    functions.sort_by(|&a, &b| executed[b].cmp(&executed[a]).then_with(|| units[a].name.cmp(&units[b].name)));
    for index in functions {
        output.push(format!("  {} calls={} executed={}", units[index].name, run.calls[index], executed[index]));
    }
    output.push("calls:".into());
    let mut calls: Vec<_> = run.pairs.iter().collect();
    calls.sort_by(|a, b| b.1.cmp(a.1).then_with(|| units[(a.0).0].name.cmp(&units[(b.0).0].name)).then_with(|| units[(a.0).1].name.cmp(&units[(b.0).1].name)));
    for (&(caller, callee), count) in calls {
        output.push(format!("  {} -> {} {}", units[caller].name, units[callee].name, count));
    }
    output.push("hot lines:".into());
    let mut hot_lines: Vec<_> = lines.iter().filter(|e| *e.1 > 0).collect();
    hot_lines.sort_by(|a, b| b.1.cmp(a.1).then_with(|| a.0.cmp(b.0)));
    for (line, count) in hot_lines.iter().take(5) {
        output.push(format!("  line {}: {}", line, count));
    }
    output.push(format!("coverage: {} of {} lines", hot_lines.len(), lines.len()));
    output.push(format!("not executed: {}", join_numbers(lines.iter().filter(|e| *e.1 == 0).map(|e| *e.0), "none")));
    output.push("hot spots:".into());
    let mut spots: Vec<usize> = (0..code.len()).filter(|&i| run.counts[i] > 0).collect();
    spots.sort_by(|&a, &b| run.counts[b].cmp(&run.counts[a]).then_with(|| a.cmp(&b)));
    for pc in spots.into_iter().take(5) {
        output.push(format!("  pc={} count={} {}", pc, run.counts[pc], code[pc].spelling()));
    }
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
    let source = fs::read_to_string("input/program.src").unwrap();
    let input = fs::read_to_string("input/input.txt").unwrap();
    let mut programs: Vec<(String, Vec<(usize, String)>)> = Vec::new();
    for (i, line) in source.lines().enumerate() {
        if let Some(name) = line.strip_prefix("#program ") {
            programs.push((name.into(), Vec::new()));
        }
        else {
            programs.last_mut().unwrap().1.push((i + 1, line.into()));
        }
    }
    let mut inputs: BTreeMap<String,
    Vec<i64>> = BTreeMap::new();
    let mut name = String::new();
    for line in input.lines() {
        if let Some(next) = line.strip_prefix("#input ") {
            name = next.into();
            inputs.insert(name.clone(), Vec::new());
        }
        else {
            inputs.get_mut(&name).unwrap().extend(line.split_whitespace().map(|v| v.parse::<i64>().unwrap()));
        }
    }
    let mut listing_output = Vec::new();
    let mut printed_output = Vec::new();
    let mut diagnostics = Vec::new();
    let mut stats = Vec::new();
    let mut rows = vec![vec!["program".into(), "status".into(), "code".into(), "executed".into(), "output".into()]];
    let mut compile_errors: BTreeMap<&str,
    usize> = [("lexical", 0), ("syntax", 0), ("semantic", 0)].iter().copied().collect();
    let mut compiled = 0;
    let mut runtime_errors = 0;
    let mut total_folds = 0;
    let mut total_rules = [0usize; 7];
    let mut total_executed = 0;
    for (name, lines) in &programs {
        let heading = format!("== program {} ==", name);
        listing_output.push(heading.clone());
        printed_output.push(heading.clone());
        diagnostics.push(heading.clone());
        stats.push(heading);
        let result = lexer::lex(lines).and_then(parser::parse).and_then(|mut program| semantic::analyze(&mut program).map(|analysis| (program, analysis)));
        let (mut program, analysis) = match result {
            Ok(result) => result,
            Err(error) => {
                *compile_errors.get_mut(error.kind).unwrap() += 1;
                listing_output.push("not compiled".into());
                stats.push("not compiled".into());
                diagnostics.push(format!("{} error {}: {}", error.kind, error.position.text(), error.message));
                display(lines, error.position, &mut diagnostics);
                diagnostics.push("status: compile error".into());
                rows.push(vec![name.clone(), format!("{} error", error.kind), "-".into(), "-".into(), "-".into()]);
                continue;
            }
        };
        compiled += 1;
        let live = reachable(analysis.main, &analysis.calls);
        for (position, message) in warnings(&program, &analysis, &live) {
            diagnostics.push(format!("warning {}: {}", position.text(), message));
        }
        let mut folds = 0;
        for declaration in &mut program.declarations {
            match declaration {
                Top::Global(declaration) => if let Some(value) = &mut declaration.initializer {
                    fold_expression(value, &mut folds);
                },
                Top::Function(function) if live.contains(&function.symbol.unwrap()) => fold_statement(&mut function.body, &mut folds),
                _ => ()
            }
        }
        let generated = codegen::generate(&program, &analysis, &live);
        let before = &generated.units;
        let mut after = before.clone();
        let mut rules = [0usize; 7];
        for unit in &mut after {
            peephole(&mut unit.code, &mut rules);
        }
        listing(&analysis, &generated, before, &after, &mut listing_output);
        let (code, starts, owners) = codegen::arrange(&after);
        let (old_code, old_starts, old_owners) = codegen::arrange(before);
        let values = inputs.get(name).map(Vec::as_slice).unwrap_or(&[]);
        let run = vm::run(&code, &owners, &starts, generated.global_size, values);
        let comparison = vm::run(&old_code, &old_owners, &old_starts, generated.global_size, values);
        printed_output.extend(run.output.iter().cloned());
        if let Some(error) = &run.error {
            runtime_errors += 1;
            let instruction = &code[error.pc];
            diagnostics.push(format!("runtime error {}: {} in {}", instruction.position.text(), error.message, after[owners[error.pc]].name));
            display(lines, instruction.position, &mut diagnostics);
            let callers: Vec<usize> = error.frames.iter().skip(1).rev().map(|frame| frame.return_address - 1).collect();
            for &pc in callers.iter().take(5) {
                diagnostics.push(format!("  called from {} at {}", after[owners[pc]].name, code[pc].position.text()));
            }
            if callers.len() > 5 {
                diagnostics.push(format!("  ... {} more", callers.len() - 5));
            }
            diagnostics.push("status: runtime error".into());
        } else {
            diagnostics.push("status: ok".into());
        }
        let same = run.output == comparison.output && run.error.as_ref().map(|e| &e.message) == comparison.error.as_ref().map(|e| &e.message);
        let rule_total: usize = rules.iter().sum();
        stats.push(format!("code: {} -> {}", old_code.len(), code.len()));
        stats.push(format!("folds: {}", folds));
        stats.push(format!("peephole: {}", rule_total));
        for i in 0..7 {
            stats.push(format!("  {} {}", RULES[i], rules[i]));
            total_rules[i] += rules[i];
        }
        stats.push(format!("executed: {}", run.executed));
        stats.push(format!("executed before peephole: {}", comparison.executed));
        stats.push(format!("behaviour: {}", if same {
            "same"
        } else {
            "different"
        }));
        stats.push(format!("max call depth: {}", run.max_depth));
        stats.push(format!("max stack: {}", run.max_stack));
        statistics(&after, &code, &owners, &run, &mut stats);
        total_folds += folds;
        total_executed += run.executed;
        rows.push(vec![name.clone(), if run.error.is_some() {
            "runtime error".into()
        } else {
            "ok".into()
        }, code.len().to_string(), run.executed.to_string(), run.output.len().to_string()]);
    }
    stats.push("== summary ==".into());
    stats.push(format!("programs: {}", programs.len()));
    stats.push(format!("compiled: {}", compiled));
    stats.push(format!("compile errors: lexical {} syntax {} semantic {}", compile_errors["lexical"], compile_errors["syntax"], compile_errors["semantic"]));
    stats.push(format!("runtime errors: {}", runtime_errors));
    stats.push(format!("folds: {}", total_folds));
    stats.push(format!("peephole: {}", total_rules.iter().sum::<usize>()));
    for i in 0..7 {
        stats.push(format!("  {} {}", RULES[i], total_rules[i]));
    }
    stats.push(format!("executed: {}", total_executed));
    let widths: Vec<usize> = (0..5).map(|i| rows.iter().map(|row| row[i].len()).max().unwrap()).collect();
    for row in rows {
        let cells: Vec<String> = row.iter().enumerate().map(|(i, value)| if i < 2 {
            format!("{:<width$}", value, width = widths[i])
        } else {
            format!("{:>width$}", value, width = widths[i])
        }).collect();
        stats.push(format!("  {}", cells.join("  ")));
    }
    write("listing.txt", &listing_output);
    write("output.txt", &printed_output);
    write("diagnostics.txt", &diagnostics);
    write("stats.txt", &stats);
}
