use std::collections::BTreeSet;
use crate::{dataset::Point, grid_index::distance};

pub const INF: i64 = i64::MAX;

pub struct Ordering {
    pub core: Vec<i64>,
    pub reach: Vec<i64>,
    pub predecessor: Vec<Option<usize>>,
    pub points: Vec<usize>,
}

pub fn order(points: &[Point], neighborhoods: &[Vec<usize>], min_pts: usize) -> Ordering {
    let core: Vec<i64> = neighborhoods.iter().enumerate().map(|(i, neighbors)| {
        if neighbors.len() < min_pts { return INF; }
        let mut values: Vec<i64> = neighbors.iter().map(|&j| distance(&points[i], &points[j])).collect();
        values.sort_unstable();
        values[min_pts - 1]
    }).collect();
    let mut reach = vec![INF; points.len()];
    let mut predecessor = vec![None; points.len()];
    let mut processed = vec![false; points.len()];
    let mut ordering = Vec::new();
    for start in 0..points.len() {
        if processed[start] { continue; }
        let mut seeds = BTreeSet::from([start]);
        while !seeds.is_empty() {
            let i = *seeds.iter().min_by_key(|&&i| (reach[i], points[i].id)).unwrap();
            seeds.remove(&i);
            processed[i] = true;
            ordering.push(i);
            if core[i] == INF { continue; }
            for &j in &neighborhoods[i] {
                if processed[j] { continue; }
                let candidate = core[i].max(distance(&points[i], &points[j]));
                if candidate < reach[j] {
                    reach[j] = candidate;
                    predecessor[j] = Some(i);
                    seeds.insert(j);
                }
            }
        }
    }
    Ordering { core, reach, predecessor, points: ordering }
}
