mod lexer;
mod parser;
mod unifier;
mod inference;
mod evaluator;
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use lexer::Position;
use parser::{Expression, ExprKind, Pattern, PatternKind, Group, Item, TypeExpression};
use unifier::{Type, Scheme, Unifier};
pub fn quote(value: &str) -> String {
    let mut out = String::from("\"");
    for c in value.chars() { match c { '\\' => out.push_str("\\\\"), '"' => out.push_str("\\\""), '\n' => out.push_str("\\n"), '\t' => out.push_str("\\t"), _ => out.push(c) } }
    out.push('"'); out
}
fn value_string(value: &evaluator::Value) -> String {
    use evaluator::Value;
    match value { Value::Integer(value) => value.to_string(), Value::Boolean(value) => value.to_string(), Value::String(value) => quote(value), Value::Pair(a, b) => format!("({}, {})", value_string(a), value_string(b)), Value::List(values) => format!("[{}]", values.iter().map(value_string).collect::<Vec<_>>().join("; ")), _ => "<fun>".into() }
}
pub fn edit_distance(a: &str, b: &str) -> usize {
    let mut row: Vec<_> = (0..=b.len()).collect();
    for (i, a) in a.bytes().enumerate() {
        let mut next = vec![i + 1];
        for (j, b) in b.bytes().enumerate() { next.push((next[j] + 1).min(row[j + 1] + 1).min(row[j] + usize::from(a != b))); }
        row = next;
    }
    row[b.len()]
}
struct TypePrinter<'a> { unifier: &'a Unifier, names: BTreeMap<usize, String>, quantified: Option<&'a BTreeSet<usize>> }
impl<'a> TypePrinter<'a> {
    fn new(unifier: &'a Unifier, quantified: Option<&'a BTreeSet<usize>>) -> Self { Self { unifier, names: BTreeMap::new(), quantified } }
    fn write(&mut self, ty: &Type) -> String {
        match self.unifier.resolve(ty) {
            Type::Integer => "int".into(), Type::Boolean => "bool".into(), Type::String => "string".into(),
            Type::Variable(index) => {
                if let Some(name) = self.names.get(&index) { return name.clone(); }
                let k = self.names.len();
                let suffix = if k >= 26 { (k / 26).to_string() } else { String::new() };
                let weak = self.quantified.map_or(false, |quantified| !quantified.contains(&index));
                let name = format!("'{}{}{}", if weak { "_" } else { "" }, (b'a' + (k % 26) as u8) as char, suffix);
                self.names.insert(index, name.clone()); name
            },
            Type::List(element) => { let written = self.write(&element); format!("{} list", if matches!(*element, Type::Pair(..) | Type::Function(..)) { format!("({})", written) } else { written }) },
            Type::Pair(a, b) => {
                let left = self.write(&a); let right = self.write(&b);
                format!("{} * {}", if matches!(*a, Type::Pair(..) | Type::Function(..)) { format!("({})", left) } else { left }, if matches!(*b, Type::Pair(..) | Type::Function(..)) { format!("({})", right) } else { right })
            },
            Type::Function(a, b) => { let left = self.write(&a); let right = self.write(&b); format!("{} -> {}", if matches!(*a, Type::Function(..)) { format!("({})", left) } else { left }, right) }
        }
    }
}
fn error_message(error: &inference::Error, unifier: &Unifier) -> String {
    use inference::ErrorKind;
    let mut printer = TypePrinter::new(unifier, None);
    match &error.kind {
        ErrorKind::Message(message) => message.clone(), ErrorKind::Function(ty) => format!("expected a function but found {}", printer.write(ty)),
        ErrorKind::Check(expected, found, failure) => {
            let mut message = format!("expected {} but found {}", printer.write(expected), printer.write(found));
            if failure.occurs {
                let (variable, other) = if matches!(failure.expected, Type::Variable(_)) { (&failure.expected, &failure.found) } else { (&failure.found, &failure.expected) };
                message.push_str(&format!(" (infinite type {} = {})", printer.write(variable), printer.write(other)));
            } else if failure.nested { message.push_str(&format!(" ({} vs {})", printer.write(&failure.expected), printer.write(&failure.found))); }
            message
        }
    }
}
fn signature_type(expression: &TypeExpression, unifier: &mut Unifier, variables: &mut BTreeMap<String, Type>) -> Type {
    match expression {
        TypeExpression::Primitive(name) => match name.as_str() { "int" => Type::Integer, "bool" => Type::Boolean, _ => Type::String },
        TypeExpression::Variable(name) => { if let Some(ty) = variables.get(name) { ty.clone() } else { let ty = unifier.fresh(); variables.insert(name.clone(), ty.clone()); ty } },
        TypeExpression::List(ty) => Type::list(signature_type(ty, unifier, variables)),
        TypeExpression::Pair(a, b) => { let a = signature_type(a, unifier, variables); let b = signature_type(b, unifier, variables); Type::pair(a, b) },
        TypeExpression::Function(a, b) => { let a = signature_type(a, unifier, variables); let b = signature_type(b, unifier, variables); Type::function(a, b) }
    }
}
fn signature_matches(inferred: &Type, declared: &Type, unifier: &Unifier, assigned: &mut BTreeMap<usize, Type>) -> bool {
    let inferred = unifier.resolve(inferred);
    let declared = unifier.resolve(declared);
    match inferred {
        Type::Variable(index) => if let Some(old) = assigned.get(&index) { *old == declared } else { assigned.insert(index, declared); true },
        Type::List(a) => if let Type::List(b) = declared { signature_matches(&a, &b, unifier, assigned) } else { false },
        Type::Pair(a, b) => if let Type::Pair(c, d) = declared { signature_matches(&a, &c, unifier, assigned) && signature_matches(&b, &d, unifier, assigned) } else { false },
        Type::Function(a, b) => if let Type::Function(c, d) = declared { signature_matches(&a, &c, unifier, assigned) && signature_matches(&b, &d, unifier, assigned) } else { false },
        _ => inferred == declared
    }
}
fn type_syntax(ty: &TypeExpression) -> String {
    match ty {
        TypeExpression::Primitive(name) | TypeExpression::Variable(name) => name.clone(),
        TypeExpression::List(ty) => { let value = type_syntax(ty); format!("{} list", if matches!(ty.as_ref(), TypeExpression::Pair(..) | TypeExpression::Function(..)) { format!("({})", value) } else { value }) },
        TypeExpression::Pair(a, b) => { let a_text = type_syntax(a); let b_text = type_syntax(b); format!("{} * {}", if matches!(a.as_ref(), TypeExpression::Pair(..) | TypeExpression::Function(..)) { format!("({})", a_text) } else { a_text }, if matches!(b.as_ref(), TypeExpression::Pair(..) | TypeExpression::Function(..)) { format!("({})", b_text) } else { b_text }) },
        TypeExpression::Function(a, b) => { let a_text = type_syntax(a); format!("{} -> {}", if matches!(a.as_ref(), TypeExpression::Function(..)) { format!("({})", a_text) } else { a_text }, type_syntax(b)) }
    }
}
fn pattern_string(pattern: &Pattern) -> String {
    match &pattern.kind {
        PatternKind::Wildcard => "_".into(), PatternKind::Name(name) => name.clone(), PatternKind::Integer(value) => value.to_string(), PatternKind::Boolean(value) => value.to_string(), PatternKind::String(value) => quote(value), PatternKind::Nil => "[]".into(),
        PatternKind::List(values) => format!("[{}]", values.iter().map(pattern_string).collect::<Vec<_>>().join("; ")),
        PatternKind::Pair(a, b) => format!("({}, {})", pattern_string(a), pattern_string(b)),
        PatternKind::Cons(a, b) => { let head = pattern_string(a); format!("{} :: {}", if matches!(&a.kind, PatternKind::Cons(..)) { format!("({})", head) } else { head }, pattern_string(b)) }
    }
}
fn group_string(group: &Group) -> String {
    let bindings: Vec<_> = group.bindings.iter().map(|binding| {
        let mut body = binding.expression.clone(); let mut names = vec![binding.name.clone()];
        while let ExprKind::Fun(parameter, next) = &body.kind { names.push(parameter.name.clone().unwrap_or_else(|| "_".into())); body = next.clone(); }
        format!("{} = {}", names.join(" "), expression_string(&body, 0))
    }).collect();
    format!("let {}{}", if group.recursive.is_some() { "rec " } else { "" }, bindings.join(" and "))
}
fn ends_in_match(expression: &Expression) -> bool {
    match &expression.kind { ExprKind::Match(..) => true, ExprKind::Let(_, body) | ExprKind::Fun(_, body) => ends_in_match(body), ExprKind::If(_, _, no) => ends_in_match(no), _ => false }
}
fn expression_string(expression: &Expression, required: usize) -> String {
    let (strength, text) = match &expression.kind {
        ExprKind::Integer(value) => (9, value.to_string()), ExprKind::Boolean(value) => (9, value.to_string()), ExprKind::String(value) => (9, quote(value)), ExprKind::Name(name) => (9, name.clone()),
        ExprKind::Fun(..) => {
            let mut body = expression.clone(); let mut parameters = Vec::new();
            while let ExprKind::Fun(parameter, next) = &body.kind { parameters.push(parameter.name.clone().unwrap_or_else(|| "_".into())); body = next.clone(); }
            (0, format!("fun {} -> {}", parameters.join(" "), expression_string(&body, 0)))
        },
        ExprKind::Apply(function, argument) => (8, format!("{} {}", expression_string(function, 8), expression_string(argument, 9))),
        ExprKind::Binary(operator, _, left, right) => { let p = parser::precedence(operator); let right_associative = parser::right_associative(operator); (p, format!("{} {} {}", expression_string(left, p + usize::from(right_associative)), operator, expression_string(right, p + usize::from(!right_associative)))) },
        ExprKind::Negate(_, value) => (7, format!("-{}", expression_string(value, 7))),
        ExprKind::If(condition, yes, no) => (0, format!("if {} then {} else {}", expression_string(condition, 0), expression_string(yes, 0), expression_string(no, 0))),
        ExprKind::Pair(a, b) => (9, format!("({}, {})", expression_string(a, 0), expression_string(b, 0))),
        ExprKind::List(values) => (9, format!("[{}]", values.iter().map(|value| expression_string(value, 0)).collect::<Vec<_>>().join("; "))),
        ExprKind::Let(group, body) => (0, format!("{} in {}", group_string(group), expression_string(body, 0))),
        ExprKind::Match(value, arms) => {
            let arms: Vec<_> = arms.iter().enumerate().map(|(i, (pattern, body))| { let body_text = expression_string(body, 0); format!("{} -> {}", pattern_string(pattern), if i + 1 < arms.len() && ends_in_match(body) { format!("({})", body_text) } else { body_text }) }).collect();
            (0, format!("match {} with {}", expression_string(value, 0), arms.join(" | ")))
        }
    };
    if strength < required { format!("({})", text) } else { text }
}
fn item_string(item: &Item) -> String { match item { Item::Signature(name, _, ty) => format!("val {} : {};;", name, type_syntax(ty)), Item::Declaration(group) => format!("{};;", group_string(group)), Item::Expression(expression) => format!("{};;", expression_string(expression, 0)) } }

#[derive(Clone)]
enum Cover { Wild, Constructor(String, Vec<Cover>) }
fn cover(pattern: &Pattern) -> Cover {
    fn list(values: &[Pattern]) -> Cover {
        if values.is_empty() { Cover::Constructor("nil".into(), Vec::new()) }
        else { Cover::Constructor("cons".into(), vec![cover(&values[0]), list(&values[1..])]) }
    }
    match &pattern.kind {
        PatternKind::Wildcard | PatternKind::Name(_) => Cover::Wild,
        PatternKind::Integer(value) => Cover::Constructor(format!("i{}", value), Vec::new()),
        PatternKind::String(value) => Cover::Constructor(format!("s{}", quote(value)), Vec::new()),
        PatternKind::Boolean(value) => Cover::Constructor(value.to_string(), Vec::new()),
        PatternKind::Nil => Cover::Constructor("nil".into(), Vec::new()),
        PatternKind::Cons(a, b) => Cover::Constructor("cons".into(), vec![cover(a), cover(b)]),
        PatternKind::Pair(a, b) => Cover::Constructor("pair".into(), vec![cover(a), cover(b)]),
        PatternKind::List(values) => list(values)
    }
}
fn constructor_arguments(ty: &Type, name: &str) -> Vec<Type> {
    match ty { Type::List(element) if name == "cons" => vec![element.as_ref().clone(), ty.clone()], Type::Pair(a, b) => vec![a.as_ref().clone(), b.as_ref().clone()], _ => Vec::new() }
}
fn specialize(matrix: &[Vec<Cover>], name: &str, arity: usize) -> Vec<Vec<Cover>> {
    let mut result = Vec::new();
    for row in matrix {
        let prefix = match &row[0] { Cover::Wild => vec![Cover::Wild; arity], Cover::Constructor(constructor, arguments) if constructor == name => arguments.clone(), _ => continue };
        let mut next = prefix; next.extend_from_slice(&row[1..]); result.push(next);
    }
    result
}
fn useful(matrix: &[Vec<Cover>], vector: &[Cover], types: &[Type]) -> bool {
    if vector.is_empty() { return matrix.is_empty(); }
    if let Cover::Constructor(name, arguments) = &vector[0] {
        let mut next = arguments.clone(); next.extend_from_slice(&vector[1..]);
        let mut next_types = constructor_arguments(&types[0], name); next_types.extend_from_slice(&types[1..]);
        return useful(&specialize(matrix, name, arguments.len()), &next, &next_types);
    }
    let family: Vec<&str> = match &types[0] { Type::Boolean => vec!["false", "true"], Type::List(_) => vec!["nil", "cons"], Type::Pair(..) => vec!["pair"], _ => Vec::new() };
    let present: BTreeSet<_> = matrix.iter().filter_map(|row| if let Cover::Constructor(name, _) = &row[0] { Some(name.as_str()) } else { None }).collect();
    if !family.is_empty() && family.iter().all(|name| present.contains(name)) {
        for name in family {
            let mut arguments = constructor_arguments(&types[0], name);
            let arity = arguments.len(); arguments.extend_from_slice(&types[1..]);
            let mut next = vec![Cover::Wild; arity]; next.extend_from_slice(&vector[1..]);
            if useful(&specialize(matrix, name, arity), &next, &arguments) { return true; }
        }
        false
    } else {
        let defaults: Vec<_> = matrix.iter().filter(|row| matches!(row[0], Cover::Wild)).map(|row| row[1..].to_vec()).collect();
        useful(&defaults, &vector[1..], &types[1..])
    }
}
type Scope = BTreeMap<String, Position>;
#[derive(Clone)]
struct Reference { target: Position, tail: bool }
fn pattern_names(pattern: &Pattern) -> Vec<(String, Position)> {
    match &pattern.kind {
        PatternKind::Name(name) => vec![(name.clone(), pattern.position)],
        PatternKind::Cons(a, b) | PatternKind::Pair(a, b) => { let mut names = pattern_names(a); names.extend(pattern_names(b)); names },
        PatternKind::List(values) => values.iter().flat_map(pattern_names).collect(),
        _ => Vec::new()
    }
}
fn pure_references(expression: &Expression, scope: &Scope, tail: bool) -> Vec<Reference> {
    match &expression.kind {
        ExprKind::Name(name) => scope.get(name).map_or_else(Vec::new, |&target| vec![Reference { target, tail: false }]),
        ExprKind::Fun(parameter, body) => { let mut inner = scope.clone(); if let Some(name) = &parameter.name { inner.insert(name.clone(), parameter.position); } pure_references(body, &inner, false) },
        ExprKind::Apply(..) => {
            let mut head = expression.clone(); let mut arguments = Vec::new();
            while let ExprKind::Apply(function, argument) = &head.kind { arguments.push(argument.clone()); head = function.clone(); }
            arguments.reverse();
            let mut references = if let ExprKind::Name(name) = &head.kind { scope.get(name).map_or_else(Vec::new, |&target| vec![Reference { target, tail }]) } else { pure_references(&head, scope, false) };
            for argument in arguments { references.extend(pure_references(&argument, scope, false)); }
            references
        },
        ExprKind::Binary(operator, _, a, b) => { let mut references = pure_references(a, scope, false); references.extend(pure_references(b, scope, tail && (operator == "&&" || operator == "||"))); references },
        ExprKind::Negate(_, body) => pure_references(body, scope, false),
        ExprKind::If(condition, yes, no) => { let mut references = pure_references(condition, scope, false); references.extend(pure_references(yes, scope, tail)); references.extend(pure_references(no, scope, tail)); references },
        ExprKind::Pair(a, b) => { let mut references = pure_references(a, scope, false); references.extend(pure_references(b, scope, false)); references },
        ExprKind::List(values) => values.iter().flat_map(|value| pure_references(value, scope, false)).collect(),
        ExprKind::Match(value, arms) => {
            let mut references = pure_references(value, scope, false);
            for (pattern, body) in arms { let mut inner = scope.clone(); inner.extend(pattern_names(pattern)); references.extend(pure_references(body, &inner, tail)); }
            references
        },
        ExprKind::Let(group, body) => {
            let mut inner = scope.clone(); for binding in &group.bindings { inner.insert(binding.name.clone(), binding.position); }
            let rhs_scope = if group.recursive.is_some() { &inner } else { scope };
            let mut references: Vec<_> = group.bindings.iter().flat_map(|binding| pure_references(&binding.expression, rhs_scope, false)).collect();
            references.extend(pure_references(body, &inner, tail)); references
        },
        _ => Vec::new()
    }
}
struct Inspection { warnings: Vec<(Position, usize, String)>, classifications: BTreeMap<Position, &'static str>, candidates: BTreeMap<Position, String> }
impl Inspection {
    fn new() -> Self { Self { warnings: Vec::new(), classifications: BTreeMap::new(), candidates: BTreeMap::new() } }
    fn group(&mut self, group: &Group, scope: &Scope, top: bool, context: &inference::Context) -> Scope {
        let mut inner = scope.clone();
        for binding in &group.bindings {
            inner.insert(binding.name.clone(), binding.position);
            if !top { self.candidates.insert(binding.position, binding.name.clone()); }
        }
        let rhs_scope = if group.recursive.is_some() { &inner } else { scope };
        for binding in &group.bindings { self.walk(&binding.expression, rhs_scope, context); }
        if let Some(position) = group.recursive {
            let names: BTreeSet<_> = group.bindings.iter().map(|binding| binding.position).collect();
            let references: Vec<_> = group.bindings.iter().flat_map(|binding| pure_references(&binding.expression, &inner, false)).collect();
            if references.iter().all(|reference| !names.contains(&reference.target)) { self.warnings.push((position, 3, "unused rec flag".into())); }
            for binding in &group.bindings {
                let mut body = binding.expression.clone(); let mut body_scope = inner.clone();
                while let ExprKind::Fun(parameter, next) = &body.kind { if let Some(name) = &parameter.name { body_scope.insert(name.clone(), parameter.position); } body = next.clone(); }
                let references: Vec<_> = pure_references(&body, &body_scope, true).into_iter().filter(|reference| names.contains(&reference.target)).collect();
                if !references.is_empty() { self.classifications.insert(binding.position, if references.iter().all(|reference| reference.tail) { "tail recursive" } else { "recursive" }); }
            }
        }
        inner
    }
    fn walk(&mut self, expression: &Expression, scope: &Scope, context: &inference::Context) {
        match &expression.kind {
            ExprKind::Fun(parameter, body) => {
                let mut inner = scope.clone();
                if let Some(name) = &parameter.name { self.candidates.insert(parameter.position, name.clone()); inner.insert(name.clone(), parameter.position); }
                self.walk(body, &inner, context);
            },
            ExprKind::Apply(a, b) | ExprKind::Pair(a, b) | ExprKind::Binary(_, _, a, b) => { self.walk(a, scope, context); self.walk(b, scope, context); },
            ExprKind::Negate(_, body) => self.walk(body, scope, context),
            ExprKind::If(condition, yes, no) => { self.walk(condition, scope, context); self.walk(yes, scope, context); self.walk(no, scope, context); },
            ExprKind::List(values) => { for value in values { self.walk(value, scope, context); } },
            ExprKind::Let(group, body) => { let inner = self.group(group, scope, false, context); self.walk(body, &inner, context); },
            ExprKind::Match(value, arms) => {
                let (ty, patterns) = &context.matches[&expression.position];
                let ty = context.unifier.resolve(ty);
                let mut matrix = Vec::new();
                for (i, pattern) in patterns.iter().enumerate() {
                    let candidate = cover(pattern);
                    if i > 0 && !useful(&matrix, &[candidate.clone()], &[ty.clone()]) { self.warnings.push((pattern.position, 2, "this match case is unused".into())); }
                    matrix.push(vec![candidate]);
                }
                if useful(&matrix, &[Cover::Wild], &[ty]) { self.warnings.push((expression.position, 1, "this match is not exhaustive".into())); }
                self.walk(value, scope, context);
                for (pattern, body) in arms {
                    let mut inner = scope.clone();
                    for (name, position) in pattern_names(pattern) { self.candidates.insert(position, name.clone()); inner.insert(name, position); }
                    self.walk(body, &inner, context);
                }
            },
            _ => ()
        }
    }
    fn finish(&mut self, references: Vec<Reference>) {
        let used: BTreeSet<_> = references.into_iter().map(|reference| reference.target).collect();
        for (&position, name) in &self.candidates { if !name.starts_with('_') && !used.contains(&position) { self.warnings.push((position, 4, format!("unused variable '{}'", name))); } }
        self.warnings.sort_by_key(|warning| (warning.0, warning.1));
    }
}
fn inspection(item: &Item, scope: &Scope, context: &inference::Context) -> Inspection {
    let mut inspection = Inspection::new();
    let references = match item {
        Item::Declaration(group) => { let inner = inspection.group(group, scope, true, context); group.bindings.iter().flat_map(|binding| pure_references(&binding.expression, if group.recursive.is_some() { &inner } else { scope }, false)).collect() },
        Item::Expression(expression) => { inspection.walk(expression, scope, context); pure_references(expression, scope, false) },
        _ => Vec::new()
    };
    inspection.finish(references); inspection
}

fn builtins(unifier: &mut Unifier) -> (unifier::Environment, evaluator::Environment) {
    let mut types = BTreeMap::new();
    let a = unifier.fresh(); let b = unifier.fresh();
    let fst = Type::function(Type::pair(a.clone(), b), a);
    types.insert("fst".into(), Scheme { quantified: unifier.variables(&fst), ty: fst });
    let a = unifier.fresh(); let b = unifier.fresh();
    let snd = Type::function(Type::pair(a, b.clone()), b);
    types.insert("snd".into(), Scheme { quantified: unifier.variables(&snd), ty: snd });
    types.insert("not".into(), Scheme::mono(Type::function(Type::Boolean, Type::Boolean)));
    types.insert("string_of_int".into(), Scheme::mono(Type::function(Type::Integer, Type::String)));
    let result = unifier.fresh();
    let failwith = Type::function(Type::String, result);
    types.insert("failwith".into(), Scheme { quantified: unifier.variables(&failwith), ty: failwith });
    let values = ["fst", "snd", "not", "string_of_int", "failwith"].iter().map(|name| (name.to_string(), evaluator::Value::Builtin(name.to_string()))).collect();
    (types, values)
}
#[derive(Clone)]
struct Signature { position: Position, ty: TypeExpression }
fn report(position: Position, kind: &str, message: &str, sources: &[Vec<String>], output: &mut Vec<String>) {
    let name = ["prelude.ml", "program.ml"][position.file];
    output.push(format!("{}:{}:{}: {}: {}", name, position.line, position.column, kind, message));
    if position.line <= sources[position.file].len() {
        output.push(format!("    {}", sources[position.file][position.line - 1]));
        output.push(format!("{}^", " ".repeat(position.column + 3)));
    }
}
fn write(name: &str, lines: &[String]) {
    fs::create_dir_all("output").unwrap();
    fs::write(format!("output/{}", name), if lines.is_empty() { String::new() } else { lines.join("\n") + "\n" }).unwrap();
}
fn main() {
    let file_names = ["prelude.ml", "program.ml"];
    let texts: Vec<_> = file_names.iter().map(|name| fs::read_to_string(format!("input/{}", name)).unwrap()).collect();
    let sources: Vec<Vec<String>> = texts.iter().map(|text| text.lines().map(str::to_string).collect()).collect();
    let mut context = inference::Context::new();
    let (mut type_environment, mut value_environment) = builtins(&mut context.unifier);
    let mut evaluator = evaluator::Evaluator { calls: 0 };
    let mut scope = Scope::new();
    let (mut types, mut values, mut errors, mut formatted) = (Vec::new(), Vec::new(), Vec::new(), Vec::new());
    let mut statistics = [[0usize; 7]; 2];
    for file in 0..2 {
        types.push(format!("== {} ==", file_names[file])); values.push(format!("== {} ==", file_names[file])); formatted.push(format!("(* {} *)", file_names[file]));
        let mut pending: BTreeMap<String, Signature> = BTreeMap::new();
        let mut parser = parser::Parser { tokens: lexer::lex(&texts[file], file), index: 0 };
        evaluator.calls = 0;
        while parser.peek().kind != "eof" {
            statistics[file][0] += 1;
            let item = match parser.item() {
                Ok(item) => item,
                Err(token) => {
                    let message = if token.kind == "invalid" { token.value.clone() } else if token.kind == "eof" { "unexpected end of file".into() } else { format!("unexpected '{}'", token.spelling) };
                    statistics[file][2] += 1; report(token.position, "syntax error", &message, &sources, &mut errors);
                    parser.recover(); continue;
                }
            };
            formatted.push(item_string(&item));
            if let Item::Signature(name, position, ty) = &item {
                if let Some(old) = pending.insert(name.clone(), Signature { position: *position, ty: ty.clone() }) {
                    statistics[file][5] += 1; report(old.position, "warning", &format!("signature for '{}' is never used", name), &sources, &mut errors);
                }
                continue;
            }
            context.clear();
            let typing = (|| -> Result<(unifier::Environment, Vec<Scheme>, Option<Type>), (Position, String)> {
                match &item {
                    Item::Declaration(group) => {
                        let signatures: Vec<_> = group.bindings.iter().map(|binding| pending.remove(&binding.name)).collect();
                        let (mut next, mut schemes) = context.group(group, &type_environment, false).map_err(|error| (error.position, error_message(&error, &context.unifier)))?;
                        for (i, signature) in signatures.iter().enumerate() {
                            if let Some(signature) = signature {
                                let declared = signature_type(&signature.ty, &mut context.unifier, &mut BTreeMap::new());
                                if !signature_matches(&schemes[i].ty, &declared, &context.unifier, &mut BTreeMap::new()) {
                                    let mut printer = TypePrinter::new(&context.unifier, None);
                                    return Err((group.bindings[i].position, format!("'{}' has type {} but its signature is {}", group.bindings[i].name, printer.write(&schemes[i].ty), printer.write(&declared))));
                                }
                                schemes[i] = Scheme { quantified: context.unifier.variables(&declared), ty: declared };
                                next.insert(group.bindings[i].name.clone(), schemes[i].clone());
                            }
                        }
                        Ok((next, schemes, None))
                    },
                    Item::Expression(expression) => {
                        let ty = context.expression(expression, &type_environment).map_err(|error| (error.position, error_message(&error, &context.unifier)))?;
                        Ok((type_environment.clone(), Vec::new(), Some(ty)))
                    },
                    _ => unreachable!()
                }
            })();
            let (next_types, schemes, expression_type) = match typing {
                Ok(result) => result,
                Err((position, message)) => { statistics[file][3] += 1; report(position, "type error", &message, &sources, &mut errors); continue; }
            };
            let inspected = inspection(&item, &scope, &context);
            let classification = |position: Position| inspected.classifications.get(&position).map_or_else(String::new, |kind| format!(" ({})", kind));
            if let Item::Declaration(group) = &item {
                for (binding, scheme) in group.bindings.iter().zip(&schemes) {
                    let ty = TypePrinter::new(&context.unifier, None).write(&scheme.ty);
                    types.push(format!("{} : {}{}", binding.name, ty, classification(binding.position)));
                }
            } else { types.push(format!("- : {}", TypePrinter::new(&context.unifier, None).write(expression_type.as_ref().unwrap()))); }
            context.locals.sort_by_key(|local| local.position);
            for local in &context.locals {
                let ty = TypePrinter::new(&context.unifier, Some(&local.scheme.quantified)).write(&local.scheme.ty);
                types.push(format!("  {} ({}:{}) : {}{}", local.name, local.position.line, local.position.column, ty, classification(local.position)));
            }
            for (position, _, message) in &inspected.warnings { statistics[file][5] += 1; report(*position, "warning", message, &sources, &mut errors); }
            let evaluated = match &item {
                Item::Declaration(group) => evaluator.group(group, &value_environment),
                Item::Expression(expression) => evaluator.expression(expression, &value_environment).map(|value| (value_environment.clone(), vec![value])),
                _ => unreachable!()
            };
            let (next_values, evaluated) = match evaluated {
                Ok(result) => result,
                Err(error) => { statistics[file][4] += 1; report(error.position, "runtime error", &error.message, &sources, &mut errors); continue; }
            };
            if let Item::Declaration(group) = &item {
                for (binding, value) in group.bindings.iter().zip(&evaluated) {
                    values.push(format!("{} = {}", binding.name, value_string(value)));
                    scope.insert(binding.name.clone(), binding.position);
                }
                statistics[file][1] += group.bindings.len();
            } else { values.push(format!("- = {}", value_string(&evaluated[0]))); }
            type_environment = next_types; value_environment = next_values;
        }
        let mut unused: Vec<_> = pending.into_iter().collect(); unused.sort_by_key(|(_, signature)| signature.position);
        for (name, signature) in unused { statistics[file][5] += 1; report(signature.position, "warning", &format!("signature for '{}' is never used", name), &sources, &mut errors); }
        statistics[file][6] = evaluator.calls;
    }
    errors.push("== summary ==".into());
    for file in 0..2 { let s = statistics[file]; errors.push(format!("{}: items={} bindings={} syntax={} type={} runtime={} warnings={} calls={}", file_names[file], s[0], s[1], s[2], s[3], s[4], s[5], s[6])); }
    write("types.txt", &types); write("values.txt", &values); write("errors.txt", &errors); write("formatted.ml", &formatted);
}
