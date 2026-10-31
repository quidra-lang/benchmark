use std::collections::BTreeMap;

struct Parser<'a> {
    tokens: Vec<String>,
    position: usize,
    variables: &'a BTreeMap<String, i64>,
}

impl Parser<'_> {
    fn unary(&mut self) -> Result<i64, String> {
        let token = self.tokens[self.position].clone();
        self.position += 1;
        if token == "-" {
            return Ok(-self.unary()?);
        }
        if token == "(" {
            let value = self.sum()?;
            self.position += 1;
            return Ok(value);
        }
        if token.as_bytes()[0].is_ascii_digit() {
            return Ok(token.parse().unwrap());
        }
        self.variables
            .get(&token)
            .copied()
            .ok_or_else(|| format!("undefined variable {}", token))
    }

    fn product(&mut self) -> Result<i64, String> {
        let mut value = self.unary()?;
        while self.position < self.tokens.len()
            && (self.tokens[self.position] == "*" || self.tokens[self.position] == "/")
        {
            let operation = self.tokens[self.position].clone();
            self.position += 1;
            let right = self.unary()?;
            if operation == "/" && right == 0 {
                return Err("division by zero".to_string());
            }
            value = if operation == "*" {
                value * right
            } else {
                value / right
            };
        }
        Ok(value)
    }

    fn sum(&mut self) -> Result<i64, String> {
        let mut value = self.product()?;
        while self.position < self.tokens.len()
            && (self.tokens[self.position] == "+" || self.tokens[self.position] == "-")
        {
            let operation = self.tokens[self.position].clone();
            self.position += 1;
            let right = self.product()?;
            value = if operation == "+" {
                value + right
            } else {
                value - right
            };
        }
        Ok(value)
    }
}

fn tokenize(line: &str) -> Vec<String> {
    let bytes = line.as_bytes();
    let (mut tokens, mut i) = (Vec::new(), 0);
    while i < bytes.len() {
        if bytes[i] == b' ' {
            i += 1;
            continue;
        }
        let start = i;
        if bytes[i].is_ascii_digit() {
            while i < bytes.len() && bytes[i].is_ascii_digit() {
                i += 1;
            }
        } else if bytes[i].is_ascii_lowercase() {
            while i < bytes.len() && bytes[i].is_ascii_lowercase() {
                i += 1;
            }
        } else {
            i += 1;
        }
        tokens.push(line[start..i].to_string());
    }
    tokens
}

fn main() {
    let mut variables = BTreeMap::new();
    for line in [
        "width = 12",
        "height = width - 5",
        "area = width * height",
        "(area + 6) / 4",
        "shift = -area / 8 + 3",
        "height = 100 / (height - 7) + bonus",
        "volume = area * depth",
        "width = (width+3)*-(2-4)",
        "width * shift - height",
    ] {
        let tokens = tokenize(line);
        let assignment = tokens.len() > 1 && tokens[1] == "=";
        let mut parser = Parser {
            tokens,
            position: if assignment { 2 } else { 0 },
            variables: &variables,
        };
        match parser.sum() {
            Err(error) => println!("error: {}", error),
            Ok(value) => {
                if assignment {
                    let name = parser.tokens[0].clone();
                    variables.insert(name.clone(), value);
                    println!("{} = {}", name, value);
                } else {
                    println!("{}", value);
                }
            }
        }
    }
}
