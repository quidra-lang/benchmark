use std::collections::BTreeSet;
use crate::{
    instance::Instance, minstd::Minstd
};
pub fn gene_operations(ins: &Instance, genes: &[usize]) -> Vec<usize> {
    let mut counts = vec![0; ins.jobs.len()];
    genes.iter().map(|&j| {
        let i = ins.jobs[j].operations[counts[j]]; counts[j] += 1; i
    }).collect()
}
pub fn decode(ins: &Instance, genes: &[usize]) -> Vec<i64> {
    let mut starts = vec![0; ins.operations.len()];
    let mut ready = vec![0; ins.jobs.len()];
    let mut free = vec![0; ins.machines.len()];
    for id in gene_operations(ins, genes) {
        let o = &ins.operations[id];
        let s = ready[o.job].max(free[o.machine]);
        starts[id] = s;
        ready[o.job] = s+o.duration;
        free[o.machine] = s+o.duration;
    }
    starts
}
pub fn tournament(rng: &mut Minstd, values: &[i64], size: usize) -> usize {
    (0..size).map(|_|rng.below(values.len())).min_by_key(|&i|(values[i], i)).unwrap()
}
pub fn crossover(rng: &mut Minstd, a: &[usize], b: &[usize], jobs: usize) -> (Vec<usize>, Vec<usize>) {
    let keep: BTreeSet<usize >= (0..jobs).filter(|_|rng.below(2) == 0).collect();
    let child = |x: &[usize], y: &[usize]| {
        let mut fill = y.iter().filter(|j|!keep.contains(j));
        x.iter().map(|j|if keep.contains(j) {
            *j
        }else {
            *fill.next().unwrap()
        }).collect()
    };
    (child(a, b), child(b, a))
}
pub fn swap_mutation(rng: &mut Minstd, c: &mut [usize]) {
    let a = rng.below(c.len());
    let b = rng.below(c.len());
    c.swap(a, b);
}
pub fn insert_mutation(rng: &mut Minstd, c: &mut Vec<usize>) {
    let a = rng.below(c.len());
    let b = rng.below(c.len());
    let g = c.remove(a);
    c.insert(b, g);
}
