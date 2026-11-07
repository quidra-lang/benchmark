use crate::line_solver::FILLED;

pub fn is_line(text: &str) -> bool {
    !text.is_empty() && text.bytes().all(|c| c.is_ascii_digit() || c == b' ')
}

pub fn parse(text: &str) -> Option<Vec<usize>> {
    if text == "0" { return Some(Vec::new()); }
    text.split(' ').map(|token| {
        if token.is_empty() || token.len() > 2 || token.starts_with('0') || !token.bytes().all(|c| c.is_ascii_digit()) { None }
        else { token.parse().ok() }
    }).collect()
}

pub fn run(cells: &[u8]) -> Vec<usize> {
    let mut clue = Vec::new();
    let mut count = 0;
    for &state in cells {
        if state == FILLED { count += 1; }
        else if count > 0 { clue.push(count); count = 0; }
    }
    if count > 0 { clue.push(count); }
    clue
}

pub fn text(clue: &[usize], separator: &str) -> String {
    if clue.is_empty() { "0".into() } else { clue.iter().map(usize::to_string).collect::<Vec<_>>().join(separator) }
}

pub fn span(clue: &[usize]) -> usize { clue.iter().sum::<usize>() + clue.len().saturating_sub(1) }
