mod lexer;
mod parser;
mod values_fields;
mod builtins;
mod streams;
use std::collections::{
    BTreeMap,
    BTreeSet
};
use std::cell::RefCell;
use std::rc::Rc;
use std::fs;
use lexer::Position;
use parser::{
    Program,
    Expression,
    ExprKind,
    Statement,
    StmtKind
};
use values_fields::{
    Value,
    Fields
};
use builtins::RuntimeError;
#[derive(Clone, PartialEq, Eq, PartialOrd, Ord)]
struct Key(Option<usize>, String);
struct CallSite {
    name: String,
    arguments: Vec<Expression>,
    scope: Option<usize>,
    position: Position
}
struct Preparation {
    globals: BTreeSet<String>,
    arrays: BTreeSet<Key>,
    uses: Vec<(Key, Position)>,
    calls: Vec<CallSite>,
    lines: BTreeMap<usize,
    usize>,
    functions: BTreeMap<String,
    usize>
}
impl Preparation {
    fn key(program: &Program, scope: Option<usize>, name: &str) -> Key {
        if scope.map_or(false, |i| program.functions[i].parameters.iter().any(|p| p.0 == name)) {
            Key(scope, name.into())
        } else {
            Key(None, name.into())
        }
    }
    fn name(&mut self, program: &Program, scope: Option<usize>, name: &str, position: Position, array: bool) {
        let key = Self::key(program, scope, name);
        if key.0.is_none() {
            self.globals.insert(name.into());
        }
        if array {
            self.arrays.insert(key.clone());
        }
        self.uses.push((key, position));
    }
    fn expression(&mut self, program: &Program, scope: Option<usize>, expression: &Expression) {
        match &expression.kind {
            ExprKind::Name(name) => self.name(program, scope, name, expression.position, false),
            ExprKind::Index(name, indices) => {
                self.name(program, scope, name, expression.position, true);
                for index in indices {
                    self.expression(program, scope, index);
                }
            },
            ExprKind::Field(body) | ExprKind::Parentheses(body) | ExprKind::Unary(_, body) | ExprKind::Increment(_, _, body) => self.expression(program, scope, body),
            ExprKind::Binary(_, a, b) | ExprKind::Assignment(_, a, b) => {
                self.expression(program, scope, a);
                self.expression(program, scope, b);
            },
            ExprKind::Conditional(a, b, c) => {
                self.expression(program, scope, a);
                self.expression(program, scope, b);
                self.expression(program, scope, c);
            },
            ExprKind::In(indices, name, position) => {
                for index in indices {
                    self.expression(program, scope, index);
                }
                self.name(program, scope, name, *position, true);
            },
            ExprKind::Call(name, builtin, arguments) => {
                if !builtin {
                    self.calls.push(CallSite {
                        name: name.clone(),
                        arguments: arguments.clone(),
                        scope,
                        position: expression.position
                    });
                }
                for argument in arguments {
                    self.expression(program, scope, argument);
                }
                if *builtin && name == "split" {
                    if let ExprKind::Name(name) = &arguments[1].kind {
                        self.arrays.insert(Self::key(program, scope, name));
                    }
                }
            },
            ExprKind::Getline(target, file) => {
                if let Some(target) = target {
                    self.expression(program, scope, target);
                }
                if let Some(file) = file {
                    self.expression(program, scope, file);
                }
            },
            _ => ()
        }
    }
    fn statement(&mut self, program: &Program, scope: Option<usize>, statement: &Statement) {
        if !matches!(statement.kind, StmtKind::Block(_) | StmtKind::Empty) {
            self.lines.entry(statement.position.line).or_insert(0);
        }
        match &statement.kind {
            StmtKind::Block(statements) => for statement in statements {
                self.statement(program, scope, statement);
            },
            StmtKind::Expression(expression) => self.expression(program, scope, expression),
            StmtKind::If(condition, yes, no) => {
                self.expression(program, scope, condition);
                self.statement(program, scope, yes);
                if let Some(no) = no {
                    self.statement(program, scope, no);
                }
            },
            StmtKind::While(condition, body) => {
                self.expression(program, scope, condition);
                self.statement(program, scope, body);
            },
            StmtKind::Do(body, condition) => {
                self.statement(program, scope, body);
                self.expression(program, scope, condition);
            },
            StmtKind::For(init, condition, update, body) => {
                for expression in [init, condition, update].iter().filter_map(|e| e.as_ref()) {
                    self.expression(program, scope, expression);
                }
                self.statement(program, scope, body);
            },
            StmtKind::ForIn(variable, vp, array, ap, body) => {
                self.name(program, scope, variable, *vp, false);
                self.name(program, scope, array, *ap, true);
                self.statement(program, scope, body);
            },
            StmtKind::Output(_, arguments, redirect) => {
                for argument in arguments {
                    self.expression(program, scope, argument);
                }
                if let Some((_, target, _)) = redirect {
                    self.expression(program, scope, target);
                }
            },
            StmtKind::Delete(name, position, indices) => {
                self.name(program, scope, name, *position, true);
                if let Some(indices) = indices {
                    for index in indices {
                        self.expression(program, scope, index);
                    }
                }
            },
            StmtKind::Exit(value) | StmtKind::Return(value) => if let Some(value) = value {
                self.expression(program, scope, value);
            },
            _ => ()
        }
    }
    fn analyze(program: &Program) -> Result<Self,
    (Position, String)> {
        let mut prep = Self {
            globals: ["FILENAME", "FNR", "FS", "NF", "NR", "OFS", "ORS", "SUBSEP"].iter().map(|s| s.to_string()).collect(),
            arrays: BTreeSet::new(),
            uses: Vec::new(),
            calls: Vec::new(),
            lines: BTreeMap::new(),
            functions: BTreeMap::new()
        };
        let mut errors = Vec::new();
        for (i, function) in program.functions.iter().enumerate() {
            if prep.functions.contains_key(&function.name) {
                errors.push((function.position, 0, format!("function {} redefined", function.name)));
            } else {
                prep.functions.insert(function.name.clone(), i);
            }
            let mut parameters = BTreeSet::new();
            for (name, position) in &function.parameters {
                if !parameters.insert(name.clone()) {
                    errors.push((*position, 1, format!("duplicate parameter {}", name)));
                }
                prep.uses.push((Key(Some(i), name.clone()), *position));
            }
            prep.statement(program, Some(i), &function.body);
        }
        for rule in &program.rules {
            if let Some(start) = &rule.start {
                prep.expression(program, None, start);
            }
            if let Some(end) = &rule.end {
                prep.expression(program, None, end);
            }
            if let Some(action) = &rule.action {
                prep.statement(program, None, action);
            }
        }
        for (key, position) in &prep.uses {
            if prep.functions.contains_key(&key.1) {
                errors.push((*position, 2, format!("function {} used as variable", key.1)));
            }
        }
        let mut links = Vec::new();
        for call in &prep.calls {
            if let Some(&callee) = prep.functions.get(&call.name) {
                let parameters = &program.functions[callee].parameters;
                if call.arguments.len() > parameters.len() {
                    errors.push((call.position, 4, format!("too many arguments to {}", call.name)));
                }
                for (argument, parameter) in call.arguments.iter().zip(parameters) {
                    if let ExprKind::Name(name) = &argument.kind {
                        links.push((Self::key(program, call.scope, name), Key(Some(callee), parameter.0.clone())));
                    }
                }
            } else {
                errors.push((call.position, 3, format!("undefined function {}", call.name)));
            }
        }
        if !errors.is_empty() {
            errors.sort_by_key(|e| (e.0, e.1));
            let (position, _, message) = errors.remove(0);
            return Err((position, message));
        }
        loop {
            let mut changed = false;
            for (a, b) in &links {
                if prep.arrays.contains(a) || prep.arrays.contains(b) {
                    changed |= prep.arrays.insert(a.clone());
                    changed |= prep.arrays.insert(b.clone());
                }
            }
            if !changed {
                break;
            }
        }
        Ok(prep)
    }
}
type Array = Rc<RefCell<BTreeMap<String, Value>>>;
#[derive(Clone)]
enum Cell {
    Scalar(Value),
    Array(Array)
}
enum Location {
    Variable(Option<usize>, String),
    Element(Array, String),
    Field(usize)
}
enum Flow {
    Runtime(RuntimeError),
    Next,
    Exit,
    Return(Value),
    Break,
    Continue
}
impl From<RuntimeError> for Flow {
    fn from(error: RuntimeError) -> Self {
        Self::Runtime(error)
    }
}
type Evaluation<T> = Result<T, Flow>;
struct Runtime<'a> {
    program: &'a Program,
    preparation: Preparation,
    globals: BTreeMap<String,
    Cell>,
    locals: Vec<BTreeMap<String,
    Cell>>,
    fields: Fields,
    streams: streams::Streams,
    arguments: streams::Arguments,
    operand: usize,
    current: Option<(usize, Vec<String>, usize)>,
    phase: &'static str,
    status: i64,
    rules: Vec<usize>,
    ranges: Vec<bool>,
    calls: Vec<usize>,
    active: Vec<usize>,
    depths: Vec<usize>,
}
impl<'a> Runtime<'a> {
    fn new(program: &'a Program, preparation: Preparation, arguments: streams::Arguments) -> Self {
        let mut globals = BTreeMap::new();
        for name in &preparation.globals {
            let cell = if preparation.arrays.contains(&Key(None, name.clone())) {
                Cell::Array(Rc::new(RefCell::new(BTreeMap::new())))
            } else {
                Cell::Scalar(Value::Uninitialized)
            };
            globals.insert(name.clone(), cell);
        }
        for (name, value) in [("FS", Value::String(" ".into())), ("OFS", Value::String(" ".into())), ("ORS", Value::String("\n".into())), ("SUBSEP", Value::String("\x1c".into())), ("NR", Value::Number(0)), ("FNR", Value::Number(0)), ("FILENAME", Value::String(String::new()))].iter().cloned() {
            globals.insert(name.into(), Cell::Scalar(value));
        }
        Self {
            program,
            preparation,
            globals,
            locals: Vec::new(),
            fields: Fields::new(),
            streams: streams::Streams::new(),
            arguments,
            operand: 0,
            current: None,
            phase: "BEGIN",
            status: 0,
            rules: vec![0; program.rules.len()],
            ranges: vec![false; program.rules.len()],
            calls: vec![0; program.functions.len()],
            active: vec![0; program.functions.len()],
            depths: vec![0; program.functions.len()]
        }
    }
    fn variable(&self, name: &str) -> Option<usize> {
        if self.locals.last().map_or(false, |local| local.contains_key(name)) {
            Some(self.locals.len() - 1)
        } else {
            None
        }
    }
    fn cell(&self, frame: Option<usize>, name: &str) -> Option<&Cell> {
        if let Some(frame) = frame {
            self.locals[frame].get(name)
        } else {
            self.globals.get(name)
        }
    }
    fn array(&mut self, name: &str) -> Array {
        let frame = self.variable(name);
        if let Some(Cell::Array(array)) = self.cell(frame, name) {
            return array.clone();
        }
        unreachable!()
    }
    fn value(&self, frame: Option<usize>, name: &str) -> Value {
        if frame.is_none() && name == "NF" {
            return Value::Number(self.fields.fields.len() as i64);
        }
        match self.cell(frame, name) {
            Some(Cell::Scalar(value)) => value.clone(),
            None => Value::Uninitialized,
            _ => unreachable!()
        }
    }
    fn global(&self, name: &str) -> Value {
        self.value(None, name)
    }
    fn key(&mut self, expressions: &[Expression]) -> Evaluation<String> {
        let mut keys = Vec::new();
        for expression in expressions {
            keys.push(self.expression(expression)?.text());
        }
        Ok(keys.join(&self.global("SUBSEP").text()))
    }
    fn location(&mut self, expression: &Expression) -> Evaluation<Location> {
        match &expression.kind {
            ExprKind::Name(name) => Ok(Location::Variable(self.variable(name), name.clone())),
            ExprKind::Index(name, indices) => {
                let key = self.key(indices)?;
                Ok(Location::Element(self.array(name), key))
            },
            ExprKind::Field(index) => {
                let index = self.expression(index)?.number();
                if index < 0 {
                    return Err(builtins::error(expression.position, "negative field index").into());
                }
                Ok(Location::Field(index as usize))
            },
            _ => unreachable!()
        }
    }
    fn read(&mut self, location: &Location) -> Value {
        match location {
            Location::Variable(frame, name) => self.value(*frame, name),
            Location::Element(array, key) => array.borrow_mut().entry(key.clone()).or_insert(Value::Uninitialized).clone(),
            Location::Field(index) => self.fields.get(*index)
        }
    }
    fn store(&mut self, location: &Location, value: Value, position: Position) -> Evaluation<Value> {
        match location {
            Location::Variable(frame, name) => {
                if frame.is_none() && name == "NF" {
                    let n = value.number();
                    if n < 0 {
                        return Err(builtins::error(position, "negative NF").into());
                    }
                    let ofs = self.global("OFS").text();
                    self.fields.nf(n as usize, &ofs);
                }
                else if let Some(frame) = frame {
                    self.locals[*frame].insert(name.clone(), Cell::Scalar(value));
                }
                else {
                    self.preparation.globals.insert(name.clone());
                    self.globals.insert(name.clone(), Cell::Scalar(value));
                }
            },
            Location::Element(array, key) => {
                array.borrow_mut().insert(key.clone(), value);
            },
            Location::Field(index) => {
                let fs = self.global("FS").text();
                let ofs = self.global("OFS").text();
                self.fields.assign(*index, value, &fs, &ofs);
            }
        }
        Ok(self.read(location))
    }
    fn arithmetic(&self, op: &str, a: i64, b: i64, position: Position) -> Evaluation<Value> {
        if (op == "/" || op == "%") && b == 0 {
            return Err(builtins::error(position, "division by zero").into());
        }
        if op == "^" && b < 0 {
            return Err(builtins::error(position, "negative exponent").into());
        }
        Ok(Value::Number(match op {
            "+" => a + b,
            "-" => a - b,
            "*" => a * b,
            "/" => a / b,
            "%" => a % b,
            "^" => {
                let mut result = 1;
                let mut base = a;
                let mut exponent = b;
                while exponent > 0 {
                    if exponent % 2 == 1 {
                        result *= base;
                    }
                    exponent /= 2;
                    if exponent > 0 {
                        base *= base;
                    }
                }
                result
            },
            _ => unreachable!()
        }))
    }
    fn expression(&mut self, expression: &Expression) -> Evaluation<Value> {
        let position = expression.position;
        match &expression.kind {
            ExprKind::Number(n) => Ok(Value::Number(*n)),
            ExprKind::String(s) => Ok(Value::String(s.clone())),
            ExprKind::Name(_) | ExprKind::Index(_, _) | ExprKind::Field(_) => {
                let location = self.location(expression)?;
                Ok(self.read(&location))
            },
            ExprKind::Parentheses(body) => self.expression(body),
            ExprKind::Unary(op, body) => {
                let value = self.expression(body)?;
                Ok(Value::Number(match op.as_str() {
                    "-" => -value.number(),
                    "+" => value.number(),
                    _ => if value.truth() {
                        0
                    } else {
                        1
                    }
                }))
            },
            ExprKind::Binary(op, left, right) => {
                let a = self.expression(left)?;
                if op == "||" && a.truth() {
                    return Ok(Value::Number(1));
                }
                if op == "&&" && !a.truth() {
                    return Ok(Value::Number(0));
                }
                let b = self.expression(right)?;
                if op == "||" || op == "&&" {
                    return Ok(Value::Number(if b.truth() {
                        1
                    } else {
                        0
                    }));
                }
                if op == "concat" {
                    return Ok(Value::String(a.text() + &b.text()));
                }
                if ["<", "<=", "==", "!=", ">=", ">"].contains(&op.as_str()) {
                    let order = a.compare(&b);
                    let result = match op.as_str() {
                        "<" => order.is_lt(),
                        "<=" => !order.is_gt(),
                        "==" => order.is_eq(),
                        "!=" => !order.is_eq(),
                        ">=" => !order.is_lt(),
                        _ => order.is_gt()
                    };
                    return Ok(Value::Number(if result {
                        1
                    } else {
                        0
                    }));
                }
                self.arithmetic(op, a.number(), b.number(), position)
            },
            ExprKind::Assignment(op, target, right) => {
                let location = self.location(target)?;
                let b = self.expression(right)?;
                let value = if op == "=" {
                    b
                } else {
                    let a = self.read(&location);
                    self.arithmetic(&op[..1], a.number(), b.number(), position)?
                };
                self.store(&location, value, position)
            },
            ExprKind::Increment(delta, prefix, target) => {
                let location = self.location(target)?;
                let value = self.read(&location).number();
                self.store(&location, Value::Number(value + delta), position)?;
                Ok(Value::Number(if *prefix {
                    value + delta
                } else {
                    value
                }))
            },
            ExprKind::Conditional(condition, yes, no) => if self.expression(condition)?.truth() {
                self.expression(yes)
            } else {
                self.expression(no)
            },
            ExprKind::In(indices, name, _) => {
                let key = self.key(indices)?;
                let contains = self.array(name).borrow().contains_key(&key);
                Ok(Value::Number(if contains {
                    1
                } else {
                    0
                }))
            },
            ExprKind::Call(name, builtin, arguments) => if *builtin {
                self.builtin(name, arguments, position)
            } else {
                self.call(name, arguments)
            },
            ExprKind::Getline(target, file) => {
                let (status, line) = if let Some(file) = file {
                    let name = self.expression(file)?.text();
                    self.streams.getline(&name)
                } else if self.phase == "END" {
                    (0, None)
                } else {
                    match self.next_record()? {
                        Some(line) => (1, Some(line)),
                        None => (0, None)
                    }
                };
                if let Some(line) = line {
                    if let Some(target) = target {
                        let location = self.location(target)?;
                        self.store(&location, Value::input(line), position)?;
                    } else {
                        let fs = self.global("FS").text();
                        self.fields.set(line, &fs);
                    }
                }
                Ok(Value::Number(status))
            }
        }
    }
    fn builtin(&mut self, name: &str, arguments: &[Expression], position: Position) -> Evaluation<Value> {
        if name == "length" {
            if arguments.is_empty() {
                return Ok(Value::Number(self.fields.record.text().len() as i64));
            }
            if let ExprKind::Name(name) = &arguments[0].kind {
                let frame = self.variable(name);
                if let Some(Cell::Array(array)) = self.cell(frame, name) {
                    return Ok(Value::Number(array.borrow().len() as i64));
                }
            }
            return Ok(Value::Number(self.expression(&arguments[0])?.text().len() as i64));
        }
        if name == "split" {
            let text = self.expression(&arguments[0])?.text();
            let separator = if arguments.len() == 3 {
                self.expression(&arguments[2])?.text()
            } else {
                self.global("FS").text()
            };
            let array_name = if let ExprKind::Name(name) = &arguments[1].kind {
                name
            } else {
                unreachable!()
            };
            let array = self.array(array_name);
            let pieces = values_fields::split(&text, &separator);
            let count = pieces.len();
            let mut array = array.borrow_mut();
            array.clear();
            for (i, piece) in pieces.into_iter().enumerate() {
                array.insert((i + 1).to_string(), Value::input(piece));
            }
            return Ok(Value::Number(count as i64));
        }
        let mut values = Vec::new();
        for argument in arguments {
            values.push(self.expression(argument)?);
        }
        if name == "close" {
            return Ok(Value::Number(self.streams.close(&values[0].text())));
        }
        Ok(builtins::scalar(name, &values, position)?)
    }
    fn call(&mut self, name: &str, arguments: &[Expression]) -> Evaluation<Value> {
        let index = self.preparation.functions[name];
        let function = self.program.functions[index].clone();
        let mut local = BTreeMap::new();
        for (i, (name, _)) in function.parameters.iter().enumerate() {
            let cell = if self.preparation.arrays.contains(&Key(Some(index), name.clone())) {
                if let Some(argument) = arguments.get(i) {
                    let name = if let ExprKind::Name(name) = &argument.kind {
                        name
                    } else {
                        unreachable!()
                    };
                    Cell::Array(self.array(name))
                } else {
                    Cell::Array(Rc::new(RefCell::new(BTreeMap::new())))
                }
            } else {
                Cell::Scalar(if let Some(argument) = arguments.get(i) {
                    self.expression(argument)?
                } else {
                    Value::Uninitialized
                })
            };
            local.insert(name.clone(), cell);
        }
        self.calls[index] += 1;
        self.active[index] += 1;
        self.depths[index] = self.depths[index].max(self.active[index]);
        self.locals.push(local);
        let result = self.statement(&function.body);
        self.locals.pop();
        self.active[index] -= 1;
        match result {
            Ok(()) => Ok(Value::Uninitialized),
            Err(Flow::Return(value)) => Ok(value),
            Err(flow) => Err(flow)
        }
    }
    fn output(&mut self, printf: bool, arguments: &[Expression], redirect: &Option<(bool, Expression, Position)>, position: Position) -> Evaluation<()> {
        let mut values = Vec::new();
        for argument in arguments {
            values.push(self.expression(argument)?);
        }
        let text = if printf {
            builtins::format(&values, position)?
        } else {
            if values.is_empty() {
                values.push(self.fields.record.clone());
            }
            values.iter().map(Value::text).collect::<Vec<_>>().join(&self.global("OFS").text()) + &self.global("ORS").text()
        };
        if let Some((append, target, position)) = redirect {
            let name = self.expression(target)?.text();
            if !streams::valid_name(&name) || name == "stdout.txt" || name == "stats.txt" {
                return Err(builtins::error(*position, "invalid output file name").into());
            }
            self.streams.output(Some(&name), *append, &text);
        } else {
            self.streams.output(None, false, &text);
        }
        Ok(())
    }
    fn statement(&mut self, statement: &Statement) -> Evaluation<()> {
        let position = statement.position;
        if !matches!(statement.kind, StmtKind::Block(_) | StmtKind::Empty) {
            *self.preparation.lines.get_mut(&position.line).unwrap() += 1;
        }
        match &statement.kind {
            StmtKind::Block(statements) => for statement in statements {
                self.statement(statement)?;
            },
            StmtKind::Empty => (),
            StmtKind::Expression(expression) => {
                self.expression(expression)?;
            },
            StmtKind::If(condition, yes, no) => if self.expression(condition)?.truth() {
                self.statement(yes)?;
            } else if let Some(no) = no {
                self.statement(no)?;
            },
            StmtKind::While(condition, body) => while self.expression(condition)?.truth() {
                match self.statement(body) {
                    Ok(()) | Err(Flow::Continue) => (),
                    Err(Flow::Break) => break,
                    Err(flow) => return Err(flow)
                }
            },
            StmtKind::Do(body, condition) => loop {
                match self.statement(body) {
                    Ok(()) | Err(Flow::Continue) => (),
                    Err(Flow::Break) => break,
                    Err(flow) => return Err(flow)
                }
                if !self.expression(condition)?.truth() {
                    break;
                }
            },
            StmtKind::For(init, condition, update, body) => {
                if let Some(init) = init {
                    self.expression(init)?;
                }
                loop {
                    if let Some(condition) = condition {
                        if !self.expression(condition)?.truth() {
                            break;
                        }
                    }
                    match self.statement(body) {
                        Ok(()) | Err(Flow::Continue) => (),
                        Err(Flow::Break) => break,
                        Err(flow) => return Err(flow)
                    }
                    if let Some(update) = update {
                        self.expression(update)?;
                    }
                }
            },
            StmtKind::ForIn(variable, vp, array, _, body) => {
                let mut keys: Vec<String> = self.array(array).borrow().keys().cloned().collect();
                keys.sort_by(|a, b| values_fields::key_order(a, b));
                for key in keys {
                    let location = Location::Variable(self.variable(variable), variable.clone());
                    self.store(&location, Value::input(key), *vp)?;
                    match self.statement(body) {
                        Ok(()) | Err(Flow::Continue) => (),
                        Err(Flow::Break) => break,
                        Err(flow) => return Err(flow)
                    }
                }
            },
            StmtKind::Output(printf, arguments, redirect) => self.output(*printf, arguments, redirect, position)?,
            StmtKind::Delete(name, _, indices) => {
                let key = if let Some(indices) = indices {
                    Some(self.key(indices)?)
                } else {
                    None
                };
                let array = self.array(name);
                if let Some(key) = key {
                    array.borrow_mut().remove(&key);
                } else {
                    array.borrow_mut().clear();
                }
            },
            StmtKind::Next => {
                if self.phase == "BEGIN" || self.phase == "END" {
                    return Err(builtins::error(position, "next used in BEGIN or END").into());
                }
                return Err(Flow::Next);
            },
            StmtKind::Break => return Err(Flow::Break),
            StmtKind::Continue => return Err(Flow::Continue),
            StmtKind::Exit(value) => {
                if let Some(value) = value {
                    self.status = self.expression(value)?.number();
                }
                return Err(Flow::Exit);
            },
            StmtKind::Return(value) => return Err(Flow::Return(if let Some(value) = value {
                self.expression(value)?
            } else {
                Value::Uninitialized
            }))
        }
        Ok(())
    }
    fn next_record(&mut self) -> Evaluation<Option<String>> {
        loop {
            if let Some((file, lines, position)) = &mut self.current {
                if *position < lines.len() {
                    let line = lines[*position].clone();
                    *position += 1;
                    self.arguments.files[*file].1 += 1;
                    let nr = self.global("NR").number() + 1;
                    let fnr = self.global("FNR").number() + 1;
                    self.globals.insert("NR".into(), Cell::Scalar(Value::Number(nr)));
                    self.globals.insert("FNR".into(), Cell::Scalar(Value::Number(fnr)));
                    return Ok(Some(line));
                }
            }
            let operand = match self.arguments.operands.get(self.operand) {
                Some(operand) => operand.clone(),
                None => return Ok(None)
            };
            self.operand += 1;
            match operand {
                streams::Operand::Assignment(name, value) => {
                    self.preparation.globals.insert(name.clone());
                    self.globals.insert(name, Cell::Scalar(Value::input(value)));
                },
                streams::Operand::File(name, index) => {
                    self.globals.insert("FILENAME".into(), Cell::Scalar(Value::String(name.clone())));
                    self.globals.insert("FNR".into(), Cell::Scalar(Value::Number(0)));
                    self.current = Some((index, streams::read_file(&name).unwrap(), 0));
                }
            }
        }
    }
    fn execute(&mut self) -> Evaluation<()> {
        for (name, value) in self.arguments.options.clone() {
            self.preparation.globals.insert(name.clone());
            self.globals.insert(name, Cell::Scalar(Value::input(value)));
        }
        let mut exiting = false;
        for i in 0..self.program.rules.len() {
            let rule = self.program.rules[i].clone();
            if rule.kind == "BEGIN" {
                self.rules[i] += 1;
                match self.statement(rule.action.as_ref().unwrap()) {
                    Err(Flow::Exit) => {
                        exiting = true;
                        break;
                    },
                    result => result?
                }
            }
        }
        self.phase = "rules";
        if !exiting && self.program.rules.iter().any(|r| r.kind != "BEGIN") {
            'records: while let Some(record) = self.next_record()? {
                let fs = self.global("FS").text();
                self.fields.set(record, &fs);
                for i in 0..self.program.rules.len() {
                    let rule = self.program.rules[i].clone();
                    if rule.kind == "BEGIN" || rule.kind == "END" {
                        continue;
                    }
                    let tested: Evaluation<bool> = (|| {
                        Ok(if rule.kind == "all" {
                            true
                        } else if rule.kind == "range" {
                            if !self.ranges[i] && self.expression(rule.start.as_ref().unwrap())?.truth() {
                                self.ranges[i] = true;
                            }
                            let matched = self.ranges[i];
                            if matched && self.expression(rule.end.as_ref().unwrap())?.truth() {
                                self.ranges[i] = false;
                            }
                            matched
                        } else {
                            self.expression(rule.start.as_ref().unwrap())?.truth()
                        })
                    })();
                    let matched = match tested {
                        Ok(matched) => matched,
                        Err(Flow::Next) => continue 'records,
                        Err(Flow::Exit) => break 'records,
                        Err(flow) => return Err(flow)
                    };
                    if matched {
                        self.rules[i] += 1;
                        let result = if let Some(action) = &rule.action {
                            self.statement(action)
                        } else {
                            let text = self.fields.record.text() + &self.global("ORS").text();
                            self.streams.output(None, false, &text);
                            Ok(())
                        };
                        match result {
                            Err(Flow::Next) => continue 'records,
                            Err(Flow::Exit) => break 'records,
                            result => result?
                        }
                    }
                }
            }
        }
        self.phase = "END";
        for i in 0..self.program.rules.len() {
            let rule = self.program.rules[i].clone();
            if rule.kind == "END" {
                self.rules[i] += 1;
                match self.statement(rule.action.as_ref().unwrap()) {
                    Err(Flow::Exit) => break,
                    result => result?
                }
            }
        }
        Ok(())
    }
    fn report(&self, status: String) {
        self.streams.save();
        let mut lines = vec![status, "[inputs]".into()];
        for (name, count) in &self.arguments.files {
            lines.push(format!("{} records={}", name, count));
        }
        lines.push("[getline]".into());
        for input in &self.streams.inputs {
            lines.push(if input.opened {
                format!("{} reads={}", input.name, input.reads)
            } else {
                format!("{} missing", input.name)
            });
        }
        lines.push("[rules]".into());
        for (i, rule) in self.program.rules.iter().enumerate() {
            lines.push(format!("{} {} count={}", rule.position.text(), rule.kind, self.rules[i]));
        }
        lines.push("[functions]".into());
        for (i, function) in self.program.functions.iter().enumerate() {
            lines.push(format!("{} calls={} depth={}", function.name, self.calls[i], self.depths[i]));
        }
        lines.push("[outputs]".into());
        lines.push(format!("stdout.txt writes={} bytes={}", self.streams.writes, self.streams.stdout.len()));
        for output in &self.streams.outputs {
            lines.push(format!("{} writes={} bytes={}", output.name, output.writes, output.text.len()));
        }
        lines.push("[lines]".into());
        for (line, count) in &self.preparation.lines {
            lines.push(format!("{} count={}", line, count));
        }
        lines.push("[globals]".into());
        for name in &self.preparation.globals {
            let value = match self.globals.get(name) {
                Some(Cell::Array(array)) => format!("array ({})", array.borrow().len()),
                _ => self.global(name).display()
            };
            lines.push(format!("{} = {}", name, value));
        }
        save_stats(&lines);
    }
}
fn save_stats(lines: &[String]) {
    fs::create_dir_all("output").unwrap();
    fs::write("output/stats.txt", lines.join("\n") + "\n").unwrap();
}
fn failure(status: String) {
    fs::create_dir_all("output").unwrap();
    fs::write("output/stdout.txt", "").unwrap();
    save_stats(&[status]);
}
fn main() {
    let source = fs::read_to_string("input/program.awk").unwrap();
    let program = match lexer::lex(&source).and_then(parser::parse) {
        Ok(program) => program,
        Err(position) => {
            failure(format!("status: syntax error at {}", position.text()));
            return;
        }
    };
    let preparation = match Preparation::analyze(&program) {
        Ok(preparation) => preparation,
        Err((position, message)) => {
            failure(format!("status: error at {}: {}", position.text(), message));
            return;
        }
    };
    let arguments = streams::arguments(&fs::read_to_string("input/args.txt").unwrap());
    let mut runtime = Runtime::new(&program, preparation, arguments);
    let status = match runtime.execute() {
        Err(Flow::Runtime(error)) => format!("status: runtime error at {}: {}", error.position.text(), error.message),
        _ => format!("status: exit {}", runtime.status)
    };
    runtime.report(status);
}
