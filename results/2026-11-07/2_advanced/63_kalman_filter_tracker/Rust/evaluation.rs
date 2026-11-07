use crate::association;

pub fn distance(a: [f64; 2], b: [f64; 2]) -> f64 { let x = a[0]-b[0]; let y = a[1]-b[1]; (x*x+y*y).sqrt() }
pub fn real(value: f64) -> String {
    let s = format!("{:.4}", value);
    if s == "-0.0000" { "0.0000".to_owned() } else { s }
}

pub fn ospa(x: &[[f64; 2]], y: &[[f64; 2]], cutoff: f64) -> f64 {
    if x.is_empty() && y.is_empty() { return 0.0; }
    if x.is_empty() || y.is_empty() { return cutoff; }
    let (u, v) = if x.len() <= y.len() { (x, y) } else { (y, x) };
    let costs: Vec<Vec<_>> = u.iter().map(|&a| v.iter().map(|&b| {
        let d = cutoff.min(distance(a, b)); Some(d*d)
    }).collect()).collect();
    let pairs = association::optimal(&costs, v.len());
    let sum: f64 = pairs.iter().map(|&(i, j)| costs[i][j].unwrap()).sum();
    ((sum+cutoff*cutoff*(v.len()-u.len()) as f64)/v.len() as f64).sqrt()
}

pub struct Continuity { pub covered: usize, pub breaks: usize, pub swaps: usize, pub delay: Option<usize> }

pub fn continuity(labels: &[Option<usize>]) -> Continuity {
    let mut covered = 0;
    let mut groups = 0usize;
    let mut swaps = 0;
    let mut previous = None;
    let mut active = false;
    for &label in labels {
        if let Some(track) = label {
            covered += 1;
            if !active { groups += 1; }
            if previous.is_some() && previous != Some(track) { swaps += 1; }
            previous = Some(track); active = true;
        } else { active = false; }
    }
    Continuity { covered, breaks: groups.saturating_sub(1), swaps, delay: labels.iter().position(Option::is_some) }
}
