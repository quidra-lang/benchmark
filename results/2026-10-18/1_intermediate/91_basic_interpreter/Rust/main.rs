use std::collections::{BTreeMap, HashMap};
use std::io::{self, Read};

#[derive(Debug)]
enum Failure {
    Syntax,
    Runtime(String),
}

type Result<T> = std::result::Result<T, Failure>;

fn syntax<T>() -> Result<T> {
    Err(Failure::Syntax)
}

fn fault<T>(reason: &str) -> Result<T> {
    Err(Failure::Runtime(reason.to_string()))
}

#[derive(Clone, PartialEq, Eq)]
enum Value {
    Integer(i64),
    Text(String),
}

impl Value {
    fn number(&self) -> i64 {
        if let Value::Integer(n) = self { *n } else { unreachable!() }
    }

    fn text(&self) -> &str {
        if let Value::Text(s) = self { s } else { unreachable!() }
    }

    fn kind(&self) -> char {
        match self {
            Value::Integer(_) => 'I',
            Value::Text(_) => 'S',
        }
    }

    fn display(&self) -> String {
        match self {
            Value::Integer(n) => n.to_string(),
            Value::Text(s) => s.clone(),
        }
    }
}

#[derive(Clone)]
struct Token {
    kind: char,
    text: String,
    value: Value,
}

#[derive(Clone)]
struct Expression {
    kind: String,
    data_type: char,
    value: Value,
    args: Vec<Expression>,
}

impl Expression {
    fn new(kind: &str, data_type: char, value: Value) -> Self {
        Self { kind: kind.into(), data_type, value, args: Vec::new() }
    }

    fn operation(kind: &str, data_type: char, op: &str, args: Vec<Self>) -> Self {
        Self {
            kind: kind.into(),
            data_type,
            value: Value::Text(op.into()),
            args,
        }
    }
}

#[derive(Clone)]
struct PrintItem {
    kind: String,
    expression: Option<Expression>,
}

#[derive(Clone)]
struct Clause {
    line: Option<i64>,
    body: Vec<usize>,
}

#[derive(Clone)]
struct Statement {
    kind: String,
    line: i64,
    next: Option<usize>,
    expression: Option<Expression>,
    target: Option<Expression>,
    targets: Vec<Expression>,
    expressions: Vec<Expression>,
    values: Vec<Value>,
    numbers: Vec<i64>,
    clauses: Vec<Clause>,
    items: Vec<PrintItem>,
    name: String,
    mode: String,
}

impl Statement {
    fn new(kind: &str) -> Self {
        Self {
            kind: kind.into(),
            line: 0,
            next: None,
            expression: None,
            target: None,
            targets: Vec::new(),
            expressions: Vec::new(),
            values: Vec::new(),
            numbers: Vec::new(),
            clauses: Vec::new(),
            items: Vec::new(),
            name: String::new(),
            mode: String::new(),
        }
    }
}

fn variable(name: &str) -> bool {
    let bytes = name.as_bytes();
    if bytes.is_empty() || !bytes[0].is_ascii_uppercase() {
        return false;
    }
    match bytes.len() {
        1 => true,
        2 => bytes[1].is_ascii_digit() || bytes[1] == b'$',
        3 => bytes[1].is_ascii_digit() && bytes[2] == b'$',
        _ => false,
    }
}

fn name_type(name: &str) -> char {
    if name.ends_with('$') { 'S' } else { 'I' }
}

fn signature(name: &str, args: &str) -> bool {
    match name {
        "ABS" | "SGN" | "INT" | "SQR" | "RND" | "CHR$" | "STR$"
            => args == "I",
        "LEN" | "ASC" | "VAL" => args == "S",
        "LEFT$" | "RIGHT$" => args == "SI",
        "MID$" => args == "SI" || args == "SII",
        "INSTR" => args == "SS",
        _ => false,
    }
}

fn function(name: &str) -> bool {
    matches!(
        name,
        "ABS" | "SGN" | "INT" | "SQR" | "RND" | "LEN" | "ASC"
            | "VAL" | "CHR$" | "STR$" | "LEFT$" | "RIGHT$"
            | "MID$" | "INSTR"
    )
}

fn tokenize(source: &str) -> Result<Vec<Token>> {
    let bytes = source.as_bytes();
    let mut tokens = Vec::new();
    let mut p = 0;
    while p < bytes.len() {
        let c = bytes[p];
        if c == b' ' {
            p += 1;
        } else if c == b'"' {
            let start = p;
            p += 1;
            while p < bytes.len() && bytes[p] != b'"' { p += 1; }
            if p == bytes.len() { return syntax(); }
            tokens.push(Token {
                kind: 'S',
                text: source[start..=p].into(),
                value: Value::Text(source[start + 1..p].into()),
            });
            p += 1;
        } else if c.is_ascii_digit() {
            let start = p;
            while p < bytes.len() && bytes[p].is_ascii_digit() { p += 1; }
            let word = &source[start..p];
            let n = word.parse::<i64>().map_err(|_| Failure::Syntax)?;
            if n > 32767 { return syntax(); }
            tokens.push(Token {
                kind: 'I',
                text: word.into(),
                value: Value::Integer(n),
            });
        } else if c.is_ascii_uppercase() {
            if source[p..].starts_with("REM") {
                tokens.push(Token {
                    kind: 'W',
                    text: "REM".into(),
                    value: Value::Text("REM".into()),
                });
                break;
            }
            let start = p;
            while p < bytes.len() && (bytes[p].is_ascii_uppercase() || bytes[p].is_ascii_digit()) {
                p += 1;
            }
            if p < bytes.len() && bytes[p] == b'$' { p += 1; }
            let word = source[start..p].to_owned();
            tokens.push(Token {
                kind: 'W',
                text: word.clone(),
                value: Value::Text(word),
            });
        } else {
            let word = if p + 1 < bytes.len() &&
                matches!(&source[p..p + 2], "<>" | "<=" | ">=") {
                &source[p..p + 2]
            } else {
                &source[p..p + 1]
            };
            if !b"+-*/^=<>() ,;:".contains(&c) { return syntax(); }
            tokens.push(Token {
                kind: 'P',
                text: word.into(),
                value: Value::Text(word.into()),
            });
            p += word.len();
        }
    }
    tokens.push(Token { kind: 'E', text: String::new(), value: Value::Text(String::new()) });
    Ok(tokens)
}

struct Parser<'a> {
    tokens: Vec<Token>,
    position: usize,
    program: &'a mut Vec<Statement>,
}

impl Parser<'_> {
    fn current(&self) -> &Token {
        &self.tokens[self.position]
    }

    fn at(&self, text: &str) -> bool {
        matches!(self.current().kind, 'W' | 'P') && self.current().text == text
    }

    fn take(&mut self, text: &str) -> bool {
        if !self.at(text) { return false; }
        self.position += 1;
        true
    }

    fn expect(&mut self, text: &str) -> Result<()> {
        if self.take(text) { Ok(()) } else { syntax() }
    }

    fn number(&mut self) -> Result<i64> {
        if self.current().kind != 'I' { return syntax(); }
        let result = self.current().value.number();
        self.position += 1;
        Ok(result)
    }

    fn integer(&mut self, level: usize) -> Result<Expression> {
        let expr = self.expression(level)?;
        if expr.data_type != 'I' { return syntax(); }
        Ok(expr)
    }

    fn target(&mut self) -> Result<Expression> {
        let token = self.current().clone();
        if token.kind != 'W' || !variable(&token.text) { return syntax(); }
        self.position += 1;
        let mut result = Expression::new(
            "variable", name_type(&token.text), Value::Text(token.text),
        );
        if self.take("(") {
            result.kind = "array".into();
            result.args.push(self.integer(0)?);
            if self.take(",") { result.args.push(self.integer(0)?); }
            self.expect(")")?;
        }
        Ok(result)
    }

    fn primary(&mut self) -> Result<Expression> {
        let token = self.current().clone();
        if matches!(token.kind, 'I' | 'S') {
            self.position += 1;
            return Ok(Expression::new("constant", token.kind, token.value));
        }
        if self.take("(") {
            let result = self.expression(0)?;
            self.expect(")")?;
            return Ok(result);
        }
        if token.kind == 'W' && variable(&token.text) { return self.target(); }
        if self.take("ERR") {
            return Ok(Expression::new("builtin", 'I', Value::Text("ERR".into())));
        }
        if self.take("ERL") {
            return Ok(Expression::new("builtin", 'I', Value::Text("ERL".into())));
        }
        if token.kind == 'W' && function(&token.text) {
            self.position += 1;
            self.expect("(")?;
            let mut args = vec![self.expression(0)?];
            while self.take(",") { args.push(self.expression(0)?); }
            self.expect(")")?;
            let types: String = args.iter().map(|e| e.data_type).collect();
            if !signature(&token.text, &types) { return syntax(); }
            return Ok(Expression::operation(
                "call", name_type(&token.text), &token.text, args,
            ));
        }
        syntax()
    }

    fn expression(&mut self, level: usize) -> Result<Expression> {
        if level == 2 && self.take("NOT") {
            return Ok(Expression::operation("unary", 'I', "NOT", vec![self.integer(2)?]));
        }
        if level == 6 && self.take("-") {
            return Ok(Expression::operation("unary", 'I', "-", vec![self.integer(6)?]));
        }
        if level == 8 { return self.primary(); }
        let mut left = self.expression(level + 1)?;
        let operators: &[&str] = match level {
            0 => &["OR"],
            1 => &["AND"],
            3 => &["=", "<>", "<", ">", "<=", ">="],
            4 => &["+", "-"],
            5 => &["*", "/", "MOD"],
            7 => &["^"],
            _ => &[],
        };
        while operators.iter().any(|op| self.at(op)) {
            let op = self.current().text.clone();
            self.position += 1;
            let right = self.expression(if level == 7 { 6 } else { level + 1 })?;
            if left.data_type != right.data_type
                || (left.data_type == 'S' && level != 3 && op != "+") {
                return syntax();
            }
            left = Expression::operation(
                "binary", if level == 3 { 'I' } else { left.data_type },
                &op, vec![left, right],
            );
            if level == 7 { break; }
        }
        Ok(left)
    }

    fn clause(&mut self) -> Result<Clause> {
        if self.current().kind == 'I' {
            Ok(Clause { line: Some(self.number()?), body: Vec::new() })
        } else {
            Ok(Clause { line: None, body: self.list(true)? })
        }
    }

    fn list(&mut self, in_clause: bool) -> Result<Vec<usize>> {
        let mut result = vec![self.statement(in_clause)?];
        while self.take(":") { result.push(self.statement(in_clause)?); }
        Ok(result)
    }

    fn statement(&mut self, in_clause: bool) -> Result<usize> {
        let word = self.current().text.clone();
        if in_clause && matches!(word.as_str(), "IF" | "FOR" | "NEXT" | "WHILE" | "WEND" | "DATA") {
            return syntax();
        }
        let mut statement = Statement::new(&word);
        if self.take("REM") || self.take("RETURN") || self.take("WEND")
            || self.take("END") || self.take("STOP") {
            return Ok(self.store(statement));
        }
        if self.take("PRINT") {
            let mut last_value = false;
            while self.current().kind != 'E' && !self.at(":") && !self.at("ELSE") {
                if self.take(";") {
                    statement.items.push(PrintItem { kind: ";".into(), expression: None });
                    last_value = false;
                } else if self.take(",") {
                    statement.items.push(PrintItem { kind: ",".into(), expression: None });
                    last_value = false;
                } else {
                    let kind = if self.at("TAB") { "TAB" } else if self.at("SPC") {
                        "SPC"
                    } else { "value" };
                    if kind == "value" && last_value { return syntax(); }
                    let expression = if kind == "value" {
                        self.expression(0)?
                    } else {
                        self.position += 1;
                        self.expect("(")?;
                        let value = self.integer(0)?;
                        self.expect(")")?;
                        value
                    };
                    statement.items.push(PrintItem {
                        kind: kind.into(), expression: Some(expression),
                    });
                    last_value = kind == "value";
                }
            }
            return Ok(self.store(statement));
        }
        if self.take("INPUT") || self.take("READ") || self.take("DIM") {
            loop {
                let target = self.target()?;
                if word == "DIM" && target.kind != "array" { return syntax(); }
                statement.targets.push(target);
                if !self.take(",") { break; }
            }
            return Ok(self.store(statement));
        }
        if self.take("DATA") {
            loop {
                let negative = self.take("-");
                let token = self.current().clone();
                if token.kind != 'I' && (token.kind != 'S' || negative) {
                    return syntax();
                }
                self.position += 1;
                statement.values.push(if negative {
                    Value::Integer(-token.value.number())
                } else {
                    token.value
                });
                if !self.take(",") { break; }
            }
            return Ok(self.store(statement));
        }
        if self.take("IF") {
            statement.expression = Some(self.integer(0)?);
            self.expect("THEN")?;
            statement.clauses.push(self.clause()?);
            if self.take("ELSE") { statement.clauses.push(self.clause()?); }
            if self.current().kind != 'E' { return syntax(); }
            return Ok(self.store(statement));
        }
        if self.take("GOTO") || self.take("GOSUB") {
            statement.numbers.push(self.number()?);
            return Ok(self.store(statement));
        }
        if self.take("ON") {
            if self.take("ERROR") {
                statement.kind = "handler".into();
                self.expect("GOTO")?;
                statement.numbers.push(self.number()?);
            } else {
                statement.expression = Some(self.integer(0)?);
                statement.mode = if self.take("GOTO") {
                    "GOTO".into()
                } else {
                    self.expect("GOSUB")?;
                    "GOSUB".into()
                };
                loop {
                    statement.numbers.push(self.number()?);
                    if !self.take(",") { break; }
                }
            }
            return Ok(self.store(statement));
        }
        if self.take("RESUME") {
            if self.take("NEXT") {
                statement.mode = "NEXT".into();
            } else if self.current().kind == 'I' {
                statement.mode = "line".into();
                statement.numbers.push(self.number()?);
            }
            return Ok(self.store(statement));
        }
        if self.take("FOR") {
            let token = self.current().clone();
            if token.kind != 'W' || !variable(&token.text) || name_type(&token.text) != 'I' {
                return syntax();
            }
            statement.name = token.text;
            self.position += 1;
            self.expect("=")?;
            statement.expressions.push(self.integer(0)?);
            self.expect("TO")?;
            statement.expressions.push(self.integer(0)?);
            statement.expressions.push(if self.take("STEP") {
                self.integer(0)?
            } else {
                Expression::new("constant", 'I', Value::Integer(1))
            });
            return Ok(self.store(statement));
        }
        if self.take("NEXT") {
            let token = self.current().clone();
            if token.kind == 'W' && variable(&token.text) && name_type(&token.text) == 'I' {
                statement.name = token.text;
                self.position += 1;
            }
            return Ok(self.store(statement));
        }
        if self.take("WHILE") || self.take("RANDOMIZE") {
            statement.expression = Some(self.integer(0)?);
            return Ok(self.store(statement));
        }
        if self.take("RESTORE") {
            if self.current().kind == 'I' {
                statement.numbers.push(self.number()?);
            }
            return Ok(self.store(statement));
        }
        self.take("LET");
        statement.kind = "assign".into();
        statement.target = Some(self.target()?);
        self.expect("=")?;
        statement.expression = Some(self.expression(0)?);
        if statement.target.as_ref().unwrap().data_type !=
            statement.expression.as_ref().unwrap().data_type {
            return syntax();
        }
        Ok(self.store(statement))
    }

    fn store(&mut self, statement: Statement) -> usize {
        let id = self.program.len();
        self.program.push(statement);
        id
    }

    fn parse(&mut self) -> Result<Vec<usize>> {
        let list = self.list(false)?;
        if self.current().kind != 'E' { return syntax(); }
        Ok(list)
    }
}

struct BasicArray {
    bounds: Vec<i64>,
    values: Vec<Value>,
}

#[derive(Clone)]
struct Frame {
    kind: String,
    position: Option<usize>,
    name: String,
    limit: i64,
    step: i64,
}

struct Machine {
    inputs: Vec<String>,
    program: Vec<Statement>,
    vars: HashMap<String, Value>,
    arrays: HashMap<String, BasicArray>,
    stack: Vec<Frame>,
    entries: HashMap<i64, usize>,
    sequence: Vec<usize>,
    data: Vec<(i64, Value)>,
    data_pos: usize,
    input_pos: usize,
    random: i64,
    handler: i64,
    handling: bool,
    remembered: Option<usize>,
    err: i64,
    erl: i64,
    buffer: String,
    output: Vec<String>,
}

impl Machine {
    fn new(inputs: Vec<String>) -> Self {
        Self {
            inputs, program: Vec::new(), vars: HashMap::new(),
            arrays: HashMap::new(), stack: Vec::new(), entries: HashMap::new(),
            sequence: Vec::new(), data: Vec::new(), data_pos: 0, input_pos: 0,
            random: 1, handler: 0, handling: false, remembered: None,
            err: 0, erl: 0, buffer: String::new(), output: Vec::new(),
        }
    }

    fn end_line(&mut self) {
        let line = self.buffer.trim_end_matches(' ').to_owned();
        self.output.push(line);
        self.buffer.clear();
    }

    fn message(&mut self, text: String) {
        if !self.buffer.is_empty() { self.end_line(); }
        self.output.push(text);
    }

    fn checked(n: i64) -> Result<i64> {
        if !(-32768..=32767).contains(&n) { fault("OVERFLOW") } else { Ok(n) }
    }

    fn get(&self, name: &str) -> Value {
        self.vars.get(name).cloned().unwrap_or_else(|| {
            if name_type(name) == 'S' { Value::Text(String::new()) }
            else { Value::Integer(0) }
        })
    }

    fn declare(&mut self, name: &str, bounds: &[i64]) {
        let size = bounds.iter().fold(1_usize, |a, b| a * (*b as usize + 1));
        let initial = if name_type(name) == 'S' {
            Value::Text(String::new())
        } else { Value::Integer(0) };
        self.arrays.insert(name.into(), BasicArray {
            bounds: bounds.to_vec(),
            values: vec![initial; size],
        });
    }

    fn address(&mut self, target: &Expression) -> Result<(String, Option<usize>)> {
        let name = target.value.text().to_owned();
        if target.kind == "variable" { return Ok((name, None)); }
        let mut indices = Vec::new();
        for index in &target.args {
            indices.push(self.evaluate(index)?.number());
        }
        if !self.arrays.contains_key(&name) {
            self.declare(&name, &vec![10; indices.len()]);
        }
        let array = self.arrays.get(&name).unwrap();
        if indices.len() != array.bounds.len() { return fault("SUBSCRIPT OUT OF RANGE"); }
        let mut position = 0_usize;
        for (i, value) in indices.iter().enumerate() {
            if *value < 0 || *value > array.bounds[i] {
                return fault("SUBSCRIPT OUT OF RANGE");
            }
            position = position * (array.bounds[i] as usize + 1) + *value as usize;
        }
        Ok((name, Some(position)))
    }

    fn load(&self, address: &(String, Option<usize>)) -> Value {
        match address.1 {
            Some(index) => self.arrays[&address.0].values[index].clone(),
            None => self.get(&address.0),
        }
    }

    fn store(&mut self, address: &(String, Option<usize>), value: Value) {
        match address.1 {
            Some(index) => self.arrays.get_mut(&address.0).unwrap().values[index] = value,
            None => { self.vars.insert(address.0.clone(), value); }
        }
    }

    fn integer_power(mut base: i64, mut exponent: i64) -> Result<i64> {
        if exponent < 0 { return fault("ILLEGAL FUNCTION CALL"); }
        let mut result = 1;
        while exponent > 0 {
            if exponent & 1 != 0 { result = Self::checked(result * base)?; }
            exponent >>= 1;
            if exponent > 0 { base = Self::checked(base * base)?; }
        }
        Ok(result)
    }

    fn evaluate(&mut self, expression: &Expression) -> Result<Value> {
        let op = expression.value.text_if();
        if expression.kind == "constant" { return Ok(expression.value.clone()); }
        if expression.kind == "variable" || expression.kind == "array" {
            let address = self.address(expression)?;
            return Ok(self.load(&address));
        }
        if expression.kind == "builtin" {
            return Ok(Value::Integer(if op == "ERR" { self.err } else { self.erl }));
        }
        if expression.kind == "unary" {
            let a = self.evaluate(&expression.args[0])?.number();
            return Ok(Value::Integer(if op == "NOT" { !a } else { Self::checked(-a)? }));
        }
        let mut args = Vec::new();
        for arg in &expression.args { args.push(self.evaluate(arg)?); }
        if expression.kind == "call" { return self.call(op, &args); }
        let (a, b) = (&args[0], &args[1]);
        if matches!(op, "=" | "<>" | "<" | ">" | "<=" | ">=") {
            let ordering = if a == b {
                0
            } else if a.kind() == 'S' {
                match a.text().cmp(b.text()) {
                    std::cmp::Ordering::Less => -1,
                    std::cmp::Ordering::Equal => 0,
                    std::cmp::Ordering::Greater => 1,
                }
            } else {
                match a.number().cmp(&b.number()) {
                    std::cmp::Ordering::Less => -1,
                    std::cmp::Ordering::Equal => 0,
                    std::cmp::Ordering::Greater => 1,
                }
            };
            let yes = match op {
                "=" => ordering == 0,
                "<>" => ordering != 0,
                "<" => ordering < 0,
                ">" => ordering > 0,
                "<=" => ordering <= 0,
                _ => ordering >= 0,
            };
            return Ok(Value::Integer(if yes { -1 } else { 0 }));
        }
        if expression.data_type == 'S' {
            let result = format!("{}{}", a.text(), b.text());
            if result.len() > 255 { return fault("STRING TOO LONG"); }
            return Ok(Value::Text(result));
        }
        let (x, y) = (a.number(), b.number());
        let result = match op {
            "+" => Self::checked(x + y)?,
            "-" => Self::checked(x - y)?,
            "*" => Self::checked(x * y)?,
            "/" => {
                if y == 0 { return fault("DIVISION BY ZERO"); }
                Self::checked(x / y)?
            }
            "MOD" => {
                if y == 0 { return fault("DIVISION BY ZERO"); }
                x % y
            }
            "^" => Self::integer_power(x, y)?,
            "AND" => x & y,
            "OR" => x | y,
            _ => unreachable!(),
        };
        Ok(Value::Integer(result))
    }

    fn call(&mut self, name: &str, args: &[Value]) -> Result<Value> {
        let n = if args[0].kind() == 'I' { args[0].number() } else { 0 };
        let s = if args[0].kind() == 'S' { args[0].text() } else { "" };
        let k = if args.len() > 1 && args[1].kind() == 'I' {
            args[1].number()
        } else { 0 };
        let result = match name {
            "ABS" => Value::Integer(Self::checked(n.abs())?),
            "SGN" => Value::Integer(n.signum()),
            "INT" => Value::Integer(n),
            "SQR" => {
                if n < 0 { return fault("ILLEGAL FUNCTION CALL"); }
                Value::Integer((n as f64).sqrt().floor() as i64)
            }
            "RND" => {
                if n < 1 { return fault("ILLEGAL FUNCTION CALL"); }
                self.random = self.random * 48271 % 2147483647;
                Value::Integer(self.random % n + 1)
            }
            "LEN" => Value::Integer(s.len() as i64),
            "ASC" => {
                if s.is_empty() { return fault("ILLEGAL FUNCTION CALL"); }
                Value::Integer(s.as_bytes()[0] as i64)
            }
            "VAL" => {
                let bytes = s.as_bytes();
                let mut i = 0;
                while i < bytes.len() && bytes[i] == b' ' { i += 1; }
                let start = i;
                if i < bytes.len() && (bytes[i] == b'+' || bytes[i] == b'-') {
                    i += 1;
                }
                let digit_start = i;
                while i < bytes.len() && bytes[i].is_ascii_digit() { i += 1; }
                let parsed = if digit_start == i {
                    0
                } else {
                    s[start..i].parse::<i64>().unwrap_or(i64::MAX)
                };
                Value::Integer(Self::checked(parsed)?)
            }
            "CHR$" => {
                if !(32..=126).contains(&n) { return fault("ILLEGAL FUNCTION CALL"); }
                Value::Text((n as u8 as char).to_string())
            }
            "STR$" => Value::Text(n.to_string()),
            "LEFT$" => {
                if k < 0 { return fault("ILLEGAL FUNCTION CALL"); }
                Value::Text(s[..s.len().min(k as usize)].to_owned())
            }
            "RIGHT$" => {
                if k < 0 { return fault("ILLEGAL FUNCTION CALL"); }
                Value::Text(s[s.len().saturating_sub(k as usize)..].to_owned())
            }
            "MID$" => {
                let length = if args.len() == 3 { args[2].number() } else { s.len() as i64 };
                if k < 1 || length < 0 { return fault("ILLEGAL FUNCTION CALL"); }
                let start = (k as usize - 1).min(s.len());
                let end = (start + length as usize).min(s.len());
                Value::Text(s[start..end].to_owned())
            }
            "INSTR" => {
                Value::Integer(s.find(args[1].text()).map_or(0, |i| i as i64 + 1))
            }
            _ => unreachable!(),
        };
        Ok(result)
    }

    fn line(&self, number: i64) -> Result<usize> {
        self.entries.get(&number).copied().ok_or_else(|| {
            Failure::Runtime("UNDEFINED LINE NUMBER".into())
        })
    }

    fn push(&mut self, frame: Frame) -> Result<()> {
        if self.stack.len() == 100 { return fault("OUT OF MEMORY"); }
        self.stack.push(frame);
        Ok(())
    }

    fn search(&self, kind: &str, name: &str) -> Option<usize> {
        for i in (0..self.stack.len()).rev() {
            let frame = &self.stack[i];
            if frame.kind == "GOSUB" { break; }
            if frame.kind == kind && (name.is_empty() || name == frame.name) {
                return Some(i);
            }
        }
        None
    }

    fn matching(&self, statement: usize, open: &str, close: &str) -> Result<Option<usize>> {
        let start = self.sequence.iter().position(|x| *x == statement).unwrap() + 1;
        let mut depth = 0;
        for id in self.sequence[start..].iter().copied() {
            let current = &self.program[id];
            if current.kind == open { depth += 1; }
            else if current.kind == close {
                if depth == 0 { return Ok(current.next); }
                depth -= 1;
            }
        }
        fault(&format!("{} WITHOUT {}", open, close))
    }

    fn subroutine(&mut self, number: i64, after: Option<usize>) -> Result<usize> {
        let destination = self.line(number)?;
        self.push(Frame {
            kind: "GOSUB".into(), position: after, name: String::new(),
            limit: 0, step: 0,
        })?;
        Ok(destination)
    }

    fn execute(&mut self, id: usize) -> Result<Option<usize>> {
        let s = self.program[id].clone();
        let mut next = s.next;
        match s.kind.as_str() {
            "REM" | "DATA" => {}
            "assign" => {
                let address = self.address(s.target.as_ref().unwrap())?;
                let value = self.evaluate(s.expression.as_ref().unwrap())?;
                self.store(&address, value);
            }
            "PRINT" => {
                for item in &s.items {
                    if item.kind == "," {
                        self.buffer.push_str(&" ".repeat(10 - self.buffer.len() % 10));
                    } else if item.kind != ";" {
                        let value = self.evaluate(item.expression.as_ref().unwrap())?;
                        if item.kind == "value" {
                            self.buffer.push_str(&value.display());
                        } else {
                            let n = value.number();
                            if n < 0 { return fault("ILLEGAL FUNCTION CALL"); }
                            let count = if item.kind == "SPC" {
                                n as usize
                            } else {
                                (n as usize).saturating_sub(self.buffer.len())
                            };
                            self.buffer.push_str(&" ".repeat(count));
                        }
                    }
                }
                if s.items.is_empty() || !matches!(s.items.last().unwrap().kind.as_str(), ";" | ",") {
                    self.end_line();
                }
            }
            "INPUT" | "READ" => {
                for target in &s.targets {
                    let address = self.address(target)?;
                    let value = if s.kind == "READ" {
                        if self.data_pos >= self.data.len() { return fault("OUT OF DATA"); }
                        let value = self.data[self.data_pos].1.clone();
                        self.data_pos += 1;
                        if value.kind() != target.data_type { return fault("TYPE MISMATCH"); }
                        value
                    } else {
                        loop {
                            if self.input_pos >= self.inputs.len() {
                                return fault("INPUT PAST END");
                            }
                            let text = &self.inputs[self.input_pos];
                            self.input_pos += 1;
                            if target.data_type == 'S' {
                                break Value::Text(text.clone());
                            }
                            let bytes = text.as_bytes();
                            let start = if bytes.first() == Some(&b'-') { 1 } else { 0 };
                            if start < bytes.len() && bytes[start..].iter().all(u8::is_ascii_digit) {
                                if let Ok(n) = text.parse::<i64>() {
                                    if (-32768..=32767).contains(&n) {
                                        break Value::Integer(n);
                                    }
                                }
                            }
                            self.message("?REDO FROM START".into());
                        }
                    };
                    self.store(&address, value);
                }
            }
            "RESTORE" => {
                self.data_pos = if let Some(number) = s.numbers.first() {
                    self.line(*number)?;
                    self.data.iter().position(|(line, _)| line >= number)
                        .unwrap_or(self.data.len())
                } else { 0 };
            }
            "IF" => {
                let branch = if self.evaluate(s.expression.as_ref().unwrap())?.number() != 0 {
                    0
                } else { 1 };
                if let Some(clause) = s.clauses.get(branch) {
                    next = if let Some(line) = clause.line {
                        Some(self.line(line)?)
                    } else {
                        clause.body.first().copied()
                    };
                }
            }
            "GOTO" => next = Some(self.line(s.numbers[0])?),
            "GOSUB" => next = Some(self.subroutine(s.numbers[0], next)?),
            "ON" => {
                let index = self.evaluate(s.expression.as_ref().unwrap())?.number();
                if index < 0 { return fault("ILLEGAL FUNCTION CALL"); }
                if index > 0 && index as usize <= s.numbers.len() {
                    let number = s.numbers[index as usize - 1];
                    next = Some(if s.mode == "GOTO" {
                        self.line(number)?
                    } else {
                        self.subroutine(number, next)?
                    });
                }
            }
            "RETURN" => {
                let found = self.stack.iter().rposition(|f| f.kind == "GOSUB");
                let Some(index) = found else { return fault("RETURN WITHOUT GOSUB"); };
                next = self.stack[index].position;
                self.stack.truncate(index);
            }
            "FOR" => {
                let mut vals = Vec::new();
                for e in &s.expressions { vals.push(self.evaluate(e)?.number()); }
                let (start, end, step) = (vals[0], vals[1], vals[2]);
                if step == 0 { return fault("ILLEGAL FUNCTION CALL"); }
                if let Some(index) = self.search("FOR", &s.name) {
                    self.stack.truncate(index);
                }
                self.vars.insert(s.name.clone(), Value::Integer(start));
                if if step > 0 { start > end } else { start < end } {
                    next = self.matching(id, "FOR", "NEXT")?;
                } else {
                    self.push(Frame {
                        kind: "FOR".into(), position: next, name: s.name,
                        limit: end, step,
                    })?;
                }
            }
            "NEXT" => {
                let Some(index) = self.search("FOR", &s.name) else {
                    return fault("NEXT WITHOUT FOR");
                };
                self.stack.truncate(index + 1);
                let frame = self.stack[index].clone();
                let value = Self::checked(self.get(&frame.name).number() + frame.step)?;
                self.vars.insert(frame.name, Value::Integer(value));
                if if frame.step > 0 { value > frame.limit } else { value < frame.limit } {
                    self.stack.pop();
                } else {
                    next = frame.position;
                }
            }
            "WHILE" => {
                if self.evaluate(s.expression.as_ref().unwrap())?.number() != 0 {
                    self.push(Frame {
                        kind: "WHILE".into(), position: Some(id),
                        name: String::new(), limit: 0, step: 0,
                    })?;
                } else {
                    next = self.matching(id, "WHILE", "WEND")?;
                }
            }
            "WEND" => {
                let Some(index) = self.search("WHILE", "") else {
                    return fault("WEND WITHOUT WHILE");
                };
                next = self.stack[index].position;
                self.stack.truncate(index);
            }
            "DIM" => {
                for target in &s.targets {
                    let name = target.value.text();
                    let mut bounds = Vec::new();
                    for e in &target.args { bounds.push(self.evaluate(e)?.number()); }
                    if self.arrays.contains_key(name) { return fault("DUPLICATE DEFINITION"); }
                    if bounds.iter().any(|n| *n < 0) { return fault("ILLEGAL FUNCTION CALL"); }
                    let size = bounds.iter().fold(1_i64, |a, b| a * (b + 1));
                    if size > 10000 { return fault("OUT OF MEMORY"); }
                    self.declare(name, &bounds);
                }
            }
            "RANDOMIZE" => {
                let seed = self.evaluate(s.expression.as_ref().unwrap())?.number();
                if seed < 1 { return fault("ILLEGAL FUNCTION CALL"); }
                self.random = seed;
            }
            "handler" => {
                if s.numbers[0] != 0 { self.line(s.numbers[0])?; }
                self.handler = s.numbers[0];
            }
            "RESUME" => {
                if !self.handling { return fault("RESUME WITHOUT ERROR"); }
                next = if s.mode == "line" {
                    Some(self.line(s.numbers[0])?)
                } else if s.mode == "NEXT" {
                    self.program[self.remembered.unwrap()].next
                } else {
                    self.remembered
                };
                self.handling = false;
            }
            "STOP" => {
                self.message(format!("BREAK IN LINE {}", s.line));
                return Ok(None);
            }
            "END" => return Ok(None),
            _ => unreachable!(),
        }
        Ok(next)
    }

    fn connect(&mut self, body: &[usize], after: Option<usize>, line: i64) {
        let mut next = after;
        for id in body.iter().rev().copied() {
            self.program[id].line = line;
            self.program[id].next = next;
            let clauses = self.program[id].clauses.clone();
            for clause in clauses {
                self.connect(&clause.body, next, line);
            }
            next = Some(id);
        }
    }

    fn finish(&mut self) -> Vec<String> {
        if !self.buffer.is_empty() { self.end_line(); }
        self.output.push("READY".into());
        std::mem::take(&mut self.output)
    }

    fn run(&mut self, source: &BTreeMap<i64, String>) -> Vec<String> {
        let mut parsed = Vec::new();
        for (line, content) in source {
            let result = tokenize(content).and_then(|tokens| {
                Parser { tokens, position: 0, program: &mut self.program }.parse()
            });
            match result {
                Ok(statements) => parsed.push((*line, statements)),
                Err(_) => {
                    self.message(format!("ERROR IN LINE {}: SYNTAX ERROR", line));
                    return self.finish();
                }
            }
        }
        let mut following = None;
        for (line, body) in parsed.iter().rev() {
            self.connect(body, following, *line);
            self.entries.insert(*line, body[0]);
            following = Some(body[0]);
        }
        for (line, body) in &parsed {
            for id in body {
                self.sequence.push(*id);
                if self.program[*id].kind == "DATA" {
                    for value in &self.program[*id].values {
                        self.data.push((*line, value.clone()));
                    }
                }
            }
        }
        let mut position = following;
        while let Some(id) = position {
            match self.execute(id) {
                Ok(next) => position = next,
                Err(Failure::Runtime(problem)) => {
                    if self.handler != 0 && !self.handling {
                        self.err = error_code(&problem);
                        self.erl = self.program[id].line;
                        self.remembered = Some(id);
                        self.handling = true;
                        position = self.line(self.handler).ok();
                    } else {
                        self.message(format!(
                            "ERROR IN LINE {}: {}", self.program[id].line, problem,
                        ));
                        position = None;
                    }
                }
                Err(Failure::Syntax) => unreachable!(),
            }
        }
        self.finish()
    }
}

impl Value {
    fn text_if(&self) -> &str {
        if let Value::Text(s) = self { s } else { "" }
    }
}

fn error_code(problem: &str) -> i64 {
    match problem {
        "NEXT WITHOUT FOR" => 1,
        "RETURN WITHOUT GOSUB" => 3,
        "OUT OF DATA" => 4,
        "ILLEGAL FUNCTION CALL" => 5,
        "OVERFLOW" => 6,
        "OUT OF MEMORY" => 7,
        "UNDEFINED LINE NUMBER" => 8,
        "SUBSCRIPT OUT OF RANGE" => 9,
        "DUPLICATE DEFINITION" => 10,
        "DIVISION BY ZERO" => 11,
        "TYPE MISMATCH" => 13,
        "STRING TOO LONG" => 15,
        "RESUME WITHOUT ERROR" => 20,
        "FOR WITHOUT NEXT" => 26,
        "WHILE WITHOUT WEND" => 29,
        "WEND WITHOUT WHILE" => 30,
        "INPUT PAST END" => 62,
        _ => unreachable!(),
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let sessions = lines.next().unwrap_or("0").parse::<usize>().unwrap();
    let mut output = Vec::new();
    for _ in 0..sessions {
        let mut source = BTreeMap::new();
        for line in lines.by_ref() {
            if line == "RUN" { break; }
            let bytes = line.as_bytes();
            let mut i = 0;
            while i < bytes.len() && bytes[i].is_ascii_digit() { i += 1; }
            let number = line[..i].parse::<i64>().unwrap();
            if i == bytes.len() {
                source.remove(&number);
            } else {
                let content = line[i..].trim_start_matches(' ').to_owned();
                source.insert(number, content);
            }
        }
        let mut data = Vec::new();
        for line in lines.by_ref() {
            if line == "END" { break; }
            data.push(line.to_owned());
        }
        output.extend(Machine::new(data).run(&source));
    }
    if !output.is_empty() {
        println!("{}", output.join("\n"));
    }
}
