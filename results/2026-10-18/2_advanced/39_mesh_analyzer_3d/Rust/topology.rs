use crate::obj_io::Face;
use std::collections::{BTreeMap, BTreeSet, VecDeque};

pub type Edge = (usize, usize);
pub fn edge(a: usize, b: usize) -> Edge { (a.min(b), a.max(b)) }
pub fn face_edges(face: &Face) -> [Edge; 3] {
    let [a, b, c] = face.vertices;
    [edge(a, b), edge(b, c), edge(c, a)]
}

pub struct Component {
    pub faces: Vec<usize>,
    pub vertices: BTreeSet<usize>,
    pub edges: Vec<Edge>,
}

pub struct Topology {
    pub edges: BTreeMap<Edge, Vec<usize>>,
    pub components: Vec<Component>,
    pub face_component: Vec<usize>,
    pub fans: Vec<Vec<Vec<usize>>>,
}

impl Topology {
    pub fn build(faces: &[Face], vertex_count: usize) -> Self {
        let mut edges: BTreeMap<Edge, Vec<usize>> = BTreeMap::new();
        for (i, face) in faces.iter().enumerate() { for edge in face_edges(face) { edges.entry(edge).or_default().push(i); } }
        let mut face_component = vec![usize::MAX; faces.len()];
        let mut components = Vec::new();
        for first in 0..faces.len() {
            if face_component[first] != usize::MAX { continue; }
            let index = components.len();
            face_component[first] = index;
            let mut queue = VecDeque::from([first]);
            let mut members = Vec::new();
            while let Some(face) = queue.pop_front() {
                members.push(face);
                for edge in face_edges(&faces[face]) {
                    for &neighbor in &edges[&edge] {
                        if face_component[neighbor] == usize::MAX { face_component[neighbor] = index; queue.push_back(neighbor); }
                    }
                }
            }
            members.sort_unstable();
            let vertices = members.iter().flat_map(|&i| faces[i].vertices).collect();
            let component_edges: BTreeSet<_> = members.iter().flat_map(|&i| face_edges(&faces[i])).collect();
            components.push(Component { faces: members, vertices, edges: component_edges.into_iter().collect() });
        }
        let mut fans = vec![Vec::new(); vertex_count + 1];
        for vertex in 1..=vertex_count {
            let mut remaining: BTreeSet<_> = faces.iter().enumerate().filter(|(_, face)| face.vertices.contains(&vertex)).map(|(i, _)| i).collect();
            while let Some(&first) = remaining.first() {
                remaining.remove(&first);
                let mut fan = Vec::new();
                let mut queue = VecDeque::from([first]);
                while let Some(face) = queue.pop_front() {
                    fan.push(face);
                    for (a, b) in face_edges(&faces[face]) {
                        if a != vertex && b != vertex { continue; }
                        for &neighbor in &edges[&(a, b)] {
                            if remaining.remove(&neighbor) { queue.push_back(neighbor); }
                        }
                    }
                }
                fan.sort_unstable();
                fans[vertex].push(fan);
            }
        }
        Self { edges, components, face_component, fans }
    }

    pub fn degree(&self, vertex: usize) -> usize { self.edges.keys().filter(|&&(a, b)| a == vertex || b == vertex).count() }

    pub fn component_nonmanifold_vertices(&self, component: usize) -> usize {
        self.components[component].vertices.iter().filter(|&&v| self.fans[v].iter().filter(|fan| self.face_component[fan[0]] == component).count() >= 2).count()
    }
}

pub struct BoundaryLoop {
    pub component: usize,
    pub vertices: Vec<usize>,
    pub length: usize,
    pub kind: &'static str,
    pub filled: bool,
}

pub fn loops(topology: &Topology) -> Vec<BoundaryLoop> {
    let mut loops = Vec::new();
    for (component, data) in topology.components.iter().enumerate() {
        let mut unused: BTreeSet<_> = data.edges.iter().copied().filter(|edge| topology.edges[edge].len() == 1).collect();
        while let Some(&(a, b)) = unused.first() {
            unused.remove(&(a, b));
            let mut vertices = vec![a, b];
            while *vertices.last().unwrap() != a {
                let x = *vertices.last().unwrap();
                let next = unused.iter().filter_map(|&(u, v)| if u == x { Some((v, (u, v))) } else if v == x { Some((u, (u, v))) } else { None }).min_by_key(|&(y, _)| y);
                let Some((y, edge)) = next else { break; };
                unused.remove(&edge);
                vertices.push(y);
            }
            let closed = *vertices.last().unwrap() == a;
            let length = vertices.len() - 1;
            if closed { vertices.pop(); }
            loops.push(BoundaryLoop { component, vertices, length, kind: if closed { "mixed" } else { "open" }, filled: false });
        }
    }
    loops
}
