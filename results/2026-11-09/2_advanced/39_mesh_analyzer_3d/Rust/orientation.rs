use crate::obj_io::Face;
use crate::topology::{edge, Edge, Topology};
use std::collections::VecDeque;

pub fn directed(face: &Face, u: usize, v: usize) -> bool {
    let [a, b, c] = face.vertices;
    [(a, b), (b, c), (c, a)].contains(&(u, v))
}

pub fn flip(face: &mut Face) { face.vertices.swap(1, 2); }

pub fn inconsistent(faces: &[Face], topology: &Topology) -> Vec<Edge> {
    topology.edges.iter().filter(|&(&(a, b), members)| members.len() == 2 && directed(&faces[members[0]], a, b) == directed(&faces[members[1]], a, b)).map(|(&edge, _)| edge).collect()
}

pub fn repair(faces: &mut [Face], topology: &Topology) {
    let mut visited = vec![false; faces.len()];
    for start in 0..faces.len() {
        if visited[start] { continue; }
        visited[start] = true;
        let mut queue = VecDeque::from([start]);
        while let Some(g) = queue.pop_front() {
            let [a, b, c] = faces[g].vertices;
            for (u, v) in [(a, b), (b, c), (c, a)] {
                let members = &topology.edges[&edge(u, v)];
                if members.len() != 2 { continue; }
                let h = if members[0] == g { members[1] } else { members[0] };
                if !visited[h] {
                    if directed(&faces[h], u, v) { flip(&mut faces[h]); }
                    visited[h] = true;
                    queue.push_back(h);
                }
            }
        }
    }
}
