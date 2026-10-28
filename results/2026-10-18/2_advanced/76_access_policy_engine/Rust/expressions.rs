#[derive(Clone,PartialEq,Eq)] pub enum Value {
    Integer(i64),
    String(String),
    Boolean(bool),
    Bag(Vec<String>)
}
impl Value {
    pub fn notation(&self) -> String {
        match self {
            Self::Integer(v) => v.to_string(),Self::String(v) => format!("\"{}\"",v),Self::Boolean(v) => v.to_string(),Self::Bag(v) => format!("[{}]",v.iter().map(|s| format!("\"{}\"",s)).collect::<Vec<_>>().join(","))
        }
    }
}
#[derive(Clone)] pub enum Expr {
    Literal(Value),
    Attribute(String),
    It,
    Unary(String,Box<Expr>),
    Binary(String,Box<Expr>,Box<Expr>),
    Call(String,Vec<Expr>)
}
struct Parser {
    tokens: Vec<String>,
    at: usize
}
fn tokens(source: &str) -> Vec<String> {
    let bytes = source.as_bytes();
    let mut at = 0;
    let mut tokens = Vec::new();
    while at < bytes.len() {
        if bytes[at] == b' ' {
            at += 1;
            continue;
        }
        let first = at;
        if bytes[at] == b'"' {
            at += 1;
            while bytes[at] != b'"' {
                at += 1;
            }
            at += 1;
        } else if bytes[at].is_ascii_alphanumeric() {
            at += 1;
            while at < bytes.len() && (bytes[at].is_ascii_alphanumeric() || b"_.".contains(&bytes[at])) {
                at += 1;
            }
        } else {
            at += 1;
            if at < bytes.len() && bytes[at] == b'=' && b"=!<>".contains(&bytes[first]) {
                at += 1;
            }
        }
        tokens.push(source[first..at].to_owned());
    }
    tokens
}
impl Parser {
    fn peek(&self) -> &str {
        self.tokens.get(self.at).map_or("",String::as_str)
    }
    fn take(&mut self) -> String {
        let token = self.tokens[self.at].clone();
        self.at += 1;
        token
    }
    fn expression(&mut self, minimum: usize) -> Expr {
        let first = self.take();
        let mut left = if first == "not" || first == "-" {
            let binding = if first == "not" {
                3
            } else {
                7
            };
            Expr::Unary(first,Box::new(self.expression(binding)))
        } else if first == "(" {
            let expression = self.expression(1);
            self.take();
            expression
        } else if first == "[" {
            let mut values = Vec::new();
            if self.peek() != "]" {
                loop {
                    let value = self.take();
                    values.push(value[1..value.len()-1].to_owned());
                    if self.peek() != "," {
                        break;
                    }
                    self.take();
                }
            }
            self.take();
            Expr::Literal(Value::Bag(values))
        } else if first.starts_with('"') {
            Expr::Literal(Value::String(first[1..first.len()-1].to_owned()))
        } else if first.bytes().all(|b| b.is_ascii_digit()) {
            Expr::Literal(Value::Integer(first.parse().unwrap()))
        } else if first == "true" || first == "false" {
            Expr::Literal(Value::Boolean(first == "true"))
        } else if first == "it" {
            Expr::It
        } else if self.peek() == "(" {
            self.take();
            let mut arguments = Vec::new();
            if self.peek() != ")" {
                loop {
                    arguments.push(self.expression(1));
                    if self.peek() != "," {
                        break;
                    }
                    self.take();
                }
            }
            self.take();
            Expr::Call(first,arguments)
        } else {
            Expr::Attribute(first)
        };
        loop {
            let binding = match self.peek() {
                "or" => 1,"and" => 2,"==" | "!=" | "<" | "<=" | ">" | ">=" | "in" => 4,"+" | "-" => 5,"*" => 6,_ => 0
            };
            if binding < minimum {
                break;
            }
            let operator = self.take();
            let right = self.expression(binding+1);
            left = Expr::Binary(operator,Box::new(left),Box::new(right));
        }
        left
    }
}
pub fn parse(source: &str) -> Expr {
    Parser {
        tokens: tokens(source),
        at: 0
    }.expression(1)
}
