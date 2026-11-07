use std::collections::BTreeSet;
use crate::slots::{Layout, Slot};
use crate::word_index::WordIndex;

#[derive(Clone)]
pub struct GridState {
    pub letters: Vec<u8>,
    pub words: Vec<Option<usize>>,
    pub used: BTreeSet<usize>,
}
impl GridState {
    pub fn new(letters: Vec<u8>, count: usize) -> Self { Self { letters, words: vec![None; count], used: BTreeSet::new() } }
    pub fn pattern(&self, slot: &Slot) -> Vec<u8> { slot.cells.iter().map(|&cell| self.letters[cell]).collect() }
    pub fn assign(&mut self, slot: &Slot, id: usize, index: &WordIndex) -> Vec<usize> {
        let mut filled = Vec::new();
        for (&cell, &letter) in slot.cells.iter().zip(&index.words[id].letters) {
            if self.letters[cell] == b'.' { self.letters[cell] = letter; filled.push(cell); }
        }
        self.words[slot.index] = Some(id);
        self.used.insert(id);
        filled
    }
    fn unassign(&mut self, slot: &Slot, filled: &[usize]) {
        for &cell in filled { self.letters[cell] = b'.'; }
        self.used.remove(&self.words[slot.index].take().unwrap());
    }
}
#[derive(PartialEq)]
enum SearchResult { Complete, Fail, Abort }
pub struct Attempt {
    pub state: GridState,
    pub minimum: i64,
    pub budget: usize,
    pub nodes: usize,
    pub backtracks: usize,
    pub prunes: usize,
    pub dead_ends: usize,
    pub sequence: Vec<usize>,
    pub max_depth: usize,
    pub best: GridState,
    pub failures: Vec<usize>,
    pub trace: Vec<String>,
    pub outcome: &'static str,
}
impl Attempt {
    pub fn new(initial: &GridState, minimum: i64, budget: usize) -> Self {
        Self { state: initial.clone(), minimum, budget, nodes: 0, backtracks: 0, prunes: 0, dead_ends: 0,
            sequence: Vec::new(), max_depth: 0, best: initial.clone(), failures: vec![0; initial.words.len()], trace: Vec::new(), outcome: "" }
    }
    pub fn run(&mut self, layout: &Layout, index: &WordIndex) {
        self.outcome = match self.search(layout, index) { SearchResult::Complete => "filled", SearchResult::Fail => "unfillable", SearchResult::Abort => "budget" };
    }
    pub fn final_state(&self) -> &GridState { if self.outcome == "filled" { &self.state } else { &self.best } }
    fn candidates(&self, slot: &Slot, index: &WordIndex) -> Vec<usize> { index.candidates(&self.state.pattern(slot), self.minimum, &self.state.used) }
    fn search(&mut self, layout: &Layout, index: &WordIndex) -> SearchResult {
        let mut chosen: Option<(usize, Vec<usize>)> = None;
        for slot in &layout.slots {
            if self.state.words[slot.index].is_some() { continue; }
            let words = self.candidates(slot, index);
            if chosen.as_ref().is_none_or(|(_, previous)| words.len() < previous.len()) { chosen = Some((slot.index, words)); }
        }
        let Some((number, words)) = chosen else { return SearchResult::Complete; };
        if words.is_empty() { self.dead_ends += 1; self.failures[number] += 1; return SearchResult::Fail; }
        let slot = &layout.slots[number];
        for word in words {
            if self.nodes == self.budget { return SearchResult::Abort; }
            self.nodes += 1;
            let filled = self.state.assign(slot, word, index);
            self.sequence.push(number);
            let wiped = slot.crossings.iter().copied().find(|&other| self.state.words[other].is_none() && self.candidates(&layout.slots[other], index).is_empty());
            if self.nodes <= 10 { self.trace.push(format!("{}={}{}", slot.label, index.words[word].text, if wiped.is_some() { "!" } else { "" })); }
            let result = if let Some(other) = wiped {
                self.prunes += 1; self.failures[other] += 1; SearchResult::Fail
            } else {
                if self.sequence.len() > self.max_depth { self.max_depth = self.sequence.len(); self.best = self.state.clone(); }
                self.search(layout, index)
            };
            if result != SearchResult::Fail { return result; }
            self.state.unassign(slot, &filled);
            self.sequence.pop();
            self.backtracks += 1;
        }
        SearchResult::Fail
    }
}
