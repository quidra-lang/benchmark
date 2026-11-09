use std::{collections::BTreeMap, rc::Rc};
use crate::dataset::Row;

#[derive(Clone)]
pub struct Neighbor {
    pub gap: f64,
    pub row: Rc<Row>,
}
pub fn distance(a: &[f64], b: &[f64], metric: &str) -> f64 {
    let mut total: f64 = 0.0; let mut dot = 0.0; let mut squares_a = 0.0; let mut squares_b = 0.0;
    for (&x, &y) in a.iter().zip(b) {
        let difference = x - y;
        match metric {
            "squared_euclidean" => total += difference * difference,
            "manhattan" => total += difference.abs(),
            "chebyshev" => total = total.max(difference.abs()),
            _ => { dot += x * y; squares_a += x * x; squares_b += y * y; }
        }
    }
    if metric != "cosine" { return total; }
    let norm_a = squares_a.sqrt(); let norm_b = squares_b.sqrt();
    if norm_a == 0.0 || norm_b == 0.0 { 1.0 } else { 1.0 - dot / (norm_a * norm_b) }
}
pub fn sort_neighbors(mut neighbors: Vec<Neighbor>) -> Vec<Neighbor> {
    neighbors.sort_by(|a, b| a.gap.partial_cmp(&b.gap).unwrap().then_with(|| a.row.id.cmp(&b.row.id))); neighbors
}
#[derive(Default)]
struct Tally { count: usize, distance: f64, weight: f64 }
#[derive(Clone)]
pub struct Prediction {
    pub label: String,
    pub share: f64,
    pub runner: Option<String>,
    pub runner_share: f64,
    pub estimate: f64,
    pub neighbors: Vec<Neighbor>,
}
impl Prediction {
    pub fn from_order(order: &[Neighbor], k: usize, weighting: &str, retain: bool) -> Self {
        let nearest = &order[..k.min(order.len())]; let mut tallies = BTreeMap::<String, Tally>::new();
        let mut weight_total = 0.0; let mut target_total = 0.0; let mut weighted = 0.0;
        for neighbor in nearest {
            let weight = 1.0 / (neighbor.gap + 0.000000001); let label = neighbor.row.label.as_ref().unwrap();
            let tally = tallies.entry(label.clone()).or_default();
            tally.count += 1; tally.distance += neighbor.gap; tally.weight += weight; weight_total += weight;
            let target = neighbor.row.target.unwrap(); target_total += target; weighted += weight * target;
        }
        let uniform = weighting == "uniform"; let mut ranked: Vec<_> = tallies.iter().collect();
        ranked.sort_by(|(a_label, a), (b_label, b)| {
            let comparison = if uniform { b.count.cmp(&a.count) } else { b.weight.partial_cmp(&a.weight).unwrap() };
            comparison.then_with(|| a.distance.partial_cmp(&b.distance).unwrap()).then_with(|| a_label.cmp(b_label))
        });
        let share = |tally: &Tally| if uniform { tally.count as f64 / nearest.len() as f64 } else { tally.weight / weight_total };
        Self {
            label: ranked[0].0.clone(), share: share(ranked[0].1), runner: ranked.get(1).map(|(label, _)| (*label).clone()),
            runner_share: ranked.get(1).map_or(0.0, |(_, tally)| share(tally)),
            estimate: if uniform { target_total / nearest.len() as f64 } else { weighted / weight_total },
            neighbors: if retain { nearest.to_vec() } else { Vec::new() },
        }
    }
}
