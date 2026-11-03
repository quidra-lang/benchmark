use std::rc::Rc;
use crate::lexer::{Position, Token};
pub type Expression = Rc<Expr>;
#[derive(Clone)]
pub struct Expr { pub position: Position, pub kind: ExprKind }
#[derive(Clone)]
pub enum ExprKind {
    Integer(i64), Boolean(bool), String(String), Name(String), Fun(Parameter, Expression),
    Apply(Expression, Expression), Binary(String, Position, Expression, Expression), Negate(Position, Expression),
    If(Expression, Expression, Expression), Pair(Expression, Expression), List(Vec<Expression>),
    Match(Expression, Vec<(Pattern, Expression)>), Let(Group, Expression)
}
#[derive(Clone)]
pub struct Parameter { pub name: Option<String>, pub position: Position }
#[derive(Clone)]
pub struct Binding { pub name: String, pub position: Position, pub expression: Expression }
#[derive(Clone)]
pub struct Group { pub recursive: Option<Position>, pub bindings: Vec<Binding> }
#[derive(Clone)]
pub struct Pattern { pub position: Position, pub kind: PatternKind }
#[derive(Clone)]
pub enum PatternKind { Wildcard, Name(String), Integer(i64), Boolean(bool), String(String), Nil, Cons(Box<Pattern>, Box<Pattern>), List(Vec<Pattern>), Pair(Box<Pattern>, Box<Pattern>) }
#[derive(Clone)]
pub enum TypeExpression { Primitive(String), Variable(String), List(Box<TypeExpression>), Pair(Box<TypeExpression>, Box<TypeExpression>), Function(Box<TypeExpression>, Box<TypeExpression>) }
#[derive(Clone)]
pub enum Item { Signature(String, Position, TypeExpression), Declaration(Group), Expression(Expression) }
pub fn precedence(op: &str) -> usize { match op { "||" => 1, "&&" => 2, "=" | "<>" | "<" | ">" | "<=" | ">=" => 3, "::" | "^" => 4, "+" | "-" => 5, "*" | "/" | "mod" => 6, _ => 0 } }
pub fn right_associative(op: &str) -> bool { ["||", "&&", "::", "^"].contains(&op) }
fn expression(position: Position, kind: ExprKind) -> Expression { Rc::new(Expr { position, kind }) }
pub struct Parser { pub tokens: Vec<Token>, pub index: usize }
impl Parser {
    pub fn peek(&self) -> &Token { &self.tokens[self.index] }
    fn spelling(&self) -> &str { &self.peek().value }
    fn take(&mut self) -> Token { let token = self.peek().clone(); if token.kind != "eof" { self.index += 1; } token }
    fn expect(&mut self, word: &str) -> Result<Token, Token> { if self.spelling() == word && self.peek().kind != "invalid" { Ok(self.take()) } else { Err(self.peek().clone()) } }
    fn name(&mut self) -> Result<Token, Token> { if self.peek().kind == "identifier" && self.spelling() != "_" { Ok(self.take()) } else { Err(self.peek().clone()) } }
    fn parameter(&mut self) -> Result<Parameter, Token> {
        if self.peek().kind != "identifier" { return Err(self.peek().clone()); }
        let token = self.take();
        Ok(Parameter { name: if token.value == "_" { None } else { Some(token.value) }, position: token.position })
    }
    fn atomic_start(&self) -> bool { let token = self.peek(); ["integer", "string"].contains(&token.kind.as_str()) || token.kind == "identifier" && token.value != "_" || token.kind != "invalid" && ["true", "false", "(", "["].contains(&token.value.as_str()) }
    fn group(&mut self) -> Result<Group, Token> {
        self.expect("let")?;
        let recursive = if self.spelling() == "rec" { Some(self.take().position) } else { None };
        let mut bindings = Vec::new();
        loop {
            let name = self.name()?;
            let mut parameters = Vec::new();
            while self.peek().kind == "identifier" { parameters.push(self.parameter()?); }
            self.expect("=")?;
            let mut body = self.expr()?;
            for parameter in parameters.into_iter().rev() { body = expression(parameter.position, ExprKind::Fun(parameter, body)); }
            bindings.push(Binding { name: name.value, position: name.position, expression: body });
            if self.spelling() != "and" { break; }
            self.take();
        }
        Ok(Group { recursive, bindings })
    }
    pub fn item(&mut self) -> Result<Item, Token> {
        let item = if self.spelling() == "val" {
            self.take(); let name = self.name()?; self.expect(":")?;
            Item::Signature(name.value, name.position, self.type_expression()?)
        } else if self.spelling() == "let" {
            let position = self.peek().position;
            let group = self.group()?;
            if self.spelling() == "in" { self.take(); Item::Expression(expression(position, ExprKind::Let(group, self.expr()?))) }
            else { Item::Declaration(group) }
        } else { Item::Expression(self.expr()?) };
        self.expect(";;")?;
        Ok(item)
    }
    fn expr(&mut self) -> Result<Expression, Token> {
        let position = self.peek().position;
        match self.spelling() {
            "let" => { let group = self.group()?; self.expect("in")?; Ok(expression(position, ExprKind::Let(group, self.expr()?))) },
            "fun" => {
                self.take(); let mut parameters = vec![self.parameter()?];
                while self.peek().kind == "identifier" { parameters.push(self.parameter()?); }
                self.expect("->")?;
                let mut body = self.expr()?;
                for (i, parameter) in parameters.into_iter().enumerate().collect::<Vec<_>>().into_iter().rev() {
                    let start = if i == 0 { position } else { parameter.position };
                    body = expression(start, ExprKind::Fun(parameter, body));
                }
                Ok(body)
            },
            "if" => {
                self.take(); let condition = self.expr()?; self.expect("then")?;
                let yes = self.expr()?; self.expect("else")?; let no = self.expr()?;
                Ok(expression(position, ExprKind::If(condition, yes, no)))
            },
            "match" => {
                self.take(); let value = self.expr()?; self.expect("with")?;
                if self.spelling() == "|" { self.take(); }
                let mut arms = Vec::new();
                loop {
                    let pattern = self.pattern()?; self.expect("->")?; let body = self.expr()?;
                    arms.push((pattern, body));
                    if self.spelling() != "|" { break; }
                    self.take();
                }
                Ok(expression(position, ExprKind::Match(value, arms)))
            },
            _ => self.binary(1)
        }
    }
    fn binary(&mut self, minimum: usize) -> Result<Expression, Token> {
        let mut left = self.unary()?;
        loop {
            let priority = precedence(self.spelling());
            if priority < minimum || priority == 0 { break; }
            let operator = self.take();
            let right = self.binary(if right_associative(&operator.value) { priority } else { priority + 1 })?;
            left = expression(left.position, ExprKind::Binary(operator.value, operator.position, left, right));
        }
        Ok(left)
    }
    fn unary(&mut self) -> Result<Expression, Token> {
        if self.spelling() == "-" { let token = self.take(); return Ok(expression(token.position, ExprKind::Negate(token.position, self.unary()?))); }
        let mut function = self.atomic()?;
        while self.atomic_start() { let argument = self.atomic()?; function = expression(function.position, ExprKind::Apply(function, argument)); }
        Ok(function)
    }
    fn atomic(&mut self) -> Result<Expression, Token> {
        let token = self.peek().clone();
        let position = token.position;
        let kind = match token.kind.as_str() {
            "integer" => { self.take(); ExprKind::Integer(token.value.parse().unwrap()) },
            "string" => { self.take(); ExprKind::String(token.value) },
            "identifier" if token.value != "_" => { self.take(); ExprKind::Name(token.value) },
            _ => match token.value.as_str() {
                "true" | "false" if token.kind != "invalid" => { self.take(); ExprKind::Boolean(token.value == "true") },
                "(" if token.kind != "invalid" => {
                    self.take(); let first = self.expr()?;
                    if self.spelling() == "," { self.take(); let second = self.expr()?; self.expect(")")?; ExprKind::Pair(first, second) }
                    else { self.expect(")")?; return Ok(first); }
                },
                "[" if token.kind != "invalid" => {
                    self.take(); let mut elements = Vec::new();
                    if self.spelling() != "]" {
                        elements.push(self.expr()?);
                        while self.spelling() == ";" { self.take(); elements.push(self.expr()?); }
                    }
                    self.expect("]")?; ExprKind::List(elements)
                },
                _ => return Err(token)
            }
        };
        Ok(expression(position, kind))
    }
    fn pattern(&mut self) -> Result<Pattern, Token> {
        let head = self.atomic_pattern()?;
        if self.spelling() == "::" { self.take(); let tail = self.pattern()?; Ok(Pattern { position: head.position, kind: PatternKind::Cons(Box::new(head), Box::new(tail)) }) }
        else { Ok(head) }
    }
    fn atomic_pattern(&mut self) -> Result<Pattern, Token> {
        let token = self.peek().clone();
        let position = token.position;
        let kind = match token.kind.as_str() {
            "integer" => { self.take(); PatternKind::Integer(token.value.parse().unwrap()) },
            "string" => { self.take(); PatternKind::String(token.value) },
            "identifier" => { self.take(); if token.value == "_" { PatternKind::Wildcard } else { PatternKind::Name(token.value) } },
            _ => match token.value.as_str() {
                "true" | "false" if token.kind != "invalid" => { self.take(); PatternKind::Boolean(token.value == "true") },
                "-" if token.kind != "invalid" => { self.take(); if self.peek().kind != "integer" { return Err(self.peek().clone()); } PatternKind::Integer(-self.take().value.parse::<i64>().unwrap()) },
                "(" if token.kind != "invalid" => {
                    self.take(); let first = self.pattern()?;
                    if self.spelling() == "," { self.take(); let second = self.pattern()?; self.expect(")")?; PatternKind::Pair(Box::new(first), Box::new(second)) }
                    else { self.expect(")")?; return Ok(first); }
                },
                "[" if token.kind != "invalid" => {
                    self.take(); let mut elements = Vec::new();
                    if self.spelling() != "]" { elements.push(self.pattern()?); while self.spelling() == ";" { self.take(); elements.push(self.pattern()?); } }
                    self.expect("]")?;
                    if elements.is_empty() { PatternKind::Nil } else { PatternKind::List(elements) }
                },
                _ => return Err(token)
            }
        };
        Ok(Pattern { position, kind })
    }
    fn type_expression(&mut self) -> Result<TypeExpression, Token> {
        let first = self.product_type()?;
        if self.spelling() == "->" { self.take(); Ok(TypeExpression::Function(Box::new(first), Box::new(self.type_expression()?))) }
        else { Ok(first) }
    }
    fn product_type(&mut self) -> Result<TypeExpression, Token> {
        let first = self.list_type()?;
        if self.spelling() == "*" { self.take(); Ok(TypeExpression::Pair(Box::new(first), Box::new(self.list_type()?))) }
        else { Ok(first) }
    }
    fn list_type(&mut self) -> Result<TypeExpression, Token> {
        let mut ty = self.type_atom()?;
        while self.peek().kind == "identifier" && self.spelling() == "list" { self.take(); ty = TypeExpression::List(Box::new(ty)); }
        Ok(ty)
    }
    fn type_atom(&mut self) -> Result<TypeExpression, Token> {
        let token = self.peek().clone();
        if token.kind == "type_variable" { self.take(); Ok(TypeExpression::Variable(token.value)) }
        else if token.kind == "identifier" && ["int", "bool", "string"].contains(&token.value.as_str()) { self.take(); Ok(TypeExpression::Primitive(token.value)) }
        else if token.kind == "symbol" && token.value == "(" { self.take(); let ty = self.type_expression()?; self.expect(")")?; Ok(ty) }
        else { Err(token) }
    }
    pub fn recover(&mut self) { while self.peek().kind != "eof" && self.spelling() != ";;" { self.take(); } if self.spelling() == ";;" { self.take(); } }
}
