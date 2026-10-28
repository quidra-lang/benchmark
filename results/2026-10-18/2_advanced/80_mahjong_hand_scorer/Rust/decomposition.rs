use std::collections::BTreeSet;
use crate::tiles;
#[derive(Clone,Copy,PartialEq,Eq,PartialOrd,Ord)] pub struct Set {
    pub start: usize,
    pub sequence: bool
}
impl Set {
    pub fn kinds(&self) -> Vec<usize> {
        if self.sequence {
            vec![self.start,self.start+1,self.start+2]
        } else {
            vec![self.start;3]
        }
    }
}
pub struct Decomposition {
    pub pair: usize,
    pub sets: Vec<Set>
}
pub fn standard(counts: &[u8;34], melds: usize) -> Vec<Decomposition> {
    fn visit(counts: &mut [u8;34], sets: &mut Vec<Set>, needed: usize, pair: usize, result: &mut BTreeSet<(usize,Vec<Set>)>) {
        let Some(first) = counts.iter().position(|&n| n > 0) else {
            if sets.len() == needed {
                let mut sets = sets.clone();
                sets.sort();
                result.insert((pair,sets));
            }
            return;
        };
        if sets.len() == needed {
            return;
        }
        if counts[first] >= 3 {
            counts[first] -= 3;
            sets.push(Set {
                start: first,
                sequence: false
            });
            visit(counts,sets,needed,pair,result);
            sets.pop();
            counts[first] += 3;
        }
        if first < 27 && first%9 <= 6 && counts[first+1] > 0 && counts[first+2] > 0 {
            for k in first..=first+2 {
                counts[k] -= 1;
            }
            sets.push(Set {
                start: first,
                sequence: true
            });
            visit(counts,sets,needed,pair,result);
            sets.pop();
            for k in first..=first+2 {
                counts[k] += 1;
            }
        }
    }
    let mut result = BTreeSet::new();
    for pair in 0..34 {
        if counts[pair] >= 2 {
            let mut remainder = *counts;
            remainder[pair] -= 2;
            visit(&mut remainder,&mut Vec::new(),4-melds,pair,&mut result);
        }
    }
    result.into_iter().map(|(pair,sets)| Decomposition {
        pair,
        sets
    }).collect()
}
pub fn chiitoitsu(counts: &[u8;34], melds: usize) -> bool {
    melds == 0 && counts.iter().filter(|&&n| n == 2).count() == 7 && counts.iter().map(|&n| n as usize).sum::<usize>() == 14
}
pub fn kokushi(counts: &[u8;34], melds: usize) -> bool {
    melds == 0 && (0..34).all(|k| if tiles::yaochuu(k) {
        counts[k] > 0
    } else {
        counts[k] == 0
    }) && counts.iter().map(|&n| n as usize).sum::<usize>() == 14
}
pub fn winning(counts: &[u8;34], melds: usize) -> bool {
    chiitoitsu(counts,melds) || kokushi(counts,melds) || !standard(counts,melds).is_empty()
}
pub fn waiting(hand: &[u8;34], meld_counts: &[u8;34], melds: usize) -> Vec<usize> {
    let mut result = Vec::new();
    for kind in 0..34 {
        if hand[kind]+meld_counts[kind] <= 3 {
            let mut trial = *hand;
            trial[kind] += 1;
            if winning(&trial,melds) {
                result.push(kind);
            }
        }
    }
    result
}
pub fn shape(set: Option<Set>, winning: usize) -> &'static str {
    match set {
        None => "tanki",Some(set) => if !set.sequence {
            "shanpon"
        } else if winning == set.start+1 {
            "kanchan"
        } else if (set.start%9 == 0 && winning == set.start+2) || (set.start%9 == 6 && winning == set.start) {
            "penchan"
        } else {
            "ryanmen"
        }
    }
}
