use std::cell::RefCell;
use std::cmp::Ordering;
use std::collections::BTreeMap;
use std::rc::Rc;
use crate::lexer::Position;
use crate::parser::{Expression, ExprKind, Parameter, Pattern, PatternKind, Group};
#[derive(Clone)]
pub enum Value { Integer(i64), Boolean(bool), String(String), Pair(Box<Value>, Box<Value>), List(Vec<Value>), Closure(Rc<Closure>), Builtin(String) }
pub type Environment = BTreeMap<String, Value>;
pub struct Closure { parameter: Parameter, body: Expression, environment: Rc<RefCell<Environment>> }
pub struct Error { pub position: Position, pub message: String }
pub struct Evaluator { pub calls: usize }
fn error(position: Position, message: &str) -> Error { Error { position, message: message.into() } }
fn integer(value: i64, position: Position) -> Result<Value, Error> {
    if (-2147483648..=2147483647).contains(&value) { Ok(Value::Integer(value)) } else { Err(error(position, "integer overflow")) }
}
fn compare(a: &Value, b: &Value, position: Position) -> Result<Ordering, Error> {
    match (a, b) {
        (Value::Integer(a), Value::Integer(b)) => Ok(a.cmp(b)), (Value::Boolean(a), Value::Boolean(b)) => Ok(a.cmp(b)),
        (Value::String(a), Value::String(b)) => Ok(a.cmp(b)),
        (Value::Pair(a, b), Value::Pair(c, d)) => { let first = compare(a, c, position)?; if first.is_eq() { compare(b, d, position) } else { Ok(first) } },
        (Value::List(a), Value::List(b)) => {
            for (a, b) in a.iter().zip(b) { let order = compare(a, b, position)?; if !order.is_eq() { return Ok(order); } }
            Ok(a.len().cmp(&b.len()))
        },
        _ => Err(error(position, "functional value compared"))
    }
}
fn matches(pattern: &Pattern, value: &Value, bindings: &mut Environment) -> bool {
    match (&pattern.kind, value) {
        (PatternKind::Wildcard, _) => true,
        (PatternKind::Name(name), _) => { bindings.insert(name.clone(), value.clone()); true },
        (PatternKind::Integer(a), Value::Integer(b)) => a == b,
        (PatternKind::Boolean(a), Value::Boolean(b)) => a == b,
        (PatternKind::String(a), Value::String(b)) => a == b,
        (PatternKind::Nil, Value::List(values)) => values.is_empty(),
        (PatternKind::Cons(a, b), Value::List(values)) => !values.is_empty() && matches(a, &values[0], bindings) && matches(b, &Value::List(values[1..].to_vec()), bindings),
        (PatternKind::List(patterns), Value::List(values)) => patterns.len() == values.len() && patterns.iter().zip(values).all(|(p, v)| matches(p, v, bindings)),
        (PatternKind::Pair(a, b), Value::Pair(c, d)) => matches(a, c, bindings) && matches(b, d, bindings),
        _ => false
    }
}
impl Evaluator {
    pub fn group(&mut self, group: &Group, environment: &Environment) -> Result<(Environment, Vec<Value>), Error> {
        let mut values = Vec::new();
        if group.recursive.is_some() {
            let shared = Rc::new(RefCell::new(environment.clone()));
            for binding in &group.bindings {
                if let ExprKind::Fun(parameter, body) = &binding.expression.kind {
                    values.push(Value::Closure(Rc::new(Closure { parameter: parameter.clone(), body: body.clone(), environment: shared.clone() })));
                }
            }
            for (binding, value) in group.bindings.iter().zip(&values) { shared.borrow_mut().insert(binding.name.clone(), value.clone()); }
            let result = shared.borrow().clone();
            Ok((result, values))
        } else {
            for binding in &group.bindings { values.push(self.expression(&binding.expression, environment)?); }
            let mut result = environment.clone();
            for (binding, value) in group.bindings.iter().zip(&values) { result.insert(binding.name.clone(), value.clone()); }
            Ok((result, values))
        }
    }
    fn apply(&mut self, function: Value, argument: Value, position: Position) -> Result<Value, Error> {
        self.calls += 1;
        match function {
            Value::Closure(closure) => {
                let mut environment = closure.environment.borrow().clone();
                if let Some(name) = &closure.parameter.name { environment.insert(name.clone(), argument); }
                self.expression(&closure.body, &environment)
            },
            Value::Builtin(name) => match (name.as_str(), argument) {
                ("fst", Value::Pair(a, _)) => Ok(*a), ("snd", Value::Pair(_, b)) => Ok(*b),
                ("not", Value::Boolean(value)) => Ok(Value::Boolean(!value)),
                ("string_of_int", Value::Integer(value)) => Ok(Value::String(value.to_string())),
                ("failwith", Value::String(value)) => Err(Error { position, message: format!("failure {}", crate::quote(&value)) }),
                _ => unreachable!()
            },
            _ => unreachable!()
        }
    }
    pub fn expression(&mut self, expression: &Expression, environment: &Environment) -> Result<Value, Error> {
        match &expression.kind {
            ExprKind::Integer(value) => Ok(Value::Integer(*value)), ExprKind::Boolean(value) => Ok(Value::Boolean(*value)),
            ExprKind::String(value) => Ok(Value::String(value.clone())), ExprKind::Name(name) => Ok(environment[name].clone()),
            ExprKind::Fun(parameter, body) => Ok(Value::Closure(Rc::new(Closure { parameter: parameter.clone(), body: body.clone(), environment: Rc::new(RefCell::new(environment.clone())) }))),
            ExprKind::Apply(function, argument) => { let function = self.expression(function, environment)?; let argument = self.expression(argument, environment)?; self.apply(function, argument, expression.position) },
            ExprKind::Negate(position, value) => { if let Value::Integer(value) = self.expression(value, environment)? { integer(-value, *position) } else { unreachable!() } },
            ExprKind::Binary(operator, position, a, b) => {
                let left = self.expression(a, environment)?;
                if operator == "&&" { if let Value::Boolean(value) = left { return if value { self.expression(b, environment) } else { Ok(Value::Boolean(false)) }; } }
                if operator == "||" { if let Value::Boolean(value) = left { return if value { Ok(Value::Boolean(true)) } else { self.expression(b, environment) }; } }
                let right = self.expression(b, environment)?;
                match operator.as_str() {
                    "+" | "-" | "*" | "/" | "mod" => if let (Value::Integer(a), Value::Integer(b)) = (left, right) {
                        if (operator == "/" || operator == "mod") && b == 0 { return Err(error(*position, "division by zero")); }
                        let value = match operator.as_str() { "+" => a + b, "-" => a - b, "*" => a * b, "/" => a / b, _ => a - b * (a / b) };
                        integer(value, *position)
                    } else { unreachable!() },
                    "^" => if let (Value::String(a), Value::String(b)) = (left, right) { Ok(Value::String(a + &b)) } else { unreachable!() },
                    "::" => if let Value::List(mut values) = right { values.insert(0, left); Ok(Value::List(values)) } else { unreachable!() },
                    _ => { let order = compare(&left, &right, *position)?; let value = match operator.as_str() { "=" => order.is_eq(), "<>" => !order.is_eq(), "<" => order.is_lt(), ">" => order.is_gt(), "<=" => order.is_le(), _ => order.is_ge() }; Ok(Value::Boolean(value)) }
                }
            },
            ExprKind::If(condition, yes, no) => if let Value::Boolean(value) = self.expression(condition, environment)? { self.expression(if value { yes } else { no }, environment) } else { unreachable!() },
            ExprKind::Pair(a, b) => { let a = self.expression(a, environment)?; let b = self.expression(b, environment)?; Ok(Value::Pair(Box::new(a), Box::new(b))) },
            ExprKind::List(elements) => { let mut values = Vec::new(); for element in elements { values.push(self.expression(element, environment)?); } Ok(Value::List(values)) },
            ExprKind::Match(value, arms) => {
                let value = self.expression(value, environment)?;
                for (pattern, body) in arms { let mut bindings = BTreeMap::new(); if matches(pattern, &value, &mut bindings) { let mut inner = environment.clone(); inner.extend(bindings); return self.expression(body, &inner); } }
                Err(error(expression.position, "match failure"))
            },
            ExprKind::Let(group, body) => { let (inner, _) = self.group(group, environment)?; self.expression(body, &inner) }
        }
    }
}
