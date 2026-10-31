#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Linkage { Single, Complete, Average, Weighted, Centroid, Median, Ward }

impl Linkage {
    pub fn parse(value: &str) -> Self {
        match value {
            "single" => Self::Single, "complete" => Self::Complete, "average" => Self::Average,
            "weighted" => Self::Weighted, "centroid" => Self::Centroid, "median" => Self::Median, _ => Self::Ward,
        }
    }
    pub fn name(self) -> &'static str {
        match self {
            Self::Single => "single", Self::Complete => "complete", Self::Average => "average",
            Self::Weighted => "weighted", Self::Centroid => "centroid", Self::Median => "median", Self::Ward => "ward",
        }
    }
    fn squared(self) -> bool { matches!(self, Self::Centroid | Self::Median | Self::Ward) }
}

pub struct Merge { pub a: usize, pub b: usize, pub height: f64, pub size: usize }
pub struct Edge { pub parent: usize, pub child: usize, pub weight: f64 }

pub fn lance_williams(method: Linkage, a: usize, b: usize, k: usize) -> (f64, f64, f64, f64) {
    let na = a as f64;
    let nb = b as f64;
    let nk = k as f64;
    match method {
        Linkage::Single => (0.5, 0.5, 0.0, -0.5),
        Linkage::Complete => (0.5, 0.5, 0.0, 0.5),
        Linkage::Average => (na / (na + nb), nb / (na + nb), 0.0, 0.0),
        Linkage::Weighted => (0.5, 0.5, 0.0, 0.0),
        Linkage::Centroid => (na / (na + nb), nb / (na + nb), -(na * nb) / ((na + nb) * (na + nb)), 0.0),
        Linkage::Median => (0.5, 0.5, -0.25, 0.0),
        Linkage::Ward => { let total = na + nb + nk; ((na + nk) / total, (nb + nk) / total, -nk / total, 0.0) }
    }
}

pub fn agglomerate(delta: &[Vec<f64>], method: Linkage) -> Vec<Merge> {
    let n = delta.len();
    let capacity = 2 * n - 1;
    let mut values = vec![vec![0.0; capacity]; capacity];
    for u in 0..n {
        for w in 0..n { values[u][w] = if method.squared() { delta[u][w] * delta[u][w] } else { delta[u][w] }; }
    }
    let mut sizes = vec![1; capacity];
    let mut active: Vec<usize> = (0..n).collect();
    let mut merges = Vec::new();
    for step in 0..n - 1 {
        let (mut a, mut b) = (active[0], active[1]);
        for (position, &u) in active.iter().enumerate() {
            for &w in &active[position + 1..] {
                if values[u][w] < values[a][b] { a = u; b = w; }
            }
        }
        let node = n + step;
        sizes[node] = sizes[a] + sizes[b];
        let height = if method.squared() { values[a][b].sqrt() } else { values[a][b] };
        merges.push(Merge { a, b, height, size: sizes[node] });
        for &k in &active {
            if k == a || k == b { continue; }
            let (alpha_a, alpha_b, beta, gamma) = lance_williams(method, sizes[a], sizes[b], sizes[k]);
            let value = alpha_a * values[a][k] + alpha_b * values[b][k] + beta * values[a][b] + gamma * (values[a][k] - values[b][k]).abs();
            values[node][k] = value;
            values[k][node] = value;
        }
        active.retain(|&u| u != a && u != b);
        active.push(node);
    }
    merges
}

pub fn minimum_spanning_tree(delta: &[Vec<f64>]) -> Vec<Edge> {
    let n = delta.len();
    let mut in_tree = vec![false; n];
    in_tree[0] = true;
    let mut keys = delta[0].clone();
    let mut parents = vec![0; n];
    let mut edges = Vec::new();
    for _ in 0..n - 1 {
        let mut chosen = None;
        for u in 0..n {
            if !in_tree[u] && chosen.map_or(true, |v| keys[u] < keys[v]) { chosen = Some(u); }
        }
        let v = chosen.unwrap();
        in_tree[v] = true;
        edges.push(Edge { parent: parents[v], child: v, weight: keys[v] });
        for u in 0..n {
            if !in_tree[u] && delta[v][u] < keys[u] { keys[u] = delta[v][u]; parents[u] = v; }
        }
    }
    edges
}
