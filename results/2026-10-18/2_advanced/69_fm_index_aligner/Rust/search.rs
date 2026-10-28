use crate::fm_index::Index;

pub fn lower_bound(sequence: &[u8], reverse: &Index) -> Vec<i32> {
    let mut z = 0; let mut interval = (0, reverse.bwt.len()); let mut result = Vec::new();
    for &c in sequence { interval = reverse.extend(interval, c); if interval.0 >= interval.1 { z += 1; interval = (0, reverse.bwt.len()); } result.push(z); }
    result
}
pub struct Search { pub nodes: usize, pub leaves: usize, pub hits: Vec<(usize, usize)> }
pub fn backtrack(sequence: &[u8], maximum: usize, forward: &Index, reverse: &Index) -> Search {
    let bounds = lower_bound(sequence, reverse); let mut result = Search { nodes: 0, leaves: 0, hits: Vec::new() };
    let mut stack = vec![(sequence.len() as i32-1, maximum as i32, 0, forward.bwt.len())];
    while let Some((i, z, lo, hi)) = stack.pop() {
        result.nodes += 1;
        if z < if i < 0 { 0 } else { bounds[i as usize] } { continue; }
        if i < 0 {
            result.leaves += 1;
            for row in lo..hi { result.hits.push((forward.locate(row).0, maximum-z as usize)); }
        } else {
            for base in [b'T', b'G', b'C', b'A'] {
                let same = sequence[i as usize] == base;
                if !same && z == 0 { continue; }
                let next = forward.extend((lo, hi), base);
                if next.0 < next.1 { stack.push((i-1, z-i32::from(!same), next.0, next.1)); }
            }
        }
    }
    result
}
