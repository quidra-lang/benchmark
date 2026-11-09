use std::collections::{
    BTreeMap,
    BTreeSet
};
use crate::lexer::Position;
use crate::parser::{
    Program,
    Top,
    Type,
    Expression,
    ExprKind,
    Statement,
    StmtKind
};
use crate::semantic::{
    Analysis,
    SymbolKind
};
#[derive(Clone)]
pub struct Instruction {
    pub op: String,
    pub operands: Vec<i64>,
    pub position: Position,
    pub callee: Option<usize>,
}
impl Instruction {
    pub fn new(op: &str, operands: Vec<i64>, position: Position) -> Self {
        Self {
            op: op.into(),
            operands,
            position,
            callee: None
        }
    }
    pub fn spelling(&self) -> String {
        let mut text = self.op.clone();
        for operand in &self.operands {
            text.push_str(&format!(" {}", operand));
        }
        text
    }
    pub fn jump(&self) -> bool {
        ["JUMP", "JUMPF", "JUMPT"].contains(&self.op.as_str())
    }
    pub fn conditional(&self) -> bool {
        self.op == "JUMPF" || self.op == "JUMPT"
    }
    pub fn transfer(&self) -> bool {
        ["JUMP", "RET", "RETV", "HALT"].contains(&self.op.as_str())
    }
}
#[derive(Clone)]
pub struct Unit {
    pub name: String,
    pub function: Option<usize>,
    pub slots: Vec<usize>,
    pub code: Vec<Instruction>,
}
pub struct Generated {
    pub units: Vec<Unit>,
    pub addresses: BTreeMap<usize,
    usize>,
    pub global_size: usize,
}
struct Generator<'a> {
    analysis: &'a Analysis,
    addresses: &'a BTreeMap<usize,
    usize>,
    slots: BTreeMap<usize,
    usize>,
    code: Vec<Instruction>,
    loops: Vec<(Vec<usize>, Vec<usize>)>,
}
impl<'a> Generator<'a> {
    fn emit(&mut self, op: &str, operands: Vec<i64>, position: Position) -> usize {
        let index = self.code.len();
        self.code.push(Instruction::new(op, operands, position));
        index
    }
    fn patch(&mut self, index: usize, target: usize) {
        self.code[index].operands[0] = target as i64;
    }
    fn call(&mut self, id: usize, n: usize, position: Position) {
        let index = self.emit("CALL", vec![0, n as i64], position);
        self.code[index].callee = Some(id);
    }
    fn variable(&mut self, id: usize, load: bool, position: Position) {
        if let Some(&address) = self.addresses.get(&id) {
            self.emit(if load {
                "LOADG"
            } else {
                "STOREG"
            }, vec![address as i64], position);
        } else {
            let slot = self.slots[&id];
            self.emit(if load {
                "LOADL"
            } else {
                "STOREL"
            }, vec![slot as i64], position);
        }
    }
    fn expression(&mut self, expression: &Expression) {
        let position = expression.position;
        match &expression.kind {
            ExprKind::Literal(value, _) => {
                self.emit("PUSH", vec![*value], position);
            },
            ExprKind::Read => {
                self.emit("READ", vec![], position);
            },
            ExprKind::Variable(_) => self.variable(expression.symbol.unwrap(), true, position),
            ExprKind::Array(_, index) => {
                self.expression(index);
                let id = expression.symbol.unwrap();
                let size = if let SymbolKind::Global(Some(size)) = self.analysis.symbols[id].kind {
                    size
                } else {
                    unreachable!()
                };
                self.emit("LOADA", vec![self.addresses[&id] as i64, size as i64], position);
            },
            ExprKind::Call(_, arguments) => {
                for argument in arguments {
                    self.expression(argument);
                }
                self.call(expression.symbol.unwrap(), arguments.len(), position);
            },
            ExprKind::Unary(operator, operand) => {
                self.expression(operand);
                self.emit(if operator == "-" {
                    "NEG"
                } else {
                    "NOT"
                }, vec![], position);
            },
            ExprKind::Binary(operator, left, right) => {
                self.expression(left);
                if operator == "&&" || operator == "||" {
                    let branch = self.emit(if operator == "&&" {
                        "JUMPF"
                    } else {
                        "JUMPT"
                    }, vec![0], position);
                    self.expression(right);
                    let end = self.emit("JUMP", vec![0], position);
                    let here = self.code.len();
                    self.patch(branch, here);
                    self.emit("PUSH", vec![if operator == "&&" {
                        0
                    } else {
                        1
                    }], position);
                    let here = self.code.len();
                    self.patch(end, here);
                } else {
                    self.expression(right);
                    let op = match operator.as_str() {
                        "+" => "ADD",
                        "-" => "SUB",
                        "*" => "MUL",
                        "/" => "DIV",
                        "%" => "MOD",
                        "<" => "LT",
                        "<=" => "LE",
                        ">" => "GT",
                        ">=" => "GE",
                        "==" => "EQ",
                        "!=" => "NE",
                        _ => unreachable!()
                    };
                    self.emit(op, vec![], position);
                }
            }
        }
    }
    fn statement(&mut self, statement: &Statement) {
        let position = statement.position;
        match &statement.kind {
            StmtKind::Block(statements, _) => for statement in statements {
                self.statement(statement);
            },
            StmtKind::Declaration(declaration) => {
                if let Some(initializer) = &declaration.initializer {
                    self.expression(initializer);
                }
                else {
                    self.emit("PUSH", vec![0], declaration.position);
                }
                self.variable(declaration.symbol.unwrap(), false, declaration.position);
            },
            StmtKind::Assignment(_, index, value, symbol) => {
                if let Some(index) = index {
                    self.expression(index);
                }
                self.expression(value);
                let id = symbol.unwrap();
                if index.is_some() {
                    let size = if let SymbolKind::Global(Some(size)) = self.analysis.symbols[id].kind {
                        size
                    } else {
                        unreachable!()
                    };
                    self.emit("STOREA", vec![self.addresses[&id] as i64, size as i64], position);
                } else {
                    self.variable(id, false, position);
                }
            },
            StmtKind::Call(expression) => {
                self.expression(expression);
                if expression.ty != Some(Type::Void) {
                    self.emit("POP", vec![], position);
                }
            },
            StmtKind::Print(values) => {
                for value in values {
                    self.expression(value);
                }
                self.emit("PRINT", vec![values.len() as i64], position);
            },
            StmtKind::If(condition, yes, no) => {
                self.expression(condition);
                let branch = self.emit("JUMPF", vec![0], position);
                self.statement(yes);
                if let Some(no) = no {
                    let end = self.emit("JUMP", vec![0], position);
                    let here = self.code.len();
                    self.patch(branch, here);
                    self.statement(no);
                    let here = self.code.len();
                    self.patch(end, here);
                } else {
                    let here = self.code.len();
                    self.patch(branch, here);
                }
            },
            StmtKind::While(condition, body) => {
                let start = self.code.len();
                self.expression(condition);
                let branch = self.emit("JUMPF", vec![0], position);
                self.loops.push((Vec::new(), Vec::new()));
                self.statement(body);
                let (breaks, continues) = self.loops.pop().unwrap();
                self.emit("JUMP", vec![start as i64], position);
                let end = self.code.len();
                self.patch(branch, end);
                for jump in breaks {
                    self.patch(jump, end);
                }
                for jump in continues {
                    self.patch(jump, start);
                }
            },
            StmtKind::For(init, condition, update, body) => {
                if let Some(init) = init {
                    self.statement(init);
                }
                let start = self.code.len();
                let branch = condition.as_ref().map(|condition| {
                    self.expression(condition);
                    self.emit("JUMPF", vec![0], position)
                });
                self.loops.push((Vec::new(), Vec::new()));
                self.statement(body);
                let (breaks, continues) = self.loops.pop().unwrap();
                let update_start = self.code.len();
                if let Some(update) = update {
                    self.statement(update);
                }
                self.emit("JUMP", vec![start as i64], position);
                let end = self.code.len();
                if let Some(branch) = branch {
                    self.patch(branch, end);
                }
                for jump in breaks {
                    self.patch(jump, end);
                }
                for jump in continues {
                    self.patch(jump, update_start);
                }
            },
            StmtKind::Break => {
                let jump = self.emit("JUMP", vec![0], position);
                self.loops.last_mut().unwrap().0.push(jump);
            },
            StmtKind::Continue => {
                let jump = self.emit("JUMP", vec![0], position);
                self.loops.last_mut().unwrap().1.push(jump);
            },
            StmtKind::Return(value) => {
                if let Some(value) = value {
                    self.expression(value);
                }
                self.emit(if value.is_some() {
                    "RETV"
                } else {
                    "RET"
                }, vec![], position);
            },
            StmtKind::Empty => ()
        }
    }
}
fn local_symbols(statement: &Statement, symbols: &mut Vec<usize>) {
    match &statement.kind {
        StmtKind::Declaration(declaration) => symbols.push(declaration.symbol.unwrap()),
        StmtKind::Block(statements, _) => for statement in statements {
            local_symbols(statement, symbols);
        },
        StmtKind::If(_, yes, no) => {
            local_symbols(yes, symbols);
            if let Some(no) = no {
                local_symbols(no, symbols);
            }
        },
        StmtKind::While(_, body) => local_symbols(body, symbols),
        StmtKind::For(init, _, update, body) => {
            if let Some(init) = init {
                local_symbols(init, symbols);
            }
            if let Some(update) = update {
                local_symbols(update, symbols);
            }
            local_symbols(body, symbols);
        },
        _ => ()
    }
}
pub fn generate(program: &Program, analysis: &Analysis, reachable: &BTreeSet<usize>) -> Generated {
    let mut addresses = BTreeMap::new();
    let mut global_size = 0;
    for &id in &analysis.globals {
        addresses.insert(id, global_size);
        global_size += if let SymbolKind::Global(Some(size)) = analysis.symbols[id].kind {
            size
        } else {
            1
        };
    }
    let mut generator = Generator {
        analysis,
        addresses: &addresses,
        slots: BTreeMap::new(),
        code: Vec::new(),
        loops: Vec::new()
    };
    for declaration in &program.declarations {
        if let Top::Global(declaration) = declaration {
            if let Some(initializer) = &declaration.initializer {
                generator.expression(initializer);
                generator.variable(declaration.symbol.unwrap(), false, declaration.position);
            }
        }
    }
    let position = analysis.symbols[analysis.main].position;
    generator.call(analysis.main, 0, position);
    generator.emit("HALT", vec![], position);
    let mut units = vec![Unit {
        name: "<init>".into(),
        function: None,
        slots: Vec::new(),
        code: std::mem::take(&mut generator.code)
    }];
    for declaration in &program.declarations {
        if let Top::Function(function) = declaration {
            let id = function.symbol.unwrap();
            if !reachable.contains(&id) {
                continue;
            }
            let mut locals = Vec::new();
            local_symbols(&function.body, &mut locals);
            locals.sort_by_key(|&id| analysis.symbols[id].position);
            let mut slots: Vec<usize> = function.parameters.iter().map(|p| p.symbol.unwrap()).collect();
            slots.extend(locals);
            generator.slots = slots.iter().enumerate().map(|(slot, &id)| (id, slot)).collect();
            generator.emit("ENTER", vec![slots.len() as i64], function.position);
            generator.statement(&function.body);
            if function.ty == Type::Void {
                let close = if let StmtKind::Block(_, close) = function.body.kind {
                    close
                } else {
                    unreachable!()
                };
                generator.emit("RET", vec![], close);
            }
            units.push(Unit {
                name: function.name.clone(),
                function: Some(id),
                slots,
                code: std::mem::take(&mut generator.code)
            });
        }
    }
    Generated {
        units,
        addresses,
        global_size
    }
}
pub fn arrange(units: &[Unit]) -> (Vec<Instruction>, Vec<usize>, Vec<usize>) {
    let mut starts = Vec::new();
    let mut functions = BTreeMap::new();
    let mut address = 0;
    for unit in units {
        starts.push(address);
        if let Some(id) = unit.function {
            functions.insert(id, address);
        }
        address += unit.code.len();
    }
    let mut code = Vec::new();
    let mut owners = Vec::new();
    for (index, unit) in units.iter().enumerate() {
        for instruction in &unit.code {
            let mut instruction = instruction.clone();
            if instruction.jump() {
                instruction.operands[0] += starts[index] as i64;
            }
            if let Some(id) = instruction.callee {
                instruction.operands[0] = functions[&id] as i64;
            }
            code.push(instruction);
            owners.push(index);
        }
    }
    (code, starts, owners)
}
