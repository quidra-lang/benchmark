use std::collections::BTreeMap;
use std::fs;
use crate::rational::Fraction as F;
pub fn name(s: &str) -> bool {
    !s.is_empty() && s.as_bytes()[0].is_ascii_lowercase() && s.bytes().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'_') && !["bounds", "integer", "binary", "free", "inf"].contains(&s)
}
pub type Terms = Vec<(String, F)>;
fn expression(items: &[&str]) -> Option<Terms> {
    let mut i = 0;
    let mut sign = F::integer(1);
    if items.first() == Some(&"-") { sign = -sign; i += 1; }
    let mut result = Vec::new();
    loop {
        let word = *items.get(i)?;
        let (coefficient, variable) = if !word.starts_with('-') {
            if let Some(number) = F::parse(word) {
                let variable = *items.get(i + 1)?;
                if !name(variable) { return None; }
                i += 2;
                (number, variable)
            } else if name(word) { i += 1; (F::integer(1), word) }
            else { return None; }
        } else { return None; };
        result.push((variable.into(), coefficient * sign));
        if i == items.len() { return Some(result); }
        sign = match items[i] { "+" => F::integer(1), "-" => F::integer(-1), _ => return None };
        i += 1;
    }
}
#[derive(Clone)]
pub struct Constraint { pub line: usize, pub name: String, pub terms: Terms, pub comparison: String, pub rhs: F }
fn constraint(items: &[&str], line: usize) -> Option<Constraint> {
    if items.len() < 4 { return None; }
    let label = items[0].strip_suffix(':')?;
    if !name(label) || !["<=", ">=", "="].contains(&items[items.len() - 2]) { return None; }
    Some(Constraint { line, name: label.into(), terms: expression(&items[1..items.len() - 2])?, comparison: items[items.len() - 2].into(), rhs: F::parse(items[items.len() - 1])? })
}
#[derive(Clone)]
pub struct Bound { pub line: usize, pub name: String, pub lower: Option<Option<F>>, pub upper: Option<Option<F>> }
fn bound(items: &[&str], line: usize) -> Option<Bound> {
    let lower = |s: &str| if s == "-inf" { Some(None) } else { F::parse(s).map(Some) };
    let upper = |s: &str| if s == "inf" { Some(None) } else { F::parse(s).map(Some) };
    if items.len() == 2 && name(items[0]) && items[1] == "free" {
        Some(Bound { line, name: items[0].into(), lower: Some(None), upper: Some(None) })
    } else if items.len() == 3 && name(items[0]) {
        let (mut lo, mut hi) = (None, None);
        match items[1] {
            ">=" => lo = Some(lower(items[2])?),
            "<=" => hi = Some(upper(items[2])?),
            "=" => { let value = Some(F::parse(items[2])?); lo = Some(value); hi = Some(value); },
            _ => return None
        }
        Some(Bound { line, name: items[0].into(), lower: lo, upper: hi })
    } else if items.len() == 5 && items[1] == "<=" && items[3] == "<=" && name(items[2]) {
        Some(Bound { line, name: items[2].into(), lower: Some(lower(items[0])?), upper: Some(upper(items[4])?) })
    } else { None }
}
#[derive(Clone)]
pub struct Parsed {
    pub maximize: bool, pub objective: Terms, pub constraints: Vec<Constraint>, pub bounds: Vec<Bound>,
    pub integers: Vec<(usize, Vec<String>)>, pub binaries: Vec<(usize, Vec<String>)>
}
pub struct Block { pub name: String, pub parsed: Option<Parsed>, pub error: Option<(usize, String)> }
fn parse_body(body: &[(usize, String)], end: usize) -> Result<Parsed, (usize, String)> {
    let mut parsed = Parsed { maximize: false, objective: Vec::new(), constraints: Vec::new(), bounds: Vec::new(), integers: Vec::new(), binaries: Vec::new() };
    let mut state = 0;
    for (line, text) in body {
        let items: Vec<_> = text.split(' ').collect();
        let valid = match state {
            0 => if text == "maximize" || text == "minimize" { parsed.maximize = text == "maximize"; state = 1; true } else { false },
            1 => if items.len() >= 2 && items[0].strip_suffix(':').map_or(false, name) {
                if let Some(terms) = expression(&items[1..]) { parsed.objective = terms; state = 2; true } else { false }
            } else { false },
            2 => if text == "subject to" { state = 3; true } else { false },
            3 | 4 => if state == 4 && ["bounds", "integer", "binary"].contains(&text.as_str()) {
                state = match text.as_str() { "bounds" => 5, "integer" => 6, _ => 7 }; true
            } else if let Some(c) = constraint(&items, *line) { parsed.constraints.push(c); state = 4; true } else { false },
            5 => if text == "integer" || text == "binary" { state = if text == "integer" { 6 } else { 7 }; true }
            else if let Some(b) = bound(&items, *line) { parsed.bounds.push(b); true } else { false },
            6 | 7 => if state == 6 && text == "binary" { state = 7; true }
            else if items.iter().all(|word| name(word)) {
                let declaration = (*line, items.iter().map(|word| word.to_string()).collect());
                if state == 6 { parsed.integers.push(declaration); } else { parsed.binaries.push(declaration); }
                true
            } else { false },
            _ => false
        };
        if !valid { return Err((*line, "syntax error".into())); }
    }
    if state < 4 { Err((end, "syntax error".into())) } else { Ok(parsed) }
}
pub fn read() -> Vec<Block> {
    let mut result = Vec::new();
    let mut model = String::new();
    let mut body = Vec::new();
    for (i, line) in fs::read_to_string("input/models.lp").unwrap().lines().enumerate() {
        if line.is_empty() || line.starts_with('#') { continue; }
        if let Some(name) = line.strip_prefix("model ") { model = name.into(); body.clear(); }
        else if line == "end" {
            let (parsed, error) = match parse_body(&body, i + 1) { Ok(parsed) => (Some(parsed), None), Err(error) => (None, Some(error)) };
            result.push(Block { name: model.clone(), parsed, error });
        } else { body.push((i + 1, line.to_string())); }
    }
    result
}
pub struct Params { pub level: usize, pub limit: usize, pub levels: BTreeMap<String, usize>, pub limits: BTreeMap<String, usize> }
pub fn params() -> Params {
    let text = fs::read_to_string("input/params.txt").unwrap();
    let items: Vec<Vec<_>> = text.lines().map(|line| line.split(' ').collect()).collect();
    let mut result = Params { level: items[0][1].parse().unwrap(), limit: items[1][1].parse().unwrap(), levels: BTreeMap::new(), limits: BTreeMap::new() };
    for row in &items[2..] {
        if row[0] == "log" { result.levels.insert(row[1].into(), row[2].parse().unwrap()); }
        else { result.limits.insert(row[1].into(), row[2].parse().unwrap()); }
    }
    result
}
