use std::collections::HashMap;
use crate::tiles;
type Key = ([u8;34],usize,usize,bool);
fn standard(counts: [u8;34], sets: usize, partials: usize, pair: bool, memo: &mut HashMap<Key,i64>) -> i64 {
    let key = (counts,sets,partials,pair);
    if let Some(&value) = memo.get(&key) {
        return value;
    }
    let mut best = 8-2*sets as i64-partials.min(4-sets) as i64-i64::from(pair);
    let Some(first) = counts.iter().position(|&n| n > 0) else {
        return best;
    };
    let mut trial = counts;
    trial[first] -= 1;
    best = best.min(standard(trial,sets,partials,pair,memo));
    if sets < 4 && counts[first] >= 3 {
        let mut trial = counts;
        trial[first] -= 3;
        best = best.min(standard(trial,sets+1,partials,pair,memo));
    }
    if sets < 4 && first < 27 && first%9 <= 6 && counts[first+1] > 0 && counts[first+2] > 0 {
        let mut trial = counts;
        for k in first..=first+2 {
            trial[k] -= 1;
        }
        best = best.min(standard(trial,sets+1,partials,pair,memo));
    }
    if counts[first] >= 2 {
        let mut trial = counts;
        trial[first] -= 2;
        if !pair {
            best = best.min(standard(trial,sets,partials,true,memo));
        }
        if partials < 4 {
            best = best.min(standard(trial,sets,partials+1,pair,memo));
        }
    }
    if partials < 4 && first < 27 {
        for gap in 1..=2 {
            if first%9+gap < 9 && counts[first+gap] > 0 {
                let mut trial = counts;
                trial[first] -= 1;
                trial[first+gap] -= 1;
                best = best.min(standard(trial,sets,partials+1,pair,memo));
            }
        }
    }
    memo.insert(key,best);
    best
}
pub fn calculate(counts: &[u8;34]) -> [i64;3] {
    let distinct = counts.iter().filter(|&&n| n > 0).count();
    let pairs = counts.iter().filter(|&&n| n >= 2).count();
    let yaochuu = (0..34).filter(|&k| tiles::yaochuu(k) && counts[k] > 0).count();
    let pair = (0..34).any(|k| tiles::yaochuu(k) && counts[k] >= 2);
    [standard(*counts,0,0,false,&mut HashMap::new()),6-pairs as i64+0i64.max(7-distinct as i64),13-yaochuu as i64-i64::from(pair)]
}
