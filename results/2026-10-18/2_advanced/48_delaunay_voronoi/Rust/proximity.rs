use crate::{predicates::{self, Point}, triangulation::Triangulation};

pub struct DisjointSet {
    parent: Vec<usize>,
}

impl DisjointSet {
    pub fn new(n: usize) -> Self { Self { parent: (0..n).collect() } }

    pub fn find(&mut self, x: usize) -> usize {
        if self.parent[x] != x {
            let parent = self.parent[x];
            self.parent[x] = self.find(parent);
        }
        self.parent[x]
    }

    pub fn join(&mut self, a: usize, b: usize) -> bool {
        let x = self.find(a);
        let y = self.find(b);
        if x == y { false } else { self.parent[y] = x; true }
    }
}

pub fn nearest(points: &[Point]) -> Vec<usize> {
    (0..points.len()).map(|s| (0..points.len()).filter(|&t| t != s)
        .min_by_key(|&t| (predicates::d2(points[s], points[t]), t)).unwrap()).collect()
}

pub fn components(n: usize, edges: &[(usize, usize)]) -> Vec<Vec<usize>> {
    let mut sets = DisjointSet::new(n);
    for &(i, j) in edges { sets.join(i, j); }
    let mut result: Vec<Vec<usize>> = Vec::new();
    let mut roots = Vec::new();
    for s in 0..n {
        let root = sets.find(s);
        if let Some(j) = roots.iter().position(|&r| r == root) { result[j].push(s); }
        else { roots.push(root); result.push(vec![s]); }
    }
    result
}

pub fn kruskal(points: &[Point], edges: &[(usize, usize)]) -> Vec<(usize, usize)> {
    let mut order = edges.to_vec();
    order.sort_by_key(|&(i, j)| (predicates::d2(points[i], points[j]), i, j));
    let mut sets = DisjointSet::new(points.len());
    order.into_iter().filter(|&(i, j)| sets.join(i, j)).collect()
}

pub fn gabriel(i: usize, j: usize, points: &[Point], mesh: &Triangulation) -> bool {
    [(i, j), (j, i)].iter().all(|edge| mesh.directed.get(edge).map_or(true, |&q| predicates::dot(points[q], points[i], points[j]) > 0))
}

pub fn relative(i: usize, j: usize, points: &[Point]) -> bool {
    let length = predicates::d2(points[i], points[j]);
    !(0..points.len()).any(|k| predicates::d2(points[i], points[k]) < length && predicates::d2(points[j], points[k]) < length)
}

pub fn route(i: usize, j: usize, points: &[Point], neighbors: &[Vec<usize>]) -> (Vec<usize>, f64) {
    let mut current = i;
    let mut path = vec![i];
    let mut length = 0.0;
    while current != j {
        let next = *neighbors[current].iter().min_by_key(|&&t| (predicates::d2(points[t], points[j]), t)).unwrap();
        length += (predicates::d2(points[current], points[next]) as f64).sqrt();
        path.push(next);
        current = next;
    }
    (path, length)
}

pub fn dijkstra(start: usize, points: &[Point], neighbors: &[Vec<usize>]) -> (Vec<f64>, Vec<Option<usize>>) {
    let n = points.len();
    let mut distances = vec![f64::INFINITY; n];
    let mut previous = vec![None; n];
    let mut visited = vec![false; n];
    distances[start] = 0.0;
    for _ in 0..n {
        let current = (0..n).filter(|&s| !visited[s]).min_by(|&a, &b| distances[a].partial_cmp(&distances[b]).unwrap().then(a.cmp(&b))).unwrap();
        visited[current] = true;
        for &next in &neighbors[current] {
            let alternative = distances[current] + (predicates::d2(points[current], points[next]) as f64).sqrt();
            if alternative < distances[next] {
                distances[next] = alternative;
                previous[next] = Some(current);
            }
        }
    }
    (distances, previous)
}
