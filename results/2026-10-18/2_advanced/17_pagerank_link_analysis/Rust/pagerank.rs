pub type WeightedEdges = Vec<Vec<(usize, usize)>>;

pub struct PageRankResult {
    pub values: Vec<f64>,
    pub changes: Vec<f64>,
    pub converged_at: Option<usize>,
}

pub fn power_iteration(in_edges: &[Vec<(usize, usize)>], teleport: &[usize], damping: f64,
    iterations: usize, tolerance: f64) -> PageRankResult {
    let count = in_edges.len();
    let mut out_weight = vec![0; count];
    for edges in in_edges { for &(source, weight) in edges { out_weight[source] += weight; } }
    let dangling: Vec<_> = (0..count).filter(|&node| out_weight[node] == 0).collect();
    let mut in_teleport = vec![false; count];
    for &node in teleport { in_teleport[node] = true; }
    let size = teleport.len() as f64;
    let mut values: Vec<_> = in_teleport.iter().map(|&included| if included { 1.0 / size } else { 0.0 }).collect();
    let mut changes = Vec::new();
    let mut converged_at = None;
    for step in 1..=iterations {
        let mut dangling_mass = 0.0;
        for &node in &dangling { dangling_mass += values[node]; }
        let teleport_value = ((1.0 - damping) + damping * dangling_mass) / size;
        let mut updated = Vec::new();
        for node in 0..count {
            let mut inflow = 0.0;
            for &(source, weight) in &in_edges[node] {
                inflow += (values[source] * weight as f64) / out_weight[source] as f64;
            }
            updated.push(damping * inflow + if in_teleport[node] { teleport_value } else { 0.0 });
        }
        let mut change = 0.0;
        for node in 0..count { change += (updated[node] - values[node]).abs(); }
        changes.push(change);
        if converged_at.is_none() && change < tolerance { converged_at = Some(step); }
        values = updated;
    }
    PageRankResult { values, changes, converged_at }
}
