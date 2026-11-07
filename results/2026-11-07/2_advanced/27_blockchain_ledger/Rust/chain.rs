use std::rc::Rc;
use crate::{
    blocks::Block, transactions::Utxo
};
pub struct BlockRecord {
    pub block: Block,
    pub parent: Option<Rc<BlockRecord>>,
    pub utxo: Utxo,
    pub transaction_fees: Vec<i64>,
    pub fees: i64,
    pub source: String,
    pub cumulative_work: i64
}
impl BlockRecord {
    pub fn new(block: Block, parent: Option<Rc<BlockRecord>>, utxo: Utxo, transaction_fees: Vec<i64>, source: String) -> Rc<Self> {
        let cumulative_work = parent.as_ref().map_or(1, |p|p.cumulative_work+16i64.pow(block.difficulty as u32));
        let fees = transaction_fees.iter().sum();
        Rc::new(Self {
            block,
            parent,
            utxo,
            transaction_fees,
            fees,
            source,
            cumulative_work
        })
    }
}
pub fn reward(height: usize, initial: i64, interval: usize) -> i64 {
    let mut a = initial;
    for _ in 0..height/interval {
        a /= 2;
    }
    a
}
pub fn ancestor(mut r: Rc<BlockRecord>, height: usize) -> Rc<BlockRecord> {
    while r.block.height>height {
        r = r.parent.as_ref().unwrap().clone();
    }
    r
}
pub fn chain_to(mut r: Rc<BlockRecord>) -> Vec<Rc<BlockRecord>> {
    let mut out = vec![];
    loop {
        out.push(r.clone());
        if let Some(p) = &r.parent {
            r = p.clone();
        }else {
            break
        }
    }
    out.reverse();
    out
}
pub fn fork_point(a: Rc<BlockRecord>, b: Rc<BlockRecord>) -> Rc<BlockRecord> {
    let h = a.block.height.min(b.block.height);
    let mut a = ancestor(a, h);
    let mut b = ancestor(b, h);
    while a.block.hash != b.block.hash {
        a = a.parent.as_ref().unwrap().clone();
        b = b.parent.as_ref().unwrap().clone();
    }
    a
}
pub fn median_time(r: Rc<BlockRecord>) -> i64 {
    let mut times = vec![];
    let mut next = Some(r);
    while let Some(r) = next {
        times.push(r.block.timestamp);
        if times.len() == 3 {
            break
        }
        next = r.parent.clone();
    }
    times.sort();
    times[(times.len()-1)/2]
}
pub fn required_difficulty(p: Rc<BlockRecord>, initial: usize, interval: usize, target: i64) -> usize {
    let h = p.block.height+1;
    let d = p.block.difficulty;
    if h == 1 {
        return initial
    }
    if h%interval != 0 {
        return d
    }
    let span = p.block.timestamp-ancestor(p.clone(), h-interval).block.timestamp;
    let expected = target*(interval as i64-1);
    if 2*span<expected {
        (d+1).min(2)
    }else if span>2*expected {
        d.saturating_sub(1)
    }else {
        d
    }
}
