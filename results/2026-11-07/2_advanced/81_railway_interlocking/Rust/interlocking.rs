use std::collections::BTreeSet;
use std::fs;
use crate::layout::Layout;
pub const STATES: [&str;4] = ["none","LOCKED","USED","APPROACH"];
#[derive(Clone,Copy)] pub enum Finish {
    Signal(usize),
    Buffer(usize),
    Boundary(usize)
}
pub struct Route {
    pub name: String,
    pub start: usize,
    pub finish: Finish,
    pub finish_name: String,
    pub up: bool,
    pub points: Vec<(usize,bool)>,
    pub sections: Vec<usize>,
    pub overlap: Vec<usize>,
    pub flank: Vec<(usize,bool)>,
    pub conflicts: Vec<usize>,
    pub approach: usize,
    pub state: usize,
    pub passed: BTreeSet<usize>,
    pub overlap_locked: bool,
    pub counter: usize,
    pub release: Option<usize>,
    pub statistics: [usize;7]
}
pub struct Interlocking {
    pub routes: Vec<Route>,
    pub section_route: Vec<Option<usize>>,
    pub section_overlap: Vec<BTreeSet<usize>>,
    pub point_locks: Vec<Vec<(usize,bool)>>
}
impl Interlocking {
    pub fn route(&self, name: &str) -> usize {
        self.routes.iter().position(|r| r.name == name).unwrap()
    }
    pub fn read(layout: &Layout) -> Self {
        let source = fs::read_to_string("input/routes.txt").unwrap();
        let lines: Vec<Vec<_>> = source.lines().map(|l| l.split_whitespace().collect()).collect();
        let names: Vec<_> = lines.iter().map(|w| w[1]).collect();
        let mut routes = Vec::new();
        for w in &lines {
            let point_list = |source: &str| if source == "-" {
                Vec::new()
            } else {
                source.split(',').map(|p| {
                    let (name,position) = p.split_once(':').unwrap();
                    (layout.point(name),position == "R")
                }).collect()
            };
            let section_list = |source: &str| if source == "-" {
                Vec::new()
            } else {
                source.split(',').map(|s| layout.section(s)).collect()
            };
            let start = layout.signals.iter().position(|s| s.name == w[2]).unwrap();
            let finish = if let Some(s) = layout.signals.iter().position(|s| s.name == w[3]) {
                Finish::Signal(s)
            } else if let Some(b) = layout.buffers.iter().position(|s| s.name == w[3]) {
                Finish::Buffer(b)
            } else {
                Finish::Boundary(layout.boundary(w[3]))
            };
            routes.push(Route {
                name: w[1].to_owned(),
                start,
                finish,
                finish_name: w[3].to_owned(),
                up: layout.signals[start].up,
                points: point_list(w[4]),
                sections: section_list(w[5]),
                overlap: section_list(w[6]),
                flank: point_list(w[7]),
                conflicts: if w[8] == "-" {
                    Vec::new()
                } else {
                    w[8].split(',').map(|r| names.iter().position(|&n| n == r).unwrap()).collect()
                },
                approach: w[9].parse().unwrap(),
                state: 0,
                passed: BTreeSet::new(),
                overlap_locked: false,
                counter: 0,
                release: None,
                statistics: [0;7]
            });
        }
        Self {
            routes,
            section_route: vec![None;layout.sections.len()],
            section_overlap: vec![BTreeSet::new();layout.sections.len()],
            point_locks: vec![Vec::new();layout.points.len()]
        }
    }
    pub fn lock(&mut self, route: usize) {
        let r = &mut self.routes[route];
        r.state = 1;
        r.passed.clear();
        r.overlap_locked = true;
        r.counter = 0;
        r.release = None;
        for &section in &r.sections {
            self.section_route[section] = Some(route);
        }
        for &section in &r.overlap {
            self.section_overlap[section].insert(route);
        }
        for &(point,position) in r.points.iter().chain(&r.flank) {
            self.point_locks[point].push((route,position));
        }
    }
    pub fn unlock_section(&mut self, route: usize, section: usize, layout: &Layout) {
        if self.section_route[section] == Some(route) {
            self.section_route[section] = None;
        }
        for (p,point) in layout.points.iter().enumerate() {
            if point.common == section {
                self.point_locks[p].retain(|&(r,_)| r != route);
            }
        }
    }
    pub fn unlock_overlap(&mut self, route: usize, layout: &Layout) {
        for &section in &self.routes[route].overlap {
            self.section_overlap[section].remove(&route);
            for (p,point) in layout.points.iter().enumerate() {
                if point.common == section {
                    self.point_locks[p].retain(|&(r,_)| r != route);
                }
            }
        }
        self.routes[route].overlap_locked = false;
    }
    pub fn release(&mut self, route: usize, layout: &Layout) {
        for section in self.routes[route].sections.clone() {
            if self.section_route[section] == Some(route) {
                self.section_route[section] = None;
            }
        }
        if self.routes[route].overlap_locked {
            self.unlock_overlap(route,layout);
        }
        for locks in &mut self.point_locks {
            locks.retain(|&(r,_)| r != route);
        }
        self.routes[route].state = 0;
        self.routes[route].release = None;
    }
}
