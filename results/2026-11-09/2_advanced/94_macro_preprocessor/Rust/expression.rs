use crate::lexer::Token;
enum Expression {
    Value(i64),
    Name(String),
    Unary(String, Box<Expression>),
    Binary(String, Box<Expression>, Box<Expression>),
    Conditional(Box<Expression>, Box<Expression>, Box<Expression>)
}
fn precedence(op: &str) -> usize {
    match op {
        "||" => 1,
        "&&" => 2,
        "|" => 3,
        "^" => 4,
        "&" => 5,
        "==" | "!=" => 6,
        "<" | ">" | "<=" | ">=" => 7,
        "<<" | ">>" => 8,
        "+" | "-" => 9,
        "*" | "/" | "%" => 10,
        _ => 0
    }
}
fn constant(token: &Token) -> Result<i64, String> {
    let text = token.text.as_str();
    if token.kind == "character" {
        let body = &text[1..text.len() - 1];
        let bytes = body.as_bytes();
        if bytes.len() == 1 && bytes[0] != b'\'' && bytes[0] != b'\\' {
            return Ok(bytes[0] as i64);
        }
        if bytes.len() == 2 && bytes[0] == b'\\' {
            let value = match bytes[1] {
                b'n' => Some(10),
                b't' => Some(9),
                b'\\' => Some(92),
                b'\'' => Some(39),
                b'"' => Some(34),
                b'0' => Some(0),
                _ => None
            };
            if let Some(value) = value {
                return Ok(value);
            }
        }
        return Err(format!("invalid character constant {}", text));
    }
    let mut body = text;
    for suffix in ["ll", "LL", "l", "L"] {
        if body.len() > suffix.len() && body.ends_with(suffix) {
            body = &body[..body.len() - suffix.len()];
            break;
        }
    }
    let (digits, base) = if body.starts_with("0x") || body.starts_with("0X") {
        (&body[2..], 16)
    } else if body.starts_with('0') {
        (body, 8)
    } else {
        (body, 10)
    };
    if !digits.is_empty() && digits.bytes().all(|b| match base {
        16 => b.is_ascii_hexdigit(),
        8 => b >= b'0' && b <= b'7',
        _ => b.is_ascii_digit()
    }) {
        if let Ok(value) = i64::from_str_radix(digits, base) {
            return Ok(value);
        }
    }
    Err(format!("invalid integer constant \"{}\"", text))
}
struct Parser<'a> {
    tokens: &'a [Token],
    index: usize
}
impl<'a> Parser<'a> {
    fn text(&self) -> &str {
        self.tokens.get(self.index).map_or("", |t| t.text.as_str())
    }
    fn expression(&mut self) -> Result<Expression,
    String> {
        let left = self.binary(1)?;
        if self.text() == "?" {
            self.index += 1;
            let yes = self.expression()?;
            if self.text() != ":" {
                return Err("'?' without following ':'".into());
            }
            self.index += 1;
            let no = self.expression()?;
            Ok(Expression::Conditional(Box::new(left), Box::new(yes), Box::new(no)))
        } else {
            Ok(left)
        }
    }
    fn binary(&mut self, minimum: usize) -> Result<Expression,
    String> {
        let mut left = self.unary()?;
        loop {
            let p = precedence(self.text());
            if p == 0 || p < minimum {
                break;
            }
            let op = self.text().to_string();
            self.index += 1;
            let right = self.binary(p + 1)?;
            left = Expression::Binary(op, Box::new(left), Box::new(right));
        }
        Ok(left)
    }
    fn unary(&mut self) -> Result<Expression,
    String> {
        if ["+", "-", "!", "~"].contains(&self.text()) {
            let op = self.text().into();
            self.index += 1;
            return Ok(Expression::Unary(op, Box::new(self.unary()?)));
        }
        let token = self.tokens.get(self.index).ok_or("expected value at end of expression")?;
        self.index += 1;
        if token.kind == "number" || token.kind == "character" {
            Ok(Expression::Value(constant(token)?))
        }
        else if token.kind == "identifier" {
            Ok(Expression::Name(token.text.clone()))
        }
        else if token.text == "(" {
            let expression = self.expression()?;
            if self.text() != ")" {
                return Err("missing ')' in expression".into());
            }
            self.index += 1;
            Ok(expression)
        }
        else {
            Err(format!("expected value before \"{}\"", token.text))
        }
    }
}
fn evaluate(expression: &Expression, diagnostics: &mut Vec<(&'static str, String)>) -> Result<i64, String> {
    match expression {
        Expression::Value(value) => Ok(*value),
        Expression::Name(name) => {
            diagnostics.push(("warning", format!("identifier \"{}\" evaluates to 0", name)));
            Ok(0)
        },
        Expression::Unary(op, value) => {
            let value = evaluate(value, diagnostics)?;
            Ok(match op.as_str() {
                "+" => value,
                "-" => -value,
                "!" => if value == 0 {
                    1
                } else {
                    0
                },
                _ => -value - 1
            })
        },
        Expression::Conditional(condition, yes, no) => if evaluate(condition, diagnostics)? != 0 {
            evaluate(yes, diagnostics)
        } else {
            evaluate(no, diagnostics)
        },
        Expression::Binary(op, a, b) => {
            let a = evaluate(a, diagnostics)?;
            if op == "&&" && a == 0 {
                return Ok(0);
            }
            if op == "||" && a != 0 {
                return Ok(1);
            }
            let b = evaluate(b, diagnostics)?;
            if (op == "/" || op == "%") && b == 0 {
                return Err("division by zero in #if".into());
            }
            Ok(match op.as_str() {
                "+" => a + b,
                "-" => a - b,
                "*" => a * b,
                "/" => a / b,
                "%" => a % b,
                "<<" => a << b,
                ">>" => a >> b,
                "&" => a & b,
                "|" => a | b,
                "^" => a ^ b,
                "&&" | "||" => if b != 0 {
                    1
                } else {
                    0
                },
                "<" => if a < b {
                    1
                } else {
                    0
                },
                ">" => if a > b {
                    1
                } else {
                    0
                },
                "<=" => if a <= b {
                    1
                } else {
                    0
                },
                ">=" => if a >= b {
                    1
                } else {
                    0
                },
                "==" => if a == b {
                    1
                } else {
                    0
                },
                "!=" => if a != b {
                    1
                } else {
                    0
                },
                _ => unreachable!()
            })
        }
    }
}
pub fn test(tokens: &[Token], directive: &str) -> (Option<i64>, Vec<(&'static str, String)>) {
    let mut parser = Parser {
        tokens,
        index: 0
    };
    let mut diagnostics = Vec::new();
    let parsed = if tokens.is_empty() {
        Err(format!("#{} with no expression", directive))
    } else {
        parser.expression().and_then(|tree| if parser.index != tokens.len() {
            Err(format!("missing binary operator before \"{}\"", tokens[parser.index].text))
        } else {
            Ok(tree)
        })
    };
    let result = parsed.and_then(|tree| evaluate(&tree, &mut diagnostics));
    match result {
        Ok(value) => (Some(value), diagnostics),
        Err(message) => {
            diagnostics.push(("error", message));
            (None, diagnostics)
        }
    }
}
