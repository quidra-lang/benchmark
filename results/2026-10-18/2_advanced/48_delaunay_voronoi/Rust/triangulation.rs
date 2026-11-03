use crate::predicates::{Point, orient, incircle};
use std::collections::{BTreeMap, BTreeSet};

pub type Triangle = [usize; 3];

pub fn canonical(t: Triangle) -> Triangle {
    let j = if t[0] < t[1] && t[0] < t[2] { 0 } else if t[1] < t[2] { 1 } else { 2 };
    [t[j], t[(j + 1) % 3], t[(j + 2) % 3]]
}

pub struct Triangulation {
    pub directed: BTreeMap<(usize, usize), usize>,
}

pub struct Insertion {
    pub containing: Option<Triangle>,
    pub visible: usize,
    pub flips: usize,
    pub triangles: usize,
    pub hull: usize,
}

impl Triangulation {
    pub fn new(points: &[Point]) -> (Self, Triangle) {
        let first = if orient(points[0], points[1], points[2]) > 0 { [0, 1, 2] } else { [0, 2, 1] };
        let mut result = Self { directed: BTreeMap::new() };
        result.add(first);
        (result, first)
    }

    fn add(&mut self, [a, b, c]: Triangle) {
        self.directed.insert((a, b), c);
        self.directed.insert((b, c), a);
        self.directed.insert((c, a), b);
    }

    fn remove(&mut self, [a, b, c]: Triangle) {
        self.directed.remove(&(a, b));
        self.directed.remove(&(b, c));
        self.directed.remove(&(c, a));
    }

    pub fn triangles(&self) -> Vec<Triangle> {
        self.directed.iter().map(|(&(a, b), &c)| canonical([a, b, c])).collect::<BTreeSet<_>>().into_iter().collect()
    }

    pub fn hull_edges(&self) -> Vec<(usize, usize)> {
        self.directed.keys().copied().filter(|&(a, b)| !self.directed.contains_key(&(b, a))).collect()
    }

    pub fn hull(&self) -> Vec<usize> {
        let edges: BTreeMap<usize, usize> = self.hull_edges().into_iter().collect();
        let first = *edges.keys().next().unwrap();
        let mut result = vec![first];
        let mut current = edges[&first];
        while current != first {
            result.push(current);
            current = edges[&current];
        }
        result
    }

    pub fn insert(&mut self, s: usize, points: &[Point]) -> Insertion {
        let containing = self.triangles().into_iter().find(|&[a, b, c]|
            orient(points[a], points[b], points[s]) > 0 && orient(points[b], points[c], points[s]) > 0
                && orient(points[c], points[a], points[s]) > 0);
        let mut checking = BTreeSet::new();
        let mut visible = 0;
        if let Some([a, b, c]) = containing {
            self.remove([a, b, c]);
            for (u, v) in [(a, b), (b, c), (c, a)] {
                self.add([u, v, s]);
                checking.insert((u, v));
            }
        } else {
            for (u, v) in self.hull_edges() {
                if orient(points[u], points[v], points[s]) < 0 {
                    self.add([v, u, s]);
                    checking.insert((v, u));
                    visible += 1;
                }
            }
        }
        let mut flips = 0;
        while let Some(&(a, b)) = checking.iter().next() {
            checking.remove(&(a, b));
            if self.directed.get(&(a, b)).copied() != Some(s) { continue; }
            if let Some(&q) = self.directed.get(&(b, a)) {
                if incircle(points[a], points[b], points[s], points[q]) > 0 {
                    self.remove([a, b, s]);
                    self.remove([b, a, q]);
                    self.add([a, q, s]);
                    self.add([q, b, s]);
                    checking.insert((a, q));
                    checking.insert((q, b));
                    flips += 1;
                }
            }
        }
        Insertion { containing, visible, flips, triangles: self.directed.len() / 3, hull: self.hull_edges().len() }
    }
}

pub fn walk(point: Point, points: &[Point], triangles: &[Triangle], numbers: &BTreeMap<(usize, usize), usize>)
    -> (Vec<usize>, Option<(usize, usize)>) {
    let mut path = vec![0];
    loop {
        let current = *path.last().unwrap();
        let [a, b, c] = triangles[current];
        let crossing = [(a, b), (b, c), (c, a)].iter().copied().find(|&(u, v)| orient(points[u], points[v], point) < 0);
        if let Some((u, v)) = crossing {
            if let Some(&next) = numbers.get(&(v, u)) { path.push(next); }
            else { return (path, Some((u.min(v), u.max(v)))); }
        } else { return (path, None); }
    }
}
