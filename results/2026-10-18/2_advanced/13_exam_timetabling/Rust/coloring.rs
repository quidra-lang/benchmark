use std::cmp::Reverse;
use std::collections::BTreeSet;
use crate::conflict_graph::ConflictGraph;

pub struct Attempt<'a, F> {
    courses: Vec<usize>,
    graph: &'a ConflictGraph,
    limit: usize,
    candidate_slots: F,
    pub dead_ends: usize,
    pub dead_end_course: Option<usize>,
    pub aborted: bool,
    pub chosen: Vec<(usize, usize)>,
}

impl<'a, F> Attempt<'a, F>
where F: Fn(usize, &[Option<usize>]) -> Vec<usize> {
    pub fn new(courses: Vec<usize>, graph: &'a ConflictGraph, limit: usize, candidate_slots: F) -> Self {
        Self {
            courses, graph, limit, candidate_slots,
            dead_ends: 0, dead_end_course: None, aborted: false, chosen: Vec::new(),
        }
    }

    fn saturation(&self, course: usize, assignment: &[Option<usize>]) -> usize {
        self.graph.neighbours(course).keys().filter_map(|&other| assignment[other])
            .collect::<BTreeSet<_>>().len()
    }

    pub fn search(&mut self, assignment: &mut [Option<usize>]) -> bool {
        let chosen = self.courses.iter().copied().filter(|&course| assignment[course].is_none())
            .min_by_key(|&course| (Reverse(self.saturation(course, assignment)), Reverse(self.graph.degree(course)), course));
        let Some(course) = chosen else { return true; };
        self.chosen.push((course, self.saturation(course, assignment)));
        for slot in (self.candidate_slots)(course, assignment) {
            assignment[course] = Some(slot);
            if self.search(assignment) {
                return true;
            }
            assignment[course] = None;
            if self.aborted {
                return false;
            }
        }
        self.chosen.pop();
        self.dead_ends += 1;
        self.dead_end_course = Some(course);
        self.aborted = self.dead_ends > self.limit;
        false
    }
}

pub fn greedy_numbering(order: &[usize], graph: &ConflictGraph, course_count: usize) -> usize {
    let mut numbers = vec![None; course_count];
    let mut maximum = 0;
    for &course in order {
        let taken: BTreeSet<_> = graph.neighbours(course).keys()
            .filter_map(|&other| numbers[other]).collect();
        let mut number = 1;
        while taken.contains(&number) {
            number += 1;
        }
        numbers[course] = Some(number);
        maximum = maximum.max(number);
    }
    maximum
}
