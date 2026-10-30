use std::collections::{
    BTreeMap,
    BTreeSet
};
use crate::lexer::{
    Position,
    Error
};
use crate::parser::{
    Program,
    Top,
    Type,
    Expression,
    ExprKind,
    Declaration,
    Statement,
    StmtKind
};
#[derive(Clone)]
pub enum SymbolKind {
    Global(Option<usize>),
    Function(Vec<Type>),
    Parameter,
    Local
}
#[derive(Clone)]
pub struct Symbol {
    pub name: String,
    pub ty: Type,
    pub kind: SymbolKind,
    pub position: Position,
    pub references: Vec<Position>,
    pub reads: usize,
    pub owner: Option<usize>
}
pub struct Analysis {
    pub symbols: Vec<Symbol>,
    pub globals: Vec<usize>,
    pub functions: Vec<usize>,
    pub calls: BTreeMap<usize,
    BTreeSet<usize>>,
    pub main: usize
}
struct Semantic {
    analysis: Analysis,
    globals: BTreeMap<String,
    usize>,
    scopes: Vec<BTreeMap<String,
    usize>>,
    current: Option<usize>,
    loops: usize
}
fn error(position: Position, message: String) -> Error {
    Error {
        kind: "semantic",
        position,
        message
    }
}
pub fn completes(statement: &Statement) -> bool {
    match &statement.kind {
        StmtKind::Break | StmtKind::Continue | StmtKind::Return(_) => false,
        StmtKind::Block(statements, _) => statements.iter().all(completes),
        StmtKind::If(_, yes, no) => no.as_ref().map_or(true, |no| completes(yes) || completes(no)),
        _ => true
    }
}
fn nonconstant(expression: &Expression) -> Option<Position> {
    let mut positions = Vec::new();
    match &expression.kind {
        ExprKind::Variable(_) | ExprKind::Read => positions.push(expression.position),
        ExprKind::Array(_, index) => {
            positions.push(expression.position);
            positions.extend(nonconstant(index));
        },
        ExprKind::Call(_, arguments) => {
            positions.push(expression.position);
            for argument in arguments {
                positions.extend(nonconstant(argument));
            }
        },
        ExprKind::Unary(_, body) => positions.extend(nonconstant(body)),
        ExprKind::Binary(_, a, b) => {
            positions.extend(nonconstant(a));
            positions.extend(nonconstant(b));
        },
        _ => ()
    }
    positions.into_iter().min()
}
impl Semantic {
    fn symbol(&mut self, name: &str, ty: Type, kind: SymbolKind, position: Position) -> usize {
        let id = self.analysis.symbols.len();
        self.analysis.symbols.push(Symbol {
            name: name.into(),
            ty,
            kind,
            position,
            references: Vec::new(),
            reads: 0,
            owner: self.current
        });
        id
    }
    fn find(&self, name: &str) -> Option<usize> {
        self.scopes.iter().rev().find_map(|scope| scope.get(name).copied()).or_else(|| self.globals.get(name).copied())
    }
    fn reference(&mut self, id: usize, position: Position, read: bool) {
        self.analysis.symbols[id].references.push(position);
        if read {
            self.analysis.symbols[id].reads += 1;
        }
    }
    fn variable(&mut self, name: &str, position: Position, array: bool, read: bool) -> Result<usize,
    Error> {
        let id = self.find(name).ok_or_else(|| error(position, format!("undeclared identifier '{}'", name)))?;
        self.reference(id, position, read);
        match &self.analysis.symbols[id].kind {
            SymbolKind::Function(_) => return Err(error(position, format!("'{}' is a function, not a variable", name))),
            SymbolKind::Global(Some(_)) if !array => return Err(error(position, format!("array '{}' used without index", name))),
            SymbolKind::Global(Some(_)) => (),
            _ if array => return Err(error(position, format!("'{}' is not an array", name))),
            _ => ()
        }
        Ok(id)
    }
    fn expression(&mut self, expression: &mut Expression, statement: bool) -> Result<Type,
    Error> {
        let position = expression.position;
        let ty = match &mut expression.kind {
            ExprKind::Literal(_, ty) => *ty,
            ExprKind::Read => Type::Int,
            ExprKind::Variable(name) => {
                let id = self.variable(name, position, false, true)?;
                expression.symbol = Some(id);
                self.analysis.symbols[id].ty
            },
            ExprKind::Array(name, index) => {
                let id = self.variable(name, position, true, true)?;
                expression.symbol = Some(id);
                if self.expression(index, false)? != Type::Int {
                    return Err(error(position, format!("index of '{}' must be int", name)));
                }
                Type::Int
            },
            ExprKind::Call(name, arguments) => {
                let id = self.find(name).ok_or_else(|| error(position, format!("undeclared function '{}'", name)))?;
                self.reference(id, position, true);
                expression.symbol = Some(id);
                let parameters = if let SymbolKind::Function(parameters) = &self.analysis.symbols[id].kind {
                    parameters.clone()
                } else {
                    return Err(error(position, format!("'{}' is not a function", name)));
                };
                if let Some(caller) = self.current {
                    self.analysis.calls.entry(caller).or_default().insert(id);
                }
                if parameters.len() != arguments.len() {
                    return Err(error(position, format!("wrong number of arguments to '{}' (expected {}, found {})", name, parameters.len(), arguments.len())));
                }
                for (i, argument) in arguments.iter_mut().enumerate() {
                    if self.expression(argument, false)? != parameters[i] {
                        return Err(error(position, format!("argument {} of '{}' must be {}", i + 1, name, parameters[i].text())));
                    }
                }
                let ty = self.analysis.symbols[id].ty;
                if !statement && ty == Type::Void {
                    return Err(error(position, format!("void function '{}' used as a value", name)));
                }
                ty
            },
            ExprKind::Unary(operator, operand) => {
                let ty = self.expression(operand, false)?;
                let expected = if operator == "-" {
                    Type::Int
                } else {
                    Type::Bool
                };
                if ty != expected {
                    return Err(error(position, format!("operator '{}' requires {} operand", operator, expected.text())));
                }
                ty
            },
            ExprKind::Binary(operator, a, b) => {
                let left = self.expression(a, false)?;
                let right = self.expression(b, false)?;
                if ["+", "-", "*", "/", "%", "<", "<=", ">", ">="].contains(&operator.as_str()) {
                    if left != Type::Int || right != Type::Int {
                        return Err(error(position, format!("operator '{}' requires int operands", operator)));
                    }
                    if ["+", "-", "*", "/", "%"].contains(&operator.as_str()) {
                        Type::Int
                    } else {
                        Type::Bool
                    }
                } else if operator == "==" || operator == "!=" {
                    if left != right {
                        return Err(error(position, format!("operator '{}' requires operands of the same type", operator)));
                    }
                    Type::Bool
                } else {
                    if left != Type::Bool || right != Type::Bool {
                        return Err(error(position, format!("operator '{}' requires bool operands", operator)));
                    }
                    Type::Bool
                }
            }
        };
        expression.ty = Some(ty);
        Ok(ty)
    }
    fn declaration(&mut self, declaration: &mut Declaration) -> Result<(),
    Error> {
        if declaration.ty == Type::Void {
            return Err(error(declaration.position, format!("variable '{}' cannot have type void", declaration.name)));
        }
        if self.scopes.last().unwrap().contains_key(&declaration.name) {
            return Err(error(declaration.position, format!("redeclaration of '{}'", declaration.name)));
        }
        if let Some(initializer) = &mut declaration.initializer {
            if self.expression(initializer, false)? != declaration.ty {
                return Err(error(declaration.position, format!("type mismatch in initialization of '{}'", declaration.name)));
            }
        }
        let id = self.symbol(&declaration.name, declaration.ty, SymbolKind::Local, declaration.position);
        declaration.symbol = Some(id);
        self.scopes.last_mut().unwrap().insert(declaration.name.clone(), id);
        Ok(())
    }
    fn statement(&mut self, statement: &mut Statement) -> Result<(),
    Error> {
        let position = statement.position;
        match &mut statement.kind {
            StmtKind::Block(statements, _) => {
                self.scopes.push(BTreeMap::new());
                for statement in statements {
                    self.statement(statement)?;
                }
                self.scopes.pop();
            },
            StmtKind::Declaration(declaration) => self.declaration(declaration)?,
            StmtKind::Assignment(name, index, value, symbol) => {
                let id = self.variable(name, position, index.is_some(), false)?;
                *symbol = Some(id);
                if let Some(index) = index {
                    if self.expression(index, false)? != Type::Int {
                        return Err(error(position, format!("index of '{}' must be int", name)));
                    }
                }
                let ty = self.expression(value, false)?;
                if ty != self.analysis.symbols[id].ty {
                    return Err(error(position, format!("type mismatch in assignment to '{}'", name)));
                }
            },
            StmtKind::Call(expression) => {
                self.expression(expression, true)?;
            },
            StmtKind::If(condition, yes, no) => {
                if self.expression(condition, false)? != Type::Bool {
                    return Err(error(position, "condition of 'if' must be bool".into()));
                }
                self.statement(yes)?;
                if let Some(no) = no {
                    self.statement(no)?;
                }
            },
            StmtKind::While(condition, body) => {
                if self.expression(condition, false)? != Type::Bool {
                    return Err(error(position, "condition of 'while' must be bool".into()));
                }
                self.loops += 1;
                self.statement(body)?;
                self.loops -= 1;
            },
            StmtKind::For(init, condition, update, body) => {
                self.scopes.push(BTreeMap::new());
                if let Some(init) = init {
                    self.statement(init)?;
                }
                if let Some(condition) = condition {
                    if self.expression(condition, false)? != Type::Bool {
                        return Err(error(position, "condition of 'for' must be bool".into()));
                    }
                }
                if let Some(update) = update {
                    self.statement(update)?;
                }
                self.loops += 1;
                self.statement(body)?;
                self.loops -= 1;
                self.scopes.pop();
            },
            StmtKind::Break => if self.loops == 0 {
                return Err(error(position, "'break' outside loop".into()));
            },
            StmtKind::Continue => if self.loops == 0 {
                return Err(error(position, "'continue' outside loop".into()));
            },
            StmtKind::Return(value) => {
                let id = self.current.unwrap();
                let ty = self.analysis.symbols[id].ty;
                let name = self.analysis.symbols[id].name.clone();
                if ty == Type::Void && value.is_some() {
                    return Err(error(position, format!("function '{}' must not return a value", name)));
                }
                if ty != Type::Void && value.is_none() {
                    return Err(error(position, format!("function '{}' must return a value", name)));
                }
                if let Some(value) = value {
                    if self.expression(value, false)? != ty {
                        return Err(error(position, format!("return value of '{}' must be {}", name, ty.text())));
                    }
                }
            },
            StmtKind::Print(values) => for (i, value) in values.iter_mut().enumerate() {
                if self.expression(value, false)? != Type::Int {
                    return Err(error(position, format!("argument {} of 'print' must be int", i + 1)));
                }
            },
            StmtKind::Empty => ()
        }
        Ok(())
    }
}
pub fn analyze(program: &mut Program) -> Result<Analysis, Error> {
    let mut semantic = Semantic {
        analysis: Analysis {
            symbols: Vec::new(),
            globals: Vec::new(),
            functions: Vec::new(),
            calls: BTreeMap::new(),
            main: 0
        },
        globals: BTreeMap::new(),
        scopes: Vec::new(),
        current: None,
        loops: 0
    };
    for declaration in &mut program.declarations {
        match declaration {
            Top::Global(declaration) => {
                if let Some((size, position)) = declaration.array {
                    if declaration.ty != Type::Int {
                        return Err(error(declaration.position, format!("array '{}' must have element type int", declaration.name)));
                    }
                    if size == 0 {
                        return Err(error(position, format!("array '{}' must have a positive size", declaration.name)));
                    }
                } else if declaration.ty == Type::Void {
                    return Err(error(declaration.position, format!("variable '{}' cannot have type void", declaration.name)));
                }
                if semantic.globals.contains_key(&declaration.name) {
                    return Err(error(declaration.position, format!("redeclaration of '{}'", declaration.name)));
                }
                if let Some(initializer) = &mut declaration.initializer {
                    if let Some(position) = nonconstant(initializer) {
                        return Err(error(position, "global initializer must be constant".into()));
                    }
                    if semantic.expression(initializer, false)? != declaration.ty {
                        return Err(error(declaration.position, format!("type mismatch in initialization of '{}'", declaration.name)));
                    }
                }
                let id = semantic.symbol(&declaration.name, declaration.ty, SymbolKind::Global(declaration.array.map(|v| v.0)), declaration.position);
                declaration.symbol = Some(id);
                semantic.globals.insert(declaration.name.clone(), id);
                semantic.analysis.globals.push(id);
            },
            Top::Function(function) => {
                if semantic.globals.contains_key(&function.name) {
                    return Err(error(function.position, format!("redeclaration of '{}'", function.name)));
                }
                let mut names = BTreeSet::new();
                for parameter in &function.parameters {
                    if parameter.ty == Type::Void {
                        return Err(error(parameter.position, format!("parameter '{}' cannot have type void", parameter.name)));
                    }
                    if !names.insert(parameter.name.clone()) {
                        return Err(error(parameter.position, format!("redeclaration of '{}'", parameter.name)));
                    }
                }
                let id = semantic.symbol(&function.name, function.ty, SymbolKind::Function(function.parameters.iter().map(|p| p.ty).collect()), function.position);
                function.symbol = Some(id);
                semantic.globals.insert(function.name.clone(), id);
                semantic.analysis.functions.push(id);
            }
        }
    }
    let main = semantic.globals.get("main").copied().filter(|&id| matches!(semantic.analysis.symbols[id].kind, SymbolKind::Function(_))).ok_or_else(|| error(program.end, "no main function".into()))?;
    let signature = &semantic.analysis.symbols[main];
    if signature.ty != Type::Void || matches!(&signature.kind, SymbolKind::Function(parameters) if !parameters.is_empty()) {
        return Err(error(signature.position, "main must be declared as 'void main()'".into()));
    }
    semantic.analysis.main = main;
    for declaration in &mut program.declarations {
        if let Top::Function(function) = declaration {
            let id = function.symbol.unwrap();
            semantic.current = Some(id);
            semantic.scopes = vec![BTreeMap::new()];
            for parameter in &mut function.parameters {
                let symbol = semantic.symbol(&parameter.name, parameter.ty, SymbolKind::Parameter, parameter.position);
                parameter.symbol = Some(symbol);
                semantic.scopes[0].insert(parameter.name.clone(), symbol);
            }
            if let StmtKind::Block(statements, _) = &mut function.body.kind {
                for statement in statements {
                    semantic.statement(statement)?;
                }
            }
            if function.ty != Type::Void && completes(&function.body) {
                return Err(error(function.position, format!("missing return in function '{}'", function.name)));
            }
        }
    }
    Ok(semantic.analysis)
}
