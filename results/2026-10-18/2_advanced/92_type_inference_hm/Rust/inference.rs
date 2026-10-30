use std::collections::{BTreeMap, BTreeSet};
use crate::lexer::Position;
use crate::parser::{Expression, ExprKind, Group, Pattern, PatternKind};
use crate::unifier::{Type, Scheme, Environment, Unifier, Failure};
pub enum ErrorKind { Message(String), Function(Type), Check(Type, Type, Failure) }
pub struct Error { pub position: Position, pub kind: ErrorKind }
pub struct Local { pub name: String, pub position: Position, pub scheme: Scheme }
pub struct Context { pub unifier: Unifier, pub locals: Vec<Local>, pub matches: BTreeMap<Position, (Type, Vec<Pattern>)> }
impl Context {
    pub fn new() -> Self { Self { unifier: Unifier::new(), locals: Vec::new(), matches: BTreeMap::new() } }
    pub fn clear(&mut self) { self.locals.clear(); self.matches.clear(); }
    fn message(&self, position: Position, message: String) -> Error { Error { position, kind: ErrorKind::Message(message) } }
    fn check(&mut self, expected: &Type, found: &Type, position: Position) -> Result<(), Error> {
        self.unifier.unify(expected, found).map_err(|failure| Error { position, kind: ErrorKind::Check(expected.clone(), found.clone(), failure) })
    }
    pub fn group(&mut self, group: &Group, environment: &Environment, local: bool) -> Result<(Environment, Vec<Scheme>), Error> {
        let mut names = BTreeSet::new();
        for binding in &group.bindings {
            if !names.insert(binding.name.clone()) { return Err(self.message(binding.position, format!("variable '{}' is bound twice in this let", binding.name))); }
            if group.recursive.is_some() && !matches!(&binding.expression.kind, ExprKind::Fun(..)) { return Err(self.message(binding.position, format!("'{}' in let rec must be a function", binding.name))); }
        }
        let mut recursive = environment.clone();
        let mut types = Vec::new();
        if group.recursive.is_some() {
            for binding in &group.bindings { let ty = self.unifier.fresh(); recursive.insert(binding.name.clone(), Scheme::mono(ty.clone())); types.push(ty); }
            for (i, binding) in group.bindings.iter().enumerate() {
                let found = self.expression(&binding.expression, &recursive)?;
                self.check(&types[i], &found, binding.position)?;
            }
        } else { for binding in &group.bindings { types.push(self.expression(&binding.expression, environment)?); } }
        let schemes: Vec<_> = types.into_iter().map(|ty| self.unifier.generalize(ty, environment)).collect();
        let mut result = environment.clone();
        for (binding, scheme) in group.bindings.iter().zip(&schemes) {
            result.insert(binding.name.clone(), scheme.clone());
            if local { self.locals.push(Local { name: binding.name.clone(), position: binding.position, scheme: scheme.clone() }); }
        }
        Ok((result, schemes))
    }
    pub fn expression(&mut self, expression: &Expression, environment: &Environment) -> Result<Type, Error> {
        match &expression.kind {
            ExprKind::Integer(_) => Ok(Type::Integer), ExprKind::Boolean(_) => Ok(Type::Boolean), ExprKind::String(_) => Ok(Type::String),
            ExprKind::Name(name) => if let Some(scheme) = environment.get(name) { Ok(self.unifier.instantiate(scheme)) } else {
                let candidate = environment.keys().map(|candidate| (crate::edit_distance(name, candidate), candidate)).filter(|(distance, _)| *distance <= 2 && *distance < name.len()).min();
                let suffix = candidate.map_or_else(String::new, |(_, candidate)| format!(" (did you mean '{}'?)", candidate));
                Err(self.message(expression.position, format!("unbound variable '{}'{}", name, suffix)))
            },
            ExprKind::Fun(parameter, body) => {
                let argument = self.unifier.fresh(); let mut inner = environment.clone();
                if let Some(name) = &parameter.name { inner.insert(name.clone(), Scheme::mono(argument.clone())); }
                let result = self.expression(body, &inner)?; Ok(Type::function(argument, result))
            },
            ExprKind::Apply(function, argument) => {
                let function_type = self.expression(function, environment)?;
                let (expected, result) = match self.unifier.resolve(&function_type) {
                    Type::Variable(index) => { let a = self.unifier.fresh(); let b = self.unifier.fresh(); self.unifier.bind(index, Type::function(a.clone(), b.clone())); (a, b) },
                    Type::Function(a, b) => (*a, *b),
                    ty => return Err(Error { position: function.position, kind: ErrorKind::Function(ty) })
                };
                let found = self.expression(argument, environment)?; self.check(&expected, &found, argument.position)?; Ok(result)
            },
            ExprKind::Binary(operator, _, left, right) => {
                let (a, b, result) = match operator.as_str() {
                    "+" | "-" | "*" | "/" | "mod" => (Type::Integer, Type::Integer, Type::Integer),
                    "^" => (Type::String, Type::String, Type::String), "&&" | "||" => (Type::Boolean, Type::Boolean, Type::Boolean),
                    "::" => { let a = self.unifier.fresh(); (a.clone(), Type::list(a.clone()), Type::list(a)) },
                    _ => { let a = self.unifier.fresh(); (a.clone(), a, Type::Boolean) }
                };
                let found = self.expression(left, environment)?; self.check(&a, &found, left.position)?;
                let found = self.expression(right, environment)?; self.check(&b, &found, right.position)?; Ok(result)
            },
            ExprKind::Negate(_, value) => { let found = self.expression(value, environment)?; self.check(&Type::Integer, &found, value.position)?; Ok(Type::Integer) },
            ExprKind::If(condition, yes, no) => {
                let found = self.expression(condition, environment)?; self.check(&Type::Boolean, &found, condition.position)?;
                let yes_type = self.expression(yes, environment)?; let no_type = self.expression(no, environment)?;
                self.check(&yes_type, &no_type, no.position)?; Ok(yes_type)
            },
            ExprKind::Pair(a, b) => { let a = self.expression(a, environment)?; let b = self.expression(b, environment)?; Ok(Type::pair(a, b)) },
            ExprKind::List(elements) => {
                let ty = self.unifier.fresh();
                for value in elements { let found = self.expression(value, environment)?; self.check(&ty, &found, value.position)?; }
                Ok(Type::list(ty))
            },
            ExprKind::Match(value, arms) => {
                let ty = self.expression(value, environment)?; let result = self.unifier.fresh();
                for (pattern, body) in arms {
                    let mut bindings = BTreeMap::new(); let found = self.pattern(pattern, &mut bindings)?;
                    self.check(&ty, &found, pattern.position)?;
                    let mut inner = environment.clone();
                    for (name, ty) in bindings { inner.insert(name, Scheme::mono(ty)); }
                    let found = self.expression(body, &inner)?; self.check(&result, &found, body.position)?;
                }
                self.matches.insert(expression.position, (ty, arms.iter().map(|(pattern, _)| pattern.clone()).collect()));
                Ok(result)
            },
            ExprKind::Let(group, body) => { let (inner, _) = self.group(group, environment, true)?; self.expression(body, &inner) }
        }
    }
    fn pattern(&mut self, pattern: &Pattern, bindings: &mut BTreeMap<String, Type>) -> Result<Type, Error> {
        match &pattern.kind {
            PatternKind::Wildcard => Ok(self.unifier.fresh()),
            PatternKind::Name(name) => {
                if bindings.contains_key(name) { return Err(self.message(pattern.position, format!("variable '{}' is bound twice in this pattern", name))); }
                let ty = self.unifier.fresh(); bindings.insert(name.clone(), ty.clone()); Ok(ty)
            },
            PatternKind::Integer(_) => Ok(Type::Integer), PatternKind::Boolean(_) => Ok(Type::Boolean), PatternKind::String(_) => Ok(Type::String),
            PatternKind::Nil => Ok(Type::list(self.unifier.fresh())),
            PatternKind::Cons(a, b) => {
                let ty = self.unifier.fresh(); let head = self.pattern(a, bindings)?; self.check(&ty, &head, a.position)?;
                let tail = self.pattern(b, bindings)?; let list = Type::list(ty); self.check(&list, &tail, b.position)?; Ok(list)
            },
            PatternKind::List(elements) => {
                let ty = self.unifier.fresh();
                for element in elements { let found = self.pattern(element, bindings)?; self.check(&ty, &found, element.position)?; }
                Ok(Type::list(ty))
            },
            PatternKind::Pair(a, b) => { let a = self.pattern(a, bindings)?; let b = self.pattern(b, bindings)?; Ok(Type::pair(a, b)) }
        }
    }
}
