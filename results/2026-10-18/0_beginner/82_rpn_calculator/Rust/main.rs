fn main() {
    for expression in ["3 4 + 2 *", "-17 5 / 4 -3 * -", "1 2 + * 3", "15 7 1 1 + - / 3 * 2 1 1 + + -",
        "4 2 5 * + 1 3 2 * - 5 + /", "2 3 4 + 5", "46341 46339 * -2 /"] {
        let mut stack: Vec<i64> = Vec::new();
        let mut error = None;
        for token in expression.split(' ') {
            if token.len() == 1 && "+-*/".contains(token) {
                if stack.len() < 2 {
                    error = Some("stack underflow");
                    break;
                }
                let b = stack.pop().unwrap();
                let a = stack.pop().unwrap();
                if token == "/" && b == 0 {
                    error = Some("division by zero");
                    break;
                }
                let value = match token {
                    "+" => a + b,
                    "-" => a - b,
                    "*" => a * b,
                    _ => a / b,
                };
                stack.push(value);
            } else {
                stack.push(token.parse().unwrap());
            }
        }
        if error.is_none() && stack.len() != 1 {
            error = Some("leftover operands");
        }
        if let Some(message) = error {
            println!("{} => error: {}", expression, message);
        } else {
            println!("{} => {}", expression, stack[0]);
        }
    }
}
