use std::collections::{BTreeMap, BTreeSet};
use crate::enrolment::{Course, StudentCourses};

pub struct Edge {
    pub first: usize,
    pub second: usize,
    pub shared: usize,
}

pub struct ConflictGraph {
    pub vertices: Vec<usize>,
    shared: Vec<BTreeMap<usize, usize>>,
}

impl ConflictGraph {
    pub fn new(courses: &[Course], students: &StudentCourses) -> Self {
        let vertices = courses.iter().enumerate()
            .filter_map(|(index, course)| (course.size() > 0).then_some(index)).collect();
        let mut shared = vec![BTreeMap::new(); courses.len()];
        for enrolled in students.values() {
            for (index, &first) in enrolled.iter().enumerate() {
                for &second in &enrolled[index + 1..] {
                    *shared[first].entry(second).or_insert(0) += 1;
                    *shared[second].entry(first).or_insert(0) += 1;
                }
            }
        }
        Self { vertices, shared }
    }

    pub fn neighbours(&self, course: usize) -> &BTreeMap<usize, usize> {
        &self.shared[course]
    }

    pub fn degree(&self, course: usize) -> usize {
        self.shared[course].len()
    }

    pub fn shared_total(&self, course: usize) -> usize {
        self.shared[course].values().sum()
    }

    pub fn edges(&self) -> Vec<Edge> {
        self.vertices.iter().flat_map(|&first| {
            self.shared[first].iter().filter_map(move |(&second, &shared)| {
                (first < second).then_some(Edge { first, second, shared })
            })
        }).collect()
    }

    pub fn components(&self) -> Vec<Vec<usize>> {
        let mut seen = BTreeSet::new();
        let mut components = Vec::new();
        for &vertex in &self.vertices {
            if !seen.insert(vertex) {
                continue;
            }
            let mut component = vec![vertex];
            let mut index = 0;
            while index < component.len() {
                for &neighbour in self.shared[component[index]].keys() {
                    if seen.insert(neighbour) {
                        component.push(neighbour);
                    }
                }
                index += 1;
            }
            component.sort_unstable();
            components.push(component);
        }
        components.sort_by(|a, b| b.len().cmp(&a.len()).then_with(|| a[0].cmp(&b[0])));
        components
    }

    pub fn greedy_clique(&self, courses: &[usize]) -> Vec<usize> {
        let mut candidates = courses.to_vec();
        let mut clique = Vec::new();
        while let Some(&chosen) = candidates.iter().min_by_key(|&&course| {
            (std::cmp::Reverse(self.degree(course)), course)
        }) {
            clique.push(chosen);
            candidates.retain(|course| self.shared[chosen].contains_key(course));
        }
        clique
    }

    pub fn kempe_chain(
        &self,
        assignment: &[Option<usize>],
        start: usize,
        first: usize,
        second: usize,
    ) -> Vec<usize> {
        let mut chain = vec![start];
        let mut seen = BTreeSet::from([start]);
        let mut index = 0;
        while index < chain.len() {
            for &neighbour in self.shared[chain[index]].keys() {
                let slot = assignment[neighbour];
                if (slot == Some(first) || slot == Some(second)) && seen.insert(neighbour) {
                    chain.push(neighbour);
                }
            }
            index += 1;
        }
        chain.sort_unstable();
        chain
    }
}

pub fn reachable(arrows: &[Vec<usize>], source: usize, target: usize) -> bool {
    let mut stack = vec![source];
    let mut seen = BTreeSet::from([source]);
    while let Some(node) = stack.pop() {
        if node == target {
            return true;
        }
        for &successor in &arrows[node] {
            if seen.insert(successor) {
                stack.push(successor);
            }
        }
    }
    false
}
