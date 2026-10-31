use std::fs;
use crate::report::Fraction;

pub struct Net {
    pub places: Vec<String>, pub transitions: Vec<String>, pub inputs: Vec<Vec<usize>>, pub outputs: Vec<Vec<usize>>,
    pub initial: usize, pub final_place: usize,
}
impl Net {
    pub fn read() -> Self {
        let input = fs::read_to_string("input/model.txt").unwrap();
        let mut places = Vec::new(); let mut transitions = Vec::new(); let mut arcs = Vec::new();
        let (mut initial, mut final_place) = (String::new(), String::new());
        for line in input.lines() {
            let w: Vec<_> = line.split_whitespace().collect();
            match w[0] {
                "PLACE" => places.push(w[1].to_owned()), "TRANSITION" => transitions.push(w[1].to_owned()),
                "ARC" => arcs.push((w[1].to_owned(), w[2].to_owned())),
                "INITIAL" => initial = w[1].to_owned(), _ => final_place = w[1].to_owned(),
            }
        }
        transitions.sort();
        let mut inputs = vec![Vec::new(); transitions.len()]; let mut outputs = vec![Vec::new(); transitions.len()];
        for (a, b) in arcs {
            if let Some(p) = places.iter().position(|n| n == &a) {
                inputs[transitions.iter().position(|n| n == &b).unwrap()].push(p);
            } else { outputs[transitions.iter().position(|n| n == &a).unwrap()].push(places.iter().position(|n| n == &b).unwrap()); }
        }
        for list in inputs.iter_mut().chain(outputs.iter_mut()) { list.sort_unstable(); }
        let initial = places.iter().position(|n| n == &initial).unwrap();
        let final_place = places.iter().position(|n| n == &final_place).unwrap();
        Self { places, transitions, inputs, outputs, initial, final_place }
    }
    pub fn marking(&self, final_marking: bool) -> Vec<i64> {
        let mut marking = vec![0; self.places.len()]; marking[if final_marking { self.final_place } else { self.initial }] = 1; marking
    }
    pub fn enabled(&self, marking: &[i64], transition: usize) -> bool { self.inputs[transition].iter().all(|&p| marking[p] > 0) }
    pub fn fire(&self, marking: &[i64], transition: usize) -> Vec<i64> {
        let mut result = marking.to_vec();
        for &p in &self.inputs[transition] { result[p] -= 1; } for &p in &self.outputs[transition] { result[p] += 1; } result
    }
    pub fn arcs(&self) -> usize { self.inputs.iter().chain(&self.outputs).map(Vec::len).sum() }
}

#[derive(Clone, Default)]
pub struct Totals { pub missing: i64, pub remaining: i64, pub consumed: i64, pub produced: i64, pub skipped: i64 }
impl Totals {
    pub fn fitness(&self) -> Fraction {
        Fraction::new(2*self.consumed*self.produced-self.missing*self.produced-self.remaining*self.consumed, 2*self.consumed*self.produced)
    }
    pub fn add(&mut self, other: &Self) {
        self.missing += other.missing; self.remaining += other.remaining; self.consumed += other.consumed; self.produced += other.produced; self.skipped += other.skipped;
    }
}
#[derive(Default)]
pub struct PlaceTotals { pub missing: i64, pub remaining: i64, pub deviating: usize, pub waits: Vec<i64>, pub routes: Vec<i64> }
