use crate::lexer::{
    Token,
    Position
};
#[derive(Clone)]
pub struct Expression {
    pub position: Position,
    pub kind: ExprKind
}
#[derive(Clone)]
pub enum ExprKind {
    Number(i64),
    String(String),
    Name(String),
    Index(String, Vec<Expression>),
    Field(Box<Expression>),
    Parentheses(Box<Expression>),
    Unary(String, Box<Expression>),
    Binary(String, Box<Expression>, Box<Expression>),
    Assignment(String, Box<Expression>, Box<Expression>),
    Increment(i64, bool, Box<Expression>),
    Conditional(Box<Expression>, Box<Expression>, Box<Expression>),
    In(Vec<Expression>, String, Position),
    Call(String, bool, Vec<Expression>),
    Getline(Option<Box<Expression>>, Option<Box<Expression>>),
}
impl Expression {
    pub fn lvalue(&self) -> bool {
        matches!(self.kind, ExprKind::Name(_) | ExprKind::Index(_, _) | ExprKind::Field(_))
    }
}
#[derive(Clone)]
pub struct Statement {
    pub position: Position,
    pub kind: StmtKind
}
#[derive(Clone)]
pub enum StmtKind {
    Block(Vec<Statement>),
    Empty,
    Expression(Expression),
    If(Expression, Box<Statement>, Option<Box<Statement>>),
    While(Expression, Box<Statement>),
    Do(Box<Statement>, Expression),
    For(Option<Expression>, Option<Expression>, Option<Expression>, Box<Statement>),
    ForIn(String, Position, String, Position, Box<Statement>),
    Output(bool, Vec<Expression>, Option<(bool, Expression, Position)>),
    Delete(String, Position, Option<Vec<Expression>>),
    Next,
    Break,
    Continue,
    Exit(Option<Expression>),
    Return(Option<Expression>),
}
#[derive(Clone)]
pub struct Function {
    pub name: String,
    pub position: Position,
    pub parameters: Vec<(String, Position)>,
    pub body: Statement
}
#[derive(Clone)]
pub struct Rule {
    pub kind: &'static str,
    pub position: Position,
    pub start: Option<Expression>,
    pub end: Option<Expression>,
    pub action: Option<Statement>
}
pub struct Program {
    pub rules: Vec<Rule>,
    pub functions: Vec<Function>
}
struct Parser {
    tokens: Vec<Token>,
    index: usize,
    function: bool,
    special: bool,
    loops: usize
}
type Result<T> = std::result::Result<T, Position>;
impl Parser {
    fn peek(&self) -> &Token {
        &self.tokens[self.index]
    }
    fn text(&self) -> &str {
        &self.peek().text
    }
    fn take(&mut self) -> Token {
        let token = self.peek().clone();
        if token.kind != "end" {
            self.index += 1;
        }
        token
    }
    fn expect(&mut self, text: &str) -> Result<Token> {
        if self.text() == text && self.peek().kind != "end" {
            Ok(self.take())
        } else {
            Err(self.peek().position)
        }
    }
    fn name(&mut self) -> Result<Token> {
        if self.peek().kind == "name" {
            Ok(self.take())
        } else {
            Err(self.peek().position)
        }
    }
    fn newlines(&mut self) {
        while self.peek().kind == "newline" {
            self.take();
        }
    }
    fn terminator(&mut self) -> Result<()> {
        if self.text() == ";" || self.peek().kind == "newline" {
            self.take();
            Ok(())
        } else if self.text() == "}" {
            Ok(())
        } else {
            Err(self.peek().position)
        }
    }
    fn expressions(&mut self, suppress: bool) -> Result<Vec<Expression>> {
        let mut expressions = vec![self.expression(suppress)?];
        while self.text() == "," {
            self.take();
            self.newlines();
            expressions.push(self.expression(suppress)?);
        }
        Ok(expressions)
    }
    fn expression(&mut self, suppress: bool) -> Result<Expression> {
        let left = self.conditional(suppress)?;
        if left.lvalue() && ["=", "+=", "-=", "*=", "/=", "%=", "^="].contains(&self.text()) {
            let token = self.take();
            let right = self.expression(suppress)?;
            Ok(Expression {
                position: token.position,
                kind: ExprKind::Assignment(token.text, Box::new(left), Box::new(right))
            })
        } else {
            Ok(left)
        }
    }
    fn conditional(&mut self, suppress: bool) -> Result<Expression> {
        let condition = self.binary(1, suppress)?;
        if self.text() == "?" {
            let token = self.take();
            let yes = self.conditional(suppress)?;
            self.expect(":")?;
            let no = self.conditional(suppress)?;
            Ok(Expression {
                position: token.position,
                kind: ExprKind::Conditional(Box::new(condition), Box::new(yes), Box::new(no))
            })
        } else {
            Ok(condition)
        }
    }
    fn binary(&mut self, minimum: usize, suppress: bool) -> Result<Expression> {
        let mut left = self.unary(suppress)?;
        loop {
            let explicit = match self.text() {
                "||" => 1,
                "&&" => 2,
                "in" => 3,
                "<" | "<=" | "==" | "!=" | ">=" => 4,
                ">" if !suppress => 4,
                "+" | "-" => 6,
                "*" | "/" | "%" => 7,
                _ => 0
            };
            let concat = explicit == 0 && (["number", "string", "name", "function", "builtin"].contains(&self.peek().kind) || ["$", "(", "++", "--"].contains(&self.text()));
            let precedence = if concat {
                5
            } else {
                explicit
            };
            if precedence == 0 || precedence < minimum {
                break;
            }
            if explicit == 3 {
                let token = self.take();
                let name = self.name()?;
                left = Expression {
                    position: token.position,
                    kind: ExprKind::In(vec![left], name.text, name.position)
                };
                continue;
            }
            let position = self.peek().position;
            let operator = if concat {
                "concat".to_string()
            } else {
                self.take().text
            };
            if operator == "||" || operator == "&&" {
                self.newlines();
            }
            let right = self.binary(precedence + 1, suppress)?;
            left = Expression {
                position,
                kind: ExprKind::Binary(operator, Box::new(left), Box::new(right))
            };
        }
        Ok(left)
    }
    fn unary(&mut self, suppress: bool) -> Result<Expression> {
        if ["!", "-", "+"].contains(&self.text()) {
            let token = self.take();
            let body = self.unary(suppress)?;
            return Ok(Expression {
                position: token.position,
                kind: ExprKind::Unary(token.text, Box::new(body))
            });
        }
        let left = self.postfix(suppress)?;
        if self.text() == "^" {
            let token = self.take();
            let right = self.unary(suppress)?;
            Ok(Expression {
                position: token.position,
                kind: ExprKind::Binary(token.text, Box::new(left), Box::new(right))
            })
        } else {
            Ok(left)
        }
    }
    fn prefix(&mut self, suppress: bool) -> Result<Expression> {
        let token = self.take();
        let lvalue = self.lvalue(suppress)?;
        Ok(Expression {
            position: token.position,
            kind: ExprKind::Increment(if token.text == "++" {
                1
            } else {
                -1
            }, true, Box::new(lvalue))
        })
    }
    fn postfix(&mut self, suppress: bool) -> Result<Expression> {
        if self.text() == "++" || self.text() == "--" {
            return self.prefix(suppress);
        }
        let body = self.atom(suppress)?;
        if body.lvalue() && (self.text() == "++" || self.text() == "--") {
            let token = self.take();
            Ok(Expression {
                position: token.position,
                kind: ExprKind::Increment(if token.text == "++" {
                    1
                } else {
                    -1
                }, false, Box::new(body))
            })
        } else {
            Ok(body)
        }
    }
    fn lvalue(&mut self, suppress: bool) -> Result<Expression> {
        if self.peek().kind != "name" && self.text() != "$" {
            return Err(self.peek().position);
        }
        self.atom(suppress)
    }
    fn atom(&mut self, suppress: bool) -> Result<Expression> {
        let token = self.peek().clone();
        let position = token.position;
        let kind = match token.kind {
            "number" => {
                self.take();
                ExprKind::Number(token.text.parse().unwrap())
            },
            "string" => {
                self.take();
                ExprKind::String(token.value)
            },
            "name" => {
                self.take();
                if self.text() == "[" {
                    self.take();
                    let indices = self.expressions(false)?;
                    self.expect("]")?;
                    ExprKind::Index(token.text, indices)
                } else {
                    ExprKind::Name(token.text)
                }
            },
            "function" | "builtin" => {
                self.take();
                let builtin = token.kind == "builtin";
                let mut arguments = Vec::new();
                if self.text() == "(" {
                    self.take();
                    if self.text() != ")" {
                        arguments = self.expressions(false)?;
                    }
                    self.expect(")")?;
                }
                else if !builtin || token.text != "length" {
                    return Err(self.peek().position);
                }
                if builtin {
                    let n = arguments.len();
                    let valid = match token.text.as_str() {
                        "length" => n <= 1,
                        "substr" => n == 2 || n == 3,
                        "index" => n == 2,
                        "split" => (n == 2 || n == 3) && matches!(arguments[1].kind, ExprKind::Name(_)),
                        "sprintf" => n >= 1,
                        _ => n == 1
                    };
                    if !valid {
                        return Err(position);
                    }
                }
                ExprKind::Call(token.text, builtin, arguments)
            },
            _ => match token.text.as_str() {
                "$" => {
                    self.take();
                    let field = if self.text() == "++" || self.text() == "--" {
                        self.prefix(suppress)?
                    } else {
                        self.atom(suppress)?
                    };
                    ExprKind::Field(Box::new(field))
                },
                "(" => {
                    self.take();
                    let expressions = self.expressions(false)?;
                    self.expect(")")?;
                    if expressions.len() == 1 {
                        ExprKind::Parentheses(Box::new(expressions.into_iter().next().unwrap()))
                    }
                    else {
                        self.expect("in")?;
                        let name = self.name()?;
                        ExprKind::In(expressions, name.text, name.position)
                    }
                },
                "getline" => {
                    self.take();
                    let target = if self.peek().kind == "name" || self.text() == "$" {
                        Some(Box::new(self.lvalue(suppress)?))
                    } else {
                        None
                    };
                    let file = if self.text() == "<" {
                        self.take();
                        Some(Box::new(self.atom(suppress)?))
                    } else {
                        None
                    };
                    ExprKind::Getline(target, file)
                },
                _ => return Err(position)
            }
        };
        Ok(Expression {
            position,
            kind
        })
    }
    fn block(&mut self) -> Result<Statement> {
        let position = self.expect("{")?.position;
        let mut statements = Vec::new();
        while self.text() != "}" {
            if self.peek().kind == "newline" || self.text() == ";" {
                self.take();
            } else {
                statements.push(self.statement()?);
            }
        }
        self.expect("}")?;
        Ok(Statement {
            position,
            kind: StmtKind::Block(statements)
        })
    }
    fn loop_body(&mut self) -> Result<Box<Statement>> {
        self.newlines();
        self.loops += 1;
        let body = self.statement()?;
        self.loops -= 1;
        Ok(Box::new(body))
    }
    fn statement(&mut self) -> Result<Statement> {
        let token = self.peek().clone();
        let position = token.position;
        let kind;
        match token.text.as_str() {
            "{" => return self.block(),
            ";" => {
                self.take();
                return Ok(Statement {
                    position,
                    kind: StmtKind::Empty
                });
            },
            "if" => {
                self.take();
                self.expect("(")?;
                let condition = self.expression(false)?;
                self.expect(")")?;
                self.newlines();
                let yes = Box::new(self.statement()?);
                self.newlines();
                let no = if self.text() == "else" {
                    self.take();
                    self.newlines();
                    Some(Box::new(self.statement()?))
                } else {
                    None
                };
                return Ok(Statement {
                    position,
                    kind: StmtKind::If(condition, yes, no)
                });
            },
            "while" => {
                self.take();
                self.expect("(")?;
                let condition = self.expression(false)?;
                self.expect(")")?;
                let body = self.loop_body()?;
                return Ok(Statement {
                    position,
                    kind: StmtKind::While(condition, body)
                });
            },
            "do" => {
                self.take();
                let body = self.loop_body()?;
                self.newlines();
                self.expect("while")?;
                self.expect("(")?;
                let condition = self.expression(false)?;
                self.expect(")")?;
                kind = StmtKind::Do(body, condition);
            },
            "for" => {
                self.take();
                self.expect("(")?;
                let for_in = self.tokens.get(self.index).map_or(false, |t| t.kind == "name") && self.tokens.get(self.index + 1).map_or(false, |t| t.text == "in") && self.tokens.get(self.index + 2).map_or(false, |t| t.kind == "name") && self.tokens.get(self.index + 3).map_or(false, |t| t.text == ")");
                if for_in {
                    let variable = self.name()?;
                    self.take();
                    let array = self.name()?;
                    self.take();
                    let body = self.loop_body()?;
                    return Ok(Statement {
                        position,
                        kind: StmtKind::ForIn(variable.text, variable.position, array.text, array.position, body)
                    });
                }
                let init = if self.text() == ";" {
                    None
                } else {
                    Some(self.expression(false)?)
                };
                self.expect(";")?;
                self.newlines();
                let condition = if self.text() == ";" {
                    None
                } else {
                    Some(self.expression(false)?)
                };
                self.expect(";")?;
                self.newlines();
                let update = if self.text() == ")" {
                    None
                } else {
                    Some(self.expression(false)?)
                };
                self.expect(")")?;
                let body = self.loop_body()?;
                return Ok(Statement {
                    position,
                    kind: StmtKind::For(init, condition, update, body)
                });
            },
            "print" | "printf" => {
                self.take();
                let printf = token.text == "printf";
                let empty = [";", "\n", "}", ">", ">>"].contains(&self.text());
                let mut parenthesized = false;
                if self.text() == "(" {
                    let mut depth = 0;
                    for i in self.index..self.tokens.len() {
                        if self.tokens[i].text == "(" {
                            depth += 1;
                        } else if self.tokens[i].text == ")" {
                            depth -= 1;
                            if depth == 0 {
                                parenthesized = self.tokens.get(i + 1).map_or(false, |t| [";", "\n", "}", ">", ">>"].contains(&t.text.as_str()) || t.kind == "end");
                                break;
                            }
                        }
                    }
                }
                if empty && printf {
                    return Err(self.peek().position);
                }
                let arguments = if empty {
                    Vec::new()
                } else if parenthesized {
                    self.take();
                    let arguments = self.expressions(false)?;
                    self.expect(")")?;
                    arguments
                } else {
                    self.expressions(true)?
                };
                let redirect = if self.text() == ">" || self.text() == ">>" {
                    let op = self.take();
                    Some((op.text == ">>", self.binary(5, false)?, op.position))
                } else {
                    None
                };
                kind = StmtKind::Output(printf, arguments, redirect);
            },
            "delete" => {
                self.take();
                let name = self.name()?;
                let indices = if self.text() == "[" {
                    self.take();
                    let indices = self.expressions(false)?;
                    self.expect("]")?;
                    Some(indices)
                } else {
                    None
                };
                kind = StmtKind::Delete(name.text, name.position, indices);
            },
            "next" => {
                self.take();
                if self.special && !self.function {
                    return Err(position);
                }
                kind = StmtKind::Next;
            },
            "break" | "continue" => {
                self.take();
                if self.loops == 0 {
                    return Err(position);
                }
                kind = if token.text == "break" {
                    StmtKind::Break
                } else {
                    StmtKind::Continue
                };
            },
            "exit" | "return" => {
                self.take();
                if token.text == "return" && !self.function {
                    return Err(position);
                }
                let value = if [";", "\n", "}"].contains(&self.text()) {
                    None
                } else {
                    Some(self.expression(false)?)
                };
                kind = if token.text == "exit" {
                    StmtKind::Exit(value)
                } else {
                    StmtKind::Return(value)
                };
            },
            _ => kind = StmtKind::Expression(self.expression(false)?)
        }
        self.terminator()?;
        Ok(Statement {
            position,
            kind
        })
    }
}
pub fn parse(tokens: Vec<Token>) -> Result<Program> {
    let mut parser = Parser {
        tokens,
        index: 0,
        function: false,
        special: false,
        loops: 0
    };
    let mut program = Program {
        rules: Vec::new(),
        functions: Vec::new()
    };
    while parser.peek().kind != "end" {
        if parser.text() == ";" || parser.peek().kind == "newline" {
            parser.take();
            continue;
        }
        let position = parser.peek().position;
        if parser.text() == "function" {
            parser.take();
            if parser.peek().kind != "name" && parser.peek().kind != "function" {
                return Err(parser.peek().position);
            }
            let name = parser.take();
            parser.expect("(")?;
            let mut parameters = Vec::new();
            if parser.text() != ")" {
                loop {
                    let parameter = parser.name()?;
                    parameters.push((parameter.text, parameter.position));
                    if parser.text() != "," {
                        break;
                    }
                    parser.take();
                    parser.newlines();
                }
            }
            parser.expect(")")?;
            parser.newlines();
            parser.function = true;
            let body = parser.block()?;
            parser.function = false;
            program.functions.push(Function {
                name: name.text,
                position: name.position,
                parameters,
                body
            });
        } else if parser.text() == "BEGIN" || parser.text() == "END" {
            let begin = parser.take().text == "BEGIN";
            parser.special = true;
            let action = parser.block()?;
            parser.special = false;
            program.rules.push(Rule {
                kind: if begin {
                    "BEGIN"
                } else {
                    "END"
                },
                position,
                start: None,
                end: None,
                action: Some(action)
            });
        } else if parser.text() == "{" {
            let action = parser.block()?;
            program.rules.push(Rule {
                kind: "all",
                position,
                start: None,
                end: None,
                action: Some(action)
            });
        }
        else {
            let start = parser.expression(false)?;
            let end = if parser.text() == "," {
                parser.take();
                parser.newlines();
                Some(parser.expression(false)?)
            } else {
                None
            };
            let action = if parser.text() == "{" {
                Some(parser.block()?)
            } else {
                if parser.text() != ";" && parser.peek().kind != "newline" && parser.peek().kind != "end" {
                    return Err(parser.peek().position);
                }
                None
            };
            program.rules.push(Rule {
                kind: if end.is_some() {
                    "range"
                } else {
                    "pattern"
                },
                position,
                start: Some(start),
                end,
                action
            });
        }
    }
    Ok(program)
}
