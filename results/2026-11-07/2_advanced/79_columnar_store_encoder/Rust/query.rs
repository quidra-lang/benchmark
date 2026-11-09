#[derive(Clone)] pub enum Literal {
    Integer(i64),
    String(String),
    Boolean(bool)
}
#[derive(Clone)] pub enum Condition {
    Comparison(String,String,Vec<Literal>),
    Not(Box<Condition>),
    Binary(bool,Box<Condition>,Box<Condition>)
}
pub struct Item {
    pub column: Option<String>,
    pub aggregate: Option<String>,
    pub distinct: bool
}
impl Item {
    pub fn header(&self) -> String {
        let column = self.column.as_deref().unwrap_or("*");
        if let Some(aggregate) = &self.aggregate {
            format!("{}({}{})",aggregate,if self.distinct {
                "DISTINCT "
            } else {
                ""
            },column)
        } else {
            column.to_owned()
        }
    }
}
pub struct Query {
    pub items: Vec<Item>,
    pub star: bool,
    pub condition: Option<Condition>,
    pub group: Option<String>,
    pub order: Option<(String,bool)>,
    pub limit: Option<usize>
}
struct Parser {
    tokens: Vec<String>,
    at: usize
}
fn lex(source: &str) -> Vec<String> {
    let bytes = source.as_bytes();
    let mut at = 0;
    let mut result = Vec::new();
    while at < bytes.len() {
        if bytes[at] == b' ' {
            at += 1;
            continue;
        }
        let first = at;
        if bytes[at] == b'\'' {
            at += 1;
            while bytes[at] != b'\'' {
                at += 1;
            }
            at += 1;
        } else if bytes[at].is_ascii_alphanumeric() || bytes[at] == b'-' {
            at += 1;
            while at < bytes.len() && (bytes[at].is_ascii_alphanumeric() || bytes[at] == b'_') {
                at += 1;
            }
        } else {
            at += 1;
            if at < bytes.len() && ((bytes[first] == b'<' && (bytes[at] == b'=' || bytes[at] == b'>')) || (bytes[first] == b'>' && bytes[at] == b'=')) {
                at += 1;
            }
        }
        result.push(source[first..at].to_owned());
    }
    result
}
impl Parser {
    fn peek(&self) -> &str {
        self.tokens.get(self.at).map_or("",String::as_str)
    }
    fn take(&mut self) -> String {
        let value = self.tokens[self.at].clone();
        self.at += 1;
        value
    }
    fn literal(&mut self) -> Literal {
        let token = self.take();
        if token.starts_with('\'') {
            Literal::String(token[1..token.len()-1].to_owned())
        } else if token == "TRUE" || token == "FALSE" {
            Literal::Boolean(token == "TRUE")
        } else {
            Literal::Integer(token.parse().unwrap())
        }
    }
    fn condition(&mut self) -> Condition {
        let mut left = self.conjunction();
        while self.peek() == "OR" {
            self.take();
            left = Condition::Binary(false,Box::new(left),Box::new(self.conjunction()));
        }
        left
    }
    fn conjunction(&mut self) -> Condition {
        let mut left = self.negation();
        while self.peek() == "AND" {
            self.take();
            left = Condition::Binary(true,Box::new(left),Box::new(self.negation()));
        }
        left
    }
    fn negation(&mut self) -> Condition {
        if self.peek() == "NOT" {
            self.take();
            return Condition::Not(Box::new(self.negation()));
        }
        if self.peek() == "(" {
            self.take();
            let condition = self.condition();
            self.take();
            return condition;
        }
        let name = self.take();
        let mut operator = self.take();
        let mut literals = Vec::new();
        match operator.as_str() {
            "IS" => {
                if self.peek() == "NOT" {
                    self.take();
                    operator.push_str(" NOT");
                }
                self.take();
                operator.push_str(" NULL");
            },"BETWEEN" => {
                literals.push(self.literal());
                self.take();
                literals.push(self.literal());
            },"IN" => {
                self.take();
                loop {
                    literals.push(self.literal());
                    if self.peek() != "," {
                        break;
                    }
                    self.take();
                }
                self.take();
            },_ => literals.push(self.literal())
        }
        Condition::Comparison(name,operator,literals)
    }
}
pub fn parse(source: &str) -> Query {
    let mut parser = Parser {
        tokens: lex(source),
        at: 0
    };
    parser.take();
    let mut items = Vec::new();
    let star = parser.peek() == "*";
    if star {
        parser.take();
    } else {
        loop {
            let first = parser.take();
            if ["COUNT","SUM","AVG","MIN","MAX"].contains(&first.as_str()) {
                parser.take();
                let distinct = parser.peek() == "DISTINCT";
                if distinct {
                    parser.take();
                }
                let name = parser.take();
                parser.take();
                items.push(Item {
                    column: if name == "*" {
                        None
                    } else {
                        Some(name)
                    },
                    aggregate: Some(first),
                    distinct
                });
            } else {
                items.push(Item {
                    column: Some(first),
                    aggregate: None,
                    distinct: false
                });
            }
            if parser.peek() != "," {
                break;
            }
            parser.take();
        }
    }
    let condition = if parser.peek() == "WHERE" {
        parser.take();
        Some(parser.condition())
    } else {
        None
    };
    let group = if parser.peek() == "GROUP" {
        parser.take();
        parser.take();
        Some(parser.take())
    } else {
        None
    };
    let order = if parser.peek() == "ORDER" {
        parser.take();
        parser.take();
        let name = parser.take();
        let descending = parser.peek() == "DESC";
        if parser.peek() == "ASC" || descending {
            parser.take();
        }
        Some((name,descending))
    } else {
        None
    };
    let limit = if parser.peek() == "LIMIT" {
        parser.take();
        Some(parser.take().parse().unwrap())
    } else {
        None
    };
    Query {
        items,
        star,
        condition,
        group,
        order,
        limit
    }
}
