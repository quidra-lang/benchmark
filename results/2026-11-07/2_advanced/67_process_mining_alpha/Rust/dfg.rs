use std::collections::BTreeMap;
pub type Log = Vec<(Vec<String>, i64)>;
pub type Counts = BTreeMap<(String, String), i64>;

pub fn counts(log: &Log) -> Counts {
    let mut counts = Counts::new();
    for (trace, weight) in log { for pair in trace.windows(2) { *counts.entry((pair[0].clone(), pair[1].clone())).or_default() += weight; } }
    counts
}
pub fn get(counts: &Counts, a: &str, b: &str) -> i64 { *counts.get(&(a.to_owned(), b.to_owned())).unwrap_or(&0) }
pub fn relation(counts: &Counts, a: &str, b: &str) -> &'static str {
    match (get(counts, a, b) > 0, get(counts, b, a) > 0) {
        (true, false) => "->", (false, true) => "<-", (true, true) => "||", _ => "#",
    }
}
pub fn table(values: &[Vec<String>], width: usize) -> Vec<String> {
    let n = values.len();
    let mut lines = vec![format!("    {}", (1..=n).map(|i| format!("{:>width$}", i, width=width)).collect::<String>())];
    for (i, row) in values.iter().enumerate() { lines.push(format!("{:>4}{}", i+1, row.iter().map(|v| format!("{:>width$}", v, width=width)).collect::<String>())); }
    lines
}
pub fn footprint(names: &[String], relations: &[Vec<String>]) -> Vec<String> {
    let mut lines: Vec<_> = names.iter().enumerate().map(|(i, n)| format!("ACTIVITY {} {}", i+1, n)).collect();
    lines.extend(table(relations, 4)); lines
}
