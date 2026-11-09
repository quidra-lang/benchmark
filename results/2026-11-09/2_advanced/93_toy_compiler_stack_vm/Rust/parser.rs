use crate::lexer::{
    Position,
    Token,
    Error
};
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Type {
    Int,
    Bool,
    Void
}
impl Type {
    pub fn text(self) -> &'static str {
        match self {
            Self::Int => "int",
            Self::Bool => "bool",
            Self::Void => "void"
        }
    }
}
#[derive(Clone)]
pub struct Expression {
    pub position: Position,
    pub kind: ExprKind,
    pub symbol: Option<usize>,
    pub ty: Option<Type>
}
#[derive(Clone)]
pub enum ExprKind {
    Literal(i64, Type),
    Variable(String),
    Array(String, Box<Expression>),
    Call(String, Vec<Expression>),
    Read,
    Unary(String, Box<Expression>),
    Binary(String, Box<Expression>, Box<Expression>)
}
#[derive(Clone)]
pub struct Declaration {
    pub ty: Type,
    pub name: String,
    pub position: Position,
    pub initializer: Option<Expression>,
    pub array: Option<(usize, Position)>,
    pub symbol: Option<usize>
}
#[derive(Clone)]
pub struct Function {
    pub ty: Type,
    pub name: String,
    pub position: Position,
    pub parameters: Vec<Declaration>,
    pub body: Statement,
    pub symbol: Option<usize>
}
#[derive(Clone)]
pub enum Top {
    Global(Declaration),
    Function(Function)
}
#[derive(Clone)]
pub struct Statement {
    pub position: Position,
    pub kind: StmtKind
}
#[derive(Clone)]
pub enum StmtKind {
    Block(Vec<Statement>, Position),
    Declaration(Declaration),
    Assignment(String, Option<Expression>, Expression, Option<usize>),
    Call(Expression),
    If(Expression, Box<Statement>, Option<Box<Statement>>),
    While(Expression, Box<Statement>),
    For(Option<Box<Statement>>, Option<Expression>, Option<Box<Statement>>, Box<Statement>),
    Break,
    Continue,
    Return(Option<Expression>),
    Print(Vec<Expression>),
    Empty
}
pub struct Program {
    pub declarations: Vec<Top>,
    pub end: Position
}
struct Parser {
    tokens: Vec<Token>,
    index: usize
}
fn priority(operator: &str) -> usize {
    match operator {
        "||" => 1,
        "&&" => 2,
        "==" | "!=" => 3,
        "<" | "<=" | ">" | ">=" => 4,
        "+" | "-" => 5,
        "*" | "/" | "%" => 6,
        _ => 0
    }
}
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
    fn error(&self) -> Error {
        let token = self.peek();
        Error {
            kind: "syntax",
            position: token.position,
            message: if token.kind == "end" {
                "unexpected end of program".into()
            } else {
                format!("unexpected '{}'", token.text)
            }
        }
    }
    fn expect(&mut self, text: &str) -> Result<Token,
    Error> {
        if self.text() == text && self.peek().kind != "end" {
            Ok(self.take())
        } else {
            Err(self.error())
        }
    }
    fn identifier(&mut self) -> Result<Token,
    Error> {
        if self.peek().kind == "identifier" {
            Ok(self.take())
        } else {
            Err(self.error())
        }
    }
    fn ty(&mut self) -> Result<Type,
    Error> {
        match self.text() {
            "int" => {
                self.take();
                Ok(Type::Int)
            },
            "bool" => {
                self.take();
                Ok(Type::Bool)
            },
            "void" => {
                self.take();
                Ok(Type::Void)
            },
            _ => Err(self.error())
        }
    }
    fn declaration(&mut self, require_initial: bool) -> Result<Declaration,
    Error> {
        let ty = self.ty()?;
        let name = self.identifier()?;
        let initializer = if self.text() == "=" {
            self.take();
            Some(self.expression(1)?)
        } else if require_initial {
            return Err(self.error());
        } else {
            None
        };
        Ok(Declaration {
            ty,
            name: name.text,
            position: name.position,
            initializer,
            array: None,
            symbol: None
        })
    }
    fn top(&mut self) -> Result<Top,
    Error> {
        let ty = self.ty()?;
        let name = self.identifier()?;
        if self.text() == "(" {
            self.take();
            let mut parameters = Vec::new();
            if self.text() != ")" {
                loop {
                    let ty = self.ty()?;
                    let name = self.identifier()?;
                    parameters.push(Declaration {
                        ty,
                        name: name.text,
                        position: name.position,
                        initializer: None,
                        array: None,
                        symbol: None
                    });
                    if self.text() != "," {
                        break;
                    }
                    self.take();
                }
            }
            self.expect(")")?;
            let body = self.block()?;
            Ok(Top::Function(Function {
                ty,
                name: name.text,
                position: name.position,
                parameters,
                body,
                symbol: None
            }))
        } else {
            let mut declaration = Declaration {
                ty,
                name: name.text,
                position: name.position,
                initializer: None,
                array: None,
                symbol: None
            };
            if self.text() == "[" {
                self.take();
                if self.peek().kind != "integer" {
                    return Err(self.error());
                }
                let size = self.take();
                declaration.array = Some((size.text.parse().unwrap(), size.position));
                self.expect("]")?;
            }
            else if self.text() == "=" {
                self.take();
                declaration.initializer = Some(self.expression(1)?);
            }
            self.expect(";")?;
            Ok(Top::Global(declaration))
        }
    }
    fn block(&mut self) -> Result<Statement,
    Error> {
        let open = self.expect("{")?;
        let mut statements = Vec::new();
        while self.text() != "}" && self.peek().kind != "end" {
            if ["int", "bool", "void"].contains(&self.text()) {
                let position = self.peek().position;
                let declaration = self.declaration(false)?;
                self.expect(";")?;
                statements.push(Statement {
                    position,
                    kind: StmtKind::Declaration(declaration)
                });
            }
            else {
                statements.push(self.statement()?);
            }
        }
        let close = self.expect("}")?;
        Ok(Statement {
            position: open.position,
            kind: StmtKind::Block(statements, close.position)
        })
    }
    fn statement(&mut self) -> Result<Statement,
    Error> {
        let position = self.peek().position;
        let kind = match self.text() {
            "{" => return self.block(),
            "if" => {
                self.take();
                self.expect("(")?;
                let condition = self.expression(1)?;
                self.expect(")")?;
                let yes = Box::new(self.statement()?);
                let no = if self.text() == "else" {
                    self.take();
                    Some(Box::new(self.statement()?))
                } else {
                    None
                };
                StmtKind::If(condition, yes, no)
            },
            "while" => {
                self.take();
                self.expect("(")?;
                let condition = self.expression(1)?;
                self.expect(")")?;
                StmtKind::While(condition, Box::new(self.statement()?))
            },
            "for" => {
                self.take();
                self.expect("(")?;
                let init = if self.text() == ";" {
                    None
                } else if ["int", "bool", "void"].contains(&self.text()) {
                    let position = self.peek().position;
                    Some(Box::new(Statement {
                        position,
                        kind: StmtKind::Declaration(self.declaration(true)?)
                    }))
                } else {
                    Some(Box::new(self.simple()?))
                };
                self.expect(";")?;
                let condition = if self.text() == ";" {
                    None
                } else {
                    Some(self.expression(1)?)
                };
                self.expect(";")?;
                let update = if self.text() == ")" {
                    None
                } else {
                    Some(Box::new(self.simple()?))
                };
                self.expect(")")?;
                StmtKind::For(init, condition, update, Box::new(self.statement()?))
            },
            "break" => {
                self.take();
                self.expect(";")?;
                StmtKind::Break
            },
            "continue" => {
                self.take();
                self.expect(";")?;
                StmtKind::Continue
            },
            "return" => {
                self.take();
                let value = if self.text() == ";" {
                    None
                } else {
                    Some(self.expression(1)?)
                };
                self.expect(";")?;
                StmtKind::Return(value)
            },
            "print" => {
                self.take();
                self.expect("(")?;
                let mut values = vec![self.expression(1)?];
                while self.text() == "," {
                    self.take();
                    values.push(self.expression(1)?);
                }
                self.expect(")")?;
                self.expect(";")?;
                StmtKind::Print(values)
            },
            _ => {
                let statement = self.simple()?;
                self.expect(";")?;
                return Ok(statement);
            }
        };
        Ok(Statement {
            position,
            kind
        })
    }
    fn arguments(&mut self) -> Result<Vec<Expression>,
    Error> {
        self.expect("(")?;
        let mut arguments = Vec::new();
        if self.text() != ")" {
            arguments.push(self.expression(1)?);
            while self.text() == "," {
                self.take();
                arguments.push(self.expression(1)?);
            }
        }
        self.expect(")")?;
        Ok(arguments)
    }
    fn simple(&mut self) -> Result<Statement,
    Error> {
        let position = self.peek().position;
        if self.text() == "read" {
            self.take();
            self.expect("(")?;
            self.expect(")")?;
            return Ok(Statement {
                position,
                kind: StmtKind::Call(Expression {
                    position,
                    kind: ExprKind::Read,
                    symbol: None,
                    ty: None
                })
            });
        }
        let name = self.identifier()?;
        if self.text() == "(" {
            let arguments = self.arguments()?;
            return Ok(Statement {
                position,
                kind: StmtKind::Call(Expression {
                    position,
                    kind: ExprKind::Call(name.text, arguments),
                    symbol: None,
                    ty: None
                })
            });
        }
        let index = if self.text() == "[" {
            self.take();
            let index = self.expression(1)?;
            self.expect("]")?;
            Some(index)
        } else {
            None
        };
        self.expect("=")?;
        let value = self.expression(1)?;
        Ok(Statement {
            position,
            kind: StmtKind::Assignment(name.text, index, value, None)
        })
    }
    fn expression(&mut self, minimum: usize) -> Result<Expression,
    Error> {
        let mut left = self.unary()?;
        loop {
            let precedence = priority(self.text());
            if precedence < minimum || precedence == 0 {
                break;
            }
            let operator = self.take();
            let right = self.expression(precedence + 1)?;
            left = Expression {
                position: operator.position,
                kind: ExprKind::Binary(operator.text, Box::new(left), Box::new(right)),
                symbol: None,
                ty: None
            };
        }
        Ok(left)
    }
    fn unary(&mut self) -> Result<Expression,
    Error> {
        if self.text() == "-" || self.text() == "!" {
            let operator = self.take();
            let child = self.unary()?;
            return Ok(Expression {
                position: operator.position,
                kind: ExprKind::Unary(operator.text, Box::new(child)),
                symbol: None,
                ty: None
            });
        }
        let token = self.peek().clone();
        let position = token.position;
        let kind = if token.kind == "integer" {
            self.take();
            ExprKind::Literal(token.text.parse().unwrap(), Type::Int)
        }
        else if token.text == "true" || token.text == "false" {
            self.take();
            ExprKind::Literal(if token.text == "true" {
                1
            } else {
                0
            }, Type::Bool)
        }
        else if token.text == "read" {
            self.take();
            self.expect("(")?;
            self.expect(")")?;
            ExprKind::Read
        }
        else if token.text == "(" {
            self.take();
            let inner = self.expression(1)?;
            self.expect(")")?;
            return Ok(inner);
        }
        else if token.kind == "identifier" {
            self.take();
            if self.text() == "(" {
                ExprKind::Call(token.text, self.arguments()?)
            } else if self.text() == "[" {
                self.take();
                let index = self.expression(1)?;
                self.expect("]")?;
                ExprKind::Array(token.text, Box::new(index))
            } else {
                ExprKind::Variable(token.text)
            }
        }
        else {
            return Err(self.error());
        };
        Ok(Expression {
            position,
            kind,
            symbol: None,
            ty: None
        })
    }
}
pub fn parse(tokens: Vec<Token>) -> Result<Program, Error> {
    let mut parser = Parser {
        tokens,
        index: 0
    };
    let mut declarations = Vec::new();
    while parser.peek().kind != "end" {
        declarations.push(parser.top()?);
    }
    Ok(Program {
        declarations,
        end: parser.peek().position
    })
}
