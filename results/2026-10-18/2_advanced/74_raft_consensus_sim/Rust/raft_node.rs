use std::collections::{BTreeMap,BTreeSet};
pub const ROLES: [&str;3] = ["FOLLOWER","CANDIDATE","LEADER"];
#[derive(Clone,PartialEq,Eq)] pub struct Entry {
    pub term: usize,
    pub command: String,
    pub request: usize
}
pub struct Transfer {
    pub target: usize,
    pub sent: bool,
    pub deadline: usize
}
pub struct Node {
    pub term: usize,
    pub voted: Option<usize>,
    pub log: Vec<Entry>,
    pub up: bool,
    pub role: usize,
    pub commit: usize,
    pub applied: usize,
    pub store: BTreeMap<String,i64>,
    pub known: Option<usize>,
    pub votes: BTreeSet<usize>,
    pub deadline: Option<usize>,
    pub next: Vec<usize>,
    pub matched: Vec<usize>,
    pub heartbeat: Option<usize>,
    pub quorum: Option<usize>,
    pub heard: BTreeSet<usize>,
    pub transfer: Option<Transfer>,
    pub stats: [usize;9],
    pub election: Option<usize>
}
impl Node {
    pub fn new(n: usize) -> Self {
        Self {
            term: 0,
            voted: None,
            log: Vec::new(),
            up: true,
            role: 0,
            commit: 0,
            applied: 0,
            store: BTreeMap::new(),
            known: None,
            votes: BTreeSet::new(),
            deadline: None,
            next: vec![0;n],
            matched: vec![0;n],
            heartbeat: None,
            quorum: None,
            heard: BTreeSet::new(),
            transfer: None,
            stats: [0;9],
            election: None
        }
    }
    pub fn reset(&mut self) {
        self.role = 0;
        self.commit = 0;
        self.applied = 0;
        self.store.clear();
        self.known = None;
        self.votes.clear();
        self.deadline = None;
        self.next.fill(0);
        self.matched.fill(0);
        self.heartbeat = None;
        self.quorum = None;
        self.heard.clear();
        self.transfer = None;
        self.election = None;
    }
    pub fn length(&self) -> usize {
        self.log.len()
    }
    pub fn term_at(&self, index: usize) -> usize {
        if index == 0 {
            0
        } else {
            self.log[index-1].term
        }
    }
    pub fn last_term(&self) -> usize {
        self.term_at(self.length())
    }
    pub fn up_to_date(&self, index: usize, term: usize) -> bool {
        (term,index) >= (self.last_term(),self.length())
    }
}
pub fn apply(store: &mut BTreeMap<String,i64>, command: &str) -> String {
    let w: Vec<_> = command.split_whitespace().collect();
    match w[0] {
        "NOOP" => String::new(), "SET" => {
            store.insert(w[1].to_owned(),w[2].parse().unwrap());
            "ok".to_owned()
        }
        "ADD" => {
            let value = store.entry(w[1].to_owned()).or_insert(0);
            *value += w[2].parse::<i64>().unwrap();
            value.to_string()
        }
        "DEL" => if store.remove(w[1]).is_some() {
            "deleted".to_owned()
        } else {
            "missing".to_owned()
        }, _ => store.get(w[1]).map_or_else(|| "missing".to_owned(),i64::to_string)
    }
}
