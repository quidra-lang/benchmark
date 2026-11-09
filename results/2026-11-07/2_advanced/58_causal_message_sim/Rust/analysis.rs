use std::collections::VecDeque;
use crate::{clocks, processes::{self, Copy, Event, Message, Program, State}};

pub fn graph(states: &[State], events: &[Event], messages: &[Message], copies: &[Copy]) -> Vec<Vec<usize>> {
    let mut edges = vec![Vec::new(); events.len()];
    for state in states {
        for pair in state.events.windows(2) { edges[pair[0]].push(pair[1]); }
    }
    for copy in copies {
        if let Some(e) = copy.received { edges[messages[copy.message].event].push(e); }
    }
    edges
}

pub fn path(edges: &[Vec<usize>], start: usize, target: usize) -> Option<Vec<usize>> {
    let mut parent = vec![None; edges.len()];
    parent[start] = Some(start);
    let mut queue = VecDeque::from([start]);
    while let Some(e) = queue.pop_front() {
        for &next in &edges[e] {
            if parent[next].is_some() { continue; }
            parent[next] = Some(e);
            if next == target {
                let mut result = vec![target];
                while *result.last().unwrap() != start {
                    result.push(parent[*result.last().unwrap()].unwrap());
                }
                result.reverse();
                return Some(result);
            }
            queue.push_back(next);
        }
    }
    None
}

pub struct Concurrency {
    pub ordered: usize,
    pub concurrent: usize,
    pub equal: usize,
    pub inversions: usize,
    pub pairs: Vec<Vec<usize>>,
}

pub fn concurrency(events: &[Event], n: usize) -> Concurrency {
    let mut result = Concurrency { ordered: 0, concurrent: 0, equal: 0,
        inversions: 0, pairs: vec![vec![0; n]; n] };
    for (i, a) in events.iter().enumerate() {
        for b in &events[i + 1..] {
            if clocks::relation(&a.vector, &b.vector) == "||" {
                result.concurrent += 1;
                result.equal += usize::from(a.lamport == b.lamport);
                result.pairs[a.process.min(b.process)][a.process.max(b.process)] += 1;
            } else { result.ordered += 1; }
            if (a.time < b.time && a.lamport > b.lamport)
                || (b.time < a.time && b.lamport > a.lamport) { result.inversions += 1; }
        }
    }
    result
}

pub struct Ordering {
    pub races: Vec<(usize, usize, usize)>,
    pub violations: Vec<(usize, usize, usize)>,
    pub fifo: usize,
}

pub fn ordering(states: &[State], events: &[Event], messages: &[Message], copies: &[Copy]) -> Ordering {
    let mut result = Ordering { races: Vec::new(), violations: Vec::new(), fifo: 0 };
    let vector = |c: usize| &events[messages[copies[c].message].event].vector;
    for (p, state) in states.iter().enumerate() {
        for pair in state.delivered.windows(2) {
            if clocks::relation(vector(pair[0]), vector(pair[1])) == "||" {
                result.races.push((p, pair[0], pair[1]));
            }
        }
        for (i, &a) in state.delivered.iter().enumerate() {
            for &b in &state.delivered[i + 1..] {
                if clocks::relation(vector(b), vector(a)) == "->" {
                    result.violations.push((p, a, b));
                    result.fifo += usize::from(copies[a].source == copies[b].source);
                }
            }
        }
    }
    result
}

pub struct Enumeration {
    pub limits: Vec<usize>,
    pub product: usize,
    pub consistent: usize,
    pub levels: Vec<usize>,
    pub predicates: Vec<(usize, bool)>,
}

pub fn enumerate(time: i64, thresholds: &[i64], programs: &[Program], states: &[State], events: &[Event]) -> Enumeration {
    let limits: Vec<_> = states.iter().map(|s| s.events.iter().filter(|&&e| events[e].time <= time).count()).collect();
    let mut strides = Vec::new();
    let mut product = 1;
    for &limit in &limits { strides.push(product); product *= limit + 1; }
    let mut valid = vec![false; product];
    let mut transit = vec![0; product];
    let mut levels = vec![0; limits.iter().sum::<usize>() + 1];
    let initial: i64 = programs.iter().map(|p| p.initial).sum();
    let mut consistent = 0;
    for index in 0..product {
        let cut: Vec<_> = limits.iter().enumerate().map(|(p, &n)| index / strides[p] % (n + 1)).collect();
        valid[index] = cut.iter().enumerate().all(|(p, &c)| c == 0 || clocks::le(&events[states[p].events[c - 1]].vector, &cut));
        if valid[index] {
            consistent += 1;
            levels[cut.iter().sum::<usize>()] += 1;
            transit[index] = initial - programs.iter().enumerate().map(|(p, program)|
                processes::balance_at(program.initial, &states[p], events, cut[p])).sum::<i64>();
        }
    }
    let predicates = thresholds.iter().map(|&threshold| {
        let count = (0..product).filter(|&i| valid[i] && transit[i] >= threshold).count();
        let mut avoiding = vec![false; product];
        for i in 0..product {
            if !valid[i] || transit[i] >= threshold { continue; }
            avoiding[i] = i == 0 || limits.iter().enumerate().any(|(p, &n)|
                i / strides[p] % (n + 1) > 0 && avoiding[i - strides[p]]);
        }
        (count, !avoiding[product - 1])
    }).collect();
    Enumeration { limits, product, consistent, levels, predicates }
}
