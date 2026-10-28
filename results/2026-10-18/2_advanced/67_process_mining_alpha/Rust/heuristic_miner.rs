use crate::{dfg::{self, Counts}, report::Fraction};

pub fn dependency(counts: &Counts, a: &str, b: &str) -> Fraction {
    let forward = dfg::get(counts, a, b); let reverse = dfg::get(counts, b, a);
    Fraction::new(forward-reverse, forward+reverse+1)
}
pub fn loop_measure(count: i64) -> Fraction { Fraction::new(count, count+1) }
pub fn split(counts: &Counts, a: &str, b: &str, c: &str) -> Fraction {
    Fraction::new(dfg::get(counts, b, c)+dfg::get(counts, c, b), dfg::get(counts, a, b)+dfg::get(counts, a, c)+1)
}
pub fn join(counts: &Counts, a: &str, b: &str, c: &str) -> Fraction {
    Fraction::new(dfg::get(counts, b, c)+dfg::get(counts, c, b), dfg::get(counts, b, a)+dfg::get(counts, c, a)+1)
}
