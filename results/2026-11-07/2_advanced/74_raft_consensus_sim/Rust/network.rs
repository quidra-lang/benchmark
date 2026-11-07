use std::collections::BTreeMap;
use std::fs;
use crate::raft_node::Entry;
pub const TYPES: [&str;5] = ["RV","RVR","AE","AER","TN"];
#[derive(Clone)] pub enum Payload {
    Vote(usize,usize),
    VoteResponse(bool),
    Append {
        previous: usize,
        previous_term: usize,
        entries: Vec<Entry>,
        commit: usize
    },
    AppendResponse(bool,usize),
    TimeoutNow
}
#[derive(Clone)] pub struct Message {
    pub source: usize,
    pub destination: usize,
    pub term: usize,
    pub payload: Payload
}
impl Message {
    pub fn kind(&self) -> usize {
        match self.payload {
            Payload::Vote(..) => 0,Payload::VoteResponse(..) => 1,Payload::Append {
                ..
            }
            => 2,Payload::AppendResponse(..) => 3,Payload::TimeoutNow => 4
        }
    }
}
struct Drop {
    source: Option<usize>,
    destination: Option<usize>,
    kind: Option<usize>,
    first: usize,
    last: usize
}
pub struct Network {
    pub delays: Vec<Vec<usize>>,
    pub losses: Vec<Vec<usize>>,
    passes: Vec<Vec<usize>>,
    drops: Vec<Drop>,
    groups: Vec<usize>,
    pub queue: BTreeMap<usize,Vec<(usize,Message)>>,
    serial: usize,
    pub by_type: [[usize;6];5],
    pub by_link: Vec<Vec<[usize;6]>>
}
impl Network {
    pub fn read(n: usize) -> Self {
        let source = fs::read_to_string("input/network.txt").unwrap();
        let lines: Vec<Vec<_>> = source.lines().map(|l| l.split_whitespace().collect()).collect();
        let delay = lines[0][1].parse().unwrap();
        let mut delays = vec![vec![delay;n];n];
        let mut losses = vec![vec![0;n];n];
        let mut drops = Vec::new();
        for w in &lines[1..] {
            let parse = |s: &str| if s == "*" {
                None
            } else {
                Some(s.parse::<usize>().unwrap()-1)
            };
            let source = parse(w[1]);
            let destination = parse(w[2]);
            if w[0] == "DROP" {
                drops.push(Drop {
                    source,
                    destination,
                    kind: TYPES.iter().position(|&t| t == w[3]),
                    first: w[4].parse().unwrap(),
                    last: w[5].parse().unwrap()
                });
            } else {
                let value = w[3].parse().unwrap();
                for a in 0..n {
                    for b in 0..n {
                        if a != b && source.map_or(true,|s| s == a) && destination.map_or(true,|d| d == b) {
                            if w[0] == "DELAY" {
                                delays[a][b] = value;
                            } else {
                                losses[a][b] = value;
                            }
                        }
                    }
                }
            }
        }
        Self {
            delays,
            losses,
            passes: vec![vec![0;n];n],
            drops,
            groups: vec![0;n],
            queue: BTreeMap::new(),
            serial: 0,
            by_type: [[0;6];5],
            by_link: vec![vec![[0;6];n];n]
        }
    }
    pub fn partition(&mut self, groups: &[Vec<usize>]) {
        for (group,nodes) in groups.iter().enumerate() {
            for &node in nodes {
                self.groups[node] = group;
            }
        }
    }
    pub fn heal(&mut self) {
        self.groups.fill(0);
    }
    fn count(&mut self, message: &Message, event: usize) {
        self.by_type[message.kind()][event] += 1;
        self.by_link[message.source][message.destination][event] += 1;
    }
    pub fn send(&mut self, time: usize, message: Message) {
        self.count(&message,0);
        let (a,b) = (message.source,message.destination);
        if self.groups[a] != self.groups[b] {
            self.count(&message,2);
        } else if self.drops.iter().any(|d| d.source.map_or(true,|s| s == a) && d.destination.map_or(true,|v| v == b) && d.kind.map_or(true,|k| k == message.kind()) && d.first <= time && time <= d.last) {
            self.count(&message,3);
        } else {
            self.passes[a][b] += 1;
            if self.losses[a][b] > 0 && self.passes[a][b]%self.losses[a][b] == 0 {
                self.count(&message,4);
            } else {
                self.serial += 1;
                self.queue.entry(time+self.delays[a][b]).or_default().push((self.serial,message));
            }
        }
    }
    pub fn arriving(&mut self, time: usize) -> Vec<Message> {
        let mut messages = self.queue.remove(&time).unwrap_or_default();
        messages.sort_by_key(|(serial,m)| (m.source,*serial));
        messages.into_iter().map(|(_,m)| m).collect()
    }
    pub fn deliver(&mut self, message: &Message, up: bool) -> bool {
        let reason = if !up {
            5
        } else if self.groups[message.source] != self.groups[message.destination] {
            2
        } else {
            1
        };
        self.count(message,reason);
        reason == 1
    }
    pub fn inflight(&self) -> [usize;5] {
        let mut counts = [0;5];
        for messages in self.queue.values() {
            for (_,message) in messages {
                counts[message.kind()] += 1;
            }
        }
        counts
    }
}
