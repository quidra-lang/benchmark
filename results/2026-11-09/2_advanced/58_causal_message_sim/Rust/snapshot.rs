use crate::processes::{self, Copy, Event, Message, Program, State};

#[derive(Clone)]
pub struct Record {
    pub time: i64,
    pub reason: String,
    pub balance: i64,
    pub lamport: usize,
    pub vector: Vec<usize>,
    pub pending: Vec<usize>,
}

#[derive(Clone, Default)]
pub struct Channel {
    pub dispatched: Option<i64>,
    pub accepted: Option<i64>,
    pub copies: Vec<usize>,
}

pub struct Snapshot {
    pub name: String,
    pub started: i64,
    pub completed: Option<i64>,
    pub records: Vec<Option<Record>>,
    pub channels: Vec<Channel>,
    pub ignored: Vec<(usize, i64)>,
}

impl Snapshot {
    pub fn new(name: String, time: i64, n: usize) -> Self {
        Self { name, started: time, completed: None, records: vec![None; n],
            channels: vec![Channel::default(); n * n], ignored: Vec::new() }
    }

    pub fn cut(&self) -> Vec<usize> {
        self.records.iter().enumerate().map(|(p, r)| r.as_ref().unwrap().vector[p]).collect()
    }
}

pub struct Cut {
    pub orphans: Vec<usize>,
    pub transit: Vec<usize>,
    pub money: i64,
}

pub fn evaluate(cut: &[usize], programs: &[Program], states: &[State],
                events: &[Event], messages: &[Message], copies: &[Copy]) -> Cut {
    let mut result = Cut { orphans: Vec::new(), transit: Vec::new(), money: 0 };
    for (p, program) in programs.iter().enumerate() {
        result.money += processes::balance_at(program.initial, &states[p], events, cut[p]);
    }
    for (i, copy) in copies.iter().enumerate() {
        let message = &messages[copy.message];
        let sent = events[message.event].ordinal <= cut[copy.source];
        let received = copy.received.map_or(false, |e| events[e].ordinal <= cut[copy.destination]);
        if received && !sent { result.orphans.push(i); }
        if sent && !received {
            result.transit.push(i);
            result.money += message.amount;
        }
    }
    result
}
