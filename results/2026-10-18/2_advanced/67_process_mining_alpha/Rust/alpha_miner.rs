use crate::dfg::{self, Counts, Log};
pub type Pair = (u16, u16);

pub fn indices(mask: u16, count: usize) -> Vec<usize> { (0..count).filter(|&i| mask&(1<<i) != 0).collect() }
pub fn candidate(pair: Pair, relations: &[Vec<String>]) -> bool {
    let (a, b) = (indices(pair.0, relations.len()), indices(pair.1, relations.len()));
    !a.is_empty() && !b.is_empty() && a.iter().all(|&x| b.iter().all(|&y| relations[x][y] == "->"))
        && a.iter().all(|&x| a.iter().all(|&y| relations[x][y] == "#"))
        && b.iter().all(|&x| b.iter().all(|&y| relations[x][y] == "#"))
}
pub fn compare(a: &Pair, b: &Pair, count: usize) -> std::cmp::Ordering {
    indices(a.0, count).cmp(&indices(b.0, count)).then(indices(a.1, count).cmp(&indices(b.1, count)))
}
pub fn triangles(log: &Log) -> Counts {
    let mut counts = Counts::new();
    for (trace, weight) in log { for triple in trace.windows(3) {
        if triple[0] == triple[2] && triple[0] != triple[1] { *counts.entry((triple[0].clone(), triple[1].clone())).or_default() += weight; }
    } }
    counts
}
pub fn plus_relation(counts: &Counts, triangles: &Counts, a: &str, b: &str) -> &'static str {
    let ab = dfg::get(counts, a, b) > 0;
    let ba = dfg::get(counts, b, a) > 0;
    let loop2 = a != b && dfg::get(triangles, a, b) > 0 && dfg::get(triangles, b, a) > 0;
    if ab && (!ba || loop2) { "->" } else if ba && (!ab || loop2) { "<-" } else if ab && ba { "||" } else { "#" }
}
