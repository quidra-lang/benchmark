use std::collections::{BTreeMap, BTreeSet};
use crate::baskets::{Basket, Frequent, Itemset, contains};

pub struct CandidateLevel { pub joined: usize, pub excluded: usize, pub pruned: usize, pub itemsets: Vec<Itemset> }

pub fn one_smaller_subsets(items: &[String]) -> Vec<Itemset> {
    (0..items.len()).map(|index| items[..index].iter().chain(&items[index + 1..]).cloned().collect()).collect()
}

pub fn generate_candidates(previous: &[Itemset], size: usize, taxonomy: Option<&BTreeMap<String, String>>) -> CandidateLevel {
    let mut ordered = previous.to_vec(); ordered.sort();
    let mut joined = Vec::new();
    for (i, first) in ordered.iter().enumerate() {
        for second in &ordered[i + 1..] {
            if first[..first.len() - 1] != second[..second.len() - 1] { break; }
            let mut candidate = first.clone(); candidate.push(second.last().unwrap().clone()); joined.push(candidate);
        }
    }
    let known: BTreeSet<Itemset> = previous.iter().cloned().collect();
    let mut result = CandidateLevel { joined: joined.len(), excluded: 0, pruned: 0, itemsets: Vec::new() };
    for candidate in joined {
        if size == 2 && taxonomy.is_some_and(|map| map.get(&candidate[0]) == Some(&candidate[1]) || map.get(&candidate[1]) == Some(&candidate[0])) { result.excluded += 1; continue; }
        if one_smaller_subsets(&candidate).iter().any(|subset| !known.contains(subset)) { result.pruned += 1; } else { result.itemsets.push(candidate); }
    }
    result
}

pub fn count_supports(baskets: &[Basket], candidates: &[Itemset]) -> Frequent {
    let mut counts: Frequent = candidates.iter().cloned().map(|items| (items, 0)).collect();
    let mut by_first: BTreeMap<&str, Vec<&Itemset>> = BTreeMap::new();
    for items in candidates { by_first.entry(&items[0]).or_default().push(items); }
    for basket in baskets {
        for item in basket {
            if let Some(candidates) = by_first.get(item.as_str()) {
                for &items in candidates { if contains(basket, items) { *counts.get_mut(items).unwrap() += 1; } }
            }
        }
    }
    counts
}
