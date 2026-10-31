use std::collections::BTreeMap;
use crate::raft_node::{Entry,Node};
pub struct Checker {
    pub leaders: BTreeMap<usize,usize>,
    pub committed: BTreeMap<usize,(usize,usize)>,
    pub applied: BTreeMap<usize,(Entry,String)>,
    pub violations: [usize;5],
    pub elected: usize,
    pub applies: usize,
    pub truncations: usize,
    pub removed: usize
}
impl Checker {
    pub fn new() -> Self {
        Self {
            leaders: BTreeMap::new(),
            committed: BTreeMap::new(),
            applied: BTreeMap::new(),
            violations: [0;5],
            elected: 0,
            applies: 0,
            truncations: 0,
            removed: 0
        }
    }
    pub fn leader(&mut self, node: usize, term: usize, log: &[Entry]) {
        self.elected += 1;
        if let Some(&old) = self.leaders.get(&term) {
            if old != node {
                self.violations[0] += 1;
            }
        } else {
            self.leaders.insert(term,node);
        }
        if self.committed.iter().any(|(&i,&(term,_))| i > log.len() || log[i-1].term != term) {
            self.violations[1] += 1;
        }
    }
    pub fn commit(&mut self, index: usize, term: usize, time: usize) {
        self.committed.entry(index).or_insert((term,time));
    }
    pub fn apply(&mut self, index: usize, entry: &Entry, result: String) {
        self.applies += 1;
        if let Some((old,_)) = self.applied.get(&index) {
            if old != entry {
                self.violations[3] += 1;
            }
        } else {
            self.applied.insert(index,(entry.clone(),result));
        }
    }
    pub fn truncate(&mut self, first: usize, entries: &[Entry]) {
        self.truncations += 1;
        self.removed += entries.len();
        for (i,entry) in entries.iter().enumerate() {
            if self.committed.get(&(first+i)).map_or(false,|&(term,_)| term == entry.term) {
                self.violations[4] += 1;
            }
        }
    }
    pub fn matching(&mut self, nodes: &[Node]) {
        for a in 0..nodes.len() {
            for b in a+1..nodes.len() {
                let limit = nodes[a].length().min(nodes[b].length());
                let g = (1..=limit).rev().find(|&i| nodes[a].term_at(i) == nodes[b].term_at(i)).unwrap_or(0);
                if (0..g).any(|i| nodes[a].log[i] != nodes[b].log[i]) {
                    self.violations[2] += 1;
                }
            }
        }
    }
    pub fn lines(&self, terms: usize, ticks: usize, nodes: usize) -> Vec<String> {
        let names = ["ELECTION_SAFETY","LEADER_COMPLETENESS","LOG_MATCHING","STATE_MACHINE_SAFETY","COMMITTED_KEPT"];
        let details = [format!("terms {} leaders {} elected {}",terms,self.leaders.len(),self.elected),format!("checks {} committed {}",self.elected,self.committed.len()),format!("checks {} pairs {}",ticks,ticks*nodes*(nodes-1)/2),format!("applies {} indices {}",self.applies,self.applied.len()),format!("truncations {} removed {}",self.truncations,self.removed)];
        (0..5).map(|i| format!("{} {} violations {} {}",names[i],if self.violations[i] == 0 {
            "OK"
        } else {
            "FAIL"
        },self.violations[i],details[i])).collect()
    }
}
