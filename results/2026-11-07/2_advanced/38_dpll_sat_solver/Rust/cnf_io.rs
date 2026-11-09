use crate::Formula;
use std::fs;

pub fn number(text: &str) -> Option<usize> {
    if text.is_empty() || text.len() > 6 || !text.bytes().all(|b| b.is_ascii_digit()) || (text.len() > 1 && text.starts_with('0')) { None } else { text.parse().ok() }
}

pub fn read(name: &str) -> Result<Formula, String> {
    let text = fs::read_to_string(format!("input/{name}")).unwrap();
    let mut header = None;
    let mut clauses = Vec::new();
    let mut clause = Vec::new();
    for (index, line) in text.lines().enumerate() {
        let line_number = index + 1;
        if line.starts_with('c') { continue; }
        let tokens: Vec<_> = line.split_whitespace().collect();
        if tokens.is_empty() { continue; }
        if tokens[0] == "p" {
            if header.is_some() { return Err(format!("duplicate header at line {line_number}")); }
            if tokens.len() != 4 || tokens[1] != "cnf" || number(tokens[2]).is_none() || number(tokens[3]).is_none() {
                return Err(format!("bad header at line {line_number}"));
            }
            header = Some((number(tokens[2]).unwrap(), number(tokens[3]).unwrap()));
        } else {
            let Some((variables, _)) = header else { return Err("missing header".into()); };
            for token in tokens {
                let digits = token.strip_prefix('-').unwrap_or(token);
                let valid = token == "0" || (digits != "0" && number(digits).is_some());
                if !valid { return Err(format!("bad token {token} at line {line_number}")); }
                let literal: i64 = token.parse().unwrap();
                if literal.unsigned_abs() as usize > variables { return Err(format!("literal out of range {token} at line {line_number}")); }
                if literal == 0 { clauses.push(std::mem::take(&mut clause)); } else { clause.push(literal); }
            }
        }
    }
    let Some((variables, declared)) = header else { return Err("missing header".into()); };
    if !clause.is_empty() { return Err("unterminated clause".into()); }
    if clauses.len() != declared { return Err(format!("clause count mismatch header={declared} found={}", clauses.len())); }
    Ok(Formula { variables, clauses })
}

pub fn model_lines(model: &[bool]) -> Vec<String> {
    let mut literals: Vec<_> = (1..model.len()).map(|x| if model[x] { x.to_string() } else { format!("-{x}") }).collect();
    literals.push("0".into());
    literals.chunks(10).map(|chunk| format!("v {}", chunk.join(" "))).collect()
}
