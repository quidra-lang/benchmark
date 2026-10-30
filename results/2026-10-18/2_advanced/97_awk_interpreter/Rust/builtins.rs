use crate::lexer::Position;
use crate::values_fields::Value;
pub struct RuntimeError {
    pub position: Position,
    pub message: String
}
pub fn error(position: Position, message: &str) -> RuntimeError {
    RuntimeError {
        position,
        message: message.into()
    }
}
pub fn format(values: &[Value], position: Position) -> Result<String, RuntimeError> {
    let text = values[0].text();
    let bytes = text.as_bytes();
    let mut output = String::new();
    let mut i = 0;
    let mut argument = 1;
    while i < bytes.len() {
        if bytes[i] != b'%' {
            output.push(bytes[i] as char);
            i += 1;
            continue;
        }
        i += 1;
        if bytes.get(i) == Some(&b'%') {
            output.push('%');
            i += 1;
            continue;
        }
        let mut left = false;
        let mut zero = false;
        while bytes.get(i).map_or(false, |b| *b == b'-' || *b == b'0') {
            left |= bytes[i] == b'-';
            zero |= bytes[i] == b'0';
            i += 1;
        }
        let start = i;
        while bytes.get(i).map_or(false, |b| b.is_ascii_digit()) {
            i += 1;
        }
        let width: usize = text[start..i].parse().unwrap_or(0);
        let precision = if bytes.get(i) == Some(&b'.') {
            i += 1;
            let start = i;
            while bytes.get(i).map_or(false, |b| b.is_ascii_digit()) {
                i += 1;
            }
            Some(text[start..i].parse::<usize>().unwrap_or(0))
        } else {
            None
        };
        let conversion = *bytes.get(i).ok_or_else(|| error(position, "invalid format"))?;
        i += 1;
        if !b"dis cxo".contains(&conversion) || conversion == b' ' {
            return Err(error(position, "invalid format"));
        }
        let value = values.get(argument).ok_or_else(|| error(position, "not enough arguments"))?;
        argument += 1;
        let numeric = b"dixo".contains(&conversion);
        let mut body;
        if numeric {
            let n = value.number();
            let mut digits = match conversion {
                b'x' => format!("{:x}", n.abs()),
                b'o' => format!("{:o}", n.abs()),
                _ => n.abs().to_string()
            };
            if let Some(p) = precision {
                if p == 0 && n == 0 {
                    digits.clear();
                } else if digits.len() < p {
                    digits = "0".repeat(p - digits.len()) + &digits;
                }
            }
            body = if n < 0 {
                "-".to_string() + &digits
            } else {
                digits
            };
        } else if conversion == b's' {
            body = value.text();
            if let Some(p) = precision {
                body.truncate(p.min(body.len()));
            }
        }
        else if matches!(value, Value::Number(_) | Value::Numeric(_, _)) {
            let code = value.number();
            if code != 10 && !(32..=126).contains(&code) {
                return Err(error(position, "invalid character code"));
            }
            body = (code as u8 as char).to_string();
        } else {
            body = value.text().chars().next().map(|c| c.to_string()).unwrap_or_default();
        }
        if body.len() < width {
            let padding = width - body.len();
            if left {
                body.push_str(&" ".repeat(padding));
            }
            else if numeric && zero && precision.is_none() {
                if body.starts_with('-') {
                    body = "-".to_string() + &"0".repeat(padding) + &body[1..];
                } else {
                    body = "0".repeat(padding) + &body;
                }
            }
            else {
                body = " ".repeat(padding) + &body;
            }
        }
        output.push_str(&body);
    }
    Ok(output)
}
pub fn scalar(name: &str, values: &[Value], position: Position) -> Result<Value, RuntimeError> {
    Ok(match name {
        "substr" => {
            let text = values[0].text();
            let start = values[1].number();
            let end = if values.len() == 3 {
                start + values[2].number()
            } else {
                text.len() as i64 + 1
            };
            let start = start.max(1);
            let end = end.min(text.len() as i64 + 1);
            Value::String(if end > start {
                text[(start - 1) as usize..(end - 1) as usize].into()
            } else {
                String::new()
            })
        },
        "index" => {
            let text = values[0].text();
            let target = values[1].text();
            Value::Number(if target.is_empty() {
                0
            } else {
                text.find(&target).map_or(0, |i| (i + 1) as i64)
            })
        },
        "toupper" => Value::String(values[0].text().to_ascii_uppercase()),
        "tolower" => Value::String(values[0].text().to_ascii_lowercase()),
        "int" => Value::Number(values[0].number()),
        "sprintf" => Value::String(format(values, position)?),
        _ => unreachable!()
    })
}
